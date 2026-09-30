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
constexpr int BTN_PIN    = D1;   // 확장 보드 사용자 버튼 (누르면 LOW)
constexpr int VIB_PIN    = D0;   // Grove 진동 모터(105020003), Grove A0/D0 포트 가정. 다른 포트면 수정
constexpr int BUZZER_PIN = A3;   // 확장 보드 부저 (패시브 -> 구형파로 울림)
// 카메라 XCLK 가 LEDC 채널0/타이머0 을 쓰므로 부저는 다른 채널(타이머)에 고정한다
constexpr uint8_t  BUZZER_LEDC_CH = 4;
constexpr uint32_t BUZZER_FREQ    = 2700;   // Hz
constexpr uint32_t DEBOUNCE_MS    = 30;

// 버튼을 누를 때마다 대기 -> 진동 -> 부저 -> 대기 순환
enum OutMode { MODE_IDLE = 0, MODE_VIBRATE, MODE_BUZZER, MODE_COUNT };
static int outMode = MODE_IDLE;
static const char* const OUT_MODE_NAME[] = {"대기", "진동", "부저"};

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
  pinMode(VIB_PIN, OUTPUT);
  digitalWrite(VIB_PIN, LOW);
  ledcAttachChannel(BUZZER_PIN, BUZZER_FREQ, 8, BUZZER_LEDC_CH);
  ledcWrite(BUZZER_PIN, 0);
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

void nextOutMode() {
  outMode = (outMode + 1) % MODE_COUNT;
  digitalWrite(VIB_PIN, outMode == MODE_VIBRATE ? HIGH : LOW);
  if (outMode != MODE_BUZZER) ledcWrite(BUZZER_PIN, 0);
  Serial.printf(">> 출력 모드: %s\n", OUT_MODE_NAME[outMode]);
}

// 부저 모드일 때 200ms 울림 / 300ms 쉼 반복
void updateOutputs() {
  if (outMode != MODE_BUZZER) return;
  bool on = (millis() % 500) < 200;
  ledcWrite(BUZZER_PIN, on ? 128 : 0);   // 50% 듀티 구형파
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

void setup() {
  Serial.begin(115200);
  delay(1000);

  if (!initCamera()) {
    Serial.println("카메라 초기화 실패");
    while (true) delay(1000);
  }
  if (!initModel()) {
    while (true) delay(1000);
  }
  initSensors();   // 실패해도 추론은 계속
  initOutputs();

  // 자동 노출이 수렴할 때까지 초기 프레임을 버림
  for (int i = 0; i < 10; ++i) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (fb) esp_camera_fb_return(fb);
    delay(100);
  }
  Serial.println("시작");
}

void loop() {
  static uint32_t next = millis();
  static uint32_t count = 0;
  static uint32_t closedStreak = 0;

  // 버튼/출력은 매 루프마다 확인 (500ms 주기와 무관하게 즉시 반응)
  if (buttonPressed()) nextOutMode();
  updateOutputs();

  if ((int32_t)(millis() - next) < 0) return;
  next += INTERVAL_MS;
  if ((int32_t)(millis() - next) > 0) next = millis() + INTERVAL_MS;  // 처리가 밀리면 재정렬

  // ---- 눈 추론
  bool eyeOk = false;
  float pClosed = 0.0f;
  uint32_t tPre = 0, tInf = 0;

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
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
  closedStreak = closed ? closedStreak + 1 : 0;

  // ---- 근접 센서
  int prox = vcnlOk ? (int)vcnl.getProximity() : -1;

  // ---- 가속도/자이로
  sensors_event_t a, g, temp;
  if (mpuOk) mpu.getEvent(&a, &g, &temp);

  // ---- 출력 (한 줄)
  Serial.printf("[%5lu] ", (unsigned long)++count);
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
  Serial.printf(" | 출력=%s | 전처리 %lums 추론 %lums\n",
                OUT_MODE_NAME[outMode], (unsigned long)tPre, (unsigned long)tInf);
}