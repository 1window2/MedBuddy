// 파일명: caregiver_notification_monitor_factory.dart
// 역할: 보호자별 복약 감시에 필요한 HTTP Control과 로컬 알림 서비스를 조립한다.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../controls/check_caregiver_medication_control.dart';
import '../controls/link_patient_caregiver_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_caregiver_notification_control.dart';
import '../services/api_config.dart';
import '../services/caregiver_notification_monitor_service.dart';
import '../services/notification_service.dart';



// 클래스명: CaregiverNotificationMonitorFactory
// 역할: 보호자 복약 감시의 의존성 조립 경계이다.
// 주요 책임:
// - 환자 연동·설정·일정 조회와 개인정보 표시 설정을 감시 서비스에 연결하고 소유 자원을 정리한다.
class CaregiverNotificationMonitorFactory {
  // 함수이름: CaregiverNotificationMonitorFactory._
  // 함수역할: 보호자 감시 조립을 정적 create 진입점으로만 제공하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - CaregiverNotificationMonitorFactory: 초기화된 인스턴스.
  const CaregiverNotificationMonitorFactory._();

  // 함수이름: create
  // 함수역할: 보호자별 조회 Control을 만들고 알림 허용·민감정보 설정을 확인하는 전송 콜백과 함께 감시 서비스를 구성한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - baseUrl (String): 복약 API 기본 주소
  // - client (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - pollingInterval (Duration): 활성 보호자 연동이 있을 때 확인 간격
  // - idlePollingInterval (Duration): 활성 보호자 연동이 없을 때의 확인 간격
  // - requestPermission (bool): 감시 중 운영체제 권한 요청을 수행할지 여부
  // - monitorCompletionTransitions (bool): 미완료에서 전체 완료로 바뀐 순간을 감시할지 여부
  // - languageProvider (String Function()?): 알림 생성 시점의 언어 조회 경계
  // - onCaregiverStatusChanged (ValueChanged<bool>?): 활성 보호자 연동 존재 여부 변경 수신자
  // 반환값:
  // - CaregiverNotificationMonitorService: 보호자별 조회 Control을 만들고 알림 허용·민감정보 설정을 확인하는 전송 콜백과 함께 감시 서비스를 구성한다.
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
      loadMonitoringSnapshots: medicationControl.requestMonitoringSnapshot,
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
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 모니터 팩토리가 생성한 연결·설정·복약 조회 제어기의 자원을 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */() {
        linkControl.dispose();
        settingControl.dispose();
        medicationControl.dispose();
        userSettingControl.dispose();
      },
    );
  }
}
