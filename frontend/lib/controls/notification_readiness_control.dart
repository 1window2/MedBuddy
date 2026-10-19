// 파일명: notification_readiness_control.dart
// 역할: 복약 데이터를 바꾸지 않고 기기 권한과 첫 약 등록 상태를 점검한다.
import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';

class NotificationReadinessSnapshot {
  final bool? hasMedication;
  final bool? notifications;
  final bool? medicationChannel;
  final bool? exactAlarms;

  const NotificationReadinessSnapshot({
    this.hasMedication,
    this.notifications,
    this.medicationChannel,
    this.exactAlarms,
  });
}

class NotificationReadinessControl {
  final NotificationService notificationService;
  final Future<bool?> Function()? loadHasMedication;
  final Future<void> Function()? openNotificationSettings;
  final bool supportsNotifications;
  final bool supportsExactAlarms;
  final bool supportsSystemSettings;
  Future<NotificationReadinessSnapshot>? _loading;

  // 권한 확인과 시스템 이동 경계를 주입하며, 지원하지 않는 플랫폼은 성공으로 표시하지 않는다.
  NotificationReadinessControl({
    required this.notificationService,
    this.loadHasMedication,
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
    bool? hasMedication;
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
    try {
      hasMedication = await loadHasMedication?.call();
    } catch (_) {
      // 오프라인일 때 등록 약이 없다고 단정하지 않는다.
    }
    return NotificationReadinessSnapshot(
      hasMedication: hasMedication,
      notifications: notifications,
      medicationChannel: medicationChannel,
      exactAlarms: exactAlarms,
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

  // 기존의 정확한 알람 재등록 함수만 재사용한다.
  Future<void> requestExactPermission() async {
    if (!supportsExactAlarms) {
      throw UnsupportedError('Exact alarms unavailable.');
    }
    final allowed = await notificationService.requestExactReminderPermission();
    if (allowed) await notificationService.rescheduleInexactRemindersAsExact();
  }

  Future<void> sendTest(String language) =>
      notificationService.showReadinessTestNotification(language: language);
}
