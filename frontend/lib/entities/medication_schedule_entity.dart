// 파일명: medication_schedule_entity.dart
// 역할: 처방전 OCR 결과와 저장된 복약 일정 정보를 표현하는 모델을 정의한다.

// 클래스명: MedicationSchedule
// 역할: 약 이름, 1회 투약량, 1일 횟수, 총 투약일 등 복약 일정 필드를 보관한다.
// 주요 책임:
// - 처방전 분석 API 응답을 앱 내부 모델로 변환한다.
// - 오늘의 복약 일정 API 응답을 앱 내부 모델로 변환한다.
// - 복약 상태 변경 시 불변 객체 형태로 새 값을 생성한다.
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

  // 함수명: fromAnalysisJson
  // 함수역할:
  // - 처방전 OCR 분석 API가 반환한 약 정보를 복약 일정 모델로 변환한다.
  // 매개변수:
  // - json: 처방전 분석 API의 약 정보 JSON
  // 반환값:
  // - MedicationSchedule 인스턴스
  factory MedicationSchedule.fromAnalysisJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      medicationName: _readString(json['drug_name']),
      dosage: _readString(json['dosage_per_time']),
      intakeTime: _readString(json['daily_frequency']),
      medicationTime: _readInt(json['total_days']),
    );
  }

  // 함수명: fromScheduleJson
  // 함수역할:
  // - 저장된 복약 일정 API 응답을 화면에서 사용할 모델로 변환한다.
  // - 과거 오타 필드명도 함께 읽어 기존 데이터와의 호환성을 유지한다.
  // 매개변수:
  // - json: 복약 일정 API 응답 JSON
  // 반환값:
  // - MedicationSchedule 인스턴스
  factory MedicationSchedule.fromScheduleJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      maskedPrescriptionText: _readString(
        json['maskedPrescriptionText'] ?? json['masked_prescription_text'],
      ),
      createdDate: _readDate(json['created_date'] ?? json['createdDate']),
      medicationID: _readString(
        json['medication_id'] ?? json['medicationID'] ?? json['id'],
      ),
      medicationName: _readString(
        json['drug_name'] ?? json['medication_name'] ?? json['item_name'],
      ),
      dosage: _readString(json['dosage_per_time'] ?? json['dosage']),
      intakeTime: _readString(json['daily_frequency'] ?? json['intake_time']),
      medicationStatus: _readBool(
        json['medication_status'] ??
            json['medicationStatus'] ??
            json['medcationStatus'] ??
            json['medcation_status'],
      ),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      medicationTime: _readInt(json['total_days'] ?? json['medication_time']),
    );
  }

  String get displayName {
    return medicationName.isEmpty
        ? '\uC57D\uD488\uBA85 \uD655\uC778 \uD544\uC694'
        : medicationName;
  }

  String get medicationTimeLabel {
    if (medicationTime <= 0) {
      return '';
    }
    return '$medicationTime\uC77C';
  }

  // 함수명: toJson
  // 함수역할:
  // - 테스트와 저장 흐름에서 사용할 수 있도록 복약 일정을 JSON 형태로 변환한다.
  // 반환값:
  // - API 필드명을 기준으로 한 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'medication_id': medicationID,
      'drug_name': medicationName,
      'dosage_per_time': dosage,
      'daily_frequency': intakeTime,
      'medication_status': medicationStatus,
      'patient_id': patientID,
      'created_date': createdDate?.toIso8601String(),
      'total_days': medicationTimeLabel,
    };
  }

  // 함수명: copyWith
  // 함수역할:
  // - 기존 복약 일정 값을 유지하면서 일부 필드만 변경한 새 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 MedicationSchedule 인스턴스
  MedicationSchedule copyWith({
    String? maskedPrescriptionText,
    DateTime? createdDate,
    String? medicationID,
    String? medicationName,
    String? dosage,
    String? intakeTime,
    bool? medicationStatus,
    String? patientID,
    int? medicationTime,
  }) {
    return MedicationSchedule(
      maskedPrescriptionText:
          maskedPrescriptionText ?? this.maskedPrescriptionText,
      createdDate: createdDate ?? this.createdDate,
      medicationID: medicationID ?? this.medicationID,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      intakeTime: intakeTime ?? this.intakeTime,
      medicationStatus: medicationStatus ?? this.medicationStatus,
      patientID: patientID ?? this.patientID,
      medicationTime: medicationTime ?? this.medicationTime,
    );
  }

  void saveAnalysisResult() {
    throw UnsupportedError('Analysis result saving is handled by controls.');
  }

  MedicationSchedule getTodayMedicationInfo() {
    return this;
  }

  MedicationSchedule getAnalysisResult() {
    return this;
  }

  MedicationSchedule getSavedMedicationInfo() {
    throw UnsupportedError('Saved medication lookup is handled by controls.');
  }

  MedicationSchedule updateMedicationInfo() {
    throw UnsupportedError(
        'Medication schedule editing is not implemented yet.');
  }

  MedicationSchedule getTodayMedicationSchedule() {
    return this;
  }

  MedicationSchedule saveMedicationStatus({bool medicationStatus = true}) {
    return copyWith(medicationStatus: medicationStatus);
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
