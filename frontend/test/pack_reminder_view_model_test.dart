// 파일명: pack_reminder_view_model_test.dart
// 역할: 외출 전 약 챙기기 알림의 화면 쪽 동기화(기간 일정 실패, 기다리는 사이 설정 변경, 로그아웃 실패 뒤 복원 상한)와
//   백그라운드 갱신 중 계정 소유권이 사라졌을 때의 정리를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/pack_reminder_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_reminder_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

const _owner = 'pack-reminder-patient';

// 격일 점심 약: 오늘 일정에는 없지만 기간 일정에는 있다.
final _everyOtherDayLunch = MedicationSchedule(
  medicationName: 'TEST_ONLY',
  prescriptionDate: DateTime.now().subtract(const Duration(days: 1)),
  medicationTime: 14,
  scheduleSlotKeys: const ['lunch'],
  doseCycleDays: 2,
);

// 함수이름: _client
// 함수역할: 알림 설정 조회에 빈 목록을 돌려주는 서버를 만든다.
// 매개변수: 없음. 반환값: http.Client.
http.Client _client() => MockClient(
  (_) async => http.Response(
    jsonEncode({'success': true, 'data': <Object>[]}),
    200,
    headers: {'content-type': 'application/json'},
  ),
);

// 함수이름: _model
// 함수역할: 오늘 일정이 비어 있고 기간 일정을 주입한 화면 쪽 알림 모델을 만든다.
// 매개변수: notifications: 예약·취소 기록기; loadScheduleWindow: 기간 일정 공급자.
// 반환값: MedBuddyReminderViewModel.
MedBuddyReminderViewModel _model(
  RecordingNotificationService notifications,
  Future<List<MedicationSchedule>> Function() loadScheduleWindow,
) => MedBuddyReminderViewModel(
  setNotification: SetNotification(
    patientHash: _owner,
    client: _client(),
    notificationRegistrar: notifications.registerNotification,
  ),
  notificationService: notifications,
  patientHash: _owner,
  readUserSetting: () => const UserSetting(),
  readSchedules: () => const [],
  scheduleIsFresh: () => true,
  loadScheduleWindow: loadScheduleWindow,
  onChanged: (_) {},
);

// 함수이름: _packCalls
// 함수역할: 외출 전 알림의 예약·취소 기록만 고른다.
// 매개변수: notifications: 기록기. 반환값: ("register"|"cancel") 목록.
List<String> _packCalls(RecordingNotificationService notifications) => [
  for (final registration in notifications.registrations)
    if (registration.slotKey == 'pack') 'register',
  for (final cancellation in notifications.cancellations)
    if (cancellation.slotKey == 'pack') 'cancel',
];

void main() {
  const enabled = PackReminderSetting(enabled: true);

  test(
    'a failed course-window read keeps the existing pack reminder',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifications = RecordingNotificationService();
      final model = _model(
        notifications,
        () async => throw StateError('offline'),
      );

      expect(await model.savePackReminderSetting(enabled), isTrue);

      // 오늘 일정만으로 판단하면 격일 약의 앞으로의 알림까지 지워진다.
      expect(_packCalls(notifications), isEmpty);
      model.dispose();
    },
  );

  test('the course window decides the days when it loads', () async {
    SharedPreferences.setMockInitialValues({});
    final notifications = RecordingNotificationService();
    final model = _model(notifications, () async => [_everyOtherDayLunch]);

    expect(await model.savePackReminderSetting(enabled), isTrue);

    final registration = notifications.registrations.singleWhere(
      (registration) => registration.slotKey == 'pack',
    );
    expect(registration.id, PackReminderControl.notificationId);
    expect(registration.activeDates, isNotEmpty);
    expect(registration.activeDates.length, lessThan(14));
    model.dispose();
  });

  test(
    'a setting changed while the window loads wins over the old one',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifications = RecordingNotificationService();
      final windows = <Completer<List<MedicationSchedule>>>[];
      final model = _model(notifications, () {
        final completer = Completer<List<MedicationSchedule>>();
        windows.add(completer);
        return completer.future;
      });

      final first = model.savePackReminderSetting(enabled);
      await pumpEventQueue();
      // 첫 저장이 기간 일정을 기다리는 사이 사용자가 끈다.
      final preferences = await SharedPreferences.getInstance();
      await PackReminderControl.save(
        preferences,
        _owner,
        const PackReminderSetting(),
      );
      windows.single.complete([_everyOtherDayLunch]);
      await first;

      expect(_packCalls(notifications), ['cancel']);
      model.dispose();
    },
  );

  test(
    'restoring after an aborted sign-out stops at the last allowed date',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await PackReminderControl.save(preferences, _owner, enabled);
      final notifications = RecordingNotificationService();
      final model = _model(
        notifications,
        () async => throw StateError('unused'),
      );
      final today = DateTime.now();
      final lastAllowed = DateTime(today.year, today.month, today.day + 3);

      await model.restoreAfterAbortedSignOut(
        isCurrent: () => true,
        courses: [_everyOtherDayLunch],
        lastAllowedDate: lastAllowed,
      );

      final registration = notifications.registrations.singleWhere(
        (registration) => registration.slotKey == 'pack',
      );
      expect(
        registration.activeDates.every((d) => !d.isAfter(lastAllowed)),
        isTrue,
      );
      model.dispose();
    },
  );

  test(
    'a background refresh that loses the account cancels the pack reminder',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cancellations = <(int, String?)>[];
      var owns = true;
      final service = MedicationReminderRefreshService(
        loadSettings: () async => const <MedicationAlarm>[],
        loadSchedules: () async => [_everyOtherDayLunch],
        loadUserSetting: () async => const UserSetting(),
        registerReminder:
            ({
              required id,
              required slotKey,
              required slotTitle,
              required hour,
              required minute,
              required activeDates,
              language = 'ko',
            }) async {},
        cancelReminder: (id, {slotKey}) async =>
            cancellations.add((id, slotKey)),
        ownsReminders: () async => owns,
        synchronizePack:
            ({
              required schedules,
              required notificationsEnabled,
              required language,
            }) async {
              // 예약하는 사이 로그아웃 정리가 끝났다.
              owns = false;
            },
      );

      await service.synchronize();
      service.dispose();

      expect(
        cancellations,
        contains((PackReminderControl.notificationId, 'pack')),
      );
    },
  );
}
