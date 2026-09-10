# CAU 가전 IoT 캡스톤디자인

## Team : SEE

# DD-Glasses

> **졸음 감지 및 피드백 보안경 개발**

## 📁 폴더 구조

```text
DD-Glasses/
├── ALGO/       # 내부 졸음 감지 알고리즘
├── APP/        # Flutter 기반 프론트엔드 앱
│   └── lib/src/  # BLE 통신 레이어 — 자세한 설명은 APP/lib/src/README.md
└── DEVICE/     # ESP32/Arduino 기반 디바이스 코드
    └── ble/    # GATT 통신 참고 구현 — 담당: 한지원. device.cpp는 건드리지 않음
```

## 🔗 BLE 통신

Flutter 앱 ↔ XIAO ESP32-S3(Sense) 사이 BLE 링크. 보드 없이도
`APP/assets/replay/`의 하드웨어팀 캡처 데이터로 전체 파이프라인을
개발·테스트할 수 있게 만들었습니다. 상세 설계, GATT 프로파일, 전송
신뢰성 정책은 `APP/lib/src/README.md`와 `DEVICE/ble/README.md`에
정리해뒀습니다. `feature/ble-communication` 브랜치에서 작업 중이며,
팀 리뷰 전까지 main에는 반영하지 않았습니다.
