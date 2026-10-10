// 파일명: medication_reminder_refresh_factory.dart
// 역할: 복약 알림 갱신 서비스가 쓰는 설정·일정 Control과 로컬 알림 의존성을 조립한다.

import 'package:http/http.dart' as http;

import '../controls/check_schedule_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/dose_outbox_store.dart';
import '../services/medication_reminder_background_service.dart';
import '../services/notification_service.dart';

// 클래스명: MedicationReminderRefreshFactory
// 역할: 서비스 계층이 Control을 직접 만들지 않도록 실제 의존성을 가진 갱신 서비스를 조립한다.
// 주요 책임:
// - 환자 범위의 알림 설정·일정·사용자 설정 Control을 만들어 갱신 서비스의 읽기 함수로 넘긴다.
// - 갱신 서비스가 해제될 때 만든 Control을 함께 해제한다.
class MedicationReminderRefreshFactory {
  // 함수이름: create
  // 함수역할: 환자 범위의 설정·일정 Control을 만들고 로컬 알림 예약·취소 및 민감정보 정책과 함께 갱신 서비스를 구성한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - baseUrl (String): 복약 API 기본 주소
  // - client (http.Client?): 요청에 사용할 HTTP 클라이언트; 주입한 쪽이 닫는다.
  // - notificationService (NotificationService?): 플랫폼 로컬 알림 서비스
  // - openDoseStore (Future<DoseOutboxStore> Function()?): 기기의 복용 전송 대기 저장소를 여는 함수; 생략하면 앱과 공유하는 저장소
  // 반환값:
  // - MedicationReminderRefreshService: 초기화된 인스턴스.
  static MedicationReminderRefreshService create({
    required String patientHash,
    String baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    NotificationService? notificationService,
    Future<DoseOutboxStore> Function()? openDoseStore,
  }) {
    final normalizedPatientHash = PatientHash.normalizePatientHash(patientHash);
    final alarmControl = SetNotification(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: client,
    );
    final scheduleControl = CheckSchedule(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: client,
    );
    final userSettingControl = ManageUserSetting(
      baseUrl: baseUrl,
      userHash: normalizedPatientHash,
      client: client,
      useRemotePersistence: false,
    );
    final resolvedNotificationService =
        notificationService ?? NotificationService.instance;
    resolvedNotificationService.setHistoryUser(normalizedPatientHash, persistSession: false);
    return MedicationReminderRefreshService(
      loadSettings: alarmControl.requestMedicationAlarm,
      loadSchedules: scheduleControl.requestMedicationScheduleWindow,
      loadTodaySchedules: scheduleControl.requestTodayMedicationSchedule,
      loadPendingDoses: /* 함수이름: loadPendingDoses 콜백
       * 함수역할: 오프라인에서 기록해 아직 서버에 없는 이 환자의 복용 기록을 기기 저장소에서 읽는다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 전송 대기 중인 복용 기록 목록.
       */() async =>
          (await (openDoseStore ?? DoseOutboxStore.open)()).pending(
            normalizedPatientHash,
          ),
      loadUserSetting: userSettingControl.requestUserSetting,
      registerReminder: resolvedNotificationService.registerNotification,
      cancelReminder: resolvedNotificationService.cancelReminder,
      setPrivacy: resolvedNotificationService.setShowSensitiveDetails,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 갱신 서비스가 생성한 알림·일정·사용자 설정 제어기를 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */() {
        alarmControl.dispose();
        scheduleControl.dispose();
        userSettingControl.dispose();
      },
    );
  }
}
