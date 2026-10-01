import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 보안경 펌웨어(DEVICE/device.ino)와 앱이 공유하는 BLE GATT 규약.
/// 한쪽의 UUID / 페이로드 형식을 바꾸면 반드시 다른 쪽도 같이 바꿔야 한다.
class BleProtocol {
  BleProtocol._();

  /// 보안경이 광고(advertising)하는 기기 이름.
  static const String deviceName = 'DD-GLASSES';

  /// 센서/추론 결과 서비스. 광고 패킷에도 실려서 스캔 필터로 쓴다.
  static final Guid telemetryService = Guid(
    '8e7f0001-6c1b-4d3a-9f2e-3dd6a5e0b001',
  );

  /// 500ms 마다 기기가 notify 하는 [SensorFrame].
  static final Guid telemetryChar = Guid(
    '8e7f0002-6c1b-4d3a-9f2e-3dd6a5e0b001',
  );

  /// 설정 서비스.
  static final Guid settingsService = Guid(
    '8e7f0003-6c1b-4d3a-9f2e-3dd6a5e0b001',
  );

  /// 설정 characteristic (read / write). 페이로드는 [DeviceSettings] 참고.
  /// 3바이트: [음량, 진동, 플래그(bit0=소리 on, bit1=진동 on)].
  /// 설정의 원본은 기기(NVS)이므로 앱은 연결할 때마다 이 값을 읽어 온다.
  static final Guid settingsChar = Guid('8e7f0004-6c1b-4d3a-9f2e-3dd6a5e0b001');

  /// 미리보기 characteristic (write): [종류(0=소리, 1=진동), 단계(1~5)].
  /// 저장은 하지 않고 기기가 잠깐 울리거나 진동하게만 한다.
  static final Guid previewChar = Guid('8e7f0005-6c1b-4d3a-9f2e-3dd6a5e0b001');
}

/// 경고음 음량 / 진동 세기의 단계 범위. 펌웨어의 LEVEL_MIN / LEVEL_MAX 와 같아야 한다.
class SettingLevel {
  SettingLevel._();

  static const int min = 1;
  static const int max = 5;
  static const int defaultLevel = 3;
}

/// 기기에 저장된 사용자 설정. 페이로드: [음량 1~5, 진동 1~5, 플래그].
/// 플래그는 bit0=소리 켜짐, bit1=진동 켜짐.
///
/// 꺼도 단계는 그대로 두므로 다시 켜면 직전 세기로 돌아온다. 그래서 "꺼짐"을 0단계로
/// 표현하지 않는다. 둘을 동시에 끄면 졸음 경고를 전달할 수단이 없어지므로 펌웨어가
/// 그런 쓰기를 거부한다 ([vibrationEnabled] / [soundEnabled] 중 하나는 항상 켜져 있다).
class DeviceSettings {
  const DeviceSettings({
    required this.volume,
    required this.vibration,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  final int volume;
  final int vibration;
  final bool soundEnabled;
  final bool vibrationEnabled;

  DeviceSettings copyWith({
    int? volume,
    int? vibration,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) => DeviceSettings(
    volume: volume ?? this.volume,
    vibration: vibration ?? this.vibration,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
  );

  static DeviceSettings? parse(List<int> bytes) {
    if (bytes.length < 2) return null;
    int clamp(int v) => v.clamp(SettingLevel.min, SettingLevel.max);
    // 플래그를 보내지 않는 구버전 펌웨어는 둘 다 켜진 것으로 본다.
    final flags = bytes.length >= 3 ? bytes[2] : 0x03;
    return DeviceSettings(
      volume: clamp(bytes[0]),
      vibration: clamp(bytes[1]),
      soundEnabled: flags & 1 != 0,
      vibrationEnabled: flags & 2 != 0,
    );
  }

  List<int> toBytes() => [
    volume,
    vibration,
    (soundEnabled ? 1 : 0) | (vibrationEnabled ? 2 : 0),
  ];
}

enum PreviewType { sound, vibration }

/// 기기가 500ms 주기로 보내는 센서/추론 한 프레임 (16바이트).
///
///  [0]    flags  bit0=눈 유효, bit1=눈 감김, bit2=근접 유효, bit3=IMU 유효, bit4=착용 중,
///                bit5=졸음 경고 중, bit6=직전에 버튼 반응
///  [1]    감음 확률 % (0~100)
///  [2:4]  근접 raw uint16 LE
///  [4:16] IMU int16 LE x6 : acc xyz (0.01 m/s²), gyro xyz (mrad/s)
///
/// 유효하지 않은 센서 값은 null 이다.
class SensorFrame {
  const SensorFrame({
    required this.eyeClosed,
    required this.closedProbability,
    required this.proximity,
    required this.accel,
    required this.gyro,
    required this.worn,
    required this.alerting,
    required this.buttonReacted,
  });

  /// 눈 추론이 유효할 때만 값이 있다.
  final bool? eyeClosed;
  final double? closedProbability;

  /// VCNL4040 근접 raw count.
  final int? proximity;

  /// 가속도 (m/s²) x, y, z.
  final List<double>? accel;

  /// 각속도 (rad/s) x, y, z.
  final List<double>? gyro;

  /// 기기가 근접센서로 착용을 확정했는지. 착용 전에는 카메라가 휴면이라 눈 값이 없다.
  final bool worn;

  /// 기기가 지금 졸음 경고를 울리고 있는지. 졸음 판정은 기기가 하므로 앱은 이 값을 그대로 쓴다.
  final bool alerting;

  /// 직전 구간에 사용자가 버튼을 눌러 경고에 반응했는지. 한 프레임 동안만 true 다.
  final bool buttonReacted;

  static const int length = 16;

  static SensorFrame? parse(List<int> b) {
    if (b.length < length) return null;
    final flags = b[0];
    final eyeOk = flags & 1 != 0;
    final proxOk = flags & 4 != 0;
    final imuOk = flags & 8 != 0;

    int i16(int at) {
      final v = b[at] | (b[at + 1] << 8);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    return SensorFrame(
      eyeClosed: eyeOk ? flags & 2 != 0 : null,
      closedProbability: eyeOk ? b[1] / 100 : null,
      proximity: proxOk ? b[2] | (b[3] << 8) : null,
      accel: imuOk ? [for (var k = 0; k < 3; k++) i16(4 + k * 2) / 100] : null,
      worn: flags & 16 != 0,
      gyro: imuOk ? [for (var k = 3; k < 6; k++) i16(4 + k * 2) / 1000] : null,
      alerting: flags & 32 != 0,
      buttonReacted: flags & 64 != 0,
    );
  }
}
