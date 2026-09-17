#include <Wire.h>
#include <Adafruit_VCNL4040.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ===== BLE GATT 규약 (APP/lib/ble_protocol.dart 와 반드시 동일하게 유지) =====
#define BLE_DEVICE_NAME          "DD-GLASSES"
#define PROXIMITY_SERVICE_UUID   "8e7f0003-6c1b-4d3a-9f2e-3dd6a5e0b001"
#define PROXIMITY_CHAR_UUID      "8e7f0004-6c1b-4d3a-9f2e-3dd6a5e0b001"

#define PROXIMITY_INTERVAL_MS    500   // IR 근접센서 값 전송 주기

// ===== BLE 관련 전역 변수 =====
BLECharacteristic* proximity_char = nullptr;
bool ble_connected = false;
unsigned long last_proximity_ms = 0;

// ===== VCNL4040 IR 근접센서 =====
Adafruit_VCNL4040 vcnl4040;

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

// ---------- BLE GATT 서버 초기화 ----------
void setup_ble() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new GlassesServerCallbacks());

  // IR 근접센서(VCNL4040) proximity 원시값 서비스. 페이로드: uint16 (little-endian).
  BLEService* proximity_service = server->createService(PROXIMITY_SERVICE_UUID);
  proximity_char = proximity_service->createCharacteristic(
      PROXIMITY_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  proximity_char->addDescriptor(new BLE2902());
  uint8_t initial_value[2] = {0, 0};
  proximity_char->setValue(initial_value, sizeof(initial_value));
  proximity_service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(PROXIMITY_SERVICE_UUID);
  advertising->setScanResponse(true);  // 이름은 scan response 로 전송
  BLEDevice::startAdvertising();

  Serial.println("BLE 광고 시작: " BLE_DEVICE_NAME);
}

// ---------- VCNL4040 초기화 ----------
void setup_proximity_sensor() {
  Wire.begin();
  if (!vcnl4040.begin()) {
    Serial.println("VCNL4040 초기화 실패 (배선/I2C 주소 확인)");
    while (1) delay(1000);
  }
  Serial.println("VCNL4040 초기화 완료");
}

// ---------- proximity 값 읽어서 BLE로 전송 ----------
void publish_proximity() {
  uint16_t value = vcnl4040.getProximity();
  uint8_t payload[2] = {
      (uint8_t)(value & 0xFF),
      (uint8_t)((value >> 8) & 0xFF),
  };
  proximity_char->setValue(payload, sizeof(payload));
  if (ble_connected) proximity_char->notify();

  Serial.print("proximity: ");
  Serial.println(value);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  setup_proximity_sensor();
  setup_ble();
}

void loop() {
  unsigned long now = millis();
  if (now - last_proximity_ms >= PROXIMITY_INTERVAL_MS) {
    last_proximity_ms = now;
    publish_proximity();
  }
  delay(10);
}
