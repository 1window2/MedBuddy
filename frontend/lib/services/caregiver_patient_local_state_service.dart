import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';

// 파일명: caregiver_patient_local_state_service.dart
// 역할: 서버 환자 별칭의 오프라인 캐시와 알림 중복 방지 상태를 관리한다.

// Class Name: CaregiverPatientLocalStateService
// Role: Persist caregiver-scoped patient aliases and alert-state cleanup.
// Responsibilities: Normalize labels, reconcile linked patients and remove state for detached patients.
// Attributes: patientLabelKeyPrefix/linkedPatientsKeyPrefix/alertKeyPrefix (String): storage namespaces; maximumLabelLength (int): 20-code-unit alias limit.
class CaregiverPatientLocalStateService {
  // 함수이름: CaregiverPatientLocalStateService._
  // 함수역할: 환자별 별칭·숨김·알림 기록의 정적 저장 API만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - CaregiverPatientLocalStateService: 초기화된 인스턴스.
  CaregiverPatientLocalStateService._();

  // 보호자 기기 저장소의 키 접두어. 뒤에 보호자 해시가 이어지며, 계정 정리와 알림 감시도 같은 값을 쓴다.
  static const String patientLabelKeyPrefix = 'caregiver_patient_label.';
  static const String linkedPatientsKeyPrefix = 'caregiver_linked_patients.';
  static const String alertKeyPrefix = 'caregiver_alert.';
  static const int maximumLabelLength = 20;

  // Function Name: resolveLabel
  // Description: Read a nonblank cached alias or derive a localized patient label.
  // Parameters: preferences (SharedPreferences): storage; caregiverHash/patientHash (String): identity scope; isEnglish (bool): fallback language.
  // Returns: String: trimmed alias or fallback label.
  static String resolveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
    bool isEnglish = false,
  }) {
    final savedLabel = preferences
        .getString(_labelKey(caregiverHash, patientHash))
        ?.trim();
    if (savedLabel != null && savedLabel.isNotEmpty) {
      return savedLabel;
    }
    return fallbackLabel(patientHash, isEnglish: isEnglish);
  }

  // Function Name: fallbackLabel
  // Description: Build a patient label using the uppercase final four hash characters; use a generic linked-patient label for a blank hash.
  // Parameters: patientHash (String): patient identity; isEnglish (bool): English instead of Korean.
  // Returns: String: fallback label.
  static String fallbackLabel(String patientHash, {bool isEnglish = false}) {
    final normalized = patientHash.trim();
    if (normalized.isEmpty) {
      return isEnglish ? 'Linked patient' : '연동된 환자';
    }
    final suffix = normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
    return '${isEnglish ? 'Patient' : '환자'} ${suffix.toUpperCase()}';
  }

  // Function Name: saveLabel
  // Description: Collapse whitespace and cap aliases at the length limit; blank input removes the alias and unchanged input avoids a write.
  // Parameters: preferences (SharedPreferences): storage; caregiverHash/patientHash (String): scope; label (String): requested alias; isEnglish (bool): reset-label language.
  // Returns: Future<String>: persisted bounded alias or localized fallback.
  static Future<String> saveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
    required String label,
    bool isEnglish = false,
  }) async {
    final normalizedLabel = label
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final key = _labelKey(caregiverHash, patientHash);
    if (normalizedLabel.isEmpty) {
      if (preferences.containsKey(key)) {
        await preferences.remove(key);
      }
      return fallbackLabel(patientHash, isEnglish: isEnglish);
    }
    final boundedLabel = normalizedLabel.length <= maximumLabelLength
        ? normalizedLabel
        : normalizedLabel.substring(0, maximumLabelLength);
    // 채팅 목록과 알림 감시가 주기적으로 서버 별칭을 다시 반영하므로 값이 같으면 쓰지 않는다.
    if (preferences.getString(key) != boundedLabel) {
      await preferences.setString(key, boundedLabel);
    }
    return boundedLabel;
  }

  // Function Name: synchronizeLinkedPatients
  // Description: Normalize the current patient set, remove state for previously linked patients that disappeared, and save the sorted set.
  // Parameters: preferences (SharedPreferences): storage; caregiverHash (String): owner; patientHashes (Iterable<String>): current links.
  // Returns: Future<void>: reconciliation completion; storage errors propagate.
  static Future<void> synchronizeLinkedPatients(
    SharedPreferences preferences, {
    required String caregiverHash,
    required Iterable<String> patientHashes,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final currentPatients = patientHashes
        .map(PatientHash.normalizePatientHash)
        .toSet();
    final linkedPatientsKey = '$linkedPatientsKeyPrefix$normalizedCaregiver';
    final previousPatients = preferences.getStringList(linkedPatientsKey);
    if (previousPatients != null) {
      final removedPatients = previousPatients.toSet().difference(
        currentPatients,
      );
      for (final patientHash in removedPatients) {
        await clearPatientState(
          preferences,
          caregiverHash: normalizedCaregiver,
          patientHash: patientHash,
        );
      }
    }
    final sortedPatients = currentPatients.toList(growable: false)..sort();
    await preferences.setStringList(linkedPatientsKey, sortedPatients);
  }

  // Function Name: clearPatientState
  // Description: Remove only the selected caregiver-patient alias and alert-state keys.
  // Parameters: preferences (SharedPreferences): storage; caregiverHash/patientHash (String): normalized cleanup scope.
  // Returns: Future<void>: selected-key removal completion.
  static Future<void> clearPatientState(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    final labelKey = _labelKey(normalizedCaregiver, normalizedPatient);
    final alertPrefix =
        '$alertKeyPrefix$normalizedCaregiver.$normalizedPatient.';
    final keysToRemove = preferences
        .getKeys()
        .where(/* 함수이름: where 콜백
         * 함수역할: 선택한 환자의 표시 이름 키와 알림 재확인 키만 정리 대상으로 선택한다.
         * 매개변수:
         * - key (String): 검사할 SharedPreferences 저장 키
         * 반환값:
         * - 해당 환자의 이름 또는 알림 기록 키이면 true.
         */(key) => key == labelKey || key.startsWith(alertPrefix))
        .toList(growable: false);
    for (final key in keysToRemove) {
      await preferences.remove(key);
    }
  }

  // Function Name: _labelKey
  // Description: Build a patient-label key from normalized participant identities.
  // Parameters: caregiverHash/patientHash (String): participant identities.
  // Returns: String: pair-scoped preference key.
  static String _labelKey(String caregiverHash, String patientHash) {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    return '$patientLabelKeyPrefix$normalizedCaregiver.$normalizedPatient';
  }
}
