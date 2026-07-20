// 파일명: patient_caregiver_link_entity.dart
// 역할: 환자와 보호자 사이의 연동 상태를 표현하는 모델을 정의한다.

// 클래스명: PatientCaregiverLink
// 역할: 환자 해시, 보호자 해시, 연동 여부, 생성 시각을 앱 내부에서 보관한다.
// 주요 책임:
// - 서버 응답 JSON을 Dart 모델로 변환한다.
// - 연동 생성/삭제 상태를 불변 객체 형태로 표현한다.
// - API 전송이나 테스트에 사용할 JSON을 생성한다.
class PatientLinkCode {
  final String code;
  final String patientHash;
  final DateTime expiresAt;

  const PatientLinkCode({
    required this.code,
    required this.patientHash,
    required this.expiresAt,
  });

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

  bool isExpired([DateTime? now]) {
    return !expiresAt.isAfter(now ?? DateTime.now());
  }

  Duration remaining([DateTime? now]) {
    final duration = expiresAt.difference(now ?? DateTime.now());
    return duration.isNegative ? Duration.zero : duration;
  }

  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }
}

class PatientCaregiverLink {
  final int? linkId;
  final String patientId;
  final String caregiverId;
  final String patientHash;
  final String caregiverHash;
  final bool linkStatus;
  final DateTime? linkedAt;

  const PatientCaregiverLink({
    this.linkId,
    this.patientId = '',
    this.caregiverId = '',
    this.patientHash = '',
    this.caregiverHash = '',
    this.linkStatus = false,
    this.linkedAt,
  });

  // 함수명: fromJson
  // 함수역할:
  // - 서버에서 받은 환자-보호자 연동 JSON을 앱 모델로 변환한다.
  // - 과거 필드명과 현재 필드명을 함께 읽어 호환성을 유지한다.
  // 매개변수:
  // - json: 환자-보호자 연동 API 응답 JSON
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
      linkStatus: _readBool(
        json['link_status'] ?? json['linkStatus'] ?? json['linked'],
      ),
      linkedAt: _readDate(
        json['linked_at'] ?? json['linkedAt'] ?? json['created_at'],
      ),
    );
  }

  // 함수명: toJson
  // 함수역할:
  // - 환자-보호자 연동 정보를 API 필드명 기준 JSON으로 변환한다.
  // 반환값:
  // - JSON Map
  Map<String, dynamic> toJson() {
    return {
      'link_id': linkId,
      'patient_id': patientId,
      'caregiver_id': caregiverId,
      'patient_hash': patientHash,
      'caregiver_hash': caregiverHash,
      'link_status': linkStatus,
      'linked_at': linkedAt?.toIso8601String(),
    };
  }

  PatientCaregiverLink savePatientCaregiverLink() {
    if (!validateCaregiverHash()) {
      throw StateError('Caregiver hash must differ from the patient hash.');
    }
    return copyWith(linkStatus: true);
  }

  bool validateCaregiverHash() {
    return caregiverHash.trim().isNotEmpty &&
        caregiverHash.trim() != patientHash.trim();
  }

  PatientCaregiverLink removePatientCaregiverLink() {
    return copyWith(linkStatus: false);
  }

  // 함수명: copyWith
  // 함수역할:
  // - 기존 연동 정보를 유지하면서 일부 필드만 변경한 새 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 PatientCaregiverLink 인스턴스
  PatientCaregiverLink copyWith({
    int? linkId,
    String? patientId,
    String? caregiverId,
    String? patientHash,
    String? caregiverHash,
    bool? linkStatus,
    DateTime? linkedAt,
  }) {
    return PatientCaregiverLink(
      linkId: linkId ?? this.linkId,
      patientId: patientId ?? this.patientId,
      caregiverId: caregiverId ?? this.caregiverId,
      patientHash: patientHash ?? this.patientHash,
      caregiverHash: caregiverHash ?? this.caregiverHash,
      linkStatus: linkStatus ?? this.linkStatus,
      linkedAt: linkedAt ?? this.linkedAt,
    );
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(_readString(value));
  }

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

  static DateTime? _readDate(dynamic value) {
    final text = _readString(value);
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }
}
