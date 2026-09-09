import 'dart:typed_data';

/// Opcodes written to the Command characteristic with Write With Response.
class AwakeCommand {
  AwakeCommand._();

  static const int ping = 0x01;
  static const int stopFeedback = 0x02;
  static const int startCalibration = 0x03;
  static const int setStreamRate = 0x04;
  static const int testMode = 0x05;
  static const int requestLog = 0x06;

  /// Round-trip probe. The firmware answers with a Status notification, which
  /// is how the main screen measures latency.
  static Uint8List buildPing() => Uint8List.fromList(<int>[ping]);

  /// Ends feedback early (proposal condition 1 equivalent, from the app side).
  static Uint8List buildStopFeedback() =>
      Uint8List.fromList(<int>[stopFeedback]);

  /// Starts the one-minute baseline collection on the device.
  static Uint8List buildStartCalibration() =>
      Uint8List.fromList(<int>[startCalibration]);

  /// Sets the Live Metrics rate, 1-20 Hz.
  static Uint8List buildSetStreamRate(int hz) =>
      Uint8List.fromList(<int>[setStreamRate, hz.clamp(1, 20).toInt()]);

  /// Asks the firmware to emit [packetCount] frames with a known sequence, so
  /// the app can measure loss without any sensor involved.
  static Uint8List buildTestMode(int packetCount) {
    final raw = Uint8List(3);
    raw[0] = testMode;
    ByteData.sublistView(raw)
        .setUint16(1, packetCount.clamp(1, 65535).toInt(), Endian.little);
    return raw;
  }

  /// Requests buffered log chunks from [fromIndex] onward. Used both for the
  /// initial catch-up after reconnecting and to fill gaps the app detected.
  static Uint8List buildRequestLog(int fromIndex) {
    final raw = Uint8List(5);
    raw[0] = requestLog;
    ByteData.sublistView(raw).setUint32(1, fromIndex, Endian.little);
    return raw;
  }
}

/// Eight-byte device status, notified once a second. Its arrival is what the
/// watchdog counts as a heartbeat when the metrics stream is idle.
class DeviceStatus {
  const DeviceStatus({
    required this.batteryPct,
    required this.firmwareMajor,
    required this.firmwareMinor,
    required this.uptimeSeconds,
    required this.bufferedLogCount,
  });

  static const int byteLength = 8;

  final int batteryPct;
  final int firmwareMajor;
  final int firmwareMinor;
  final int uptimeSeconds;

  /// Samples held in PSRAM because the phone was unreachable.
  final int bufferedLogCount;

  factory DeviceStatus.decode(Uint8List raw) {
    final data = ByteData.sublistView(raw);
    return DeviceStatus(
      batteryPct: data.getUint8(0),
      firmwareMajor: data.getUint8(1),
      firmwareMinor: data.getUint8(2),
      uptimeSeconds: data.getUint16(3, Endian.little),
      bufferedLogCount: data.getUint16(5, Endian.little),
    );
  }

  String get firmwareVersion => 'v$firmwareMajor.$firmwareMinor';

  @override
  String toString() => 'DeviceStatus($firmwareVersion, battery: $batteryPct%, '
      'uptime: ${uptimeSeconds}s, buffered: $bufferedLogCount)';
}
