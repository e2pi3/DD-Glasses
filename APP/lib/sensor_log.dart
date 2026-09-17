import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connect.dart';

/// 기기가 보낸 proximity 값 한 건.
class ProximityLogEntry {
  const ProximityLogEntry({required this.value, required this.timestamp});

  final int value;
  final DateTime timestamp;
}

/// 기기가 500ms 주기로 보내는 IR 근접센서 값을 최근 N개까지 보관하는 로그.
/// 설정 화면의 "로그" 메뉴에서 이 값을 그대로 보여준다.
class ProximityLog extends ChangeNotifier {
  ProximityLog._() {
    _sub = DeviceConnection.instance.proximitySamples.listen((value) {
      entries.insert(0, ProximityLogEntry(value: value, timestamp: DateTime.now()));
      if (entries.length > _maxEntries) entries.removeLast();
      notifyListeners();
    });
  }

  static final ProximityLog instance = ProximityLog._();

  static const int _maxEntries = 200;

  /// 최신 값이 맨 앞에 오도록 보관한다.
  final List<ProximityLogEntry> entries = [];

  late final StreamSubscription<int> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
