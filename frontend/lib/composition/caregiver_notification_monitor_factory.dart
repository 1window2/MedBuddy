// 파일명: caregiver_notification_monitor_factory.dart
// 역할: 실행 환경에 맞는 보호자 복약 알림 감시 서비스를 조합한다.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../controls/check_caregiver_medication_control.dart';
import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_caregiver_notification_control.dart';
import '../services/api_config.dart';
import '../services/caregiver_notification_monitor_service.dart';
import '../services/notification_service.dart';

// 파일명: caregiver_notification_monitor_factory.dart
// 역할: 보호자 알림 감시에 필요한 Control과 플랫폼 서비스를 조립한다.

// 클래스명: CaregiverNotificationMonitorFactory
// 역할: 순수 감시 서비스가 구체 HTTP Control을 직접 생성하지 않게 한다.
class CaregiverNotificationMonitorFactory {
  const CaregiverNotificationMonitorFactory._();

  static CaregiverNotificationMonitorService create({
    required String caregiverHash,
    String baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    Duration pollingInterval =
        CaregiverNotificationMonitorService.defaultPollingInterval,
    Duration idlePollingInterval =
        CaregiverNotificationMonitorService.defaultIdlePollingInterval,
    bool requestPermission = true,
    bool monitorCompletionTransitions = true,
    String Function()? languageProvider,
    ValueChanged<bool>? onCaregiverStatusChanged,
  }) {
    final linkControl = LinkPatientCaregiver(
      baseUrl: baseUrl,
      userHash: caregiverHash,
      client: client,
    );
    final settingControl = SetCaregiverNotification(
      baseUrl: baseUrl,
      caregiverHash: caregiverHash,
      client: client,
    );
    final medicationControl = CheckCaregiverMedication(
      baseUrl: baseUrl,
      caregiverHash: caregiverHash,
      client: client,
    );
    final userSettingControl = ManageUserSetting(
      baseUrl: baseUrl,
      userHash: caregiverHash,
      client: client,
      useRemotePersistence: false,
    );

    return CaregiverNotificationMonitorService(
      caregiverHash: caregiverHash,
      loadLinks: linkControl.requestLinkScreen,
      loadSettings: (patientHash) {
        return settingControl.requestCaregiverNotificationSettings(
          patientHash: patientHash,
        );
      },
      loadSchedules: (patientHash) async {
        final info = await medicationControl.requestPatientMedicationInfo(
          patientHash: patientHash,
        );
        return info.todayMedicationScheduleList;
      },
      sendAlert:
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {
            final userSetting = await userSettingControl.requestUserSetting();
            if (!userSetting.caregiverNotificationsEnabled) {
              return;
            }
            NotificationService.instance.setShowSensitiveDetails(
              userSetting.showNotificationDetails,
            );
            return NotificationService.instance.showCaregiverAlert(
              id: id,
              title: title,
              body: body,
              patientHash: patientHash,
              language: languageProvider?.call() ?? 'ko',
            );
          },
      permissionRequester: NotificationService.instance.requestPermission,
      pollingInterval: pollingInterval,
      idlePollingInterval: idlePollingInterval,
      requestPermission: requestPermission,
      monitorCompletionTransitions: monitorCompletionTransitions,
      languageProvider: languageProvider,
      onCaregiverStatusChanged: onCaregiverStatusChanged,
      onDispose: () {
        linkControl.dispose();
        settingControl.dispose();
        medicationControl.dispose();
        userSettingControl.dispose();
      },
    );
  }
}
