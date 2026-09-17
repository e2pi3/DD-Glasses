#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ===== BLE GATT 규약 (APP/lib/ble_protocol.dart 와 반드시 동일하게 유지) =====
#define BLE_DEVICE_NAME          "DD-GLASSES"
#define BATTERY_SERVICE_UUID     BLEUUID((uint16_t)0x180F)
#define BATTERY_LEVEL_CHAR_UUID  BLEUUID((uint16_t)0x2A19)

#define BATTERY_INTERVAL_MS      30000   // 배터리 잔량 전송 주기

// ===== BLE 관련 전역 변수 =====
BLECharacteristic* battery_char = nullptr;
bool ble_connected = false;
uint8_t last_battery = 0xFF;
unsigned long last_battery_ms = 0;

class GlassesServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    ble_connected = true;
    Serial.println("BLE 연결됨");
  }
  void onDisconnect(BLEServer* server) override {
    ble_connected = false;
    Serial.println("BLE 연결 해제됨 -> 다시 광고 시작");
    BLEDevice::startAdvertising();
  }
};

// TODO(battery): XIAO ESP32S3는 배터리 전압 측정 회로가 기본 내장되어 있지 않다.
// 배터리 단자 -> 분압 저항 -> ADC 핀을 연결한 뒤 analogReadMilliVolts()로 측정해
// 퍼센트로 환산하도록 교체할 것. 지금은 전원 상태와 무관하게 100으로 고정.
uint8_t read_battery_percent() {
  return 100;
}

// ---------- BLE GATT 서버 초기화 ----------
void setup_ble() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new GlassesServerCallbacks());

  // 표준 배터리 서비스
  BLEService* battery_service = server->createService(BATTERY_SERVICE_UUID);
  battery_char = battery_service->createCharacteristic(
      BATTERY_LEVEL_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  battery_char->addDescriptor(new BLE2902());
  last_battery = read_battery_percent();
  battery_char->setValue(&last_battery, 1);
  battery_service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BATTERY_SERVICE_UUID);
  advertising->setScanResponse(true);  // 이름은 scan response 로 전송
  BLEDevice::startAdvertising();

  Serial.println("BLE 광고 시작: " BLE_DEVICE_NAME);
}

void publish_battery_if_due() {
  unsigned long now = millis();
  if (now - last_battery_ms < BATTERY_INTERVAL_MS) return;
  last_battery_ms = now;

  uint8_t level = read_battery_percent();
  if (level == last_battery) return;
  last_battery = level;
  battery_char->setValue(&last_battery, 1);
  if (ble_connected) battery_char->notify();
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  setup_ble();
}

void loop() {
  publish_battery_if_due();
  delay(1000);
}
