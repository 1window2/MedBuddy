import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_caregiver_link_entity.dart';
import '../services/caregiver_patient_local_state_service.dart';

// 파일명: manage_caregiver_patient_local_state_control.dart
// 역할: 보호자 화면의 환자 별칭과 연결 해제 후 로컬 정리를 조정한다.

// 클래스명: ManageCaregiverPatientLocalState
// 역할: UI가 SharedPreferences 구현을 직접 알지 않도록 로컬 상태 작업을 제공한다.
class ManageCaregiverPatientLocalState {
  const ManageCaregiverPatientLocalState();

  static const int maximumLabelLength =
      CaregiverPatientLocalStateService.maximumLabelLength;

  String fallbackLabel(String patientHash) {
    return CaregiverPatientLocalStateService.fallbackLabel(patientHash);
  }

  Future<String> loadLabel({
    required String caregiverHash,
    required String patientHash,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return CaregiverPatientLocalStateService.resolveLabel(
      preferences,
      caregiverHash: caregiverHash,
      patientHash: patientHash,
    );
  }

  Future<Map<String, String>> loadLabels({
    required String caregiverHash,
    required List<PatientCaregiverLink> links,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final labels = <String, String>{};
    for (final link in links) {
      if (link.caregiverHash != caregiverHash) {
        continue;
      }
      final serverAlias = link.patientAlias;
      if (serverAlias != null) {
        // NULL은 서버 별칭 도입 전의 기존 행이므로 기기 별칭을 보존한다.
        // 빈 문자열은 사용자가 다른 기기에서 별칭을 지운 상태이므로 캐시도 비운다.
        await CaregiverPatientLocalStateService.saveLabel(
          preferences,
          caregiverHash: caregiverHash,
          patientHash: link.patientHash,
          label: serverAlias,
        );
      }
      labels[link.patientHash] = CaregiverPatientLocalStateService.resolveLabel(
        preferences,
        caregiverHash: caregiverHash,
        patientHash: link.patientHash,
      );
    }
    return labels;
  }

  Future<String> saveLabel({
    required String caregiverHash,
    required String patientHash,
    required String label,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: caregiverHash,
      patientHash: patientHash,
      label: label,
    );
  }

  Future<void> clearPatientState({
    required String caregiverHash,
    required String patientHash,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await CaregiverPatientLocalStateService.clearPatientState(
      preferences,
      caregiverHash: caregiverHash,
      patientHash: patientHash,
    );
  }
}
