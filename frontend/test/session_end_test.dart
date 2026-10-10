// File Name: session_end_test.dart
// Role: Verifies what the application shell does around the end of a session: the bounded upload
//   of doses recorded offline before sign-out, the notification action held while signed out when
//   a different account signs in, and the reminder upgrade when the app returns to the foreground.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
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

// Class Name: _RecordingWorkPlatform
// Role: WorkManager substitute that records the suspension of dose upload work in a shared log.
// Attributes: store - outbox the suspension deactivates; events - shared event log.
class _RecordingWorkPlatform extends DoseSyncWorkPlatform {
  // Function Name: _RecordingWorkPlatform
  // Description: Binds the outbox and the event log.
  // Parameters: store, events - see the class attributes. Returns: The recording platform.
  _RecordingWorkPlatform(this.store, this.events);

  final DoseOutboxStore store;
  final List<String> events;

  @override
  bool get supported => true;

  @override
  Future<void> registerOneOff(String owner) async {}

  @override
  Future<void> registerPeriodic(String owner) async {}

  @override
  Future<void> cancelAll() async => events.add('work-cancelled');

  @override
  Future<DoseOutboxStore> openStore() async => store;
}

// Function Name: _viewModel
// Description: Builds a view model on local settings, an empty schedule and recording notifications.
// Parameters: notificationService - notification fake; defaults to a new recording fake.
// Returns: The view model, isolated from the backend and the notification plugin.
MedBuddyViewModel _viewModel([RecordingNotificationService? notificationService]) {
  return MedBuddyViewModel(
    checkSchedule: _EmptyCheckSchedule(),
    setNotification: EmptySetNotification(),
    manageUserSetting: ManageUserSetting(useRemotePersistence: false),
    notificationService: notificationService ?? RecordingNotificationService(),
  );
}

// Function Name: main
// Description: Registers the session-end tests.
// Parameters: None. Returns: None.
void main() {
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
    DoseSyncBackgroundScheduler.platform = const DoseSyncWorkPlatform();
  });

  // A dose recorded while offline is still waiting on the device. Sign-out uploads it while the
  // token is valid, before the upload work is suspended and the account deactivated.
  testWidgets('sign-out uploads doses recorded offline before suspending the upload work', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final viewModel = _viewModel();
    final harness = await attachTestDoseSync(viewModel);
    const medication = MedicationSchedule(
      medicationID: '91',
      medicationName: '테스트정',
      scheduleSlotKeys: ['morning'],
      slotStatuses: {'morning': false},
    );
    await harness.seedSchedules(const [medication]);
    // Offline: the record is stored and stays queued.
    await harness.service.record(
      medicationIds: const [91],
      slotKey: 'morning',
      completed: true,
    );
    await harness.service.drain();
    expect(await harness.pending(), hasLength(1));
    harness.uploads.clear();
    // Back online when the user signs out.
    harness.respond = (http.Request request) async {
      events.add('dose-uploaded');
      return doseSyncReceipt(request, const [medication]);
    };
    DoseSyncBackgroundScheduler.platform = _RecordingWorkPlatform(harness.store, events);
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        sessionReminderCleanup: () async => events.add('reminders-cancelled'),
        viewModelFactory: () => viewModel,
      ),
    );
    await tester.pump();
    events.clear();

    await authenticationControl.signOutForTest(() async {
      events.add('provider-sign-out');
    });
    await tester.pump();

    expect(events.take(4), [
      'dose-uploaded',
      'work-cancelled',
      'reminders-cancelled',
      'provider-sign-out',
    ]);
    expect(await harness.pending(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  // Offline sign-out attempt: the upload fails, the record stays queued for the same account, and
  // the rest of the sign-out preparation still runs.
  testWidgets('a dose that cannot be uploaded stays queued and does not stop sign-out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final viewModel = _viewModel();
    final harness = await attachTestDoseSync(viewModel);
    const medication = MedicationSchedule(
      medicationID: '91',
      medicationName: '테스트정',
      scheduleSlotKeys: ['morning'],
      slotStatuses: {'morning': false},
    );
    await harness.seedSchedules(const [medication]);
    await harness.service.record(
      medicationIds: const [91],
      slotKey: 'morning',
      completed: true,
    );
    await harness.service.drain();
    DoseSyncBackgroundScheduler.platform = _RecordingWorkPlatform(harness.store, events);
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        sessionReminderCleanup: () async => events.add('reminders-cancelled'),
        viewModelFactory: () => viewModel,
      ),
    );
    await tester.pump();
    events.clear();
    harness.uploads.clear();

    await authenticationControl.signOutForTest(() async {
      events.add('provider-sign-out');
    });
    await tester.pump();

    expect(harness.uploads, hasLength(1));
    expect(events.take(3), [
      'work-cancelled',
      'reminders-cancelled',
      'provider-sign-out',
    ]);
    expect(authenticationControl.session, isNull);
    final pending = await harness.pending();
    expect(pending, hasLength(1));
    expect(pending.single['state'], 'pending');

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  // A notification tapped while nobody is signed in may belong to the account that just signed
  // out. It is carried out when the same account signs in again and dropped for another account.
  for (final sameAccount in [true, false]) {
    testWidgets(
      'a notification action held while signed out is ${sameAccount ? "applied to the same" : "dropped for a different"} account',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        MedicationNotificationSelectionHandler? selectionHandler;
        final authenticationControl = AuthenticationControl.development();
        addTearDown(authenticationControl.dispose);
        final firstAccount = authenticationControl.session!.userHash;

        await tester.pumpWidget(
          MedBuddyApp(
            authenticationControl: authenticationControl,
            notificationSelectionRegistrar: (handler) => selectionHandler = handler,
            sessionReminderCleanup: () async {},
            viewModelFactory: _viewModel,
          ),
        );
        await tester.pumpAndSettle();

        await authenticationControl.signOutForTest(() async {});
        await tester.pumpAndSettle();
        expect(authenticationControl.session, isNull);

        // Tapped on the lock screen after the sign-out.
        selectionHandler!(
          const MedicationNotificationSelection(
            destination: MedicationNotificationDestination.schedule,
            slotKey: 'morning',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CheckScheduleUI), findsNothing);

        authenticationControl.establishSessionForTest(
          sameAccount ? firstAccount : 'another-account',
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(CheckScheduleUI),
          sameAccount ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  // The user may allow "Alarms & reminders" in the system settings and come back: reminders that
  // were scheduled as inexact alarms are replaced without any further action in the app.
  testWidgets('returning to the foreground upgrades reminders scheduled as inexact alarms', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final notificationService = RecordingNotificationService();
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        sessionReminderCleanup: () async {},
        viewModelFactory: () => _viewModel(notificationService),
      ),
    );
    await tester.pumpAndSettle();
    final before = notificationService.exactRescheduleCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(notificationService.exactRescheduleCount, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(notificationService.exactRescheduleCount, before + 1);
  });
}
