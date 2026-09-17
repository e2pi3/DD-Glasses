import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 보안경 펌웨어(DEVICE/device.ino)와 앱이 공유하는 BLE GATT 규약.
/// 한쪽의 UUID / 페이로드 형식을 바꾸면 반드시 다른 쪽도 같이 바꿔야 한다.
class BleProtocol {
  BleProtocol._();

  /// 보안경이 광고(advertising)하는 기기 이름.
  static const String deviceName = 'DD-GLASSES';

  /// 눈 상태 서비스 (커스텀).
  static final Guid eyeService = Guid('8e7f0001-6c1b-4d3a-9f2e-3dd6a5e0b001');

  /// 눈 상태 characteristic (read / notify). 페이로드 형식은 [EyeState.parse] 참고.
  static final Guid eyeStateChar = Guid('8e7f0002-6c1b-4d3a-9f2e-3dd6a5e0b001');

  /// IR 근접센서(VCNL4040) 서비스 (커스텀).
  static final Guid proximityService = Guid('8e7f0003-6c1b-4d3a-9f2e-3dd6a5e0b001');

  /// proximity characteristic (read / notify). 페이로드 형식은 [ProximitySample.parse] 참고.
  static final Guid proximityChar = Guid('8e7f0004-6c1b-4d3a-9f2e-3dd6a5e0b001');
}

/// 기기가 추론 1회마다 보내는 눈 상태.
class EyeState {
  const EyeState({
    required this.closed,
    required this.closedProbability,
    required this.openProbability,
  });

  final bool closed;
  final double closedProbability;
  final double openProbability;

  /// 페이로드: [0] 판정(0=뜸, 1=감음), [1] 감음 확률 %, [2] 뜸 확률 %.
  static EyeState? parse(List<int> bytes) {
    if (bytes.length < 3) return null;
    return EyeState(
      closed: bytes[0] == 1,
      closedProbability: bytes[1] / 100,
      openProbability: bytes[2] / 100,
    );
  }
}

/// 기기가 500ms 주기로 보내는 VCNL4040 IR 근접센서 원시값(raw count).
class ProximitySample {
  const ProximitySample(this.value);

  final int value;

  /// 페이로드: uint16 (little-endian).
  static ProximitySample? parse(List<int> bytes) {
    if (bytes.length < 2) return null;
    return ProximitySample(bytes[0] | (bytes[1] << 8));
  }
}
