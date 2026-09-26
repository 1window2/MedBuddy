import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';

// 파일명: caregiver_patient_local_state_service.dart
// 역할: 서버 환자 별칭의 오프라인 캐시와 알림 중복 방지 상태를 관리한다.

// 클래스명: CaregiverPatientLocalStateService
// 역할: 한 보호자와 연결된 여러 환자의 기기 캐시가 서로 섞이지 않게 분리한다.
// 주요 책임:
// - 서버에서 받은 환자 표시 이름을 오프라인 확인용으로 환자별 저장한다.
// - 별칭이 없으면 개인식별정보 노출을 줄인 짧은 환자 식별명을 만든다.
// - 연결이 해제된 환자의 알림 스냅샷과 표시 이름을 정리한다.
class CaregiverPatientLocalStateService {
  // 함수이름: CaregiverPatientLocalStateService._
  // 함수역할: 환자별 별칭·숨김·알림 기록의 정적 저장 API만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - CaregiverPatientLocalStateService: 초기화된 인스턴스.
  CaregiverPatientLocalStateService._();

  static const String _labelPrefix = 'caregiver_patient_label';
  static const String _linkedPatientsPrefix = 'caregiver_linked_patients';
  static const String _alertPrefix = 'caregiver_alert';
  static const int maximumLabelLength = 20;

  // 함수이름: resolveLabel
  // 함수역할: 저장된 환자 별칭을 읽고 없으면 짧은 식별명을 반환한다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 기기의 로컬 저장소
  // - caregiverHash (String): 현재 보호자 식별 hash
  // - patientHash (String): 표시할 환자 식별 hash
  // 반환값:
  // - 보호자 화면과 알림에 사용할 환자 표시 이름
  static String resolveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) {
    final savedLabel = preferences
        .getString(_labelKey(caregiverHash, patientHash))
        ?.trim();
    if (savedLabel != null && savedLabel.isNotEmpty) {
      return savedLabel;
    }
    return fallbackLabel(patientHash);
  }

  // 함수이름: resolveSavedLabel
  // 함수역할: 보호자가 직접 저장한 환자 별칭만 반환한다. 별칭이 없을 때 환자 hash 일부를 알림 문구에 노출하지 않도록 null을 반환한다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 기기의 로컬 저장소
  // - caregiverHash (String): 현재 보호자 식별 hash
  // - patientHash (String): 별칭을 조회할 환자 식별 hash
  // 반환값:
  // - 저장된 별칭 또는 null
  static String? resolveSavedLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) {
    final savedLabel = preferences
        .getString(_labelKey(caregiverHash, patientHash))
        ?.trim();
    return savedLabel == null || savedLabel.isEmpty ? null : savedLabel;
  }

  // 함수이름: fallbackLabel
  // 함수역할: 환자 hash 전체를 노출하지 않고 마지막 네 글자로 기본 식별명을 만든다.
  // 매개변수:
  // - patientHash (String): 환자 식별 hash
  // 반환값:
  // - 환자 ABCD 형식의 기본 표시 이름
  static String fallbackLabel(String patientHash) {
    final normalized = patientHash.trim();
    if (normalized.isEmpty) {
      return '연결된 환자';
    }
    final suffix = normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
    return '환자 ${suffix.toUpperCase()}';
  }

  // 함수이름: saveLabel
  // 함수역할: 보호자가 입력한 환자 별칭을 정리해 환자별 키로 저장한다. 빈 값을 저장하면 사용자 별칭을 제거하고 기본 식별명으로 되돌린다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 기기의 로컬 저장소
  // - caregiverHash (String): 현재 보호자 식별 hash
  // - patientHash (String): 별칭을 지정할 환자 식별 hash
  // - label (String): 보호자가 입력한 표시 이름
  // 반환값:
  // - 저장 후 실제 화면에 표시할 이름
  static Future<String> saveLabel(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
    required String label,
  }) async {
    final normalizedLabel = label
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final key = _labelKey(caregiverHash, patientHash);
    if (normalizedLabel.isEmpty) {
      await preferences.remove(key);
      return fallbackLabel(patientHash);
    }
    final boundedLabel = normalizedLabel.length <= maximumLabelLength
        ? normalizedLabel
        : normalizedLabel.substring(0, maximumLabelLength);
    await preferences.setString(key, boundedLabel);
    return boundedLabel;
  }

  // 함수이름: synchronizeLinkedPatients
  // 함수역할: 직전 연동 목록과 현재 목록을 비교해 해제된 환자의 로컬 상태를 정리한다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 기기의 로컬 저장소
  // - caregiverHash (String): 현재 보호자 식별 hash
  // - patientHashes (Iterable<String>): 서버가 반환한 현재 활성 환자 hash 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  static Future<void> synchronizeLinkedPatients(
    SharedPreferences preferences, {
    required String caregiverHash,
    required Iterable<String> patientHashes,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final currentPatients = patientHashes
        .map(PatientHash.normalizePatientHash)
        .where(/* 함수이름: where 콜백
         * 함수역할: 숨긴 환자 목록에서 빈 해시를 제외한다.
         * 매개변수:
         * - hash (String): 저장된 숨김 환자 해시
         * 반환값:
         * - 환자 해시가 비어 있지 않으면 true.
         */(hash) => hash.isNotEmpty)
        .toSet();
    final linkedPatientsKey = '$_linkedPatientsPrefix.$normalizedCaregiver';
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

  // 함수이름: clearPatientState
  // 함수역할: 연결 해제된 환자의 별칭과 알림 중복 방지 상태를 모두 제거한다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 기기의 로컬 저장소
  // - caregiverHash (String): 현재 보호자 식별 hash
  // - patientHash (String): 정리할 환자 식별 hash
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  static Future<void> clearPatientState(
    SharedPreferences preferences, {
    required String caregiverHash,
    required String patientHash,
  }) async {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    final labelKey = _labelKey(normalizedCaregiver, normalizedPatient);
    final alertPrefix =
        '$_alertPrefix.$normalizedCaregiver.$normalizedPatient.';
    final keysToRemove = preferences
        .getKeys()
        .where(/* 함수이름: where 콜백
         * 함수역할: 선택한 환자의 표시 이름 키와 알림 재확인 키만 정리 대상으로 선택한다.
         * 매개변수:
         * - key (String): Flutter 위젯의 동일성 키
         * 반환값:
         * - 해당 환자의 이름 또는 알림 기록 키이면 true.
         */(key) => key == labelKey || key.startsWith(alertPrefix))
        .toList(growable: false);
    for (final key in keysToRemove) {
      await preferences.remove(key);
    }
  }

  // 함수이름: _labelKey
  // 함수역할: 정규화한 보호자·환자 해시를 결합해 해당 관계의 표시 별칭 전용 저장 키를 만든다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - String: 정규화한 보호자·환자 해시를 결합해 해당 관계의 표시 별칭 전용 저장 키를 만든다.
  static String _labelKey(String caregiverHash, String patientHash) {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    final normalizedPatient = PatientHash.normalizePatientHash(patientHash);
    return '$_labelPrefix.$normalizedCaregiver.$normalizedPatient';
  }
}
