import 'dart:math' as math;

import 'calibration.dart';
import 'sensor_sample.dart';

/// How far the incoming stream can be trusted.
///
/// The hardware captures arrive at 2-4 Hz. A blink lasts 100-400 ms, so at
/// that rate blink duration quantises to whole sample periods and PERCLOS is
/// built from a handful of points. The engine reports this rather than
/// emitting numbers that look precise and are not.
enum MetricConfidence {
  /// >= 20 Hz. Blink duration and PERCLOS are meaningful.
  full,

  /// 8-20 Hz. PERCLOS usable, blink duration coarse.
  reduced,

  /// < 8 Hz. Head pose and jerk only; blink metrics are indicative at best.
  poseOnly,
}

/// Sample rate the IR channel needs before blink duration is trustworthy.
const double kBlinkCapableRateHz = 20.0;

/// One derived measurement set, produced for every incoming sample.
class DrowsinessMetrics {
  const DrowsinessMetrics({
    required this.timestampMs,
    required this.pitchDeg,
    required this.rollDeg,
    required this.angularRate,
    required this.isHeadJerk,
    required this.eyeClosure,
    required this.isEyeClosed,
    required this.closedDurationMs,
    required this.perclos,
    required this.blinkRatePerMin,
    required this.meanBlinkDurationMs,
    required this.confidence,
    required this.windowIsWarm,
  });

  final int timestampMs;

  /// Head pitch relative to the calibrated neutral pose. Negative means the
  /// head has dropped forward.
  final double pitchDeg;
  final double rollDeg;

  /// Bias-corrected angular rate magnitude, rad/s.
  final double angularRate;

  /// True on the leading edge of a movement above the jerk threshold.
  final bool isHeadJerk;

  /// 0.0 fully open, 1.0 fully closed.
  final double eyeClosure;
  final bool isEyeClosed;

  /// How long the eyes have been continuously closed, milliseconds.
  final int closedDurationMs;

  /// Fraction of the trailing window with the eyes closed, 0.0-1.0.
  /// Null until the window has warmed up — reporting 100 % off a single
  /// sample was a real bug found against capture 1.
  final double? perclos;

  final double? blinkRatePerMin;
  final double? meanBlinkDurationMs;

  final MetricConfidence confidence;
  final bool windowIsWarm;

  @override
  String toString() => 'DrowsinessMetrics(pitch: ${pitchDeg.toStringAsFixed(1)}, '
      'closure: ${eyeClosure.toStringAsFixed(2)}, '
      'perclos: ${perclos == null ? '-' : (perclos! * 100).toStringAsFixed(0) + '%'}, '
      'jerk: $isHeadJerk, confidence: ${confidence.name})';
}

class _ClosureSample {
  const _ClosureSample(this.timestampMs, this.closed);
  final int timestampMs;
  final bool closed;
}

class _Blink {
  const _Blink(this.endTimestampMs, this.durationMs);
  final int endTimestampMs;
  final int durationMs;
}

/// Turns raw samples into the drowsiness indicators from the project
/// proposal: PERCLOS, blink rate and duration, head pitch, and head jerk.
///
/// Stateless with respect to Bluetooth — it runs identically on replayed
/// spreadsheet data and on a live BLE stream, which is what makes the app
/// developable before the hardware link exists.
class MetricEngine {
  MetricEngine({
    required this.calibration,
    this.window = const Duration(seconds: 60),
    this.closureThresholdSigma = 2.5,
    this.warmUpFraction = 0.5,
  });

  /// Replaces the baselines after a fresh calibration; window state is kept.
  SensorCalibration calibration;

  /// Trailing window PERCLOS and blink rate are computed over.
  final Duration window;

  /// Eyes count as closed once the IR reading rises this many standard
  /// deviations above the open-eye baseline. Higher = fewer false closures.
  final double closureThresholdSigma;

  /// Fraction of [window] that must be filled before PERCLOS is reported.
  final double warmUpFraction;

  final List<_ClosureSample> _closureWindow = <_ClosureSample>[];
  final List<_Blink> _blinks = <_Blink>[];

  bool _eyesClosed = false;
  int _closureStartMs = 0;
  bool _jerkArmed = true;

  /// Latest metrics, or null before the first sample.
  DrowsinessMetrics? get latest => _latest;
  DrowsinessMetrics? _latest;

  MetricConfidence get confidence {
    final rate = calibration.sampleRateHz;
    if (rate >= kBlinkCapableRateHz) return MetricConfidence.full;
    if (rate >= 8.0) return MetricConfidence.reduced;
    return MetricConfidence.poseOnly;
  }

  void reset() {
    _closureWindow.clear();
    _blinks.clear();
    _eyesClosed = false;
    _closureStartMs = 0;
    _jerkArmed = true;
    _latest = null;
  }

  DrowsinessMetrics add(SensorSample sample) {
    final t = sample.timestampMs;

    // --- head pose -------------------------------------------------------
    final pitch =
        SensorCalibration.pitchDegOf(sample) - calibration.neutralPitchDeg;
    final roll =
        SensorCalibration.rollDegOf(sample) - calibration.neutralRollDeg;

    // --- angular rate and jerk edge --------------------------------------
    final dx = sample.gx - calibration.gyroBiasX;
    final dy = sample.gy - calibration.gyroBiasY;
    final dz = sample.gz - calibration.gyroBiasZ;
    final angularRate = math.sqrt(dx * dx + dy * dy + dz * dz);

    var isJerk = false;
    if (angularRate > calibration.jerkThreshold) {
      if (_jerkArmed) {
        isJerk = true;
        _jerkArmed = false;
      }
    } else {
      _jerkArmed = true;
    }

    // --- eye closure ------------------------------------------------------
    // Higher IR reading means more reflected light, which means the eyelid is
    // closed (the proposal's IR section). Confirm the polarity with the
    // hardware team before trusting the absolute direction.
    final excess = sample.proximity - calibration.proximityOpenBaseline;
    final closureSpan = calibration.proximityNoise * closureThresholdSigma * 2;
    final closure = closureSpan <= 0
        ? 0.0
        : (excess / closureSpan).clamp(0.0, 1.0).toDouble();
    final closed =
        excess > calibration.proximityNoise * closureThresholdSigma;

    if (closed && !_eyesClosed) {
      _eyesClosed = true;
      _closureStartMs = t;
    } else if (!closed && _eyesClosed) {
      _eyesClosed = false;
      _blinks.add(_Blink(t, t - _closureStartMs));
    }
    final closedDuration = _eyesClosed ? t - _closureStartMs : 0;

    // --- trailing window --------------------------------------------------
    _closureWindow.add(_ClosureSample(t, closed));
    final cutoff = t - window.inMilliseconds;
    while (_closureWindow.isNotEmpty &&
        _closureWindow.first.timestampMs < cutoff) {
      _closureWindow.removeAt(0);
    }
    while (_blinks.isNotEmpty && _blinks.first.endTimestampMs < cutoff) {
      _blinks.removeAt(0);
    }

    final spanMs =
        _closureWindow.last.timestampMs - _closureWindow.first.timestampMs;
    final warm = spanMs >= window.inMilliseconds * warmUpFraction &&
        _closureWindow.length >= 4;

    double? perclos;
    double? blinkRate;
    double? meanBlinkDuration;
    if (warm) {
      final closedCount = _closureWindow.where((c) => c.closed).length;
      perclos = closedCount / _closureWindow.length;
      final spanMinutes = spanMs / 60000.0;
      if (spanMinutes > 0) blinkRate = _blinks.length / spanMinutes;
      if (_blinks.isNotEmpty) {
        final total = _blinks.fold<int>(0, (sum, b) => sum + b.durationMs);
        meanBlinkDuration = total / _blinks.length;
      }
    }

    final metrics = DrowsinessMetrics(
      timestampMs: t,
      pitchDeg: pitch,
      rollDeg: roll,
      angularRate: angularRate,
      isHeadJerk: isJerk,
      eyeClosure: closure,
      isEyeClosed: closed,
      closedDurationMs: closedDuration,
      perclos: perclos,
      blinkRatePerMin: blinkRate,
      meanBlinkDurationMs: meanBlinkDuration,
      confidence: confidence,
      windowIsWarm: warm,
    );
    _latest = metrics;
    return metrics;
  }
}
