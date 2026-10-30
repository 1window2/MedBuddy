// 파일명: notification_readiness_control.dart
// 역할: 복약 데이터를 바꾸지 않고 기기 알림 권한과 테스트 알림을 관리한다.
import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';

class NotificationReadinessSnapshot {
  final bool? notifications;
  final bool? medicationChannel;
  final bool? exactAlarms;
  final bool? exactAlarmsEditable;

  const NotificationReadinessSnapshot({
    this.notifications,
    this.medicationChannel,
    this.exactAlarms,
    this.exactAlarmsEditable,
  });
}

class NotificationReadinessControl {
  final NotificationService notificationService;
  final Future<void> Function()? openNotificationSettings;
  final bool supportsNotifications;
  final bool supportsExactAlarms;
  final bool supportsSystemSettings;
  Future<NotificationReadinessSnapshot>? _loading;

  // 권한 확인과 시스템 이동 경계를 주입하며, 지원하지 않는 플랫폼은 성공으로 표시하지 않는다.
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

  // 복귀·새로고침이 겹쳐도 한 점검만 수행하고 실패 항목은 미확인으로 남긴다.
  Future<NotificationReadinessSnapshot> refresh() =>
      _loading ??= _load().whenComplete(() => _loading = null);

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

  Future<void> requestNotificationPermission() async {
    if (!supportsNotifications) {
      throw UnsupportedError('Notifications unavailable.');
    }
    await notificationService.requestPermission();
  }

  Future<void> openSystemSettings() async {
    if (!supportsSystemSettings) {
      throw UnsupportedError('Settings unavailable.');
    }
    await (openNotificationSettings ??
        notificationService.openSystemNotificationSettings)();
  }

  // 재예약은 설정 화면에서 돌아온 뒤 refresh에서 실제 허용 상태를 확인하고 수행한다.
  Future<void> openExactSettings() async {
    if (!supportsExactAlarms) {
      throw UnsupportedError('Exact alarms unavailable.');
    }
    await notificationService.openExactReminderSettings();
  }

  Future<void> sendTest(String language) =>
      notificationService.showReadinessTestNotification(language: language);
}
