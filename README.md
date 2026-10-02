# 🏅**우 수 상** 


# DD-Glasses : 졸음 감지 및 피드백 보안경

> 가전 IoT 캡스톤디자인 경진대회 — Team SEE

- 보안경에 장착한 초소형 카메라로 착용자의 눈을 촬영하고, 기기 안에서 직접 동작하는 경량 CNN 모델이 눈의 뜸/감김을 판정  
- 졸음이 감지되면 진동과 부저로 즉시 경고하며, Flutter 앱과 BLE로 연동해 동작 제어와 설정 가능  
- 추론은 **On-device** 연산

<br>

## 폴더 구조

```text
DD-Glasses/
├── APP/        # Flutter 기반 프론트엔드 앱
├── DEVICE/     # ESP32/Arduino 기반 디바이스 코드
└── MODEL/      # 눈 상태 분류 CNN 학습 및 변환
    ├── eye_common.py   # 공통 전처리 (보드와 동일한 연산)
    ├── train.py        # 학습 -> int8 TFLite 변환 -> C 헤더 생성
    ├── cv.py           # 시간 블록 기반 5-fold 교차검증
    └── output/         # 학습 결과 (모델, 리포트 등)
```

<br>

## 주요 기능

- **On-device 눈 상태 분류** : ESP32-S3에서 TensorFlow Lite Micro로 int8 양자화 CNN을 500ms 주기로 실행
- **졸음 판정 및 피드백** : 눈 감김이 일정 시간 지속되면 진동 모터와 부저로 경고
- **보조 센서** : IMU(MPU-6050)로 고개 움직임, 근접 센서(VCNL4040)로 착용 상태 측정
- **앱 연동** : Flutter 앱에서 BLE로 기기 가동/정지, 음량·진동 세기·판정 기준 등 설정
- **보드 버튼** : 기기의 버튼으로 피드백 신호 정지

<br>

## 하드웨어
<img width="660" height="330" alt="DDG" src="https://github.com/user-attachments/assets/dc17d240-aaa8-4d75-b5d1-e33a78ba4e93" />  

| 구성 요소 | 모델 | 역할 |
|---|---|---|
| MCU | Seeed Studio XIAO ESP32S3 Sense | 메인 제어, CNN 추론, BLE |
| 카메라 | OV3660 | 눈 영상 촬영 |
| IR 센서 | VCNL4040 | 착용 상태 측정 |
| IMU | MPU-6050 | 고개 움직임(가속도/각속도) 측정 |
| 진동 모터 | Grove Vibration Motor (105020003) | 진동 피드백 |
| 확장 보드 | Seeed XIAO Expansion Board | 부저, 사용자 버튼 |
| 배터리 | 3.7V 2000mAh Li-Po | 전원 |


<br>

## 눈 상태 분류 모델

### - 데이터셋

보드의 카메라로 직접 촬영한 눈 근접 사진을 사용

| 클래스 | 설명 | 이미지 수 |
|---|---|---|
| `open` | 뜬 눈 | 431 |
| `closed` | 감은 눈 | 268 |
| **합계** |  | **699** |


### - 전처리


```text
카메라 QVGA(320x240) Grayscale
  -> 좌측 240x240 크롭 (카메라 위치상 눈이 프레임 한쪽으로 치우침)
  -> 3x3 Box 평균으로 80x80 축소 (정수 배 연산)
  -> 이미지별 Min-Max 정규화 (조명 변화 흡수)
  -> int8 입력 (값 - 128)
```


### - 모델 구조


| 레이어 | 출력 크기 |
|---|---|
| Input (Grayscale) | 80 x 80 x 1 |
| Conv 3x3, stride 2 | 40 x 40 x 16 |
| DS Block, stride 2 | 20 x 20 x 32 |
| DS Block, stride 2 | 10 x 10 x 64 |
| DS Block | 10 x 10 x 64 |
| DS Block, stride 2 | 5 x 5 x 128 |
| Global Average Pooling + Dropout | 128 |
| Dense + Softmax | 2 (open / closed) |

- 파라미터 수 : **18,754**
- 학습 : 클래스 가중치(불균형 보정), 기하·광학 증강(회전, 이동, 확대, 감마, 블러, 노이즈), Early Stopping
- 배포 : **int8 전정수 양자화** TFLite -> C 배열 헤더로 변환하여 펌웨어에 포함

### - 학습 지표
<img width="880" height="330" alt="history" src="https://github.com/user-attachments/assets/f0bdf622-b0f2-4af1-a0d0-cd9631e012fc" /> 

<br>  

### - 모델 성능  
<img width="727" height="505" alt="gradcam_test" src="https://github.com/user-attachments/assets/ecaa77e2-079d-4746-9865-914a35886624" />  

| 지표 | 결과 |
|---|---|
| 정확도 (Accuracy) | **98.0%** |
| 감은 눈 재현율 (Closed Recall) | **100%** |
| 감은 눈 정밀도 (Closed Precision) | 95.0% |
| 뜬 눈 재현율 (Open Recall) | 96.8% |

**Hold-out 테스트셋 (104장)**
| 모델 | 정확도 |
|---|---|
| Float32 | 99.0% |
| int8 양자화 (보드 탑재) | 99.0% |

- 모델 크기 : **약 37KB** (int8 TFLite)

<br>

