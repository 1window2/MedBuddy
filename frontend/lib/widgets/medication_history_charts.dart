// 파일명: medication_history_charts.dart
// 역할: 서버 복약 이력을 정기 복용 통계와 필요시 복용 횟수로 나눠 시각화한다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities/medication_history_entity.dart';
import '../entities/calendar_days.dart';
import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: MedicationHistoryChartCounts
// 역할: 정기 복용 상태와 필요시 실제 복용 횟수를 겹치지 않게 집계한다.
// 주요 책임: 정기 복용률의 분모에서 필요시 기록을 제외하고 차트용 개수를 제공한다.
// 속성: taken/skipped/unrecorded: 정기 일정 상태별 수; asNeeded: 필요시 복용 완료 수.
class MedicationHistoryChartCounts {
  // 함수이름: MedicationHistoryChartCounts
  // 함수역할: 차트에 사용할 상태별 개수를 보관한다.
  // 매개변수: taken/skipped/unrecorded: 정기 상태별 수; asNeeded: 필요시 복용 수; 생략하면 각 0.
  // 반환값: 집계 객체; 음수 여부는 직접 검증하지 않는다.
  const MedicationHistoryChartCounts({
    this.taken = 0,
    this.skipped = 0,
    this.unrecorded = 0,
    this.asNeeded = 0,
  });

  // 함수이름: MedicationHistoryChartCounts.fromEntries
  // 함수역할: 기록을 정기 세 상태와 필요시 복용 완료로 나누어 센다.
  // 매개변수: entries: 집계할 복약 기록.
  // 반환값: 집계 결과; 필요시 미기록·건너뜀은 개수에 넣지 않는다.
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
  // 함수이름: scheduled
  // 함수역할: 정기 일정의 세 상태를 더해 복용률 분모를 계산한다.
  // 매개변수: 없음.
  // 반환값: 필요시 복용을 제외한 정기 기록 수.
  int get scheduled => taken + skipped + unrecorded;
  // 함수이름: total
  // 함수역할: 누적 막대에 표시할 정기 기록과 필요시 복용의 합을 계산한다.
  // 매개변수: 없음.
  // 반환값: 차트에 포함되는 전체 개수.
  int get total => scheduled + asNeeded;
  // 함수이름: percent
  // 함수역할: 정기 복용 완료 수를 정기 일정 수로 나눠 반올림한 비율을 제공한다.
  // 매개변수: 없음.
  // 반환값: 정수 백분율 또는 정기 일정이 없으면 null.
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

// 클래스명: MedicationHistoryChartsSummary
// 역할: 복약 상태별 집계와 정기 기록률을 요약 차트로 표시한다.
// 주요 책임: 전체 화면에서는 비율·횟수 전환을 제공하고 작은 공유 카드에서는 횟수를 표시한다.
// 속성: snapshot 또는 counts: 집계 원본; isEnglish: 언어; compact: 소형 모드; showAsNeeded: 필요시 범례 표시.
class MedicationHistoryChartsSummary extends StatefulWidget {
  // Function Name: MedicationHistoryChartsSummary
  // Description: Creates a full summary from a medication-history snapshot.
  // Parameters: key: Widget identity; snapshot: Source records; isEnglish: Display language.
  // Returns: A noncompact summary with as-needed counts visible.
  const MedicationHistoryChartsSummary({
    super.key,
    required this.snapshot,
    required this.isEnglish,
  }) : counts = null,
       compact = false,
       showAsNeeded = true;

  // 함수이름: MedicationHistoryChartsSummary.counts
  // 함수역할: 미리 계산한 집계로 전체 기록 없이 차트 요약을 구성한다.
  // 매개변수: key: 위젯 식별자; counts: 집계; isEnglish: 언어; compact: 소형 표시; showAsNeeded: 필요시 범례 포함 여부.
  // 반환값: 기본적으로 소형 횟수 표시를 사용하는 요약 위젯.
  const MedicationHistoryChartsSummary.counts({
    super.key,
    required MedicationHistoryChartCounts this.counts,
    required this.isEnglish,
    this.compact = true,
    this.showAsNeeded = true,
  }) : snapshot = null;

  final MedicationHistorySnapshot? snapshot;
  final MedicationHistoryChartCounts? counts;
  final bool isEnglish;
  // 채팅 카드처럼 작게 표시할 때는 전환 없이 횟수만 보여준다.
  final bool compact;
  final bool showAsNeeded;

  // 함수이름: createState
  // 함수역할: 비율과 횟수 표시 선택을 관리할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 요약 차트 State.
  @override
  State<MedicationHistoryChartsSummary> createState() =>
      _MedicationHistoryChartsSummaryState();
}

// Class Name: _MedicationHistoryChartsSummaryState
// Role: Owns the summary's count-versus-percentage display selection.
// Responsibilities: Derive counts when needed and render a responsive ring and legend.
// Attributes: _showRatio: Current count display mode, initially enabled for precomputed counts.
class _MedicationHistoryChartsSummaryState
    extends State<MedicationHistoryChartsSummary> {
  late bool _showRatio = widget.counts != null;

  // Function Name: build
  // Description: Builds the scheduled-dose ring and category legend, stacking them for narrow or enlarged-text layouts.
  // Parameters: context: Flutter build context.
  // Returns: The summary widget; only noncompact charts permit count/percentage toggling.
  @override
  Widget build(BuildContext context) {
    final counts =
        widget.counts ??
        MedicationHistoryChartCounts.fromEntries(widget.snapshot!.items);
    final isEnglish = widget.isEnglish;
    const foreground = MedBuddyColors.textStrong;
    const muted = MedBuddyColors.textMuted;
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
        painter: _HistoryRingPainter(counts),
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
                  KeepWordsText(
                    caption,
                    textAlign: TextAlign.center,
                    style: MedBuddyTextStyles.menuBody.copyWith(
                      fontSize: widget.compact ? 10 : 12,
                      color: muted,
                    ),
                  ),
                  if (!widget.compact) ...[
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
      button: !widget.compact,
      label: !widget.showAsNeeded
          ? (isEnglish ? 'Recorded doses $value' : '복용 기록 $value')
          : isEnglish
          ? 'Scheduled dose record ${_showRatio ? 'count' : 'rate'} $value'
          : '정기 복용 ${_showRatio ? '기록 횟수' : '기록률'} $value',
      child: widget.compact
          ? ring
          : Tooltip(
              message: hint,
              child: InkWell(
                key: const Key('history-rate-toggle'),
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _showRatio = !_showRatio),
                child: ring,
              ),
            ),
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
                    color: _chartColors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KeepWordsText(
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

// Class Name: _HistoryRingPainter
// Role: Paints scheduled-dose proportions without including as-needed doses in the denominator.
// Responsibilities: Draw taken, skipped and unrecorded arcs; leave a neutral ring when no scheduled doses exist.
// Attributes: counts: Category totals used for ring geometry.
class _HistoryRingPainter extends CustomPainter {
  // Function Name: _HistoryRingPainter
  // Description: Binds the ring painter to a set of dose counts.
  // Parameters: counts: Aggregated history counts.
  // Returns: A painter that uses only scheduled categories.
  const _HistoryRingPainter(this.counts);
  final MedicationHistoryChartCounts counts;

  // Function Name: paint
  // Description: Draws a 13-pixel ring and proportional scheduled-state arcs from the top clockwise.
  // Parameters: canvas: Drawing surface; size: Available bounds.
  // Returns: None; zero scheduled doses leave only the base oval.
  @override
  void paint(Canvas canvas, Size size) {
    const width = 13.0;
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawOval(rect, paint..color = _chartColors[2]);
    if (counts.scheduled == 0) return;
    var angle = -math.pi / 2;
    final values = [counts.taken, counts.skipped, counts.unrecorded];
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i] / counts.scheduled;
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          angle,
          sweep,
          false,
          paint..color = _chartColors[i],
        );
      }
      angle += sweep;
    }
  }

  // 함수이름: shouldRepaint
  // 함수역할: 고리의 정기 상태 개수가 달라졌을 때만 다시 그리도록 판단한다.
  // 매개변수: oldDelegate: 이전 고리 페인터.
  // 반환값: 정기 세 개수 중 하나라도 다르면 true; 필요시 개수만 바뀌면 false.
  @override
  bool shouldRepaint(_HistoryRingPainter oldDelegate) =>
      oldDelegate.counts.taken != counts.taken ||
      oldDelegate.counts.skipped != counts.skipped ||
      oldDelegate.counts.unrecorded != counts.unrecorded;
}

// 클래스명: MedicationHistoryWeekChart
// 역할: 시작일로부터 7일간 정기 상태와 필요시 복용을 누적 막대로 보여준다.
// 주요 책임: 날짜별 집계를 비교하고 조회 범위 내 과거·오늘 날짜 선택을 전달한다.
// 속성: snapshot: 기록; weekStart/today/selected: 날짜 범위와 선택; isEnglish/enabled/onDaySelected: 언어와 상호작용.
class MedicationHistoryWeekChart extends StatelessWidget {
  // 함수이름: MedicationHistoryWeekChart
  // 함수역할: 7일 차트의 기록과 날짜 선택 조건을 구성한다.
  // 매개변수: key: 식별자; snapshot: 기록; weekStart: 월요일 기준 시작일; today/selected: 오늘·선택일; isEnglish: 언어; enabled: 선택 허용; onDaySelected: 날짜 콜백.
  // 반환값: 주간 차트; 시작일을 월요일로 보정하지 않는다.
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

  // 함수이름: build
  // 함수역할: 날짜별 누적 막대와 선택 표시를 만들고 미래·조회 범위 밖 날짜의 선택을 막는다.
  // 매개변수: context: 화면 구성 문맥.
  // 반환값: 7일 차트 위젯; 최댓값을 기준으로 최소 2의 짝수 눈금을 사용한다.
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
