// 파일명: check_schedule_ui_boundary.dart
// 역할: 오늘의 복약 일정, 복용 완료와 시간대별 알림 설정 화면을 제공한다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../boundaries/health_recommendation_ui_boundary.dart';
import 'check_medication_detail_ui_boundary.dart';
import '../boundaries/set_notification_ui_boundary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/medbuddy_feature_updates.dart';
import 'medication_image_viewer_boundary.dart';

// 파일명: check_schedule_ui_boundary.dart
// 역할: 오늘 복약 일정과 시간대별 알림 설정 화면을 구성한다.

// 클래스명: CheckScheduleUI
// 역할: 오늘 복용해야 하는 약을 시간대별로 보여주고 복약 상태와 알림을 관리한다.
// 주요 책임:
// - 화면 진입 시 오늘 복약 일정과 알림 설정을 불러온다.
// - 1일 복용 횟수를 기준으로 아침/점심/저녁/취침 전 슬롯에 약을 배치한다.
// - 시간대별 알림 설정 팝업을 열고 로컬 알림 예약을 요청한다.
class CheckScheduleUI extends StatefulWidget {
  final List<MedicationSchedule>? selectionSchedules;
  final String selectionLanguage;
  final Set<String> initialSelectedMedicationIds;
  final String? initialSlotKey;

  const CheckScheduleUI({super.key, this.initialSlotKey})
    : selectionSchedules = null,
      selectionLanguage = 'ko',
      initialSelectedMedicationIds = const {};

  // 생성자명: CheckScheduleUI.selection
  // 역할: 오늘 일정의 시간대 카드 구성을 재사용해 채팅에 첨부할 약을 선택한다.
  const CheckScheduleUI.selection({
    super.key,
    required List<MedicationSchedule> schedules,
    required String language,
    Set<String> selectedMedicationIds = const {},
  }) : selectionSchedules = schedules,
       selectionLanguage = language,
       initialSelectedMedicationIds = selectedMedicationIds,
       initialSlotKey = null;

  bool get isSelectionMode => selectionSchedules != null;

  @override
  State<CheckScheduleUI> createState() => _CheckScheduleUIState();
}

class _CheckScheduleUIState extends State<CheckScheduleUI> {
  static const Duration _completionSnackBarDuration = Duration(seconds: 5);
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

  int _completionSnackBarGeneration = 0;
  final Map<String, GlobalKey> _slotKeys = {
    for (final definition in _slotDefinitions) definition.key: GlobalKey(),
  };
  bool _didRevealInitialSlot = false;
  late Set<String> _selectedMedicationIds;

  @override
  void initState() {
    super.initState();
    _selectedMedicationIds = {...widget.initialSelectedMedicationIds};
    if (widget.isSelectionMode) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel = context.read<MedBuddyViewModel>();
      await viewModel.refreshMedicationSchedule();
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _revealInitialSlot();
        }
      });
    });
  }

  // 함수명: _revealInitialSlot
  // 역할:
  // - 알림에서 전달된 시간대 카드가 화면에 보이도록 최초 한 번만 이동한다.
  void _revealInitialSlot() {
    if (_didRevealInitialSlot) {
      return;
    }
    final slotKey = widget.initialSlotKey?.trim().toLowerCase();
    final targetContext = _slotKeys[slotKey]?.currentContext;
    if (targetContext == null) {
      return;
    }
    _didRevealInitialSlot = true;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSelectionMode) {
      return _buildSelectionScreen(context);
    }
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

  Widget _buildSelectionScreen(BuildContext context) {
    final text = _ScheduleText(widget.selectionLanguage);
    final schedules = widget.selectionSchedules ?? const <MedicationSchedule>[];
    final slots = _buildSelectionSlots(schedules);
    return Scaffold(
      backgroundColor: MedBuddyColors.surface,
      body: Column(
        children: [
          _ScheduleSelectionHeader(
            text: text,
            onBackRequested: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(34, 14, 34, 24),
              children: [
                for (final slot in slots) ...[
                  _TimeSlotCard(
                    text: text,
                    slot: slot,
                    userSetting: UserSetting(language: text.language),
                    reminderSetting: MedicationAlarm.defaults(slot.key),
                    isCompletedProvider: (_) => false,
                    onReminderRequested: () {},
                    onGuideRequested: (_) {},
                    onStatusChanged: (_, _) async {},
                    isSelectionMode: true,
                    isSelectedProvider: (schedule) =>
                        _selectedMedicationIds.contains(schedule.medicationID),
                    onSelectionRequested: _toggleMedicationSelection,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          _ScheduleSelectionFooter(
            text: text,
            selectedCount: _selectedMedicationIds.length,
            onConfirmRequested: _selectedMedicationIds.isEmpty
                ? null
                : () => _completeMedicationSelection(context, schedules),
          ),
        ],
      ),
    );
  }

  // 함수명: _toggleMedicationSelection
  // 역할: 같은 약이 여러 시간대에 보여도 약 식별자 하나를 기준으로 선택 상태를 바꾼다.
  void _toggleMedicationSelection(MedicationSchedule schedule) {
    setState(() {
      final medicationId = schedule.medicationID;
      if (!_selectedMedicationIds.add(medicationId)) {
        _selectedMedicationIds.remove(medicationId);
      }
    });
  }

  // 함수명: _completeMedicationSelection
  // 역할: 화면에 표시된 순서를 유지하면서 중복 없이 선택한 약 목록을 채팅 화면으로 반환한다.
  void _completeMedicationSelection(
    BuildContext context,
    List<MedicationSchedule> schedules,
  ) {
    final selectedById = <String, MedicationSchedule>{};
    for (final schedule in schedules) {
      if (_selectedMedicationIds.contains(schedule.medicationID)) {
        selectedById.putIfAbsent(schedule.medicationID, () => schedule);
      }
    }
    Navigator.pop<List<MedicationSchedule>>(
      context,
      selectedById.values.toList(growable: false),
    );
  }

  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
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
          Expanded(child: _buildContent(viewModel, slots, text)),
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

    if (viewModel.hasTodayScheduleLoadError) {
      return _ScheduleLoadErrorState(
        text: text,
        message: text.scheduleLoadFailed,
        onRetryRequested: viewModel.refreshMedicationSchedule,
      );
    }

    if (viewModel.todayMedicationScheduleList.isEmpty) {
      return _ScheduleEmptyState(text: text);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(34, 14, 34, 12),
      children: [
        for (final slot in slots) ...[
          KeyedSubtree(
            key: _slotKeys[slot.key],
            child: _TimeSlotCard(
              text: text,
              slot: slot,
              userSetting: viewModel.userSetting,
              reminderSetting:
                  viewModel.medicationReminderSettings[slot.key] ??
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
              onStatusChanged: (schedule, medicationStatus) =>
                  _handleMedicationStatusChange(
                    viewModel: viewModel,
                    slot: slot,
                    schedule: schedule,
                    medicationStatus: medicationStatus,
                    text: text,
                  ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  // 함수명: _handleMedicationStatusChange
  // 역할:
  // - 복용 완료 변경을 저장하고, 완료 직후에는 실수로 누른 상태를 되돌릴 기회를 제공한다.
  // - 실행 취소 요청도 동일한 상태 변경 API를 사용해 화면과 서버 상태를 함께 복원한다.
  Future<void> _handleMedicationStatusChange({
    required MedBuddyViewModel viewModel,
    required _ScheduleSlot slot,
    required MedicationSchedule schedule,
    required bool medicationStatus,
    required _ScheduleText text,
  }) async {
    final success = await viewModel.requestMedicationDoseStatusUpdate(
      slot.key,
      schedule,
      medicationStatus,
    );
    if (!mounted) {
      return;
    }
    if (!success) {
      _completionSnackBarGeneration += 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.statusUpdateFailed),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    _completionSnackBarGeneration += 1;
    messenger.hideCurrentSnackBar();
    if (!medicationStatus) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            text.completionCancelled(
              schedule.displayNameForLanguage(text.language),
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final snackBarGeneration = _completionSnackBarGeneration;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          text.completionSaved(
            text.slotTitle(slot.key),
            schedule.displayNameForLanguage(text.language),
          ),
        ),
        duration: _completionSnackBarDuration,
        action: SnackBarAction(
          label: text.undo,
          onPressed: () async {
            _completionSnackBarGeneration += 1;
            final undoSucceeded = await viewModel
                .requestMedicationDoseStatusUpdate(slot.key, schedule, false);
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  undoSucceeded
                      ? text.completionCancelled(
                          schedule.displayNameForLanguage(text.language),
                        )
                      : text.statusUpdateFailed,
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
    Future<void>.delayed(_completionSnackBarDuration, () {
      if (!mounted || snackBarGeneration != _completionSnackBarGeneration) {
        return;
      }
      _completionSnackBarGeneration += 1;
      ScaffoldMessenger.of(
        context,
      ).hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
    });
  }

  void _openHealthRecommendation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HealthRecommendationUI()),
    );
  }

  List<_ScheduleSlot> _buildSlots(MedBuddyViewModel viewModel) {
    return _slotDefinitions
        .map((definition) {
          final medications = viewModel.todayMedicationScheduleList
              .where((schedule) {
                return viewModel
                    .slotKeysForSchedule(schedule)
                    .contains(definition.key);
              })
              .toList(growable: false);
          return _ScheduleSlot(
            definition: definition,
            medications: medications,
          );
        })
        .toList(growable: false);
  }

  List<_ScheduleSlot> _buildSelectionSlots(List<MedicationSchedule> schedules) {
    return _slotDefinitions
        .map((definition) {
          final medications = schedules
              .where(
                (schedule) =>
                    _selectionSlotKeys(schedule).contains(definition.key),
              )
              .toList(growable: false);
          return _ScheduleSlot(
            definition: definition,
            medications: medications,
          );
        })
        .toList(growable: false);
  }

  List<String> _selectionSlotKeys(MedicationSchedule schedule) {
    if (schedule.scheduleSlotKeys.isNotEmpty) {
      return schedule.slotKeys;
    }
    if (schedule.dailyFrequencyCount > 0) {
      return medicationScheduleSlotKeysForFrequency(
        schedule.dailyFrequencyCount,
      );
    }
    return schedule.slotKeys;
  }

  Future<void> _showReminderDialog(
    MedBuddyViewModel viewModel,
    _ScheduleSlot slot,
    _ScheduleText text,
  ) async {
    final setting =
        viewModel.medicationReminderSettings[slot.key] ??
        MedicationAlarm.defaults(slot.key);
    final slotTitle = text.slotTitle(slot.key);
    final selectedTime = await SetNotificationUI.showNotificationPopup(
      context,
      language: viewModel.userSetting.language,
      slotTitle: slotTitle,
      initialTime: TimeOfDay(hour: setting.hour, minute: setting.minute),
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
    if (!mounted) {
      return;
    }
    _showReminderResultMessage(viewModel.statusMessage, success: success);
  }

  Future<void> _handleReminderToggle(
    MedBuddyViewModel viewModel,
    _ScheduleSlot slot,
    _ScheduleText text,
  ) async {
    final setting =
        viewModel.medicationReminderSettings[slot.key] ??
        MedicationAlarm.defaults(slot.key);
    if (!setting.isEnabled) {
      await _showReminderDialog(viewModel, slot, text);
      return;
    }

    final success = await viewModel.requestMedicationReminderCancel(
      slotKey: slot.key,
      slotTitle: text.slotTitle(slot.key),
    );
    if (!mounted) {
      return;
    }
    _showReminderResultMessage(viewModel.statusMessage, success: success);
  }

  // 함수명: _showReminderResultMessage
  // 역할:
  // - 알림 설정 또는 해제 요청의 성공 여부를 화면 하단 안내로 명확히 전달한다.
  void _showReminderResultMessage(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? MedBuddyColors.primaryDark
            : Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showMedicationDetail(
    MedBuddyViewModel viewModel,
    MedicationSchedule schedule,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckMedicationDetailUI(
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
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

// 클래스명: _ScheduleSelectionHeader
// 역할: 오늘 일정 화면과 같은 상단 구조로 채팅에 첨부할 약 선택 목적을 안내한다.
class _ScheduleSelectionHeader extends StatelessWidget {
  final _ScheduleText text;
  final VoidCallback onBackRequested;

  const _ScheduleSelectionHeader({
    required this.text,
    required this.onBackRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + 12,
        28,
        20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: text.back,
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.selectionTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.selectionDescription,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
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

// 클래스명: _ScheduleSelectionFooter
// 역할: 선택한 약의 개수를 보여주고 여러 약 선택 결과를 한 번에 확정한다.
class _ScheduleSelectionFooter extends StatelessWidget {
  final _ScheduleText text;
  final int selectedCount;
  final VoidCallback? onConfirmRequested;

  const _ScheduleSelectionFooter({
    required this.text,
    required this.selectedCount,
    required this.onConfirmRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final useVerticalLayout =
                constraints.maxWidth < 360 || textScale > 1.3;
            final countLabel = Text(
              text.selectedMedicationCount(selectedCount),
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            );
            final confirmButton = FilledButton.icon(
              key: const ValueKey('scheduleMedicationSelectionConfirm'),
              onPressed: onConfirmRequested,
              icon: const Icon(Icons.check_rounded),
              label: Text(text.confirmSelection),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: useVerticalLayout
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        countLabel,
                        const SizedBox(height: 8),
                        confirmButton,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: countLabel),
                        confirmButton,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _TimeSlotCard extends StatelessWidget {
  final _ScheduleText text;
  final _ScheduleSlot slot;
  final UserSetting userSetting;
  final MedicationAlarm reminderSetting;
  final bool Function(MedicationSchedule schedule) isCompletedProvider;
  final VoidCallback onReminderRequested;
  final void Function(MedicationSchedule schedule) onGuideRequested;
  final Future<void> Function(
    MedicationSchedule schedule,
    bool medicationStatus,
  )
  onStatusChanged;
  final bool isSelectionMode;
  final bool Function(MedicationSchedule schedule)? isSelectedProvider;
  final void Function(MedicationSchedule schedule)? onSelectionRequested;

  const _TimeSlotCard({
    required this.text,
    required this.slot,
    required this.userSetting,
    required this.reminderSetting,
    required this.isCompletedProvider,
    required this.onReminderRequested,
    required this.onGuideRequested,
    required this.onStatusChanged,
    this.isSelectionMode = false,
    this.isSelectedProvider,
    this.onSelectionRequested,
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
                          userSetting.formatTime(
                            reminderSetting.isEnabled
                                ? reminderSetting.hour
                                : slot.hour,
                            reminderSetting.isEnabled
                                ? reminderSetting.minute
                                : 0,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isSelectionMode)
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
                  isSelectionMode: isSelectionMode,
                  isSelected: isSelectedProvider?.call(schedule) ?? false,
                  onSelectionRequested: onSelectionRequested == null
                      ? null
                      : () => onSelectionRequested!(schedule),
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionRequested;

  const _MedicationScheduleRow({
    required this.text,
    required this.schedule,
    required this.isCompleted,
    required this.onGuideRequested,
    required this.onStatusChanged,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: isSelectionMode
          ? ValueKey(
              'scheduleMedicationSelectionOption_${schedule.medicationID}',
            )
          : null,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: isSelectionMode && isSelected
            ? const Color(0xFFEAFBF4)
            : Colors.white,
        border: const Border(bottom: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: isSelectionMode
                ? text.selectMedication
                : (isCompleted ? text.undoComplete : text.complete),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isSelectionMode
                  ? onSelectionRequested
                  : () => onStatusChanged(!isCompleted),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSelectionMode
                      ? isSelected
                            ? Icons.check_circle
                            : Icons.circle_outlined
                      : isCompleted
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  color: isSelectionMode
                      ? MedBuddyColors.primary
                      : isCompleted
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
              onTap: isSelectionMode ? onSelectionRequested : onGuideRequested,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.displayNameForLanguage(text.language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCompleted
                            ? MedBuddyColors.textLight
                            : MedBuddyColors.textStrong,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text.dosageLabel(schedule),
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
          const SizedBox(width: 10),
          _MedicationThumbnail(
            schedule: schedule,
            displayName: schedule.displayNameForLanguage(text.language),
            language: text.language,
          ),
        ],
      ),
    );
  }
}

// 클래스명: _MedicationThumbnail
// 역할: 오늘 복약 일정 행 오른쪽에 약품 이미지 또는 대체 표시를 보여준다.
// 주요 책임:
// - 일정 API가 제공한 네트워크 이미지 URL을 고정 크기로 표시한다.
// - URL이 없거나 이미지 로딩에 실패하면 이미지 없음 아이콘을 표시한다.
class _MedicationThumbnail extends StatelessWidget {
  final MedicationSchedule schedule;
  final String displayName;
  final String language;

  const _MedicationThumbnail({
    required this.schedule,
    required this.displayName,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = safeMedicationImageUrl(schedule.imageUrl);
    final hasNetworkImage = imageUrl.isNotEmpty;
    final thumbnailKey = schedule.medicationID.trim().isNotEmpty
        ? schedule.medicationID.trim()
        : displayName;

    return Tooltip(
      message: displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasNetworkImage
            ? () => MedicationImageViewer.show(
                context,
                medicationName: displayName,
                imageUrl: imageUrl,
                language: language,
              )
            : null,
        child: Container(
          key: Key('schedule-medication-thumbnail-$thumbnailKey'),
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MedBuddyColors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasNetworkImage
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _MissingMedicationImage(),
                )
              : const _MissingMedicationImage(),
        ),
      ),
    );
  }
}

// 클래스명: _MissingMedicationImage
// 역할: 약품 사진을 제공할 수 없을 때 일관된 대체 아이콘을 표시한다.
class _MissingMedicationImage extends StatelessWidget {
  const _MissingMedicationImage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: MedBuddyColors.textLight,
        size: 25,
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
    final backgroundColor = isEnabled
        ? Colors.white
        : Colors.white.withValues(alpha: 0.0);

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

// 클래스명: _ScrollableScheduleState
// 역할: 작은 화면과 큰 글씨에서도 빈 상태와 오류 상태를 안전하게 스크롤한다.
class _ScrollableScheduleState extends StatelessWidget {
  final Widget child;

  const _ScrollableScheduleState({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  final _ScheduleText text;

  const _ScheduleEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return _ScrollableScheduleState(
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

class _ScheduleLoadErrorState extends StatelessWidget {
  final _ScheduleText text;
  final String message;
  final Future<void> Function() onRetryRequested;

  const _ScheduleLoadErrorState({
    required this.text,
    required this.message,
    required this.onRetryRequested,
  });

  @override
  Widget build(BuildContext context) {
    return _ScrollableScheduleState(
      child: Container(
        key: const Key('schedule-load-error'),
        width: 320,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: MedBuddyRadii.largeCard,
          boxShadow: MedBuddyShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: MedBuddyColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('schedule-load-retry'),
              onPressed: onRetryRequested,
              icon: const Icon(Icons.refresh),
              label: Text(text.retry),
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

class _ScheduleText {
  final String language;

  const _ScheduleText(this.language);

  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get title => isEnglish ? "Today's Medication Schedule" : '오늘의 복약 일정';
  String get selectionTitle => isEnglish ? 'Choose Medications' : '대화할 약 선택';
  String get selectionDescription => isEnglish
      ? 'Choose one or more medications to include with your message.'
      : '메시지에 함께 보낼 약을 하나 이상 선택해주세요.';
  String selectedMedicationCount(int count) =>
      isEnglish ? '$count selected' : '$count개 선택';
  String get confirmSelection => isEnglish ? 'Done' : '선택 완료';
  String get progress => isEnglish ? 'Progress' : '복용 진행률';
  String get healthRecommendation =>
      isEnglish ? 'View Health Recommendations' : '건강 관리 추천 보기';
  String get emptySlot =>
      isEnglish ? 'No medication for this time' : '복용할 약이 없습니다';
  String get emptySchedule =>
      isEnglish ? 'No medication scheduled for today' : '오늘 복용할 약이 없습니다';
  String get complete => isEnglish ? 'Mark as taken' : '복용 완료';
  String get undoComplete => isEnglish ? 'Undo taken' : '복용 완료 취소';
  String get selectMedication => isEnglish ? 'Select medication' : '약 선택';
  String get close => isEnglish ? 'Close' : '닫기';
  String get statusUpdateFailed =>
      isEnglish ? 'Could not update medication status.' : '복약 상태를 변경하지 못했습니다.';
  String get scheduleLoadFailed => isEnglish
      ? 'Could not load today\'s medication schedule.'
      : '오늘의 복약 일정을 불러오지 못했습니다.';
  String get retry => isEnglish ? 'Retry' : '다시 시도';
  String get undo => isEnglish ? 'Undo' : '실행 취소';

  String completionSaved(String slotTitle, String medicationName) {
    return isEnglish
        ? '$slotTitle · $medicationName marked as taken.'
        : '$slotTitle · $medicationName 복용을 완료했습니다.';
  }

  String completionCancelled(String medicationName) {
    return isEnglish
        ? '$medicationName completion was undone.'
        : '$medicationName 복용 완료를 취소했습니다.';
  }

  // 함수이름: dosageLabel
  // 함수역할:
  // - OCR 투약량이 숫자로만 제공되면 약 이름의 제형에 맞는 단위를 보완한다.
  // - 이미 단위가 포함된 투약량은 원문을 그대로 유지한다.
  // 매개변수:
  // - schedule: 약 이름과 1회 투약량이 포함된 오늘 복약 일정
  // 반환값:
  // - 화면에 표시할 단위 포함 투약량 또는 정보 없음 문구
  String dosageLabel(MedicationSchedule schedule) {
    return schedule.dosageLabelForLanguage(language);
  }

  String reminderTooltip(String slotTitle) {
    return isEnglish ? 'Set $slotTitle reminder' : '$slotTitle 알림 설정';
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
