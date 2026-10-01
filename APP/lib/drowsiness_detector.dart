/// 졸음 감지 1건이 잡힌 순간의 판정 근거.
class DrowsinessHit {
  const DrowsinessHit({
    required this.at,
    required this.perclos,
    required this.closedSeconds,
  });

  final DateTime at;

  /// 최근 [DrowsinessDetector.perclosWindow] 동안 눈을 감고 있던 비율 (0~1).
  final double perclos;

  /// 이번에 연속으로 눈을 감고 있던 시간(초).
  final double closedSeconds;
}

/// 기기가 보내는 눈 감김 로그로 졸음을 판정한다.
///
/// 펌웨어(DEVICE/device.ino)의 규칙을 그대로 따른다. 로그의 눈 감김 값은 이미
/// 기기 임계값으로 판정된 결과이므로, 연속 횟수만 세면 같은 판정이 나온다.
///  - 감김 [closedTrigger]회 연속 -> 감지 1건 (기기는 이때 경고를 울린다)
///  - 경고 중에는 다시 세지 않고, 눈을 [openRecover]회 연속 뜨면 회복으로 보고 다시 센다
///
/// 기기 상태를 따라가는 계산이라 입력 순서에 의존한다. 착용이 끊기면 [reset]으로
/// 상태를 비워야 다음 착용이 깨끗한 상태에서 시작한다.
class DrowsinessDetector {
  DrowsinessDetector();

  /// 기기의 로그 전송 주기 (device.ino 의 INTERVAL_MS).
  static const Duration frameInterval = Duration(milliseconds: 500);

  /// 연속 감김 횟수가 이 값에 도달하면 감지 1건 (device.ino 의 CLOSED_TRIGGER).
  static const int closedTrigger = 4;

  /// 경고 중 눈을 이만큼 연속으로 뜨면 회복 (device.ino 의 OPEN_RECOVER).
  static const int openRecover = 4;

  /// PERCLOS를 계산하는 구간.
  static const Duration perclosWindow = Duration(seconds: 60);

  int _closedStreak = 0;
  int _openStreak = 0;
  bool _alertActive = false;
  DateTime? _closedSince;

  final List<_EyeSample> _window = [];

  /// 기기 기준으로 지금 졸음 경고가 울리고 있는지.
  bool get isAlerting => _alertActive;

  /// 로그 프레임 한 건을 넣는다. [eyeClosed]가 null이면(눈 추론 값이 없는 프레임)
  /// 판정에 쓰지 않는다. 이 프레임에서 감지가 잡히면 그 근거를 돌려준다.
  DrowsinessHit? add({required DateTime at, required bool? eyeClosed}) {
    if (eyeClosed == null) return null;

    _window
      ..add(_EyeSample(at, eyeClosed))
      ..removeWhere((s) => at.difference(s.at) > perclosWindow);

    if (_alertActive) {
      _openStreak = eyeClosed ? 0 : _openStreak + 1;
      _closedStreak = 0;
      _closedSince = null;
      if (_openStreak >= openRecover) _alertActive = false;
      return null;
    }

    if (!eyeClosed) {
      _closedStreak = 0;
      _closedSince = null;
      return null;
    }

    _closedStreak++;
    final closedSince = _closedSince ??= at;
    if (_closedStreak < closedTrigger) return null;

    _alertActive = true;
    _openStreak = 0;
    // 첫 감김 프레임이 가리키는 구간(0.5초)까지 포함해서 눈 감김 시간을 센다.
    final closedFor = at.difference(closedSince) + frameInterval;
    return DrowsinessHit(
      at: at,
      perclos: _perclos(),
      closedSeconds: closedFor.inMilliseconds / 1000,
    );
  }

  double _perclos() {
    if (_window.isEmpty) return 0;
    return _window.where((s) => s.closed).length / _window.length;
  }

  void reset() {
    _closedStreak = 0;
    _openStreak = 0;
    _alertActive = false;
    _closedSince = null;
    _window.clear();
  }
}

class _EyeSample {
  const _EyeSample(this.at, this.closed);

  final DateTime at;
  final bool closed;
}
