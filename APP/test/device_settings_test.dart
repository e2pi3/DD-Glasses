import 'package:dd_glasses/ble_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceSettings', () {
    test('플래그 비트: 소리/진동/고개 떨굼을 각각 읽는다', () {
      final s = DeviceSettings.parse([3, 4, 0x05, 1, 2])!;

      expect(s.volume, 3);
      expect(s.vibration, 4);
      expect(s.soundEnabled, isTrue);
      expect(s.vibrationEnabled, isFalse);
      expect(s.headDropEnabled, isTrue);
      expect(s.vibrationPattern, 1);
      expect(s.soundPattern, 2);
      // 민감도 바이트가 없으면 보통
      expect(s.headDropSensitivity, 1);
    });

    test('고개 떨굼 민감도를 읽고 쓴다', () {
      final s = DeviceSettings.parse([3, 3, 0x07, 0, 0, 2])!;

      expect(s.headDropSensitivity, 2);
      expect(s.copyWith(headDropSensitivity: 0).toBytes()[5], 0);
      expect(s.toBytes().length, 6);
    });

    test('toBytes 는 parse 와 짝이 맞는다', () {
      const original = DeviceSettings(
        volume: 2,
        vibration: 5,
        soundEnabled: false,
        vibrationEnabled: true,
        vibrationPattern: 1,
        soundPattern: 2,
        headDropEnabled: false,
      );

      final restored = DeviceSettings.parse(original.toBytes())!;

      expect(restored.toBytes(), original.toBytes());
      expect(restored.headDropEnabled, isFalse);
    });

    test('고개 떨굼은 소리/진동과 별개로 켜고 끈다', () {
      final s = DeviceSettings.parse([3, 3, 0x03, 0, 0])!;

      expect(s.headDropEnabled, isFalse);
      expect(s.copyWith(headDropEnabled: true).toBytes()[2], 0x07);
    });

    test('2바이트 미만은 읽지 못한다', () {
      expect(DeviceSettings.parse([3]), isNull);
    });
  });
}
