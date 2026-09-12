import 'dart:typed_data';

/// 보안경이 보내는 한 샘플.
///
/// 패킷은 20바이트로 고정했습니다. BLE 기본 ATT MTU 23바이트에서 헤더 3바이트를
/// 빼면 notification 페이로드가 20바이트이므로, MTU 협상 없이도 그대로 들어갑니다.
/// float32 로 보내면 36바이트가 되어 한 패킷에 못 실립니다. 센서 원시값은 12~16비트라
/// int16 으로 충분합니다.
///
/// 레이아웃 (little-endian):
///   0      uint8   seq       시퀀스 번호, 유실 감지용
///   1      uint8   flags     bit0 = 착용 감지, bit1..7 예약
///   2..3   int16   irLeft
///   4..5   int16   irRight
///   6..7   int16   gyroX
///   8..9   int16   gyroY
///   10..11 int16   gyroZ
///   12..13 int16   accX
///   14..15 int16   accY
///   16..17 int16   accZ
///   18..19 int16   heartRate (bpm, 미측정 시 -1)
class SensorSample {
  static const packetLength = 20;

  final int seq;
  final bool worn;
  final int irLeft;
  final int irRight;
  final int gyroX;
  final int gyroY;
  final int gyroZ;
  final int accX;
  final int accY;
  final int accZ;
  final int heartRate;
  final DateTime receivedAt;

  const SensorSample({
    required this.seq,
    required this.worn,
    required this.irLeft,
    required this.irRight,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.heartRate,
    required this.receivedAt,
  });

  /// 길이가 맞지 않으면 null 을 반환합니다. BLE 는 잘린 패킷이 올라오는 경우가 있어
  /// 예외를 던지지 않고 조용히 버리는 편이 안전합니다.
  static SensorSample? decode(List<int> raw) {
    if (raw.length < packetLength) return null;
    final b = ByteData.sublistView(Uint8List.fromList(raw));
    return SensorSample(
      seq: b.getUint8(0),
      worn: (b.getUint8(1) & 0x01) != 0,
      irLeft: b.getInt16(2, Endian.little),
      irRight: b.getInt16(4, Endian.little),
      gyroX: b.getInt16(6, Endian.little),
      gyroY: b.getInt16(8, Endian.little),
      gyroZ: b.getInt16(10, Endian.little),
      accX: b.getInt16(12, Endian.little),
      accY: b.getInt16(14, Endian.little),
      accZ: b.getInt16(16, Endian.little),
      heartRate: b.getInt16(18, Endian.little),
      receivedAt: DateTime.now(),
    );
  }

  /// 양쪽 IR 이 모두 임계값 아래면 눈이 감긴 것으로 봅니다.
  /// 임계값은 전전팀 초기 데이터가 나오기 전까지의 잠정값입니다.
  bool eyesClosed(int threshold) => irLeft < threshold && irRight < threshold;

  /// 자이로 크기. 고개 꺾임 판정의 입력.
  double get gyroMagnitude {
    final x = gyroX.toDouble(), y = gyroY.toDouble(), z = gyroZ.toDouble();
    return (x * x + y * y + z * z);
  }

  List<Object?> toCsvRow() => [
        receivedAt.toIso8601String(),
        seq,
        worn ? 1 : 0,
        irLeft,
        irRight,
        gyroX,
        gyroY,
        gyroZ,
        accX,
        accY,
        accZ,
        heartRate,
      ];

  static const csvHeader =
      'timestamp,seq,worn,ir_left,ir_right,gyro_x,gyro_y,gyro_z,acc_x,acc_y,acc_z,hr';
}
