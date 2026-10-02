/// 착용 1회 = 세션 1건. 통계 화면은 세션과 졸음 감지 기록에서 계산한다.
class Session {
  final int? id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int detectionCount;

  const Session({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.detectionCount = 0,
  });

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  Map<String, Object?> toMap() => {
    'id': id,
    'started_at': startedAt.millisecondsSinceEpoch,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'detection_count': detectionCount,
  };

  factory Session.fromMap(Map<String, Object?> m) => Session(
    id: m['id'] as int?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
    endedAt: m['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
    detectionCount: (m['detection_count'] as int?) ?? 0,
  );
}

/// 졸음 감지 1건.
class DetectionEvent {
  final int? id;
  final int sessionId;
  final DateTime occurredAt;

  /// 판정 근거. 화면에는 아직 보여주지 않지만, 감지가 잡힌 이유를 나중에 보여줄 수 있게 함께 저장한다.
  final double perclos;
  final double maxClosedSeconds;

  const DetectionEvent({
    this.id,
    required this.sessionId,
    required this.occurredAt,
    required this.perclos,
    required this.maxClosedSeconds,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
    'perclos': perclos,
    'max_closed_seconds': maxClosedSeconds,
  };

  factory DetectionEvent.fromMap(Map<String, Object?> m) => DetectionEvent(
    id: m['id'] as int?,
    sessionId: m['session_id'] as int,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int),
    perclos: (m['perclos'] as num).toDouble(),
    maxClosedSeconds: (m['max_closed_seconds'] as num).toDouble(),
  );
}
