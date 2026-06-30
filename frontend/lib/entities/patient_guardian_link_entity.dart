// 파일명: patient_guardian_link_entity.dart
// 역할: 환자와 보호자 사이의 연동 상태를 표현하는 모델을 정의한다.

// 클래스명: PatientGuardianLink
// 역할: 환자 해시, 보호자 해시, 연동 여부, 생성 시각을 앱 내부에서 보관한다.
// 주요 책임:
// - 서버 응답 JSON을 Dart 모델로 변환한다.
// - 연동 생성/삭제 상태를 불변 객체 형태로 표현한다.
// - API 전송이나 테스트에 사용할 JSON을 생성한다.
class PatientGuardianLink {
  final int? linkID;
  final String patientID;
  final String guardianID;
  final bool linked;
  final DateTime? createdAt;

  const PatientGuardianLink({
    this.linkID,
    this.patientID = '',
    this.guardianID = '',
    this.linked = false,
    this.createdAt,
  });

  // 함수명: fromJson
  // 함수역할:
  // - 서버에서 받은 환자-보호자 연동 JSON을 앱 모델로 변환한다.
  // - 과거 필드명과 현재 필드명을 함께 읽어 호환성을 유지한다.
  // 매개변수:
  // - json: 환자-보호자 연동 API 응답 JSON
  // 반환값:
  // - PatientGuardianLink 인스턴스
  factory PatientGuardianLink.fromJson(Map<String, dynamic> json) {
    return PatientGuardianLink(
      linkID: _readInt(json['id'] ?? json['link_id'] ?? json['linkID']),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      guardianID: _readString(
        json['guardian_hash'] ??
            json['guardian_id'] ??
            json['guardianID'] ??
            json['caregiver_hash'] ??
            json['caregiver_id'] ??
            json['caregiverID'],
      ),
      linked: _readBool(json['linked']),
      createdAt: _readDate(json['created_at'] ?? json['createdAt']),
    );
  }

  // 함수명: toJson
  // 함수역할:
  // - 환자-보호자 연동 정보를 API 필드명 기준 JSON으로 변환한다.
  // 반환값:
  // - JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': linkID,
      'patient_hash': patientID,
      'guardian_hash': guardianID,
      'linked': linked,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  PatientGuardianLink createPatientGuardianLink() {
    return copyWith(linked: true);
  }

  PatientGuardianLink deletePatientGuardianLink() {
    return copyWith(linked: false);
  }

  // 함수명: copyWith
  // 함수역할:
  // - 기존 연동 정보를 유지하면서 일부 필드만 변경한 새 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 PatientGuardianLink 인스턴스
  PatientGuardianLink copyWith({
    int? linkID,
    String? patientID,
    String? guardianID,
    bool? linked,
    DateTime? createdAt,
  }) {
    return PatientGuardianLink(
      linkID: linkID ?? this.linkID,
      patientID: patientID ?? this.patientID,
      guardianID: guardianID ?? this.guardianID,
      linked: linked ?? this.linked,
      createdAt: createdAt ?? this.createdAt,
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
