import 'dart:math' as math;

/// One raw reading from the glasses, in the units the hardware team's
/// Arduino sketch produces.
///
/// Verified against the eight `sensor_data_10sec_*.xlsx` captures:
///  * acceleration is in m/s^2 (magnitude at rest reads ~10.31, i.e. 5 %
///    above standard gravity — see [SensorCalibration.accelScale]),
///  * angular rate is in rad/s (still readings sit at a fixed bias of about
///    -0.04 / -0.058 / -0.050; a brisk head turn reached 4.2 rad/s),
///  * proximity is the raw IR ADC count, higher when the eyelid is closed.
class SensorSample {
  const SensorSample({
    required this.timestampMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.proximity,
  });

  /// Device uptime in milliseconds (Arduino `millis()`), not wall clock.
  /// The app stamps its own receive time separately.
  final int timestampMs;

  final double ax;
  final double ay;
  final double az;

  final double gx;
  final double gy;
  final double gz;

  final int proximity;

  double get accelMagnitude => math.sqrt(ax * ax + ay * ay + az * az);

  /// Parses one row of the replay CSV
  /// (`t_ms,ax,ay,az,gx,gy,gz,prox`).
  factory SensorSample.fromCsvRow(List<String> cells) {
    if (cells.length < 8) {
      throw FormatException('expected 8 columns, got ${cells.length}');
    }
    double d(int i) => double.parse(cells[i].trim());
    return SensorSample(
      timestampMs: double.parse(cells[0].trim()).round(),
      ax: d(1),
      ay: d(2),
      az: d(3),
      gx: d(4),
      gy: d(5),
      gz: d(6),
      proximity: double.parse(cells[7].trim()).round(),
    );
  }

  @override
  String toString() => 'SensorSample(t: $timestampMs, '
      'a: (${ax.toStringAsFixed(2)}, ${ay.toStringAsFixed(2)}, ${az.toStringAsFixed(2)}), '
      'g: (${gx.toStringAsFixed(3)}, ${gy.toStringAsFixed(3)}, ${gz.toStringAsFixed(3)}), '
      'prox: $proximity)';
}
