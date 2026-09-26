import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_feature_updates.dart';
import '../viewmodels/medbuddy_view_model.dart';
import 'set_notification_ui_boundary.dart';

// File Name: medication_reminder_settings_ui_boundary.dart
// Role: UI boundaries and helpers for per-slot reminder retrieval, time changes, and disabling.

// Class Name: MedicationReminderSettingsUI
// Role: Represents current per-slot reminder state, configuration, and disabling.
// Responsibilities:
// - Loads current schedules and reminder settings.
// - Reuses the existing view-model save flow from slot dialogs.
// - Immediately reports reminder enable and disable outcomes.
class MedicationReminderSettingsUI extends StatefulWidget {
  // Function Name: MedicationReminderSettingsUI
  // Description: Initializes current per-slot reminder state, configuration, and disabling with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // Returns: Initialized MedicationReminderSettingsUI instance.
  const MedicationReminderSettingsUI({super.key});

  // Function Name: createState
  // Description: Creates the state object that coordinates current per-slot reminder state, configuration, and disabling.
  // Parameters:
  // - None.
  // Returns: A new _MedicationReminderSettingsUIState instance.
  @override
  State<MedicationReminderSettingsUI> createState() =>
      _MedicationReminderSettingsUIState();
}

// Class Name: _MedicationReminderSettingsUIState
// Role: Manages state for current per-slot reminder state, configuration, and disabling.
// Responsibilities:
// - Builds retrieval state and each slot's medication count, reminder time, and enable controls.
// - Selects medications assigned to the requested slot using the view model's rules.
// - Opens reminder editing at the current time and saves the selected hour and minute with the slot's medications.
// Attributes:
// - _slots (List<_ReminderSlotDefinition>): List combining per-slot medications and presentation definitions.
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

  // Function Name: initState
  // Description: Requests current schedules and reminder settings after the first frame.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    // Function Name: initState.addPostFrameCallback callback
    // Description: Connects current per-slot reminder state, configuration, and disabling to the captured operation `context.read<MedBuddyViewModel>().refreshMedicationSchedule(); context.read<MedBuddyViewModel>()`.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MedBuddyViewModel>().refreshMedicationSchedule();
      }
    });
  }

  // Function Name: build
  // Description: Renders current per-slot reminder state, configuration, and disabling from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for current per-slot reminder state, configuration, and disabling.
  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.schedule),
        viewModel.updatesFor(MedBuddyFeature.reminder),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      // Function Name: build.builder callback
      // Description: Composes current per-slot reminder state, configuration, and disabling with the current parent constraints for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

  // Function Name: _buildScreen
  // Description: Builds retrieval state and each slot's medication count, reminder time, and enable controls.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: Widget tree for current per-slot reminder state, configuration, and disabling.
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
                        // Function Name: _buildScreen.onPressed callback
                        // Description: Closes this route with the selection or cancellation encoded by `Navigator.maybePop(context)`.
                        // Parameters:
                        // - None.
                        // Returns: No callback payload; any selection is delivered through the route result.
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
                      : viewModel.hasTodayScheduleLoadError
                      ? _ReminderScheduleLoadError(
                          text: text,
                          onRetryRequested: viewModel.refreshMedicationSchedule,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          itemCount: _slots.length,
                          // Function Name: _buildScreen.separatorBuilder callback
                          // Description: Separates adjacent entries in current per-slot reminder state, configuration, and disabling using the declared spacing or divider.
                          // Parameters:
                          // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
                          // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
                          // Returns: Widget subtree for the described layout or fallback.
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          // Function Name: _buildScreen.itemBuilder callback
                          // Description: Composes current per-slot reminder state, configuration, and disabling with the current parent constraints for the active layout.
                          // Parameters:
                          // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
                          // - index (int): Zero-based position of the target medication, photo, or row.
                          // Returns: Widget subtree for the described layout or fallback.
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
                                  // Function Name: _buildScreen.onTimeRequested callback
                                  // Description: Opens reminder editing at the current time and saves the selected hour and minute with the slot's medications.
                                  // Parameters:
                                  // - None.
                                  // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                                  : () => _requestReminderTime(
                                      viewModel,
                                      slot,
                                      schedules,
                                      setting,
                                      text,
                                    ),
                              onEnabledChanged: schedules.isEmpty
                                  ? null
                                  // Function Name: _buildScreen.onEnabledChanged callback
                                  // Description: Opens time editing when enabling a reminder and cancels the slot reminder when disabling it.
                                  // Parameters:
                                  // - enabled (bool): Whether the choice, action, or feature is enabled.
                                  // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
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

  // Function Name: _schedulesForSlot
  // Description: Selects medications assigned to the requested slot using the view model's rules.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // Returns: List<MedicationSchedule>: Medication schedules matching the requested slot.
  List<MedicationSchedule> _schedulesForSlot(
    MedBuddyViewModel viewModel,
    String slotKey,
  ) {
    return viewModel.todayMedicationScheduleList
        .where(
          // Function Name: _schedulesForSlot.where callback
          // Description: Checks the collection condition `viewModel.slotKeysForSchedule(schedule).contains(slotKey)` for current per-slot reminder state, configuration, and disabling.
          // Parameters:
          // - schedule (inferred by callback contract): Medication schedule containing name, dosage, days, slots, and completion state.
          // Returns: Boolean predicate result for the supplied item.
          (schedule) =>
              viewModel.slotKeysForSchedule(schedule).contains(slotKey),
        )
        .toList(growable: false);
  }

  // Function Name: _requestReminderTime
  // Description: Opens reminder editing at the current time and saves the selected hour and minute with the slot's medications.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slot (_ReminderSlotDefinition): Dose-slot identity, time, and presentation data.
  // - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - setting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
  // - text (_ReminderSettingsText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
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

  // Function Name: _changeReminderEnabled
  // Description: Opens time editing when enabling a reminder and cancels the slot reminder when disabling it.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slot (_ReminderSlotDefinition): Dose-slot identity, time, and presentation data.
  // - schedules (List<MedicationSchedule>): Medication schedules for review, display, or slot grouping.
  // - setting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
  // - enabled (bool): Whether the choice, action, or feature is enabled.
  // - text (_ReminderSettingsText): Localized labels used by this section.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
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

  // Function Name: _showResult
  // Description: Replaces the previous snackbar with the reminder save or cancellation result using outcome colors.
  // Parameters:
  // - message (String): Visible wording for the current result, error, or state.
  // - succeeded (bool): Whether the preceding save, retrieval, or update succeeded.
  // Returns: None; updates state or performs the documented action.
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

// Class Name: _ReminderSlotCard
// Role: Represents a dose slot's label, reminder time, enabled state, and edit action.
// Responsibilities:
// - Composes a dose slot's label, reminder time, enabled state, and edit action using the display values and actions supplied by its parent.
// Attributes:
// - slot (_ReminderSlotDefinition): Dose-slot identity, time, and presentation data.
// - setting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
// - medicationCount (int): Number of medications included in the slot or summary.
// - onTimeRequested (VoidCallback?): Callback opening time selection for the dose slot to edit.
class _ReminderSlotCard extends StatelessWidget {
  final _ReminderSlotDefinition slot;
  final MedicationAlarm setting;
  final int medicationCount;
  final _ReminderSettingsText text;
  final VoidCallback? onTimeRequested;
  final ValueChanged<bool>? onEnabledChanged;

  // Function Name: _ReminderSlotCard
  // Description: Initializes a dose slot's label, reminder time, enabled state, and edit action with the supplied configuration.
  // Parameters:
  // - slot (_ReminderSlotDefinition): Dose-slot identity, time, and presentation data.
  // - setting (MedicationAlarm): The dose-slot reminder configuration being displayed or edited.
  // - medicationCount (int): Number of medications included in the slot or summary.
  // - text (_ReminderSettingsText): Localized labels used by this section.
  // - onTimeRequested (VoidCallback?): Callback opening time selection for the dose slot to edit.
  // - onEnabledChanged (ValueChanged<bool>?): Callback reporting the changed value or selection state to the owning screen.
  // Returns: Initialized _ReminderSlotCard instance.
  const _ReminderSlotCard({
    required this.slot,
    required this.setting,
    required this.medicationCount,
    required this.text,
    required this.onTimeRequested,
    required this.onEnabledChanged,
  });

  // Function Name: build
  // Description: Renders a dose slot's label, reminder time, enabled state, and edit action from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a dose slot's label, reminder time, enabled state, and edit action.
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

// Class Name: _ReminderSlotDefinition
// Role: Represents a reminder slot's key, labels, color, and icon.
// Responsibilities:
// - Selects the slot label for the requested language.
// Attributes:
// - key (String): String key identifying the dose slot.
// - koreanLabel (String): Wording identifying a field, choice, or action.
// - englishLabel (String): Wording identifying a field, choice, or action.
// - icon (IconData): Icon shown in normal or selected state.
class _ReminderSlotDefinition {
  final String key;
  final String koreanLabel;
  final String englishLabel;
  final IconData icon;

  // Function Name: _ReminderSlotDefinition
  // Description: Combines the supplied values for a reminder slot's key, labels, color, and icon in a _ReminderSlotDefinition instance.
  // Parameters:
  // - key (String): String key identifying the dose slot.
  // - koreanLabel (String): Wording identifying a field, choice, or action.
  // - englishLabel (String): Wording identifying a field, choice, or action.
  // - icon (IconData): Icon shown in normal or selected state.
  // Returns: Initialized _ReminderSlotDefinition instance.
  const _ReminderSlotDefinition({
    required this.key,
    required this.koreanLabel,
    required this.englishLabel,
    required this.icon,
  });

  // Function Name: label
  // Description: Selects the slot label for the requested language.
  // Parameters:
  // - isEnglish (bool): Whether English wording is selected; false selects Korean.
  // Returns: The formatted display text or identifier described above.
  String label(bool isEnglish) => isEnglish ? englishLabel : koreanLabel;
}

// Class Name: _ReminderScheduleLoadError
// Role: Represents schedule-load failure and retry on the reminders screen.
// Responsibilities:
// - Composes schedule-load failure and retry on the reminders screen using the display values and actions supplied by its parent.
// Attributes:
// - onRetryRequested (Future<void> Function()): Callback reloading failed or stale screen data.
class _ReminderScheduleLoadError extends StatelessWidget {
  final _ReminderSettingsText text;
  final Future<void> Function() onRetryRequested;

  // Function Name: _ReminderScheduleLoadError
  // Description: Initializes schedule-load failure and retry on the reminders screen with the supplied configuration.
  // Parameters:
  // - text (_ReminderSettingsText): Localized labels used by this section.
  // - onRetryRequested (Future<void> Function()): Callback reloading failed or stale screen data.
  // Returns: Initialized _ReminderScheduleLoadError instance.
  const _ReminderScheduleLoadError({
    required this.text,
    required this.onRetryRequested,
  });

  // Function Name: build
  // Description: Renders schedule-load failure and retry on the reminders screen from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for schedule-load failure and retry on the reminders screen.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          key: const Key('reminder-schedule-load-error'),
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          decoration: BoxDecoration(
            color: MedBuddyColors.surface,
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
                text.scheduleLoadFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('reminder-schedule-load-retry'),
                onPressed: onRetryRequested,
                icon: const Icon(Icons.refresh),
                label: Text(text.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Class Name: _ReminderSettingsText
// Role: Represents localized wording for per-slot reminder retrieval, time changes, and disabling.
// Responsibilities:
// - Selects Korean or English labels and interpolates message values for localized wording for per-slot reminder retrieval, time changes, and disabling.
// Attributes:
// - language (String): Language code selecting visible wording.
class _ReminderSettingsText {
  final String language;

  // Function Name: _ReminderSettingsText
  // Description: Stores the language used to select localized wording for per-slot reminder retrieval, time changes, and disabling.
  // Parameters:
  // - language (String): Language code selecting visible wording.
  // Returns: Initialized _ReminderSettingsText instance.
  const _ReminderSettingsText(this.language);

  // Function Name: isEnglish
  // Description: Recognizes English locale prefixes after trimming and lowercasing the language code.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  // Function Name: title
  // Description: Provides localized wording for "Medication Reminder Settings" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get title => isEnglish ? 'Medication Reminder Settings' : '복약 알림 설정';
  // Function Name: description
  // Description: Provides localized wording for "Choose a time slot to edit its reminder. Reminders without medication stay unavailable." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get description => isEnglish
      ? 'Choose a time slot to edit its reminder. Reminders without medication stay unavailable.'
      : '시간대를 눌러 알림 시간을 변경하세요. 등록된 약이 없는 시간대는 사용할 수 없습니다.';
  // Function Name: back
  // Description: Provides localized wording for "Back" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get back => isEnglish ? 'Back' : '뒤로';
  // Function Name: noMedication
  // Description: Provides localized wording for "No medication in this time slot" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get noMedication =>
      isEnglish ? 'No medication in this time slot' : '이 시간대에 등록된 약이 없습니다';
  // Function Name: scheduleLoadFailed
  // Description: Provides localized wording for "Could not load your medication schedule." using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get scheduleLoadFailed => isEnglish
      ? 'Could not load your medication schedule.'
      : '복약 일정을 불러오지 못했습니다.';
  // Function Name: retry
  // Description: Provides localized wording for "Retry" using the current language and message inputs.
  // Parameters:
  // - None.
  // Returns: The formatted display text or identifier described above.
  String get retry => isEnglish ? 'Retry' : '다시 시도';
  // Function Name: enabledAt
  // Description: Provides localized wording for "$time · $count medication${count == 1 ?" using the current language and message inputs.
  // Parameters:
  // - time (String): Hour and minute to display in the picker or save.
  // - count (int): Item count or ordinal number used in wording or a list.
  // Returns: The formatted display text or identifier described above.
  String enabledAt(String time, int count) => isEnglish
      ? '$time · $count medication${count == 1 ? '' : 's'}'
      : '$time · 약 $count개';
  // Function Name: disabled
  // Description: Provides localized wording for "Off · $count medication${count == 1 ?" using the current language and message inputs.
  // Parameters:
  // - count (int): Item count or ordinal number used in wording or a list.
  // Returns: The formatted display text or identifier described above.
  String disabled(int count) => isEnglish
      ? 'Off · $count medication${count == 1 ? '' : 's'}'
      : '꺼짐 · 약 $count개';
}
