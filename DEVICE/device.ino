#define sensor_t camera_sensor_t
#include "esp_camera.h"
#undef sensor_t

#include <Wire.h>
#include <Adafruit_VCNL4040.h>
#include <Adafruit_MPU6050.h>

#include <Chirale_TensorFlowLite.h>
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/schema/schema_generated.h"

#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "eye_model_data.h"

// ===== XIAO ESP32S3 Sense 카메라 핀 =====
#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM     10
#define SIOD_GPIO_NUM     40
#define SIOC_GPIO_NUM     39
#define Y9_GPIO_NUM       48
#define Y8_GPIO_NUM       11
#define Y7_GPIO_NUM       12
#define Y6_GPIO_NUM       14
#define Y5_GPIO_NUM       16
#define Y4_GPIO_NUM       18
#define Y3_GPIO_NUM       17
#define Y2_GPIO_NUM       15
#define VSYNC_GPIO_NUM    38
#define HREF_GPIO_NUM     47
#define PCLK_GPIO_NUM     13

// ===== 외부 센서 I2C (XIAO 기본: D4=GPIO5 SDA, D5=GPIO6 SCL). 배선이 다르면 수정 =====
constexpr int I2C_SDA = 5;
constexpr int I2C_SCL = 6;
constexpr uint32_t I2C_FREQ = 400000;

// ===== 확장 보드 입출력 =====
constexpr int VIB_PIN    = D0;   // Grove 진동 모터(105020003), Grove A0/D0 포트 가정. 다른 포트면 수정
constexpr int BUZZER_PIN = A3;   // 확장 보드 부저 (패시브 -> 구형파로 울림)
// 카메라 XCLK 가 LEDC 채널0/타이머0 을 쓰므로 부저는 다른 채널(타이머)에 고정한다
constexpr uint8_t  BUZZER_LEDC_CH = 4;
constexpr uint32_t BUZZER_FREQ    = 2700;   // Hz
constexpr int      BTN_PIN        = D1;     // 확장 보드 사용자 버튼 (누르면 LOW) — 경고에 "반응"하는 용도
constexpr uint32_t DEBOUNCE_MS    = 30;

// 진동 모터도 세기 조절을 위해 PWM 으로 구동 (카메라=채널0, 부저=채널4 와 겹치지 않게)
constexpr uint8_t  VIB_LEDC_CH = 6;
constexpr uint32_t VIB_FREQ    = 1000;   // Hz

// ===== 사용자 설정 (앱에서 변경, NVS 에 저장) =====
// 1~5 단계. 0(무음/꺼짐)은 경고를 못 듣는 사고를 막기 위해 허용하지 않는다.
constexpr uint8_t LEVEL_MIN = 1;
constexpr uint8_t LEVEL_MAX = 5;
constexpr uint8_t LEVEL_DEFAULT = 3;
// 단계별 PWM 듀티(8bit). 부저는 듀티 80 이상에서는 체감 음량이 거의 늘지 않아 6~80 구간을 5단계로 나눴다.
// 진동 모터는 너무 낮으면 기동하지 못해 하한을 둔다.
static const uint8_t BUZZ_DUTY[LEVEL_MAX + 1] = {0, 6, 12, 22, 42, 80};
static const uint8_t VIB_DUTY[LEVEL_MAX + 1]  = {0, 110, 140, 175, 215, 255};

static Preferences prefs;
static volatile uint8_t volumeLevel    = LEVEL_DEFAULT;
static volatile uint8_t vibrationLevel = LEVEL_DEFAULT;
static volatile bool    settingsDirty  = false;   // BLE 콜백에서 바뀐 값을 loop 에서 NVS 에 저장

// ===== 착용 판정 =====
// 근접센서(VCNL4040) 값이 임계값 이상으로 WEAR_CONFIRM_MS 동안 계속 유지되면 착용으로 본다.
// 착용 전에는 카메라를 꺼 두고(휴면), 착용이 확정되면 켜서 졸음 판정을 시작한다.
constexpr int      PROX_WEAR_THRESHOLD = 15;
constexpr uint32_t WEAR_CONFIRM_MS     = 2000;
static bool     worn          = false;
static bool     cameraOn      = false;
static bool     proxWasHigh   = false;
static uint32_t proxHighSince = 0;

// ===== 졸음 경고 =====
// 눈 감김이 CLOSED_TRIGGER 회 연속(0.5s x 4 = 2초)이면 진동을 0.75초 울림/0.75초 쉼으로 반복하고,
// 진동이 ALERT_VIB_ONLY_PULSES 번 울리는 동안 버튼 반응이 없으면 그 뒤부터 소리도 함께 울린다.
// 버튼을 누르면 경고를 멈추고 RESUME_DELAY_MS 뒤부터 다시 측정한다.
// 경고 중 눈 뜸이 OPEN_RECOVER 회 연속이면 버튼 없이도 경고를 멈추고 바로 다시 측정한다.
constexpr uint32_t CLOSED_TRIGGER        = 4;
constexpr uint32_t ALERT_PULSE_MS        = 750;
constexpr uint32_t ALERT_PERIOD_MS       = 1500;
constexpr uint32_t ALERT_VIB_ONLY_PULSES = 4;
constexpr uint32_t RESUME_DELAY_MS       = 1500;
constexpr uint32_t OPEN_RECOVER          = 4;
static uint32_t closedStreak = 0;
static uint32_t openStreak   = 0;
static bool     alertActive  = false;
static uint32_t alertStart   = 0;
static uint32_t resumeAt     = 0;

// 앱의 설정 화면에서 값을 바꿀 때 바로 확인할 수 있게 잠깐 울리는 미리보기
constexpr uint32_t PREVIEW_MS = 700;
enum PreviewType : uint8_t { PREVIEW_SOUND = 0, PREVIEW_VIBRATION = 1 };
static volatile bool    previewPending = false;
static volatile uint8_t previewReqType = 0;
static volatile uint8_t previewReqLevel = LEVEL_DEFAULT;
static uint32_t previewStart = 0;
static uint8_t  previewType  = 0;
static uint8_t  previewLevel = LEVEL_DEFAULT;
static bool     previewActive = false;

// ===== BLE (앱의 ble_protocol.dart 와 반드시 일치) =====
#define BLE_DEVICE_NAME          "DD-GLASSES"
#define UUID_TELEMETRY_SERVICE   "8e7f0001-6c1b-4d3a-9f2e-3dd6a5e0b001"
#define UUID_TELEMETRY_CHAR      "8e7f0002-6c1b-4d3a-9f2e-3dd6a5e0b001"   // notify
#define UUID_SETTINGS_SERVICE    "8e7f0003-6c1b-4d3a-9f2e-3dd6a5e0b001"
#define UUID_SETTINGS_CHAR       "8e7f0004-6c1b-4d3a-9f2e-3dd6a5e0b001"   // read / write : [음량, 진동]
#define UUID_PREVIEW_CHAR        "8e7f0005-6c1b-4d3a-9f2e-3dd6a5e0b001"   // write : [종류(0=소리,1=진동), 단계]

static BLEServer*         bleServer    = nullptr;
static BLECharacteristic* telemetryChr = nullptr;
static BLECharacteristic* settingsChr  = nullptr;
static volatile bool      bleConnected = false;

// ===== 전처리 설정 (eye_common.py 와 반드시 일치) =====
constexpr int CAM_W   = 320;   // QVGA
constexpr int CAM_H   = 240;
constexpr int CROP_X0 = 0;     // 좌측 240x240 크롭 (우측 80px 제거)
constexpr int CROP    = 240;
constexpr int POOL    = 3;     // 3x3 box 평균
constexpr int IMG     = CROP / POOL;  // 80

// ===== 판정 설정 =====
constexpr float    CLOSED_THRESHOLD = 0.4f;   // 감은 눈 확률 임계값
constexpr uint32_t INTERVAL_MS      = 500;    // 촬영/추론/센서 공통 주기

// ===== TFLite Micro =====
constexpr int kArenaSize = 64 * 1024;
alignas(16) static uint8_t tensor_arena[kArenaSize];
static tflite::MicroInterpreter* interpreter = nullptr;
static TfLiteTensor* input  = nullptr;
static TfLiteTensor* output = nullptr;

static uint16_t pooled[IMG * IMG];   // 3x3 합 (0..2295)

// ===== 외부 센서 =====
static Adafruit_VCNL4040 vcnl;
static Adafruit_MPU6050  mpu;
static bool vcnlOk = false;
static bool mpuOk  = false;

// 모델 입력(80x80 흑백, 전체 시야 320x240 축소본의 좌측 240x240)에 맞춘 카메라 설정
bool initCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk  = XCLK_GPIO_NUM;
  config.pin_pclk  = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href  = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn  = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;

  // 모델은 흑백(휘도)만 사용 -> 센서가 Y 채널만 출력하게 해서 JPEG 디코딩/색 변환을 없앤다
  config.pixel_format = PIXFORMAT_GRAYSCALE;
  // 320x240 은 학습 전처리의 중간 해상도와 같고, 240/3 = 80 으로 정수 배 평균이 가능하다
  config.frame_size   = FRAMESIZE_QVGA;
  // 76.8KB 프레임 2장을 PSRAM 에 두고 항상 최신 프레임을 받는다
  config.fb_count     = 2;
  config.fb_location  = CAMERA_FB_IN_PSRAM;
  config.grab_mode    = CAMERA_GRAB_LATEST;

  if (!psramFound()) {
    Serial.println("PSRAM 없음 - Tools > PSRAM > OPI PSRAM 확인");
    return false;
  }
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("esp_camera_init 실패: 0x%x (%s)\n", err, esp_err_to_name(err));
    return false;
  }

  camera_sensor_t* s = esp_camera_sensor_get();
  Serial.printf("센서 PID: 0x%x\n", s->id.PID);
  // 센서마다 지원하지 않는 설정이 있어 함수가 있을 때만 호출
  #define SENSOR_SET(fn, v) do { if (s->fn) s->fn(s, v); } while (0)

  // 방향: 학습 이미지와 같은 방향이어야 한다(좌측 크롭이 눈 위치를 전제로 함).
  // 학습 이미지는 OV3660 일 때만 vflip 한 상태로 촬영됐다.
  SENSOR_SET(set_vflip, s->id.PID == OV3660_PID ? 1 : 0);
  SENSOR_SET(set_hmirror, 0);

  // 축소 방식: 센서 DSP 다운스케일(DCW) 사용 -> 전체 시야를 축소(학습 시 resize 와 동일).
  SENSOR_SET(set_dcw, 1);

  // 밝기: 입력마다 min-max 정규화를 하므로 절대 밝기는 무관하다.
  // 노이즈 특성이 학습 데이터와 달라지지 않도록 나머지 값은 기본값 유지.
  SENSOR_SET(set_exposure_ctrl, 1);
  SENSOR_SET(set_gain_ctrl, 1);
  SENSOR_SET(set_brightness, 0);
  SENSOR_SET(set_contrast, 0);

  // 감마/렌즈 보정/불량 화소 보정: 학습 이미지도 기본 ISP 처리를 거쳤으므로 켠 상태 유지
  SENSOR_SET(set_raw_gma, 1);
  SENSOR_SET(set_lenc, 1);
  SENSOR_SET(set_bpc, 1);
  SENSOR_SET(set_wpc, 1);
  #undef SENSOR_SET
  return true;
}

bool initModel() {
  const tflite::Model* model = tflite::GetModel(g_eye_model);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    Serial.printf("모델 스키마 버전 불일치: %lu != %d\n", (unsigned long)model->version(), TFLITE_SCHEMA_VERSION);
    return false;
  }

  static tflite::MicroMutableOpResolver<5> resolver;
  resolver.AddConv2D();
  resolver.AddDepthwiseConv2D();
  resolver.AddMean();
  resolver.AddFullyConnected();
  resolver.AddSoftmax();

  static tflite::MicroInterpreter interp(model, resolver, tensor_arena, kArenaSize);
  interpreter = &interp;

  if (interpreter->AllocateTensors() != kTfLiteOk) {
    Serial.println("AllocateTensors 실패 - kArenaSize 를 늘려볼 것");
    return false;
  }
  input  = interpreter->input(0);
  output = interpreter->output(0);

  Serial.printf("모델 로드 완료: %u bytes, arena 사용 %u / %d bytes\n",
                g_eye_model_len, (unsigned)interpreter->arena_used_bytes(), kArenaSize);
  Serial.printf("입력 [%d,%d,%d,%d] scale=%.6f zp=%d / 출력 scale=%.6f zp=%d\n",
                input->dims->data[0], input->dims->data[1], input->dims->data[2], input->dims->data[3],
                input->params.scale, (int)input->params.zero_point,
                output->params.scale, (int)output->params.zero_point);
  return true;
}

// 외부 센서 초기화. 실패해도 추론은 계속한다.
void initSensors() {
  Wire.begin(I2C_SDA, I2C_SCL, I2C_FREQ);

  Serial.print("I2C 스캔:");
  for (uint8_t addr = 1; addr < 127; ++addr) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) Serial.printf(" 0x%02X", addr);
  }
  Serial.println("  (VCNL4040=0x60, MPU-6050=0x68 또는 0x69)");

  vcnlOk = vcnl.begin(VCNL4040_I2CADDR_DEFAULT, &Wire);
  if (vcnlOk) {
    vcnl.enableProximity(true);
    vcnl.enableAmbientLight(false);   // 근접값만 사용
    vcnl.enableWhiteLight(false);
  }
  Serial.printf("VCNL4040: %s\n", vcnlOk ? "OK" : "찾을 수 없음");

  mpuOk = mpu.begin(MPU6050_I2CADDR_DEFAULT, &Wire) || mpu.begin(0x69, &Wire);
  if (mpuOk) {
    mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }
  Serial.printf("MPU-6050: %s\n", mpuOk ? "OK" : "찾을 수 없음");
}

void initOutputs() {
  pinMode(BTN_PIN, INPUT_PULLUP);
  ledcAttachChannel(VIB_PIN, VIB_FREQ, 8, VIB_LEDC_CH);
  ledcWrite(VIB_PIN, 0);
  ledcAttachChannel(BUZZER_PIN, BUZZER_FREQ, 8, BUZZER_LEDC_CH);
  ledcWrite(BUZZER_PIN, 0);
}

// 저장된 설정을 읽어온다. 이 값이 기기의 "진실"이고 앱은 연결 때마다 읽어서 보여준다.
void loadSettings() {
  prefs.begin("dd", false);
  uint8_t v = prefs.getUChar("vol", LEVEL_DEFAULT);
  uint8_t b = prefs.getUChar("vib", LEVEL_DEFAULT);
  volumeLevel    = (v >= LEVEL_MIN && v <= LEVEL_MAX) ? v : LEVEL_DEFAULT;
  vibrationLevel = (b >= LEVEL_MIN && b <= LEVEL_MAX) ? b : LEVEL_DEFAULT;
  Serial.printf("설정 로드: 음량=%u 진동=%u\n", volumeLevel, vibrationLevel);
}

void saveSettingsIfDirty() {
  if (!settingsDirty) return;
  settingsDirty = false;
  prefs.putUChar("vol", volumeLevel);   // 값이 같으면 NVS 쓰기를 건너뛴다
  prefs.putUChar("vib", vibrationLevel);
  Serial.printf("설정 저장: 음량=%u 진동=%u\n", volumeLevel, vibrationLevel);
}

// ---- BLE 콜백 (BLE 태스크에서 실행되므로 loop 와 공유하는 값만 건드린다)
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    bleConnected = true;
    Serial.println("BLE 연결됨");
  }
  void onDisconnect(BLEServer*) override {
    bleConnected = false;
    Serial.println("BLE 연결 끊김 - 광고 재시작");
    BLEDevice::startAdvertising();
  }
};

class SettingsCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    if (c->getLength() < 2) return;
    const uint8_t* d = c->getData();
    if (d[0] < LEVEL_MIN || d[0] > LEVEL_MAX || d[1] < LEVEL_MIN || d[1] > LEVEL_MAX) return;
    volumeLevel    = d[0];
    vibrationLevel = d[1];
    settingsDirty  = true;
  }
};

class PreviewCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    if (c->getLength() < 2) return;
    const uint8_t* d = c->getData();
    if (d[0] > PREVIEW_VIBRATION || d[1] < LEVEL_MIN || d[1] > LEVEL_MAX) return;
    previewReqType  = d[0];
    previewReqLevel = d[1];
    previewPending  = true;
  }
};

void initBle() {
  BLEDevice::init(BLE_DEVICE_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  // 센서/추론 결과 (500ms 마다 notify)
  BLEService* telemetrySvc = bleServer->createService(UUID_TELEMETRY_SERVICE);
  telemetryChr = telemetrySvc->createCharacteristic(UUID_TELEMETRY_CHAR,
                                                    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  telemetryChr->addDescriptor(new BLE2902());
  telemetrySvc->start();

  // 설정 (읽기: 저장된 현재 값 / 쓰기: 변경 + 저장) 및 미리보기
  BLEService* settingsSvc = bleServer->createService(UUID_SETTINGS_SERVICE);
  settingsChr = settingsSvc->createCharacteristic(UUID_SETTINGS_CHAR,
                                                  BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  settingsChr->setCallbacks(new SettingsCallbacks());
  BLECharacteristic* previewChr = settingsSvc->createCharacteristic(UUID_PREVIEW_CHAR,
                                                                    BLECharacteristic::PROPERTY_WRITE);
  previewChr->setCallbacks(new PreviewCallbacks());
  settingsSvc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(UUID_TELEMETRY_SERVICE);
  adv->setScanResponse(true);   // 128bit UUID 가 광고 패킷을 거의 채우므로 이름은 스캔 응답으로
  BLEDevice::startAdvertising();
  Serial.println("BLE 광고 시작: " BLE_DEVICE_NAME);
}

// 현재 설정을 읽기 값으로 갱신 (앱이 언제 읽어도 최신값이 나오도록 loop 에서 매번 호출)
void refreshSettingsValue() {
  uint8_t v[2] = {volumeLevel, vibrationLevel};
  settingsChr->setValue(v, 2);
}

// 텔레메트리 프레임 (16바이트, 기본 MTU 23 에서도 한 패킷) — 앱 ble_protocol.dart 의 SensorFrame.parse 참고
//  [0]    flags  bit0=눈 유효, bit1=눈 감김, bit2=근접 유효, bit3=IMU 유효, bit4=착용 중
//  [1]    감음 확률 % (0~100)
//  [2:4]  근접 raw uint16 LE
//  [4:16] IMU int16 LE x6 : acc xyz (0.01 m/s2), gyro xyz (mrad/s)
void sendTelemetry(bool eyeOk, bool closed, float pClosed, bool proxOk, int prox,
                   bool imuOk, const sensors_event_t& a, const sensors_event_t& g, bool wornNow) {
  if (!bleConnected) return;
  uint8_t f[16] = {};
  f[0] = (eyeOk ? 1 : 0) | (closed ? 2 : 0) | (proxOk ? 4 : 0) | (imuOk ? 8 : 0) | (wornNow ? 16 : 0);
  if (eyeOk) f[1] = (uint8_t)constrain((int)(pClosed * 100.0f + 0.5f), 0, 100);
  if (proxOk) { f[2] = prox & 0xFF; f[3] = (prox >> 8) & 0xFF; }
  if (imuOk) {
    const float v[6] = {a.acceleration.x * 100.0f, a.acceleration.y * 100.0f, a.acceleration.z * 100.0f,
                        g.gyro.x * 1000.0f, g.gyro.y * 1000.0f, g.gyro.z * 1000.0f};
    for (int i = 0; i < 6; ++i) {
      int16_t s = (int16_t)constrain((int)lroundf(v[i]), -32768, 32767);
      f[4 + i * 2]     = s & 0xFF;
      f[4 + i * 2 + 1] = ((uint16_t)s >> 8) & 0xFF;
    }
  }
  telemetryChr->setValue(f, sizeof(f));
  telemetryChr->notify();
}

// 버튼이 새로 눌린 순간에만 true (채터링 제거)
bool buttonPressed() {
  static int      stable    = HIGH;
  static int      last      = HIGH;
  static uint32_t changedAt = 0;
  int r = digitalRead(BTN_PIN);
  if (r != last) {
    last = r;
    changedAt = millis();
  }
  if (millis() - changedAt >= DEBOUNCE_MS && r != stable) {
    stable = r;
    return stable == LOW;
  }
  return false;
}

void startAlert() {
  alertActive = true;
  alertStart  = millis();
  openStreak  = 0;
  Serial.println("!! 졸음 경고 시작");
}

void stopAlert(const char* why) {
  if (!alertActive) return;
  alertActive = false;
  Serial.printf("졸음 경고 종료 (%s)\n", why);
}

// 진동/부저 출력을 매 루프 갱신. 앱의 설정 미리보기가 졸음 경고보다 우선한다.
//  - 미리보기: 소리는 200ms 울림 x2, 진동은 700ms 연속
//  - 졸음 경고: 진동 0.75s 울림/0.75s 쉼 반복, 4번째 울림이 끝난 뒤부터 같은 박자로 소리도 함께
void updateOutputs() {
  uint32_t now = millis();
  if (previewPending) {
    previewPending = false;
    previewType    = previewReqType;
    previewLevel   = previewReqLevel;
    previewStart   = now;
    previewActive  = true;
  }
  if (previewActive && now - previewStart >= PREVIEW_MS) previewActive = false;

  uint8_t buzz = 0, vib = 0;
  if (previewActive) {
    if (previewType == PREVIEW_SOUND) {
      if (((now - previewStart) % 350) < 200) buzz = BUZZ_DUTY[previewLevel];
    } else {
      vib = VIB_DUTY[previewLevel];
    }
  } else if (alertActive) {
    uint32_t t = now - alertStart;
    if ((t % ALERT_PERIOD_MS) < ALERT_PULSE_MS) {
      vib = VIB_DUTY[vibrationLevel];
      if (t / ALERT_PERIOD_MS >= ALERT_VIB_ONLY_PULSES) buzz = BUZZ_DUTY[volumeLevel];
    }
  }
  ledcWrite(BUZZER_PIN, buzz);
  ledcWrite(VIB_PIN, vib);
}

// QVGA 흑백 프레임 -> 좌측 240x240 크롭 -> 3x3 평균 -> min-max -> int8 입력
// eye_common.py 의 crop_and_pool + minmax_stretch, train.py 의 int8 양자화와 같은 계산
void preprocess(const uint8_t* src) {
  uint16_t lo = 0xFFFF, hi = 0;
  for (int y = 0; y < IMG; ++y) {
    for (int x = 0; x < IMG; ++x) {
      uint16_t sum = 0;
      for (int dy = 0; dy < POOL; ++dy) {
        const uint8_t* row = src + (y * POOL + dy) * CAM_W + CROP_X0 + x * POOL;
        sum += row[0] + row[1] + row[2];
      }
      pooled[y * IMG + x] = sum;
      if (sum < lo) lo = sum;
      if (sum > hi) hi = sum;
    }
  }
  // 파이썬: (m - lo) / max(hi - lo, 1.0)  (m = 합/9) -> 합 단위로는 최소 범위 9
  uint32_t range = hi - lo;
  if (range < POOL * POOL) range = POOL * POOL;

  int8_t* dst = input->data.int8;
  for (int i = 0; i < IMG * IMG; ++i) {
    // round((s - lo) * 255 / range) - 128
    int32_t q = (int32_t)(((pooled[i] - lo) * 510u + range) / (2 * range)) - 128;
    dst[i] = (int8_t)(q > 127 ? 127 : q);
  }
}

// 카메라는 착용 중에만 켠다. PWDN 핀이 배선되어 있지 않아(-1) 드라이버를 내려 XCLK 를 끄는 방식으로 휴면시킨다.
bool cameraStart() {
  if (!initCamera()) {
    Serial.println("카메라 초기화 실패 - 다음 주기에 재시도");
    return false;
  }
  // 자동 노출이 수렴할 때까지 초기 프레임을 버림
  for (int i = 0; i < 10; ++i) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) esp_camera_fb_return(fb);
    delay(100);
  }
  Serial.println("카메라 켜짐");
  return true;
}

void cameraStop() {
  // OV3660: SYSTEM_CTROL0(0x3008) bit6 = software power down. 클럭을 끊기 전에 센서를 스탠바이로 내린다.
  // 다시 켤 때는 esp_camera_init 이 센서를 리셋하므로 따로 깨울 필요가 없다.
  camera_sensor_t* s = esp_camera_sensor_get();
  if (s && s->id.PID == OV3660_PID && s->set_reg) {
    s->set_reg(s, 0x3008, 0x40, 0x40);
    delay(10);
  }
  esp_camera_deinit();
  Serial.println("카메라 휴면");
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  if (!initModel()) {
    while (true) delay(1000);
  }
  initSensors();   // 실패해도 추론은 계속
  loadSettings();
  initOutputs();
  initBle();

  Serial.println("시작 - 착용 대기 (카메라 휴면)");
}

void loop() {
  static uint32_t next = millis();
  static uint32_t count = 0;

  // 버튼/출력은 매 루프마다 확인 (500ms 주기와 무관하게 즉시 반응)
  if (buttonPressed() && alertActive) {
    stopAlert("버튼 반응");
    closedStreak = 0;
    resumeAt = millis() + RESUME_DELAY_MS;
  }
  updateOutputs();
  saveSettingsIfDirty();
  refreshSettingsValue();

  if ((int32_t)(millis() - next) < 0) {
    // 다음 주기까지 CPU 를 양보한다. 미착용 중엔 반응성이 필요한 게 앱 미리보기뿐이라 길게 쉰다.
    delay(worn ? 2 : 20);
    return;
  }
  next += INTERVAL_MS;
  if ((int32_t)(millis() - next) > 0) next = millis() + INTERVAL_MS;  // 처리가 밀리면 재정렬

  // ---- 근접 센서 -> 착용 판정
  int prox = vcnlOk ? (int)vcnl.getProximity() : -1;
  uint32_t now = millis();
  if (vcnlOk && prox >= PROX_WEAR_THRESHOLD) {
    if (!proxWasHigh) { proxWasHigh = true; proxHighSince = now; }
    if (!worn && now - proxHighSince >= WEAR_CONFIRM_MS) {
      worn = true;
      Serial.println("착용 확정");
    }
  } else {
    proxWasHigh = false;
    if (worn) {
      worn = false;
      stopAlert("착용 해제");
      closedStreak = 0;
      Serial.println("착용 해제");
    }
  }
  if (!worn && cameraOn) { cameraStop(); cameraOn = false; }
  if (worn && !cameraOn) cameraOn = cameraStart();   // 실패하면 다음 주기에 재시도

  // ---- 눈 추론 (카메라가 켜져 있을 때만)
  bool eyeOk = false;
  float pClosed = 0.0f;
  uint32_t tPre = 0, tInf = 0;

  camera_fb_t* fb = cameraOn ? esp_camera_fb_get() : nullptr;
  if (!cameraOn) {
    // 휴면 중: 촬영/추론 없음
  } else if (!fb) {
    Serial.println("촬영 실패");
  } else if (fb->width != CAM_W || fb->height != CAM_H || fb->format != PIXFORMAT_GRAYSCALE) {
    Serial.printf("예상과 다른 프레임: %ux%u format=%d\n", fb->width, fb->height, fb->format);
    esp_camera_fb_return(fb);
  } else {
    uint32_t t0 = micros();
    preprocess(fb->buf);
    esp_camera_fb_return(fb);
    uint32_t t1 = micros();
    if (interpreter->Invoke() == kTfLiteOk) {
      pClosed = (output->data.int8[1] - output->params.zero_point) * output->params.scale;
      eyeOk = true;
    } else {
      Serial.println("추론 실패");
    }
    uint32_t t2 = micros();
    tPre = (t1 - t0) / 1000;
    tInf = (t2 - t1) / 1000;
  }
  bool closed = eyeOk && pClosed >= CLOSED_THRESHOLD;

  // ---- 졸음 판정: 연속 감김 횟수가 기준에 도달하면 경고. 경고 중/버튼 반응 직후 대기 중에는 세지 않는다.
  bool cooling = (int32_t)(millis() - resumeAt) < 0;
  if (alertActive) {
    // 경고 중에 눈이 OPEN_RECOVER 회 연속 떠 있으면 스스로 회복한 것으로 보고 경고를 멈춘다.
    openStreak = (eyeOk && !closed) ? openStreak + 1 : 0;
    closedStreak = 0;
    if (openStreak >= OPEN_RECOVER) stopAlert("눈 뜸 회복");
  } else if (!worn || cooling) {
    closedStreak = 0;
  } else {
    closedStreak = closed ? closedStreak + 1 : 0;
    if (closedStreak >= CLOSED_TRIGGER) startAlert();
  }

  // ---- 가속도/자이로
  sensors_event_t a, g, temp;
  if (mpuOk) mpu.getEvent(&a, &g, &temp);

  // ---- 앱으로 전송
  sendTelemetry(eyeOk, closed, pClosed, vcnlOk, prox, mpuOk, a, g, worn);

  // ---- 출력 (한 줄)
  Serial.printf("[%5lu] %s%s ", (unsigned long)++count, worn ? "착용" : "미착용", alertActive ? "/경고" : "");
  if (eyeOk) {
    Serial.printf("%s p=%.3f 연속=%2lu", closed ? "감김" : "뜸  ", pClosed, (unsigned long)closedStreak);
  } else {
    Serial.print("눈 --            ");
  }
  if (vcnlOk) Serial.printf(" | prox=%5d", prox);
  else        Serial.print(" | prox=  --");
  if (mpuOk) {
    Serial.printf(" | acc(m/s2)=%6.2f %6.2f %6.2f | gyro(rad/s)=%5.2f %5.2f %5.2f",
                  a.acceleration.x, a.acceleration.y, a.acceleration.z,
                  g.gyro.x, g.gyro.y, g.gyro.z);
  } else {
    Serial.print(" | mpu --");
  }
  Serial.printf(" | 전처리 %lums 추론 %lums\n", (unsigned long)tPre, (unsigned long)tInf);
}