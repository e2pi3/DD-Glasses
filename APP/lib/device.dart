import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_protocol.dart';
import 'connect.dart';

/// 졸음감지 보안경(엣지 디바이스)이 보내는 상태/신호 정보를 담는 모델.
/// 홈 화면 등에서 이 값을 구독해서 화면에 표시한다. 연결 자체의 상태는
/// [DeviceConnection](connect.dart)이 담당하고, 이 클래스는 연결된 기기가
/// 보내는 데이터(배터리, 눈 상태, 러닝타임 등)만 담는다.
class DeviceInfo extends ChangeNotifier {
  DeviceInfo._() {
    final connection = DeviceConnection.instance;
    connection.addListener(_onConnectionChanged);
    _batterySub = connection.batteryLevels.listen((level) {
      batteryLevel = level.clamp(0, 100);
      notifyListeners();
    });
    _eyeStateSub = connection.eyeStates.listen((state) {
      eyeState = state;
      notifyListeners();
    });
  }

  static final DeviceInfo instance = DeviceInfo._();

  /// 기기에서 받은 배터리 잔량(%). 아직 받지 못했으면 null.
  int? batteryLevel;

  /// 기기에서 받은 가장 최근 눈 상태. 아직 받지 못했으면 null.
  EyeState? eyeState;

  StreamSubscription<int>? _batterySub;
  StreamSubscription<EyeState>? _eyeStateSub;

  DateTime? _connectedAt;
  Timer? _ticker;

  /// 기기가 연결된 시점부터 흐른 시간. 연결되어 있지 않으면 0이다.
  Duration get runningTime {
    final connectedAt = _connectedAt;
    return connectedAt == null
        ? Duration.zero
        : DateTime.now().difference(connectedAt);
  }

  void _onConnectionChanged() {
    final connected = DeviceConnection.instance.isConnected;
    if (connected && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else if (!connected && _connectedAt != null) {
      _connectedAt = null;
      _ticker?.cancel();
      _ticker = null;
      batteryLevel = null;
      eyeState = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _batterySub?.cancel();
    _eyeStateSub?.cancel();
    DeviceConnection.instance.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
