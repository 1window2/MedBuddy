// 파일명: notification_readiness_control.dart
// 역할: 복약 데이터를 바꾸지 않고 기기 알림 권한과 테스트 알림을 관리한다.
import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';

// 클래스명: NotificationReadinessSnapshot
// 역할: 알림과 정확한 예약의 사용 가능 상태를 한 번의 점검 결과로 보관한다.
// 주요 책임: 허용, 거부, 확인 불가를 구분해 화면에 전달한다.
// 속성: notifications/medicationChannel/exactAlarms: nullable 권한 상태; exactAlarmsEditable: 설정 변경 지원 여부.
class NotificationReadinessSnapshot {
  final bool? notifications;
  final bool? medicationChannel;
  final bool? exactAlarms;
  final bool? exactAlarmsEditable;

  // 함수이름: NotificationReadinessSnapshot
  // 함수역할: 권한 조회 결과를 보관하며 생략한 값은 미확인 상태로 둔다.
  // 매개변수: notifications, medicationChannel, exactAlarms: 권한 허용 여부; exactAlarmsEditable: 정확한 알람 설정 지원 여부.
  // 반환값: 불변 점검 결과; null은 거부와 다르다.
  const NotificationReadinessSnapshot({
    this.notifications,
    this.medicationChannel,
    this.exactAlarms,
    this.exactAlarmsEditable,
  });
}

// 클래스명: NotificationReadinessControl
// 역할: 플랫폼별 알림 준비 상태 확인과 시스템 설정 이동을 조율한다.
// 주요 책임: 중복 점검을 합치고 조회 실패를 미확인으로 유지하며 허용된 정확한 예약을 복구한다.
// 속성: notificationService: 기기 알림 경계; 지원 플래그: 플랫폼 기능 여부; _loading: 진행 중인 공동 점검.
class NotificationReadinessControl {
  final NotificationService notificationService;
  final Future<void> Function()? openNotificationSettings;
  final bool supportsNotifications;
  final bool supportsExactAlarms;
  final bool supportsSystemSettings;
  Future<NotificationReadinessSnapshot>? _loading;

  // 함수이름: NotificationReadinessControl
  // 함수역할: 알림 서비스와 설정 이동 경계를 주입하고 미지정 지원 여부를 현재 플랫폼으로 결정한다.
  // 매개변수: notificationService: 필수 서비스; openNotificationSettings: 선택적 설정 이동 함수; supportsNotifications/supportsExactAlarms/supportsSystemSettings: 테스트용 지원 여부 재정의.
  // 반환값: 점검 제어 객체; 미지원 플랫폼을 허용 상태로 간주하지 않는다.
  NotificationReadinessControl({
    required this.notificationService,
    this.openNotificationSettings,
    bool? supportsNotifications,
    bool? supportsExactAlarms,
    bool? supportsSystemSettings,
  }) : supportsNotifications =
           supportsNotifications ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS)),
       supportsExactAlarms =
           supportsExactAlarms ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       supportsSystemSettings =
           supportsSystemSettings ??
           (openNotificationSettings != null ||
               (!kIsWeb && defaultTargetPlatform == TargetPlatform.android));

  // 함수이름: refresh
  // 함수역할: 복귀와 새로고침 요청이 겹치면 진행 중인 권한 점검을 공유한다.
  // 매개변수: 없음.
  // 반환값: 점검 결과 Future; 완료 후 다음 요청은 새로 점검한다.
  Future<NotificationReadinessSnapshot> refresh() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  // 함수이름: _load
  // 함수역할: 지원되는 권한을 읽고 정확한 알람이 허용되면 부정확한 예약의 재등록을 시도한다.
  // 매개변수: 없음.
  // 반환값: 권한 스냅샷; 각 조회 실패는 null로 남기며 재예약 실패는 권한 값을 바꾸지 않는다.
  Future<NotificationReadinessSnapshot> _load() async {
    bool? notifications;
    bool? medicationChannel;
    bool? exactAlarms;
    bool? exactAlarmsEditable;
    if (supportsNotifications) {
      try {
        final permissions = await notificationService
            .readReadinessPermissions();
        notifications = permissions.notifications;
        medicationChannel = permissions.medicationChannel;
        exactAlarms = permissions.exactAlarms;
      } catch (_) {
        // 플러그인 오류와 미허용을 구분한다.
      }
    }
    if (supportsExactAlarms && exactAlarms == true) {
      try {
        await notificationService.rescheduleInexactRemindersAsExact();
      } catch (_) {
        // 재예약 오류와 사용자가 허용한 권한 상태는 구분한다.
      }
    }
    if (supportsExactAlarms) {
      try {
        exactAlarmsEditable = await notificationService
            .supportsExactReminderSettings();
      } catch (_) {
        // 설정 지원 여부를 읽지 못해도 기존 권한을 꺼진 것으로 바꾸지 않는다.
      }
    }
    return NotificationReadinessSnapshot(
      notifications: notifications,
      medicationChannel: medicationChannel,
      exactAlarms: exactAlarms,
      exactAlarmsEditable: exactAlarmsEditable,
    );
  }

  // 함수이름: requestNotificationPermission
  // 함수역할: 지원 플랫폼에서 알림 권한 요청을 실행한다.
  // 매개변수: 없음.
  // 반환값: 완료 Future; 미지원 시 UnsupportedError, 서비스 오류는 전파한다.
  Future<void> requestNotificationPermission() async {
    if (!supportsNotifications) {
      throw UnsupportedError('Notifications unavailable.');
    }
    await notificationService.requestPermission();
  }

  // 함수이름: openSystemSettings
  // 함수역할: 주입된 이동 함수 또는 알림 서비스로 시스템 알림 설정을 연다.
  // 매개변수: 없음.
  // 반환값: 완료 Future; 설정 이동 미지원 시 UnsupportedError.
  Future<void> openSystemSettings() async {
    if (!supportsSystemSettings) {
      throw UnsupportedError('Settings unavailable.');
    }
    await (openNotificationSettings ??
        notificationService.openSystemNotificationSettings)();
  }

  // 함수이름: openExactSettings
  // 함수역할: 정확한 알람 설정 화면을 열고 실제 권한 확인과 재예약은 복귀 후 refresh에 맡긴다.
  // 매개변수: 없음.
  // 반환값: 완료 Future; 정확한 알람 미지원 시 UnsupportedError.
  Future<void> openExactSettings() async {
    if (!supportsExactAlarms) {
      throw UnsupportedError('Exact alarms unavailable.');
    }
    await notificationService.openExactReminderSettings();
  }

  // 함수이름: sendTest
  // 함수역할: 지정 언어로 알림 준비 상태 확인용 테스트 알림을 보낸다.
  // 매개변수: language: 테스트 알림 문구의 언어 코드.
  // 반환값: 알림 표시 완료 Future; 서비스 오류는 전파한다.
  Future<void> sendTest(String language) =>
      notificationService.showReadinessTestNotification(language: language);
}
