import 'medication_detail_entity.dart';
import 'medication_schedule_entity.dart';

// 파일명: medication_guide_entity.dart
// 역할: 저장 목록과 오늘 일정에서 공통으로 쓰는 약 상세 안내 데이터를 정의한다.

// 클래스명: MedicationGuide
// 역할: 약 상세정보 화면과 음성 안내에 필요한 정보를 한 형식으로 묶는다.
// 주요 책임:
// - 저장된 복약 정보와 오늘 복약 일정을 같은 UI 모델로 변환한다.
// - 처방전에서 추출한 복용량, 횟수, 일수를 바탕으로 상세 복용 가이드를 만든다.
// - TTS가 읽을 약 이름, 상세 복용 안내, 주의사항 문장을 조합한다.
class MedicationGuide {
  final String itemName;
  final String efficacy;
  final String usageMethod;
  final String warning;
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;
  final String imageUrl;
  final String aiGuide;

  const MedicationGuide({
    required this.itemName,
    required this.efficacy,
    required this.usageMethod,
    required this.warning,
    this.dosagePerTime = '',
    this.dailyFrequency = '',
    this.totalDays = '',
    this.imageUrl = '',
    this.aiGuide = '',
  });

  factory MedicationGuide.fromMedicationDetail(MedicationDetail medication) {
    return MedicationGuide(
      itemName: medication.itemName,
      efficacy: medication.efficacy,
      usageMethod: medication.usageMethod,
      warning: medication.warning,
      dosagePerTime: medication.dosagePerTime,
      dailyFrequency: medication.dailyFrequency,
      totalDays: medication.totalDays,
      imageUrl: medication.imageUrl,
      aiGuide: medication.aiGuide,
    );
  }

  factory MedicationGuide.fromMedicationSchedule(MedicationSchedule schedule) {
    return MedicationGuide(
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
      lines.add('$period 복용하세요');
    }
    if (lines.isEmpty) {
      lines.add('처방전에서 추출한 상세 복용 정보가 없습니다.');
    }
    return lines;
  }

  String get voiceGuideText {
    final sections = [
      displayName,
      if (efficacy.trim().isNotEmpty) '효능. ${efficacy.trim()}',
      if (usageMethod.trim().isNotEmpty) '복용 방법. ${usageMethod.trim()}',
      '상세 복용 가이드. ${detailedDosageGuideLines.join('. ')}',
      '주의사항. ${_normalizeOrFallback(warning, '정보 없음')}',
      if (aiGuide.trim().isNotEmpty) '추가 안내. ${aiGuide.trim()}',
    ];
    return sections.join('\n');
  }

  static String _normalizeOrFallback(String value, String fallback) {
    final normalizedValue = value.trim();
    return normalizedValue.isEmpty ? fallback : normalizedValue;
  }

  static List<String> _slotLabelsFromFrequency(String dailyFrequency) {
    final frequencyCount = _readInt(dailyFrequency);
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

  static int _readInt(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(0) ?? '') ?? 0;
  }
}
