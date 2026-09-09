import '../sensing/sensor_sample.dart';

/// A stream of sensor readings, wherever they come from.
///
/// The whole point of this interface is that everything above it — metrics,
/// risk fusion, screens, logging — is written once and never learns whether
/// the samples arrived over Bluetooth or were replayed from a spreadsheet.
/// The app is therefore fully developable and demonstrable before the BLE
/// link exists, and the recorded captures double as regression fixtures.
abstract class SensorSource {
  /// Human-readable name for the log and the debug banner.
  String get name;

  Stream<SensorSample> get samples;

  Future<void> start();

  Future<void> stop();
}
