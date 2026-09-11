import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// TODO(bluetooth): 실제 연동 시 기기 스캔/연결 실패 등 세부 상태가 늘어날 수 있음.
enum ConnectionStatus { bluetoothOff, bluetoothOn, deviceConnected }

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 앱 전역에서 공유하는 매니저.
/// 홈/설정 화면이 같은 상태를 보고 갱신할 수 있도록 싱글턴으로 둔다.
///
/// 폰의 블루투스 어댑터 on/off는 [FlutterBluePlus.adapterState] 스트림을 구독해
/// 자동으로 반영한다. 특정 기기(DD-GLASSES)와의 실제 연결/해제는 아직 없음.
///
/// TODO(bluetooth): 실제 연동 시 기기 스캔 및 GATT 연결 스트림을 구독해서
/// deviceConnected/deviceId를 갱신하는 방식으로 교체한다.
class DeviceConnection extends ChangeNotifier {
  DeviceConnection._() {
    _init();
  }

  static final DeviceConnection instance = DeviceConnection._();

  ConnectionStatus _status = ConnectionStatus.bluetoothOff;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.deviceConnected;

  String? _deviceId;
  String? get deviceId => _deviceId;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  Future<void> _init() async {
    await _ensureBluetoothPermissions();
    _adapterStateSub = FlutterBluePlus.adapterState.listen(
      _onAdapterStateChanged,
    );
  }

  // Android 12+(API 31+)에서는 어댑터 상태 조회에도 런타임 권한 승인이 필요하다.
  Future<void> _ensureBluetoothPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
  }

  void _onAdapterStateChanged(BluetoothAdapterState state) {
    final next = state == BluetoothAdapterState.on
        ? ConnectionStatus.bluetoothOn
        : ConnectionStatus.bluetoothOff;
    if (next == _status) return;
    _status = next;
    if (next == ConnectionStatus.bluetoothOff) {
      _deviceId = null;
    }
    notifyListeners();
  }

  void disconnect() {
    if (_status != ConnectionStatus.deviceConnected) return;
    _status = ConnectionStatus.bluetoothOn;
    _deviceId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    super.dispose();
  }
}
