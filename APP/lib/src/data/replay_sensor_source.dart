import 'dart:async';

import '../sensing/sensor_sample.dart';
import 'sensor_source.dart';

/// Replays a recorded capture as if it were arriving live.
///
/// Backed by the hardware team's `sensor_data_10sec_*.xlsx` exports, converted
/// to CSV under `assets/replay/`. Timing follows the recorded timestamps, so a
/// 2 Hz capture replays at 2 Hz and the app sees exactly the sample rate the
/// firmware will produce — including the parts of the pipeline that degrade at
/// low rates.
class ReplaySensorSource implements SensorSource {
  ReplaySensorSource({
    required this.samplesList,
    required this.name,
    this.loop = true,
    this.speed = 1.0,
  }) : assert(speed > 0, 'speed must be positive');

  /// Parses the CSV layout written by `tools/convert_captures.py`:
  /// `t_ms,ax,ay,az,gx,gy,gz,prox`.
  factory ReplaySensorSource.fromCsv(
    String csv, {
    required String name,
    bool loop = true,
    double speed = 1.0,
  }) {
    final rows = <SensorSample>[];
    final lines = csv.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (i == 0 && line.toLowerCase().startsWith('t_ms')) continue;
      rows.add(SensorSample.fromCsvRow(line.split(',')));
    }
    if (rows.isEmpty) {
      throw FormatException('capture "$name" contained no samples');
    }
    return ReplaySensorSource(
      samplesList: rows,
      name: name,
      loop: loop,
      speed: speed,
    );
  }

  final List<SensorSample> samplesList;

  @override
  final String name;

  /// Restart from the beginning when the capture ends. The captures are only
  /// 12 seconds long, so looping is what makes them usable for a demo.
  final bool loop;

  /// Playback multiplier. 0 is rejected; values above 1 compress the waits,
  /// which is how the tests replay a 12-second capture instantly.
  final double speed;

  final StreamController<SensorSample> _controller =
      StreamController<SensorSample>.broadcast();

  Timer? _timer;
  int _index = 0;
  int _loopCount = 0;

  @override
  Stream<SensorSample> get samples => _controller.stream;

  /// Total sample periods emitted, useful for tests.
  int get emitted => _index + _loopCount * samplesList.length;

  @override
  Future<void> start() async {
    if (_timer != null) return;
    _index = 0;
    _loopCount = 0;
    _scheduleNext(Duration.zero);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  /// Pushes the whole capture synchronously, ignoring timestamps. Used by
  /// tests and by the offline metric replay tool.
  void pumpAll() {
    for (final sample in samplesList) {
      if (!_controller.isClosed) _controller.add(sample);
    }
  }

  void _scheduleNext(Duration delay) {
    _timer = Timer(delay, () {
      if (_index >= samplesList.length) {
        if (!loop) {
          stop();
          return;
        }
        _index = 0;
        _loopCount++;
      }
      final sample = samplesList[_index];
      if (!_controller.isClosed) {
        // Keep timestamps monotonic across loops, otherwise every window in
        // the metric engine would jump backwards on each repeat.
        _controller.add(
          _loopCount == 0
              ? sample
              : SensorSample(
                  timestampMs: sample.timestampMs + _loopCount * _captureSpanMs,
                  ax: sample.ax,
                  ay: sample.ay,
                  az: sample.az,
                  gx: sample.gx,
                  gy: sample.gy,
                  gz: sample.gz,
                  proximity: sample.proximity,
                ),
        );
      }

      final next = _index + 1;
      Duration wait;
      if (next < samplesList.length) {
        final deltaMs =
            samplesList[next].timestampMs - samplesList[_index].timestampMs;
        wait = Duration(microseconds: (deltaMs * 1000 / speed).round());
      } else {
        wait = Duration(microseconds: (_medianIntervalMs * 1000 / speed).round());
      }
      _index = next;
      _scheduleNext(wait);
    });
  }

  int get _captureSpanMs {
    if (samplesList.length < 2) return 1000;
    return samplesList.last.timestampMs -
        samplesList.first.timestampMs +
        _medianIntervalMs;
  }

  int get _medianIntervalMs {
    if (samplesList.length < 2) return 250;
    final deltas = <int>[];
    for (var i = 1; i < samplesList.length; i++) {
      deltas.add(samplesList[i].timestampMs - samplesList[i - 1].timestampMs);
    }
    deltas.sort();
    return deltas[deltas.length ~/ 2];
  }
}
