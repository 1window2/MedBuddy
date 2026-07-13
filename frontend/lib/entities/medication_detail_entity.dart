// 파일명: medication_detail_entity.dart
// 역할: 서버와 화면 사이에서 사용하는 약 상세 정보 모델을 정의한다.

// 클래스명: MedicationDetail
// 역할: 공공데이터 API 및 저장된 복약 정보 API에서 받은 약 상세 정보를 보관한다.
// 주요 책임:
// - API 응답 JSON을 안전하게 변환한다.
// - 저장 요청에 필요한 JSON payload를 생성한다.
// - 음성 안내에 사용할 텍스트를 조합한다.
import 'medication_schedule_entity.dart';

class MedicationDetail {
  final int? id;
  final String patientHash;
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
  final String aiGuide;

  const MedicationDetail({
    this.id,
    this.patientHash = '',
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
      imageUrl: _readString(json['image_url'] ?? json['itemImage']),
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
      imageUrl: schedule.imageUrl ?? '',
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
      'item_name': itemName,
      'efficacy': efficacy,
      'use_method': usageMethod,
      'warning_message': warning,
      'dosage_per_time': dosagePerTime,
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
      'image_url': imageUrl,
      'ai_guide': aiGuide,
    };
  }

  bool get hasScheduleInfo {
    return dosagePerTime.trim().isNotEmpty ||
        dailyFrequency.trim().isNotEmpty ||
        totalDays.trim().isNotEmpty;
  }

  String get displayName {
    final normalizedName = itemName.trim();
    return normalizedName.isEmpty ? '약품명 확인 필요' : normalizedName;
  }

  List<String> get detailedDosageGuideLines {
    final dosage = _normalizeOrFallback(dosagePerTime, '복용량 정보 없음');
    final slotLabels = _slotLabelsFromFrequency(dailyFrequency);
    final lines = slotLabels.map((slot) => '$slot: $dosage').toList();

    final period = totalDays.trim();
    if (period.isNotEmpty) {
      lines.add('$period 복용하세요.');
    }
    if (lines.isEmpty) {
      lines.add('처방전에서 추출된 상세 복용 정보가 없습니다.');
    }
    return lines;
  }

  String get voiceGuideText {
    final sections = [
      displayName,
      if (usageMethod.trim().isNotEmpty) '복용 방법. ${usageMethod.trim()}',
      '주의사항. ${_normalizeOrFallback(warning, '정보 없음')}',
    ];
    return sections.join('\n');
  }

  void saveMedicationDetail() {
    throw UnsupportedError('약 상세 정보 저장은 CheckSavedMedication에서 처리합니다.');
  }

  MedicationDetail checkMedicationDetail() {
    return this;
  }

  MedicationDetail getMedicationDetail() {
    return this;
  }

  // 함수명: getVoiceGuideText
  // 함수역할:
  // - 사용자가 들을 수 있는 약 안내 문장을 주요 필드 순서대로 합친다.
  // 반환값:
  // - 빈 값이 제거된 음성 안내 문자열
  String getVoiceGuideText() {
    return voiceGuideText;
  }

  static String _normalizeOrFallback(String value, String fallback) {
    final normalizedValue = value.trim();
    return normalizedValue.isEmpty ? fallback : normalizedValue;
  }

  static List<String> _slotLabelsFromFrequency(String dailyFrequency) {
    final frequencyCount = _readInt(dailyFrequency) ?? 0;
    if (frequencyCount >= 4) {
      return const ['아침', '점심', '저녁', '취침 전'];
    }
    if (frequencyCount == 3) {
      return const ['아침', '점심', '저녁'];
    }
    if (frequencyCount == 2) {
      return const ['아침', '저녁'];
    }
    if (frequencyCount == 1) {
      return const ['아침'];
    }
    return const [];
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
