import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../session.dart';
import '../session_cache.dart';
import '../session_recorder.dart';
import '../theme.dart';
import '../widget.dart';

/// 기록은 [SessionCache.retentionDays]일치만 남기므로 그보다 긴 구간은 두지 않는다.
enum _StatsPeriod { today, last7Days }

extension on _StatsPeriod {
  String get label => switch (this) {
    _StatsPeriod.today => '오늘',
    _StatsPeriod.last7Days => '최근 7일',
  };
}

/// 통계 화면. 기간(오늘/최근 7일)을 고르면 착용 요약, 졸음이 많은 시간대,
/// 막대 그래프, 날짜별 기록을 보여준다.
///
/// 값은 SessionRecorder가 기기 로그로부터 쌓은 [SessionCache]에서 읽는다.
/// 이 화면은 하단 탭의 IndexedStack 안에서 안 보일 때도 살아 있으므로, [active]가 false인
/// 동안에는 기록이 바뀌어도 다시 그리지 않고 보이게 될 때 한 번에 그린다.
/// 착용 중에는 진행 중인 세션의 시간을 1초마다 스스로 계산해서 초 단위까지 보여준다.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.active});

  /// 이 탭이 지금 화면에 보이는지.
  final bool active;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final SessionCache _cache = SessionCache.instance;

  _StatsPeriod _period = _StatsPeriod.last7Days;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCacheChanged);
    _cache.load();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant StatisticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncTicker();
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onCacheChanged() {
    // 안 보이는 동안 바뀐 기록은 탭으로 돌아올 때 build 가 다시 읽는다.
    if (mounted && widget.active) setState(() {});
  }

  /// 화면이 보이는 동안에만 1초 타이머를 돌려, 착용 중인 세션의 초 단위를 갱신한다.
  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!widget.active) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (SessionRecorder.instance.activeSessionId != null && mounted) {
        setState(() {});
      }
    });
  }

  ({DateTime start, DateTime end}) _rangeFor(_StatsPeriod period, DateTime today) {
    final end = today.add(const Duration(days: 1));
    return switch (period) {
      _StatsPeriod.today => (start: today, end: end),
      _StatsPeriod.last7Days => (
        start: today.subtract(
          const Duration(days: SessionCache.retentionDays - 1),
        ),
        end: end,
      ),
    };
  }

  void _onPeriodChanged(_StatsPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = _rangeFor(_period, today);
    final sessions = _cache.sessionsBetween(range.start, range.end);
    final activeId = SessionRecorder.instance.activeSessionId;

    // 진행 중인 세션은 기록된 종료 시각이 몇 초~수십 초 늦으므로 지금 시각으로 계산한다.
    Duration durationOf(Session s) =>
        s.id == activeId ? now.difference(s.startedAt) : s.duration;

    // "어제 N회" 비교는 어제 착용 기록이 있을 때만 보여준다.
    int? yesterdayCount;
    if (_period == _StatsPeriod.today) {
      final yesterday = today.subtract(const Duration(days: 1));
      if (_cache.sessionsBetween(yesterday, today).isNotEmpty) {
        yesterdayCount = _cache.detectionsBetween(yesterday, today).length;
      }
    }

    return ListView(
      // Scaffold(extendBody)가 body 의 MediaQuery 에 하단 바 높이를 더해 주므로, 그만큼 띄워야 끝까지 스크롤된다.
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        _PeriodControl(value: _period, onChanged: _onPeriodChanged),
        const SizedBox(height: 16),
        if (!_cache.isLoaded)
          const _LoadingView()
        else if (sessions.isEmpty)
          const _EmptyView()
        else
          _StatsContent(
            period: _period,
            today: today,
            sessions: sessions,
            detections: _cache.detectionsBetween(range.start, range.end),
            durationOf: durationOf,
            yesterdayCount: yesterdayCount,
          ),
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

/// 하나의 막대(시간대/일자)에 대응하는 집계 값.
class _ChartBucket {
  const _ChartBucket({
    required this.start,
    required this.end,
    required this.label,
    required this.count,
    required this.wornMinutes,
  });

  final DateTime start;
  final DateTime end;
  final String label;

  /// 이 구간의 졸음 감지 횟수.
  final int count;

  /// 이 구간에 시작한 세션의 착용 시간(분). 일별 차트에서만 쓴다.
  final double wornMinutes;

  bool isCurrent(DateTime now) => !now.isBefore(start) && now.isBefore(end);
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
    required this.today,
    required this.sessions,
    required this.detections,
    required this.durationOf,
    required this.yesterdayCount,
  });

  final _StatsPeriod period;
  final DateTime today;
  final List<Session> sessions;
  final List<DetectionEvent> detections;
  final Duration Function(Session) durationOf;

  /// 어제 감지 횟수. 어제 착용 기록이 없으면 null.
  final int? yesterdayCount;

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  static String _monthDay(DateTime d) => '${two(d.month)}-${two(d.day)}';

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  List<_ChartBucket> _buildBuckets() {
    switch (period) {
      case _StatsPeriod.today:
        return [
          for (var h = 0; h < 24; h++)
            _bucket(
              today.add(Duration(hours: h)),
              const Duration(hours: 1),
              '$h시',
            ),
        ];
      case _StatsPeriod.last7Days:
        const days = SessionCache.retentionDays;
        final start = today.subtract(const Duration(days: days - 1));
        return [
          for (var i = 0; i < days; i++)
            _bucket(
              start.add(Duration(days: i)),
              const Duration(days: 1),
              _monthDay(start.add(Duration(days: i))),
            ),
        ];
    }
  }

  _ChartBucket _bucket(DateTime start, Duration span, String label) {
    final end = start.add(span);
    final count = detections
        .where(
          (d) => !d.occurredAt.isBefore(start) && d.occurredAt.isBefore(end),
        )
        .length;
    final worn = sessions
        .where((s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end))
        .fold<Duration>(Duration.zero, (sum, s) => sum + durationOf(s));
    return _ChartBucket(
      start: start,
      end: end,
      label: label,
      count: count,
      wornMinutes: worn.inSeconds / 60,
    );
  }

  List<_DaySummary> _buildDaySummaries() {
    final byDay = <DateTime, _DaySummary>{};

    for (final session in sessions) {
      final day = _dayOf(session.startedAt);
      byDay.putIfAbsent(day, () => _DaySummary(day)).wornDuration +=
          durationOf(session);
    }

    for (final detection in detections) {
      byDay[_dayOf(detection.occurredAt)]?.detectionTimes.add(
        detection.occurredAt,
      );
    }

    for (final summary in byDay.values) {
      summary.detectionTimes.sort();
    }

    return byDay.values.toList()..sort((a, b) => b.day.compareTo(a.day));
  }

  /// 감지가 가장 많았던 시각(시)과 그 횟수. 같으면 이른 시각. 감지가 없으면 null.
  ({int hour, int count})? _peakHour() {
    if (detections.isEmpty) return null;
    final perHour = List<int>.filled(24, 0);
    for (final d in detections) {
      perHour[d.occurredAt.hour]++;
    }
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (perHour[h] > perHour[best]) best = h;
    }
    return (hour: best, count: perHour[best]);
  }

  @override
  Widget build(BuildContext context) {
    final totalWorn = sessions.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + durationOf(s),
    );
    final days = _buildDaySummaries();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryCard(
          totalWorn: totalWorn,
          detectionCount: detections.length,
          yesterdayCount: yesterdayCount,
        ),
        const SizedBox(height: 12),
        _InsightCard(peak: _peakHour()),
        const SizedBox(height: 16),
        Text(
          period == _StatsPeriod.today ? '시간대별 감지 횟수' : '일별 착용 시간',
          style: textTheme.titleMedium,
        ),
        if (period == _StatsPeriod.last7Days)
          Text('막대 아래 빨간 숫자는 졸음 감지 횟수', style: textTheme.bodySmall),
        const SizedBox(height: 8),
        _BarChartCard(
          buckets: _buildBuckets(),
          byWornTime: period == _StatsPeriod.last7Days,
        ),
        const SizedBox(height: 16),
        Text('일별 기록', style: textTheme.titleMedium),
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
                      '${formatKorean(days[i].wornDuration)}',
                  subtitle: days[i].detectionTimes.isEmpty
                      ? '감지 없음'
                      : '감지 ${days[i].detectionTimes.length}회 · '
                            '${days[i].detectionTimes.map((t) => '${two(t.hour)}:${two(t.minute)}').join(', ')}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 총 착용 시간(초 단위)을 크게, 감지 횟수와 착용 1시간당 감지 횟수를 아래에 보여준다.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalWorn,
    required this.detectionCount,
    required this.yesterdayCount,
  });

  final Duration totalWorn;
  final int detectionCount;
  final int? yesterdayCount;

  /// 착용이 1분도 안 되면 시간당 횟수가 의미 없이 튀므로 표시하지 않는다.
  String get _ratePerHour {
    if (totalWorn.inSeconds < 60) return '-';
    final rate = detectionCount / (totalWorn.inSeconds / 3600);
    return '${rate.toStringAsFixed(1)}회';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('총 착용 시간', style: textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            formatHms(totalWorn),
            style: textTheme.titleMedium?.copyWith(
              fontSize: 36,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: '감지 횟수',
                  value: '$detectionCount회',
                  caption: yesterdayCount == null ? null : '어제 $yesterdayCount회',
                ),
              ),
              const SizedBox(
                height: 48,
                child: VerticalDivider(thickness: 1, color: AppColors.divider),
              ),
              Expanded(
                child: _SummaryStat(label: '착용 1시간당', value: _ratePerHour),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: textTheme.titleMedium?.copyWith(fontSize: 22)),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// 졸음이 가장 많았던 시간대 한 줄. 감지가 없으면 칭찬 문구를 보여준다.
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.peak});

  final ({int hour, int count})? peak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final peak = this.peak;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(
            peak == null ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: peak == null ? colorScheme.primary : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              peak == null
                  ? '졸음 감지 없이 안전하게 착용했어요'
                  : '졸음이 가장 많은 시간대 · ${peak.hour}시 (${peak.count}회)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 오늘은 시간대별 감지 횟수, 최근 7일은 일별 착용 시간(분)을 막대로 그린다.
/// 일별 차트는 막대 아래 라벨에 그날의 감지 횟수를 빨간 숫자로 함께 보여준다.
class _BarChartCard extends StatelessWidget {
  const _BarChartCard({required this.buckets, required this.byWornTime});

  final List<_ChartBucket> buckets;
  final bool byWornTime;

  /// 착용 시간 축의 눈금 간격(분) 후보. 눈금이 4개 안팎이 되는 가장 작은 값을 쓴다.
  static const List<double> _minuteSteps = [30, 60, 120, 240, 480, 960];

  double _valueOf(_ChartBucket b) => byWornTime ? b.wornMinutes : b.count.toDouble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();

    final dataMax = buckets.map(_valueOf).fold<double>(0, math.max);
    final double interval;
    final double maxY;
    if (byWornTime) {
      final step = _minuteSteps.firstWhere(
        (s) => dataMax / s <= 4,
        orElse: () => _minuteSteps.last,
      );
      interval = step;
      maxY = math.max((dataMax / step).ceil(), 1) * step;
    } else {
      interval = 1;
      maxY = math.max(dataMax + 1, 3);
    }
    // 시간대 차트는 24개 라벨이 겹치므로 6시간마다만 보여준다.
    final labelStep = byWornTime ? 1 : 6;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
      child: SizedBox(
        height: byWornTime ? 230 : 200,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              horizontalInterval: interval,
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
                  interval: interval,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    final text = !byWornTime
                        ? value.toInt().toString()
                        : (value % 60 == 0
                              ? '${value ~/ 60}시간'
                              : '${value.toInt()}분');
                    return Text(text, style: textTheme.bodySmall);
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: byWornTime ? 46 : 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 ||
                        index >= buckets.length ||
                        index % labelStep != 0) {
                      return const SizedBox.shrink();
                    }
                    final bucket = buckets[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(bucket.label, style: textTheme.bodySmall),
                          if (byWornTime && bucket.count > 0)
                            Text(
                              '${bucket.count}회',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.textPrimary,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final text = byWornTime
                      ? formatKorean(Duration(seconds: (rod.toY * 60).round()))
                      : '${rod.toY.toInt()}회';
                  return BarTooltipItem(
                    text,
                    TextStyle(
                      color: colorScheme.surface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < buckets.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: _valueOf(buckets[i]),
                      color: buckets[i].isCurrent(now)
                          ? colorScheme.primary
                          : AppColors.textSecondary.withValues(alpha: 0.4),
                      width: byWornTime ? 22 : 8,
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
