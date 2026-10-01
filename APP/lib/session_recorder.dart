import 'dart:async';

import 'ble_protocol.dart';
import 'connect.dart';
import 'drowsiness_detector.dart';
import 'session.dart';
import 'session_cache.dart';

/// 기기가 500ms 마다 보내는 로그 프레임을 착용 세션 / 졸음 감지 기록으로 바꿔
/// [SessionCache]에 쌓는다. 앱 시작 시 [start]를 한 번 호출하면 된다.
///
/// 착용 여부는 프레임의 `worn`(기기가 근접센서로 확정한 값)을 그대로 쓰고,
/// 졸음 판정은 [DrowsinessDetector]에 맡긴다.
/// TODO(telemetry): 펌웨어가 경고 상태 비트를 보내주면 따라 계산하는 대신
/// 그 값을 그대로 쓴다. 버튼으로 경고를 끈 경우까지 기기와 정확히 일치하게 된다.
class SessionRecorder {
  SessionRecorder._();

  static final SessionRecorder instance = SessionRecorder._();

  /// 프레임이 이보다 오래 끊기면 착용 세션을 닫는다. 기기 전원이 꺼진 경우를 대비한 값.
  static const Duration _frameTimeout = Duration(seconds: 10);

  /// 착용 시간을 갱신하는 주기. 프레임마다(0.5초) 갱신하면 파일 쓰기와 화면 갱신이
  /// 계속 밀리기만 하므로, 이 주기로 묶어서 갱신한다. 세션을 닫을 때는 즉시 갱신한다.
  static const Duration _extendInterval = Duration(seconds: 5);

  final DeviceConnection _connection = DeviceConnection.instance;
  final SessionCache _cache = SessionCache.instance;
  final DrowsinessDetector _detector = DrowsinessDetector();

  bool _started = false;
  StreamSubscription<SensorFrame>? _frameSub;
  Timer? _watchdog;

  int? _sessionId;
  DateTime? _lastFrameAt;
  DateTime? _lastExtendAt;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _cache.load();
    _frameSub = _connection.sensorFrames.listen(_onFrame);
    _connection.addListener(_onConnectionChanged);
    _watchdog = Timer.periodic(_frameTimeout, (_) => _checkStaleFrames());
  }

  void _onConnectionChanged() {
    if (!_connection.isConnected) _endSession();
  }

  /// 기기가 말없이 사라진 경우(전원 꺼짐 등) 마지막 프레임 시각으로 세션을 닫는다.
  void _checkStaleFrames() {
    final lastFrameAt = _lastFrameAt;
    if (_sessionId == null || lastFrameAt == null) return;
    if (DateTime.now().difference(lastFrameAt) > _frameTimeout) _endSession();
  }

  void _onFrame(SensorFrame frame) {
    final now = DateTime.now();
    _lastFrameAt = now;

    if (!frame.worn) {
      _endSession();
      return;
    }

    var sessionId = _sessionId;
    if (sessionId == null) {
      sessionId = _cache.startSession(now);
      _sessionId = sessionId;
      _lastExtendAt = now;
    } else if (now.difference(_lastExtendAt ?? now) >= _extendInterval) {
      _cache.extendSession(sessionId, now);
      _lastExtendAt = now;
    }

    _updateDrowsiness(frame, now, sessionId);
  }

  void _updateDrowsiness(SensorFrame frame, DateTime now, int sessionId) {
    final hit = _detector.add(at: now, eyeClosed: frame.eyeClosed);
    if (hit == null) return;
    _cache.addDetection(
      DetectionEvent(
        sessionId: sessionId,
        occurredAt: hit.at,
        perclos: hit.perclos,
        maxClosedSeconds: hit.closedSeconds,
      ),
    );
  }

  void _endSession() {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final lastFrameAt = _lastFrameAt;
    if (lastFrameAt != null) _cache.extendSession(sessionId, lastFrameAt);
    _sessionId = null;
    _lastExtendAt = null;
    _detector.reset();
    // 착용이 끝난 시점의 기록은 바로 파일에 남긴다.
    _cache.flush();
  }

  void dispose() {
    _frameSub?.cancel();
    _connection.removeListener(_onConnectionChanged);
    _watchdog?.cancel();
    _started = false;
  }
}
