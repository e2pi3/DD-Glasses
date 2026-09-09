import 'dart:typed_data';

import 'live_metrics.dart' show PacketFormatException;

/// Hazard event sent over the Alert characteristic with Indicate.
///
/// Eight bytes, little-endian:
/// ```
///  0  2  alertId    uint16   monotonic; the key the acknowledgement matches
///  2  1  level      uint8    1 caution, 2 warning, 3 danger
///  3  1  cause      uint8    RiskCause bitmask
///  4  4  uptimeMs   uint32   device uptime when the hazard was detected
/// ```
class AlertPacket {
  const AlertPacket({
    required this.alertId,
    required this.level,
    required this.causeBitmask,
    required this.deviceUptimeMs,
  });

  static const int byteLength = 8;

  final int alertId;
  final int level;
  final int causeBitmask;
  final int deviceUptimeMs;

  factory AlertPacket.decode(Uint8List raw) {
    if (raw.length != byteLength) {
      throw PacketFormatException(
        'alert must be $byteLength bytes, got ${raw.length}',
      );
    }
    final data = ByteData.sublistView(raw);
    return AlertPacket(
      alertId: data.getUint16(0, Endian.little),
      level: data.getUint8(2),
      causeBitmask: data.getUint8(3),
      deviceUptimeMs: data.getUint32(4, Endian.little),
    );
  }

  Uint8List encode() {
    final raw = Uint8List(byteLength);
    final data = ByteData.sublistView(raw);
    data.setUint16(0, alertId & 0xFFFF, Endian.little);
    data.setUint8(2, level & 0xFF);
    data.setUint8(3, causeBitmask & 0xFF);
    data.setUint32(4, deviceUptimeMs & 0xFFFFFFFF, Endian.little);
    return raw;
  }

  @override
  String toString() =>
      'AlertPacket(id: $alertId, level: $level, cause: 0x${causeBitmask.toRadixString(16)})';
}

/// What the app is telling the glasses about an alert.
enum AlertAckStatus {
  /// The alarm reached the screen. Stops retransmission.
  displayed,

  /// The wearer confirmed it. Ends the feedback (proposal condition 2).
  confirmedByUser,

  /// The wearer dismissed it without acting.
  dismissed,
}

/// Three-byte acknowledgement written back with Write With Response.
class AlertAck {
  const AlertAck({required this.alertId, required this.status});

  static const int byteLength = 3;

  final int alertId;
  final AlertAckStatus status;

  factory AlertAck.decode(Uint8List raw) {
    if (raw.length != byteLength) {
      throw PacketFormatException(
        'ack must be $byteLength bytes, got ${raw.length}',
      );
    }
    final data = ByteData.sublistView(raw);
    final code = data.getUint8(2);
    return AlertAck(
      alertId: data.getUint16(0, Endian.little),
      status: AlertAckStatus
          .values[code.clamp(0, AlertAckStatus.values.length - 1).toInt()],
    );
  }

  Uint8List encode() {
    final raw = Uint8List(byteLength);
    final data = ByteData.sublistView(raw);
    data.setUint16(0, alertId & 0xFFFF, Endian.little);
    data.setUint8(2, status.index);
    return raw;
  }

  @override
  String toString() => 'AlertAck(id: $alertId, ${status.name})';
}
