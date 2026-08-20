import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyCheckSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

class _EmptySetNotification extends SetNotification {
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

class _NoopNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    String language = 'ko',
  }) async {}

  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {}

  @override
  Future<void> cancelAllMedicationReminders() async {}

  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
  }) async {}
}

void main() {
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
  });

  test('schedule payload resolves to the dose screen destination', () {
    expect(
      NotificationService.destinationFromPayload('schedule:morning:17'),
      MedicationNotificationDestination.schedule,
    );
  });

  test('malformed notification payloads cannot trigger navigation', () {
    expect(NotificationService.destinationFromPayload(null), isNull);
    expect(NotificationService.destinationFromPayload('schedule::17'), isNull);
    expect(
      NotificationService.destinationFromPayload('schedule:morning:not-an-id'),
      isNull,
    );
    expect(NotificationService.destinationFromPayload('settings:17'), isNull);
  });

  test('a selected schedule notification reaches the registered handler', () {
    final selections = <MedicationNotificationSelection>[];
    NotificationService.setNotificationSelectionHandler(selections.add);

    NotificationService.handleNotificationPayload('schedule:evening:29');

    expect(
      selections.single.destination,
      MedicationNotificationDestination.schedule,
    );
    expect(selections.single.patientHash, isNull);
  });

  test('a cold-start notification is delivered after handler registration', () {
    NotificationService.handleNotificationPayload('schedule:morning:31');

    final selections = <MedicationNotificationSelection>[];
    NotificationService.setNotificationSelectionHandler(selections.add);

    expect(
      selections.single.destination,
      MedicationNotificationDestination.schedule,
    );
  });

  test('caregiver payload keeps the selected patient hash', () {
    final selection = NotificationService.selectionFromPayload(
      'caregiver:patient_test',
    );

    expect(
      selection?.destination,
      MedicationNotificationDestination.caregiverSchedule,
    );
    expect(selection?.patientHash, 'patient_test');
  });

  testWidgets('the notification selection handler opens the dose screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    MedicationNotificationSelectionHandler? selectionHandler;

    await tester.pumpWidget(
      MedBuddyApp(
        navigatorKey: navigatorKey,
        notificationSelectionRegistrar: (handler) {
          selectionHandler = handler;
        },
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: _NoopNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectionHandler, isNotNull);
    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(navigatorKey.currentState?.canPop(), isTrue);
    expect(find.byType(CheckScheduleUI), findsOneWidget);
  });

  testWidgets('sign-out cancels local medication reminders first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        sessionReminderCleanup: () async {
          events.add('reminders-canceled');
        },
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: _NoopNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await authenticationControl.signOutForTest(() async {
      events.add('provider-sign-out');
    });

    expect(events, ['reminders-canceled', 'provider-sign-out']);
  });
}
