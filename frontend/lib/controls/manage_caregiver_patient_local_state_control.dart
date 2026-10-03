import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_caregiver_link_entity.dart';
import '../services/caregiver_patient_local_state_service.dart';

// 파일명: manage_caregiver_patient_local_state_control.dart
// 역할: 보호자 화면의 환자 별칭과 연결 해제 후 로컬 정리를 조정한다.

// 클래스명: ManageCaregiverPatientLocalState
// 역할: 보호자 화면의 환자 별칭과 연동 해제 후 로컬 정리를 제공한다.
// 주요 책임:
// - 저장소 접근을 서비스에 위임하고 서버 별칭을 환자별 로컬 표시 이름에 반영한다.
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

  // 함수이름: fallbackLabel
  // 함수역할: 저장된 별칭이 없을 때 사용할 환자 해시 기반의 기본 표시 이름을 구한다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - String: 저장된 별칭이 없을 때 사용할 환자 해시 기반의 기본 표시 이름을 구한다.
  String fallbackLabel(String patientHash) {
    return CaregiverPatientLocalStateService.fallbackLabel(patientHash);
  }

  // 함수이름: loadLabel
  // 함수역할: 현재 보호자·환자 쌍의 로컬 별칭을 읽고 없으면 기본 표시 이름을 사용한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - Future<String>: 현재 보호자·환자 쌍의 로컬 별칭을 읽고 없으면 기본 표시 이름을 사용한다.
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

  // 함수이름: loadLabels
  // 함수역할: 현재 보호자의 연동만 처리하고 서버 별칭을 로컬 저장소에 반영한 뒤 환자 해시별 표시 이름을 모은다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - links (List<PatientCaregiverLink>): 참여자·활성 상태를 확인할 환자·보호자 연동 목록
  // 반환값:
  // - Future<Map<String, String>>: 현재 보호자의 연동만 처리하고 서버 별칭을 로컬 저장소에 반영한 뒤 환자 해시별 표시 이름을 모은다.
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

  // 함수이름: saveLabel
  // 함수역할: 보호자·환자 쌍의 표시 이름을 정규화하여 기기에 저장하고 실제 표시할 이름을 구한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - label (String): 보호자가 지정한 환자 표시 이름
  // 반환값:
  // - Future<String>: 보호자·환자 쌍의 표시 이름을 정규화하여 기기에 저장하고 실제 표시할 이름을 구한다.
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
