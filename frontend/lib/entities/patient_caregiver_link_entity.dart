// File Name: patient_caregiver_link_entity.dart
// Role: Defines expiring patient link codes and immutable patient-caregiver relationships.

// Class Name: PatientLinkCode
// Role: Holds a temporary patient registration code and its expiry.
// Responsibilities:
// - Validate required response fields and expose expiry and remaining lifetime for the pairing screen.
// Attributes:
// - code (String): Temporary registration code for patient pairing.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - expiresAt (DateTime): Absolute expiry timestamp of the pairing code.
class PatientLinkCode {
  final String code;
  final String patientHash;
  final DateTime expiresAt;

  // Function Name: PatientLinkCode
  // Description: Captures the generated pairing code, its patient scope, and absolute expiry timestamp.
  // Parameters:
  // - code (String): Temporary registration code for patient pairing.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - expiresAt (DateTime): Absolute expiry timestamp of the pairing code.
  // Returns:
  // - PatientLinkCode: the initialized instance.
  const PatientLinkCode({
    required this.code,
    required this.patientHash,
    required this.expiresAt,
  });

  // Function Name: PatientLinkCode.fromJson
  // Description: Requires a nonblank pairing code, patient hash, and parseable expiry while accepting current and legacy key spellings.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - PatientLinkCode: the decoded record after field validation and default handling.
  factory PatientLinkCode.fromJson(Map<String, dynamic> json) {
    final code = _readString(json['patient_code'] ?? json['code']);
    final patientHash = _readString(
      json['patient_hash'] ?? json['patientHash'],
    );
    final expiresAt = DateTime.tryParse(
      _readString(json['expires_at'] ?? json['expiresAt']),
    );
    if (code.isEmpty || patientHash.isEmpty || expiresAt == null) {
      throw const FormatException(
        'Patient link code response is missing required fields.',
      );
    }
    return PatientLinkCode(
      code: code,
      patientHash: patientHash,
      expiresAt: expiresAt,
    );
  }

  // Function Name: isExpired
  // Description: Reports expiry at or before the supplied clock, using the current time when no clock is injected.
  // Parameters:
  // - now (DateTime?): Reference timestamp for comparisons and calendar calculations.
  // Returns:
  // - bool: Reports expiry at or before the supplied clock, using the current time when no clock is injected.
  bool isExpired([DateTime? now]) {
    return !expiresAt.isAfter(now ?? DateTime.now());
  }

  // Function Name: remaining
  // Description: Computes time until code expiry and clamps already expired codes to a zero duration.
  // Parameters:
  // - now (DateTime?): Reference timestamp for comparisons and calendar calculations.
  // Returns:
  // - Duration: Computes time until code expiry and clamps already expired codes to a zero duration.
  Duration remaining([DateTime? now]) {
    final duration = expiresAt.difference(now ?? DateTime.now());
    return duration.isNegative ? Duration.zero : duration;
  }

  // Function Name: _readString
  // Description: Converts a nullable field to trimmed text, representing a missing value as an empty string.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - String: trimmed field text, or an empty string for null.
  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }
}

// 클래스명: PatientCaregiverLink
// 역할: 환자와 보호자의 식별자·별칭·연동 상태와 생성 시각을 보관한다.
// 주요 책임:
// - 현재 및 구형 응답을 변환하고 자기 자신과의 연동을 검증하며 불변 연결·해제 상태를 생성한다.
// 속성:
// - linkId (int?): 조회·전송·감시 대상 연동 ID
// - patientId (String): 구형 응답과 호환할 환자 식별자
// - caregiverId (String): 구형 응답과 호환할 보호자 식별자
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
// - patientAlias (String?): 보호자가 설정한 환자 별칭; 빈 문자열은 별칭 해제
// - linkStatus (bool): 환자·보호자 연결 활성 상태
// - linkedAt (DateTime?): 환자·보호자가 연결된 시각
class PatientCaregiverLink {
  final int? linkId;
  final String patientId;
  final String caregiverId;
  final String patientHash;
  final String caregiverHash;
  final String? patientAlias;
  final bool linkStatus;
  final DateTime? linkedAt;

  // 함수이름: PatientCaregiverLink
  // 함수역할: 환자·보호자 식별자, 표시 별칭, 연동 활성 상태와 연결 시각을 한 관계로 묶는다.
  // 매개변수:
  // - linkId (int?): 조회·전송·감시 대상 연동 ID
  // - patientId (String): 구형 응답과 호환할 환자 식별자
  // - caregiverId (String): 구형 응답과 호환할 보호자 식별자
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientAlias (String?): 보호자가 설정한 환자 별칭; 빈 문자열은 별칭 해제
  // - linkStatus (bool): 환자·보호자 연결 활성 상태
  // - linkedAt (DateTime?): 환자·보호자가 연결된 시각
  // 반환값:
  // - PatientCaregiverLink: 초기화된 인스턴스.
  const PatientCaregiverLink({
    this.linkId,
    this.patientId = '',
    this.caregiverId = '',
    this.patientHash = '',
    this.caregiverHash = '',
    this.patientAlias,
    this.linkStatus = false,
    this.linkedAt,
  });

  // 함수이름: PatientCaregiverLink.fromJson
  // 함수역할: 서버에서 받은 환자-보호자 연동 JSON을 앱 모델로 변환한다. 과거 필드명과 현재 필드명을 함께 읽어 호환성을 유지한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 환자-보호자 연동 API 응답 JSON
  // 반환값:
  // - PatientCaregiverLink 인스턴스
  factory PatientCaregiverLink.fromJson(Map<String, dynamic> json) {
    return PatientCaregiverLink(
      linkId: _readInt(json['link_id'] ?? json['id'] ?? json['linkID']),
      patientId: _readString(json['patient_id'] ?? json['patientID']),
      caregiverId: _readString(
        json['caregiver_id'] ?? json['caregiverID'] ?? json['guardian_id'],
      ),
      patientHash: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      caregiverHash: _readString(
        json['caregiver_hash'] ??
            json['caregiver_id'] ??
            json['caregiverID'] ??
            json['guardian_hash'] ??
            json['guardian_id'] ??
            json['guardianID'],
      ),
      patientAlias: _readPatientAlias(json),
      linkStatus: _readBool(
        json['link_status'] ?? json['linkStatus'] ?? json['linked'],
      ),
      linkedAt: _readDate(
        json['linked_at'] ?? json['linkedAt'] ?? json['created_at'],
      ),
    );
  }

  // 함수이름: toJson
  // 함수역할: 환자-보호자 연동 정보를 API 필드명 기준 JSON으로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - JSON Map
  Map<String, dynamic> toJson() {
    return {
      'link_id': linkId,
      'patient_id': patientId,
      'caregiver_id': caregiverId,
      'patient_hash': patientHash,
      'caregiver_hash': caregiverHash,
      'patient_alias': patientAlias,
      'link_status': linkStatus,
      'linked_at': linkedAt?.toIso8601String(),
    };
  }

  // Function Name: savePatientCaregiverLink
  // Description: Produces a linked copy only when the caregiver hash is nonblank and differs from the patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - PatientCaregiverLink: Produces a linked copy only when the caregiver hash is nonblank and differs from the patient hash.
  PatientCaregiverLink savePatientCaregiverLink() {
    if (!validateCaregiverHash()) {
      throw StateError('Caregiver hash must differ from the patient hash.');
    }
    return copyWith(linkStatus: true);
  }

  // Function Name: validateCaregiverHash
  // Description: Rejects a blank caregiver hash and a caregiver identifier equal to the patient's trimmed hash.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Rejects a blank caregiver hash and a caregiver identifier equal to the patient's trimmed hash.
  bool validateCaregiverHash() {
    return caregiverHash.trim().isNotEmpty &&
        caregiverHash.trim() != patientHash.trim();
  }

  // Function Name: removePatientCaregiverLink
  // Description: Produces an unlinked copy without discarding participant identities, alias, or linkage metadata.
  // Parameters:
  // - None.
  // Returns:
  // - PatientCaregiverLink: Produces an unlinked copy without discarding participant identities, alias, or linkage metadata.
  PatientCaregiverLink removePatientCaregiverLink() {
    return copyWith(linkStatus: false);
  }

  // 함수이름: copyWith
  // 함수역할: 기존 연동 정보를 유지하면서 일부 필드만 변경한 새 객체를 만든다.
  // 매개변수:
  // - linkId (int?): 조회·전송·감시 대상 연동 ID
  // - patientId (String?): 구형 응답과 호환할 환자 식별자
  // - caregiverId (String?): 구형 응답과 호환할 보호자 식별자
  // - patientHash (String?): 조회·저장·알림 대상 환자의 소유권 해시
  // - caregiverHash (String?): 조회·저장 범위를 제한할 보호자 해시
  // - patientAlias (String?): 보호자가 설정한 환자 별칭; 빈 문자열은 별칭 해제
  // - linkStatus (bool?): 환자·보호자 연결 활성 상태
  // - linkedAt (DateTime?): 환자·보호자가 연결된 시각
  // 반환값:
  // - 변경값이 반영된 PatientCaregiverLink 인스턴스
  PatientCaregiverLink copyWith({
    int? linkId,
    String? patientId,
    String? caregiverId,
    String? patientHash,
    String? caregiverHash,
    String? patientAlias,
    bool? linkStatus,
    DateTime? linkedAt,
  }) {
    return PatientCaregiverLink(
      linkId: linkId ?? this.linkId,
      patientId: patientId ?? this.patientId,
      caregiverId: caregiverId ?? this.caregiverId,
      patientHash: patientHash ?? this.patientHash,
      caregiverHash: caregiverHash ?? this.caregiverHash,
      patientAlias: patientAlias ?? this.patientAlias,
      linkStatus: linkStatus ?? this.linkStatus,
      linkedAt: linkedAt ?? this.linkedAt,
    );
  }

  // Function Name: _readString
  // Description: Converts a nullable field to trimmed text, representing a missing value as an empty string.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - String: trimmed field text, or an empty string for null.
  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  // 함수이름: _readPatientAlias
  // 함수역할: 서버에 아직 별칭이 없는 NULL과 사용자가 지운 빈 문자열을 구분한다. 과거 서버가 별칭 필드를 생략한 응답도 NULL로 처리한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - String?: 서버에 아직 별칭이 없는 NULL과 사용자가 지운 빈 문자열을 구분한다. 과거 서버가 별칭 필드를 생략한 응답도 NULL로 처리한다.
  static String? _readPatientAlias(Map<String, dynamic> json) {
    const aliasKeys = ['patient_alias', 'patientAlias', 'display_name'];
    for (final key in aliasKeys) {
      if (!json.containsKey(key)) {
        continue;
      }
      final rawAlias = json[key];
      return rawAlias == null ? null : _readString(rawAlias);
    }
    return null;
  }

  // Function Name: _readInt
  // Description: Reads an integer or numeric string, and uses null when parsing fails.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - int?: Reads an integer or numeric string, and uses null when parsing fails.
  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_readString(value));
  }

  // Function Name: _readBool
  // Description: Preserves booleans, treats nonzero numbers as true, and accepts true, 1, or yes text as enabled.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - bool: Preserves booleans, treats nonzero numbers as true, and accepts true, 1, or yes text as enabled.
  static bool _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = _readString(value).toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  // Function Name: _readDate
  // Description: Parses nonempty date text and returns null for absent or malformed dates.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - DateTime?: Parses nonempty date text and returns null for absent or malformed dates.
  static DateTime? _readDate(dynamic value) {
    final text = _readString(value);
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }
}
