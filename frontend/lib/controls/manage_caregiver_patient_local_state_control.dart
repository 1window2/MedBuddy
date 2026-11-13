import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_caregiver_link_entity.dart';
import '../services/caregiver_patient_local_state_service.dart';

// 파일명: manage_caregiver_patient_local_state_control.dart
// 역할: 보호자 화면의 환자 별칭과 연결 해제 후 로컬 정리를 조정한다.

// Class Name: ManageCaregiverPatientLocalState
// Role: Coordinate caregiver-scoped patient labels and local unlink cleanup.
// Responsibilities: Delegate storage normalization and synchronize server aliases into local display labels.
// Attributes: maximumLabelLength (int): service label limit; no per-instance state.
class ManageCaregiverPatientLocalState {
  // 함수이름: ManageCaregiverPatientLocalState
  // 함수역할: 보호자별 환자 별칭 조회·저장·연동 해제 정리를 위임하는 무상태 Control을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - ManageCaregiverPatientLocalState: 초기화된 인스턴스.
  const ManageCaregiverPatientLocalState();

  static const int maximumLabelLength =
      CaregiverPatientLocalStateService.maximumLabelLength;

  // Function Name: fallbackLabel
  // Description: Build a localized patient-hash label when no alias is available.
  // Parameters: patientHash (String): patient identity; isEnglish (bool): English instead of Korean fallback.
  // Returns: String: default patient label.
  String fallbackLabel(String patientHash, {bool isEnglish = false}) {
    return CaregiverPatientLocalStateService.fallbackLabel(
      patientHash,
      isEnglish: isEnglish,
    );
  }

  // Function Name: loadLabel
  // Description: Read the local alias for one caregiver-patient pair, falling back to a localized hash label.
  // Parameters: caregiverHash/patientHash (String): storage scope; isEnglish (bool): fallback language.
  // Returns: Future<String>: resolved display label; preference access failures propagate.
  Future<String> loadLabel({
    required String caregiverHash,
    required String patientHash,
    bool isEnglish = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return CaregiverPatientLocalStateService.resolveLabel(
      preferences,
      caregiverHash: caregiverHash,
      patientHash: patientHash,
      isEnglish: isEnglish,
    );
  }

  // Function Name: loadLabels
  // Description: Synchronize aliases for this caregiver's links; preserve legacy null aliases and clear locally cached aliases when the server sends an empty string.
  // Parameters: caregiverHash (String): current caregiver; links (List<PatientCaregiverLink>): server links; isEnglish (bool): fallback language.
  // Returns: Future<Map<String, String>>: labels keyed by patient hash.
  Future<Map<String, String>> loadLabels({
    required String caregiverHash,
    required List<PatientCaregiverLink> links,
    bool isEnglish = false,
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
        // 서비스는 저장된 값과 같으면 쓰지 않으므로 주기적 호출이 저장소를 다시 쓰지 않는다.
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
        isEnglish: isEnglish,
      );
    }
    return labels;
  }

  // Function Name: saveLabel
  // Description: Normalize and persist an alias, or remove it when blank, through the local-state service.
  // Parameters: caregiverHash/patientHash (String): storage scope; label (String): requested alias; isEnglish (bool): reset-label language.
  // Returns: Future<String>: resulting display label.
  Future<String> saveLabel({
    required String caregiverHash,
    required String patientHash,
    required String label,
    bool isEnglish = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: caregiverHash,
      patientHash: patientHash,
      label: label,
      isEnglish: isEnglish,
    );
  }

  // 함수이름: clearPatientState
  // 함수역할: 연결 해제한 보호자·환자 쌍의 별칭과 알림 감시 로컬 기록을 정리한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
