class MedicationSchedule {
  final String maskedPrescriptionText;
  final DateTime? createdDate;
  final String medicationID;
  final String medicationName;
  final String dosage;
  final String intakeTime;
  final bool medicationStatus;
  final String patientID;
  final int medicationTime;

  const MedicationSchedule({
    this.maskedPrescriptionText = '',
    this.createdDate,
    this.medicationID = '',
    required this.medicationName,
    this.dosage = '',
    this.intakeTime = '',
    this.medicationStatus = false,
    this.patientID = '',
    this.medicationTime = 0,
  });

  factory MedicationSchedule.fromAnalysisJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      medicationName: _readString(json['drug_name']),
      dosage: _readString(json['dosage_per_time']),
      intakeTime: _readString(json['daily_frequency']),
      medicationTime: _readInt(json['total_days']),
    );
  }

  String get displayName {
    return medicationName.isEmpty ? '약품명 확인 필요' : medicationName;
  }

  String get medicationTimeLabel {
    if (medicationTime <= 0) {
      return '';
    }
    return '$medicationTime일';
  }

  Map<String, dynamic> toJson() {
    return {
      'drug_name': medicationName,
      'dosage_per_time': dosage,
      'daily_frequency': intakeTime,
      'total_days': medicationTimeLabel,
    };
  }

  void saveAnalysisResult() {
    throw UnsupportedError('분석 결과 저장 기능은 아직 구현되지 않았습니다.');
  }

  MedicationSchedule getTodayMedicationInfo() {
    throw UnsupportedError('오늘의 복약 정보 조회 기능은 아직 구현되지 않았습니다.');
  }

  MedicationSchedule getAnalysisResult() {
    return this;
  }

  MedicationSchedule getSavedMedicationInfo() {
    throw UnsupportedError('저장된 복약 정보 조회는 CheckSavedMedication에서 처리합니다.');
  }

  MedicationSchedule updateMedicationInfo() {
    throw UnsupportedError('복약 정보 수정 기능은 아직 구현되지 않았습니다.');
  }

  MedicationSchedule getTodayMedicationSchedule() {
    throw UnsupportedError('오늘의 복약 일정 기능은 아직 구현되지 않았습니다.');
  }

  void saveMedicationStatus() {
    throw UnsupportedError('복약 완료 상태 저장 기능은 아직 구현되지 않았습니다.');
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    final text = _readString(value);
    final match = RegExp(r'\d+').firstMatch(text);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(0) ?? '') ?? 0;
  }
}
