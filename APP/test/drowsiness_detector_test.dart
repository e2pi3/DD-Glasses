import 'package:dd_glasses/drowsiness_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// 로그 프레임을 0.5초 간격으로 넣어주는 도우미. 감지가 잡힌 프레임만 모아서 돌려준다.
List<DrowsinessHit> feed(DrowsinessDetector detector, List<bool?> frames) {
  final start = DateTime(2026, 1, 1, 9);
  final hits = <DrowsinessHit>[];
  for (var i = 0; i < frames.length; i++) {
    final hit = detector.add(
      at: start.add(DrowsinessDetector.frameInterval * i),
      eyeClosed: frames[i],
    );
    if (hit != null) hits.add(hit);
  }
  return hits;
}

void main() {
  group('DrowsinessDetector', () {
    test('감김 4회 연속이면 감지 1건', () {
      final hits = feed(DrowsinessDetector(), [true, true, true, true]);

      expect(hits, hasLength(1));
      // 4프레임 = 1.5초 간격 + 첫 프레임 몫 0.5초.
      expect(hits.single.closedSeconds, 2.0);
      expect(hits.single.perclos, 1.0);
    });

    test('감김 3회까지는 감지하지 않는다', () {
      expect(feed(DrowsinessDetector(), [true, true, true]), isEmpty);
    });

    test('중간에 눈을 뜨면 연속 횟수가 처음부터 다시 센다', () {
      final frames = [true, true, true, false, true, true, true];

      expect(feed(DrowsinessDetector(), frames), isEmpty);
    });

    test('경고 중에는 감김이 이어져도 중복으로 세지 않는다', () {
      final hits = feed(DrowsinessDetector(), List.filled(20, true));

      expect(hits, hasLength(1));
    });

    test('눈을 4회 연속 떠서 회복한 뒤에는 다시 감지한다', () {
      final detector = DrowsinessDetector();
      final frames = [
        ...List.filled(4, true), // 감지 1건
        ...List.filled(4, false), // 회복
        ...List.filled(4, true), // 감지 1건
      ];

      final hits = feed(detector, frames);

      expect(hits, hasLength(2));
      expect(detector.isAlerting, isTrue);
    });

    test('눈을 3회만 뜨면 아직 회복이 아니다', () {
      final frames = [
        ...List.filled(4, true),
        ...List.filled(3, false),
        ...List.filled(4, true),
      ];

      expect(feed(DrowsinessDetector(), frames), hasLength(1));
    });

    test('눈 추론 값이 없는 프레임은 판정에 쓰지 않는다', () {
      // 카메라가 깨어나는 동안 값이 비어 들어와도 연속 횟수가 끊기지 않아야 한다.
      final frames = [true, true, null, true, true];

      expect(feed(DrowsinessDetector(), frames), hasLength(1));
    });

    test('PERCLOS는 최근 구간의 감김 비율이다', () {
      final frames = [
        ...List.filled(4, false),
        ...List.filled(4, true),
      ];

      final hits = feed(DrowsinessDetector(), frames);

      expect(hits.single.perclos, 0.5);
    });

    test('reset 뒤에는 이전 상태가 남지 않는다', () {
      final detector = DrowsinessDetector();
      feed(detector, List.filled(4, true));
      expect(detector.isAlerting, isTrue);

      detector.reset();

      expect(detector.isAlerting, isFalse);
      expect(feed(detector, List.filled(4, true)), hasLength(1));
    });
  });
}
