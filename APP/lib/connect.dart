import 'package:flutter/foundation.dart';

// TODO(bluetooth): 실제 연동 시 기기 스캔/연결 실패 등 세부 상태가 늘어날 수 있음.
enum ConnectionStatus { bluetoothOff, bluetoothOn, deviceConnected }

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 앱 전역에서 공유하는 매니저.
/// 홈/설정 화면이 같은 상태를 보고 갱신할 수 있도록 싱글턴으로 둔다.
///
/// TODO(bluetooth): 실제 연동 시 블루투스 어댑터/기기 연결 스트림을 구독해서
/// status와 deviceId를 갱신하는 방식으로 교체한다.
class DeviceConnection extends ChangeNotifier {
  DeviceConnection._();

  static final DeviceConnection instance = DeviceConnection._();

  ConnectionStatus _status = ConnectionStatus.bluetoothOff;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.deviceConnected;

  String? _deviceId;
  String? get deviceId => _deviceId;

  // TODO(bluetooth): 디버그 빌드에서 좌측 상단 팝업 메뉴로 상태를 임의로
  // 바꿔볼 수 있게 만든 테스트용 임시 로직. 실제 연동 코드가 들어오면 제거한다.
  void debugSetStatus(ConnectionStatus status) {
    if (!kDebugMode) return;
    _status = status;
    _deviceId = status == ConnectionStatus.deviceConnected
        ? 'DD-GLASSES-0001'
        : null;
    notifyListeners();
  }

  void disconnect() {
    if (_status != ConnectionStatus.deviceConnected) return;
    _status = ConnectionStatus.bluetoothOn;
    _deviceId = null;
    notifyListeners();
  }
}
