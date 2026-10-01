/// 착용 1회 = 세션 1건. 통계 화면은 전부 이 테이블에서 나옵니다.
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

  /// 판정 근거. 경고 화면에 한 줄로 노출합니다.
  /// 근거 없이 결과만 보여주면 오탐 시 사용자가 앱을 불신하게 됩니다.
  final double perclos;
  final double maxClosedSeconds;

  const DetectionEvent({
    this.id,
    required this.sessionId,
    required this.occurredAt,
    required this.perclos,
    required this.maxClosedSeconds,
  });

  String get reasonLine =>
      '눈 감김 ${maxClosedSeconds.toStringAsFixed(1)}초 · '
      'PERCLOS ${(perclos * 100).round()}%';

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

/// 통계 화면 막대 하나. 데이터가 없는 날도 0으로 채워서 내려보냅니다.
class DailyStat {
  final DateTime day;
  final Duration wornDuration;
  final int detectionCount;

  const DailyStat({
    required this.day,
    required this.wornDuration,
    required this.detectionCount,
  });
}
