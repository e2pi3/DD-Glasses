import 'dart:io';
import 'dart:math' as math;

import 'package:dd_glasses/ble.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests against the eight captures the hardware team recorded
/// with the XIAO ESP32-S3 (`sensor_data_10sec_1..8.xlsx`, converted to CSV).
///
/// Captures 2 and 4 were recorded while the wearer moved their head; the rest
/// are stationary. That split is the ground truth these tests use.
void main() {
  const stationary = <int>[1, 3, 5, 6, 8];
  const moving = <int>[2, 4];

  List<SensorSample> loadCapture(int index) {
    final file = File('assets/replay/session$index.csv');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'missing ${file.path} — run tools/convert_captures.py first',
    );
    return ReplaySensorSource.fromCsv(
      file.readAsStringSync(),
      name: 'session$index',
    ).samplesList;
  }

  SensorCalibration calibrate(List<SensorSample> samples) {
    final window = math.min(12, samples.length ~/ 3);
    return SensorCalibration.fromWindow(samples.sublist(0, window));
  }

  group('captures load', () {
    test('all eight are present and non-trivial', () {
      for (var i = 1; i <= 8; i++) {
        final samples = loadCapture(i);
        expect(samples.length, greaterThan(20), reason: 'session$i');
        final span =
            samples.last.timestampMs - samples.first.timestampMs;
        expect(span, greaterThan(10000), reason: 'session$i spans >10s');
      }
    });

    test('sample rate is 2-4 Hz, far below what blink metrics need', () {
      for (var i = 1; i <= 8; i++) {
        final calibration = calibrate(loadCapture(i));
        expect(
          calibration.sampleRateHz,
          inInclusiveRange(1.5, 4.5),
          reason: 'session$i',
        );
        // The engine must admit this rather than report confident PERCLOS.
        final engine = MetricEngine(calibration: calibration);
        expect(engine.confidence, MetricConfidence.poseOnly, reason: 'session$i');
      }
    });
  });

  group('calibration rest detection', () {
    test('accepts the stationary captures', () {
      for (final i in stationary) {
        final calibration = calibrate(loadCapture(i));
        expect(
          calibration.isValid,
          isTrue,
          reason: 'session$i should calibrate cleanly, got ${calibration.rejects}',
        );
      }
    });

    test('rejects the captures recorded while the head was moving', () {
      for (final i in moving) {
        final calibration = calibrate(loadCapture(i));
        expect(
          calibration.isValid,
          isFalse,
          reason: 'session$i was recorded in motion and must be rejected',
        );
        expect(calibration.rejects, contains(CalibrationReject.moving));
      }
    });

    test('a rejected calibration falls back to the ceiling, not an inflated '
        'adaptive threshold', () {
      // This is the bug the rest check exists to prevent: fitting the jerk
      // threshold to moving data pushed it to ~25 rad/s, which then missed
      // every real jerk in the same recording.
      for (final i in moving) {
        final calibration = calibrate(loadCapture(i));
        expect(
          calibration.jerkThreshold,
          SensorCalibration.jerkThresholdCeiling,
          reason: 'session$i',
        );
      }
    });

    test('gyro bias lands near the value measured across all captures', () {
      for (final i in stationary) {
        final calibration = calibrate(loadCapture(i));
        expect(calibration.gyroBiasX, closeTo(-0.040, 0.02), reason: 'session$i');
        expect(calibration.gyroBiasY, closeTo(-0.058, 0.02), reason: 'session$i');
        expect(calibration.gyroBiasZ, closeTo(-0.050, 0.02), reason: 'session$i');
      }
    });

    test('accelerometer reads about 5 % high on every stationary capture', () {
      for (final i in stationary) {
        final calibration = calibrate(loadCapture(i));
        expect(
          calibration.accelScale,
          inInclusiveRange(0.90, 1.00),
          reason: 'session$i needs a scale correction below 1.0',
        );
      }
    });

    test('the IR open-eye baseline moves enough between sessions that it '
        'cannot be hard-coded', () {
      final baselines = <double>[];
      for (var i = 1; i <= 8; i++) {
        baselines.add(calibrate(loadCapture(i)).proximityOpenBaseline);
      }
      final spread =
          baselines.reduce(math.max) - baselines.reduce(math.min);
      expect(
        spread,
        greaterThan(20),
        reason: 'observed 60-92 counts; a fixed threshold would be wrong '
            'most sessions, so per-session calibration is mandatory',
      );
    });
  });

  group('head jerk detection', () {
    ({int jerks, double peakRate}) analyse(int index) {
      final samples = loadCapture(index);
      final engine = MetricEngine(calibration: calibrate(samples));
      var jerks = 0;
      var peak = 0.0;
      for (final sample in samples) {
        final metrics = engine.add(sample);
        if (metrics.isHeadJerk) jerks++;
        peak = math.max(peak, metrics.angularRate);
      }
      return (jerks: jerks, peakRate: peak);
    }

    test('finds movement in the two motion captures', () {
      for (final i in moving) {
        final result = analyse(i);
        expect(result.peakRate, greaterThan(2.0), reason: 'session$i');
        expect(
          result.jerks,
          greaterThan(0),
          reason: 'session$i peaked at ${result.peakRate} rad/s and must '
              'still be detected despite the rejected calibration',
        );
      }
    });

    test('finds the single transient in capture 7', () {
      final result = analyse(7);
      expect(result.peakRate, greaterThan(0.5));
      expect(result.jerks, 1);
    });

    test('reports nothing on the stationary captures', () {
      for (final i in stationary) {
        final result = analyse(i);
        expect(result.jerks, 0, reason: 'session$i must produce no false jerks');
        expect(result.peakRate, lessThan(0.2), reason: 'session$i');
      }
    });
  });

  group('metric engine window', () {
    test('withholds PERCLOS until the window has warmed up', () {
      final samples = loadCapture(1);
      final engine = MetricEngine(
        calibration: calibrate(samples),
        window: const Duration(seconds: 60),
      );
      final first = engine.add(samples.first);
      expect(first.windowIsWarm, isFalse);
      expect(
        first.perclos,
        isNull,
        reason: 'a single sample must not be reported as 100 % PERCLOS',
      );
    });

    test('head pose stays near neutral on stationary captures', () {
      for (final i in stationary) {
        final samples = loadCapture(i);
        final engine = MetricEngine(calibration: calibrate(samples));
        var swing = 0.0;
        for (final sample in samples) {
          swing = math.max(swing, engine.add(sample).pitchDeg.abs());
        }
        expect(swing, lessThan(6.0), reason: 'session$i');
      }
    });

    test('head pose swings on the motion captures', () {
      for (final i in moving) {
        final samples = loadCapture(i);
        final engine = MetricEngine(calibration: calibrate(samples));
        var minPitch = double.infinity;
        var maxPitch = double.negativeInfinity;
        for (final sample in samples) {
          final pitch = engine.add(sample).pitchDeg;
          minPitch = math.min(minPitch, pitch);
          maxPitch = math.max(maxPitch, pitch);
        }
        expect(maxPitch - minPitch, greaterThan(15.0), reason: 'session$i');
      }
    });
  });

  group('end-to-end replay through the wire format', () {
    test('every capture produces decodable 20-byte frames in order', () async {
      for (var i = 1; i <= 8; i++) {
        final source = ReplaySensorSource.fromCsv(
          File('assets/replay/session$i.csv').readAsStringSync(),
          name: 'session$i',
          loop: false,
        );
        final pipeline = LocalMetricsPipeline(source: source);
        final frames = <LiveMetrics>[];
        final sub = pipeline.frames.listen(frames.add);

        source.pumpAll();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(frames, isNotEmpty, reason: 'session$i produced no frames');
        for (var n = 0; n < frames.length; n++) {
          expect(frames[n].seq, n & 0xFF, reason: 'session$i frame $n');
          expect(frames[n].riskLevel, inInclusiveRange(0, 3));
          expect(frames[n].riskScore, inInclusiveRange(0, 100));
        }

        await sub.cancel();
        await pipeline.dispose();
      }
    });

    test('a receiver sees zero loss on a clean replay', () async {
      final source = ReplaySensorSource.fromCsv(
        File('assets/replay/session7.csv').readAsStringSync(),
        name: 'session7',
        loop: false,
      );
      final pipeline = LocalMetricsPipeline(source: source);
      final tracker = SeqTracker();
      final sub = pipeline.frames.listen((frame) => tracker.accept(frame.seq));

      source.pumpAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(tracker.received, greaterThan(10));
      expect(tracker.lost, 0);
      expect(tracker.lossRate, 0);

      await sub.cancel();
      await pipeline.dispose();
    });
  });
}
