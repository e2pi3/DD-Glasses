import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connect.dart';

/// 졸음감지 보안경(엣지 디바이스)이 보내는 상태/신호 정보를 담는 모델.
/// 홈 화면 등에서 이 값을 구독해서 화면에 표시한다. 연결 자체의 상태는
/// [DeviceConnection](connect.dart)이 담당하고, 이 클래스는 연결된 기기가
/// 보내는 데이터(배터리, 러닝타임 등)만 담는다.
///
/// TODO(device): 실제 연동 시 기기로부터 받아오는 배터리 잔량 등 실제 값으로
/// 교체한다. 지금은 배터리 잔량만 100으로 고정한 임시 값.
class DeviceInfo extends ChangeNotifier {
  DeviceInfo._() {
    DeviceConnection.instance.addListener(_onConnectionChanged);
  }

  static final DeviceInfo instance = DeviceInfo._();

  // TODO(device): 실제 연동 전까지 100으로 고정한 임시 값.
  int batteryLevel = 100;

  DateTime? _connectedAt;
  Timer? _ticker;

  /// 기기가 연결된 시점부터 흐른 시간. 연결되어 있지 않으면 0이다.
  Duration get runningTime {
    final connectedAt = _connectedAt;
    return connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt);
  }

  void _onConnectionChanged() {
    final connected = DeviceConnection.instance.isConnected;
    if (connected && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    } else if (!connected && _connectedAt != null) {
      _connectedAt = null;
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    DeviceConnection.instance.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
