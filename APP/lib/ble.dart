/// BLE 통신 레이어 공개 API.
///
/// 담당: 한지원 (BLE/WiFi 통신). 계층 구조:
///
///   connect.dart / device.dart   (앱 전역 상태 — 팀 전체가 참조하는 자리)
///   src/data/                    AwakeBleClient(실제 무선) | LocalMetricsPipeline(재생/테스트용)
///   src/sensing/                 MetricEngine, RiskFusion, SensorCalibration
///                                 — 9/10 결정으로 연산은 보드로 이동했고, 지금은
///                                   ESP32 C 포팅의 기준이 되는 참조 구현
///   src/protocol/                20바이트 프레임, seq 유실 측정, 제한 재전송, 링크 워치독
///   src/core/                    CRC-8
///
/// src/ 아래는 전부 순수 Dart + flutter_blue_plus 정도만 의존해서
/// 하드웨어 없이도 test/에서 그대로 돌아간다.
library dd_glasses_ble;

export 'src/core/crc8.dart';

export 'src/protocol/acked_sender.dart';
export 'src/protocol/alert.dart';
export 'src/protocol/awake_uuids.dart';
export 'src/protocol/commands.dart';
export 'src/protocol/link_watchdog.dart';
export 'src/protocol/live_metrics.dart';
export 'src/protocol/seq_tracker.dart';

export 'src/sensing/calibration.dart';
export 'src/sensing/metric_engine.dart';
export 'src/sensing/risk_fusion.dart';
export 'src/sensing/sensor_sample.dart';

export 'src/data/awake_ble_client.dart';
export 'src/data/local_pipeline.dart';
export 'src/data/replay_sensor_source.dart';
export 'src/data/sensor_source.dart';
