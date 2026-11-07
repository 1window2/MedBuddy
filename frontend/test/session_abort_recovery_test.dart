// 파일명: session_abort_recovery_test.dart
// 역할: 로그아웃 중단 시 같은 세션의 서비스를 복원하되 교체된 계정은 되살리지 않는지 검증한다.

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

// 클래스명: _NoSchedule
// 역할: 외부 조회 없이 빈 일정을 제공한다.
// 주요 책임: 오늘·기간 조회가 테스트에 약을 추가하지 않도록 격리한다.
// 속성: 없음; 반환 일정은 항상 비어 있다.
class _NoSchedule extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 오늘의 약이 없는 조회 결과를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationSchedule>>: 빈 목록.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async => [];
  // 함수이름: requestMedicationScheduleWindow
  // 함수역할:
  // - 기간 조회에서 추가 일정을 제공하지 않는다.
  // 매개변수:
  // - days(int): 요청 기간; 가짜 구현은 값과 무관하게 비어 있다.
  // 반환값:
  // - Future<List<MedicationSchedule>>: 빈 목록.
  @override
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) async => [];
}

// 클래스명: _Alarms
// 역할: 복원할 아침·저녁 알림 시간을 제공한다.
// 주요 책임: 예약 호출을 기록 서비스에 전달하고 기본값이 아닌 시간을 반환한다.
// 속성: 상속된 notificationRegistrar는 주입한 기록 서비스에 연결된다.
class _Alarms extends SetNotification {
  // 함수이름: _Alarms
  // 함수역할:
  // - 테스트의 알림 기록기를 예약 콜백으로 연결한다.
  // 매개변수:
  // - notifications(RecordingNotificationService): 예약 내역을 보관할 서비스.
  // 반환값:
  // - 새 _Alarms 인스턴스.
  _Alarms(RecordingNotificationService notifications)
    : super(notificationRegistrar: notifications.registerNotification);
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 복구 과정의 시간 보존을 확인하도록 활성 아침 08:17·저녁 19:23 알림을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationAlarm>>: 고정된 두 알림.
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

// 클래스명: _Work
// 역할: 백그라운드 작업 정리의 실패 지점을 제어한다.
// 주요 책임: 저장소 개방/작업 취소 실패를 주입하고 복구 재예약을 센다.
// 속성: store는 저장소, fail은 실패 지점, registrations는 일회 작업 등록 횟수.
class _Work extends DoseSyncWorkPlatform {
  // 함수이름: _Work
  // 함수역할:
  // - 작업 스케줄러가 사용할 저장소와 실패 모드를 설정한다.
  // 매개변수:
  // - store(DoseOutboxStore): 세션의 실제 테스트 저장소.
  // - fail(String): store 또는 work이면 해당 동작에서 실패.
  // 반환값:
  // - 새 _Work 인스턴스.
  _Work(this.store, this.fail);
  final DoseOutboxStore store;
  final String fail;
  var registrations = 0;
  // 함수이름: supported
  // 함수역할:
  // - 호스트 플랫폼과 무관하게 백그라운드 작업 지원 분기를 실행한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 항상 true.
  @override
  bool get supported => true;
  // 함수이름: openStore
  // 함수역할:
  // - 설정된 저장소를 반환하거나 store 실패 지점을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DoseOutboxStore>: 주입 저장소; fail이 store이면 StateError.
  @override
  Future<DoseOutboxStore> openStore() async {
    if (fail == 'store') throw StateError('store failure');
    return store;
  }

  // 함수이름: cancelAll
  // 함수역할:
  // - 작업 취소 단계에서 선택적으로 실패하며 실제 작업은 조작하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 완료; fail이 work이면 StateError.
  @override
  Future<void> cancelAll() async {
    if (fail == 'work') throw StateError('work cancellation failure');
  }

  // 함수이름: registerOneOff
  // 함수역할:
  // - 세션 복구가 일회 전송 작업을 다시 등록하는 횟수를 기록한다.
  // 매개변수:
  // - owner(String): 예약 계정; 값은 별도로 검사하지 않는다.
  // 반환값:
  // - Future<void>: registrations 증가 완료.
  @override
  Future<void> registerOneOff(String owner) async {
    registrations++;
  }

  // 함수이름: registerPeriodic
  // 함수역할:
  // - 주기 작업 등록을 성공으로 처리하되 운영체제 작업을 만들지 않는다.
  // 매개변수:
  // - owner(String): 예약 계정; 가짜 구현에서 사용하지 않는다.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> registerPeriodic(String owner) async {}
}

// 클래스명: _Widget
// 역할: 홈 위젯 정리·복원 단계의 저장 상태와 실패를 재현한다.
// 주요 책임: 저장/렌더링은 한 번, 예약 취소는 요청마다 설정된 실패를 발생시킨다.
// 속성: store/fail은 저장소와 실패 모드, latest는 마지막 저장 JSON, throwOnce는 일회 실패 여부.
class _Widget extends DoseHomeWidgetPlatform {
  // 함수이름: _Widget
  // 함수역할:
  // - 위젯 플랫폼에 세션 저장소와 실패 지점을 주입한다.
  // 매개변수:
  // - store(DoseOutboxStore): 복구 여부를 검사할 저장소.
  // - fail(String): widget-cancel/widget-save/widget-update 실패 선택자.
  // 반환값:
  // - 새 _Widget 인스턴스.
  _Widget(this.store, this.fail);
  final DoseOutboxStore store;
  final String fail;
  Map<String, dynamic>? latest;
  var throwOnce = true;
  // 함수이름: supported
  // 함수역할:
  // - 실제 운영체제와 무관하게 위젯 서비스 경로를 활성화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 항상 true.
  @override
  bool get supported => true;
  // 함수이름: openStore
  // 함수역할:
  // - 위젯과 동기화 서비스가 공유하는 테스트 저장소를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DoseOutboxStore>: 주입 저장소.
  @override
  Future<DoseOutboxStore> openStore() async => store;
  // 함수이름: readJournal
  // 함수역할:
  // - 플랫폼에 미처리 위젯 동작이 없는 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<String?>: 빈 목록을 인코딩한 JSON.
  @override
  Future<String?> readJournal() async => '[]';
  // 함수이름: cancelScheduledUpdates
  // 함수역할:
  // - 위젯 예약 취소 단계의 실패를 선택적으로 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 완료; fail이 widget-cancel이면 StateError.
  @override
  Future<void> cancelScheduledUpdates() async {
    if (fail == 'widget-cancel') throw StateError('widget cancel failure');
  }

  // 함수이름: saveState
  // 함수역할:
  // - JSON을 latest에 기록하고 계정 없는 초기화 상태 저장에서 한 번 실패하도록 제어한다.
  // 매개변수:
  // - state(String): 위젯 상태 JSON.
  // 반환값:
  // - Future<void>: 기록 완료; JSON 파싱 오류 또는 설정된 일회 StateError.
  @override
  Future<void> saveState(String state) async {
    final value = jsonDecode(state) as Map<String, dynamic>;
    latest = value;
    if (fail == 'widget-save' && !value.containsKey('owner') && throwOnce) {
      throwOnce = false;
      throw StateError('widget write failure');
    }
  }

  // 함수이름: updateWidget
  // 함수역할:
  // - 위젯 렌더링 단계의 실패를 한 번 발생시켜 다음 복구 호출이 성공하도록 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 완료; 선택된 첫 widget-update 호출은 StateError.
  @override
  Future<void> updateWidget() async {
    if (fail == 'widget-update' && throwOnce) {
      throwOnce = false;
      throw StateError('widget render failure');
    }
  }

  // 함수이름: scheduleUpdate
  // 함수역할:
  // - 위젯 예약을 실제로 생성하지 않고 성공시킨다.
  // 매개변수:
  // - at(DateTime): 예약 시각; 가짜 구현에서 사용하지 않는다.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> scheduleUpdate(DateTime at) async {}
  // 함수이름: cancelReminder
  // 함수역할:
  // - 알림 취소를 성공 처리하여 다른 정리 단계의 실패를 격리한다.
  // 매개변수:
  // - owner(String): 대상 계정.
  // - slotKey(String): 대상 시간대.
  // - date(DateTime): 대상 날짜; 입력은 기록하지 않는다.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {}
  // 함수이름: registerSync
  // 함수역할:
  // - 위젯의 동기화 요청을 실제 작업 생성 없이 성공 처리한다.
  // 매개변수:
  // - owner(String): 요청 계정; 가짜 구현에서 사용하지 않는다.
  // 반환값:
  // - Future<void>: 즉시 완료.
  @override
  Future<void> registerSync(String owner) async {}
}

// 함수이름: main
// 함수역할:
// - 정리 실패를 주입하여 동기화·위젯·알림의 복구와 계정 경계 보호 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: tearDown
  // 함수역할:
  // - 위젯의 테스트 상태와 백그라운드 플랫폼을 기본 구현으로 되돌린다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
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
    // Function Name: aborted cleanup recovery
    // Description:
    // - Injects each cleanup failure and checks the original session, pending PRN metadata, widget and dose enqueue survive; preserves untouched reminders or restores their configured times after reminder cleanup fails.
    // Parameters:
    // - tester (WidgetTester): Drives the widget tree and advances the test clock.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
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
        final registeredBefore = notifications.registrations.length;
        final cancelledBefore = notifications.cancellations.length;
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
        if (failure != 'reminders') {
          // 알림 취소 전에 멈췄으면 예약된 알림은 그대로이므로 다시 계산하지 않는다. 다시 계산하면 기간
          // 일정이 없을 때 오늘 이후의 알림이 지워졌다.
          expect(notifications.registrations, hasLength(registeredBefore));
          expect(notifications.cancellations, hasLength(cancelledBefore));
        } else {
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
        }
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

  // 함수이름: a switched session is never restored by failed old cleanup
  // 함수역할:
  // - 정리 도중 새 계정으로 교체된 후 오류가 나도 이전 저장소와 전송 작업을 되살리지 않는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
