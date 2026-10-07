// 파일명: caregiver_monitoring_snapshot_entity.dart
// 역할: 보호자 통합 알림 조회에서 환자 한 명의 연동, 설정, 일정을 표현한다.

import 'caregiver_notification_entity.dart';
import 'medication_schedule_entity.dart';
import 'patient_caregiver_link_entity.dart';

// 클래스명: CaregiverMonitoringSnapshot
// 역할: 환자 한 명의 연동, 알림 설정과 오늘 일정을 묶은 통합 조회 결과이다.
// 주요 책임:
// - 감시 서비스가 원시 HTTP 구조를 해석하지 않고 환자별 조건과 일정을 함께 확인하게 한다.
// 속성:
// - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
// - notificationSettings (Map<String, CaregiverNotification>): 시간대 키로 조회할 보호자 알림 설정
// - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
class CaregiverMonitoringSnapshot {
  final PatientCaregiverLink link;
  final Map<String, CaregiverNotification> notificationSettings;
  final List<MedicationSchedule> schedules;

  // 함수이름: CaregiverMonitoringSnapshot
  // 함수역할: 환자 연동, 시간대별 알림 설정과 오늘 일정을 동일한 조회 시점의 자료로 묶는다.
  // 매개변수:
  // - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
  // - notificationSettings (Map<String, CaregiverNotification>): 시간대 키로 조회할 보호자 알림 설정
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // 반환값:
  // - CaregiverMonitoringSnapshot: 초기화된 인스턴스.
  const CaregiverMonitoringSnapshot({
    required this.link,
    required this.notificationSettings,
    required this.schedules,
  });

  // 함수이름: patientHash
  // 함수역할: 통합 감시 자료에 연결된 환자 해시를 연동 모델에서 읽는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 통합 감시 자료에 연결된 환자 해시를 연동 모델에서 읽는다.
  String get patientHash => link.patientHash;

  // 함수이름: patientAlias
  // 함수역할: 보호자가 지정한 환자 표시 이름을 연동 모델에서 읽고 미설정 상태는 null로 보존한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String?: 보호자가 지정한 환자 표시 이름을 연동 모델에서 읽고 미설정 상태는 null로 보존한다.
  String? get patientAlias => link.patientAlias;

  // 함수이름: CaregiverMonitoringSnapshot.fromJson
  // 함수역할: 중첩 또는 평면 연동 응답을 지원하고 환자 해시·별칭을 보완한 뒤 시간대 설정과 오늘 일정을 함께 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - CaregiverMonitoringSnapshot: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
  factory CaregiverMonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLink = json['link'];
    final linkData = rawLink is Map
        ? Map<String, dynamic>.from(rawLink)
        : Map<String, dynamic>.from(json);
    final rawPatientHash =
        json['patient_hash'] ?? json['patientHash'] ?? linkData['patient_hash'];
    linkData.putIfAbsent('patient_hash', /* 함수이름: putIfAbsent 콜백
     * 함수역할: 연결 응답에서 환자 해시가 빠졌을 때 스냅샷의 환자 해시를 보충한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 스냅샷에 제공된 환자 해시.
     */() => rawPatientHash);
    if (!linkData.containsKey('patient_alias') &&
        json.containsKey('patient_alias')) {
      linkData['patient_alias'] = json['patient_alias'];
    }

    final settings = <String, CaregiverNotification>{};
    final rawSettings = json['notification_settings'];
    if (rawSettings is List) {
      for (final rawSetting in rawSettings.whereType<Map>()) {
        final setting = CaregiverNotification.fromJson(
          Map<String, dynamic>.from(rawSetting),
        );
        settings[setting.slotKey] = setting;
      }
    }

    return CaregiverMonitoringSnapshot(
      link: PatientCaregiverLink.fromJson(linkData),
      notificationSettings: Map.unmodifiable(settings),
      schedules: MedicationSchedule.fromScheduleJsonList(
        json['today_medication_info'],
      ),
    );
  }
}
