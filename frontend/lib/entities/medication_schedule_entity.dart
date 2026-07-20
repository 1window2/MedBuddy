// 파일명: medication_schedule_entity.dart
// 역할: 처방전 OCR 결과와 저장된 오늘 복약 일정 정보를 표현하는 모델을 정의한다.

const List<String> medicationScheduleSlotKeys = [
  'morning',
  'lunch',
  'evening',
  'bedtime',
];
const String defaultMedicationScheduleSlotKey = 'morning';

int medicationScheduleCountFromText(dynamic value) {
  if (value is int) {
    return value;
  }

  final text = value?.toString().trim() ?? '';
  final matches = RegExp(r'\d+').allMatches(text).toList(growable: false);
  if (matches.isEmpty) {
    return 0;
  }
  return int.tryParse(matches.last.group(0) ?? '') ?? 0;
}

// 함수명: medicationScheduleSlotKeysForFrequency
// 함수역할:
// - 1일 복용 횟수를 오늘의 복약 일정 시간대 키 목록으로 변환한다.
// 매개변수:
// - frequencyCount: 1일 복용 횟수
// 반환값:
// - 화면과 알림 설정에서 공유하는 시간대 키 목록
List<String> medicationScheduleSlotKeysForFrequency(int frequencyCount) {
  if (frequencyCount >= 4) {
    return medicationScheduleSlotKeys;
  }
  if (frequencyCount == 3) {
    return medicationScheduleSlotKeys.sublist(0, 3);
  }
  if (frequencyCount == 2) {
    return [
      medicationScheduleSlotKeys[0],
      medicationScheduleSlotKeys[2],
    ];
  }
  return const [defaultMedicationScheduleSlotKey];
}

// 클래스명: MedicationSchedule
// 역할: 약 이름, 조제일자, 1회 투약량, 1일 횟수, 총 투약일, 복약 상태를 보관한다.
// 주요 책임:
// - 처방전 분석 API 응답을 화면 모델로 변환한다.
// - 오늘 복약 일정 API 응답을 화면 모델로 변환한다.
// - 일정 계산과 화면 표시에서 공통으로 쓰는 파생 값을 제공한다.
class MedicationSchedule {
  final String maskedPrescriptionText;
  final DateTime? createdDate;
  final DateTime? prescriptionDate;
  final String medicationID;
  final String medicationName;
  final String dosage;
  final String intakeTime;
  final bool medicationStatus;
  final Map<String, bool> slotStatuses;
  final String patientID;
  final int medicationTime;
  final String? efficacy;
  final String? usageMethod;
  final String? warning;
  final String? imageUrl;
  final String rawMedicationName;
  final double nameConfidence;
  final String nameCorrectionSource;

  const MedicationSchedule({
    this.maskedPrescriptionText = '',
    this.createdDate,
    this.prescriptionDate,
    this.medicationID = '',
    required this.medicationName,
    this.dosage = '',
    this.intakeTime = '',
    this.medicationStatus = false,
    this.slotStatuses = const {},
    this.patientID = '',
    this.medicationTime = 0,
    this.efficacy = '',
    this.usageMethod = '',
    this.warning = '',
    this.imageUrl = '',
    this.rawMedicationName = '',
    this.nameConfidence = 0,
    this.nameCorrectionSource = '',
  });

  // 함수명: fromAnalysisJson
  // 함수역할:
  // - 처방전 OCR 분석 API 응답을 복약 일정 모델로 변환한다.
  // 매개변수:
  // - json: 처방전 분석 API의 약별 JSON
  // 반환값:
  // - MedicationSchedule 인스턴스
  factory MedicationSchedule.fromAnalysisJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      medicationName: _readString(json['drug_name']),
      prescriptionDate: _readDate(json['prescription_date']),
      dosage: _readString(json['dosage_per_time']),
      intakeTime: _readString(json['daily_frequency']),
      medicationTime: _readInt(json['total_days']),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['use_method'] ?? json['usage_method']),
      warning: _readString(json['warning_message'] ?? json['warning']),
      imageUrl: _readString(
          json['image_url'] ?? json['imageUrl'] ?? json['itemImage']),
      rawMedicationName: _readString(
        json['raw_drug_name'] ??
            json['rawDrugName'] ??
            json['rawMedicationName'],
      ),
      nameConfidence: _readDouble(
        json['name_confidence'] ?? json['nameConfidence'],
      ),
      nameCorrectionSource: _readString(
        json['name_correction_source'] ?? json['nameCorrectionSource'],
      ),
    );
  }

  // 함수명: fromScheduleJson
  // 함수역할:
  // - 저장된 오늘 복약 일정 API 응답을 화면 모델로 변환한다.
  // - 과거 필드명도 함께 읽어 기존 응답과의 호환성을 유지한다.
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
      prescriptionDate: _readDate(
        json['prescription_date'] ?? json['prescriptionDate'],
      ),
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
      slotStatuses: _readSlotStatuses(
        json['slot_statuses'] ?? json['slotStatuses'],
        json['completed_slot_keys'] ?? json['completedSlotKeys'],
      ),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      medicationTime: _readInt(json['total_days'] ?? json['medication_time']),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['use_method'] ?? json['usage_method']),
      warning: _readString(json['warning_message'] ?? json['warning']),
      imageUrl: _readString(
          json['image_url'] ?? json['imageUrl'] ?? json['itemImage']),
      rawMedicationName: _readString(
        json['raw_drug_name'] ??
            json['rawDrugName'] ??
            json['rawMedicationName'],
      ),
      nameConfidence: _readDouble(
        json['name_confidence'] ?? json['nameConfidence'],
      ),
      nameCorrectionSource: _readString(
        json['name_correction_source'] ?? json['nameCorrectionSource'],
      ),
    );
  }

  static List<MedicationSchedule> fromScheduleJsonList(dynamic rawItems) {
    final scheduleItems = rawItems is Map
        ? rawItems['schedules'] ?? rawItems['schedule']
        : rawItems;
    if (scheduleItems is! List) {
      return const [];
    }

    return scheduleItems
        .whereType<Map>()
        .map(
          (item) => MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  String get displayName {
    return medicationName.isEmpty ? '약품명 확인 필요' : medicationName;
  }

  bool get hasNameCorrection {
    final rawName = rawMedicationName.trim();
    if (rawName.isEmpty || rawName == medicationName.trim()) {
      return false;
    }

    final correctionSource = nameCorrectionSource.trim();
    return correctionSource.isNotEmpty && correctionSource != 'unverified';
  }

  int get dailyFrequencyCount {
    return _readInt(intakeTime);
  }

  List<String> get slotKeys {
    return medicationScheduleSlotKeysForFrequency(dailyFrequencyCount);
  }

  String get medicationTimeLabel {
    if (medicationTime <= 0) {
      return '';
    }
    return '$medicationTime일';
  }

  String get dosageLabel {
    return dosage.trim().isEmpty ? '용량 정보 없음' : dosage.trim();
  }

  // 함수명: toJson
  // 함수역할:
  // - 테스트와 저장 흐름에서 사용할 수 있도록 복약 일정을 JSON으로 변환한다.
  // 반환값:
  // - API 필드명을 기준으로 한 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'medication_id': medicationID,
      'drug_name': medicationName,
      'dosage_per_time': dosage,
      'daily_frequency': intakeTime,
      'medication_status': medicationStatus,
      'slot_statuses': slotStatuses,
      'completed_slot_keys': slotStatuses.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList(growable: false),
      'patient_id': patientID,
      'created_date': _formatDate(createdDate),
      'prescription_date': _formatDate(prescriptionDate),
      'total_days': medicationTimeLabel,
      'efficacy': efficacy ?? '',
      'use_method': usageMethod ?? '',
      'warning_message': warning ?? '',
      'image_url': imageUrl ?? '',
      'raw_drug_name': rawMedicationName,
      'name_confidence': nameConfidence,
      'name_correction_source': nameCorrectionSource,
    };
  }

  // 함수명: copyWith
  // 함수역할:
  // - 기존 복약 일정 값을 유지하면서 일부 필드만 바꾼 새 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 MedicationSchedule 인스턴스
  MedicationSchedule copyWith({
    String? maskedPrescriptionText,
    DateTime? createdDate,
    DateTime? prescriptionDate,
    String? medicationID,
    String? medicationName,
    String? dosage,
    String? intakeTime,
    bool? medicationStatus,
    Map<String, bool>? slotStatuses,
    String? patientID,
    int? medicationTime,
    String? efficacy,
    String? usageMethod,
    String? warning,
    String? imageUrl,
    String? rawMedicationName,
    double? nameConfidence,
    String? nameCorrectionSource,
  }) {
    return MedicationSchedule(
      maskedPrescriptionText:
          maskedPrescriptionText ?? this.maskedPrescriptionText,
      createdDate: createdDate ?? this.createdDate,
      prescriptionDate: prescriptionDate ?? this.prescriptionDate,
      medicationID: medicationID ?? this.medicationID,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      intakeTime: intakeTime ?? this.intakeTime,
      medicationStatus: medicationStatus ?? this.medicationStatus,
      slotStatuses: slotStatuses ?? this.slotStatuses,
      patientID: patientID ?? this.patientID,
      medicationTime: medicationTime ?? this.medicationTime,
      efficacy: efficacy ?? this.efficacy,
      usageMethod: usageMethod ?? this.usageMethod,
      warning: warning ?? this.warning,
      imageUrl: imageUrl ?? this.imageUrl,
      rawMedicationName: rawMedicationName ?? this.rawMedicationName,
      nameConfidence: nameConfidence ?? this.nameConfidence,
      nameCorrectionSource: nameCorrectionSource ?? this.nameCorrectionSource,
    );
  }

  bool isSlotCompleted(String slotKey) {
    if (slotStatuses.isEmpty) {
      return medicationStatus;
    }
    return slotStatuses[slotKey.trim().toLowerCase()] ?? false;
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int _readInt(dynamic value) {
    return medicationScheduleCountFromText(value);
  }

  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value)) ?? 0;
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

  static Map<String, bool> _readSlotStatuses(
    dynamic rawStatuses,
    dynamic rawCompletedSlotKeys,
  ) {
    final statuses = <String, bool>{};
    if (rawStatuses is Map) {
      rawStatuses.forEach((key, value) {
        final slotKey = _readString(key).toLowerCase();
        if (slotKey.isNotEmpty) {
          statuses[slotKey] = _readBool(value);
        }
      });
    }

    if (rawCompletedSlotKeys is List) {
      for (final rawSlotKey in rawCompletedSlotKeys) {
        final slotKey = _readString(rawSlotKey).toLowerCase();
        if (slotKey.isNotEmpty) {
          statuses[slotKey] = true;
        }
      }
    }
    return Map.unmodifiable(statuses);
  }

  static DateTime? _readDate(dynamic value) {
    final text = _readString(value);
    if (text.isEmpty || text == '정보 없음') {
      return null;
    }
    return DateTime.tryParse(text);
  }

  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
