import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'session.dart';

/// 착용 세션 / 졸음 감지 기록을 폰 안에만 두는 캐시.
/// 서버로 보내지 않고, 최근 [retentionDays]일치만 남기고 오래된 기록은 지운다.
///
/// 기록은 메모리에 들고 있다가 JSON 파일 한 개로 떨어뜨린다. 7일치 세션과 감지만
/// 담으므로 용량이 작고, 파일을 지워도 앱 동작에는 영향이 없다(기록만 사라진다).
/// 통계 화면은 이 클래스의 알림을 듣고 다시 그린다.
class SessionCache extends ChangeNotifier {
  SessionCache._({
    Future<File> Function()? openFile,
    DateTime Function()? clock,
  }) : _openFile = openFile ?? _defaultFile,
       _now = clock ?? DateTime.now;

  static final SessionCache instance = SessionCache._();

  /// 테스트용. 기록 파일과 기준 시각을 직접 넣어 만든다.
  /// [clock]은 보관 기간이 지난 기록을 지우는 기준이 되는 "지금"이다.
  @visibleForTesting
  factory SessionCache.withFile(File file, {DateTime Function()? clock}) =>
      SessionCache._(openFile: () async => file, clock: clock);

  /// 보관 기간. 오늘을 포함해 이 일수만 남긴다.
  static const int retentionDays = 7;

  static const String _fileName = 'wear_records.json';
  static const int _formatVersion = 1;

  /// 기록이 바뀐 뒤 파일에 쓰기까지 기다리는 시간.
  /// 감지가 몰려도 파일 쓰기가 한 번으로 묶이게 한다.
  static const Duration _saveDelay = Duration(seconds: 2);

  final List<Session> _sessions = [];
  final List<DetectionEvent> _detections = [];

  int _nextSessionId = 1;
  int _nextDetectionId = 1;

  /// 기록을 담을 파일. 폰에서는 앱 전용 폴더, 테스트에서는 임시 폴더를 가리킨다.
  final Future<File> Function() _openFile;
  final DateTime Function() _now;

  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;
  File? _file;

  /// 파일을 다 읽어 기록을 보여줄 수 있는 상태인지.
  bool get isLoaded => _loaded;

  /// 파일을 읽어 메모리에 올린다. 여러 번 불러도 한 번만 읽는다.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?> &&
            decoded['version'] == _formatVersion) {
          _restore(decoded);
        }
      }
    } catch (e) {
      // 파일이 깨졌거나 읽을 수 없으면 기록 없이 시작한다. 기록은 캐시라 복구하지 않는다.
      debugPrint('SessionCache load error: $e');
      _sessions.clear();
      _detections.clear();
    }
    _loaded = true;
    if (_prune()) _scheduleSave();
    notifyListeners();
  }

  void _restore(Map<String, Object?> json) {
    for (final row in (json['sessions'] as List? ?? const [])) {
      _sessions.add(Session.fromMap(Map<String, Object?>.from(row as Map)));
    }
    for (final row in (json['detections'] as List? ?? const [])) {
      _detections.add(
        DetectionEvent.fromMap(Map<String, Object?>.from(row as Map)),
      );
    }
    _nextSessionId =
        _sessions.fold<int>(0, (m, s) => (s.id ?? 0) > m ? s.id! : m) + 1;
    _nextDetectionId =
        _detections.fold<int>(0, (m, d) => (d.id ?? 0) > m ? d.id! : m) + 1;
  }

  Future<File> _resolveFile() async => _file ??= await _openFile();

  static Future<File> _defaultFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 새 착용 세션을 만들고 id를 돌려준다.
  int startSession(DateTime startedAt) {
    final id = _nextSessionId++;
    _sessions.add(Session(id: id, startedAt: startedAt, endedAt: startedAt));
    _changed();
    return id;
  }

  /// 세션의 마지막 착용 확인 시각을 갱신한다. 세션을 끝낼 때도 같은 메서드를 쓴다.
  ///
  /// 앱이 강제 종료돼도 착용 시간이 무한히 늘어나지 않도록, `endedAt`은
  /// "마지막으로 착용이 확인된 시각"으로 둔다.
  void extendSession(int sessionId, DateTime at) {
    _replaceSession(
      sessionId,
      (s) => Session(
        id: s.id,
        startedAt: s.startedAt,
        endedAt: at,
        detectionCount: s.detectionCount,
      ),
    );
  }

  /// 감지 1건을 기록하고 해당 세션의 감지 횟수를 올린다.
  void addDetection(DetectionEvent event) {
    _detections.add(
      DetectionEvent(
        id: _nextDetectionId++,
        sessionId: event.sessionId,
        occurredAt: event.occurredAt,
        perclos: event.perclos,
        maxClosedSeconds: event.maxClosedSeconds,
      ),
    );
    _replaceSession(
      event.sessionId,
      (s) => Session(
        id: s.id,
        startedAt: s.startedAt,
        endedAt: s.endedAt == null || s.endedAt!.isBefore(event.occurredAt)
            ? event.occurredAt
            : s.endedAt,
        detectionCount: s.detectionCount + 1,
      ),
    );
  }

  void _replaceSession(int sessionId, Session Function(Session) update) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index < 0) return;
    _sessions[index] = update(_sessions[index]);
    _changed();
  }

  List<Session> sessionsBetween(DateTime start, DateTime end) =>
      _sessions
          .where(
            (s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end),
          )
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  List<DetectionEvent> detectionsBetween(DateTime start, DateTime end) =>
      _detections
          .where(
            (d) => !d.occurredAt.isBefore(start) && d.occurredAt.isBefore(end),
          )
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  /// 보관 기간이 지난 기록을 지운다. 지운 게 있으면 true.
  bool _prune() {
    final now = _now();
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: retentionDays - 1));

    final removedSessions = _sessions.length;
    _sessions.removeWhere((s) => s.startedAt.isBefore(cutoff));
    final keptIds = _sessions.map((s) => s.id).toSet();
    final removedDetections = _detections.length;
    _detections.removeWhere(
      (d) => d.occurredAt.isBefore(cutoff) || !keptIds.contains(d.sessionId),
    );

    return removedSessions != _sessions.length ||
        removedDetections != _detections.length;
  }

  void _changed() {
    if (!_loaded) return;
    _prune();
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => flush());
  }

  /// 메모리에 있는 기록을 즉시 파일에 쓴다.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded) return;
    final payload = jsonEncode({
      'version': _formatVersion,
      'sessions': [for (final s in _sessions) s.toMap()],
      'detections': [for (final d in _detections) d.toMap()],
    });
    try {
      final file = await _resolveFile();
      // 쓰다가 앱이 죽어도 기존 파일이 깨지지 않도록 임시 파일에 쓴 뒤 교체한다.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('SessionCache save error: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
