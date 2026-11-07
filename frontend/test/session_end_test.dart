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
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_controls.dart';
import 'support/fake_notification_service.dart';

// Class Name: _EmptyCheckSchedule
// Role: Isolate session teardown from backend schedule reads.
// Responsibilities: Return no medications for either today's schedule or the alarm window.
// Attributes: No additional state; inherited client configuration is not used by these reads.
class _EmptyCheckSchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description: Supply an empty current-day schedule without network access.
  // Parameters: None.
  // Returns: Future<List<MedicationSchedule>> resolving to an empty list.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }

  // Function Name: requestMedicationScheduleWindow
  // Description: Prevent reminder-window fetching from contacting the backend during session tests.
  // Parameters: days (int) is accepted for interface compatibility and ignored.
  // Returns: Future<List<MedicationSchedule>> resolving to an empty list.
  @override
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) async {
    return const [];
  }
}

// Class Name: _RecordingWorkPlatform
// Role: Observe dose-upload scheduler activity during sign-out.
// Responsibilities: Record one-off registration/cancellation and expose the test outbox, optionally failing store access.
// Attributes: store is the test DoseOutboxStore; events is the shared order log; failStore controls the simulated keystore error.
class _RecordingWorkPlatform extends DoseSyncWorkPlatform {
  // Function Name: _RecordingWorkPlatform
  // Description: Bind the existing outbox and ordered scheduler log without opening a platform store.
  // Parameters: store (DoseOutboxStore) is returned by openStore; events (List<String>) collects calls; failStore (bool) makes store access throw.
  // Returns: A recording scheduler platform.
  _RecordingWorkPlatform(this.store, this.events, {this.failStore = false});

  final DoseOutboxStore store;
  final List<String> events;
  final bool failStore;

  // Function Name: supported
  // Description: Enable the background-scheduler branch without checking the device.
  // Parameters: None.
  // Returns: bool, always true.
  @override
  bool get supported => true;

  // Function Name: registerOneOff
  // Description: Record registration so an aborted sign-out can be checked for restored upload work.
  // Parameters: owner (String) is the requested account; this fake records only the operation.
  // Returns: Future<void> after appending work-registered to events.
  @override
  Future<void> registerOneOff(String owner) async => events.add('work-registered');

  // Function Name: registerPeriodic
  // Description: Accept periodic scheduling without registering device work or adding an event.
  // Parameters: owner (String) is accepted but unused.
  // Returns: Future<void> completing immediately.
  @override
  Future<void> registerPeriodic(String owner) async {}

  // Function Name: cancelAll
  // Description: Append the scheduler-cancellation event for ordering against uploads and provider sign-out.
  // Parameters: None.
  // Returns: Future<void>; no native work is canceled.
  @override
  Future<void> cancelAll() async => events.add('work-cancelled');

  // Function Name: openStore
  // Description: Return the supplied outbox or simulate failure to access its encrypted storage.
  // Parameters: None; uses store and failStore.
  // Returns: Future<DoseOutboxStore>, failing with StateError when failStore is true.
  @override
  Future<DoseOutboxStore> openStore() async {
    if (failStore) throw StateError('keystore unavailable');
    return store;
  }
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
  // Function Name: tearDown
  // Description: Remove the global notification-selection handler and restore the default dose-work platform after each case.
  // Parameters: None.
  // Returns: None; resets shared test hooks.
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
    DoseSyncBackgroundScheduler.platform = const DoseSyncWorkPlatform();
  });

  // A dose recorded while offline is still waiting on the device. Sign-out uploads it while the
  // token is valid, before the upload work is suspended and the account deactivated.
  // Function Name: sign-out uploads doses recorded offline before suspending the upload work
  // Description: Queue an offline dose, reconnect at sign-out, and verify upload precedes work cancellation, reminder cleanup and provider sign-out.
  // Parameters: tester (WidgetTester) mounts the application and settles session changes.
  // Returns: Future<void>; asserts the event order and an empty dose outbox after upload.
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
  // Function Name: a dose that cannot be uploaded stays queued and does not stop sign-out
  // Description: Keep the dose endpoint offline during sign-out and verify one upload attempt does not prevent cleanup or provider sign-out.
  // Parameters: tester (WidgetTester) drives the app and session transition.
  // Returns: Future<void>; asserts a cleared session and one pending record retained for its owner.
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

  // A local cleanup step that fails aborts the sign-out. The account stays signed in, so the dose
  // upload work that was already cancelled is registered again.
  // Function Name: an aborted sign-out restores the dose upload work
  // Description: Fail store access during local sign-out cleanup and verify the still-authenticated account's canceled upload work is registered again.
  // Parameters: tester (WidgetTester) mounts the app and observes cleanup.
  // Returns: Future<void>; expects sign-out to throw, the session to remain, and cancellation followed by registration only.
  testWidgets('an aborted sign-out restores the dose upload work', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final viewModel = _viewModel();
    final harness = await attachTestDoseSync(viewModel);
    DoseSyncBackgroundScheduler.platform = _RecordingWorkPlatform(
      harness.store,
      events,
      failStore: true,
    );
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

    await expectLater(
      authenticationControl.signOutForTest(() async => events.add('provider-sign-out')),
      throwsA(anything),
    );
    await tester.pump();

    expect(authenticationControl.session, isNotNull);
    expect(events, ['work-cancelled', 'work-registered']);

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });

  // A notification tapped while nobody is signed in may belong to the account that just signed
  // out. It is carried out when the same account signs in again and dropped for another account.
  for (final sameAccount in [true, false]) {
    // Function Name: notification held while signed out is scoped to the next account
    // Description: Tap a schedule notification after sign-out and verify it opens only when the original account signs back in.
    // Parameters: tester (WidgetTester) drives navigation; captures sameAccount (bool) to exercise matching and foreign accounts.
    // Returns: Future<void>; the schedule route stays absent until a matching session exists.
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

  // A reminder action tapped while the app starts without a session survives a sign-in attempt,
  // which notifies listeners before any session exists, and is carried out only for the account
  // stored on the device.
  for (final sameAccount in [true, false]) {
    // Function Name: startup notification survives a sign-in attempt but not an account change
    // Description: Start signed out with a remembered owner, hold a schedule action through an authentication attempt, and apply it only to that stored account.
    // Parameters: tester (WidgetTester) drives session and route changes; captures sameAccount (bool).
    // Returns: Future<void>; asserts no premature route and no delivery to a different account.
    testWidgets(
      'an action held at start survives a sign-in attempt and is ${sameAccount ? "applied to the stored" : "dropped for another"} account',
      (tester) async {
        MedicationNotificationSelectionHandler? selectionHandler;
        final authenticationControl = AuthenticationControl.development();
        addTearDown(authenticationControl.dispose);
        final storedAccount = authenticationControl.session!.userHash;
        await authenticationControl.signOutForTest(() async {});
        SharedPreferences.setMockInitialValues({
          NotificationInboxStore.activeUserKey: storedAccount,
        });

        await tester.pumpWidget(
          MedBuddyApp(
            authenticationControl: authenticationControl,
            notificationSelectionRegistrar: (handler) => selectionHandler = handler,
            sessionReminderCleanup: () async {},
            viewModelFactory: _viewModel,
          ),
        );
        await tester.pumpAndSettle();

        selectionHandler!(
          const MedicationNotificationSelection(
            destination: MedicationNotificationDestination.schedule,
            slotKey: 'morning',
          ),
        );
        await tester.pumpAndSettle();
        await authenticationControl.runAuthOperationForTest(() async {});
        await tester.pumpAndSettle();
        expect(find.byType(CheckScheduleUI), findsNothing);

        authenticationControl.establishSessionForTest(
          sameAccount ? storedAccount : 'another-account',
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
  // Function Name: foreground resume upgrades inexact reminders
  // Description: Verify that pausing does not reschedule alarms and returning to the foreground requests one exact-alarm upgrade.
  // Parameters: tester (WidgetTester) drives lifecycle changes with recording notifications.
  // Returns: Future<void>; asserts the exact-reschedule count increases only on resume.
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
