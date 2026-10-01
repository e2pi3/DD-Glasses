import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_protocol.dart';
import 'connect.dart';

/// 기기가 보낸 센서 프레임 한 건.
class SensorLogEntry {
  const SensorLogEntry({required this.frame, required this.timestamp});

  final SensorFrame frame;
  final DateTime timestamp;

  /// 로그 화면에 그대로 보여줄 한 줄 요약. 값이 없는 센서는 `--`.
  String get summary {
    final f = frame;
    String fmt(List<double>? v, int digits) =>
        v == null ? '--' : v.map((e) => e.toStringAsFixed(digits)).join(' ');

    final eye = f.eyeClosed == null
        ? '--'
        : '${f.eyeClosed! ? '감김' : '뜸'} p=${f.closedProbability!.toStringAsFixed(2)}';
    final alert = f.alerting
        ? (f.buttonReacted ? '경고(버튼 반응)' : '경고 중')
        : (f.buttonReacted ? '버튼 반응' : '없음');
    return '착용: ${f.worn ? '중' : '아님'}\n'
        '눈: $eye\n'
        '졸음: $alert\n'
        'prox: ${f.proximity?.toString() ?? '--'}\n'
        'acc(m/s²): ${fmt(f.accel, 2)}\n'
        'gyro(rad/s): ${fmt(f.gyro, 3)}';
  }
}

/// 기기가 500ms 주기로 보내는 센서/추론 프레임을 최근 N개까지 보관하는 로그.
/// 설정 화면의 "로그" 메뉴에서 이 값을 그대로 보여준다.
class SensorLog extends ChangeNotifier {
  SensorLog._() {
    _sub = DeviceConnection.instance.sensorFrames.listen((frame) {
      entries.insert(
        0,
        SensorLogEntry(frame: frame, timestamp: DateTime.now()),
      );
      if (entries.length > _maxEntries) entries.removeLast();
      notifyListeners();
    });
  }

  static final SensorLog instance = SensorLog._();

  static const int _maxEntries = 200;

  /// 최신 값이 맨 앞에 오도록 보관한다.
  final List<SensorLogEntry> entries = [];

  late final StreamSubscription<SensorFrame> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
