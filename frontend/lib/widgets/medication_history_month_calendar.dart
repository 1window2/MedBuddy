// File Name: medication_history_month_calendar.dart
// Role: Month grid of the medication history screen. Each reachable day shows how many
//   scheduled doses were recorded as taken, with a colour for all, some or none, and a
//   mark when an as-needed dose was recorded; tapping a day opens its detailed records.
//   Days in the future or older than the 90-day history window cannot be selected.

import 'package:flutter/material.dart';

import '../entities/medication_history_entity.dart';
import '../theme/medbuddy_theme.dart';

// Class Name: MedicationHistoryDaySummary
// Role: Recorded scheduled doses of one day, and whether an as-needed dose was taken.
class MedicationHistoryDaySummary {
  const MedicationHistoryDaySummary({
    required this.scheduled,
    required this.taken,
    required this.asNeededTaken,
  });

  final int scheduled;
  final int taken;
  final int asNeededTaken;

  // Function Name: fromSnapshot
  // Description: Groups the records of a period by day. As-needed doses have no fixed
  //   count, so they are kept apart from the scheduled taken/total, as on the schedule.
  // Parameters: - snapshot (MedicationHistorySnapshot): Records of the period.
  // Returns: Map<DateTime, MedicationHistoryDaySummary>: Summary per UTC calendar date.
  static Map<DateTime, MedicationHistoryDaySummary> fromSnapshot(
    MedicationHistorySnapshot snapshot,
  ) {
    final scheduled = <DateTime, int>{};
    final taken = <DateTime, int>{};
    final asNeeded = <DateTime, int>{};
    for (final entry in snapshot.items) {
      final day = entry.scheduleDate;
      final isTaken = entry.status == MedicationHistoryStatus.taken;
      if (entry.isAsNeeded) {
        if (isTaken) asNeeded[day] = (asNeeded[day] ?? 0) + 1;
        continue;
      }
      scheduled[day] = (scheduled[day] ?? 0) + 1;
      if (isTaken) taken[day] = (taken[day] ?? 0) + 1;
    }
    return {
      for (final day in {...scheduled.keys, ...asNeeded.keys})
        day: MedicationHistoryDaySummary(
          scheduled: scheduled[day] ?? 0,
          taken: taken[day] ?? 0,
          asNeededTaken: asNeeded[day] ?? 0,
        ),
    };
  }

  // Function Name: color
  // Description: Green when every scheduled dose is recorded as taken, amber when some
  //   are, grey when none are. Null when the day had no scheduled dose.
  Color? get color => scheduled == 0
      ? null
      : taken == scheduled
      ? MedBuddyColors.primary
      : taken > 0
      ? MedBuddyColors.reminderAccent
      : MedBuddyColors.textMuted;
}

// Class Name: MedicationHistoryMonthCalendar
// Role: Draws the day cells and legend of one month; the history screen owns month navigation.
class MedicationHistoryMonthCalendar extends StatelessWidget {
  const MedicationHistoryMonthCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.summaries,
    required this.isEnglish,
    required this.enabled,
    required this.onDaySelected,
  });

  // First day of the shown month and the dates, all as UTC calendar dates.
  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final Map<DateTime, MedicationHistoryDaySummary> summaries;
  final bool isEnglish;
  final bool enabled;
  final ValueChanged<DateTime> onDaySelected;

  // The history keeps 90 days, so day 89 before today is the earliest reachable one.
  DateTime get earliest => MedicationHistoryDates.earliest(today);

  String _tr(String ko, String en) => isEnglish ? en : ko;

  @override
  Widget build(BuildContext context) {
    final first = DateTime.utc(month.year, month.month);
    final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
    // Sunday-first grid, as Korean wall calendars are laid out.
    final leading = first.weekday % 7;
    final weekdays = isEnglish
        ? const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        : const ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      key: const Key('history-month-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Text(
                    weekdays[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: index == 0
                          ? MedBuddyColors.danger
                          : MedBuddyColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (var week = 0; week * 7 < leading + daysInMonth; week++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _cell(
                    context,
                    week * 7 + column - leading + 1,
                    daysInMonth,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        _legend(),
      ],
    );
  }

  // Function Name: _cell
  // Description: One day: its number, taken/total of scheduled doses and a colour mark.
  //   Unreachable days are drawn faintly and cannot be tapped.
  Widget _cell(BuildContext context, int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 56);
    }
    final day = DateTime.utc(month.year, month.month, dayNumber);
    final reachable = !day.isAfter(today) && !day.isBefore(earliest);
    final summary = reachable ? summaries[day] : null;
    final isToday = day == today;
    final isSelected = day == selected;
    final colour = summary?.color;
    final label = StringBuffer(isEnglish ? 'Day $dayNumber' : '$dayNumber일');
    if (!reachable) {
      label.write(isEnglish ? ', not available' : ', 조회할 수 없음');
    } else if (summary == null || summary.scheduled == 0) {
      label.write(isEnglish ? ', no scheduled doses' : ', 정해진 복약 없음');
    } else {
      label.write(
        isEnglish
            ? ', ${summary.taken} of ${summary.scheduled} recorded as taken'
            : ', ${summary.scheduled}건 중 ${summary.taken}건 복용 기록',
      );
    }
    if ((summary?.asNeededTaken ?? 0) > 0) {
      label.write(
        isEnglish
            ? ', as-needed ${summary!.asNeededTaken}'
            : ', 필요시 ${summary!.asNeededTaken}회',
      );
    }
    if (isToday) label.write(isEnglish ? ', today' : ', 오늘');

    return Semantics(
      button: reachable,
      selected: isSelected,
      label: label.toString(),
      // 하위 InkWell의 의미 정보를 제외하므로 화면 낭독기의 누르기 동작을 직접 연결한다.
      onTap: enabled && reachable ? () => onDaySelected(day) : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isSelected
              ? MedBuddyColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: MedBuddyRadii.small,
            side: isToday
                ? const BorderSide(color: MedBuddyColors.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            key: ValueKey(
              'history-month-day-${MedicationHistoryDates.format(day)}',
            ),
            borderRadius: MedBuddyRadii.small,
            onTap: enabled && reachable ? () => onDaySelected(day) : null,
            child: SizedBox(
              height: 52,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: reachable
                              ? MedBuddyColors.textStrong
                              : MedBuddyColors.textMuted.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colour ?? Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if ((summary?.asNeededTaken ?? 0) > 0) ...[
                            const SizedBox(width: 3),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: MedBuddyColors.infoBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Days without a count keep an empty line so every day number
                      // in a week sits at the same height.
                      Text(
                        summary != null && summary.scheduled > 0
                            ? '${summary.taken}/${summary.scheduled}'
                            : ' ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colour,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Function Name: _legend
  // Description: Explains the marks in one compact row, keeping large text scrollable.
  Widget _legend() {
    Widget item(Color colour, String text, {bool ring = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring ? null : colour,
            border: ring ? Border.all(color: colour, width: 2) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('history-month-legend'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              item(MedBuddyColors.primary, _tr('모두 기록', 'All taken')),
              item(MedBuddyColors.reminderAccent, _tr('일부 기록', 'Some taken')),
              item(MedBuddyColors.textMuted, _tr('미기록', 'No record')),
              item(
                MedBuddyColors.infoBlue,
                _tr('필요시', 'As needed'),
                ring: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
