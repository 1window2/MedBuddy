// 파일명: medication_detail_entity.dart
// 역할: 서버와 화면 사이에서 사용하는 약 상세 정보 모델을 정의한다.

import 'medication_image_url_entity.dart';
import 'medication_schedule_entity.dart';

// Class Name: MedicationDetail
// Role: Holds public-catalog and saved-medication detail fields for display and persistence.
// Responsibilities:
// - Decode current and legacy keys, constrain remote image URLs, generate save payloads, and derive localized dosage and voice guidance.
// Attributes:
// - id (int?): Server-assigned saved-medication identifier.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - itemSeq (String): Public-catalog medication item identifier.
// - createdDate (DateTime?): Creation date of the saved medication or course.
// - prescriptionDate (DateTime?): Dispensing or prescription date used as the course start.
// - itemName (String): Medication name used for display and persistence.
// - efficacy (String): Public-catalog medication efficacy description.
// - usageMethod (String): Original medication usage and intake-timing instructions.
// - warning (String): Important medication warning text.
// - precaution (String): Detailed medication precautions.
// - interaction (String): Medication interaction guidance.
// - sideEffect (String): Public-catalog adverse-effect guidance.
// - storageMethod (String): Medication storage guidance.
// - dosagePerTime (String): Dose per intake including its unit.
// - dailyFrequency (String): Daily intake-frequency text from the prescription.
// - totalDays (String): Total course-duration text from the prescription.
// - imageUrl (String): Remote image URL associated with medication details or a candidate.
// - localImagePath (String): Device-only medication photo path, never sent to the backend.
// - aiGuide (String): AI guidance retained with medication details.
class MedicationDetail {
  final int? id;
  final String patientHash;
  final String itemSeq;
  final DateTime? createdDate;
  final DateTime? prescriptionDate;
  final String itemName;
  final String efficacy;
  final String usageMethod;
  final String warning;
  final String precaution;
  final String interaction;
  final String sideEffect;
  final String storageMethod;
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;
  final String imageUrl;
  final String localImagePath;
  final String aiGuide;

  // 함수이름: MedicationDetail
  // 함수역할: 약의 품목·효능·복용법·주의사항과 처방 기간 및 원격·기기 사진 정보를 상세 화면용 값으로 보존한다.
  // 매개변수:
  // - id (int?): 서버에 저장된 약의 식별자
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - itemSeq (String): 공공데이터의 약 품목번호
  // - createdDate (DateTime?): 저장 약 또는 일정의 생성 날짜
  // - prescriptionDate (DateTime?): 복용 시작 기준으로 사용할 조제·처방 날짜
  // - itemName (String): 화면과 저장에 사용할 약 이름
  // - efficacy (String): 공공데이터의 약 효능 설명
  // - usageMethod (String): 약의 용법·복용 시점 원문
  // - warning (String): 약 복용 시 중요한 경고 문구
  // - precaution (String): 약품 사용 시 세부 주의사항
  // - interaction (String): 병용 상호작용 안내
  // - sideEffect (String): 공공데이터의 부작용 안내
  // - storageMethod (String): 약 보관 방법 안내
  // - dosagePerTime (String): 단위를 포함한 1회 복용량
  // - dailyFrequency (String): 처방에 기록된 하루 복용 횟수 문자열
  // - totalDays (String): 처방에 기록된 총 복용 일수 문자열
  // - imageUrl (String): 약 상세·후보에 포함된 원격 이미지 주소
  // - localImagePath (String): 서버에 전송하지 않는 기기 전용 약 사진 경로
  // - aiGuide (String): 약 상세에 보존할 AI 안내 문구
  // 반환값:
  // - MedicationDetail: 초기화된 인스턴스.
  const MedicationDetail({
    this.id,
    this.patientHash = '',
    this.itemSeq = '',
    this.createdDate,
    this.prescriptionDate,
    required this.itemName,
    required this.efficacy,
    required this.usageMethod,
    required this.warning,
    this.precaution = '',
    this.interaction = '',
    this.sideEffect = '',
    this.storageMethod = '',
    this.dosagePerTime = '',
    this.dailyFrequency = '',
    this.totalDays = '',
    this.imageUrl = '',
    this.localImagePath = '',
    this.aiGuide = '',
  });

  // 함수이름: MedicationDetail.fromJson
  // 함수역할: 서버 응답의 snake_case 필드를 Dart 모델의 camelCase 필드로 변환한다. 일부 과거 필드명도 함께 읽어 API 응답 변화에 대응한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 서버에서 받은 약 상세 정보 JSON
  // 반환값:
  // - MedicationDetail 인스턴스
  factory MedicationDetail.fromJson(Map<String, dynamic> json) {
    return MedicationDetail(
      id: _readInt(json['id']),
      patientHash: _readString(json['patient_hash']),
      itemSeq: _readString(json['item_seq'] ?? json['itemSeq']),
      createdDate: _readDate(json['created_date'] ?? json['createdDate']),
      prescriptionDate: _readDate(
        json['prescription_date'] ?? json['prescriptionDate'],
      ),
      itemName: _readString(json['item_name']),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['usage_method'] ?? json['use_method']),
      warning: _readString(json['warning'] ?? json['warning_message']),
      precaution: _readString(json['precaution']),
      interaction: _readString(json['interaction']),
      sideEffect: _readString(json['side_effect']),
      storageMethod: _readString(json['storage_method']),
      dosagePerTime: _readString(json['dosage_per_time']),
      dailyFrequency: _readString(json['daily_frequency']),
      totalDays: _readString(json['total_days']),
      imageUrl: safeMedicationImageUrl(json['image_url'] ?? json['itemImage']),
      localImagePath: '',
      aiGuide: _readString(json['ai_guide']),
    );
  }

  // Function Name: MedicationDetail.fromMedicationSchedule
  // Description: Builds a detail fallback from a schedule's name, dosage, duration, and optional catalog fields while applying the trusted-image URL policy.
  // Parameters:
  // - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
  // Returns:
  // - MedicationDetail: the initialized instance.
  factory MedicationDetail.fromMedicationSchedule(MedicationSchedule schedule) {
    return MedicationDetail(
      itemName: schedule.displayName,
      efficacy: schedule.efficacy ?? '',
      usageMethod: schedule.usageMethod ?? '',
      warning: schedule.warning ?? '',
      dosagePerTime: schedule.dosage,
      dailyFrequency: schedule.intakeTime,
      totalDays: schedule.medicationTimeLabel,
      imageUrl: safeMedicationImageUrl(schedule.imageUrl),
    );
  }

  // 함수이름: copyWith
  // 함수역할: 서버 응답으로 만든 약 정보에 기기 내부 사진처럼 화면 전용 값을 덧붙인다. 지정하지 않은 값은 원본을 그대로 유지한다.
  // 매개변수:
  // - id (int?): 서버에 저장된 약의 식별자
  // - patientHash (String?): 조회·저장·알림 대상 환자의 소유권 해시
  // - itemSeq (String?): 공공데이터의 약 품목번호
  // - createdDate (DateTime?): 저장 약 또는 일정의 생성 날짜
  // - prescriptionDate (DateTime?): 복용 시작 기준으로 사용할 조제·처방 날짜
  // - itemName (String?): 화면과 저장에 사용할 약 이름
  // - efficacy (String?): 공공데이터의 약 효능 설명
  // - usageMethod (String?): 약의 용법·복용 시점 원문
  // - warning (String?): 약 복용 시 중요한 경고 문구
  // - precaution (String?): 약품 사용 시 세부 주의사항
  // - interaction (String?): 병용 상호작용 안내
  // - sideEffect (String?): 공공데이터의 부작용 안내
  // - storageMethod (String?): 약 보관 방법 안내
  // - dosagePerTime (String?): 단위를 포함한 1회 복용량
  // - dailyFrequency (String?): 처방에 기록된 하루 복용 횟수 문자열
  // - totalDays (String?): 처방에 기록된 총 복용 일수 문자열
  // - imageUrl (String?): 약 상세·후보에 포함된 원격 이미지 주소
  // - localImagePath (String?): 서버에 전송하지 않는 기기 전용 약 사진 경로
  // - aiGuide (String?): 약 상세에 보존할 AI 안내 문구
  // 반환값:
  // - MedicationDetail: 지정한 필드만 교체하고 나머지 값을 유지한 사본.
  MedicationDetail copyWith({
    int? id,
    String? patientHash,
    String? itemSeq,
    DateTime? createdDate,
    DateTime? prescriptionDate,
    String? itemName,
    String? efficacy,
    String? usageMethod,
    String? warning,
    String? precaution,
    String? interaction,
    String? sideEffect,
    String? storageMethod,
    String? dosagePerTime,
    String? dailyFrequency,
    String? totalDays,
    String? imageUrl,
    String? localImagePath,
    String? aiGuide,
  }) {
    return MedicationDetail(
      id: id ?? this.id,
      patientHash: patientHash ?? this.patientHash,
      itemSeq: itemSeq ?? this.itemSeq,
      createdDate: createdDate ?? this.createdDate,
      prescriptionDate: prescriptionDate ?? this.prescriptionDate,
      itemName: itemName ?? this.itemName,
      efficacy: efficacy ?? this.efficacy,
      usageMethod: usageMethod ?? this.usageMethod,
      warning: warning ?? this.warning,
      precaution: precaution ?? this.precaution,
      interaction: interaction ?? this.interaction,
      sideEffect: sideEffect ?? this.sideEffect,
      storageMethod: storageMethod ?? this.storageMethod,
      dosagePerTime: dosagePerTime ?? this.dosagePerTime,
      dailyFrequency: dailyFrequency ?? this.dailyFrequency,
      totalDays: totalDays ?? this.totalDays,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      aiGuide: aiGuide ?? this.aiGuide,
    );
  }

  // Function Name: toSaveJson
  // Description: Serializes patient-owned medication details for the save API, formats the prescription date, validates the remote image URL, and excludes the device-only photo path.
  // Parameters:
  // - None.
  // Returns:
  // - Map<String, dynamic>: Serializes patient-owned medication details for the save API, formats the prescription date, validates the remote image URL, and excludes the device-only photo path.
  Map<String, dynamic> toSaveJson() {
    return {
      'patient_hash': patientHash,
      'prescription_date': _formatDate(prescriptionDate),
      'item_seq': itemSeq,
      'item_name': itemName,
      'efficacy': efficacy,
      'use_method': usageMethod,
      'warning_message': warning,
      'interaction': interaction,
      'side_effect': sideEffect,
      'storage_method': storageMethod,
      'dosage_per_time': dosagePerTime,
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
      'image_url': safeMedicationImageUrl(imageUrl),
      'ai_guide': aiGuide,
    };
  }

  // Function Name: displayName
  // Description: Exposes the trimmed medication name, using the existing Korean review label when it is blank.
  // Parameters:
  // - None.
  // Returns:
  // - String: The trimmed medication name, using the existing Korean review label when it is blank.
  String get displayName {
    final normalizedName = itemName.trim();
    return normalizedName.isEmpty ? '약품명 확인 필요' : normalizedName;
  }

  // 함수이름: displayNameForLanguage
  // 함수역할: 약 이름이 비어 있을 때 현재 앱 언어에 맞는 확인 문구를 반환한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 약 이름이 비어 있을 때 현재 앱 언어에 맞는 확인 문구를 반환한다.
  String displayNameForLanguage(String language) {
    final normalizedName = itemName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    return _isEnglish(language) ? 'Medication name needs review' : '약품명 확인 필요';
  }

  // 함수이름: medicationEndDate
  // 함수역할: 조제일과 양수 투약일을 기준으로 시작일을 포함한 복용 종료일을 계산하고 기간이 부족하면 null을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - DateTime?: 조제일과 양수 투약일을 기준으로 시작일을 포함한 복용 종료일을 계산하고 기간이 부족하면 null을 제공한다.
  DateTime? get medicationEndDate {
    final startDate = prescriptionDate;
    final dayCount = medicationScheduleCountFromText(totalDays);
    if (startDate == null || dayCount <= 0) {
      return null;
    }
    return DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    ).add(Duration(days: dayCount - 1));
  }

  // 함수이름: isActiveOn
  // 함수역할: 조제일자와 총 투약일을 기준으로 기준 날짜에 복용 중인 약인지 판단한다. 기간 정보가 부족한 기존 저장 데이터는 목록에서 사라지지 않도록 복용 중으로 취급한다.
  // 매개변수:
  // - referenceDate (DateTime): 달력 날짜 계산 또는 비교의 기준 시각
  // 반환값:
  // - bool: 조제일자와 총 투약일을 기준으로 기준 날짜에 복용 중인 약인지 판단한다. 기간 정보가 부족한 기존 저장 데이터는 목록에서 사라지지 않도록 복용 중으로 취급한다.
  bool isActiveOn(DateTime referenceDate) {
    final startDate = prescriptionDate;
    final endDate = medicationEndDate;
    if (startDate == null || endDate == null) {
      return true;
    }
    final normalizedReference = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    return !normalizedReference.isBefore(normalizedStart) &&
        !normalizedReference.isAfter(endDate);
  }

  // 함수이름: detailedDosageGuideLines
  // 함수역할: 한국어 기본 표시용으로 시간대별 복용량과 투약 기간을 상세 안내 목록으로 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<String>: 한국어 기본 표시용으로 시간대별 복용량과 투약 기간을 상세 안내 목록으로 구성한다.
  List<String> get detailedDosageGuideLines {
    return detailedDosageGuideLinesForLanguage('ko');
  }

  // 함수이름: detailedDosageGuideLinesForLanguage
  // 함수역할: OCR 복용 정보를 앱 언어에 맞는 시간대와 기간 문구로 조합한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - List<String>: OCR 복용 정보를 앱 언어에 맞는 시간대와 기간 문구로 조합한다.
  List<String> detailedDosageGuideLinesForLanguage(String language) {
    final isEnglish = _isEnglish(language);
    final dosage = dosagePerTime.trim().isEmpty
        ? (isEnglish ? 'Dose unavailable' : '복용량 정보 없음')
        : _localizedDosageValue(dosagePerTime, language);
    final slotLabels = _slotLabelsFromFrequency(dailyFrequency, language);
    final lines = slotLabels.map(/* Function Name: map callback
     * Description: Combines each medication slot label with the per-dose quantity.
     * Parameters:
     * - slot (String): Medication time-slot label to display.
     * Returns:
     * - A slot-and-dosage display segment.
     */(slot) => '$slot: $dosage').toList();

    final period = totalDays.trim();
    if (period.isNotEmpty) {
      final localizedPeriod = _localizedDurationValue(period, language);
      lines.add(
        isEnglish ? 'Take for $localizedPeriod.' : '$localizedPeriod 복용하세요.',
      );
    }
    if (lines.isEmpty) {
      lines.add(
        isEnglish
            ? 'No detailed dosage information was extracted.'
            : '처방전에서 추출된 상세 복용 정보가 없습니다.',
      );
    }
    return lines;
  }

  // 함수이름: compactDosageGuideLines
  // 함수역할: 기존 호출부 호환을 위해 한국어 기준의 간단한 복용 정보를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<String>: 기존 호출부 호환을 위해 한국어 기준의 간단한 복용 정보를 반환한다.
  List<String> get compactDosageGuideLines {
    return compactDosageGuideLinesForLanguage('ko');
  }

  // 함수이름: compactDosageGuideLinesForLanguage
  // 함수역할: 약 상세 카드의 복용량, 횟수, 기간, 시점을 앱 언어에 맞게 구성한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - List<String>: 약 상세 카드의 복용량, 횟수, 기간, 시점을 앱 언어에 맞게 구성한다.
  List<String> compactDosageGuideLinesForLanguage(String language) {
    final isEnglish = _isEnglish(language);
    final lines = <String>[];
    if (dosagePerTime.trim().isNotEmpty) {
      final dosage = _localizedDosageValue(dosagePerTime, language);
      lines.add(isEnglish ? 'Dose per intake · $dosage' : '1회 복용량 · $dosage');
    }
    if (dailyFrequency.trim().isNotEmpty) {
      final frequency = _localizedFrequencyValue(dailyFrequency, language);
      lines.add(
        isEnglish ? 'Daily frequency · $frequency' : '복용 횟수 · $frequency',
      );
    }
    if (totalDays.trim().isNotEmpty) {
      final duration = _localizedDurationValue(totalDays, language);
      lines.add(isEnglish ? 'Duration · $duration' : '복용 기간 · $duration');
    }
    final timing = _readDosageTiming(usageMethod);
    if (timing != null) {
      final localizedTiming = _localizedTiming(timing, language);
      lines.add(
        isEnglish
            ? 'When to take · $localizedTiming'
            : '복용 시점 · $localizedTiming',
      );
    }
    if (lines.isNotEmpty) {
      return lines;
    }
    return [isEnglish ? 'No dosage information' : '복용 정보 없음'];
  }

  // 함수이름: voiceGuideText
  // 함수역할: 서버 안내를 사용할 수 없을 때 쓸 한국어 기본 복용법·주의사항 음성 안내문을 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 서버 안내를 사용할 수 없을 때 쓸 한국어 기본 복용법·주의사항 음성 안내문을 구성한다.
  String get voiceGuideText {
    return voiceGuideTextForLanguage('ko');
  }

  // 함수이름: voiceGuideTextForLanguage
  // 함수역할: 서버 음성 안내를 사용할 수 없을 때 재생할 최소 안내를 앱 언어로 만든다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 서버 음성 안내를 사용할 수 없을 때 재생할 최소 안내를 앱 언어로 만든다.
  String voiceGuideTextForLanguage(String language) {
    final isEnglish = _isEnglish(language);
    final sections = [
      displayNameForLanguage(language),
      if (usageMethod.trim().isNotEmpty)
        isEnglish
            ? 'How to take it. ${usageMethod.trim()}'
            : '복용 방법. ${usageMethod.trim()}',
      isEnglish
          ? 'Warnings. ${_normalizeOrFallback(warning, 'No information')}'
          : '주의사항. ${_normalizeOrFallback(warning, '정보 없음')}',
    ];
    return sections.join('\n');
  }

  // Function Name: _normalizeOrFallback
  // Description: Trims a supplied detail string and uses the caller's fallback when no visible text remains.
  // Parameters:
  // - value (String): Medication text checked before substituting fallback guidance.
  // - fallback (String): Fallback for absent or unparseable input.
  // Returns:
  // - String: Trims a supplied detail string and uses the caller's fallback when no visible text remains.
  static String _normalizeOrFallback(String value, String fallback) {
    final normalizedValue = value.trim();
    return normalizedValue.isEmpty ? fallback : normalizedValue;
  }

  // 함수이름: _slotLabelsFromFrequency
  // 함수역할: 1일 복용 횟수를 언어별 아침·점심·저녁·취침 전 시간대 이름으로 바꾸고 해석 불가 횟수는 빈 목록으로 처리한다.
  // 매개변수:
  // - dailyFrequency (String): 처방에 기록된 하루 복용 횟수 문자열
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - List<String>: 1일 복용 횟수를 언어별 아침·점심·저녁·취침 전 시간대 이름으로 바꾸고 해석 불가 횟수는 빈 목록으로 처리한다.
  static List<String> _slotLabelsFromFrequency(
    String dailyFrequency,
    String language,
  ) {
    final isEnglish = _isEnglish(language);
    final frequencyCount = _readInt(dailyFrequency) ?? 0;
    if (frequencyCount >= 4) {
      return isEnglish
          ? const ['Morning', 'Lunch', 'Evening', 'Bedtime']
          : const ['아침', '점심', '저녁', '취침 전'];
    }
    if (frequencyCount == 3) {
      return isEnglish
          ? const ['Morning', 'Lunch', 'Evening']
          : const ['아침', '점심', '저녁'];
    }
    if (frequencyCount == 2) {
      return isEnglish ? const ['Morning', 'Evening'] : const ['아침', '저녁'];
    }
    if (frequencyCount == 1) {
      return isEnglish ? const ['Morning'] : const ['아침'];
    }
    return const [];
  }

  // 함수이름: _localizedDosageValue
  // 함수역할: 영문 표시에서 숫자와 정·캡슐·포·방울 단위를 단복수에 맞게 바꾸고 인식하지 못한 용량은 원문으로 보존한다.
  // 매개변수:
  // - value (String): 표시 언어로 바꿀 1회 복용량 원문
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 영문 표시에서 숫자와 정·캡슐·포·방울 단위를 단복수에 맞게 바꾸고 인식하지 못한 용량은 원문으로 보존한다.
  static String _localizedDosageValue(String value, String language) {
    final normalizedValue = value.trim();
    if (!_isEnglish(language)) {
      return normalizedValue;
    }
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(정|캡슐|포|방울)$',
    ).firstMatch(normalizedValue);
    if (match == null) {
      return normalizedValue;
    }
    final amount = match.group(1)!;
    final isSingular = double.tryParse(amount) == 1;
    final unit = switch (match.group(2)) {
      '정' => isSingular ? 'tablet' : 'tablets',
      '캡슐' => isSingular ? 'capsule' : 'capsules',
      '포' => isSingular ? 'packet' : 'packets',
      '방울' => isSingular ? 'drop' : 'drops',
      _ => '',
    };
    return '$amount $unit'.trim();
  }

  // 함수이름: _localizedFrequencyValue
  // 함수역할: 영문 표시에서 숫자로 해석한 하루 횟수를 once daily 또는 times daily 문구로 바꾸고 해석 불가 원문은 유지한다.
  // 매개변수:
  // - value (String): 표시 언어로 바꿀 일일 복용 횟수 원문
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 영문 표시에서 숫자로 해석한 하루 횟수를 once daily 또는 times daily 문구로 바꾸고 해석 불가 원문은 유지한다.
  static String _localizedFrequencyValue(String value, String language) {
    final normalizedValue = value.trim();
    if (!_isEnglish(language)) {
      return normalizedValue;
    }
    final count = _readInt(normalizedValue);
    if (count == null) {
      return normalizedValue;
    }
    return count == 1 ? 'once daily' : '$count times daily';
  }

  // 함수이름: _localizedDurationValue
  // 함수역할: 영문 표시에서 복용 일수를 day·days 문구로 바꾸고 인식하지 못한 기간은 원문으로 보존한다.
  // 매개변수:
  // - value (String): 표시 언어로 바꿀 복용 기간 원문
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 영문 표시에서 복용 일수를 day·days 문구로 바꾸고 인식하지 못한 기간은 원문으로 보존한다.
  static String _localizedDurationValue(String value, String language) {
    final normalizedValue = value.trim();
    if (!_isEnglish(language)) {
      return normalizedValue;
    }
    final days = _readInt(normalizedValue);
    if (days == null) {
      return normalizedValue;
    }
    return days == 1 ? '1 day' : '$days days';
  }

  // 함수이름: _localizedTiming
  // 함수역할: 지원하는 식전·식후·공복·취침 전 문구만 영어로 변환하고 그 외 복용 시점은 그대로 유지한다.
  // 매개변수:
  // - timing (String): 식전·식후·공복 등 인식한 복용 시점
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 지원하는 식전·식후·공복·취침 전 문구만 영어로 변환하고 그 외 복용 시점은 그대로 유지한다.
  static String _localizedTiming(String timing, String language) {
    if (!_isEnglish(language)) {
      return timing;
    }
    return switch (timing) {
      '식사 직전' => 'immediately before meals',
      '식사 직후' => 'immediately after meals',
      '식전' => 'before meals',
      '식후' => 'after meals',
      '공복' => 'on an empty stomach',
      '취침 전' => 'at bedtime',
      _ => timing,
    };
  }

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en과 정확히 같은지 확인한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - bool: 언어 코드의 공백과 대소문자를 정리한 뒤 en과 정확히 같은지 확인한다.
  static bool _isEnglish(String language) {
    return language.trim().toLowerCase() == 'en';
  }

  // Function Name: _readDosageTiming
  // Description: Finds the first supported meal or bedtime timing phrase in usage instructions and normalizes the unspaced bedtime spelling.
  // Parameters:
  // - usageMethod (String): Original medication usage and intake-timing instructions.
  // Returns:
  // - String?: Finds the first supported meal or bedtime timing phrase in usage instructions and normalizes the unspaced bedtime spelling.
  static String? _readDosageTiming(String usageMethod) {
    const timingLabels = <String>[
      '식사 직전',
      '식사 직후',
      '식전',
      '식후',
      '공복',
      '취침 전',
      '취침전',
    ];
    for (final timing in timingLabels) {
      if (usageMethod.contains(timing)) {
        return timing == '취침전' ? '취침 전' : timing;
      }
    }
    return null;
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
  // Description: Extracts the final numeric medication count from text, treating a zero or absent count as unavailable.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - int?: Extracts the final numeric medication count from text, treating a zero or absent count as unavailable.
  static int? _readInt(dynamic value) {
    final count = medicationScheduleCountFromText(value);
    return count == 0 ? null : count;
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
