// 파일명: reminder_session_boundary_test.dart
// 역할: 계정 전환 중 오래된 알림 작업이 새 계정의 예약·개인정보 설정을 변경하지 않는지 검증한다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 함수이름: main
// 함수역할:
// - 설정 조회, 시간대별 취소, 알림 등록 도중 소유권이 사라지는 경계 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 알림 사용 여부별 비동기 검증을 테스트 프레임워크에 등록한다.
void main() {
  for (final notificationsEnabled in [false, true]) {
    // 함수이름: 오래된 설정 조회의 알림 변경 차단 테스트
    // 함수역할:
    // - 설정 조회를 기다리는 동안 소유권을 잃으면 취소·등록·개인정보 변경이 없어야 한다.
    // - 알림을 켜거나 끈 경우 모두 이전 계정의 작업은 정상 종료로 처리한다.
    // 매개변수:
    // - 없음; notificationsEnabled(bool)는 조회 결과의 알림 사용 설정이다.
    // 반환값:
    // - Future<void>: 동기화 결과와 부수 효과 없음의 검증 완료.
    test(
      'a stale worker cannot cancel the new account alarms (enabled=$notificationsEnabled)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = Completer<List<MedicationAlarm>>();
        var ownsReminders = true;
        final cancelled = <String?>[];
        final privacy = <bool>[];
        final service = MedicationReminderRefreshService(
          loadSettings: () => settings.future,
          loadSchedules: () async => [],
          loadUserSetting: () async => UserSetting(
            medicationNotificationsEnabled: notificationsEnabled,
            notificationDetailMode: 'full',
          ),
          registerReminder:
              ({
                required id,
                required slotKey,
                required slotTitle,
                required hour,
                required minute,
                required activeDates,
                language = 'ko',
              }) async => fail('A stale account must not register reminders'),
          cancelReminder: (id, {slotKey}) async {
            cancelled.add(slotKey);
          },
          setPrivacy: privacy.add,
          ownsReminders: () async => ownsReminders,
        );
        addTearDown(service.dispose);
        final pending = service.synchronize();
        ownsReminders = false;
        settings.complete(const []);

        expect(await pending, isTrue);
        expect(cancelled, isEmpty);
        expect(privacy, isEmpty);
      },
    );

    // 함수이름: 시간대 취소 사이 계정 전환 테스트
    // 함수역할:
    // - 첫 아침 시간대 취소 직후 소유권을 잃으면 이후 시간대는 건드리지 않아야 한다.
    // - 빈 일정에서 새 알림을 등록하려 하면 대역이 즉시 테스트를 실패시킨다.
    // 매개변수:
    // - 없음; notificationsEnabled(bool)는 알림 사용·미사용 경로를 모두 검사한다.
    // 반환값:
    // - Future<void>: 취소 목록이 아침 한 항목인지 검증 완료.
    test(
      'cancellation stops between slots at account switch (enabled=$notificationsEnabled)',
      () async {
        SharedPreferences.setMockInitialValues({});
        var ownsReminders = true;
        final cancelled = <String?>[];
        final service = MedicationReminderRefreshService(
          loadSettings: () async => [],
          loadSchedules: () async => [],
          loadUserSetting: () async =>
              UserSetting(medicationNotificationsEnabled: notificationsEnabled),
          registerReminder:
              ({
                required id,
                required slotKey,
                required slotTitle,
                required hour,
                required minute,
                required activeDates,
                language = 'ko',
              }) async => fail('Disabled slots must not register reminders'),
          cancelReminder: (id, {slotKey}) async {
            cancelled.add(slotKey);
            ownsReminders = false;
          },
          ownsReminders: () async => ownsReminders,
        );
        addTearDown(service.dispose);

        expect(await service.synchronize(), isTrue);
        expect(cancelled, ['morning']);
      },
    );
  }

  // 함수이름: 등록 중 로그아웃한 알림 정리 테스트
  // 함수역할:
  // - 예약 등록 직후 소유권이 사라지면 방금 등록한 시간대도 취소해야 한다.
  // - 활성 날짜를 고정하여 빈 예약 집합이 단순히 날짜 범위 밖이라 생긴 결과가 아님을 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 정상 종료 결과와 남은 예약 없음의 검증 완료.
  test(
    'sign-out during registration still removes the just-armed reminder',
    () async {
      SharedPreferences.setMockInitialValues({});
      var ownsReminders = true;
      final armed = <String>{};
      final service = MedicationReminderRefreshService(
        loadSettings: () async => const [
          MedicationAlarm(
            slotKey: 'morning',
            hour: 8,
            minute: 0,
            enabled: true,
          ),
        ],
        loadSchedules: () async => [
          MedicationSchedule(
            medicationName: 'synthetic',
            prescriptionDate: DateTime(2026, 10, 21),
            medicationTime: 14,
            scheduleSlotKeys: const ['morning'],
          ),
        ],
        registerReminder:
            ({
              required id,
              required slotKey,
              required slotTitle,
              required hour,
              required minute,
              required activeDates,
              language = 'ko',
            }) async {
              armed.add(slotKey);
              ownsReminders = false;
            },
        cancelReminder: (id, {slotKey}) async {
          armed.remove(slotKey);
        },
        ownsReminders: () async => ownsReminders,
        now: () => DateTime(2026, 10, 21, 7),
      );
      addTearDown(service.dispose);

      expect(await service.synchronize(), isTrue);
      expect(armed, isEmpty);
    },
  );
}
