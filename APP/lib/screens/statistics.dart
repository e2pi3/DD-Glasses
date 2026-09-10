import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';
import '../widget.dart';

enum _StatsPeriod { today, last7Days, all }

extension on _StatsPeriod {
  String get label => switch (this) {
    _StatsPeriod.today => '오늘',
    _StatsPeriod.last7Days => '최근 7일',
    _StatsPeriod.all => '전체',
  };
}

enum _LoadStatus { loading, data, empty, error }

/// 조회 구간에 필요한 세션 / 감지 기록 접근 인터페이스.
/// 실제 저장소(sqflite 등)가 준비되면 이 인터페이스를 구현한 클래스로 교체한다.
abstract class StatisticsRepository {
  Future<List<Session>> sessionsBetween(DateTime start, DateTime end);
  Future<List<DetectionEvent>> detectionsBetween(DateTime start, DateTime end);
}

/// TODO(statistics): 실제 세션 저장소가 준비되면 교체할 임시 구현.
/// 최근 며칠간의 착용 세션을 임의로 만들어 메모리에 들고 있다가 그대로 반환한다.
/// 오늘 날짜에는 일부러 세션을 만들지 않아, '오늘' 탭에서 빈 상태를 확인할 수 있다.
class _TODOMockStatisticsRepository implements StatisticsRepository {
  _TODOMockStatisticsRepository() {
    _seed();
  }

  final List<Session> _sessions = [];
  final List<DetectionEvent> _detections = [];

  void _seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final random = math.Random(7);
    var sessionId = 1;
    var detectionId = 1;

    for (var daysAgo = 1; daysAgo <= 40; daysAgo++) {
      if (random.nextDouble() < 0.15) continue;

      final day = today.subtract(Duration(days: daysAgo));
      final startHour = 7 + random.nextInt(14);
      final startedAt = day.add(
        Duration(hours: startHour, minutes: random.nextInt(60)),
      );
      final wornMinutes = 20 + random.nextInt(220);
      final endedAt = startedAt.add(Duration(minutes: wornMinutes));
      final detectionCount = random.nextInt(4);

      final id = sessionId++;
      _sessions.add(
        Session(
          id: id,
          startedAt: startedAt,
          endedAt: endedAt,
          detectionCount: detectionCount,
        ),
      );

      for (var d = 0; d < detectionCount; d++) {
        final offsetMinutes = random.nextInt(wornMinutes);
        _detections.add(
          DetectionEvent(
            id: detectionId++,
            sessionId: id,
            occurredAt: startedAt.add(Duration(minutes: offsetMinutes)),
            perclos: 0.3 + random.nextDouble() * 0.4,
            maxClosedSeconds: 1.0 + random.nextDouble() * 2.0,
            headDrop: random.nextBool(),
          ),
        );
      }
    }
  }

  @override
  Future<List<Session>> sessionsBetween(DateTime start, DateTime end) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _sessions
        .where((s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end))
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  @override
  Future<List<DetectionEvent>> detectionsBetween(
    DateTime start,
    DateTime end,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _detections
        .where((d) => !d.occurredAt.isBefore(start) && d.occurredAt.isBefore(end))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }
}

/// 통계 화면. 기간(오늘/최근 7일/전체)을 고르면 착용 요약, 막대 그래프,
/// 날짜별 세션 목록을 다시 불러와 보여준다.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatisticsRepository _repository = _TODOMockStatisticsRepository();

  _StatsPeriod _period = _StatsPeriod.last7Days;
  _LoadStatus _status = _LoadStatus.loading;
  List<Session> _sessions = const [];
  List<DetectionEvent> _detections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({DateTime start, DateTime end}) _rangeFor(_StatsPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));
    return switch (period) {
      _StatsPeriod.today => (start: today, end: end),
      _StatsPeriod.last7Days => (
        start: today.subtract(const Duration(days: 6)),
        end: end,
      ),
      _StatsPeriod.all => (
        start: today.subtract(const Duration(days: 55)),
        end: end,
      ),
    };
  }

  Future<void> _load() async {
    setState(() => _status = _LoadStatus.loading);
    final range = _rangeFor(_period);
    try {
      final sessions = await _repository.sessionsBetween(range.start, range.end);
      final detections = await _repository.detectionsBetween(
        range.start,
        range.end,
      );
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _detections = detections;
        _status = sessions.isEmpty ? _LoadStatus.empty : _LoadStatus.data;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _LoadStatus.error);
    }
  }

  void _onPeriodChanged(_StatsPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('통계', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _PeriodControl(value: _period, onChanged: _onPeriodChanged),
        const SizedBox(height: 16),
        switch (_status) {
          _LoadStatus.loading => const _LoadingView(),
          _LoadStatus.error => _ErrorView(onRetry: _load),
          _LoadStatus.empty => const _EmptyView(),
          _LoadStatus.data => _StatsContent(
            period: _period,
            sessions: _sessions,
            detections: _detections,
          ),
        },
      ],
    );
  }
}

class _PeriodControl extends StatelessWidget {
  const _PeriodControl({required this.value, required this.onChanged});

  final _StatsPeriod value;
  final ValueChanged<_StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final period in _StatsPeriod.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: period == value
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: period == value
                          ? colorScheme.primary
                          : AppColors.textSecondary,
                      fontWeight: period == value
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            '통계를 불러오지 못했습니다',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.query_stats_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            '아직 측정 기록이 없습니다',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '기기를 착용하고 측정을 시작해보세요',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 하나의 막대(시간대/일자/주)에 대응하는 집계 값.
class _ChartBucket {
  const _ChartBucket({
    required this.start,
    required this.end,
    required this.label,
    required this.count,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final int count;

  bool get isCurrent {
    final now = DateTime.now();
    return !now.isBefore(start) && now.isBefore(end);
  }
}

class _DaySummary {
  _DaySummary(this.day);

  final DateTime day;
  Duration wornDuration = Duration.zero;
  final List<DateTime> detectionTimes = [];
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.period,
    required this.sessions,
    required this.detections,
  });

  final _StatsPeriod period;
  final List<Session> sessions;
  final List<DetectionEvent> detections;

  static const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _monthDay(DateTime d) => '${_two(d.month)}-${_two(d.day)}';

  static String _hoursMinutesKorean(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours <= 0) return '$minutes분';
    if (minutes <= 0) return '$hours시간';
    return '$hours시간 $minutes분';
  }

  List<_ChartBucket> _buildBuckets() {
    switch (period) {
      case _StatsPeriod.today:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return [
          for (var h = 0; h < 24; h++)
            _bucket(
              today.add(Duration(hours: h)),
              const Duration(hours: 1),
              '$h시',
            ),
        ];
      case _StatsPeriod.last7Days:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(const Duration(days: 6));
        return [
          for (var i = 0; i < 7; i++)
            _bucket(
              start.add(Duration(days: i)),
              const Duration(days: 1),
              _monthDay(start.add(Duration(days: i))),
            ),
        ];
      case _StatsPeriod.all:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final rangeStart = today.subtract(const Duration(days: 55));
        var weekStart = rangeStart.subtract(
          Duration(days: rangeStart.weekday - 1),
        );
        final buckets = <_ChartBucket>[];
        final end = today.add(const Duration(days: 1));
        while (weekStart.isBefore(end)) {
          buckets.add(
            _bucket(weekStart, const Duration(days: 7), '${_monthDay(weekStart)}주'),
          );
          weekStart = weekStart.add(const Duration(days: 7));
        }
        return buckets;
    }
  }

  _ChartBucket _bucket(DateTime start, Duration span, String label) {
    final end = start.add(span);
    final count = detections
        .where((d) => !d.occurredAt.isBefore(start) && d.occurredAt.isBefore(end))
        .length;
    return _ChartBucket(start: start, end: end, label: label, count: count);
  }

  List<_DaySummary> _buildDaySummaries() {
    final byDay = <DateTime, _DaySummary>{};

    for (final session in sessions) {
      final day = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      final summary = byDay.putIfAbsent(day, () => _DaySummary(day));
      summary.wornDuration += session.duration;
    }

    for (final detection in detections) {
      final day = DateTime(
        detection.occurredAt.year,
        detection.occurredAt.month,
        detection.occurredAt.day,
      );
      final summary = byDay[day];
      summary?.detectionTimes.add(detection.occurredAt);
    }

    for (final summary in byDay.values) {
      summary.detectionTimes.sort();
    }

    return byDay.values.toList()..sort((a, b) => b.day.compareTo(a.day));
  }

  @override
  Widget build(BuildContext context) {
    final totalWorn = sessions.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + s.duration,
    );
    final buckets = _buildBuckets();
    final days = _buildDaySummaries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryRow(totalWorn: totalWorn, detectionCount: detections.length),
        const SizedBox(height: 16),
        _BarChartCard(buckets: buckets),
        const SizedBox(height: 16),
        Text('세션 기록', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.divider,
                  ),
                _DayRow(
                  title:
                      '${_monthDay(days[i].day)} ${_weekdayLabels[days[i].day.weekday - 1]} · '
                      '${_hoursMinutesKorean(days[i].wornDuration)}',
                  subtitle: days[i].detectionTimes.isEmpty
                      ? '감지 없음'
                      : '감지 ${days[i].detectionTimes.length}회 · '
                            '${days[i].detectionTimes.map((t) => '${_two(t.hour)}:${_two(t.minute)}').join(', ')}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.totalWorn, required this.detectionCount});

  final Duration totalWorn;
  final int detectionCount;

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hours = _two(totalWorn.inHours);
    final minutes = _two(totalWorn.inMinutes.remainder(60));

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(label: '총 착용 시간', value: '$hours:$minutes'),
          ),
          const SizedBox(
            height: 48,
            child: VerticalDivider(thickness: 1, color: AppColors.divider),
          ),
          Expanded(
            child: _SummaryStat(label: '감지 횟수', value: '$detectionCount'),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 22),
        ),
      ],
    );
  }
}

class _BarChartCard extends StatelessWidget {
  const _BarChartCard({required this.buckets});

  final List<_ChartBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dataMax = buckets.fold<int>(
      0,
      (max, b) => b.count > max ? b.count : max,
    );
    final maxY = math.max(dataMax + 1, 3).toDouble();
    final labelStep = (buckets.length / 8).ceil().clamp(1, buckets.length);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              horizontalInterval: 1,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  const FlLine(color: AppColors.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      value.toInt().toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 ||
                        index >= buckets.length ||
                        index % labelStep != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        buckets[index].label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.textPrimary,
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${rod.toY.toInt()}회',
                      TextStyle(
                        color: colorScheme.surface,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < buckets.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: buckets[i].count.toDouble(),
                      color: buckets[i].isCurrent
                          ? colorScheme.primary
                          : AppColors.textSecondary.withValues(alpha: 0.4),
                      width: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
