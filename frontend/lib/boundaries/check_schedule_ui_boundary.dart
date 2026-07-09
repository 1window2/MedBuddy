import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../boundaries/health_recommendation_ui_boundary.dart';
import '../boundaries/medication_detail_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

// 파일명: check_schedule_ui_boundary.dart
// 역할: 오늘 복약 일정과 시간대별 알림 설정 화면을 구성한다.

// 클래스명: CheckScheduleUI
// 역할: 오늘 복용해야 하는 약을 시간대별로 보여주고 복약 상태와 알림을 관리한다.
// 주요 책임:
// - 화면 진입 시 오늘 복약 일정과 알림 설정을 불러온다.
// - 1일 복용 횟수를 기준으로 아침/점심/저녁/취침 전 슬롯에 약을 배치한다.
// - 시간대별 알림 설정 팝업을 열고 로컬 알림 예약을 요청한다.
class CheckScheduleUI extends StatefulWidget {
  const CheckScheduleUI({super.key});

  @override
  State<CheckScheduleUI> createState() => _CheckScheduleUIState();
}

class _CheckScheduleUIState extends State<CheckScheduleUI> {
  static const List<_ScheduleSlotDefinition> _slotDefinitions = [
    _ScheduleSlotDefinition(
      key: 'morning',
      title: '아침',
      hour: 8,
      color: MedBuddyColors.slotMorning,
      icon: Icons.wb_sunny_outlined,
    ),
    _ScheduleSlotDefinition(
      key: 'lunch',
      title: '점심',
      hour: 12,
      color: MedBuddyColors.slotLunch,
      icon: Icons.local_cafe_outlined,
    ),
    _ScheduleSlotDefinition(
      key: 'evening',
      title: '저녁',
      hour: 18,
      color: MedBuddyColors.slotEvening,
      icon: Icons.wb_twilight_outlined,
    ),
    _ScheduleSlotDefinition(
      key: 'bedtime',
      title: '취침 전',
      hour: 22,
      color: MedBuddyColors.slotBedtime,
      icon: Icons.nightlight_round,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel = context.read<MedBuddyViewModel>();
      await viewModel.refreshMedicationOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();
    final text = _ScheduleText(viewModel.userSetting.language);
    final slots = _buildSlots(viewModel);
    final progress = viewModel.todayMedicationProgress;
    final hasTodaySchedule = viewModel.todayMedicationScheduleList.isNotEmpty;

    return Scaffold(
      backgroundColor: MedBuddyColors.surface,
      body: Column(
        children: [
          _ScheduleHeader(
            text: text,
            completedCount: progress.completedCount,
            totalCount: progress.totalCount,
            onBackRequested: () => Navigator.pop(context),
          ),
          Expanded(
            child: _buildContent(viewModel, slots, text),
          ),
          if (hasTodaySchedule)
            _HealthRecommendationFooter(
              text: text,
              onPressed: _openHealthRecommendation,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(
    MedBuddyViewModel viewModel,
    List<_ScheduleSlot> slots,
    _ScheduleText text,
  ) {
    if (viewModel.isTodayScheduleLoading &&
        viewModel.todayMedicationScheduleList.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    if (viewModel.todayMedicationScheduleList.isEmpty) {
      return _ScheduleEmptyState(text: text);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(34, 14, 34, 12),
      children: [
        for (final slot in slots) ...[
          _TimeSlotCard(
            text: text,
            slot: slot,
            reminderSetting: viewModel.medicationReminderSettings[slot.key] ??
                MedicationAlarm.defaults(slot.key),
            isCompletedProvider: (schedule) {
              return viewModel.isMedicationDoseCompleted(slot.key, schedule);
            },
            onReminderRequested: () {
              _handleReminderToggle(viewModel, slot, text);
            },
            onGuideRequested: (schedule) {
              _showMedicationDetail(viewModel, schedule);
            },
            onStatusChanged: (schedule, medicationStatus) async {
              final success = await viewModel.requestMedicationDoseStatusUpdate(
                slot.key,
                schedule,
                medicationStatus,
              );
              if (!mounted || success) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(text.statusUpdateFailed),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  void _openHealthRecommendation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HealthRecommendationUI(),
      ),
    );
  }

  List<_ScheduleSlot> _buildSlots(MedBuddyViewModel viewModel) {
    return _slotDefinitions.map((definition) {
      final medications =
          viewModel.todayMedicationScheduleList.where((schedule) {
        return viewModel.slotKeysForSchedule(schedule).contains(definition.key);
      }).toList(growable: false);
      return _ScheduleSlot(definition: definition, medications: medications);
    }).toList(growable: false);
  }

  Future<void> _showReminderDialog(
    MedBuddyViewModel viewModel,
    _ScheduleSlot slot,
    _ScheduleText text,
  ) async {
    final setting = viewModel.medicationReminderSettings[slot.key] ??
        MedicationAlarm.defaults(slot.key);
    final slotTitle = text.slotTitle(slot.key);
    final selectedTime = await showDialog<_ReminderTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ReminderDialog(
        text: text,
        slotTitle: slotTitle,
        initialHour: setting.hour,
        initialMinute: setting.minute,
      ),
    );
    if (selectedTime == null) {
      return;
    }

    final success = await viewModel.requestMedicationReminderSave(
      slotKey: slot.key,
      slotTitle: slotTitle,
      hour: selectedTime.hour,
      minute: selectedTime.minute,
      schedules: slot.medications,
    );
    if (!mounted || success) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(viewModel.statusMessage)),
    );
  }

  Future<void> _handleReminderToggle(
    MedBuddyViewModel viewModel,
    _ScheduleSlot slot,
    _ScheduleText text,
  ) async {
    final setting = viewModel.medicationReminderSettings[slot.key] ??
        MedicationAlarm.defaults(slot.key);
    if (!setting.isEnabled) {
      await _showReminderDialog(viewModel, slot, text);
      return;
    }

    final success = await viewModel.requestMedicationReminderCancel(
      slotKey: slot.key,
      slotTitle: text.slotTitle(slot.key),
    );
    if (!mounted || success) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(viewModel.statusMessage)),
    );
  }

  void _showMedicationDetail(
    MedBuddyViewModel viewModel,
    MedicationSchedule schedule,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MedicationDetailUI(
          medicationDetail: MedicationDetail.fromMedicationSchedule(schedule),
          userSetting: viewModel.userSetting,
        ),
      ),
    );
  }
}

class _HealthRecommendationFooter extends StatelessWidget {
  final _ScheduleText text;
  final VoidCallback onPressed;

  const _HealthRecommendationFooter({
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        34,
        12,
        34,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: MedBuddyColors.surface,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          side: const BorderSide(color: MedBuddyColors.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundColor: MedBuddyColors.primaryDark,
          backgroundColor: Colors.white,
        ),
        child: Text(
          text.healthRecommendation,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  final _ScheduleText text;
  final int completedCount;
  final int totalCount;
  final VoidCallback onBackRequested;

  const _ScheduleHeader({
    required this.text,
    required this.completedCount,
    required this.totalCount,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;

    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + 12,
        28,
        18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: text.back,
                onPressed: onBackRequested,
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 8),
              Text(
                text.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(left: 26),
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 15),
            decoration: BoxDecoration(
              color: MedBuddyColors.primaryDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text.progress,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$completedCount/$totalCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    color: Colors.white,
                    backgroundColor: MedBuddyColors.progressTrack,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSlotCard extends StatelessWidget {
  final _ScheduleText text;
  final _ScheduleSlot slot;
  final MedicationAlarm reminderSetting;
  final bool Function(MedicationSchedule schedule) isCompletedProvider;
  final VoidCallback onReminderRequested;
  final void Function(MedicationSchedule schedule) onGuideRequested;
  final Future<void> Function(
    MedicationSchedule schedule,
    bool medicationStatus,
  ) onStatusChanged;

  const _TimeSlotCard({
    required this.text,
    required this.slot,
    required this.reminderSetting,
    required this.isCompletedProvider,
    required this.onReminderRequested,
    required this.onGuideRequested,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final slotTitle = text.slotTitle(slot.key);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 5,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            Container(
              color: slot.color,
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(slot.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slotTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          reminderSetting.isEnabled
                              ? reminderSetting.timeLabel
                              : slot.timeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ReminderIconButton(
                    text: text,
                    slotTitle: slotTitle,
                    isEnabled: reminderSetting.isEnabled,
                    onPressed: onReminderRequested,
                  ),
                ],
              ),
            ),
            if (slot.medications.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  text.emptySlot,
                  style: const TextStyle(
                    color: MedBuddyColors.textLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              for (final schedule in slot.medications)
                _MedicationScheduleRow(
                  text: text,
                  schedule: schedule,
                  isCompleted: isCompletedProvider(schedule),
                  onGuideRequested: () => onGuideRequested(schedule),
                  onStatusChanged: (value) => onStatusChanged(schedule, value),
                ),
          ],
        ),
      ),
    );
  }
}

class _MedicationScheduleRow extends StatelessWidget {
  final _ScheduleText text;
  final MedicationSchedule schedule;
  final bool isCompleted;
  final VoidCallback onGuideRequested;
  final Future<void> Function(bool medicationStatus) onStatusChanged;

  const _MedicationScheduleRow({
    required this.text,
    required this.schedule,
    required this.isCompleted,
    required this.onGuideRequested,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: isCompleted ? text.undoComplete : text.complete,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onStatusChanged(!isCompleted),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  color: isCompleted
                      ? MedBuddyColors.primary
                      : MedBuddyColors.outline,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onGuideRequested,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCompleted
                            ? MedBuddyColors.textLight
                            : MedBuddyColors.textStrong,
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      schedule.dosageLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderIconButton extends StatelessWidget {
  final _ScheduleText text;
  final String slotTitle;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _ReminderIconButton({
    required this.text,
    required this.slotTitle,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isEnabled ? const Color(0xFFFF1744) : Colors.white;
    final backgroundColor =
        isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.0);

    return Tooltip(
      message: text.reminderTooltip(slotTitle),
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              isEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
              color: iconColor,
              size: 29,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  final _ScheduleText text;
  final String slotTitle;
  final int initialHour;
  final int initialMinute;

  const _ReminderDialog({
    required this.text,
    required this.slotTitle,
    required this.initialHour,
    required this.initialMinute,
  });

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late bool _isAm;
  late int _hour12;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _isAm = widget.initialHour < 12;
    final normalizedHour = widget.initialHour % 12;
    _hour12 = normalizedHour == 0 ? 12 : normalizedHour;
    _minute = widget.initialMinute;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF344054), width: 1.6),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.18),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: widget.text.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 25),
                ),
                Expanded(
                  child: Text(
                    widget.text.reminderDialogTitle(widget.slotTitle),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AmPmToggle(
                  text: widget.text,
                  isAm: _isAm,
                  onChanged: (value) => setState(() => _isAm = value),
                ),
                const SizedBox(width: 10),
                _TimeStepper(
                  value: _hour12,
                  min: 1,
                  max: 12,
                  onChanged: (value) => setState(() => _hour12 = value),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _TimeStepper(
                  value: _minute,
                  min: 0,
                  max: 59,
                  onChanged: (value) => setState(() => _minute = value),
                ),
              ],
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _ReminderTime(hour: _to24Hour(), minute: _minute),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                widget.text.confirm,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _to24Hour() {
    if (_isAm) {
      return _hour12 == 12 ? 0 : _hour12;
    }
    return _hour12 == 12 ? 12 : _hour12 + 12;
  }
}

class _AmPmToggle extends StatelessWidget {
  final _ScheduleText text;
  final bool isAm;
  final ValueChanged<bool> onChanged;

  const _AmPmToggle({
    required this.text,
    required this.isAm,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 50,
      decoration: BoxDecoration(
        border: Border.all(color: MedBuddyColors.outline, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextButton(
        onPressed: () => onChanged(!isAm),
        child: Text(
          isAm ? text.am : text.pm,
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TimeStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _TimeStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 104,
      decoration: BoxDecoration(
        border: Border.all(color: MedBuddyColors.outline, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Expanded(
            child: IconButton(
              onPressed: () => onChanged(value == max ? min : value + 1),
              icon: const Icon(Icons.keyboard_arrow_up,
                  color: MedBuddyColors.primary),
            ),
          ),
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: IconButton(
              onPressed: () => onChanged(value == min ? max : value - 1),
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: MedBuddyColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  final _ScheduleText text;

  const _ScheduleEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          boxShadow: MedBuddyShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 52,
              color: MedBuddyColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              text.emptySchedule,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSlotDefinition {
  final String key;
  final String title;
  final int hour;
  final Color color;
  final IconData icon;

  const _ScheduleSlotDefinition({
    required this.key,
    required this.title,
    required this.hour,
    required this.color,
    required this.icon,
  });
}

class _ScheduleSlot {
  final _ScheduleSlotDefinition definition;
  final List<MedicationSchedule> medications;

  const _ScheduleSlot({required this.definition, required this.medications});

  String get key => definition.key;
  String get title => definition.title;
  int get hour => definition.hour;
  Color get color => definition.color;
  IconData get icon => definition.icon;
  String get timeLabel => '${hour.toString().padLeft(2, '0')}:00';
}

class _ReminderTime {
  final int hour;
  final int minute;

  const _ReminderTime({required this.hour, required this.minute});
}

class _ScheduleText {
  final String language;

  const _ScheduleText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get title => isEnglish ? "Today's Medication Schedule" : '오늘의 복약 일정';
  String get progress => isEnglish ? 'Progress' : '복용 진행률';
  String get healthRecommendation =>
      isEnglish ? 'View Health Recommendations' : '건강 관리 추천 보기';
  String get emptySlot =>
      isEnglish ? 'No medication for this time' : '복용할 약이 없습니다';
  String get emptySchedule =>
      isEnglish ? 'No medication scheduled for today' : '오늘 복용할 약이 없습니다';
  String get complete => isEnglish ? 'Mark as taken' : '복용 완료';
  String get undoComplete => isEnglish ? 'Undo taken' : '복용 완료 취소';
  String get close => isEnglish ? 'Close' : '닫기';
  String get confirm => isEnglish ? 'Confirm' : '확인';
  String get am => isEnglish ? 'AM' : '오전';
  String get pm => isEnglish ? 'PM' : '오후';
  String get statusUpdateFailed =>
      isEnglish ? 'Could not update medication status.' : '복약 상태를 변경하지 못했습니다.';

  String reminderTooltip(String slotTitle) {
    return isEnglish ? 'Set $slotTitle reminder' : '$slotTitle 알림 설정';
  }

  String reminderDialogTitle(String slotTitle) {
    return isEnglish ? '$slotTitle Reminder' : '$slotTitle 알림';
  }

  String slotTitle(String slotKey) {
    return switch (slotKey) {
      'morning' => isEnglish ? 'Morning' : '아침',
      'lunch' => isEnglish ? 'Lunch' : '점심',
      'evening' => isEnglish ? 'Evening' : '저녁',
      'bedtime' => isEnglish ? 'Bedtime' : '취침 전',
      _ => isEnglish ? 'Schedule' : '일정',
    };
  }
}
