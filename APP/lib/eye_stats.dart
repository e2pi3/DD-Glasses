/// 기기가 보내는 눈 감김 로그를 모아 판정 근거를 계산한다.
///
/// 졸음 판정 자체는 기기가 하고 앱은 경고 비트를 그대로 쓴다(ble_protocol.dart의
/// `SensorFrame.alerting`). 이 클래스는 감지가 잡힌 순간 "왜 그랬는지"를 함께
/// 기록하기 위한 값만 낸다.
class EyeStats {
  EyeStats();

  /// 기기의 로그 전송 주기 (device.ino 의 INTERVAL_MS).
  static const Duration frameInterval = Duration(milliseconds: 500);

  /// PERCLOS를 계산하는 구간.
  static const Duration perclosWindow = Duration(seconds: 60);

  final List<_EyeSample> _window = [];
  DateTime? _closedSince;
  DateTime? _lastClosedAt;

  /// 로그 프레임 한 건을 넣는다. [eyeClosed]가 null이면(눈 추론 값이 없는 프레임)
  /// 카메라가 깨어나는 중이므로 셈에 넣지 않는다.
  void add({required DateTime at, required bool? eyeClosed}) {
    if (eyeClosed == null) return;

    _window
      ..add(_EyeSample(at, eyeClosed))
      ..removeWhere((s) => at.difference(s.at) > perclosWindow);

    if (eyeClosed) {
      _closedSince ??= at;
      _lastClosedAt = at;
    } else {
      _closedSince = null;
      _lastClosedAt = null;
    }
  }

  /// 최근 [perclosWindow] 동안 눈을 감고 있던 비율 (0~1).
  double get perclos {
    if (_window.isEmpty) return 0;
    return _window.where((s) => s.closed).length / _window.length;
  }

  /// 지금까지 연속으로 눈을 감고 있는 시간(초). 눈을 뜨고 있으면 0.
  /// 첫 감김 프레임이 가리키는 구간(0.5초)까지 포함해서 센다.
  double get closedSeconds {
    final since = _closedSince;
    final last = _lastClosedAt;
    if (since == null || last == null) return 0;
    return (last.difference(since) + frameInterval).inMilliseconds / 1000;
  }

  void reset() {
    _window.clear();
    _closedSince = null;
    _lastClosedAt = null;
  }
}

class _EyeSample {
  const _EyeSample(this.at, this.closed);

  final DateTime at;
  final bool closed;
}
