// File Name: session_start_test.dart
// Role: Checks what the app keeps when it starts without a session. It is a file of its own
//   because the notification service is a process-wide singleton whose pending storage writes from
//   earlier tests in the same file would hide the behaviour.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_controls.dart';
import 'support/fake_notification_service.dart';

// Class Name: _EmptyCheckSchedule
// Role: Schedule control that answers every read with an empty list, without a request.
class _EmptyCheckSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }

  @override
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) async {
    return const [];
  }
}

// Function Name: _viewModel
// Description: Builds a view model on local controls only, without network or notification plugin.
// Parameters: None.
// Returns: MedBuddyViewModel: the view model for the app under test.
MedBuddyViewModel _viewModel() => MedBuddyViewModel(
  checkSchedule: _EmptyCheckSchedule(),
  setNotification: EmptySetNotification(),
  manageUserSetting: ManageUserSetting(useRemotePersistence: false),
  notificationService: RecordingNotificationService(),
);

// Function Name: main
// Description: Registers the start-up regression case.
// Parameters: None.
// Returns: None.
void main() {
// An app that starts without a session (offline, or the server not answering yet) must keep the
// account stored on the device: caregiver alerts that arrive later are shown only for it.
testWidgets('starting without a session keeps the stored account', (tester) async {
  final authenticationControl = AuthenticationControl.development();
  addTearDown(authenticationControl.dispose);
  await authenticationControl.signOutForTest(() async {});
  SharedPreferences.setMockInitialValues({
    NotificationInboxStore.activeUserKey: 'usr_stored',
  });

  await tester.pumpWidget(
    MedBuddyApp(
      authenticationControl: authenticationControl,
      notificationSelectionRegistrar: (_) {},
      sessionReminderCleanup: () async {},
      viewModelFactory: _viewModel,
    ),
  );
  await tester.pumpAndSettle();

  final preferences = await SharedPreferences.getInstance();
  expect(
    preferences.getString(NotificationInboxStore.activeUserKey),
    'usr_stored',
  );
});
}
