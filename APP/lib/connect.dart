import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble.dart';

/// 졸음감지 보안경(엣지 디바이스)과의 연결 상태를 앱 전역에서 공유하는 매니저.
/// 홈/설정 화면이 같은 상태를 보고 갱신할 수 있도록 싱글턴으로 둔다.
///
/// 화면에서 쓰는 이 세 가지 상태는 그대로지만, 안쪽에서는 [AwakeBleClient]의
/// 더 세분화된 [AwakeLinkState]를 이 세 상태로 접어 넣는다. 특히
/// [ConnectionStatus.deviceConnected]는 GATT 연결이 아니라 "첫 20바이트
/// 프레임이 CRC까지 통과해 디코드된 시점"([AwakeLinkState.streaming])이다.
/// GATT 연결 자체는 서비스 탐색 실패, 구독 실패 등으로 아무것도 보장하지
/// 않기 때문 — 자세한 근거는 src/data/awake_ble_client.dart 참고.
enum ConnectionStatus { bluetoothOff, bluetoothOn, deviceConnected }

extension _AsConnectionStatus on AwakeLinkState {
  ConnectionStatus toConnectionStatus() {
    switch (this) {
      case AwakeLinkState.streaming:
        return ConnectionStatus.deviceConnected;
      case AwakeLinkState.idle:
      case AwakeLinkState.scanning:
      case AwakeLinkState.connecting:
      case AwakeLinkState.discovering:
      case AwakeLinkState.subscribing:
      case AwakeLinkState.reconnecting:
      case AwakeLinkState.failed:
        return ConnectionStatus.bluetoothOn;
    }
  }
}

class DeviceConnection extends ChangeNotifier {
  DeviceConnection._() {
    _adapterStateSub =
        FlutterBluePlus.adapterState.listen(_onAdapterStateChanged);
    _linkStateSub = _client.stateStream.listen(_onLinkStateChanged);
  }

  static final DeviceConnection instance = DeviceConnection._();

  /// 실제 무선 스택. 홈/설정 화면은 이 필드를 몰라도 되지만, 통계 화면 등
  /// 나중에 실시간 지표(PERCLOS, 위험도 등)가 필요해지면
  /// `DeviceConnection.instance.client.metrics`를 구독하면 된다.
  final AwakeBleClient client = AwakeBleClient();
  AwakeBleClient get _client => client;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  AwakeLinkState _linkState = AwakeLinkState.idle;

  ConnectionStatus _status = ConnectionStatus.bluetoothOff;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.deviceConnected;

  String? get deviceId => client.deviceName;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<AwakeLinkState>? _linkStateSub;

  void _onAdapterStateChanged(BluetoothAdapterState state) {
    final wasOff = _adapterState != BluetoothAdapterState.on;
    _adapterState = state;

    if (state == BluetoothAdapterState.on) {
      // 블루투스가 막 켜졌으면(또는 처음 켜진 상태로 확인되면) 바로 스캔을
      // 시작한다. 화면에는 아직 "다시 연결" 버튼이 없어서 자동 시작이 유일한
      // 진입점이다 — 재시도는 AwakeBleClient의 지수 백오프가 알아서 한다.
      if (wasOff && _linkState == AwakeLinkState.idle) {
        unawaited(client.connect());
      }
    } else {
      unawaited(client.disconnect());
    }
    _recompute();
  }

  void _onLinkStateChanged(AwakeLinkState state) {
    _linkState = state;
    _recompute();
  }

  void _recompute() {
    final next = _adapterState != BluetoothAdapterState.on
        ? ConnectionStatus.bluetoothOff
        : _linkState.toConnectionStatus();
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }

  /// 사용자가 명시적으로 다시 연결을 시도할 때 호출한다 (예: 설정 화면의
  /// "다시 검색" 같은 버튼을 나중에 추가할 경우).
  Future<void> connect() => client.connect();

  void disconnect() {
    if (_status != ConnectionStatus.deviceConnected &&
        _status != ConnectionStatus.bluetoothOn) {
      return;
    }
    unawaited(client.disconnect());
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    _linkStateSub?.cancel();
    client.dispose();
    super.dispose();
  }
}
