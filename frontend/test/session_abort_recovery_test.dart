import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_notification_service.dart';

class _NoSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async => [];
  @override
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) async => [];
}

class _Alarms extends SetNotification {
  _Alarms(RecordingNotificationService notifications)
    : super(notificationRegistrar: notifications.registerNotification);
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => [
    const MedicationAlarm(
      slotKey: 'morning',
      hour: 8,
      minute: 17,
      enabled: true,
    ),
    const MedicationAlarm(
      slotKey: 'evening',
      hour: 19,
      minute: 23,
      enabled: true,
    ),
  ];
}

class _Work extends DoseSyncWorkPlatform {
  _Work(this.store, this.fail);
  final DoseOutboxStore store;
  final String fail;
  var registrations = 0;
  @override
  bool get supported => true;
  @override
  Future<DoseOutboxStore> openStore() async {
    if (fail == 'store') throw StateError('store failure');
    return store;
  }

  @override
  Future<void> cancelAll() async {
    if (fail == 'work') throw StateError('work cancellation failure');
  }

  @override
  Future<void> registerOneOff(String owner) async {
    registrations++;
  }

  @override
  Future<void> registerPeriodic(String owner) async {}
}

class _Widget extends DoseHomeWidgetPlatform {
  _Widget(this.store, this.fail);
  final DoseOutboxStore store;
  final String fail;
  Map<String, dynamic>? latest;
  var throwOnce = true;
  @override
  bool get supported => true;
  @override
  Future<DoseOutboxStore> openStore() async => store;
  @override
  Future<String?> readJournal() async => '[]';
  @override
  Future<void> cancelScheduledUpdates() async {
    if (fail == 'widget-cancel') throw StateError('widget cancel failure');
  }

  @override
  Future<void> saveState(String state) async {
    final value = jsonDecode(state) as Map<String, dynamic>;
    latest = value;
    if (fail == 'widget-save' && !value.containsKey('owner') && throwOnce) {
      throwOnce = false;
      throw StateError('widget write failure');
    }
  }

  @override
  Future<void> updateWidget() async {
    if (fail == 'widget-update' && throwOnce) {
      throwOnce = false;
      throw StateError('widget render failure');
    }
  }

  @override
  Future<void> scheduleUpdate(DateTime at) async {}
  @override
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {}
  @override
  Future<void> registerSync(String owner) async {}
}

void main() {
  tearDown(() {
    DoseHomeWidget.resetForTest();
    DoseSyncBackgroundScheduler.platform = const DoseSyncWorkPlatform();
  });
  for (final failure in [
    'work',
    'store',
    'widget-cancel',
    'widget-save',
    'widget-update',
    'reminders',
  ]) {
    testWidgets(
      'aborted cleanup at $failure restores store, PRN metadata, widget, reminder times and dose enqueue',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final notifications = RecordingNotificationService();
        final model = MedBuddyViewModel(
          checkSchedule: _NoSchedule(),
          setNotification: _Alarms(notifications),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: notifications,
        );
        final harness = await attachTestDoseSync(model);
        final auth = AuthenticationControl.development();
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          MedBuddyApp(
            authenticationControl: auth,
            viewModelFactory: () => model,
            sessionReminderCleanup: () async {
              if (failure == 'reminders') {
                throw StateError('reminder cleanup failed');
              }
            },
          ),
        );
        await tester.pump();
        await model.loadMedicationReminderSettings(notifyAfterLoad: false);
        await harness.seedSchedules([
          MedicationSchedule(
            medicationID: '91',
            medicationName: 'synthetic',
            prescriptionDate: DateTime.now(),
            medicationTime: 30,
            scheduleSlotKeys: ['morning', 'evening'],
          ),
        ]);
        await harness.store.stageHistoryPending(harness.owner, [
          {'operation_id': 'prn_pending_123', 'medication_id': 92},
        ]);
        final work = _Work(harness.store, failure);
        final widget = _Widget(harness.store, failure);
        DoseSyncBackgroundScheduler.platform = work;
        DoseHomeWidget.platform = widget;
        final originalSession = auth.session;
        var providerCalled = false;
        await expectLater(
          auth.signOutForTest(() async {
            providerCalled = true;
          }),
          throwsA(anything),
        );
        await tester.pump();
        expect(identical(auth.session, originalSession), isTrue);
        expect(providerCalled, isFalse);
        expect(await harness.store.isActive(harness.owner), isTrue);
        expect(
          (await harness.store.readHistoryPending(
            harness.owner,
          )).single['operation_id'],
          'prn_pending_123',
        );
        expect(work.registrations, greaterThan(0));
        expect(widget.latest?['date'], isNotNull);
        expect(
          notifications.registrations.any(
            (r) => r.slotKey == 'morning' && r.hour == 8 && r.minute == 17,
          ),
          isTrue,
        );
        expect(
          notifications.registrations.any(
            (r) => r.slotKey == 'evening' && r.hour == 19 && r.minute == 23,
          ),
          isTrue,
        );
        expect(
          await harness.service.record(
            medicationIds: [91],
            slotKey: 'morning',
            completed: true,
          ),
          isTrue,
        );
        await harness.service.drain();
        expect(await harness.pending(), hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.close();
      },
    );
  }

  testWidgets('a switched session is never restored by failed old cleanup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthenticationControl.development();
    addTearDown(auth.dispose);
    final model = MedBuddyViewModel(
      checkSchedule: _NoSchedule(),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
      notificationService: RecordingNotificationService(),
    );
    final harness = await attachTestDoseSync(model);
    final work = _Work(harness.store, '');
    DoseSyncBackgroundScheduler.platform = work;
    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: auth,
        viewModelFactory: () => model,
        sessionReminderCleanup: () async {
          await harness.store.activate('new-account');
          auth.establishSessionForTest('new-account');
          throw StateError('old cleanup failed');
        },
      ),
    );
    await tester.pump();
    await expectLater(auth.signOutForTest(() async {}), throwsA(anything));
    expect(await harness.store.isActive('new-account'), isTrue);
    expect(await harness.store.isActive(harness.owner), isFalse);
    expect(work.registrations, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.close();
  });
}
