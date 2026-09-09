// File Name: medication_schedule_entity.dart
// Role: Defines prescription-analysis and saved-schedule records, slot status, and localized dosage display values.

import 'medication_image_url_entity.dart';

const List<String> medicationScheduleSlotKeys = [
  'morning',
  'lunch',
  'evening',
  'bedtime',
];
const String defaultMedicationScheduleSlotKey = 'morning';

// Function Name: medicationScheduleCountFromText
// Description: Preserves integer input or extracts the last digit group from schedule text, returning zero when no numeric count can be read.
// Parameters:
// - value (dynamic): Number or frequency text from which to extract the dose count.
// Returns:
// - int: Preserves integer input or extracts the last digit group from schedule text, returning zero when no numeric count can be read.
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

// 함수이름: medicationScheduleSlotKeysForFrequency
// 함수역할: 1일 복용 횟수를 오늘의 복약 일정 시간대 키 목록으로 변환한다.
// 매개변수:
// - frequencyCount (int): 1일 복용 횟수
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
    return [medicationScheduleSlotKeys[0], medicationScheduleSlotKeys[2]];
  }
  return const [defaultMedicationScheduleSlotKey];
}

// Class Name: MedicationSchedule
// Role: Holds prescription dates, drug names, doses, course duration, ownership, and completion status.
// Responsibilities:
// - Decode OCR and saved-schedule payloads, preserve correction provenance, and derive supported slots and localized display values.
// Attributes:
// - maskedPrescriptionText (String): Prescription OCR text after personal-data redaction.
// - createdDate (DateTime?): Creation date of the saved medication or course.
// - prescriptionDate (DateTime?): Dispensing or prescription date used as the course start.
// - prescriptionBatchId (String): Identifier grouping medications from the same prescription analysis.
// - medicationID (String): Identifier of the targeted saved medication.
// - medicationName (String): Medication name used for display and persistence.
// - dosage (String): Dose per intake including its unit.
// - intakeTime (String): Daily intake-frequency text from the prescription.
// - medicationStatus (bool): Completion state to apply or retain.
// - slotStatuses (Map<String, bool>): Completion flags keyed by medication slot.
// - scheduleSlotKeys (List<String>): Explicitly selected medication schedule slot keys.
// - patientID (String): Patient identifier retained for legacy response compatibility.
// - medicationTime (int): Total course length in days.
// - efficacy (String?): Public-catalog medication efficacy description.
// - usageMethod (String?): Original medication usage and intake-timing instructions.
// - warning (String?): Important medication warning text.
// - imageUrl (String?): Remote image URL associated with medication details or a candidate.
// - rawMedicationName (String): Original OCR medication name before correction.
// - nameConfidence (double): Confidence assigned to the recognized medication name.
// - nameCorrectionSource (String): Provenance of medication-name correction or review.
class MedicationSchedule {
  final String maskedPrescriptionText;
  final DateTime? createdDate;
  final DateTime? prescriptionDate;
  final String prescriptionBatchId;
  final String medicationID;
  final String medicationName;
  final String dosage;
  final String intakeTime;
  final bool medicationStatus;
  final Map<String, bool> slotStatuses;
  final List<String> scheduleSlotKeys;
  final String patientID;
  final int medicationTime;
  final String? efficacy;
  final String? usageMethod;
  final String? warning;
  final String? imageUrl;
  final String rawMedicationName;
  final double nameConfidence;
  final String nameCorrectionSource;

  // Function Name: MedicationSchedule
  // Description: Captures a medication course and its OCR provenance, patient ownership, optional catalog details, and per-slot completion state.
  // Parameters:
  // - maskedPrescriptionText (String): Prescription OCR text after personal-data redaction.
  // - createdDate (DateTime?): Creation date of the saved medication or course.
  // - prescriptionDate (DateTime?): Dispensing or prescription date used as the course start.
  // - prescriptionBatchId (String): Identifier grouping medications from the same prescription analysis.
  // - medicationID (String): Identifier of the targeted saved medication.
  // - medicationName (String): Medication name used for display and persistence.
  // - dosage (String): Dose per intake including its unit.
  // - intakeTime (String): Daily intake-frequency text from the prescription.
  // - medicationStatus (bool): Completion state to apply or retain.
  // - slotStatuses (Map<String, bool>): Completion flags keyed by medication slot.
  // - scheduleSlotKeys (List<String>): Explicitly selected medication schedule slot keys.
  // - patientID (String): Patient identifier retained for legacy response compatibility.
  // - medicationTime (int): Total course length in days.
  // - efficacy (String?): Public-catalog medication efficacy description.
  // - usageMethod (String?): Original medication usage and intake-timing instructions.
  // - warning (String?): Important medication warning text.
  // - imageUrl (String?): Remote image URL associated with medication details or a candidate.
  // - rawMedicationName (String): Original OCR medication name before correction.
  // - nameConfidence (double): Confidence assigned to the recognized medication name.
  // - nameCorrectionSource (String): Provenance of medication-name correction or review.
  // Returns:
  // - MedicationSchedule: the initialized instance.
  const MedicationSchedule({
    this.maskedPrescriptionText = '',
    this.createdDate,
    this.prescriptionDate,
    this.prescriptionBatchId = '',
    this.medicationID = '',
    required this.medicationName,
    this.dosage = '',
    this.intakeTime = '',
    this.medicationStatus = false,
    this.slotStatuses = const {},
    this.scheduleSlotKeys = const [],
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

  // Function Name: MedicationSchedule.fromAnalysisJson
  // Description: Converts OCR-analysis drug fields into a medication course while preserving prescription batch, raw name, confidence, and correction source.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - MedicationSchedule: the initialized instance.
  factory MedicationSchedule.fromAnalysisJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      medicationName: _readString(json['drug_name']),
      prescriptionDate: _readDate(json['prescription_date']),
      prescriptionBatchId: _readString(json['prescription_batch_id']),
      dosage: _readString(json['dosage_per_time']),
      intakeTime: _readString(json['daily_frequency']),
      medicationTime: _readInt(json['total_days']),
      scheduleSlotKeys: _readScheduleSlotKeys(
        json['schedule_slot_keys'] ?? json['scheduleSlotKeys'],
      ),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['use_method'] ?? json['usage_method']),
      warning: _readString(json['warning_message'] ?? json['warning']),
      imageUrl: safeMedicationImageUrl(
        json['image_url'] ?? json['imageUrl'] ?? json['itemImage'],
      ),
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

  // Function Name: MedicationSchedule.fromScheduleJson
  // Description: Decodes a saved medication schedule using current and legacy field spellings, including per-slot status and OCR correction provenance.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - MedicationSchedule: the initialized instance.
  factory MedicationSchedule.fromScheduleJson(Map<String, dynamic> json) {
    return MedicationSchedule(
      maskedPrescriptionText: _readString(
        json['maskedPrescriptionText'] ?? json['masked_prescription_text'],
      ),
      createdDate: _readDate(json['created_date'] ?? json['createdDate']),
      prescriptionDate: _readDate(
        json['prescription_date'] ?? json['prescriptionDate'],
      ),
      prescriptionBatchId: _readString(
        json['prescription_batch_id'] ?? json['prescriptionBatchId'],
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
      scheduleSlotKeys: _readScheduleSlotKeys(
        json['schedule_slot_keys'] ?? json['scheduleSlotKeys'],
      ),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      medicationTime: _readInt(json['total_days'] ?? json['medication_time']),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['use_method'] ?? json['usage_method']),
      warning: _readString(json['warning_message'] ?? json['warning']),
      imageUrl: safeMedicationImageUrl(
        json['image_url'] ?? json['imageUrl'] ?? json['itemImage'],
      ),
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

  // Function Name: fromScheduleJsonList
  // Description: Accepts a schedule list or a wrapper under schedules or schedule and decodes map entries, returning an empty list for other payload shapes.
  // Parameters:
  // - rawItems (dynamic): Raw server item or list before model conversion.
  // Returns:
  // - List<MedicationSchedule>: Accepts a schedule list or a wrapper under schedules or schedule and decodes map entries, returning an empty list for other payload shapes.
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
          // Function Name: map callback
          // Description: Parses a daily schedule response item into a medication schedule.
          // Parameters:
          // - item (Map): Current response or collection entry being transformed or checked.
          // Returns:
          // - The parsed medication schedule.
          (item) => MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  // 함수이름: displayName
  // 함수역할: 약명이 비어 있으면 기존 한국어 확인 문구를 사용하고 값이 있으면 원래 약명을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 약명이 비어 있으면 기존 한국어 확인 문구를 사용하고 값이 있으면 원래 약명을 제공한다.
  String get displayName {
    return medicationName.isEmpty ? '약품명 확인 필요' : medicationName;
  }

  // 함수이름: displayNameForLanguage
  // 함수역할: 약품명이 비어 있을 때 현재 언어에 맞는 대체 문구를 반환한다. 공공데이터나 OCR에서 받은 실제 약품명은 번역하지 않고 그대로 유지한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 약품명이 비어 있을 때 현재 언어에 맞는 대체 문구를 반환한다. 공공데이터나 OCR에서 받은 실제 약품명은 번역하지 않고 그대로 유지한다.
  String displayNameForLanguage(String language) {
    if (medicationName.trim().isNotEmpty) {
      return medicationName.trim();
    }
    return _isEnglishLanguage(language)
        ? 'Medication name unavailable'
        : '약품명 확인 필요';
  }

  // Function Name: hasNameCorrection
  // Description: Reports a changed raw OCR name only when a nonempty correction source other than unverified records the correction.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Reports a changed raw OCR name only when a nonempty correction source other than unverified records the correction.
  bool get hasNameCorrection {
    final rawName = rawMedicationName.trim();
    if (rawName.isEmpty || rawName == medicationName.trim()) {
      return false;
    }

    final correctionSource = nameCorrectionSource.trim();
    return correctionSource.isNotEmpty && correctionSource != 'unverified';
  }

  // 함수이름: isNameReviewRequired
  // 함수역할: 이름 출처가 unverified이거나 양수 신뢰도가 0.75 미만이면 사용자 확인이 필요한 항목으로 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 이름 출처가 unverified이거나 양수 신뢰도가 0.75 미만이면 사용자 확인이 필요한 항목으로 판정한다.
  bool get isNameReviewRequired {
    final source = nameCorrectionSource.trim();
    return source == 'unverified' ||
        (nameConfidence > 0 && nameConfidence < 0.75);
  }

  // 함수이름: isNameConfirmed
  // 함수역할: 사용자가 직접 수정하거나 검토 완료한 출처의 약명인지 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 사용자가 직접 수정하거나 검토 완료한 출처의 약명인지 판정한다.
  bool get isNameConfirmed {
    final source = nameCorrectionSource.trim();
    return source == 'user_edit' || source == 'user_review';
  }

  // 함수이름: dailyFrequencyCount
  // 함수역할: 하루 복용 횟수 텍스트에서 마지막 숫자 묶음을 정수로 읽는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - int: 하루 복용 횟수 텍스트에서 마지막 숫자 묶음을 정수로 읽는다.
  int get dailyFrequencyCount {
    return _readInt(intakeTime);
  }

  // 함수이름: slotKeys
  // 함수역할: 명시된 복약 시간대가 있으면 읽기 전용으로 제공하고 없으면 하루 복용 횟수에서 기본 시간대를 유도한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<String>: 명시된 복약 시간대가 있으면 읽기 전용으로 제공하고 없으면 하루 복용 횟수에서 기본 시간대를 유도한다.
  List<String> get slotKeys {
    if (scheduleSlotKeys.isNotEmpty) {
      return List.unmodifiable(scheduleSlotKeys);
    }
    return medicationScheduleSlotKeysForFrequency(dailyFrequencyCount);
  }

  // 함수이름: medicationTimeLabel
  // 함수역할: 양수 투약 기간을 한국어 일수 문자열로 표시하고 기간이 없으면 빈 문자열을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 양수 투약 기간을 한국어 일수 문자열로 표시하고 기간이 없으면 빈 문자열을 제공한다.
  String get medicationTimeLabel {
    if (medicationTime <= 0) {
      return '';
    }
    return '$medicationTime일';
  }

  // 함수이름: dosageLabel
  // 함수역할: 공백을 정리한 복용량을 제공하고 비어 있으면 기존 한국어 용량 없음 문구를 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 공백을 정리한 복용량을 제공하고 비어 있으면 기존 한국어 용량 없음 문구를 사용한다.
  String get dosageLabel {
    return dosage.trim().isEmpty ? '용량 정보 없음' : dosage.trim();
  }

  // Function Name: dosageLabelForLanguage
  // Description: Localizes recognized Korean dose units for English display while retaining unparsed text, fractions, and international units such as mg and mL.
  // Parameters:
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - String: Localizes recognized Korean dose units for English display while retaining unparsed text, fractions, and international units such as mg and mL.
  String dosageLabelForLanguage(String language) {
    final value = dosage.trim();
    final isEnglish = _isEnglishLanguage(language);
    if (value.isEmpty) {
      return isEnglish ? 'Dose not available' : '투약량 정보 없음';
    }

    final match = RegExp(
      r'^(\d+(?:[.,]\d+)?|\d+/\d+)\s*(정|캡슐|포|방울)?$',
    ).firstMatch(value);
    if (match == null) {
      return value;
    }

    final amount = match.group(1) ?? value;
    final detectedUnit = match.group(2);
    if (detectedUnit == null) {
      return value;
    }
    if (!isEnglish) {
      return '$amount$detectedUnit';
    }
    final unit = switch (detectedUnit) {
      '캡슐' => 'capsule',
      '포' => 'sachet',
      '방울' => 'drop',
      _ => 'tablet',
    };
    return '$amount $unit';
  }

  // 함수이름: dailyFrequencyLabelForLanguage
  // 함수역할: 1일 복용 횟수를 현재 언어의 문장형 표시값으로 변환한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 1일 복용 횟수를 현재 언어의 문장형 표시값으로 변환한다.
  String dailyFrequencyLabelForLanguage(String language) {
    final value = intakeTime.trim();
    if (value.isEmpty) {
      return _isEnglishLanguage(language)
          ? 'Frequency not available'
          : '복용 횟수 정보 없음';
    }
    if (!_isEnglishLanguage(language)) {
      return value;
    }
    final koreanFrequency = RegExp(r'^1일\s*(\d+)회$').firstMatch(value);
    final numericFrequency = RegExp(r'^\d+$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    final count = koreanFrequency == null
        ? numericFrequency
        : int.tryParse(koreanFrequency.group(1) ?? '');
    if (count == null || count <= 0) {
      return value;
    }
    return count == 1 ? 'once daily' : '$count times daily';
  }

  // 함수이름: durationLabelForLanguage
  // 함수역할: 총 복용 일수를 현재 언어에 맞는 표시값으로 변환한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 총 복용 일수를 현재 언어에 맞는 표시값으로 변환한다.
  String durationLabelForLanguage(String language) {
    if (medicationTime <= 0) {
      return _isEnglishLanguage(language)
          ? 'Duration not available'
          : '복용 기간 정보 없음';
    }
    if (!_isEnglishLanguage(language)) {
      return '$medicationTime일';
    }
    return medicationTime == 1 ? '1 day' : '$medicationTime days';
  }

  // Function Name: toJson
  // Description: Serializes schedule and correction metadata using API keys, derives completed slots, formats dates, and validates the remote image URL.
  // Parameters:
  // - None.
  // Returns:
  // - Map<String, dynamic>: Serializes schedule and correction metadata using API keys, derives completed slots, formats dates, and validates the remote image URL.
  Map<String, dynamic> toJson() {
    return {
      'medication_id': medicationID,
      'drug_name': medicationName,
      'dosage_per_time': dosage,
      'daily_frequency': intakeTime,
      'medication_status': medicationStatus,
      'slot_statuses': slotStatuses,
      'completed_slot_keys': slotStatuses.entries
          .where(/* Function Name: where callback
           * Description: Selects slot-status entries marked completed.
           * Parameters:
           * - entry (MapEntry<String, bool>): Current key-value entry in the map.
           * Returns:
           * - Whether this slot is completed.
           */(entry) => entry.value)
          .map(/* Function Name: map callback
           * Description: Extracts the slot key from a completed status entry.
           * Parameters:
           * - entry (MapEntry<String, bool>): Current key-value entry in the map.
           * Returns:
           * - The completed slot's key.
           */(entry) => entry.key)
          .toList(growable: false),
      'schedule_slot_keys': slotKeys,
      'patient_id': patientID,
      'created_date': _formatDate(createdDate),
      'prescription_date': _formatDate(prescriptionDate),
      'prescription_batch_id': prescriptionBatchId,
      'total_days': medicationTimeLabel,
      'efficacy': efficacy ?? '',
      'use_method': usageMethod ?? '',
      'warning_message': warning ?? '',
      'image_url': safeMedicationImageUrl(imageUrl),
      'raw_drug_name': rawMedicationName,
      'name_confidence': nameConfidence,
      'name_correction_source': nameCorrectionSource,
    };
  }

  // Function Name: copyWith
  // Description: Creates a medication course with explicitly supplied changes while preserving unspecified schedule, catalog, and OCR correction fields.
  // Parameters:
  // - maskedPrescriptionText (String?): Prescription OCR text after personal-data redaction.
  // - createdDate (DateTime?): Creation date of the saved medication or course.
  // - prescriptionDate (DateTime?): Dispensing or prescription date used as the course start.
  // - prescriptionBatchId (String?): Identifier grouping medications from the same prescription analysis.
  // - medicationID (String?): Identifier of the targeted saved medication.
  // - medicationName (String?): Medication name used for display and persistence.
  // - dosage (String?): Dose per intake including its unit.
  // - intakeTime (String?): Daily intake-frequency text from the prescription.
  // - medicationStatus (bool?): Completion state to apply or retain.
  // - slotStatuses (Map<String, bool>?): Completion flags keyed by medication slot.
  // - scheduleSlotKeys (List<String>?): Explicitly selected medication schedule slot keys.
  // - patientID (String?): Patient identifier retained for legacy response compatibility.
  // - medicationTime (int?): Total course length in days.
  // - efficacy (String?): Public-catalog medication efficacy description.
  // - usageMethod (String?): Original medication usage and intake-timing instructions.
  // - warning (String?): Important medication warning text.
  // - imageUrl (String?): Remote image URL associated with medication details or a candidate.
  // - rawMedicationName (String?): Original OCR medication name before correction.
  // - nameConfidence (double?): Confidence assigned to the recognized medication name.
  // - nameCorrectionSource (String?): Provenance of medication-name correction or review.
  // Returns:
  // - MedicationSchedule: a copy with supplied replacements and all other fields preserved.
  MedicationSchedule copyWith({
    String? maskedPrescriptionText,
    DateTime? createdDate,
    DateTime? prescriptionDate,
    String? prescriptionBatchId,
    String? medicationID,
    String? medicationName,
    String? dosage,
    String? intakeTime,
    bool? medicationStatus,
    Map<String, bool>? slotStatuses,
    List<String>? scheduleSlotKeys,
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
      prescriptionBatchId: prescriptionBatchId ?? this.prescriptionBatchId,
      medicationID: medicationID ?? this.medicationID,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      intakeTime: intakeTime ?? this.intakeTime,
      medicationStatus: medicationStatus ?? this.medicationStatus,
      slotStatuses: slotStatuses ?? this.slotStatuses,
      scheduleSlotKeys: scheduleSlotKeys ?? this.scheduleSlotKeys,
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

  // Function Name: isSlotCompleted
  // Description: Reads the normalized slot's completion flag, falling back to the legacy medication-wide status only when no slot statuses exist.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - bool: Reads the normalized slot's completion flag, falling back to the legacy medication-wide status only when no slot statuses exist.
  bool isSlotCompleted(String slotKey) {
    if (slotStatuses.isEmpty) {
      return medicationStatus;
    }
    return slotStatuses[slotKey.trim().toLowerCase()] ?? false;
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

  // Function Name: _readInt
  // Description: Extracts an integer count from schedule text through the shared last-digit-group parser.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - int: Extracts an integer count from schedule text through the shared last-digit-group parser.
  static int _readInt(dynamic value) {
    return medicationScheduleCountFromText(value);
  }

  // 함수이름: _isEnglishLanguage
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두사로 영어 계열을 판정한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - bool: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두사로 영어 계열을 판정한다.
  static bool _isEnglishLanguage(String language) {
    return language.trim().toLowerCase().startsWith('en');
  }

  // Function Name: _readDouble
  // Description: Converts numeric input or a numeric string to a double, using zero when conversion fails.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - double: Converts numeric input or a numeric string to a double, using zero when conversion fails.
  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(_readString(value)) ?? 0;
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

  // Function Name: _readSlotStatuses
  // Description: Combines explicit slot flags with legacy completed-slot keys and returns an immutable map with normalized nonblank keys.
  // Parameters:
  // - rawStatuses (dynamic): Raw server object containing per-slot completion flags.
  // - rawCompletedSlotKeys (dynamic): Completed-slot list from legacy payloads.
  // Returns:
  // - Map<String, bool>: Combines explicit slot flags with legacy completed-slot keys and returns an immutable map with normalized nonblank keys.
  static Map<String, bool> _readSlotStatuses(
    dynamic rawStatuses,
    dynamic rawCompletedSlotKeys,
  ) {
    final statuses = <String, bool>{};
    if (rawStatuses is Map) {
      rawStatuses.forEach(/* Function Name: forEach callback
       * Description: Normalizes nonempty slot keys and parses their completion flags into the status map.
       * Parameters:
       * - key (dynamic): Flutter widget identity key.
       * - value (dynamic): Raw completion flag for this time slot.
       * Returns:
       * - No return value.
       */(key, value) {
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

  // 함수이름: _readScheduleSlotKeys
  // 함수역할: 서버 또는 사용자 수정값에서 지원하는 복약 시간대만 정해진 순서로 읽는다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - List<String>: 서버 또는 사용자 수정값에서 지원하는 복약 시간대만 정해진 순서로 읽는다.
  static List<String> _readScheduleSlotKeys(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final requestedSlotKeys = value
        .map(_readString)
        .map(/* 함수이름: map 콜백
         * 함수역할: 복약 시간대 키를 소문자로 통일한다.
         * 매개변수:
         * - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
         * 반환값:
         * - 소문자로 정규화한 시간대 키.
         */(slotKey) => slotKey.toLowerCase())
        .where(medicationScheduleSlotKeys.contains)
        .toSet();
    return medicationScheduleSlotKeys
        .where(requestedSlotKeys.contains)
        .toList(growable: false);
  }

  // 함수이름: _readDate
  // 함수역할: 날짜 텍스트를 DateTime으로 해석하고 빈 값이나 올바르지 않은 날짜는 null로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - DateTime?: 날짜 텍스트를 DateTime으로 해석하고 빈 값이나 올바르지 않은 날짜는 null로 처리한다.
  static DateTime? _readDate(dynamic value) {
    final text = _readString(value);
    if (text.isEmpty || text == '정보 없음') {
      return null;
    }
    return DateTime.tryParse(text);
  }

  // 함수이름: _formatDate
  // 함수역할: 달력 날짜를 YYYY-MM-DD 형식으로 맞추고 날짜가 없으면 null을 유지한다.
  // 매개변수:
  // - value (DateTime?): 직렬화할 선택적 달력 날짜
  // 반환값:
  // - String?: YYYY-MM-DD 형식의 날짜; 입력 날짜가 없으면 null.
  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
