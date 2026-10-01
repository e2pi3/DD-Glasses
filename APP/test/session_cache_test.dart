import 'dart:convert';
import 'dart:io';

import 'package:dd_glasses/session.dart';
import 'package:dd_glasses/session_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  /// 기록이 쌓이는 동안 시간이 흐르지 않게 기준 시각을 고정한다.
  final now = DateTime(2026, 10, 1, 14);
  DateTime day(int daysAgo) =>
      DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));

  SessionCache open() => SessionCache.withFile(file, clock: () => now);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dd_glasses_cache_test');
    file = File('${dir.path}/wear_records.json');
  });

  tearDown(() async => dir.delete(recursive: true));

  group('SessionCache 저장/불러오기', () {
    test('기록이 없으면 빈 상태로 시작한다', () async {
      final cache = open();
      await cache.load();

      expect(cache.isLoaded, isTrue);
      expect(cache.sessionsBetween(day(7), now), isEmpty);
      expect(file.existsSync(), isFalse);
    });

    test('저장한 기록을 다시 읽어올 수 있다', () async {
      final cache = open();
      await cache.load();
      final id = cache.startSession(day(0).add(const Duration(hours: 9)));
      cache.extendSession(id, day(0).add(const Duration(hours: 10)));
      cache.addDetection(
        DetectionEvent(
          sessionId: id,
          occurredAt: day(0).add(const Duration(hours: 9, minutes: 30)),
          perclos: 0.5,
          maxClosedSeconds: 2,
        ),
      );
      await cache.flush();

      final reopened = open();
      await reopened.load();
      final sessions = reopened.sessionsBetween(day(7), now);
      final detections = reopened.detectionsBetween(day(7), now);

      expect(sessions, hasLength(1));
      expect(sessions.single.duration, const Duration(hours: 1));
      expect(sessions.single.detectionCount, 1);
      expect(detections, hasLength(1));
      expect(detections.single.sessionId, sessions.single.id);
      expect(detections.single.maxClosedSeconds, 2);
      expect(detections.single.perclos, 0.5);
    });

    test('다시 읽은 뒤 만든 세션도 id가 겹치지 않는다', () async {
      final cache = open();
      await cache.load();
      final first = cache.startSession(day(1));
      await cache.flush();

      final reopened = open();
      await reopened.load();
      final second = reopened.startSession(day(0));

      expect(second, isNot(first));
      expect(reopened.sessionsBetween(day(7), now), hasLength(2));
    });

    test('파일이 깨져 있으면 기록 없이 시작한다', () async {
      await file.writeAsString('{ 이건 JSON 이 아니다');

      final cache = open();
      await cache.load();

      expect(cache.isLoaded, isTrue);
      expect(cache.sessionsBetween(day(7), now), isEmpty);
    });

    test('저장 후 임시 파일을 남기지 않는다', () async {
      final cache = open();
      await cache.load();
      cache.startSession(day(0));
      await cache.flush();

      final names = dir.listSync().map((e) => e.path.split('/').last).toList();

      expect(names, ['wear_records.json']);
    });
  });

  group('SessionCache 보관 기간', () {
    /// 세션 1건과 그 세션의 감지 1건을 담은 파일을 직접 만든다.
    Future<void> writeRecords(List<({int id, DateTime at})> rows) async {
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'sessions': [
            for (final row in rows)
              Session(
                id: row.id,
                startedAt: row.at,
                endedAt: row.at.add(const Duration(hours: 1)),
                detectionCount: 1,
              ).toMap(),
          ],
          'detections': [
            for (final row in rows)
              DetectionEvent(
                id: row.id,
                sessionId: row.id,
                occurredAt: row.at.add(const Duration(minutes: 10)),
                perclos: 0.4,
                maxClosedSeconds: 2,
              ).toMap(),
          ],
        }),
      );
    }

    test('보관 기간이 지난 기록은 읽을 때 지워진다', () async {
      await writeRecords([
        (id: 1, at: day(30)), // 보관 기간 밖
        (id: 2, at: day(7)), // 7일 전은 오늘 포함 8일째라 밖
        (id: 3, at: day(6)), // 경계: 남는다
        (id: 4, at: day(0)),
      ]);

      final cache = open();
      await cache.load();
      final kept = cache.sessionsBetween(day(30), now);

      expect(kept.map((s) => s.id), [3, 4]);
    });

    test('세션이 지워지면 그 세션의 감지도 함께 지워진다', () async {
      await writeRecords([
        (id: 1, at: day(30)),
        (id: 2, at: day(0)),
      ]);

      final cache = open();
      await cache.load();

      expect(cache.detectionsBetween(day(30), now).map((d) => d.sessionId), [
        2,
      ]);
    });

    test('지워진 기록은 파일에도 남지 않는다', () async {
      await writeRecords([
        (id: 1, at: day(30)),
        (id: 2, at: day(0)),
      ]);

      final cache = open();
      await cache.load();
      await cache.flush();

      final saved = jsonDecode(await file.readAsString()) as Map;

      expect((saved['sessions'] as List), hasLength(1));
      expect((saved['detections'] as List), hasLength(1));
    });
  });

  group('SessionCache 조회', () {
    test('구간 밖의 기록은 돌려주지 않는다', () async {
      final cache = open();
      await cache.load();
      cache.startSession(day(3));
      cache.startSession(day(0));

      final todayOnly = cache.sessionsBetween(
        day(0),
        day(0).add(const Duration(days: 1)),
      );

      expect(todayOnly, hasLength(1));
      expect(todayOnly.single.startedAt, day(0));
    });

    test('감지를 기록하면 세션의 감지 횟수가 올라간다', () async {
      final cache = open();
      await cache.load();
      final id = cache.startSession(day(0));

      for (var i = 0; i < 3; i++) {
        cache.addDetection(
          DetectionEvent(
            sessionId: id,
            occurredAt: day(0).add(Duration(minutes: i * 5)),
            perclos: 0.4,
            maxClosedSeconds: 2,
          ),
        );
      }

      expect(cache.sessionsBetween(day(7), now).single.detectionCount, 3);
      expect(cache.detectionsBetween(day(7), now), hasLength(3));
    });

    test('감지 시각이 착용 시간보다 늦으면 착용 시간을 늘린다', () async {
      final cache = open();
      await cache.load();
      final id = cache.startSession(day(0));

      cache.addDetection(
        DetectionEvent(
          sessionId: id,
          occurredAt: day(0).add(const Duration(minutes: 30)),
          perclos: 0.4,
          maxClosedSeconds: 2,
        ),
      );

      expect(
        cache.sessionsBetween(day(7), now).single.duration,
        const Duration(minutes: 30),
      );
    });

    test('기록을 바꾸면 통계 화면에 알린다', () async {
      final cache = open();
      await cache.load();
      var notified = 0;
      cache.addListener(() => notified++);

      final id = cache.startSession(day(0));
      cache.extendSession(id, day(0).add(const Duration(hours: 1)));

      expect(notified, 2);
    });
  });
}
