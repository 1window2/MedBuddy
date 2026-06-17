class PatientCaregiverLink {
  final int? linkID;
  final String patientID;
  final String caregiverID;
  final bool linked;
  final DateTime? createdAt;

  const PatientCaregiverLink({
    this.linkID,
    this.patientID = '',
    this.caregiverID = '',
    this.linked = false,
    this.createdAt,
  });

  factory PatientCaregiverLink.fromJson(Map<String, dynamic> json) {
    return PatientCaregiverLink(
      linkID: _readInt(json['id'] ?? json['link_id'] ?? json['linkID']),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      caregiverID: _readString(
        json['caregiver_hash'] ?? json['caregiver_id'] ?? json['caregiverID'],
      ),
      linked: _readBool(json['linked']),
      createdAt: _readDate(json['created_at'] ?? json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': linkID,
      'patient_hash': patientID,
      'caregiver_hash': caregiverID,
      'linked': linked,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  PatientCaregiverLink createPatientCaregiverLink() {
    return copyWith(linked: true);
  }

  PatientCaregiverLink deletePatientCaregiverLink() {
    return copyWith(linked: false);
  }

  PatientCaregiverLink copyWith({
    int? linkID,
    String? patientID,
    String? caregiverID,
    bool? linked,
    DateTime? createdAt,
  }) {
    return PatientCaregiverLink(
      linkID: linkID ?? this.linkID,
      patientID: patientID ?? this.patientID,
      caregiverID: caregiverID ?? this.caregiverID,
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
