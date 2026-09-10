#include "esp_camera.h"
#include "open_closed_eye_int8.h"

#include <Chirale_TensorFlowLite.h>
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/schema/schema_generated.h"

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

// ===== 카메라 프레임 크기 (QVGA 기준) =====
#define CAM_WIDTH   320
#define CAM_HEIGHT  240
#define SQUARE_SIZE CAM_HEIGHT   // 회전+크롭 후 정사각형 한 변 길이 (240)

#define MODEL_INPUT_SIZE 32      // 모델 입력 32x32

// ===== 양자화 파라미터 (PC에서 확인한 실제 값) =====
const float INPUT_SCALE = 0.0022914265282452106f;
const int   INPUT_ZERO_POINT = 47;
const float OUTPUT_SCALE = 0.00390625f;
const int   OUTPUT_ZERO_POINT = -128;

// ===== 전역 버퍼 =====
static uint16_t rotated_square[SQUARE_SIZE * SQUARE_SIZE];  // RGB565

// ===== TFLite Micro 관련 전역 변수 =====
constexpr int kTensorArenaSize = 40 * 1024;  // 부족하면 AllocateTensors 실패 메시지 보고 늘릴 것
static uint8_t tensor_arena[kTensorArenaSize];


const tflite::Model* model = nullptr;
tflite::MicroInterpreter* interpreter = nullptr;
TfLiteTensor* input_tensor = nullptr;
TfLiteTensor* output_tensor = nullptr;

// 모델이 실제로 쓰는 연산자들 (onnx2tf 변환 로그 기준: Conv, MaxPool, Relu, Exp, ReduceSum, Div)
// 인터프리터 초기화 시 "Didn't find op XXX" 에러가 나면 여기에 해당 Add함수를 추가해야 함
tflite::AllOpsResolver resolver;


// ---------- RGB565 회전(시계방향 90도) + 정사각형 크롭 ----------
// 원본 아랫부분(세로 240을 넘는 가로 여유분)은 애초에 계산 안 해서 자동으로 버려짐
void rotate90cw_and_crop_square(const uint16_t* src, int srcW, int srcH, uint16_t* dst, int squareSize) {
  for (int y = 0; y < srcH; y++) {
    for (int x = 0; x < squareSize; x++) {
      int new_x = srcH - 1 - y;
      int new_y = x;
      dst[new_y * srcH + new_x] = src[y * srcW + x];
    }
  }
}

// ---------- RGB565 -> 8bit BGR 채널 분리 ----------
void rgb565_to_bgr888(uint16_t pixel, uint8_t* b, uint8_t* g, uint8_t* r) {
  uint8_t r5 = (pixel >> 11) & 0x1F;
  uint8_t g6 = (pixel >> 5) & 0x3F;
  uint8_t b5 = pixel & 0x1F;
  *r = (r5 * 255) / 31;
  *g = (g6 * 255) / 63;
  *b = (b5 * 255) / 31;
}

// ---------- 정사각형(240x240) RGB565 -> 32x32 int8 (BGR, 양자화 완료) ----------
void preprocess_to_model_input(const uint16_t* squareImg, int squareSize, int8_t* outInt8) {
  for (int oy = 0; oy < MODEL_INPUT_SIZE; oy++) {
    for (int ox = 0; ox < MODEL_INPUT_SIZE; ox++) {
      int srcX = ox * squareSize / MODEL_INPUT_SIZE;
      int srcY = oy * squareSize / MODEL_INPUT_SIZE;
      uint16_t pixel = squareImg[srcY * squareSize + srcX];

      uint8_t b, g, r;
      rgb565_to_bgr888(pixel, &b, &g, &r);

      uint8_t channels[3] = { b, g, r };
      int outIdx = (oy * MODEL_INPUT_SIZE + ox) * 3;

      for (int c = 0; c < 3; c++) {
        float normalized = ((float)channels[c] - 127.0f) / 255.0f;
        int q = (int)round(normalized / INPUT_SCALE) + INPUT_ZERO_POINT;
        if (q < -128) q = -128;
        if (q > 127) q = 127;
        outInt8[outIdx + c] = (int8_t)q;
      }
    }
  }
}

// ---------- TFLite Micro 초기화 ----------
void setup_model() {
  model = tflite::GetModel(open_closed_eye_int8);
  if (model->version() != TFLITE_SCHEMA_VERSION) {
    Serial.println("모델 스키마 버전이 안 맞습니다.");
    while (1) delay(1000);
  }

  static tflite::MicroInterpreter static_interpreter(
      model, resolver, tensor_arena, kTensorArenaSize);
  interpreter = &static_interpreter;

  TfLiteStatus allocate_status = interpreter->AllocateTensors();
  if (allocate_status != kTfLiteOk) {
    Serial.println("AllocateTensors 실패! kTensorArenaSize를 늘려보세요.");
    while (1) delay(1000);
  }

  input_tensor = interpreter->input(0);
  output_tensor = interpreter->output(0);

  Serial.println("모델 초기화 완료");
}

// ---------- 카메라 초기화 ----------
void setup_camera() {
  camera_config_t config;
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

  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size = FRAMESIZE_QVGA;
  config.fb_count = psramFound() ? 2 : 1;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("카메라 초기화 실패");
    while (1) delay(1000);
  }

  sensor_t *s = esp_camera_sensor_get();
  if (s->id.PID == OV3660_PID) {
    s->set_vflip(s, 1);
  }

  Serial.println("카메라 초기화 완료");
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  setup_camera();
  setup_model();
}

void loop() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("촬영 실패");
    delay(5000);
    return;
  }

  uint16_t* raw_pixels = (uint16_t*)fb->buf;

  rotate90cw_and_crop_square(raw_pixels, CAM_WIDTH, CAM_HEIGHT, rotated_square, SQUARE_SIZE);

  esp_camera_fb_return(fb);

  preprocess_to_model_input(rotated_square, SQUARE_SIZE, input_tensor->data.int8);

  TfLiteStatus invoke_status = interpreter->Invoke();
  if (invoke_status != kTfLiteOk) {
    Serial.println("추론 실패");
    delay(5000);
    return;
  }

  int8_t closed_raw = output_tensor->data.int8[0];
  int8_t open_raw    = output_tensor->data.int8[1];

  float closed_prob = (closed_raw - OUTPUT_ZERO_POINT) * OUTPUT_SCALE;
  float open_prob    = (open_raw - OUTPUT_ZERO_POINT) * OUTPUT_SCALE;

  Serial.print("open: ");
  Serial.print(open_prob, 3);
  Serial.print(" / closed: ");
  Serial.print(closed_prob, 3);
  Serial.print(" -> 판정: ");
  Serial.println(closed_prob > open_prob ? "감음" : "뜸");

  delay(5000);
}