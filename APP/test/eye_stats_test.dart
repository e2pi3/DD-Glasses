import 'package:dd_glasses/eye_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// 로그 프레임을 0.5초 간격으로 넣어준다.
EyeStats feed(List<bool?> frames) {
  final stats = EyeStats();
  final start = DateTime(2026, 1, 1, 9);
  for (var i = 0; i < frames.length; i++) {
    stats.add(at: start.add(EyeStats.frameInterval * i), eyeClosed: frames[i]);
  }
  return stats;
}

void main() {
  group('EyeStats 눈 감김 시간', () {
    test('감김 4프레임이면 2초', () {
      // 기기가 경고를 울리는 시점(감김 4회 연속)의 값과 같아야 한다.
      expect(feed(List.filled(4, true)).closedSeconds, 2.0);
    });

    test('감김 1프레임도 프레임 몫만큼 센다', () {
      expect(feed([true]).closedSeconds, 0.5);
    });

    test('눈을 뜨고 있으면 0', () {
      expect(feed([true, true, false]).closedSeconds, 0);
    });

    test('중간에 눈을 뜨면 처음부터 다시 센다', () {
      expect(feed([true, true, false, true]).closedSeconds, 0.5);
    });

    test('눈 추론 값이 없는 프레임은 연속을 끊지 않는다', () {
      // 카메라가 깨어나는 동안 값이 비어 들어오는 경우.
      expect(feed([true, true, null, true]).closedSeconds, 2.0);
    });
  });

  group('EyeStats PERCLOS', () {
    test('감김 비율을 낸다', () {
      expect(
        feed([...List.filled(4, false), ...List.filled(4, true)]).perclos,
        0.5,
      );
    });

    test('계속 감고 있으면 1', () {
      expect(feed(List.filled(4, true)).perclos, 1.0);
    });

    test('값이 없으면 0', () {
      expect(feed([]).perclos, 0);
      expect(feed([null]).perclos, 0);
    });

    test('계산 구간이 지난 프레임은 빠진다', () {
      final stats = EyeStats();
      final start = DateTime(2026, 1, 1, 9);
      // 구간(60초)보다 오래된 감김은 비율에서 빠지고, 최근 뜸 프레임만 남는다.
      stats.add(at: start, eyeClosed: true);
      stats.add(at: start.add(const Duration(seconds: 90)), eyeClosed: false);

      expect(stats.perclos, 0);
    });
  });

  test('reset 뒤에는 이전 값이 남지 않는다', () {
    final stats = feed(List.filled(4, true));

    stats.reset();

    expect(stats.closedSeconds, 0);
    expect(stats.perclos, 0);
  });
}
