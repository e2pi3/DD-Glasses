# BLE 통신 레이어 (담당: 한지원)

`connect.dart`/`device.dart`(앱 전역 상태, 팀 전체가 참조)가 이 폴더를 감싸서
씁니다. 아래는 이 폴더 자체의 구조와, 왜 이렇게 나눴는지입니다.

```
src/
  core/crc8.dart          CRC-8 (DEVICE/ble/protocol.h와 동일 구현, gcc로 대조 완료)
  protocol/                ← 신뢰성 계층
    awake_uuids.dart         GATT UUID
    live_metrics.dart        20바이트 프레임 인코더/디코더
    alert.dart                경보 + ACK 패킷
    commands.dart              명령 opcode, Status 패킷
    seq_tracker.dart          유실률 측정 (8비트 wrap 처리)
    acked_sender.dart          제한 재전송 (Bounded Retry)
    link_watchdog.dart        끊김 감지 (OS 콜백 불신, 직접 타이머)
  sensing/                 순수 Dart, 블루투스 무관 → 테스트 가능
    sensor_sample.dart        원시 샘플 (자이로 + IR)
    calibration.dart          세션별 기준값 + 정지 판정
    metric_engine.dart        PERCLOS·깜빡임·pitch·헤드저크
    risk_fusion.dart          0-3단계 융합 (히스테리시스 + 자동 상승)
  data/
    sensor_source.dart         추상 소스
    replay_sensor_source.dart  CSV 재생 (하드웨어 불필요)
    local_pipeline.dart        재생 → 지표 → 위험도 → 20바이트 프레임
    awake_ble_client.dart      flutter_blue_plus 클라이언트 + 연결 상태머신
```

`ble.dart`(이 폴더 밖, `lib/ble.dart`)가 공개 API 배럴입니다. `connect.dart`는
`AwakeBleClient` 하나만 가져다 쓰고, 나머지는 전부 그 안에 캡슐화돼 있습니다.

## 왜 `sensing/`이 여기 있는가 — 9/10 결정 이후의 역할

원래는 이 폴더가 온디바이스 알고리즘을 앱에서 직접 돌리는 코드였는데,
9/10 팀 회의에서 **연산은 보드에서, 폰은 표시·관리만** 하기로 정해졌습니다.
그래서 지금 `sensing/`의 역할이 바뀌었습니다 — 앱이 런타임에 이 코드로
위험도를 계산하는 게 아니라, **`DEVICE/ble/`에서 C로 포팅해야 할 알고리즘의
참조 구현**입니다.

- 적응형 임계값·세션별 캘리브레이션이 이미 Dart로 돌아가는 형태로 있고,
- 하드웨어팀 캡처 8개(`assets/replay/session1..8.csv`)에 대해
  `test/capture_replay_test.dart`로 동작이 고정돼 있으니,
- C로 옮긴 뒤 같은 캡처를 넣어 같은 결과가 나오는지 대조하면 됩니다.

`local_pipeline.dart` + `replay_sensor_source.dart`는 그래서 여전히
쓸모가 있습니다 — 보드/센서 없이 홈 화면을 실제 캡처 데이터로 돌려보는
용도, 그리고 회귀 테스트 픽스처.

## 캡처 데이터에서 나온 것 (하드웨어팀에 전달 필요)

| 발견 | 수치 | 코드 반영 |
|---|---|---|
| 샘플레이트가 느림 | 세션 1-6: 2 Hz, 7-8: 4 Hz | `MetricConfidence.poseOnly` — 20 Hz 미만이면 블린크 지표는 참고용 |
| 자이로 영점 오차 | 정지 시 `(-0.040, -0.058, -0.050)` rad/s | `SensorCalibration.defaultGyroBias*` |
| 가속도 스케일 오차 | 정지 시 \|a\| = 10.31 m/s² (+5.1%) | `defaultAccelScale = 0.950` |
| **IR 기준선이 세션마다 다름** | 눈 뜬 상태 60~92 카운트 | 하드코딩 불가 → `CalibrationCollector`로 세션별 수집 |

**가장 급한 것**: IR 샘플레이트를 최소 20 Hz로 올려야 눈 깜빡임 지속시간을
제대로 잴 수 있습니다. 지금 2~4 Hz(250~500ms 주기)로는 깜빡임(100~400ms)이
샘플 사이로 빠져나갑니다.

## "연결됨"의 정의

`AwakeLinkState`에 `connected`가 없습니다. GATT 연결은 서비스 탐색 실패,
구독 실패로 아무것도 보장하지 않기 때문입니다.

```
idle → scanning → connecting → discovering → subscribing → streaming
                       ↑                                        │
                       └──── 끊김 또는 무수신 (1·2·4·8·16s 백오프) ─┘
```

`connect.dart`의 `ConnectionStatus.deviceConnected`는 `streaming`
하나에만 대응합니다 — **첫 20바이트 프레임이 CRC까지 통과해 디코드된 시점**.
안드로이드는 연결이 끊겨도 콜백이 수 초~수십 초 늦게 오기 때문에,
`LinkWatchdog`이 OS를 안 믿고 마지막 패킷 수신 시각을 직접 잽니다.

## 신뢰성 정책 요약

| 데이터 | GATT 연산 | 기법 | 근거 |
|---|---|---|---|
| 실시간 지표 | Notify | 무확인 전송 + `SeqTracker` 유실률만 측정 | 4-10 Hz 스트림. 재전송은 오래된 값을 밀어넣는 해악 |
| 위험 경보 | Indicate | 제한 재전송 (2s × 최대 3회) | 놓치면 위험. 3회 실패 시 보드 단독 피드백 폴백 |
| 사용자 확인 / 명령 | Write w/ Rsp | 제한 재전송 | 도달 확인 필요 |

BLE 링크 계층이 이미 CRC+ARQ로 무한 재전송을 하기 때문에, 우리가 대비하는
유실은 "연결 자체가 끊김"과 "앱에 도달 못 함" 두 가지뿐입니다. 그리고 ATT는
미확인 요청을 동시에 하나만 허용해서 슬라이딩 윈도우/Go-Back-N은 GATT
레벨에서 아예 불가능합니다 — 그래서 Alert에 앱 레벨 ACK(`AlertAck`)를
따로 얹었습니다.

## 테스트

```
test/live_metrics_test.dart      20바이트 고정, 라운드트립, CRC 거부, 클램핑
test/reliability_test.dart       seq wrap/유실/중복, 제한 재전송, 워치독
test/capture_replay_test.dart    실제 캡처 8개 회귀 테스트
```

`flutter test`로 보드 없이 전부 통과합니다. `capture_replay_test.dart`가
방어하는 실제 버그 두 개:

1. **움직이는 중 캘리브레이션** — 캡처 2·4처럼 움직이면서 기준값을 잡으면
   헤드저크 임계값이 치솟아 같은 녹화 안의 진짜 움직임을 놓쳤습니다 →
   정지 판정(`CalibrationReject`) + 임계값 상한 추가.
2. **윈도우 워밍업** — 첫 샘플 하나로 PERCLOS를 계산해 100%가 찍혔습니다 →
   윈도우가 절반 찰 때까지 `null` 반환.

## 라이선스 주의

`flutter_blue_plus`는 비영리·교육 용도는 무료, 영리 목적은 별도 상용
라이선스가 필요합니다. 그래서 블루투스 API 호출은 `awake_ble_client.dart`
한 파일 안에만 있습니다 — 나중에 `flutter_reactive_ble`(BSD-3)로 바꿔야
하면 이 파일만 다시 쓰면 됩니다.
