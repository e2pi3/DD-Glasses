import 'dart:typed_data';

import '../core/crc8.dart';

/// Raised when a received frame cannot be trusted.
class PacketFormatException implements Exception {
  PacketFormatException(this.message);
  final String message;
  @override
  String toString() => 'PacketFormatException: $message';
}

/// The 20-byte real-time frame sent by the glasses at 4-20 Hz.
///
/// The length is deliberately 20 bytes so the frame still fits when ATT MTU
/// negotiation fails and the link falls back to the default MTU of 23
/// (23 - 3 bytes of ATT header = 20 bytes of payload). Every multi-byte
/// field is little-endian, matching the ESP32's native byte order.
///
/// ```
/// off size field         type    note
///  0    1  seq           uint8   wraps 0-255; gaps mean loss
///  1    1  flags         uint8   b0 wearing b1 calibrating b2 camera b3 lowPower
///  2    2  dtMs          uint16  interval since previous frame
///  4    2  perclos       uint16  x100  (0-10000 = 0-100 %)
///  6    2  pitch         int16   x10 degrees
///  8    2  roll          int16   x10 degrees
/// 10    2  blinkDurMs    uint16  ms
/// 12    1  blinkRate     uint8   blinks per minute
/// 13    1  eyeClosure    uint8   0 fully open .. 255 fully closed
/// 14    2  proximityRaw  uint16  raw IR ADC count, straight off the sensor
/// 16    1  riskLevel     uint8   0 normal .. 3 danger
/// 17    1  riskScore     uint8   0-100
/// 18    1  batteryPct    uint8   0-100
/// 19    1  crc8          uint8   over bytes 0..18
/// ```
class LiveMetrics {
  const LiveMetrics({
    required this.seq,
    required this.flags,
    required this.dtMs,
    required this.perclos,
    required this.pitchDeg,
    required this.rollDeg,
    required this.blinkDurMs,
    required this.blinkRatePerMin,
    required this.eyeClosure,
    required this.proximityRaw,
    required this.riskLevel,
    required this.riskScore,
    required this.batteryPct,
  });

  static const int byteLength = 20;

  static const int flagWearing = 0x01;
  static const int flagCalibrating = 0x02;
  static const int flagCameraActive = 0x04;
  static const int flagLowPower = 0x08;

  final int seq;
  final int flags;
  final int dtMs;

  /// Eye-closure ratio over the trailing window, 0.0 - 1.0.
  final double perclos;

  /// Head pitch in degrees relative to the calibrated neutral pose.
  final double pitchDeg;

  /// Head roll in degrees relative to the calibrated neutral pose.
  final double rollDeg;

  final int blinkDurMs;
  final int blinkRatePerMin;

  /// Current eye closure, 0 fully open to 255 fully closed, after the
  /// firmware has applied its per-session calibration.
  final int eyeClosure;

  /// The uncalibrated IR reading the closure was derived from.
  ///
  /// Carried because the sensor set is now IR plus IMU only, and the open-eye
  /// baseline moved between 60 and 92 counts across the recorded captures. The
  /// app cannot re-derive a threshold without seeing the raw number, and the
  /// calibration screen has nothing to display without it. It is also how the
  /// polarity question gets settled on the bench: open the eyes, close them,
  /// and watch which way this moves.
  final int proximityRaw;

  final int riskLevel;
  final int riskScore;
  final int batteryPct;

  bool get isWearing => flags & flagWearing != 0;
  bool get isCalibrating => flags & flagCalibrating != 0;

  /// True while the on-board camera is streaming over Wi-Fi. The radio is
  /// shared with BLE, so extra jitter and loss is expected in this state and
  /// the firmware drops the stream rate on its own.
  bool get isCameraActive => flags & flagCameraActive != 0;

  bool get isLowPower => flags & flagLowPower != 0;

  /// Eye closure as 0.0 - 1.0.
  double get eyeClosureRatio => eyeClosure / 255.0;

  /// Parses a frame received over the Live Metrics characteristic.
  ///
  /// Throws [PacketFormatException] if the length or the CRC is wrong. The
  /// caller should count these separately from sequence gaps: a CRC failure
  /// means corruption, a gap means the packet never arrived.
  factory LiveMetrics.decode(Uint8List raw) {
    if (raw.length != byteLength) {
      throw PacketFormatException(
        'expected $byteLength bytes, got ${raw.length}',
      );
    }
    final expected = Crc8.compute(raw, end: byteLength - 1);
    if (expected != raw[byteLength - 1]) {
      throw PacketFormatException(
        'CRC mismatch: computed 0x${expected.toRadixString(16)}, '
        'frame carries 0x${raw[byteLength - 1].toRadixString(16)}',
      );
    }
    final data = ByteData.sublistView(raw);
    return LiveMetrics(
      seq: data.getUint8(0),
      flags: data.getUint8(1),
      dtMs: data.getUint16(2, Endian.little),
      perclos: data.getUint16(4, Endian.little) / 10000.0,
      pitchDeg: data.getInt16(6, Endian.little) / 10.0,
      rollDeg: data.getInt16(8, Endian.little) / 10.0,
      blinkDurMs: data.getUint16(10, Endian.little),
      blinkRatePerMin: data.getUint8(12),
      eyeClosure: data.getUint8(13),
      proximityRaw: data.getUint16(14, Endian.little),
      riskLevel: data.getUint8(16),
      riskScore: data.getUint8(17),
      batteryPct: data.getUint8(18),
    );
  }

  /// Builds the wire frame. The app never transmits this — it exists so unit
  /// tests can round-trip, and so the replay source can feed the exact same
  /// decoder the BLE source feeds.
  Uint8List encode() {
    final raw = Uint8List(byteLength);
    final data = ByteData.sublistView(raw);
    data.setUint8(0, seq & 0xFF);
    data.setUint8(1, flags & 0xFF);
    data.setUint16(2, _clampInt(dtMs, 0, 65535), Endian.little);
    data.setUint16(4, _clampInt((perclos * 10000).round(), 0, 10000), Endian.little);
    data.setInt16(6, _clampInt((pitchDeg * 10).round(), -32768, 32767), Endian.little);
    data.setInt16(8, _clampInt((rollDeg * 10).round(), -32768, 32767), Endian.little);
    data.setUint16(10, _clampInt(blinkDurMs, 0, 65535), Endian.little);
    data.setUint8(12, _clampInt(blinkRatePerMin, 0, 255));
    data.setUint8(13, _clampInt(eyeClosure, 0, 255));
    data.setUint16(14, _clampInt(proximityRaw, 0, 65535), Endian.little);
    data.setUint8(16, _clampInt(riskLevel, 0, 3));
    data.setUint8(17, _clampInt(riskScore, 0, 100));
    data.setUint8(18, _clampInt(batteryPct, 0, 100));
    data.setUint8(19, Crc8.compute(raw, end: byteLength - 1));
    return raw;
  }

  static int _clampInt(int value, int low, int high) =>
      value < low ? low : (value > high ? high : value);

  @override
  String toString() => 'LiveMetrics(seq: $seq, risk: $riskLevel/$riskScore, '
      'perclos: ${(perclos * 100).toStringAsFixed(1)}%, '
      'pitch: ${pitchDeg.toStringAsFixed(1)}deg, dt: ${dtMs}ms)';
}
