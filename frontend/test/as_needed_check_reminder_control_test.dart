// 파일명: as_needed_check_reminder_control_test.dart
// 역할: 필요시 확인 알림의 단발 예약·계정 범위·실패 복구를 검증한다.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/controls/as_needed_check_reminder_control.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'support/fake_notification_service.dart';

// 함수이름: main
// 함수역할:
// - 고정 UTC 시각과 알림 대역으로 필요시 확인 예약의 저장·복원·차단 조건을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 알림 제어 및 알림 선택 해석 테스트를 등록한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 사례가 이전 계정의 알림 설정을 읽지 않도록 메모리 환경설정을 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 새 환경설정 대역을 설치한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime.utc(2026, 10, 17, 10);

  // 함수이름: test 콜백
  // 함수역할:
  // - UTC 고정 시각에서 한 시간 뒤 예약을 한국 날짜·시각으로 한 번 등록하고 다른 환자의 복원에는 활성화되지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'explicit reminder reserves exactly one Korean date and persists per patient',
    () async {
      final notifications = RecordingNotificationService();
      final control = AsNeededCheckReminderControl(
        patientHash: 'patient-a',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(control.dispose);
      await control.restore(allowed: true, isEnglish: false);
      expect(notifications.registrations, isEmpty);
      await control.save(now.add(const Duration(hours: 1)), isEnglish: false);
      expect(control.enabled, isTrue);
      final registration = notifications.registrations.single;
      expect(registration.slotKey, 'as_needed');
      expect(registration.hour, 20);
      expect(registration.activeDates, [DateTime(2026, 10, 17)]);
      final other = AsNeededCheckReminderControl(
        patientHash: 'patient-b',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(other.dispose);
      await other.restore(allowed: true, isEnglish: false);
      expect(other.enabled, isFalse);
      expect(notifications.registrations, hasLength(1));
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 예약 시각이 지나면 재등록 없이 꺼지고 전체 알림을 비허용으로 복원하면 계정 설정과 필요시 예약이 제거되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'expired reminder does not repeat and master switch disables it',
    () async {
      final notifications = RecordingNotificationService();
      var clock = now;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {},
        notifications: notifications,
        now: () => clock,
      );
      addTearDown(control.dispose);
      await control.save(now.add(const Duration(hours: 1)), isEnglish: true);
      clock = now.add(const Duration(hours: 2));
      await control.restore(allowed: true, isEnglish: true);
      expect(control.enabled, isFalse);
      expect(notifications.registrations, hasLength(1));
      await control.save(clock.add(const Duration(hours: 1)), isEnglish: true);
      await control.restore(allowed: false, isEnglish: true);
      expect(control.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'medbuddy_as_needed_check_a',
        ),
        isNull,
      );
      expect(notifications.cancellations.last.slotKey, 'as_needed');
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 권한 거부와 예약 실패 모두 StateError를 전달하며 실패한 예약을 활성 설정으로 남기지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'permission and scheduling failures never leave an enabled preference',
    () async {
      final notifications = RecordingNotificationService()
        ..permissionGranted = false;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(control.dispose);
      await expectLater(
        control.save(now.add(const Duration(hours: 1)), isEnglish: true),
        throwsStateError,
      );
      expect(notifications.registrations, isEmpty);
      notifications.permissionGranted = true;
      notifications.failRegistration = true;
      await expectLater(
        control.save(now.add(const Duration(hours: 1)), isEnglish: true),
        throwsStateError,
      );
      expect(control.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'medbuddy_as_needed_check_a',
        ),
        isNull,
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 환경설정 조회를 대기하는 사이 세션을 바꾸면 저장은 실패하고 등록·취소 요청은 모두 없는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'session change while loading preferences prevents scheduling',
    () async {
      final notifications = RecordingNotificationService();
      final prefs = Completer<SharedPreferences>();
      var current = true;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {
          if (!current) throw StateError('session changed');
        },
        notifications: notifications,
        preferences: () => prefs.future,
        now: () => now,
      );
      addTearDown(control.dispose);
      final result = control.save(
        now.add(const Duration(hours: 1)),
        isEnglish: false,
      );
      final expectation = expectLater(result, throwsStateError);
      current = false;
      prefs.complete(await SharedPreferences.getInstance());
      await expectation;
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 필요시 알림에 복용 완료·미루기 동작을 붙여도 일정 열기로만 해석되어 빠른 복약 처리를 실행하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('PRN payload only opens schedule even with supplied quick action', () {
    for (final action in [
      null,
      NotificationService.markSlotTakenActionId,
      NotificationService.snoozeTenMinutesActionId,
    ]) {
      final selection = NotificationService.selectionFromPayload(
        'schedule:as_needed:84005:2026-10-17',
        actionId: action,
      );
      expect(
        selection?.destination,
        MedicationNotificationDestination.schedule,
      );
      expect(selection?.action, MedicationNotificationAction.open);
    }
  });
}
