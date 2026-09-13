// File Name: check_schedule_ui_boundary_test.dart
// Role: Regression coverage for schedule loading, retry, reminder feedback, and whole-slot completion
//   UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _FailOnceCheckSchedule
// Role: Schedule stub that fails its first read and then permits a successful retry.
// Responsibilities:
// - Count schedule reads, reject the first, and return an empty successful retry.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _FailOnceCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Count schedule reads, reject the first, and return an empty successful retry.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule after the first call; the first call throws StateError.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      throw StateError('Schedule lookup failed.');
    }
    return const [];
  }
}

// Class Name: _EmptyCheckSchedule
// Role: Successful empty-schedule stub for distinguishing no data from errors.
// Responsibilities:
// - Model a valid schedule response with no due medications.
class _EmptyCheckSchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Model a valid schedule response with no due medications.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule list.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

// Class Name: _SuccessfulThenFailingCheckSchedule
// Role: Schedule stub that supplies stale data once and fails subsequent refreshes.
// Responsibilities:
// - Return an initial tablet, then fail refreshes to exercise stale-data clearing.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _SuccessfulThenFailingCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Return an initial tablet, then fail refreshes to exercise stale-data clearing.
  // Parameters:
  // - None.
  // Returns:
  // - One initial schedule; later calls throw StateError.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      return const [
        MedicationSchedule(
          medicationName: 'stale-tablet',
          intakeTime: '1 time',
          medicationTime: 1,
        ),
      ];
    }
    throw StateError('Schedule lookup failed.');
  }
}

// 클래스명: _ActiveCheckSchedule
// 역할: 활성 아침 복약 일정을 제공해 알림 동기화 실패와 일정 로딩을 분리하는 대역.
// 주요 책임:
// - 아침 시간대가 명시된 활성 약 일정을 제공한다.
class _ActiveCheckSchedule extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 아침 시간대가 명시된 활성 약 일정을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 아침에 한 번 복용하는 일정 한 건.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationName: 'active-tablet',
        intakeTime: '1 time',
        medicationTime: 1,
        scheduleSlotKeys: ['morning'],
      ),
    ];
  }
}

// Class Name: _CompletableCheckSchedule
// Role: Stateful schedule stub for completion feedback, undo timing, and whole-slot toggles.
// Responsibilities:
// - Assert the morning scope, count whole-slot updates, and replace the fake completion state.
// Attributes:
// - _completed (bool): Completion flag shared by the single morning schedule.
// - wholeSlotUpdateCount (int): Number of whole-slot completion requests.
class _CompletableCheckSchedule extends CheckSchedule {
  bool _completed = false;
  int wholeSlotUpdateCount = 0;

  // 함수이름: _schedule
  // 함수역할:
  // - 현재 완료 플래그를 아침 시간대와 전체 상태에 반영한 일정을 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 완료 상태의 테스트 약 일정.
  MedicationSchedule get _schedule => MedicationSchedule(
    medicationID: 'completion-tablet',
    medicationName: '테스트정',
    dosage: '1',
    intakeTime: '1회',
    medicationTime: 1,
    scheduleSlotKeys: const ['morning'],
    slotStatuses: {'morning': _completed},
    medicationStatus: _completed,
  );

  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 현재 완료 상태가 반영된 아침 일정을 조회 결과로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 상태 갱신 가능한 일정 한 건.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return [_schedule];
  }

  // 함수이름: updateMedicationStatus
  // 함수역할:
  // - 요청한 완료 여부를 저장해 다음 조회와 실행 취소에 반영한다.
  // 매개변수:
  // - medicationId (String): 선택한 저장 약 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - medicationStatus (bool): 요청한 복약 완료 또는 미완료 상태.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 변경된 완료 상태의 일정.
  @override
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    _completed = medicationStatus;
    return _schedule;
  }

  // Function Name: updateMedicationSlotStatus
  // Description:
  // - Assert the morning scope, count whole-slot updates, and replace the fake completion state.
  // Parameters:
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
  // - medicationStatus (bool): Requested taken/untaken completion state.
  // Returns:
  // - The updated schedule as a one-item list.
  @override
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    expect(slotKey, 'morning');
    wholeSlotUpdateCount += 1;
    _completed = medicationStatus;
    return [_schedule];
  }
}

// Class Name: _VisualScheduleCheckSchedule
// Role: Visual schedule fixture for explicit dosage units and medication-image rendering.
// Responsibilities:
// - Supply a half-tablet dose and trusted image URL for visual schedule assertions.
class _VisualScheduleCheckSchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Supply a half-tablet dose and trusted image URL for visual schedule assertions.
  // Parameters:
  // - None.
  // Returns:
  // - One once-daily schedule with an explicit dosage unit and image.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationID: 'visual-tablet',
        medicationName: '테스트정',
        dosage: '0.5정',
        intakeTime: '1회',
        medicationTime: 1,
        imageUrl: 'https://nedrug.mfds.go.kr/tablet.png',
      ),
    ];
  }
}

// Class Name: _EmptySetNotification
// Role: Empty alarm lookup for schedule tests without enabled reminders.
// Responsibilities:
// - Model a successful alarm lookup with no stored reminder settings.
class _EmptySetNotification extends SetNotification {
  // Function Name: requestMedicationAlarm
  // Description:
  // - Model a successful alarm lookup with no stored reminder settings.
  // Parameters:
  // - None.
  // Returns:
  // - An empty alarm list.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// 클래스명: _EnabledSetNotification
// 역할: 오전 8시 활성 알림을 제공하는 조회 대역.
// 주요 책임:
// - 아침 시간대의 오전 8시 활성 알림을 제공한다.
class _EnabledSetNotification extends SetNotification {
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 아침 시간대의 오전 8시 활성 알림을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 활성 아침 알림 한 건.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [
      MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
    ];
  }
}

// Class Name: _MutableSetNotification
// Role: Mutable alarm fixture for verifying successful enable/disable feedback in the schedule UI.
// Responsibilities:
// - Accept reminder registration without creating a real device notification.
class _MutableSetNotification extends SetNotification {
  MedicationAlarm _setting = const MedicationAlarm(
    slotKey: 'morning',
    hour: 8,
    minute: 0,
    enabled: false,
  );

  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 가장 최근에 저장하거나 비활성화한 알림 상태를 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 알림 설정 한 건.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => [_setting];

  // 함수이름: saveNotificationSetting
  // 함수역할:
  // - 선택한 시간대와 시각을 저장하고 알림을 활성화한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키.
  // - hour (int): 24시간제 기준 선택 알림 시.
  // - minute (int): 선택한 로컬 알림 시각의 분 값.
  // 반환값:
  // - 갱신된 활성 알림 설정.
  @override
  Future<MedicationAlarm> saveNotificationSetting({
    required String slotKey,
    required int hour,
    required int minute,
  }) async {
    _setting = MedicationAlarm(
      slotKey: slotKey,
      hour: hour,
      minute: minute,
      enabled: true,
    );
    return _setting;
  }

  // 함수이름: disableAlarmSetting
  // 함수역할:
  // - 기존 알림 시각을 보존한 채 활성 상태만 해제한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 비활성으로 바뀐 현재 알림 설정.
  @override
  Future<MedicationAlarm> disableAlarmSetting(String slotKey) async {
    _setting = _setting.copyWith(enabled: false);
    return _setting;
  }

  // Function Name: registerNotification
  // Description:
  // - Accept reminder registration without creating a real device notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
  //   consumed by this fixture.
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {}
}

// Class Name: _SuccessfulNotificationService
// Role: Successful notification-platform substitute for schedule UI feedback tests.
// Responsibilities:
// - Skip real notification-plugin initialization while satisfying the platform interface.
// - Grant notification permission in the fake without invoking an OS permission prompt.
// - Accept reminder registration without creating a real device notification.
class _SuccessfulNotificationService implements NotificationService {
  // 함수이름: setHistoryUser
  // 함수역할: 테스트에서는 계정별 플랫폼 저장을 생략한다. 매개변수: 계정과 저장 여부. 반환값: 없음.
  @override
  void setHistoryUser(String? userHash, {bool persistSession = true}) {}

  // 함수이름: setShowSensitiveDetails
  // 함수역할:
  // - 플랫폼 알림을 표시하지 않는 대역이므로 잠금 화면 상세정보 설정을 외부에 적용하지 않는다.
  // 매개변수:
  // - showSensitiveDetails (bool): 잠금 화면 알림에 민감 상세정보를 표시할지 여부. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 없음; 플랫폼 상태를 변경하지 않는다.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {}

  // 함수이름: openSystemNotificationSettings
  // 함수역할:
  // - 기기의 설정 앱을 열지 않고 시스템 알림 설정 이동을 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> openSystemNotificationSettings() async {}

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할:
  // - 실제 기기 알림을 건드리지 않고 예약 복약 알림 정리를 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelAllScheduledMedicationReminders() async {}

  // 함수이름: showLinkedChatAlert
  // 함수역할:
  // - 복약 대화 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // - messageKind (String?): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
  // - messagePreview (String?): 알림 인터페이스로 전달하는 선택적 채팅 미리보기. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showLinkedChatAlert({
    String? historyUserHash,
    bool recordHistory = true,
    required int id,
    required int linkId,
    String language = 'ko',
    String? messageKind,
    String? messagePreview,
    String? slotKey,
  }) async {}

  // Function Name: initialize
  // Description:
  // - Skip real notification-plugin initialization while satisfying the platform interface.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> initialize() async {}

  // Function Name: requestPermission
  // Description:
  // - Grant notification permission in the fake without invoking an OS permission prompt.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool> resolving to true.
  @override
  Future<bool> requestPermission() async => true;

  // Function Name: registerNotification
  // Description:
  // - Accept reminder registration without creating a real device notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
  //   consumed by this fixture.
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {}

  // 함수이름: cancelReminder
  // 함수역할:
  // - 기기 예약을 변경하지 않고 개별 복약 알림 취소를 성공 처리한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {}

  // Function Name: cancelAllMedicationReminders
  // Description:
  // - Acknowledge session reminder cleanup without calling the platform plugin.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> cancelAllMedicationReminders() async {}

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Accept the snooze action without scheduling a real delayed notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // - delay (Duration): Requested snooze interval or retry-wait callback. Accepted but not consumed by
  //   this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) async {}

  // 함수이름: showCaregiverAlert
  // 함수역할:
  // - 보호자 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
  // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
  // - patientHash (String?): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showCaregiverAlert({
    String? historyUserHash,
    bool recordHistory = true,
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
  }) async {}
}

// Class Name: _FailingNotificationService
// Role: Notification-platform substitute that fails scheduling while permitting other operations.
// Responsibilities:
// - Skip real notification-plugin initialization while satisfying the platform interface.
// - Grant notification permission in the fake without invoking an OS permission prompt.
// - Reject local reminder registration so schedule loading can be checked independently of platform
//   failure.
class _FailingNotificationService implements NotificationService {
  // 함수이름: setHistoryUser
  // 함수역할: 테스트에서는 계정별 플랫폼 저장을 생략한다. 매개변수: 계정과 저장 여부. 반환값: 없음.
  @override
  void setHistoryUser(String? userHash, {bool persistSession = true}) {}

  // 함수이름: setShowSensitiveDetails
  // 함수역할:
  // - 플랫폼 알림을 표시하지 않는 대역이므로 잠금 화면 상세정보 설정을 외부에 적용하지 않는다.
  // 매개변수:
  // - showSensitiveDetails (bool): 잠금 화면 알림에 민감 상세정보를 표시할지 여부. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 없음; 플랫폼 상태를 변경하지 않는다.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {}

  // 함수이름: openSystemNotificationSettings
  // 함수역할:
  // - 기기의 설정 앱을 열지 않고 시스템 알림 설정 이동을 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> openSystemNotificationSettings() async {}

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할:
  // - 실제 기기 알림을 건드리지 않고 예약 복약 알림 정리를 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelAllScheduledMedicationReminders() async {}

  // 함수이름: showLinkedChatAlert
  // 함수역할:
  // - 복약 대화 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // - messageKind (String?): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
  // - messagePreview (String?): 알림 인터페이스로 전달하는 선택적 채팅 미리보기. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showLinkedChatAlert({
    String? historyUserHash,
    bool recordHistory = true,
    required int id,
    required int linkId,
    String language = 'ko',
    String? messageKind,
    String? messagePreview,
    String? slotKey,
  }) async {}

  // Function Name: initialize
  // Description:
  // - Skip real notification-plugin initialization while satisfying the platform interface.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> initialize() async {}

  // Function Name: requestPermission
  // Description:
  // - Grant notification permission in the fake without invoking an OS permission prompt.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool> resolving to true.
  @override
  Future<bool> requestPermission() async => true;

  // Function Name: registerNotification
  // Description:
  // - Reject local reminder registration so schedule loading can be checked independently of platform
  //   failure.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
  //   consumed by this fixture.
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - A Future that fails with StateError for every registration.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {
    throw StateError('Notification registration failed.');
  }

  // 함수이름: cancelReminder
  // 함수역할:
  // - 기기 예약을 변경하지 않고 개별 복약 알림 취소를 성공 처리한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {}

  // Function Name: cancelAllMedicationReminders
  // Description:
  // - Acknowledge session reminder cleanup without calling the platform plugin.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> cancelAllMedicationReminders() async {}

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Accept the snooze action without scheduling a real delayed notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // - delay (Duration): Requested snooze interval or retry-wait callback. Accepted but not consumed by
  //   this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) async {}

  // 함수이름: showCaregiverAlert
  // 함수역할:
  // - 보호자 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
  // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
  // - patientHash (String?): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showCaregiverAlert({
    String? historyUserHash,
    bool recordHistory = true,
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
  }) async {}
}

// Function Name: main
// Description:
// - Register regression cases for schedule loading, retry, reminder feedback, and whole-slot
//   completion UI.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: schedule API failure shows a retry state.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('schedule API failure shows a retry state', (tester) async {
    final checkSchedule = _FailOnceCheckSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('schedule-load-error')), findsOneWidget);
    expect(find.byKey(const Key('schedule-load-retry')), findsOneWidget);
    expect(checkSchedule.requestCount, 1);

    await tester.tap(find.byKey(const Key('schedule-load-retry')));
    await tester.pumpAndSettle();

    expect(checkSchedule.requestCount, 2);
    expect(find.byKey(const Key('schedule-load-error')), findsNothing);
    expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 정상 응답이 빈 일정인 경우 오류 재시도 대신 일정 없음 상태를 표시하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('valid empty schedule keeps the domain empty state', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _EmptyCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('schedule-load-error')), findsNothing);
    expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 오늘 일정에 투약 단위와 약품 이미지 영역을 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('오늘 일정에 투약 단위와 약품 이미지 영역을 표시한다', (tester) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('0.5정'), findsOneWidget);
    expect(
      find.byKey(const Key('schedule-medication-thumbnail-visual-tablet')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('schedule-medication-thumbnail-visual-tablet')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('medication-image-viewer-close')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('medication-image-viewer-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영문 일정 화면은 작은 화면과 큰 글자에서도 넘치지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영문 일정 화면은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: _EmptySetNotification(),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
    );
    addTearDown(viewModel.dispose);
    await viewModel.requestUserSettingSave(
      fontSizeOption: 'large',
      readingSpeedOption: 'medium',
      language: 'en',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
          // 반환값:
          // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const CheckScheduleUI(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Today's Medication Schedule"), findsOneWidget);
    expect(find.text('0.5 tablet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 알림 설정과 해제 완료 결과를 화면 하단에 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('알림 설정과 해제 완료 결과를 화면 하단에 안내한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _MutableSetNotification(),
      notificationService: _SuccessfulNotificationService(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    final morningReminder = find.byTooltip('아침 알림 설정');
    await tester.tap(morningReminder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(viewModel.statusMessage, '아침 알림이 08:00으로 설정되었습니다.');
    expect(find.text(viewModel.statusMessage), findsOneWidget);

    await tester.tap(morningReminder);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('아침 알림이 해제되었습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 복약 완료 안내는 화면 이동 후에도 접근성 모드에서 자동으로 닫힌다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('복약 완료 안내는 화면 이동 후에도 접근성 모드에서 자동으로 닫힌다', (tester) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _CompletableCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 기존 하위 화면을 유지하면서 접근성 탐색 모드를 활성화한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
          // 반환값:
          // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
              child: child!,
            );
          },
          home: const CheckScheduleUI(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('복용 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 복약 화면에서 이동할 환경설정 도착 화면을 간단한 텍스트로 구성한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - 환경설정 문구가 있는 Scaffold.
        builder: (context) => const Scaffold(body: Text('환경설정')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Verify that the whole-slot button beside the alarm toggles all doses between taken and untaken.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('시간대 전체 버튼은 알림 오른쪽에서 전부 체크와 해제를 반복한다', (tester) async {
    final checkSchedule = _CompletableCheckSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    final reminderButton = find.byTooltip('아침 알림 설정');
    final wholeSlotButton = find.byKey(
      const ValueKey('schedule-entire-slot-toggle-morning'),
    );
    expect(
      find.byKey(const ValueKey('schedule-entire-slot-toggle-lunch')),
      findsNothing,
    );
    expect(find.byTooltip('아침 복약 전부 체크'), findsOneWidget);
    expect(
      tester.getCenter(wholeSlotButton).dx,
      greaterThan(tester.getCenter(reminderButton).dx),
    );

    await tester.tap(wholeSlotButton);
    await tester.pumpAndSettle();

    expect(checkSchedule.wholeSlotUpdateCount, 1);
    expect(find.text('아침 복약을 모두 완료했습니다.'), findsOneWidget);
    expect(find.byTooltip('아침 복약 전부 해제'), findsOneWidget);
    expect(
      viewModel.isMedicationDoseCompleted(
        'morning',
        viewModel.todayMedicationScheduleList.single,
      ),
      isTrue,
    );

    await tester.tap(wholeSlotButton);
    await tester.pumpAndSettle();

    expect(checkSchedule.wholeSlotUpdateCount, 2);
    expect(find.text('아침 복약 완료를 모두 해제했습니다.'), findsOneWidget);
    expect(find.byTooltip('아침 복약 전부 체크'), findsOneWidget);
    expect(
      viewModel.isMedicationDoseCompleted(
        'morning',
        viewModel.todayMedicationScheduleList.single,
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: failed refresh clears stale schedule data.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('failed refresh clears stale schedule data', () async {
    final checkSchedule = _SuccessfulThenFailingCheckSchedule();
    final viewModel = MedBuddyViewModel(checkSchedule: checkSchedule);
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();
    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);

    await viewModel.fetchTodayMedicationSchedule();
    expect(viewModel.todayMedicationScheduleList, isEmpty);
    expect(viewModel.hasTodayScheduleLoadError, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: reminder sync failure does not discard a loaded schedule.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('reminder sync failure does not discard a loaded schedule', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _EnabledSetNotification(),
      notificationService: _FailingNotificationService(),
    );
    addTearDown(viewModel.dispose);

    await expectLater(viewModel.refreshMedicationSchedule(), completes);

    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);
    expect(viewModel.statusMessage, contains('알림을 동기화하지 못했습니다'));
  });
}
