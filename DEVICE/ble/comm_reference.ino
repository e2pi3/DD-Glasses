// DD-Glasses — BLE 통신 레이어 참고 구현 (담당: 한지원).
//
// 이 파일은 device.cpp를 대신하지 않습니다. GATT 서비스 등록·프레임
// 인코딩·경보 재전송처럼 "통신" 부분만 담당하고, 센서 읽기와 위험도
// 판정 알고리즘(자이로+IR → PERCLOS/헤드저크/위험도)은 정윤서 파트인
// device.cpp에 그대로 남습니다. fillSyntheticFrame()이 지금 채우는
// 자리가 정확히 그 알고리즘이 나중에 값을 넣어줘야 하는 자리입니다.
//
// 통합 방법: device.cpp에서 이 파일의 세팅/전송 함수를 호출하거나,
// 이 스케치의 GATT 등록 부분을 device.cpp로 그대로 옮겨 붙이면 됩니다.
// 어느 쪽이든 protocol.h의 구조체와 UUID는 바꾸지 마세요 — Flutter 앱의
// APP/lib/src/protocol/과 바이트 단위로 맞춰뒀습니다 (gcc로 대조 완료).
//
// W1 목표: 센서 없이, 이 스케치 자체만으로 GATT 프로파일을 광고하고
// 합성 Live Metrics 프레임을 흘려서, Flutter 쪽 신뢰성 계층 전체를
// 먼저 검증합니다. IMU/IR이 붙으면 fillSyntheticFrame()만 실측값으로
// 바꾸면 되고 나머지는 그대로입니다.
//
// Verify with nRF Connect before touching the app:
//   1. AWAKE-G1 appears in the scan list
//   2. the 7E1C0001-... service and its seven characteristics are listed
//   3. enabling notifications on 7E1C0002-... produces 20 bytes at ~10 Hz
//   4. note the negotiated MTU
// If any step fails the problem is here, not in the app.
//
// Board:   Tools > Board > ESP32 Arduino > XIAO_ESP32S3
// Library: NimBLE-Arduino (h2zero) via Library Manager
//
// NimBLE rather than the bundled Bluedroid stack because it uses far less RAM
// and flash, and the camera frame buffer on the Sense board needs the room.

#include <NimBLEDevice.h>
#include "protocol.h"

// --- tuning -----------------------------------------------------------------
static uint16_t g_streamRateHz = 10;     // SET_STREAM_RATE changes this
static const uint16_t kCameraStreamRateHz = 2;

// Wi-Fi and BLE share one 2.4 GHz radio and one antenna on the ESP32-S3. While
// the camera is streaming frames to the edge server, BLE gets less air time,
// so the sketch drops its own rate rather than letting the app see jitter and
// loss it cannot explain.
static bool g_cameraActive = false;

// --- state ------------------------------------------------------------------
static NimBLECharacteristic *chLive   = nullptr;
static NimBLECharacteristic *chAlert  = nullptr;
static NimBLECharacteristic *chAck    = nullptr;
static NimBLECharacteristic *chCmd    = nullptr;
static NimBLECharacteristic *chCfg    = nullptr;
static NimBLECharacteristic *chStatus = nullptr;

static bool     g_connected      = false;
static uint8_t  g_seq            = 0;
static uint32_t g_lastFrameMs    = 0;
static uint32_t g_lastStatusMs   = 0;

static uint16_t g_alertId        = 0;
static uint16_t g_pendingAlertId = 0;
static uint8_t  g_alertAttempts  = 0;
static uint32_t g_alertSentMs    = 0;
static awake_alert_t g_pendingAlert;

// Bounded retry, the firmware half of AckedSender in the app.
static const uint32_t kAlertAckTimeoutMs = 2000;
static const uint8_t  kAlertMaxAttempts  = 3;

// TEST_MODE: emit a known sequence so the app can measure loss with no sensor
// involved. This is what produces the packet-loss figure for the report.
static uint32_t g_testRemaining = 0;

// Forward declarations. The Arduino preprocessor generates prototypes for
// free functions, but not reliably for ones first referenced from inside a
// class body, so declare them explicitly.
static void sendStatus();
static void raiseAlert(uint8_t level, uint8_t cause);
static void serviceAlertRetries();

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *server, NimBLEConnInfo &info) override {
    g_connected = true;
    Serial.printf("[ble] connected, mtu=%u\n", info.getMTU());
    // Ask for a fast connection interval while streaming. Android honours
    // 11.25-15 ms; iOS will not go below 15 ms.
    server->updateConnParams(info.getConnHandle(), 12, 24, 0, 400);
  }

  void onDisconnect(NimBLEServer *server, NimBLEConnInfo &info,
                    int reason) override {
    g_connected = false;
    Serial.printf("[ble] disconnected, reason=%d\n", reason);
    // Buffered logging would start here: keep sampling into PSRAM and upload
    // the backlog over the Log Chunk characteristic after reconnecting.
    NimBLEDevice::startAdvertising();
  }
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *characteristic,
               NimBLEConnInfo &info) override {
    const std::string value = characteristic->getValue();
    if (value.empty()) return;
    const uint8_t *bytes = (const uint8_t *)value.data();

    switch (bytes[0]) {
      case AWAKE_CMD_PING:
        Serial.println("[cmd] PING");
        sendStatus();  // the app times the round trip off this notification
        break;

      case AWAKE_CMD_STOP_FEEDBACK:
        Serial.println("[cmd] STOP_FEEDBACK");
        // stopHaptics(); stopVoice();
        break;

      case AWAKE_CMD_START_CALIBRATION:
        Serial.println("[cmd] START_CALIBRATION");
        break;

      case AWAKE_CMD_SET_STREAM_RATE:
        if (value.size() >= 2) {
          g_streamRateHz = constrain(bytes[1], 1, 20);
          Serial.printf("[cmd] stream rate -> %u Hz\n", g_streamRateHz);
        }
        break;

      case AWAKE_CMD_TEST_MODE:
        if (value.size() >= 3) {
          memcpy(&g_testRemaining, &bytes[1], sizeof(uint16_t));
          g_seq = 0;
          Serial.printf("[cmd] TEST_MODE %u packets\n",
                        (unsigned)g_testRemaining);
        }
        break;

      case AWAKE_CMD_REQUEST_LOG:
        Serial.println("[cmd] REQUEST_LOG (not implemented yet)");
        break;

      default:
        Serial.printf("[cmd] unknown opcode 0x%02X\n", bytes[0]);
        break;
    }
  }
};

class AckCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *characteristic,
               NimBLEConnInfo &info) override {
    const std::string value = characteristic->getValue();
    if (value.size() < sizeof(awake_alert_ack_t)) return;

    awake_alert_ack_t ack;
    memcpy(&ack, value.data(), sizeof(ack));
    Serial.printf("[ack] alert %u status %u\n", ack.alert_id, ack.status);

    if (ack.alert_id == g_pendingAlertId) {
      // status 0 means the app displayed it: stop retransmitting.
      g_pendingAlertId = 0;
      g_alertAttempts = 0;
      if (ack.status == AWAKE_ACK_CONFIRMED) {
        Serial.println("[ack] wearer confirmed — ending feedback");
        // stopHaptics(); stopVoice();
      }
    }
  }
};

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------
static void fillSyntheticFrame(awake_live_metrics_t *frame, uint16_t dtMs) {
  memset(frame, 0, sizeof(*frame));
  frame->seq = g_seq++;
  frame->flags = AWAKE_FLAG_WEARING | (g_cameraActive ? AWAKE_FLAG_CAMERA_ACTIVE : 0);
  frame->dt_ms = dtMs;

  // Slow sweep so the app has something visibly changing to render.
  const float phase = (millis() % 20000) / 20000.0f;
  frame->perclos_x100 = (uint16_t)(500 + 400 * sinf(phase * 6.2831853f));
  frame->pitch_x10    = (int16_t)(-50 * sinf(phase * 6.2831853f));
  frame->roll_x10     = 0;
  frame->blink_dur_ms = 250;
  frame->blink_rate   = 15;
  frame->eye_closure  = (uint8_t)(frame->perclos_x100 / 40);
  frame->proximity_raw = 70;  // stand-in for the raw IR count
  frame->risk_level   = 0;
  frame->risk_score   = (uint8_t)(frame->perclos_x100 / 100);
  frame->battery_pct  = 100;  // needs a divider on an ADC1 pin to be real
  awake_seal(frame);
}

static void sendStatus() {
  if (!g_connected || chStatus == nullptr) return;
  awake_status_t status;
  memset(&status, 0, sizeof(status));
  status.battery_pct = 100;
  status.fw_major = 0;
  status.fw_minor = 1;
  status.uptime_s = (uint16_t)(millis() / 1000);
  status.buffered_log_count = 0;
  chStatus->setValue((uint8_t *)&status, sizeof(status));
  chStatus->notify();
}

// Sends an alert with Indicate, and starts the bounded-retry timer.
//
// Indicate gives an ATT-level confirmation, which proves only that the bytes
// reached the phone's Bluetooth stack. The separate acknowledgement over
// AWAKE_CHAR_ALERT_ACK is what proves the alarm reached the wearer's screen.
// After kAlertMaxAttempts the firmware stops retrying and keeps driving the
// on-device haptics and voice on its own — a safety device must not depend on
// the phone being reachable.
static void raiseAlert(uint8_t level, uint8_t cause) {
  if (!g_connected || chAlert == nullptr) return;

  g_pendingAlert.alert_id  = ++g_alertId;
  g_pendingAlert.level     = level;
  g_pendingAlert.cause     = cause;
  g_pendingAlert.uptime_ms = millis();

  g_pendingAlertId = g_pendingAlert.alert_id;
  g_alertAttempts  = 1;
  g_alertSentMs    = millis();

  chAlert->setValue((uint8_t *)&g_pendingAlert, sizeof(g_pendingAlert));
  chAlert->indicate();
  Serial.printf("[alert] id=%u level=%u attempt 1\n",
                g_pendingAlert.alert_id, level);
}

static void serviceAlertRetries() {
  if (g_pendingAlertId == 0) return;
  if (millis() - g_alertSentMs < kAlertAckTimeoutMs) return;

  if (g_alertAttempts >= kAlertMaxAttempts) {
    Serial.printf("[alert] id=%u unacknowledged after %u attempts — "
                  "falling back to local feedback\n",
                  g_pendingAlertId, g_alertAttempts);
    g_pendingAlertId = 0;
    g_alertAttempts = 0;
    return;
  }

  g_alertAttempts++;
  g_alertSentMs = millis();
  chAlert->setValue((uint8_t *)&g_pendingAlert, sizeof(g_pendingAlert));
  chAlert->indicate();
  Serial.printf("[alert] id=%u attempt %u\n", g_pendingAlertId, g_alertAttempts);
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("[awake] booting");

  NimBLEDevice::init(AWAKE_DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  // Frames are 20 bytes so this is only an optimisation for log catch-up.
  NimBLEDevice::setMTU(247);

  NimBLEServer *server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService *service = server->createService(AWAKE_SERVICE_UUID);

  chLive = service->createCharacteristic(
      AWAKE_CHAR_LIVE_METRICS, NIMBLE_PROPERTY::NOTIFY);

  chAlert = service->createCharacteristic(
      AWAKE_CHAR_ALERT, NIMBLE_PROPERTY::INDICATE);

  chAck = service->createCharacteristic(
      AWAKE_CHAR_ALERT_ACK, NIMBLE_PROPERTY::WRITE);
  chAck->setCallbacks(new AckCallbacks());

  chCmd = service->createCharacteristic(
      AWAKE_CHAR_COMMAND, NIMBLE_PROPERTY::WRITE);
  chCmd->setCallbacks(new CommandCallbacks());

  chCfg = service->createCharacteristic(
      AWAKE_CHAR_CONFIG, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE);

  chStatus = service->createCharacteristic(
      AWAKE_CHAR_STATUS, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  service->start();

  NimBLEAdvertising *advertising = NimBLEDevice::getAdvertising();
  // Advertise the service UUID: the app filters on it, which is also how it
  // identifies the device on iOS, where no MAC address is exposed.
  advertising->addServiceUUID(AWAKE_SERVICE_UUID);
  advertising->setName(AWAKE_DEVICE_NAME);
  advertising->enableScanResponse(true);
  NimBLEDevice::startAdvertising();

  Serial.println("[awake] advertising as " AWAKE_DEVICE_NAME);
}

void loop() {
  const uint32_t now = millis();
  const uint16_t rateHz = g_cameraActive ? kCameraStreamRateHz : g_streamRateHz;
  const uint32_t intervalMs = 1000UL / (rateHz == 0 ? 1 : rateHz);

  if (g_connected && now - g_lastFrameMs >= intervalMs) {
    const uint16_t dt = (uint16_t)(now - g_lastFrameMs);
    g_lastFrameMs = now;

    awake_live_metrics_t frame;
    fillSyntheticFrame(&frame, dt);
    chLive->setValue((uint8_t *)&frame, sizeof(frame));
    chLive->notify();

    if (g_testRemaining > 0 && --g_testRemaining == 0) {
      Serial.println("[test] sequence complete");
    }
  }

  if (g_connected && now - g_lastStatusMs >= 1000) {
    g_lastStatusMs = now;
    sendStatus();
  }

  serviceAlertRetries();
  delay(2);
}
