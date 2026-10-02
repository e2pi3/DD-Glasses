import 'package:dd_glasses/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatHms', () {
    test('시:분:초를 두 자리씩 맞춘다', () {
      expect(formatHms(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
      expect(formatHms(Duration.zero), '00:00:00');
    });

    test('24시간을 넘어도 시간 자리가 늘어난다', () {
      expect(formatHms(const Duration(hours: 100)), '100:00:00');
    });

    test('음수는 0으로 본다', () {
      expect(formatHms(const Duration(seconds: -5)), '00:00:00');
    });
  });

  group('formatKorean', () {
    test('0인 단위는 뺀다', () {
      expect(formatKorean(const Duration(hours: 1, seconds: 5)), '1시간 5초');
      expect(formatKorean(const Duration(minutes: 3)), '3분');
      expect(
        formatKorean(const Duration(hours: 2, minutes: 30, seconds: 12)),
        '2시간 30분 12초',
      );
    });

    test('전부 0이면 0초', () {
      expect(formatKorean(Duration.zero), '0초');
    });
  });
}
