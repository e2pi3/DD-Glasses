import 'dart:math' as math;

import 'sensor_sample.dart';

/// Why a calibration attempt was rejected. Shown to the user as an
/// instruction, not an error code.
enum CalibrationReject {
  /// The head was moving. Gyro spread exceeded the rest limit.
  moving,

  /// Linear acceleration on top of gravity — walking, or the glasses were
  /// being handled.
  unsteady,

  /// The IR reading was not settled; the glasses were probably being put on
  /// or taken off.
  proximityUnstable,

  /// Too few samples to fit a baseline.
  notEnoughSamples,
}

extension CalibrationRejectMessage on CalibrationReject {
  /// Text for the calibration screen.
  String get message {
    switch (this) {
      case CalibrationReject.moving:
        return '고개를 움직이지 말고 정면을 봐 주세요.';
      case CalibrationReject.unsteady:
        return '걷거나 흔들리는 상태에서는 기준값을 잡을 수 없습니다. 앉아서 다시 시도해 주세요.';
      case CalibrationReject.proximityUnstable:
        return '보안경을 바르게 착용한 뒤 다시 시도해 주세요.';
      case CalibrationReject.notEnoughSamples:
        return '측정 시간이 부족합니다. 조금 더 기다려 주세요.';
    }
  }
}

/// Per-session baselines. Nothing downstream may assume a fixed threshold:
/// across the eight hardware captures the IR open-eye level moved between
/// 60 and 92 counts, so a hard-coded value would be wrong most of the time.
class SensorCalibration {
  const SensorCalibration({
    required this.gyroBiasX,
    required this.gyroBiasY,
    required this.gyroBiasZ,
    required this.accelScale,
    required this.neutralPitchDeg,
    required this.neutralRollDeg,
    required this.jerkThreshold,
    required this.proximityOpenBaseline,
    required this.proximityNoise,
    required this.sampleIntervalMs,
    required this.rejects,
  });

  // --- Defaults measured from the hardware team's captures -----------------
  // Used before a calibration has run, and as sanity bounds afterwards.

  /// Median zero-rate offset across the five stationary captures, rad/s.
  static const double defaultGyroBiasX = -0.040;
  static const double defaultGyroBiasY = -0.058;
  static const double defaultGyroBiasZ = -0.050;

  /// The accelerometer reads about 5 % high: |a| at rest averaged
  /// 10.31 m/s^2 instead of 9.807. Multiply raw values by this to correct.
  /// Angles are unaffected (a uniform scale cancels in the ratio) but the
  /// linear-acceleration checks below are not, so it is applied anyway.
  static const double defaultAccelScale = 0.950;

  /// Lowest angular rate we are willing to call a head jerk, rad/s
  /// (~20 deg/s). Below this the stationary captures produce false positives.
  static const double jerkThresholdFloor = 0.35;

  /// Highest adaptive jerk threshold, rad/s (~86 deg/s). Without a ceiling a
  /// calibration taken during movement raises the bar so far that genuine
  /// jerks are missed — captures 2 and 4 reproduce exactly that failure.
  static const double jerkThresholdCeiling = 1.50;

  // --- Rest-detection limits ----------------------------------------------
  static const double restGyroP95Max = 0.15; // rad/s
  static const double restAccelStdMax = 0.35; // m/s^2
  static const double restProximityStdMax = 10.0; // ADC counts
  static const int minimumCalibrationSamples = 8;

  final double gyroBiasX;
  final double gyroBiasY;
  final double gyroBiasZ;

  /// Multiplier that brings |a| at rest onto standard gravity.
  final double accelScale;

  /// Head pose the wearer held during calibration. All reported pitch and
  /// roll is relative to this, so mounting angle and face shape drop out.
  final double neutralPitchDeg;
  final double neutralRollDeg;

  /// Angular rate above which a sample counts as a head jerk, rad/s.
  final double jerkThreshold;

  /// IR reading with the eyes open.
  final double proximityOpenBaseline;

  /// Standard deviation of the IR reading at rest. Closure thresholds are
  /// expressed as multiples of this rather than as absolute counts.
  final double proximityNoise;

  /// Median interval between samples, milliseconds.
  final double sampleIntervalMs;

  /// Empty when the calibration is trustworthy.
  final List<CalibrationReject> rejects;

  bool get isValid => rejects.isEmpty;

  double get sampleRateHz =>
      sampleIntervalMs <= 0 ? 0 : 1000.0 / sampleIntervalMs;

  /// Conservative starting point used before any calibration has run.
  factory SensorCalibration.fallback() => const SensorCalibration(
        gyroBiasX: defaultGyroBiasX,
        gyroBiasY: defaultGyroBiasY,
        gyroBiasZ: defaultGyroBiasZ,
        accelScale: defaultAccelScale,
        neutralPitchDeg: 0,
        neutralRollDeg: 0,
        jerkThreshold: jerkThresholdFloor,
        proximityOpenBaseline: 70,
        proximityNoise: 6,
        sampleIntervalMs: 250,
        rejects: [CalibrationReject.notEnoughSamples],
      );

  /// Fits baselines to a window of samples the wearer held still.
  ///
  /// The result always carries usable numbers; [isValid] says whether they
  /// should be trusted. When rest checks fail the jerk threshold is pinned to
  /// [jerkThresholdCeiling] instead of the (inflated) adaptive value, so a
  /// bad calibration degrades to "less sensitive" rather than to "blind".
  factory SensorCalibration.fromWindow(List<SensorSample> window) {
    if (window.length < minimumCalibrationSamples) {
      return SensorCalibration.fallback();
    }

    final rejects = <CalibrationReject>[];

    final biasX = _median(window.map((s) => s.gx).toList());
    final biasY = _median(window.map((s) => s.gy).toList());
    final biasZ = _median(window.map((s) => s.gz).toList());

    final magnitudes = window.map((s) => s.accelMagnitude).toList();
    final magnitudeMedian = _median(magnitudes);
    final accelScale =
        magnitudeMedian > 0 ? 9.80665 / magnitudeMedian : defaultAccelScale;

    final gyroMagnitudes = window
        .map((s) => _magnitude(s.gx - biasX, s.gy - biasY, s.gz - biasZ))
        .toList();
    final gyroP95 = _percentile(gyroMagnitudes, 0.95);
    final accelStd = _standardDeviation(magnitudes);

    final proximities = window.map((s) => s.proximity.toDouble()).toList();
    final proximityStd = _standardDeviation(proximities);

    if (gyroP95 > restGyroP95Max) rejects.add(CalibrationReject.moving);
    if (accelStd > restAccelStdMax) rejects.add(CalibrationReject.unsteady);
    if (proximityStd > restProximityStdMax) {
      rejects.add(CalibrationReject.proximityUnstable);
    }

    final adaptiveJerk = gyroP95 * 6.0;
    final jerkThreshold = rejects.isEmpty
        ? adaptiveJerk.clamp(jerkThresholdFloor, jerkThresholdCeiling)
        : jerkThresholdCeiling;

    final intervals = <double>[];
    for (var i = 1; i < window.length; i++) {
      intervals.add(
        (window[i].timestampMs - window[i - 1].timestampMs).toDouble(),
      );
    }

    return SensorCalibration(
      gyroBiasX: biasX,
      gyroBiasY: biasY,
      gyroBiasZ: biasZ,
      accelScale: accelScale,
      neutralPitchDeg: _median(window.map(pitchDegOf).toList()),
      neutralRollDeg: _median(window.map(rollDegOf).toList()),
      jerkThreshold: jerkThreshold.toDouble(),
      proximityOpenBaseline: _percentile(proximities, 0.20),
      proximityNoise: math.max(1.5, proximityStd),
      sampleIntervalMs: intervals.isEmpty ? 250 : _median(intervals),
      rejects: rejects,
    );
  }

  /// Absolute head pitch in degrees, before the neutral pose is removed.
  static double pitchDegOf(SensorSample s) =>
      math.atan2(-s.ax, math.sqrt(s.ay * s.ay + s.az * s.az)) * 180 / math.pi;

  /// Absolute head roll in degrees, before the neutral pose is removed.
  static double rollDegOf(SensorSample s) =>
      math.atan2(s.ay, s.az) * 180 / math.pi;

  static double _magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static double _percentile(List<double> values, double fraction) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final index = ((sorted.length - 1) * fraction).round();
    // num.clamp returns num, so narrow it before using it as an index.
    return sorted[index.clamp(0, sorted.length - 1).toInt()];
  }

  static double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sum = 0.0;
    for (final v in values) {
      sum += (v - mean) * (v - mean);
    }
    return math.sqrt(sum / values.length);
  }

  @override
  String toString() => 'SensorCalibration('
      'valid: $isValid, rate: ${sampleRateHz.toStringAsFixed(1)}Hz, '
      'gyroBias: (${gyroBiasX.toStringAsFixed(3)}, ${gyroBiasY.toStringAsFixed(3)}, '
      '${gyroBiasZ.toStringAsFixed(3)}), accelScale: ${accelScale.toStringAsFixed(3)}, '
      'jerkThr: ${jerkThreshold.toStringAsFixed(2)}, '
      'proxOpen: ${proximityOpenBaseline.toStringAsFixed(0)}'
      '${rejects.isEmpty ? '' : ', rejects: $rejects'})';
}

/// Accumulates samples until it has a full calibration window.
///
/// Drives the "기준값 수집 중 00:42 / 01:00" screen: [progress] feeds the bar,
/// and a rejected result tells the user what to change instead of silently
/// producing bad thresholds.
class CalibrationCollector {
  CalibrationCollector({this.windowDuration = const Duration(seconds: 60)});

  final Duration windowDuration;
  final List<SensorSample> _samples = <SensorSample>[];
  int? _firstTimestampMs;

  int get sampleCount => _samples.length;

  double get progress {
    if (_firstTimestampMs == null || _samples.isEmpty) return 0;
    final elapsed = _samples.last.timestampMs - _firstTimestampMs!;
    return (elapsed / windowDuration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  bool get isComplete => progress >= 1.0;

  void add(SensorSample sample) {
    _firstTimestampMs ??= sample.timestampMs;
    _samples.add(sample);
  }

  void reset() {
    _samples.clear();
    _firstTimestampMs = null;
  }

  /// Fits the calibration. Safe to call before [isComplete] — useful for the
  /// live preview on the calibration screen.
  SensorCalibration fit() => SensorCalibration.fromWindow(_samples);
}
