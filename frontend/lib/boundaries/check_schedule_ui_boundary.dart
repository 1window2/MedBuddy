// 파일명: check_schedule_ui_boundary.dart
// 역할: 시간대별 오늘 일정, 복약 체크, 알림 및 채팅 첨부 선택을 제공한다.

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

// Class Name: CheckScheduleUI
// Role: Represents today's per-slot dose completion, reminders, and attachment selection.
// Responsibilities:
// - Loads today's schedules and reminder settings on entry.
// - Places medications into morning, lunch, evening, and bedtime slots by dose frequency.
// - Opens slot reminder settings and requests local notification scheduling.
// Attributes:
// - initialSlotKey (String?): Key identifying morning, lunch, evening, or bedtime.
// - showBackButton (bool): Whether to show the navigation action leaving the screen.
class CheckScheduleUI extends StatefulWidget {
  final List<MedicationSchedule>? selectionSchedules;
  final String selectionLanguage;
  final Set<String> initialSelectedMedicationIds;
  final String? initialSlotKey;
  final bool showBackButton;

  // Function Name: CheckScheduleUI
  // Description: Initializes today's per-slot dose completion, reminders, and attachment selection with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - initialSlotKey (String?): Key identifying morning, lunch, evening, or bedtime.
  // - showBackButton (bool): Whether to show the navigation action leaving the screen.
  // Returns: Initialized CheckScheduleUI instance.
  const CheckScheduleUI({
    super.key,
    this.initialSlotKey,
    this.showBackButton = true,
  }) : selectionSchedules = null,
       selectionLanguage = 'ko',
       initialSelectedMedicationIds = const {};

  // Function Name: CheckScheduleUI.selection
  // Description: Initializes today's per-slot dose completion, reminders, and attachment selection with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - language (String): Language code selecting visible wording.
  // - selectedMedicationIds (Set<String>): Medication IDs selected for attachment or deletion.
  // Returns: Initialized CheckScheduleUI instance.
  const CheckScheduleUI.selection({
    super.key,
    required List<MedicationSchedule> schedules,
    required String language,
    Set<String> selectedMedicationIds = const {},
  }) : selectionSchedules = schedules,
       selectionLanguage = language,
       initialSelectedMedicationIds = selectedMedicationIds,
       initialSlotKey = null,
       showBackButton = true;

  // 함수이름: isSelectionMode
  // 함수역할: 첨부 선택용 일정 목록이 전달되었는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isSelectionMode => selectionSchedules != null;

  // Function Name: createState
  // Description: Creates the state object that coordinates today's per-slot dose completion, reminders, and attachment selection.
  // Parameters:
  // - None.
  // Returns: A new _CheckScheduleUIState instance.
  @override
  State<CheckScheduleUI> createState() => _CheckScheduleUIState();
}

// Class Name: _CheckScheduleUIState
// Role: Manages state for today's per-slot dose completion, reminders, and attachment selection.
// Responsibilities:
// - Builds chat attachment selection from schedules with dose-status updates disabled.
// - Combines today's completion progress, slot content, and health-recommendation access.
// - Selects schedule loading, failure, or empty states and connects completion and reminder actions to slot cards.
// Attributes:
// - _slotKeys (Map<String, GlobalKey>): Dose-slot keys assigned to the medication.
// - _selectedMedicationIds (Set<String>): Medication IDs selected for attachment or deletion.
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

  final Map<String, GlobalKey> _slotKeys = {
    for (final definition in _slotDefinitions) definition.key: GlobalKey(),
  };
  final Set<String> _updatingEntireSlotKeys = <String>{};
  bool _didRevealInitialSlot = false;
  late Set<String> _selectedMedicationIds;
  // 함수이름: initState
  // 함수역할: 초기 선택 ID를 복사하고 일반 모드에서는 일정을 갱신한 뒤 요청 시간대를 드러낸다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _selectedMedicationIds = {...widget.initialSelectedMedicationIds};
    if (widget.isSelectionMode) {
      return;
    }
    // 함수이름: initState.addPostFrameCallback callback
    // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `context.read<MedBuddyViewModel>(); viewModel.refreshMedicationSchedule()`을 실행한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel = context.read<MedBuddyViewModel>();
      await viewModel.refreshMedicationSchedule();
      if (!mounted) {
        return;
      }
      // 함수이름: initState.addPostFrameCallback callback
      // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `_revealInitialSlot()`을 실행한다.
      // 매개변수:
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _revealInitialSlot();
        }
      });
    });
  }

  // 함수이름: _revealInitialSlot
  // 함수역할: 알림에서 전달된 시간대 카드가 화면에 보이도록 최초 한 번만 이동한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 오늘의 시간대별 복약 체크·알림·첨부 선택 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 오늘의 시간대별 복약 체크·알림·첨부 선택에 쓰는 위젯 트리.
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
      // 함수이름: build.builder callback
      // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

  // 함수이름: _buildSelectionScreen
  // 함수역할: 복약 상태 변경을 비활성화한 일정 목록에서 채팅 첨부 약 선택을 제공한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 오늘의 시간대별 복약 체크·알림·첨부 선택에 쓰는 위젯 트리.
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
            // 함수이름: _buildSelectionScreen.onBackRequested callback
            // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
                    // 함수이름: _buildSelectionScreen.isCompletedProvider callback
                    // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택의 캡처된 상태에서 `false` 값을 제공한다.
                    // 매개변수:
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // 반환값: `false`의 값.
                    isCompletedProvider: (_) => false,
                    // 함수이름: _buildSelectionScreen.onReminderRequested callback
                    // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onReminderRequested: () {},
                    // 함수이름: _buildSelectionScreen.onGuideRequested callback
                    // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
                    // 매개변수:
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onGuideRequested: (_) {},
                    // 함수이름: _buildSelectionScreen.onStatusChanged callback
                    // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
                    // 매개변수:
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onStatusChanged: (_, _) async {},
                    isSelectionMode: true,
                    // 함수이름: _buildSelectionScreen.isSelectedProvider callback
                    // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `_selectedMedicationIds.contains(schedule.medicationID)`을 실행한다.
                    // 매개변수:
                    // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
                // 함수이름: _buildSelectionScreen.onConfirmRequested callback
                // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `_completeMedicationSelection(context, schedules)`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                : () => _completeMedicationSelection(context, schedules),
          ),
        ],
      ),
    );
  }

  // 함수이름: _toggleMedicationSelection
  // 함수역할: 같은 약이 여러 시간대에 보여도 약 식별자 하나를 기준으로 선택 상태를 바꾼다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _toggleMedicationSelection(MedicationSchedule schedule) {
    // 함수이름: _toggleMedicationSelection.setState callback
    // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `_selectedMedicationIds.add(medicationId); _selectedMedicationIds.remove(medicationId)`을 실행한다.
    // 매개변수:
    // - 없음.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    setState(() {
      final medicationId = schedule.medicationID;
      if (!_selectedMedicationIds.add(medicationId)) {
        _selectedMedicationIds.remove(medicationId);
      }
    });
  }

  // 함수이름: _completeMedicationSelection
  // 함수역할: 화면에 표시된 순서를 유지하면서 중복 없이 선택한 약 목록을 채팅 화면으로 반환한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _completeMedicationSelection(
    BuildContext context,
    List<MedicationSchedule> schedules,
  ) {
    final selectedById = <String, MedicationSchedule>{};
    for (final schedule in schedules) {
      if (_selectedMedicationIds.contains(schedule.medicationID)) {
        // 함수이름: _completeMedicationSelection.putIfAbsent callback
        // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택의 새 키의 초기값을 `schedule` 규칙으로 계산한다.
        // 매개변수:
        // - 없음.
        // 반환값: 컬렉션 연산에 전달할 새 키의 초기값.
        selectedById.putIfAbsent(schedule.medicationID, () => schedule);
      }
    }
    Navigator.pop<List<MedicationSchedule>>(
      context,
      selectedById.values.toList(growable: false),
    );
  }

  // Function Name: _buildScreen
  // Description: Combines today's completion progress, slot content, and health-recommendation access.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: Widget tree for today's per-slot dose completion, reminders, and attachment selection.
  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
    final text = _ScheduleText(viewModel.userSetting.language);
    final slots = _buildSlots(viewModel);
    final progress = viewModel.todayMedicationProgress;
    final hasTodaySchedule = viewModel.todayMedicationScheduleList.isNotEmpty;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: Column(
        children: [
          _ScheduleHeader(
            text: text,
            completedCount: progress.completedCount,
            totalCount: progress.totalCount,
            onBackRequested: widget.showBackButton
                // Function Name: _buildScreen.onBackRequested callback
                // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
                // Parameters:
                // - None.
                // Returns: No callback payload; any selection is delivered through the route result.
                ? () => Navigator.pop(context)
                : null,
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

  // Function Name: _buildContent
  // Description: Selects schedule loading, failure, or empty states and connects completion and reminder actions to slot cards.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slots (List<_ScheduleSlot>): List combining per-slot medications and presentation definitions.
  // - text (_ScheduleText): Localized labels used by this section.
  // Returns: Widget tree for today's per-slot dose completion, reminders, and attachment selection.
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: MedBuddySpacing.contentMaxWidth,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
                  // 함수이름: _buildContent.isCompletedProvider callback
                  // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `viewModel.isMedicationDoseCompleted(slot.key, schedule)`을 실행한다.
                  // 매개변수:
                  // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  isCompletedProvider: (schedule) {
                    return viewModel.isMedicationDoseCompleted(
                      slot.key,
                      schedule,
                    );
                  },
                  // 함수이름: _buildContent.onReminderRequested callback
                  // 함수역할: 꺼진 알림은 시간 편집으로 켜고 켜진 알림은 취소 요청을 보낸다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onReminderRequested: () {
                    _handleReminderToggle(viewModel, slot, text);
                  },
                  // Function Name: _buildContent.onGuideRequested callback
                  // Description: Converts today's medication schedule to detail data and opens details with current settings.
                  // Parameters:
                  // - schedule (inferred by callback contract): Medication schedule containing name, dosage, days, slots, and completion state.
                  // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                  onGuideRequested: (schedule) {
                    _showMedicationDetail(viewModel, schedule);
                  },
                  // 함수이름: _buildContent.onStatusChanged callback
                  // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `_handleMedicationStatusChange(viewModel: viewModel, slot: slot, schedule: schedule, medicationStatus: medicationStatus, text: text)`을 실행한다.
                  // 매개변수:
                  // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
                  // - medicationStatus (콜백 계약에서 추론): 복약 또는 저장 작업의 완료 상태.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onStatusChanged: (schedule, medicationStatus) =>
                      _handleMedicationStatusChange(
                        viewModel: viewModel,
                        slot: slot,
                        schedule: schedule,
                        medicationStatus: medicationStatus,
                        text: text,
                      ),
                  isEntireSlotCompleted:
                      slot.medications.isNotEmpty &&
                      slot.medications.every(
                        // Function Name: _buildContent.every callback
                        // Description: Checks the collection condition `viewModel.isMedicationDoseCompleted(slot.key, schedule)` for today's per-slot dose completion, reminders, and attachment selection.
                        // Parameters:
                        // - schedule (inferred by callback contract): Medication schedule containing name, dosage, days, slots, and completion state.
                        // Returns: Boolean predicate result for the supplied item.
                        (schedule) => viewModel.isMedicationDoseCompleted(
                          slot.key,
                          schedule,
                        ),
                      ),
                  isEntireSlotUpdating: _updatingEntireSlotKeys.contains(
                    slot.key,
                  ),
                  // Function Name: _buildContent.onEntireSlotStatusChanged callback
                  // Description: Connects today's per-slot dose completion, reminders, and attachment selection to the captured operation `_handleEntireSlotStatusChange(viewModel: viewModel, slot: slot, medicationStatus: medicationStatus, text: text)`.
                  // Parameters:
                  // - medicationStatus (inferred by callback contract): Completion state of the dose or save operation.
                  // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                  onEntireSlotStatusChanged: (medicationStatus) =>
                      _handleEntireSlotStatusChange(
                        viewModel: viewModel,
                        slot: slot,
                        medicationStatus: medicationStatus,
                        text: text,
                      ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  // 함수이름: _handleMedicationStatusChange
  // 함수역할: 복용 완료 변경을 저장하고, 완료 직후에는 실수로 누른 상태를 되돌릴 기회를 제공한다. 실행 취소 요청도 동일한 상태 변경 API를 사용해 화면과 서버 상태를 함께 복원한다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - slot (_ScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - medicationStatus (bool): 복약 또는 저장 작업의 완료 상태.
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.statusUpdateFailed),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
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

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          text.completionSaved(
            text.slotTitle(slot.key),
            schedule.displayNameForLanguage(text.language),
          ),
        ),
        duration: _completionSnackBarDuration,
        persist: false,
        action: SnackBarAction(
          label: text.undo,
          // 함수이름: _handleMedicationStatusChange.onPressed callback
          // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에서 캡처된 작업 `viewModel.requestMedicationDoseStatusUpdate(slot.key, schedule, false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(undoSucceeded ? text.completionCancelled(schedule.displayNameForLanguage(tex...`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onPressed: () async {
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
  }

  // Function Name: _handleEntireSlotStatusChange
  // Description: Applies one completion state to every medication in the selected slot. Prevents repeated taps while the atomic backend request is in flight and reports one concise result for the whole action.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slot (_ScheduleSlot): Dose-slot identity, time, and presentation data.
  // - medicationStatus (bool): Completion state of the dose or save operation.
  // - text (_ScheduleText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _handleEntireSlotStatusChange({
    required MedBuddyViewModel viewModel,
    required _ScheduleSlot slot,
    required bool medicationStatus,
    required _ScheduleText text,
  }) async {
    if (_updatingEntireSlotKeys.contains(slot.key) ||
        slot.medications.isEmpty) {
      return;
    }
    // Function Name: _handleEntireSlotStatusChange.setState callback
    // Description: Connects today's per-slot dose completion, reminders, and attachment selection to the captured operation `_updatingEntireSlotKeys.add(slot.key)`.
    // Parameters:
    // - None.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    setState(() => _updatingEntireSlotKeys.add(slot.key));
    final success = await viewModel.requestMedicationSlotStatusUpdate(
      slot.key,
      medicationStatus,
    );
    if (!mounted) {
      return;
    }
    // Function Name: _handleEntireSlotStatusChange.setState callback
    // Description: Connects today's per-slot dose completion, reminders, and attachment selection to the captured operation `_updatingEntireSlotKeys.remove(slot.key)`.
    // Parameters:
    // - None.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    setState(() => _updatingEntireSlotKeys.remove(slot.key));

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? medicationStatus
                    ? text.entireSlotCompletionSaved(text.slotTitle(slot.key))
                    : text.entireSlotCompletionCancelled(
                        text.slotTitle(slot.key),
                      )
              : text.statusUpdateFailed,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 함수이름: _openHealthRecommendation
  // 함수역할: 오늘 일정에서 건강 관리 추천 화면을 연다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _openHealthRecommendation() {
    Navigator.push(
      context,
      // 함수이름: _openHealthRecommendation.builder callback
      // 함수역할: builder에서 건강 추천의 로딩·오류·완료 결과 위젯을 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      MaterialPageRoute(builder: (context) => const HealthRecommendationUI()),
    );
  }

  // 함수이름: _buildSlots
  // 함수역할: ViewModel의 시간대 배정 규칙으로 오늘 약품을 기본 시간대별로 묶는다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // 반환값: List<_ScheduleSlot>: 기본 시간대별로 분류된 약품과 표시 정보.
  List<_ScheduleSlot> _buildSlots(MedBuddyViewModel viewModel) {
    return _slotDefinitions
        // 함수이름: _buildSlots.map callback
        // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택의 변환값을 `_ScheduleSlot(definition: definition, medications: medications)` 규칙으로 계산한다.
        // 매개변수:
        // - definition (콜백 계약에서 추론): 복약 시간대의 식별·시각·표시 정보.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((definition) {
          final medications = viewModel.todayMedicationScheduleList
              // 함수이름: _buildSlots.where callback
              // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에 대해 `viewModel.slotKeysForSchedule(schedule).contains(definition.key)` 조건으로 컬렉션 항목을 판별한다.
              // 매개변수:
              // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
              // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
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

  // 함수이름: _buildSelectionSlots
  // 함수역할: 첨부용 일정의 명시 시간대 또는 횟수 기반 시간대로 선택 카드를 만든다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // 반환값: List<_ScheduleSlot>: 기본 시간대별로 분류된 약품과 표시 정보.
  List<_ScheduleSlot> _buildSelectionSlots(List<MedicationSchedule> schedules) {
    return _slotDefinitions
        // 함수이름: _buildSelectionSlots.map callback
        // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택의 변환값을 `_ScheduleSlot(definition: definition, medications: medications)` 규칙으로 계산한다.
        // 매개변수:
        // - definition (콜백 계약에서 추론): 복약 시간대의 식별·시각·표시 정보.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((definition) {
          final medications = schedules
              .where(
                // 함수이름: _buildSelectionSlots.where callback
                // 함수역할: 오늘의 시간대별 복약 체크·알림·첨부 선택에 대해 `_selectionSlotKeys(schedule).contains(definition.key)` 조건으로 컬렉션 항목을 판별한다.
                // 매개변수:
                // - schedule (콜백 계약에서 추론): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
                // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
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

  // 함수이름: _selectionSlotKeys
  // 함수역할: 명시된 시간대를 우선하고 없으면 양수 복용 횟수에 따른 시간대를 사용한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: List<String>: 정리·선택된 표시 문구 또는 복약 시간대 키 목록.
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

  // 함수이름: _showReminderDialog
  // 함수역할: 현재 알림 시각 편집 창을 열고 확정된 시각으로 시간대 알림을 저장한다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - slot (_ScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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

  // 함수이름: _handleReminderToggle
  // 함수역할: 꺼진 알림은 시간 편집으로 켜고 켜진 알림은 취소 요청을 보낸다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - slot (_ScheduleSlot): 복약 시간대의 식별·시각·표시 정보.
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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

  // 함수이름: _showReminderResultMessage
  // 함수역할: 알림 설정 또는 해제 요청의 성공 여부를 화면 하단 안내로 명확히 전달한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - success (bool): 직전 저장·조회·변경 요청의 성공 여부.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // Function Name: _showMedicationDetail
  // Description: Converts today's medication schedule to detail data and opens details with current settings.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - schedule (MedicationSchedule): Medication schedule containing name, dosage, days, slots, and completion state.
  // Returns: None; updates state or performs the documented action.
  void _showMedicationDetail(
    MedBuddyViewModel viewModel,
    MedicationSchedule schedule,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // Function Name: _showMedicationDetail.builder callback
        // Description: Composes today's per-slot dose completion, reminders, and attachment selection with the current parent constraints for the active layout.
        // Parameters:
        // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
        // Returns: Widget subtree for the described layout or fallback.
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: MedicationDetail.fromMedicationSchedule(schedule),
          userSetting: viewModel.userSetting,
        ),
      ),
    );
  }
}

// 클래스명: _HealthRecommendationFooter
// 역할: 오늘 일정에서 건강 추천 열기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 오늘 일정에서 건강 추천 열기 위젯을 구성한다.
// 속성:
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _HealthRecommendationFooter extends StatelessWidget {
  final _ScheduleText text;
  final VoidCallback onPressed;

  // 함수이름: _HealthRecommendationFooter
  // 함수역할: 오늘 일정에서 건강 추천 열기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationFooter 인스턴스.
  const _HealthRecommendationFooter({
    required this.text,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 오늘 일정에서 건강 추천 열기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 오늘 일정에서 건강 추천 열기에 쓰는 위젯 트리.
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

// Class Name: _ScheduleHeader
// Role: Represents today's date and dose completion progress.
// Responsibilities:
// - Composes today's date and dose completion progress using the display values and actions supplied by its parent.
// Attributes:
// - completedCount (int): Number of completed doses.
// - totalCount (int): Total scheduled doses or operation items.
// - onBackRequested (VoidCallback?): Callback for back navigation or closing the current screen.
class _ScheduleHeader extends StatelessWidget {
  final _ScheduleText text;
  final int completedCount;
  final int totalCount;
  final VoidCallback? onBackRequested;

  // 함수이름: _ScheduleHeader
  // 함수역할: 오늘 날짜와 복약 완료 진행률에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // - completedCount (int): 완료한 복약 횟수.
  // - totalCount (int): 예정된 전체 복약 횟수 또는 처리 항목 수.
  // - onBackRequested (VoidCallback?): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _ScheduleHeader 인스턴스.
  const _ScheduleHeader({
    required this.text,
    required this.completedCount,
    required this.totalCount,
    required this.onBackRequested,
  });

  // Function Name: build
  // Description: Renders today's date and dose completion progress from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for today's date and dose completion progress.
  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF249B62), MedBuddyColors.topBar],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 12,
        20,
        18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBackRequested != null) ...[
                IconButton(
                  tooltip: text.back,
                  onPressed: onBackRequested,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(left: 12, right: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text.progress,
                        style: const TextStyle(
                          color: Color(0xFFD6F2E3),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$completedCount/$totalCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
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
                    minHeight: 7,
                    color: Color(0xFFE7FFF1),
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
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
// 역할: 채팅에 첨부할 약 선택 화면의 제목과 뒤로가기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 채팅에 첨부할 약 선택 화면의 제목과 뒤로가기 위젯을 구성한다.
// 속성:
// - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
class _ScheduleSelectionHeader extends StatelessWidget {
  final _ScheduleText text;
  final VoidCallback onBackRequested;

  // 함수이름: _ScheduleSelectionHeader
  // 함수역할: 채팅에 첨부할 약 선택 화면의 제목과 뒤로가기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _ScheduleSelectionHeader 인스턴스.
  const _ScheduleSelectionHeader({
    required this.text,
    required this.onBackRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 채팅에 첨부할 약 선택 화면의 제목과 뒤로가기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 채팅에 첨부할 약 선택 화면의 제목과 뒤로가기에 쓰는 위젯 트리.
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
// 역할: 첨부할 약의 선택 개수와 일괄 확정을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 첨부할 약의 선택 개수와 일괄 확정 위젯을 구성한다.
// 속성:
// - selectedCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
// - onConfirmRequested (VoidCallback?): 현재 선택·검토 결과를 확정할 콜백.
class _ScheduleSelectionFooter extends StatelessWidget {
  final _ScheduleText text;
  final int selectedCount;
  final VoidCallback? onConfirmRequested;

  // 함수이름: _ScheduleSelectionFooter
  // 함수역할: 첨부할 약의 선택 개수와 일괄 확정에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // - selectedCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - onConfirmRequested (VoidCallback?): 현재 선택·검토 결과를 확정할 콜백.
  // 반환값: 입력 설정이 반영된 _ScheduleSelectionFooter 인스턴스.
  const _ScheduleSelectionFooter({
    required this.text,
    required this.selectedCount,
    required this.onConfirmRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 첨부할 약의 선택 개수와 일괄 확정 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 첨부할 약의 선택 개수와 일괄 확정에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          // 함수이름: build.builder callback
          // 함수역할: 첨부할 약의 선택 개수와 일괄 확정에 TextStyle, ValueKey, Icon, EdgeInsets.fromLTRB, SizedBox을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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

// Class Name: _TimeSlotCard
// Role: Represents a dose slot's medication list, reminder control, and whole-slot completion action.
// Responsibilities:
// - Composes a dose slot's medication list, reminder control, and whole-slot completion action using the display values and actions supplied by its parent.
// Attributes:
// - slot (_ScheduleSlot): Dose-slot identity, time, and presentation data.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - reminderSetting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
// - isCompletedProvider (bool Function(MedicationSchedule schedule)): Function determining an item's current selection or completion state.
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
  final bool isEntireSlotCompleted;
  final bool isEntireSlotUpdating;
  final Future<void> Function(bool medicationStatus)? onEntireSlotStatusChanged;

  // Function Name: _TimeSlotCard
  // Description: Initializes a dose slot's medication list, reminder control, and whole-slot completion action with the supplied configuration.
  // Parameters:
  // - text (_ScheduleText): Localized labels used by this section.
  // - slot (_ScheduleSlot): Dose-slot identity, time, and presentation data.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // - reminderSetting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
  // - isCompletedProvider (bool Function(MedicationSchedule schedule)): Function determining an item's current selection or completion state.
  // - onReminderRequested (VoidCallback): Callback opening the associated slot's reminder settings.
  // - onGuideRequested (void Function(MedicationSchedule schedule)): Callback opening medication details or dosage guidance.
  // - onStatusChanged (Future<void> Function(MedicationSchedule schedule, bool medicationStatus)): Callback reporting a medication's dose-completion change.
  // - isSelectionMode (bool): Whether attachment or deletion selection replaces normal interaction.
  // - isSelectedProvider (bool Function(MedicationSchedule schedule)?): Function determining an item's current selection or completion state.
  // - onSelectionRequested (void Function(MedicationSchedule schedule)?): Callback reporting the changed value or selection state to the owning screen.
  // - isEntireSlotCompleted (bool): Completion state of the dose or save operation.
  // - isEntireSlotUpdating (bool): Whether the associated save, analysis, or medication update is in progress.
  // - onEntireSlotStatusChanged (Future<void> Function(bool medicationStatus)?): Callback requesting a whole-slot completion change.
  // Returns: Initialized _TimeSlotCard instance.
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
    this.isEntireSlotCompleted = false,
    this.isEntireSlotUpdating = false,
    this.onEntireSlotStatusChanged,
  });

  // Function Name: build
  // Description: Renders a dose slot's medication list, reminder control, and whole-slot completion action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a dose slot's medication list, reminder control, and whole-slot completion action.
  @override
  Widget build(BuildContext context) {
    final slotTitle = text.slotTitle(slot.key);

    return Material(
      color: MedBuddyColors.lavenderSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.card,
        side: const BorderSide(color: MedBuddyColors.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: MedBuddyRadii.card,
        child: Column(
          children: [
            Container(
              color: slot.color,
              padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(slot.icon, color: Colors.white, size: 23),
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
                            fontSize: 18,
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
                  if (!isSelectionMode) ...[
                    _ReminderIconButton(
                      text: text,
                      slotTitle: slotTitle,
                      isEnabled: reminderSetting.isEnabled,
                      onPressed: onReminderRequested,
                    ),
                    if (slot.medications.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      _SlotCompletionToggleButton(
                        text: text,
                        slotKey: slot.key,
                        slotTitle: slotTitle,
                        isCompleted: isEntireSlotCompleted,
                        isUpdating: isEntireSlotUpdating,
                        onPressed: onEntireSlotStatusChanged == null
                            ? null
                            // Function Name: build.onPressed callback
                            // Description: Supplies `onEntireSlotStatusChanged!(!isEntireSlotCompleted)` from the captured state of a dose slot's medication list, reminder control, and whole-slot completion action.
                            // Parameters:
                            // - None.
                            // Returns: The value of `onEntireSlotStatusChanged!(!isEntireSlotCompleted)`.
                            : () => onEntireSlotStatusChanged!(
                                !isEntireSlotCompleted,
                              ),
                      ),
                    ],
                  ],
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
                  // 함수이름: build.onGuideRequested callback
                  // 함수역할: 시간대별 복약 목록·알림·전체 체크 명령에서 캡처된 작업 `onGuideRequested(schedule)`을 실행한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onGuideRequested: () => onGuideRequested(schedule),
                  // 함수이름: build.onStatusChanged callback
                  // 함수역할: 시간대별 복약 목록·알림·전체 체크 명령에서 캡처된 작업 `onStatusChanged(schedule, value)`을 실행한다.
                  // 매개변수:
                  // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onStatusChanged: (value) => onStatusChanged(schedule, value),
                  isStatusUpdating: isEntireSlotUpdating,
                  isSelectionMode: isSelectionMode,
                  isSelected: isSelectedProvider?.call(schedule) ?? false,
                  onSelectionRequested: onSelectionRequested == null
                      ? null
                      // 함수이름: build.onSelectionRequested callback
                      // 함수역할: 시간대별 복약 목록·알림·전체 체크 명령의 캡처된 상태에서 `onSelectionRequested!(schedule)` 값을 제공한다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: `onSelectionRequested!(schedule)`의 값.
                      : () => onSelectionRequested!(schedule),
                ),
          ],
        ),
      ),
    );
  }
}

// Class Name: _MedicationScheduleRow
// Role: Represents one medication's slot completion, details, and attachment selection.
// Responsibilities:
// - Composes one medication's slot completion, details, and attachment selection using the display values and actions supplied by its parent.
// Attributes:
// - schedule (MedicationSchedule): Medication schedule containing name, dosage, days, slots, and completion state.
// - isCompleted (bool): Completion state of the dose or save operation.
// - onGuideRequested (VoidCallback): Callback opening medication details or dosage guidance.
// - onStatusChanged (Future<void> Function(bool medicationStatus)): Callback reporting a medication's dose-completion change.
class _MedicationScheduleRow extends StatelessWidget {
  final _ScheduleText text;
  final MedicationSchedule schedule;
  final bool isCompleted;
  final VoidCallback onGuideRequested;
  final Future<void> Function(bool medicationStatus) onStatusChanged;
  final bool isStatusUpdating;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionRequested;

  // Function Name: _MedicationScheduleRow
  // Description: Initializes one medication's slot completion, details, and attachment selection with the supplied configuration.
  // Parameters:
  // - text (_ScheduleText): Localized labels used by this section.
  // - schedule (MedicationSchedule): Medication schedule containing name, dosage, days, slots, and completion state.
  // - isCompleted (bool): Completion state of the dose or save operation.
  // - onGuideRequested (VoidCallback): Callback opening medication details or dosage guidance.
  // - onStatusChanged (Future<void> Function(bool medicationStatus)): Callback reporting a medication's dose-completion change.
  // - isStatusUpdating (bool): Whether the associated save, analysis, or medication update is in progress.
  // - isSelectionMode (bool): Whether attachment or deletion selection replaces normal interaction.
  // - isSelected (bool): Whether the item belongs to the current selection.
  // - onSelectionRequested (VoidCallback?): Callback reporting the changed value or selection state to the owning screen.
  // Returns: Initialized _MedicationScheduleRow instance.
  const _MedicationScheduleRow({
    required this.text,
    required this.schedule,
    required this.isCompleted,
    required this.onGuideRequested,
    required this.onStatusChanged,
    this.isStatusUpdating = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionRequested,
  });

  // Function Name: build
  // Description: Renders one medication's slot completion, details, and attachment selection from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for one medication's slot completion, details, and attachment selection.
  @override
  Widget build(BuildContext context) {
    return Container(
      key: isSelectionMode
          ? ValueKey(
              'scheduleMedicationSelectionOption_${schedule.medicationID}',
            )
          : null,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
                  : isStatusUpdating
                  ? null
                  // 함수이름: build.onTap callback
                  // 함수역할: 약 한 건의 시간대 체크 상태와 상세·첨부 선택에서 캡처된 작업 `onStatusChanged(!isCompleted)`을 실행한다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  : () => onStatusChanged(!isCompleted),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: isStatusUpdating && !isSelectionMode
                    ? const SizedBox(
                        width: 25,
                        height: 25,
                        child: Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Icon(
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
                        size: 25,
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
                        fontSize: 16,
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
                        fontSize: 13,
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
// 역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시를 담당한다.
// 주요 책임:
// - 일정 API가 제공한 네트워크 이미지 URL을 고정 크기로 표시한다.
// - URL이 없거나 이미지 로딩에 실패하면 이미지 없음 아이콘을 표시한다.
// 속성:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
// - language (String): 화면 문구를 선택할 언어 코드.
class _MedicationThumbnail extends StatelessWidget {
  final MedicationSchedule schedule;
  final String displayName;
  final String language;

  // 함수이름: _MedicationThumbnail
  // 함수역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationThumbnail 인스턴스.
  const _MedicationThumbnail({
    required this.schedule,
    required this.displayName,
    required this.language,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 사진과 사진 부재·불러오기 실패 대체 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 사진과 사진 부재·불러오기 실패 대체 표시에 쓰는 위젯 트리.
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
            // 함수이름: build.onTap callback
            // 함수역할: 약품 사진과 사진 부재·불러오기 실패 대체 표시에서 캡처된 작업 `MedicationImageViewer.show(context, medicationName: displayName, imageUrl: imageUrl, language: language)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
                  // 함수이름: build.errorBuilder callback
                  // 함수역할: errorBuilder에서 사진을 표시할 수 없는 약품의 대체 아이콘 위젯을 구성한다.
                  // 매개변수:
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  errorBuilder: (_, _, _) => const _MissingMedicationImage(),
                )
              : const _MissingMedicationImage(),
        ),
      ),
    );
  }
}

// 클래스명: _MissingMedicationImage
// 역할: 사진을 표시할 수 없는 약품의 대체 아이콘을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 사진을 표시할 수 없는 약품의 대체 아이콘 위젯을 구성한다.
class _MissingMedicationImage extends StatelessWidget {
  // 함수이름: _MissingMedicationImage
  // 함수역할: 사진을 표시할 수 없는 약품의 대체 아이콘에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값: 입력 설정이 반영된 _MissingMedicationImage 인스턴스.
  const _MissingMedicationImage();

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 사진을 표시할 수 없는 약품의 대체 아이콘 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 사진을 표시할 수 없는 약품의 대체 아이콘에 쓰는 위젯 트리.
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

// 클래스명: _ReminderIconButton
// 역할: 알림 설정 여부를 나타내는 시간대별 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 알림 설정 여부를 나타내는 시간대별 명령 위젯을 구성한다.
// 속성:
// - slotTitle (String): 시간대 또는 알림 시각의 표시 문구.
// - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _ReminderIconButton extends StatelessWidget {
  final _ScheduleText text;
  final String slotTitle;
  final bool isEnabled;
  final VoidCallback onPressed;

  // 함수이름: _ReminderIconButton
  // 함수역할: 알림 설정 여부를 나타내는 시간대별 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // - slotTitle (String): 시간대 또는 알림 시각의 표시 문구.
  // - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _ReminderIconButton 인스턴스.
  const _ReminderIconButton({
    required this.text,
    required this.slotTitle,
    required this.isEnabled,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 알림 설정 여부를 나타내는 시간대별 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 알림 설정 여부를 나타내는 시간대별 명령에 쓰는 위젯 트리.
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

// Class Name: _SlotCompletionToggleButton
// Role: Represents the atomic whole-slot medication completion or uncheck action.
// Responsibilities:
// - Presents a distinct whole-slot action beside the reminder control.
// - Communicates the next action through its icon, tooltip, and semantics.
// - Prevents duplicate requests while the atomic update is running.
// Attributes:
// - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
// - slotTitle (String): Display label for a dose slot or reminder time.
// - isCompleted (bool): Completion state of the dose or save operation.
// - isUpdating (bool): Whether the associated save, analysis, or medication update is in progress.
class _SlotCompletionToggleButton extends StatelessWidget {
  final _ScheduleText text;
  final String slotKey;
  final String slotTitle;
  final bool isCompleted;
  final bool isUpdating;
  final VoidCallback? onPressed;

  // Function Name: _SlotCompletionToggleButton
  // Description: Initializes the atomic whole-slot medication completion or uncheck action with the supplied configuration.
  // Parameters:
  // - text (_ScheduleText): Localized labels used by this section.
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // - isCompleted (bool): Completion state of the dose or save operation.
  // - isUpdating (bool): Whether the associated save, analysis, or medication update is in progress.
  // - onPressed (VoidCallback?): Callback executing the item's documented primary action.
  // Returns: Initialized _SlotCompletionToggleButton instance.
  const _SlotCompletionToggleButton({
    required this.text,
    required this.slotKey,
    required this.slotTitle,
    required this.isCompleted,
    required this.isUpdating,
    required this.onPressed,
  });

  // Function Name: build
  // Description: Renders the atomic whole-slot medication completion or uncheck action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the atomic whole-slot medication completion or uncheck action.
  @override
  Widget build(BuildContext context) {
    final tooltip = text.entireSlotTooltip(slotTitle, isCompleted);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: !isUpdating && onPressed != null,
        child: Material(
          color: isCompleted
              ? Colors.white
              : Colors.white.withValues(alpha: 0.0),
          shape: const CircleBorder(),
          child: InkWell(
            key: ValueKey('schedule-entire-slot-toggle-$slotKey'),
            customBorder: const CircleBorder(),
            onTap: isUpdating ? null : onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: isUpdating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isCompleted
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        color: isCompleted
                            ? MedBuddyColors.primaryDark
                            : Colors.white,
                        size: 27,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _ScrollableScheduleState
// 역할: 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문 위젯을 구성한다.
// 속성:
// - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
class _ScrollableScheduleState extends StatelessWidget {
  final Widget child;

  // 함수이름: _ScrollableScheduleState
  // 함수역할: 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
  // 반환값: 입력 설정이 반영된 _ScrollableScheduleState 인스턴스.
  const _ScrollableScheduleState({required this.child});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // 함수이름: build.builder callback
      // 함수역할: 큰 글씨에서도 스크롤 가능한 일정 빈 상태·오류 본문에 EdgeInsets.symmetric을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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

// 클래스명: _ScheduleEmptyState
// 역할: 오늘 일정 부재 안내와 처방전 입력 진입을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 오늘 일정 부재 안내와 처방전 입력 진입 위젯을 구성한다.
class _ScheduleEmptyState extends StatelessWidget {
  final _ScheduleText text;

  // 함수이름: _ScheduleEmptyState
  // 함수역할: 오늘 일정 부재 안내와 처방전 입력 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ScheduleText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _ScheduleEmptyState 인스턴스.
  const _ScheduleEmptyState({required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 오늘 일정 부재 안내와 처방전 입력 진입 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 오늘 일정 부재 안내와 처방전 입력 진입에 쓰는 위젯 트리.
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

// 클래스명: _ScheduleLoadErrorState
// 역할: 일정 조회 실패와 재시도를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 일정 조회 실패와 재시도 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - onRetryRequested (Future<void> Function()): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
class _ScheduleLoadErrorState extends StatelessWidget {
  final _ScheduleText text;
  final String message;
  final Future<void> Function() onRetryRequested;

  // Function Name: _ScheduleLoadErrorState
  // Description: Initializes the schedule-load failure and retry action with the supplied configuration.
  // Parameters:
  // - text (_ScheduleText): Localized labels used by this section.
  // - message (String): Visible wording for the current result, error, or state.
  // - onRetryRequested (Future<void> Function()): Callback reloading failed or stale screen data.
  // Returns: Initialized _ScheduleLoadErrorState instance.
  const _ScheduleLoadErrorState({
    required this.text,
    required this.message,
    required this.onRetryRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 일정 조회 실패와 재시도 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 일정 조회 실패와 재시도에 쓰는 위젯 트리.
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

// 클래스명: _ScheduleSlotDefinition
// 역할: 시간대별 색상·아이콘·기본 알림 시각을 담당한다.
// 주요 책임:
// - 시간대별 색상·아이콘·기본 알림 시각 관련 필드 값을 하나의 객체로 묶어 전달한다.
// 속성:
// - key (String): 복약 시간대를 구분하는 식별 문자열.
// - title (String): 화면·구역·항목에 표시할 제목.
// - hour (int): 24시간제 시 값.
// - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
class _ScheduleSlotDefinition {
  final String key;
  final String title;
  final int hour;
  final Color color;
  final IconData icon;

  // 함수이름: _ScheduleSlotDefinition
  // 함수역할: 시간대별 색상·아이콘·기본 알림 시각 관련 값을 _ScheduleSlotDefinition 인스턴스에 담는다.
  // 매개변수:
  // - key (String): 복약 시간대를 구분하는 식별 문자열.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - hour (int): 24시간제 시 값.
  // - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // 반환값: 입력 설정이 반영된 _ScheduleSlotDefinition 인스턴스.
  const _ScheduleSlotDefinition({
    required this.key,
    required this.title,
    required this.hour,
    required this.color,
    required this.icon,
  });
}

// 클래스명: _ScheduleSlot
// 역할: 시간대에 배치된 약품과 표시 정보를 담당한다.
// 주요 책임:
// - 시간대 기본 시각을 두 자리 시와 분으로 표시한다.
// 속성:
// - definition (_ScheduleSlotDefinition): 복약 시간대의 식별·시각·표시 정보.
// - medications (List<MedicationSchedule>): 조회·선택·정렬·표시에 사용할 약품 목록.
class _ScheduleSlot {
  final _ScheduleSlotDefinition definition;
  final List<MedicationSchedule> medications;

  // 함수이름: _ScheduleSlot
  // 함수역할: 시간대에 배치된 약품과 표시 정보 관련 값을 _ScheduleSlot 인스턴스에 담는다.
  // 매개변수:
  // - definition (_ScheduleSlotDefinition): 복약 시간대의 식별·시각·표시 정보.
  // - medications (List<MedicationSchedule>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: 입력 설정이 반영된 _ScheduleSlot 인스턴스.
  const _ScheduleSlot({required this.definition, required this.medications});

  // 함수이름: key
  // 함수역할: 공통 시간대 정의의 시간대 식별 키를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get key => definition.key;
  // 함수이름: title
  // 함수역할: 공통 시간대 정의의 시간대 제목을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => definition.title;
  // 함수이름: hour
  // 함수역할: 공통 시간대 정의의 기본 알림 시를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: int: 공통 시간대 정의에 지정된 기본 알림 시.
  int get hour => definition.hour;
  // 함수이름: color
  // 함수역할: 공통 시간대 정의의 시간대 강조 색상을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: Color: 공통 시간대 정의의 강조 색상.
  Color get color => definition.color;
  // 함수이름: icon
  // 함수역할: 공통 시간대 정의의 시간대 아이콘을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: IconData: 현재 시간대·빠른 답장 종류에 대응하는 아이콘.
  IconData get icon => definition.icon;
  // 함수이름: timeLabel
  // 함수역할: 시간대 기본 시각을 두 자리 시와 분으로 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get timeLabel => '${hour.toString().padLeft(2, '0')}:00';
}

// Class Name: _ScheduleText
// Role: Represents localized wording for today's time-slot schedules, completion, reminders, and chat attachment selection.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for today's time-slot schedules, completion, reminders, and chat attachment selection.
// Attributes:
// - language (String): Language code selecting visible wording.
class _ScheduleText {
  final String language;

  // 함수이름: _ScheduleText
  // 함수역할: 시간대별 오늘 일정, 복약 체크, 알림 및 채팅 첨부 선택에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _ScheduleText 인스턴스.
  const _ScheduleText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘의 복약 일정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? "Today's Medication Schedule" : '오늘의 복약 일정';
  // 함수이름: selectionTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "대화할 약 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectionTitle => isEnglish ? 'Choose Medications' : '대화할 약 선택';
  // 함수이름: selectionDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "메시지에 함께 보낼 약을 하나 이상 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectionDescription => isEnglish
      ? 'Choose one or more medications to include with your message.'
      : '메시지에 함께 보낼 약을 하나 이상 선택해주세요.';
  // 함수이름: selectedMedicationCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count개 선택" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String selectedMedicationCount(int count) =>
      isEnglish ? '$count selected' : '$count개 선택';
  // 함수이름: confirmSelection
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get confirmSelection => isEnglish ? 'Done' : '선택 완료';
  // 함수이름: progress
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 진행률" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get progress => isEnglish ? 'Progress' : '복용 진행률';
  // 함수이름: healthRecommendation
  // 함수역할: 현재 언어와 입력값에 맞춰 "건강 관리 추천 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get healthRecommendation =>
      isEnglish ? 'View Health Recommendations' : '건강 관리 추천 보기';
  // 함수이름: emptySlot
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용할 약이 없습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get emptySlot =>
      isEnglish ? 'No medication for this time' : '복용할 약이 없습니다';
  // 함수이름: emptySchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘 복용할 약이 없습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get emptySchedule =>
      isEnglish ? 'No medication scheduled for today' : '오늘 복용할 약이 없습니다';
  // 함수이름: complete
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get complete => isEnglish ? 'Mark as taken' : '복용 완료';
  // 함수이름: undoComplete
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 완료 취소" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get undoComplete => isEnglish ? 'Undo taken' : '복용 완료 취소';
  // 함수이름: selectMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectMedication => isEnglish ? 'Select medication' : '약 선택';
  // 함수이름: close
  // 함수역할: 현재 언어와 입력값에 맞춰 "Close" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get close => isEnglish ? 'Close' : '닫기';
  // 함수이름: statusUpdateFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 상태를 변경하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get statusUpdateFailed =>
      isEnglish ? 'Could not update medication status.' : '복약 상태를 변경하지 못했습니다.';
  // Function Name: scheduleLoadFailed
  // Description: Provides localized wording for "Could not load today\'s medication schedule." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get scheduleLoadFailed => isEnglish
      ? 'Could not load today\'s medication schedule.'
      : '오늘의 복약 일정을 불러오지 못했습니다.';
  // Function Name: retry
  // Description: Provides localized wording for "Retry" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retry => isEnglish ? 'Retry' : '다시 시도';
  // 함수이름: undo
  // 함수역할: 현재 언어와 입력값에 맞춰 "실행 취소" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get undo => isEnglish ? 'Undo' : '실행 취소';

  // 함수이름: completionSaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "$slotTitle · $medicationName 복용을 완료했습니다." 문구를 제공한다.
  // 매개변수:
  // - slotTitle (String): 시간대 또는 알림 시각의 표시 문구.
  // - medicationName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String completionSaved(String slotTitle, String medicationName) {
    return isEnglish
        ? '$slotTitle · $medicationName marked as taken.'
        : '$slotTitle · $medicationName 복용을 완료했습니다.';
  }

  // Function Name: completionCancelled
  // Description: Provides localized wording for "$medicationName completion was undone." using the current language and message inputs.
  // Parameters:
  // - medicationName (String): Medication or account name shown to the user.
  // Returns: The formatted display text or identifier described above.
  String completionCancelled(String medicationName) {
    return isEnglish
        ? '$medicationName completion was undone.'
        : '$medicationName 복용 완료를 취소했습니다.';
  }

  // Function Name: entireSlotTooltip
  // Description: Provides localized wording for "Undo all $slotTitle medications" using the current language and message inputs.
  // Parameters:
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // - isCompleted (bool): Completion state of the dose or save operation.
  // Returns: The formatted display text or identifier described above.
  String entireSlotTooltip(String slotTitle, bool isCompleted) {
    if (isEnglish) {
      return isCompleted
          ? 'Undo all $slotTitle medications'
          : 'Mark all $slotTitle medications as taken';
    }
    return isCompleted ? '$slotTitle 복약 전부 해제' : '$slotTitle 복약 전부 체크';
  }

  // Function Name: entireSlotCompletionSaved
  // Description: Provides localized wording for "All $slotTitle medications were marked as taken." using the current language and message inputs.
  // Parameters:
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // Returns: The formatted display text or identifier described above.
  String entireSlotCompletionSaved(String slotTitle) {
    return isEnglish
        ? 'All $slotTitle medications were marked as taken.'
        : '$slotTitle 복약을 모두 완료했습니다.';
  }

  // Function Name: entireSlotCompletionCancelled
  // Description: Provides localized wording for "All $slotTitle medication completions were undone." using the current language and message inputs.
  // Parameters:
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // Returns: The formatted display text or identifier described above.
  String entireSlotCompletionCancelled(String slotTitle) {
    return isEnglish
        ? 'All $slotTitle medication completions were undone.'
        : '$slotTitle 복약 완료를 모두 해제했습니다.';
  }

  // 함수이름: dosageLabel
  // 함수역할: OCR 투약량이 숫자로만 제공되면 약 이름의 제형에 맞는 단위를 보완한다. 이미 단위가 포함된 투약량은 원문을 그대로 유지한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String dosageLabel(MedicationSchedule schedule) {
    return schedule.dosageLabelForLanguage(language);
  }

  // 함수이름: reminderTooltip
  // 함수역할: 현재 언어와 입력값에 맞춰 "$slotTitle 알림 설정" 문구를 제공한다.
  // 매개변수:
  // - slotTitle (String): 시간대 또는 알림 시각의 표시 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String reminderTooltip(String slotTitle) {
    return isEnglish ? 'Set $slotTitle reminder' : '$slotTitle 알림 설정';
  }

  // 함수이름: slotTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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
