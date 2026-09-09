import 'package:dd_glasses/ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeqTracker', () {
    test('counts a clean run as no loss', () {
      final tracker = SeqTracker();
      for (var i = 0; i < 50; i++) {
        tracker.accept(i);
      }
      expect(tracker.received, 50);
      expect(tracker.lost, 0);
      expect(tracker.lossRate, 0);
    });

    test('counts the packets inside a gap', () {
      final tracker = SeqTracker();
      tracker.accept(10);
      final missing = tracker.accept(14);
      expect(missing, 3);
      expect(tracker.lost, 3);
      expect(tracker.lastGap, <int>[11, 12, 13]);
    });

    test('handles the 8-bit wrap without inventing 250 lost packets', () {
      final tracker = SeqTracker();
      tracker.accept(254);
      tracker.accept(255);
      final missing = tracker.accept(0);
      expect(missing, 0);
      expect(tracker.lost, 0);
    });

    test('counts loss that straddles the wrap', () {
      final tracker = SeqTracker();
      tracker.accept(253);
      final missing = tracker.accept(2);
      expect(missing, 4);
      expect(tracker.lastGap, <int>[254, 255, 0, 1]);
    });

    test('separates duplicates and reordering from loss', () {
      final tracker = SeqTracker();
      tracker.accept(10);
      tracker.accept(10);
      expect(tracker.duplicates, 1);
      expect(tracker.lost, 0);

      tracker.accept(5); // far behind: reordering, not 251 lost packets
      expect(tracker.outOfOrder, 1);
      expect(tracker.lost, 0);
    });

    test('reports a loss rate that matches the acceptance target', () {
      final tracker = SeqTracker();
      // 1000 packets, 3 dropped -> 0.3 %, under the 0.5 % target.
      var seq = 0;
      for (var i = 0; i < 1000; i++) {
        if (i == 100 || i == 400 || i == 700) {
          seq = (seq + 1) & 0xFF; // skip one
        }
        tracker.accept(seq);
        seq = (seq + 1) & 0xFF;
      }
      expect(tracker.lost, 3);
      expect(tracker.lossRate, lessThan(0.005));
    });
  });

  group('AckedSender — bounded retry', () {
    test('stops retrying as soon as the ack arrives', () async {
      var attempts = 0;
      final sender = AckedSender<int>(
        send: (key, attempt) async => attempts++,
        timeout: const Duration(milliseconds: 40),
        maxAttempts: 3,
      );

      final delivery = sender.deliver(7);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sender.ack(7);

      final report = await delivery;
      expect(report.isAcknowledged, isTrue);
      expect(attempts, 1);
      expect(sender.pendingCount, 0);
      sender.dispose();
    });

    test('retries then gives up after maxAttempts', () async {
      var attempts = 0;
      var gaveUpWith = 0;
      final sender = AckedSender<int>(
        send: (key, attempt) async => attempts++,
        timeout: const Duration(milliseconds: 20),
        maxAttempts: 3,
        onGiveUp: (key, count) => gaveUpWith = count,
      );

      final report = await sender.deliver(9);
      expect(report.outcome, DeliveryOutcome.gaveUp);
      expect(attempts, 3);
      expect(report.attempts, 3);
      expect(gaveUpWith, 3);
      sender.dispose();
    });

    test('a late ack after giving up is ignored, not a crash', () async {
      final sender = AckedSender<int>(
        send: (key, attempt) async {},
        timeout: const Duration(milliseconds: 15),
        maxAttempts: 2,
      );
      await sender.deliver(1);
      expect(() => sender.ack(1), returnsNormally);
      sender.dispose();
    });

    test('a failed write consumes an attempt rather than hanging', () async {
      var attempts = 0;
      final sender = AckedSender<int>(
        send: (key, attempt) async {
          attempts++;
          throw StateError('characteristic unavailable');
        },
        timeout: const Duration(milliseconds: 15),
        maxAttempts: 2,
      );
      final report = await sender.deliver(3);
      expect(report.outcome, DeliveryOutcome.gaveUp);
      expect(attempts, 2);
      sender.dispose();
    });

    test('delivering the same key twice joins the existing delivery', () async {
      var attempts = 0;
      final sender = AckedSender<int>(
        send: (key, attempt) async => attempts++,
        timeout: const Duration(milliseconds: 40),
        maxAttempts: 3,
      );
      final first = sender.deliver(5);
      final second = sender.deliver(5);
      expect(sender.pendingCount, 1);
      sender.ack(5);
      await Future.wait(<Future<DeliveryReport>>[first, second]);
      expect(attempts, 1);
      sender.dispose();
    });
  });

  group('LinkWatchdog', () {
    test('degrades and recovers as beats stop and resume', () async {
      final watchdog = LinkWatchdog(
        degradedAfter: const Duration(milliseconds: 30),
        unstableAfter: const Duration(milliseconds: 80),
        lostAfter: const Duration(milliseconds: 150),
        tick: const Duration(milliseconds: 10),
      );
      final seen = <LinkHealth>[];
      final sub = watchdog.healthStream.listen(seen.add);

      watchdog.start();
      watchdog.beat();
      expect(watchdog.health, LinkHealth.live);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(watchdog.health, LinkHealth.lost);
      expect(seen, contains(LinkHealth.degraded));
      expect(seen, contains(LinkHealth.unstable));

      watchdog.beat();
      expect(watchdog.health, LinkHealth.live);

      await sub.cancel();
      await watchdog.dispose();
    });
  });
}
