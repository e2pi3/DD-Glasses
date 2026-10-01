import 'package:dd_glasses/ble_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// 펌웨어 sendTelemetry 가 만드는 16바이트 프레임을 그대로 흉내낸다.
List<int> frame({
  int flags = 0,
  int closedPercent = 0,
  int proximity = 0,
  List<int> imu = const [0, 0, 0, 0, 0, 0],
}) {
  final bytes = List<int>.filled(SensorFrame.length, 0);
  bytes[0] = flags;
  bytes[1] = closedPercent;
  bytes[2] = proximity & 0xFF;
  bytes[3] = (proximity >> 8) & 0xFF;
  for (var i = 0; i < 6; i++) {
    final v = imu[i] & 0xFFFF;
    bytes[4 + i * 2] = v & 0xFF;
    bytes[4 + i * 2 + 1] = (v >> 8) & 0xFF;
  }
  return bytes;
}

void main() {
  group('SensorFrame.parse', () {
    test('길이가 모자라면 버린다', () {
      expect(SensorFrame.parse(List.filled(SensorFrame.length - 1, 0)), isNull);
    });

    test('유효 비트가 없으면 센서 값이 모두 비어 있다', () {
      final f = SensorFrame.parse(frame())!;

      expect(f.eyeClosed, isNull);
      expect(f.closedProbability, isNull);
      expect(f.proximity, isNull);
      expect(f.accel, isNull);
      expect(f.gyro, isNull);
      expect(f.worn, isFalse);
      expect(f.alerting, isFalse);
      expect(f.buttonReacted, isFalse);
    });

    test('눈 감김과 확률을 읽는다', () {
      // bit0=눈 유효, bit1=눈 감김
      final closed = SensorFrame.parse(frame(flags: 1 | 2, closedPercent: 87))!;
      final open = SensorFrame.parse(frame(flags: 1, closedPercent: 12))!;

      expect(closed.eyeClosed, isTrue);
      expect(closed.closedProbability, 0.87);
      expect(open.eyeClosed, isFalse);
      expect(open.closedProbability, 0.12);
    });

    test('착용 / 경고 / 버튼 반응 비트를 읽는다', () {
      final worn = SensorFrame.parse(frame(flags: 16))!;
      final alerting = SensorFrame.parse(frame(flags: 16 | 32))!;
      final reacted = SensorFrame.parse(frame(flags: 16 | 64))!;

      expect(worn.worn, isTrue);
      expect(worn.alerting, isFalse);
      expect(alerting.alerting, isTrue);
      expect(alerting.buttonReacted, isFalse);
      expect(reacted.buttonReacted, isTrue);
      expect(reacted.alerting, isFalse);
    });

    test('근접값은 uint16 로 읽는다', () {
      final f = SensorFrame.parse(frame(flags: 4, proximity: 1234))!;

      expect(f.proximity, 1234);
    });

    test('IMU 는 음수까지 단위를 맞춰 읽는다', () {
      // 펌웨어가 보내는 단위: 가속도 0.01 m/s², 각속도 mrad/s
      final f = SensorFrame.parse(
        frame(flags: 8, imu: [981, -50, 0, 1500, -250, 0]),
      )!;

      expect(f.accel, [9.81, -0.5, 0]);
      expect(f.gyro, [1.5, -0.25, 0]);
    });
  });
}
