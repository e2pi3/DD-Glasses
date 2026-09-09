import 'dart:async';

import '../protocol/live_metrics.dart';
import '../sensing/calibration.dart';
import '../sensing/metric_engine.dart';
import '../sensing/risk_fusion.dart';
import '../sensing/sensor_sample.dart';
import 'sensor_source.dart';

/// Runs the on-device algorithm inside the app, then emits the result as a
/// wire frame.
///
/// In the shipped system the ESP32 computes the metrics and the risk level and
/// the phone only decodes 20-byte frames. Running the same pipeline in Dart on
/// replayed captures does three useful things at once: it lets the app be
/// built and demonstrated before the firmware exists, it gives the algorithm a
/// place to be unit-tested against recorded data, and — because the output is
/// encoded and decoded exactly as the radio would — it exercises the codec on
/// every sample instead of only in tests.
class LocalMetricsPipeline {
  LocalMetricsPipeline({
    required this.source,
    SensorCalibration? calibration,
    RiskThresholds thresholds = const RiskThresholds(),
    this.calibrationWindow = const Duration(seconds: 4),
    Duration metricWindow = const Duration(seconds: 60),
    this.batteryPct = 100,
  })  : _engine = MetricEngine(
          calibration: calibration ?? SensorCalibration.fallback(),
          window: metricWindow,
        ),
        _fusion = RiskFusion(thresholds: thresholds),
        _autoCalibrate = calibration == null;

  final SensorSource source;

  /// How much of the start of the stream is used to fit baselines when no
  /// calibration was supplied.
  final Duration calibrationWindow;

  final int batteryPct;

  final MetricEngine _engine;
  final RiskFusion _fusion;
  final bool _autoCalibrate;

  final List<SensorSample> _calibrationBuffer = <SensorSample>[];
  final StreamController<LiveMetrics> _frames =
      StreamController<LiveMetrics>.broadcast();
  final StreamController<RiskAssessment> _risks =
      StreamController<RiskAssessment>.broadcast();

  StreamSubscription<SensorSample>? _subscription;
  int _seq = 0;
  int? _previousTimestampMs;
  bool _calibrated = false;

  /// Frames in exactly the form the BLE source produces.
  Stream<LiveMetrics> get frames => _frames.stream;

  /// Risk transitions, for driving alerts locally during a replay demo.
  Stream<RiskAssessment> get risks => _risks.stream;

  SensorCalibration get calibration => _engine.calibration;
  MetricConfidence get confidence => _engine.confidence;

  Future<void> start() async {
    _subscription ??= source.samples.listen(_onSample);
    await source.start();
  }

  Future<void> stop() async {
    await source.stop();
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _risks.close();
  }

  void _onSample(SensorSample sample) {
    if (_autoCalibrate && !_calibrated) {
      _calibrationBuffer.add(sample);
      final span = sample.timestampMs - _calibrationBuffer.first.timestampMs;
      // Both conditions matter: the captures run as slow as 2 Hz, where four
      // seconds is only nine samples, and fitting a baseline to fewer than
      // [SensorCalibration.minimumCalibrationSamples] silently falls back to
      // the generic defaults.
      if (span < calibrationWindow.inMilliseconds ||
          _calibrationBuffer.length <
              SensorCalibration.minimumCalibrationSamples) {
        return;
      }
      _engine.calibration =
          SensorCalibration.fromWindow(_calibrationBuffer);
      _calibrated = true;
    }

    final metrics = _engine.add(sample);
    final risk = _fusion.assess(metrics);
    if (risk.changed && !_risks.isClosed) _risks.add(risk);

    final dt = _previousTimestampMs == null
        ? _engine.calibration.sampleIntervalMs.round()
        : sample.timestampMs - _previousTimestampMs!;
    _previousTimestampMs = sample.timestampMs;

    var flags = LiveMetrics.flagWearing;
    if (_autoCalibrate && !_calibrated) flags |= LiveMetrics.flagCalibrating;

    final frame = LiveMetrics(
      seq: _seq & 0xFF,
      flags: flags,
      dtMs: dt,
      perclos: metrics.perclos ?? 0,
      pitchDeg: metrics.pitchDeg,
      rollDeg: metrics.rollDeg,
      blinkDurMs: (metrics.meanBlinkDurationMs ?? 0).round(),
      blinkRatePerMin: (metrics.blinkRatePerMin ?? 0).round(),
      eyeClosure: (metrics.eyeClosure * 255).round(),
      proximityRaw: sample.proximity,
      riskLevel: risk.level.wireValue,
      riskScore: risk.score,
      batteryPct: batteryPct,
    );
    _seq = (_seq + 1) & 0xFF;

    // Round-trip through the wire format so the replay path and the radio
    // path deliver byte-identical objects downstream.
    if (!_frames.isClosed) {
      _frames.add(LiveMetrics.decode(frame.encode()));
    }
  }
}
