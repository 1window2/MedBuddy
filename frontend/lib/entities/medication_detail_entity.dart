// 파일명: medication_detail_entity.dart
// 역할: 서버와 화면 사이에서 사용하는 약 상세 정보 모델을 정의한다.

// 클래스명: MedicationDetail
// 역할: 공공데이터 API 및 저장된 복약 정보 API에서 받은 약 상세 정보를 보관한다.
// 주요 책임:
// - API 응답 JSON을 안전하게 변환한다.
// - 저장 요청에 필요한 JSON payload를 생성한다.
// - 음성 안내에 사용할 텍스트를 조합한다.
import 'medication_image_url_entity.dart';
import 'medication_schedule_entity.dart';

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

  // 함수명: fromJson
  // 함수역할:
  // - 서버 응답의 snake_case 필드를 Dart 모델의 camelCase 필드로 변환한다.
  // - 일부 과거 필드명도 함께 읽어 API 응답 변화에 대응한다.
  // 매개변수:
  // - json: 서버에서 받은 약 상세 정보 JSON
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

  // 함수명: copyWith
  // 함수역할:
  // - 서버 응답으로 만든 약 정보에 기기 내부 사진처럼 화면 전용 값을 덧붙인다.
  // - 지정하지 않은 값은 원본을 그대로 유지한다.
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

  // 함수명: toSaveJson
  // 함수역할:
  // - 저장 API가 기대하는 필드명으로 약 상세 정보를 변환한다.
  // 반환값:
  // - 저장 요청에 사용할 JSON Map
  Map<String, dynamic> toSaveJson() {
    return {
      'patient_hash': patientHash,
      'prescription_date': _formatDate(prescriptionDate),
      'item_seq': itemSeq,
      'item_name': itemName,
      'efficacy': efficacy,
      'use_method': usageMethod,
      'warning_message': warning,
      'dosage_per_time': dosagePerTime,
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
      'image_url': safeMedicationImageUrl(imageUrl),
      'ai_guide': aiGuide,
    };
  }

  String get displayName {
    final normalizedName = itemName.trim();
    return normalizedName.isEmpty ? '약품명 확인 필요' : normalizedName;
  }

  // 함수명: displayNameForLanguage
  // 역할:
  // - 약 이름이 비어 있을 때 현재 앱 언어에 맞는 확인 문구를 반환한다.
  String displayNameForLanguage(String language) {
    final normalizedName = itemName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    return _isEnglish(language) ? 'Medication name needs review' : '약품명 확인 필요';
  }

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

  // 함수명: isActiveOn
  // 역할:
  // - 조제일자와 총 투약일을 기준으로 기준 날짜에 복용 중인 약인지 판단한다.
  // - 기간 정보가 부족한 기존 저장 데이터는 목록에서 사라지지 않도록 복용 중으로 취급한다.
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

  List<String> get detailedDosageGuideLines {
    return detailedDosageGuideLinesForLanguage('ko');
  }

  // 함수명: detailedDosageGuideLinesForLanguage
  // 역할:
  // - OCR 복용 정보를 앱 언어에 맞는 시간대와 기간 문구로 조합한다.
  List<String> detailedDosageGuideLinesForLanguage(String language) {
    final isEnglish = _isEnglish(language);
    final dosage = dosagePerTime.trim().isEmpty
        ? (isEnglish ? 'Dose unavailable' : '복용량 정보 없음')
        : _localizedDosageValue(dosagePerTime, language);
    final slotLabels = _slotLabelsFromFrequency(dailyFrequency, language);
    final lines = slotLabels.map((slot) => '$slot: $dosage').toList();

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

  // 속성명: compactDosageGuideLines
  // 역할:
  // - 기존 호출부 호환을 위해 한국어 기준의 간단한 복용 정보를 반환한다.
  List<String> get compactDosageGuideLines {
    return compactDosageGuideLinesForLanguage('ko');
  }

  // 함수명: compactDosageGuideLinesForLanguage
  // 역할:
  // - 약 상세 카드의 복용량, 횟수, 기간, 시점을 앱 언어에 맞게 구성한다.
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

  String get voiceGuideText {
    return voiceGuideTextForLanguage('ko');
  }

  // 함수명: voiceGuideTextForLanguage
  // 역할:
  // - 서버 음성 안내를 사용할 수 없을 때 재생할 최소 안내를 앱 언어로 만든다.
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

  static String _normalizeOrFallback(String value, String fallback) {
    final normalizedValue = value.trim();
    return normalizedValue.isEmpty ? fallback : normalizedValue;
  }

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

  static bool _isEnglish(String language) {
    return language.trim().toLowerCase() == 'en';
  }

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

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int? _readInt(dynamic value) {
    final count = medicationScheduleCountFromText(value);
    return count == 0 ? null : count;
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
