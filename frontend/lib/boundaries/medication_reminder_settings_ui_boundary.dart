import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_feature_updates.dart';
import '../viewmodels/medbuddy_view_model.dart';
import 'set_notification_ui_boundary.dart';

// 파일명: medication_reminder_settings_ui_boundary.dart
// 역할: 홈의 빠른 기능에서 모든 시간대별 복약 알림을 한 화면에서 관리한다.

// 클래스명: MedicationReminderSettingsUI
// 역할: 아침, 점심, 저녁, 취침 전 알림의 현재 상태와 시간을 표시하고 변경한다.
// 주요 책임:
// - 최신 복약 일정과 알림 설정을 불러온다.
// - 시간대별 알림 설정 팝업을 열어 기존 ViewModel 저장 흐름을 재사용한다.
// - 알림 설정과 해제 결과를 사용자에게 즉시 안내한다.
class MedicationReminderSettingsUI extends StatefulWidget {
  const MedicationReminderSettingsUI({super.key});

  @override
  State<MedicationReminderSettingsUI> createState() =>
      _MedicationReminderSettingsUIState();
}

class _MedicationReminderSettingsUIState
    extends State<MedicationReminderSettingsUI> {
  static const List<_ReminderSlotDefinition> _slots = [
    _ReminderSlotDefinition(
      key: 'morning',
      koreanLabel: '아침',
      englishLabel: 'Morning',
      icon: Icons.wb_sunny_outlined,
    ),
    _ReminderSlotDefinition(
      key: 'lunch',
      koreanLabel: '점심',
      englishLabel: 'Lunch',
      icon: Icons.local_cafe_outlined,
    ),
    _ReminderSlotDefinition(
      key: 'evening',
      koreanLabel: '저녁',
      englishLabel: 'Evening',
      icon: Icons.wb_twilight_outlined,
    ),
    _ReminderSlotDefinition(
      key: 'bedtime',
      koreanLabel: '취침 전',
      englishLabel: 'Bedtime',
      icon: Icons.nightlight_round,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MedBuddyViewModel>().refreshMedicationSchedule();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.schedule),
        viewModel.updatesFor(MedBuddyFeature.reminder),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
    final text = _ReminderSettingsText(viewModel.userSetting.language);
    final isLoading = viewModel.isTodayScheduleLoading;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MedBuddySpacing.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: text.back,
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          text.title,
                          style: const TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 24,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    text.description,
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: MedBuddyColors.primary,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          itemCount: _slots.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final slot = _slots[index];
                            final setting =
                                viewModel.medicationReminderSettings[slot
                                    .key] ??
                                MedicationAlarm.defaults(slot.key);
                            final schedules = _schedulesForSlot(
                              viewModel,
                              slot.key,
                            );
                            return _ReminderSlotCard(
                              slot: slot,
                              setting: setting,
                              medicationCount: schedules.length,
                              text: text,
                              onTimeRequested: schedules.isEmpty
                                  ? null
                                  : () => _requestReminderTime(
                                      viewModel,
                                      slot,
                                      schedules,
                                      setting,
                                      text,
                                    ),
                              onEnabledChanged: schedules.isEmpty
                                  ? null
                                  : (enabled) => _changeReminderEnabled(
                                      viewModel,
                                      slot,
                                      schedules,
                                      setting,
                                      enabled,
                                      text,
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<MedicationSchedule> _schedulesForSlot(
    MedBuddyViewModel viewModel,
    String slotKey,
  ) {
    return viewModel.todayMedicationScheduleList
        .where(
          (schedule) =>
              viewModel.slotKeysForSchedule(schedule).contains(slotKey),
        )
        .toList(growable: false);
  }

  // 함수이름: _requestReminderTime
  // 함수역할:
  // - 선택한 시간대의 알림 시간 팝업을 열고 기존 알림 저장 흐름을 호출한다.
  // 매개변수:
  // - viewModel: 일정과 알림 저장 요청을 제공하는 ViewModel
  // - slot: 사용자가 선택한 시간대 정의
  // - schedules: 해당 시간대에 복용할 약 목록
  // - setting: 현재 알림 설정
  // - text: 현재 언어의 화면 문구
  // 반환값:
  // - 없음
  Future<void> _requestReminderTime(
    MedBuddyViewModel viewModel,
    _ReminderSlotDefinition slot,
    List<MedicationSchedule> schedules,
    MedicationAlarm setting,
    _ReminderSettingsText text,
  ) async {
    final slotLabel = slot.label(text.isEnglish);
    final selectedTime = await SetNotificationUI.showNotificationPopup(
      context,
      language: viewModel.userSetting.language,
      slotTitle: slotLabel,
      initialTime: TimeOfDay(hour: setting.hour, minute: setting.minute),
    );
    if (selectedTime == null) {
      return;
    }
    final succeeded = await viewModel.requestMedicationReminderSave(
      slotKey: slot.key,
      slotTitle: slotLabel,
      hour: selectedTime.hour,
      minute: selectedTime.minute,
      schedules: schedules,
    );
    if (mounted) {
      _showResult(viewModel.statusMessage, succeeded);
    }
  }

  // 함수이름: _changeReminderEnabled
  // 함수역할:
  // - 꺼진 알림은 시간 선택으로 연결하고 켜진 알림은 기존 취소 흐름으로 해제한다.
  // 매개변수:
  // - viewModel: 알림 저장 및 해제 요청을 제공하는 ViewModel
  // - slot: 사용자가 선택한 시간대 정의
  // - schedules: 해당 시간대에 복용할 약 목록
  // - setting: 현재 알림 설정
  // - enabled: 사용자가 요청한 새 활성 상태
  // - text: 현재 언어의 화면 문구
  // 반환값:
  // - 없음
  Future<void> _changeReminderEnabled(
    MedBuddyViewModel viewModel,
    _ReminderSlotDefinition slot,
    List<MedicationSchedule> schedules,
    MedicationAlarm setting,
    bool enabled,
    _ReminderSettingsText text,
  ) async {
    if (enabled) {
      await _requestReminderTime(viewModel, slot, schedules, setting, text);
      return;
    }
    final succeeded = await viewModel.requestMedicationReminderCancel(
      slotKey: slot.key,
      slotTitle: slot.label(text.isEnglish),
    );
    if (mounted) {
      _showResult(viewModel.statusMessage, succeeded);
    }
  }

  void _showResult(String message, bool succeeded) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: succeeded
            ? MedBuddyColors.primaryDark
            : MedBuddyColors.danger,
      ),
    );
  }
}

class _ReminderSlotCard extends StatelessWidget {
  final _ReminderSlotDefinition slot;
  final MedicationAlarm setting;
  final int medicationCount;
  final _ReminderSettingsText text;
  final VoidCallback? onTimeRequested;
  final ValueChanged<bool>? onEnabledChanged;

  const _ReminderSlotCard({
    required this.slot,
    required this.setting,
    required this.medicationCount,
    required this.text,
    required this.onTimeRequested,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = medicationCount > 0;
    final label = slot.label(text.isEnglish);

    return Material(
      color: MedBuddyColors.surface,
      borderRadius: MedBuddyRadii.largeCard,
      child: InkWell(
        borderRadius: MedBuddyRadii.largeCard,
        onTap: onTimeRequested,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.largeCard,
            border: Border.all(color: MedBuddyColors.cardBorder),
            boxShadow: MedBuddyShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isAvailable
                      ? MedBuddyColors.mint
                      : MedBuddyColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  slot.icon,
                  color: isAvailable
                      ? MedBuddyColors.primaryDark
                      : MedBuddyColors.textLight,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      !isAvailable
                          ? text.noMedication
                          : setting.isEnabled
                          ? text.enabledAt(setting.timeLabel, medicationCount)
                          : text.disabled(medicationCount),
                      style: TextStyle(
                        color: isAvailable
                            ? MedBuddyColors.textMuted
                            : MedBuddyColors.textSubtle,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isAvailable && setting.isEnabled,
                onChanged: onEnabledChanged,
                activeTrackColor: MedBuddyColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderSlotDefinition {
  final String key;
  final String koreanLabel;
  final String englishLabel;
  final IconData icon;

  const _ReminderSlotDefinition({
    required this.key,
    required this.koreanLabel,
    required this.englishLabel,
    required this.icon,
  });

  String label(bool isEnglish) => isEnglish ? englishLabel : koreanLabel;
}

class _ReminderSettingsText {
  final String language;

  const _ReminderSettingsText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get title => isEnglish ? 'Medication Reminder Settings' : '복약 알림 설정';
  String get description => isEnglish
      ? 'Choose a time slot to edit its reminder. Reminders without medication stay unavailable.'
      : '시간대를 눌러 알림 시간을 변경하세요. 등록된 약이 없는 시간대는 사용할 수 없습니다.';
  String get back => isEnglish ? 'Back' : '뒤로';
  String get noMedication =>
      isEnglish ? 'No medication in this time slot' : '이 시간대에 등록된 약이 없습니다';
  String enabledAt(String time, int count) => isEnglish
      ? '$time · $count medication${count == 1 ? '' : 's'}'
      : '$time · 약 $count개';
  String disabled(int count) => isEnglish
      ? 'Off · $count medication${count == 1 ? '' : 's'}'
      : '꺼짐 · 약 $count개';
}
