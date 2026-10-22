// 파일명: medication_reminder_refresh_factory.dart
// 역할: 복약 알림 갱신 서비스가 쓰는 설정·일정 Control과 로컬 알림 의존성을 조립한다.

import 'package:http/http.dart' as http;

import '../controls/check_schedule_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../controls/set_notification_control.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/dose_outbox_store.dart';
import '../services/dose_sync_service.dart';
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
  // - now (DateTime Function()?): 조회와 알림이 공유하는 현재 시각
  // 반환값:
  // - MedicationReminderRefreshService: 초기화된 인스턴스.
  static MedicationReminderRefreshService create({
    required String patientHash,
    String baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    NotificationService? notificationService,
    Future<DoseOutboxStore> Function()? openDoseStore,
    DateTime Function()? now,
  }) {
    final normalizedPatientHash = PatientHash.normalizePatientHash(patientHash);
    final resolvedClient = client ?? AuthenticatedApiClient();
    final clock = now ?? DateTime.now;
    final alarmControl = SetNotification(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: resolvedClient,
    );
    final scheduleControl = CheckSchedule(
      baseUrl: baseUrl,
      patientHash: normalizedPatientHash,
      client: resolvedClient,
    );
    final userSettingControl = ManageUserSetting(
      baseUrl: baseUrl,
      userHash: normalizedPatientHash,
      client: resolvedClient,
      useRemotePersistence: false,
    );
    final doseSync = DoseSyncService(
      owner: normalizedPatientHash,
      client: resolvedClient,
      openStore: openDoseStore,
      clock: clock,
      // 오늘 일정을 저장하면 기기의 14일 일정이 교체되므로, 같은 작업에서 새 기간을 받아 둔다.
      // 없으면 자정 뒤 오프라인에서 기록할 일정이 사라진다.
      loadScheduleWindow: () => scheduleControl.requestOfflineScheduleWindow(
        expectedStartDay: doseScheduleDay(clock()),
      ),
    );
    final resolvedNotificationService =
        notificationService ?? NotificationService.instance;
    resolvedNotificationService.setHistoryUser(
      normalizedPatientHash,
      persistSession: false,
    );
    return MedicationReminderRefreshService(
      loadSettings: alarmControl.requestMedicationAlarm,
      loadSchedules: scheduleControl.requestMedicationScheduleWindow,
      loadTodaySchedules: () async {
        // 전송이나 계정 활성화 없이 서버 일정에 같은 날의 영속 대기 기록을 겹쳐 읽는다.
        final requestDay = doseScheduleDay(clock());
        final revision = await doseSync.cacheRevision();
        final schedules = await scheduleControl
            .requestTodayMedicationSchedule();
        await doseSync.cacheSchedules(
          schedules,
          scheduleDate: requestDay,
          expectedRevision: revision,
          awaitScheduleWindow: true,
        );
        // 조회 중 전송이 끝났으면 최신 수신 결과를 쓰고, 읽는 도중 다시 바뀌면 재시도한다.
        final projectedRevision = await doseSync.cacheRevision();
        await doseSync.reload();
        if (await doseSync.cacheRevision() != projectedRevision ||
            doseScheduleDay(clock()) != requestDay ||
            !doseSync.hasCache) {
          throw StateError('The medication schedule changed during refresh.');
        }
        return doseSync.schedules;
      },
      loadUserSetting: userSettingControl.requestUserSetting,
      registerReminder: resolvedNotificationService.registerNotification,
      cancelReminder: resolvedNotificationService.cancelReminder,
      setPrivacy: resolvedNotificationService.setShowSensitiveDetails,
      now: clock,
      onDispose: /* 함수이름: onDispose 콜백
       * 함수역할: 갱신 서비스가 생성한 알림·일정·사용자 설정 제어기를 해제한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 없음.
       */ () {
        alarmControl.dispose();
        scheduleControl.dispose();
        userSettingControl.dispose();
        doseSync.dispose();
        if (client == null) resolvedClient.close();
      },
    );
  }
}
