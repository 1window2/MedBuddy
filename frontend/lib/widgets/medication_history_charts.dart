// 파일명: medication_history_charts.dart
// 역할: 서버 복약 이력을 정기 복용 통계와 필요시 복용 횟수로 나눠 시각화한다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities/medication_history_entity.dart';
import '../entities/calendar_days.dart';
import '../theme/medbuddy_theme.dart';

// 정기 복용의 세 상태와 필요시 실제 복용 기록을 서로 겹치지 않게 집계한다.
class MedicationHistoryChartCounts {
  const MedicationHistoryChartCounts({
    this.taken = 0,
    this.skipped = 0,
    this.unrecorded = 0,
    this.asNeeded = 0,
  });

  factory MedicationHistoryChartCounts.fromEntries(
    Iterable<MedicationHistoryEntry> entries,
  ) {
    var taken = 0;
    var skipped = 0;
    var unrecorded = 0;
    var asNeeded = 0;
    for (final entry in entries) {
      if (entry.isAsNeeded) {
        if (entry.status == MedicationHistoryStatus.taken) asNeeded++;
      } else {
        switch (entry.status) {
          case MedicationHistoryStatus.taken:
            taken++;
          case MedicationHistoryStatus.skipped:
            skipped++;
          case MedicationHistoryStatus.unrecorded:
            unrecorded++;
        }
      }
    }
    return MedicationHistoryChartCounts(
      taken: taken,
      skipped: skipped,
      unrecorded: unrecorded,
      asNeeded: asNeeded,
    );
  }

  final int taken;
  final int skipped;
  final int unrecorded;
  final int asNeeded;
  int get scheduled => taken + skipped + unrecorded;
  int get total => scheduled + asNeeded;
  int? get percent => scheduled == 0 ? null : (taken * 100 / scheduled).round();
}

const _unknownColor = Color(0xFFC9D5D0);
const _asNeededColor = Color(0xFF506ABC);
const _chartColors = [
  MedBuddyColors.primary,
  MedBuddyColors.reminderAccent,
  _unknownColor,
  _asNeededColor,
];

// 정기 복용률과 횟수 비율을 전환하며 채팅에서는 같은 집계를 작은 그래프로 표시한다.
class MedicationHistoryChartsSummary extends StatefulWidget {
  const MedicationHistoryChartsSummary({
    super.key,
    required this.snapshot,
    required this.isEnglish,
  }) : counts = null,
       compact = false,
       inverse = false,
       showAsNeeded = true,
       initiallyShowRatio = false,
       toggleEnabled = true;

  const MedicationHistoryChartsSummary.counts({
    super.key,
    required MedicationHistoryChartCounts this.counts,
    required this.isEnglish,
    this.compact = true,
    this.inverse = false,
    this.showAsNeeded = true,
    this.initiallyShowRatio = true,
    this.toggleEnabled = false,
  }) : snapshot = null;

  final MedicationHistorySnapshot? snapshot;
  final MedicationHistoryChartCounts? counts;
  final bool isEnglish;
  final bool compact;
  final bool inverse;
  final bool showAsNeeded;
  final bool initiallyShowRatio;
  final bool toggleEnabled;

  @override
  State<MedicationHistoryChartsSummary> createState() =>
      _MedicationHistoryChartsSummaryState();
}

class _MedicationHistoryChartsSummaryState
    extends State<MedicationHistoryChartsSummary> {
  late bool _showRatio = widget.initiallyShowRatio;

  @override
  Widget build(BuildContext context) {
    final counts =
        widget.counts ??
        MedicationHistoryChartCounts.fromEntries(widget.snapshot!.items);
    final isEnglish = widget.isEnglish;
    final foreground = widget.inverse
        ? Colors.white
        : MedBuddyColors.textStrong;
    final muted = widget.inverse ? Colors.white70 : MedBuddyColors.textMuted;
    final colors = widget.inverse
        ? const [
            Color(0xFF75DFC0),
            Color(0xFFFFD37B),
            Color(0xFFB8CAC4),
            Color(0xFFB6C8FF),
          ]
        : _chartColors;
    final values = [
      counts.taken,
      counts.skipped,
      counts.unrecorded,
      counts.asNeeded,
    ];
    final labels = isEnglish
        ? ['Taken', 'Skipped', 'Unrecorded', 'As needed']
        : ['복용함', '건너뜀', '미기록', '필요시 복용'];
    final rate = counts.percent == null ? '-' : '${counts.percent}%';
    final value = _showRatio ? '${counts.taken}/${counts.scheduled}' : rate;
    final caption = _showRatio
        ? (isEnglish ? 'Recorded / total' : '복용 기록 / 전체')
        : (isEnglish ? 'Record rate' : '복용 기록률');
    final hint = _showRatio
        ? (isEnglish ? 'Show percentage' : '기록률로 전환')
        : (isEnglish ? 'Show dose counts' : '복용 횟수로 전환');
    final size = widget.compact ? 112.0 : 148.0;
    final ring = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        key: const Key('history-rate-chart'),
        painter: _HistoryRingPainter(counts, colors: colors),
        child: Center(
          // 원 안에 내접하는 사각형으로 제한해 긴 비율과 확대 글자도 고리를 침범하지 않는다.
          child: SizedBox.square(
            dimension: (size - 2 * (13 + 4)) / math.sqrt2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                key: const Key('history-rate-content'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    key: const Key('history-rate-value'),
                    style: TextStyle(
                      fontSize: widget.compact ? 25 : 32,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: MedBuddyTextStyles.menuBody.copyWith(
                      fontSize: widget.compact ? 10 : 12,
                      color: muted,
                    ),
                  ),
                  if (widget.toggleEnabled) ...[
                    const SizedBox(height: 4),
                    Icon(Icons.swap_horiz_rounded, size: 18, color: muted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final chart = Semantics(
      button: widget.toggleEnabled,
      label: !widget.showAsNeeded
          ? (isEnglish ? 'Recorded doses $value' : '복용 기록 $value')
          : isEnglish
          ? 'Scheduled dose record ${_showRatio ? 'count' : 'rate'} $value'
          : '정기 복용 ${_showRatio ? '기록 횟수' : '기록률'} $value',
      child: widget.toggleEnabled
          ? Tooltip(
              message: hint,
              child: InkWell(
                key: const Key('history-rate-toggle'),
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _showRatio = !_showRatio),
                child: ring,
              ),
            )
          : ring,
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < (widget.showAsNeeded ? 4 : 3); i++) ...[
          if (i == 3) Divider(height: 16, color: muted.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels[i],
                    style: MedBuddyTextStyles.menuBody.copyWith(
                      fontSize: widget.compact ? 12 : 14,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${values[i]}',
                  key: ValueKey('history-count-$i'),
                  style: TextStyle(
                    fontSize: widget.compact ? 14 : 17,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < (widget.compact ? 236 : 310) ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        return stacked
            ? Column(children: [chart, const SizedBox(height: 12), legend])
            : Row(
                children: [
                  chart,
                  SizedBox(width: widget.compact ? 12 : 20),
                  Expanded(child: legend),
                ],
              );
      },
    );
  }
}

// 원형 그래프의 분모에는 정기 일정만 넣고 빈 일정은 0% 대신 빈 고리로 남긴다.
class _HistoryRingPainter extends CustomPainter {
  const _HistoryRingPainter(this.counts, {this.colors = _chartColors});
  final MedicationHistoryChartCounts counts;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 13.0;
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawOval(rect, paint..color = colors[2]);
    if (counts.scheduled == 0) return;
    var angle = -math.pi / 2;
    final values = [counts.taken, counts.skipped, counts.unrecorded];
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i] / counts.scheduled;
      if (sweep > 0) {
        canvas.drawArc(rect, angle, sweep, false, paint..color = colors[i]);
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_HistoryRingPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.counts.taken != counts.taken ||
      oldDelegate.counts.skipped != counts.skipped ||
      oldDelegate.counts.unrecorded != counts.unrecorded;
}

// 월요일부터 일요일까지 정기 상태와 필요시 복용을 누적 막대로 보여준다.
class MedicationHistoryWeekChart extends StatelessWidget {
  const MedicationHistoryWeekChart({
    super.key,
    required this.snapshot,
    required this.weekStart,
    required this.today,
    required this.selected,
    required this.isEnglish,
    required this.enabled,
    required this.onDaySelected,
  });
  final MedicationHistorySnapshot snapshot;
  final DateTime weekStart;
  final DateTime today;
  final DateTime selected;
  final bool isEnglish;
  final bool enabled;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => addCalendarDays(weekStart, i));
    final selectable = [
      for (final day in days)
        snapshot.range.contains(day) && !day.isAfter(today),
    ];
    final counts = [
      for (final day in days)
        MedicationHistoryChartCounts.fromEntries(
          snapshot.items.where(
            (entry) => entry.scheduleDate == day && !day.isAfter(today),
          ),
        ),
    ];
    final maximum = counts.fold<int>(
      0,
      (value, count) => math.max(value, count.total),
    );
    final scale = math.max(2, ((maximum + 1) ~/ 2) * 2);
    final weekdays = isEnglish
        ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
        : ['월', '화', '수', '목', '금', '토', '일'];
    const height = 112.0;
    return Column(
      key: const Key('history-week-chart'),
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tick in [scale, scale ~/ 2, 0])
                      Text(
                        '$tick',
                        style: const TextStyle(
                          fontSize: 11,
                          color: MedBuddyColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Divider(height: 1),
                          Divider(height: 1),
                          Divider(height: 1),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Semantics(
                              label: isEnglish
                                  ? '${MedicationHistoryDates.format(days[i])}, taken ${counts[i].taken}, skipped ${counts[i].skipped}, unrecorded ${counts[i].unrecorded}, as needed ${counts[i].asNeeded}'
                                  : '${MedicationHistoryDates.format(days[i])}, 복용함 ${counts[i].taken}, 건너뜀 ${counts[i].skipped}, 미기록 ${counts[i].unrecorded}, 필요시 ${counts[i].asNeeded}',
                              child: InkWell(
                                onTap: enabled && selectable[i]
                                    ? () => onDaySelected(days[i])
                                    : null,
                                child: SizedBox(
                                  height: height,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      widthFactor: 0.5,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (final segment in [
                                            (
                                              counts[i].asNeeded,
                                              _asNeededColor,
                                              'prn',
                                            ),
                                            (
                                              counts[i].unrecorded,
                                              _unknownColor,
                                              'unrecorded',
                                            ),
                                            (
                                              counts[i].skipped,
                                              MedBuddyColors.reminderAccent,
                                              'skipped',
                                            ),
                                            (
                                              counts[i].taken,
                                              MedBuddyColors.primary,
                                              'taken',
                                            ),
                                          ])
                                            Container(
                                              key: ValueKey(
                                                'history-week-${days[i].day}-${segment.$3}',
                                              ),
                                              height:
                                                  height * segment.$1 / scale,
                                              color: segment.$2,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 28),
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Semantics(
                  selected: days[i] == selected,
                  child: InkWell(
                    key: ValueKey(
                      'history-week-day-${MedicationHistoryDates.format(days[i])}',
                    ),
                    onTap: enabled && selectable[i]
                        ? () => onDaySelected(days[i])
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            weekdays[i],
                            style: TextStyle(
                              fontSize: 12,
                              color: selectable[i]
                                  ? MedBuddyColors.textMuted
                                  : MedBuddyColors.textMuted.withValues(
                                      alpha: 0.4,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: days[i] == selected
                                  ? MedBuddyColors.primary
                                  : null,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${days[i].day}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: days[i] == selected
                                      ? Colors.white
                                      : selectable[i]
                                      ? MedBuddyColors.textStrong
                                      : MedBuddyColors.textMuted.withValues(
                                          alpha: 0.4,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
