// File Name: medication_reminder_settings_ui_boundary_test.dart
// Role: Regression coverage for reminder-settings schedule failure and retry UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_reminder_settings_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';

// Class Name: _FailOnceReminderSchedule
// Role: Reminder-settings schedule stub with a recoverable first-read failure.
// Responsibilities:
// - Reject the initial schedule lookup and return a successful empty result on retry.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _FailOnceReminderSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Reject the initial schedule lookup and return a successful empty result on retry.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule list after the first call; initially StateError.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      throw StateError('Schedule lookup failed.');
    }
    return const [];
  }
}

// Class Name: _EmptyReminderSettings
// Role: Empty alarm fixture for isolating schedule-retry behavior in reminder settings.
// Responsibilities:
// - Provide no stored alarms while the screen exercises schedule loading.
class _EmptyReminderSettings extends SetNotification {
  // Function Name: requestMedicationAlarm
  // Description:
  // - Provide no stored alarms while the screen exercises schedule loading.
  // Parameters:
  // - None.
  // Returns:
  // - An empty alarm list.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// Function Name: main
// Description:
// - Register regression cases for reminder-settings schedule failure and retry UI.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: reminder settings surfaces schedule errors and retries.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('reminder settings surfaces schedule errors and retries', (
    tester,
  ) async {
    final checkSchedule = _FailOnceReminderSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: _EmptyReminderSettings(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: MedicationReminderSettingsUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reminder-schedule-load-error')),
      findsOneWidget,
    );
    expect(find.text('복약 일정을 불러오지 못했습니다.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-schedule-load-retry')));
    await tester.pumpAndSettle();

    expect(checkSchedule.requestCount, 2);
    expect(find.byKey(const Key('reminder-schedule-load-error')), findsNothing);
    expect(find.text('이 시간대에 등록된 약이 없습니다'), findsNWidgets(4));
  });
}
