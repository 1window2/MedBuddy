// 파일명: caregiver_notification_monitor_factory.dart
// 역할: 보호자별 복약 감시에 필요한 HTTP Control과 로컬 알림 서비스를 조립한다.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../controls/check_caregiver_medication_control.dart';
import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_caregiver_notification_control.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/caregiver_notification_monitor_service.dart';
import '../services/notification_service.dart';
import '../controls/caregiver_alert_action_control.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/caregiver_alert_delivery_service.dart';


// Function Name: deliverCaregiverAlert
// Description: Reload notification preferences immediately before delivery; skip disabled alerts and propagate loading or delivery failures.
// Parameters: loadSetting (Future<UserSetting> Function()): current preferences; notify (Future<void> Function(bool)): delivery with the sensitive-details policy.
// Returns: Future<bool>: true after delivery, false when caregiver notifications are disabled.
Future<bool> deliverCaregiverAlert({
  required Future<UserSetting> Function() loadSetting,
  required Future<void> Function(bool showSensitiveDetails) notify,
}) async {
  final userSetting = await loadSetting();
  if (!userSetting.caregiverNotificationsEnabled) {
    return false;
  }
  await notify(userSetting.showNotificationDetails);
  return true;
}

// 클래스명: CaregiverNotificationMonitorFactory
// 역할: 보호자 복약 감시에 필요한 조회와 알림 경계를 조립한다.
// 주요 책임: 연동·일정·설정 조회 및 개인정보 정책을 연결하고 직접 만든 자원만 해제한다.
// 속성: 인스턴스 상태 없음; create가 감시 서비스와 소유 자원을 구성한다.
class CaregiverNotificationMonitorFactory {
  // 함수이름: CaregiverNotificationMonitorFactory._
  // 함수역할: 보호자 감시 조립을 정적 create 진입점으로만 제공하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - CaregiverNotificationMonitorFactory: 초기화된 인스턴스.
  const CaregiverNotificationMonitorFactory._();

  // Function Name: create
  // Description: Build caregiver monitoring with current privacy preferences and server-decided missed alerts; disposal releases only factory-owned resources.
  // Parameters: caregiverHash (String): owner; baseUrl (String): API root; client (http.Client?): borrowed transport, otherwise owned; sharedMedicationControl (CheckCaregiverMedication?): borrowed schedule reader; pollingInterval/idlePollingInterval (Duration): active/idle cadence; requestPermission (bool): allow permission prompt; monitorCompletionTransitions (bool): observe completion; monitorMissedDeadlines (bool): fetch local deliveries in disabled-auth mode, not client-side deadline detection; languageProvider (String Function()?): display locale; onCaregiverStatusChanged (ValueChanged<bool>?): active-link changes.
  // Returns: CaregiverNotificationMonitorService: configured, not yet started monitor.
  static CaregiverNotificationMonitorService create({
    required String caregiverHash,
    String baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    CheckCaregiverMedication? sharedMedicationControl,
    Duration pollingInterval =
        CaregiverNotificationMonitorService.defaultPollingInterval,
    Duration idlePollingInterval =
        CaregiverNotificationMonitorService.defaultIdlePollingInterval,
    bool requestPermission = true,
    bool monitorCompletionTransitions = true,
    bool monitorMissedDeadlines = true,
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
    final medicationControl = sharedMedicationControl ?? CheckCaregiverMedication(
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

    final deliveryClient = client ?? AuthenticatedApiClient();
    final actions = CaregiverAlertActionControl(
      userHash: caregiverHash, client: deliveryClient, baseUrl: baseUrl,
    );
    return CaregiverNotificationMonitorService(
      caregiverHash: caregiverHash,
      loadMonitoringSnapshots: () async {
        final snapshots = await medicationControl.requestMonitoringSnapshot();
        if (AuthConfig.mode == AuthenticationMode.disabled && monitorMissedDeadlines) {
          try {
            for (final alert in await actions.requestLocalDeliveries()) {
              await CaregiverAlertDeliveryService.display({
                ...alert.toData(), 'language': languageProvider?.call() ?? 'ko',
              });
            }
          } catch (error) {
            debugPrint('Local caregiver deliveries could not be loaded: $error');
          }
        }
        return snapshots;
      },
      loadLinks: linkControl.requestLinkScreen,
      loadSettings: /* 함수이름: loadSettings 콜백
       * 함수역할: 환자별 보호자 알림 모드와 지연 설정을 조회한다.
       * 매개변수:
       * - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
       * 반환값:
       * - 해당 환자의 알림 설정을 완료하는 Future.
       */(patientHash) {
        return settingControl.requestCaregiverNotificationSettings(
          patientHash: patientHash,
        );
      },
      loadSchedules: /* 함수이름: loadSchedules 콜백
       * 함수역할: 보호자 조회 응답에서 오늘의 복약 일정 목록을 추출한다.
       * 매개변수:
       * - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
       * 반환값:
       * - 오늘의 환자 복약 일정 목록을 완료하는 Future.
       */(patientHash) async {
        final info = await medicationControl.requestPatientMedicationInfo(
          patientHash: patientHash,
        );
        return info.todayMedicationScheduleList;
      },
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할: 보호자 알림 허용 여부를 확인한 뒤 민감정보 표시 정책과 현재 언어를 적용해 알림을 보낸다.
          // 매개변수:
          // - id (int): 플랫폼 알림의 예약·교체·취소 식별자
          // - title (String): 기기 알림에 표시할 제목
          // - body (String): 전송하거나 표시할 메시지·알림 본문
          // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
          // 반환값:
          // - 비활성화 확인 또는 알림 표시가 완료되는 Future.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {
            await deliverCaregiverAlert(
              loadSetting: userSettingControl.requestUserSetting,
              notify: (showSensitiveDetails) {
                NotificationService.instance.setShowSensitiveDetails(
                  showSensitiveDetails,
                );
                return NotificationService.instance.showCaregiverAlert(
                  historyUserHash: caregiverHash,
                  id: id,
                  title: title,
                  body: body,
                  patientHash: patientHash,
                  language: languageProvider?.call() ?? 'ko',
                );
              },
            );
          },
      permissionRequester: NotificationService.instance.requestPermission,
      pollingInterval: pollingInterval,
      idlePollingInterval: idlePollingInterval,
      requestPermission: requestPermission,
      monitorCompletionTransitions: monitorCompletionTransitions,
      // Missed deadlines are decided by the server in both live and demo modes.
      monitorMissedDeadlines: false,
      languageProvider: languageProvider,
      onCaregiverStatusChanged: onCaregiverStatusChanged,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 모니터 팩토리가 생성한 연결·설정·복약 조회 제어기의 자원을 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */() {
        linkControl.dispose();
        settingControl.dispose();
        if (sharedMedicationControl == null) medicationControl.dispose();
        userSettingControl.dispose();
        if (client == null) deliveryClient.close();
      },
    );
  }
}
