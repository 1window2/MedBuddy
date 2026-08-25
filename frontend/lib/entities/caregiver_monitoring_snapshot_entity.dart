// 파일명: caregiver_monitoring_snapshot_entity.dart
// 역할: 보호자 통합 알림 조회에서 환자 한 명의 연동, 설정, 일정을 표현한다.

import 'caregiver_notification_entity.dart';
import 'medication_schedule_entity.dart';
import 'patient_caregiver_link_entity.dart';

// 클래스명: CaregiverMonitoringSnapshot
// 역할:
// - 서버가 한 번에 반환한 환자별 알림 설정과 오늘 복약 일정을 묶어 보관한다.
// - 감시 서비스가 HTTP 응답 구조를 직접 해석하지 않게 한다.
class CaregiverMonitoringSnapshot {
  final PatientCaregiverLink link;
  final Map<String, CaregiverNotification> notificationSettings;
  final List<MedicationSchedule> schedules;

  const CaregiverMonitoringSnapshot({
    required this.link,
    required this.notificationSettings,
    required this.schedules,
  });

  String get patientHash => link.patientHash;

  String? get patientAlias => link.patientAlias;

  factory CaregiverMonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLink = json['link'];
    final linkData = rawLink is Map
        ? Map<String, dynamic>.from(rawLink)
        : Map<String, dynamic>.from(json);
    final rawPatientHash =
        json['patient_hash'] ?? json['patientHash'] ?? linkData['patient_hash'];
    linkData.putIfAbsent('patient_hash', () => rawPatientHash);
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
