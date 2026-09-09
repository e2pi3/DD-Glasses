import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble.dart';
import 'connect.dart';

/// 졸음감지 보안경(엣지 디바이스)이 보내는 상태/신호 정보를 담는 모델.
/// 홈 화면 등에서 이 값을 구독해서 화면에 표시한다. 연결 자체의 상태는
/// [DeviceConnection](connect.dart)이 담당하고, 이 클래스는 연결된 기기가
/// 보내는 데이터(배터리, 러닝타임 등)만 담는다.
class DeviceInfo extends ChangeNotifier {
  DeviceInfo._() {
    DeviceConnection.instance.addListener(_onConnectionChanged);
    _statusSub = DeviceConnection.instance.client.status.listen(_onStatus);
    _metricsSub = DeviceConnection.instance.client.metrics.listen(_onMetrics);
  }

  static final DeviceInfo instance = DeviceInfo._();

  /// Status 알림(1Hz)이 아직 한 번도 안 왔을 때의 기본값.
  int batteryLevel = 100;

  /// 가장 최근 20바이트 프레임. PERCLOS·위험도 등을 쓰는 화면(통계 등)이
  /// 생기면 이걸 구독하면 된다. 지금 홈/설정 화면은 배터리·러닝타임만 쓴다.
  LiveMetrics? latestMetrics;

  DateTime? _connectedAt;
  Timer? _ticker;
  StreamSubscription<DeviceStatus>? _statusSub;
  StreamSubscription<LiveMetrics>? _metricsSub;

  /// 기기가 연결된 시점부터 흐른 시간. 연결되어 있지 않으면 0이다.
  Duration get runningTime {
    final connectedAt = _connectedAt;
    return connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt);
  }

  void _onStatus(DeviceStatus status) {
    batteryLevel = status.batteryPct;
    notifyListeners();
  }

  void _onMetrics(LiveMetrics metrics) {
    latestMetrics = metrics;
    // Status는 1Hz라 그 사이 공백을 Live Metrics의 배터리 필드로 메운다.
    batteryLevel = metrics.batteryPct;
    notifyListeners();
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
      latestMetrics = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _statusSub?.cancel();
    _metricsSub?.cancel();
    DeviceConnection.instance.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
