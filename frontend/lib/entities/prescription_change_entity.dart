// 파일명: prescription_change_entity.dart
// 역할: 이전 처방과 현재 처방의 비교 결과를 표현한다.

// 열거형명: PrescriptionChangeType
// 역할: 화면에서 구분할 처방 변화 유형을 정의한다.
enum PrescriptionChangeType { added, missing, scheduleChanged, unknown }

// 열거형명: PrescriptionComparisonStatus
// 역할: 이전 처방을 비교하지 못한 이유와 비교 가능 상태를 구분한다.
enum PrescriptionComparisonStatus { comparable, noHistory, expired, unrelated }

// 클래스명: PrescriptionScheduleSnapshot
// 역할: 처방 변화 전후의 용량, 횟수, 기간 값을 보관한다.
class PrescriptionScheduleSnapshot {
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;

  const PrescriptionScheduleSnapshot({
    this.dosagePerTime = '',
    this.dailyFrequency = '',
    this.totalDays = '',
  });

  // 함수이름: PrescriptionScheduleSnapshot.fromJson
  // 함수역할:
  // - 백엔드의 복약 일정 JSON을 일정 스냅샷으로 변환한다.
  // 매개변수:
  // - json: 복약 일정 필드를 포함한 JSON 객체
  // 반환값:
  // - 변환된 PrescriptionScheduleSnapshot
  factory PrescriptionScheduleSnapshot.fromJson(Map<String, dynamic> json) {
    return PrescriptionScheduleSnapshot(
      dosagePerTime: _readString(json['dosage_per_time']),
      dailyFrequency: _readString(json['daily_frequency']),
      totalDays: _readString(json['total_days']),
    );
  }

  // 함수이름: valueForField
  // 함수역할:
  // - 백엔드 필드명에 대응하는 일정 값을 반환한다.
  // 매개변수:
  // - fieldName: 조회할 snake_case 일정 필드명
  // 반환값:
  // - 대응하는 일정 문자열 또는 알 수 없는 필드이면 빈 문자열
  String valueForField(String fieldName) {
    return switch (fieldName) {
      'dosage_per_time' => dosagePerTime,
      'daily_frequency' => dailyFrequency,
      'total_days' => totalDays,
      _ => '',
    };
  }
}

// 클래스명: PrescriptionMedicationChange
// 역할: 약품 한 건에서 발견된 처방 변화를 보관한다.
class PrescriptionMedicationChange {
  final PrescriptionChangeType type;
  final String itemName;
  final List<String> changedFields;
  final PrescriptionScheduleSnapshot? previous;
  final PrescriptionScheduleSnapshot? current;

  const PrescriptionMedicationChange({
    required this.type,
    required this.itemName,
    this.changedFields = const [],
    this.previous,
    this.current,
  });

  // 함수이름: PrescriptionMedicationChange.fromJson
  // 함수역할:
  // - 백엔드의 약품별 변화 JSON을 화면 Entity로 변환한다.
  // 매개변수:
  // - json: 변화 유형과 전후 일정 정보를 포함한 JSON 객체
  // 반환값:
  // - 변환된 PrescriptionMedicationChange
  factory PrescriptionMedicationChange.fromJson(Map<String, dynamic> json) {
    return PrescriptionMedicationChange(
      type: _readChangeType(json['change_type']),
      itemName: _readString(json['item_name']),
      changedFields: _readStringList(json['changed_fields']),
      previous: _readSnapshot(json['previous']),
      current: _readSnapshot(json['current']),
    );
  }
}

// 클래스명: PrescriptionChangeSummary
// 역할: 처방 변화 유형별 개수를 보관한다.
class PrescriptionChangeSummary {
  final int addedCount;
  final int missingCount;
  final int scheduleChangedCount;
  final int unchangedCount;

  const PrescriptionChangeSummary({
    this.addedCount = 0,
    this.missingCount = 0,
    this.scheduleChangedCount = 0,
    this.unchangedCount = 0,
  });

  // 함수이름: PrescriptionChangeSummary.fromJson
  // 함수역할:
  // - 백엔드의 변화 유형별 개수 JSON을 요약 Entity로 변환한다.
  // 매개변수:
  // - json: 추가·미확인·일정 변경·유지 개수를 포함한 JSON 객체
  // 반환값:
  // - 변환된 PrescriptionChangeSummary
  factory PrescriptionChangeSummary.fromJson(Map<String, dynamic> json) {
    return PrescriptionChangeSummary(
      addedCount: _readInt(json['added_count']),
      missingCount: _readInt(json['missing_count']),
      scheduleChangedCount: _readInt(json['schedule_changed_count']),
      unchangedCount: _readInt(json['unchanged_count']),
    );
  }

  int get changeCount => addedCount + missingCount + scheduleChangedCount;
}

// 클래스명: PrescriptionChangeRadar
// 역할: 처방 변화 레이더 화면에 필요한 비교 기준일, 요약, 상세 변화를 보관한다.
class PrescriptionChangeRadar {
  final bool hasPreviousPrescription;
  final PrescriptionComparisonStatus comparisonStatus;
  final int comparisonWindowDays;
  final double? similarityScore;
  final String matchBasis;
  final DateTime? previousPrescriptionDate;
  final DateTime? currentPrescriptionDate;
  final PrescriptionChangeSummary summary;
  final List<PrescriptionMedicationChange> changes;

  const PrescriptionChangeRadar({
    required this.hasPreviousPrescription,
    this.comparisonStatus = PrescriptionComparisonStatus.comparable,
    this.comparisonWindowDays = 90,
    this.similarityScore,
    this.matchBasis = '',
    this.previousPrescriptionDate,
    this.currentPrescriptionDate,
    this.summary = const PrescriptionChangeSummary(),
    this.changes = const [],
  });

  // 함수이름: PrescriptionChangeRadar.fromJson
  // 함수역할:
  // - 비교 상태와 약품별 변화가 포함된 백엔드 응답을 화면 Entity로 변환한다.
  // 매개변수:
  // - json: 처방 변화 레이더 응답 JSON
  // 반환값:
  // - 변환된 PrescriptionChangeRadar
  factory PrescriptionChangeRadar.fromJson(Map<String, dynamic> json) {
    final rawSummary = json['summary'];
    final rawChanges = json['changes'];
    return PrescriptionChangeRadar(
      hasPreviousPrescription: json['has_previous_prescription'] == true,
      comparisonStatus: _readComparisonStatus(
        json['comparison_status'],
        hasPreviousPrescription: json['has_previous_prescription'] == true,
      ),
      comparisonWindowDays: _readInt(json['comparison_window_days']) == 0
          ? 90
          : _readInt(json['comparison_window_days']),
      similarityScore: _readDouble(json['similarity_score']),
      matchBasis: _readString(json['match_basis']),
      previousPrescriptionDate: _readDate(json['previous_prescription_date']),
      currentPrescriptionDate: _readDate(json['current_prescription_date']),
      summary: rawSummary is Map
          ? PrescriptionChangeSummary.fromJson(
              Map<String, dynamic>.from(rawSummary),
            )
          : const PrescriptionChangeSummary(),
      changes: rawChanges is List
          ? rawChanges
                .whereType<Map>()
                .map(
                  (item) => PrescriptionMedicationChange.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  bool get hasChanges => summary.changeCount > 0;
}

// 함수이름: _readComparisonStatus
// 함수역할:
// - 백엔드 비교 상태를 열거형으로 변환하고 이전 응답 형식도 지원한다.
// 매개변수:
// - value: 백엔드의 comparison_status 값
// - hasPreviousPrescription: 이전 응답 형식의 비교 가능 여부
// 반환값:
// - 화면에서 사용할 PrescriptionComparisonStatus
PrescriptionComparisonStatus _readComparisonStatus(
  dynamic value, {
  required bool hasPreviousPrescription,
}) {
  return switch (_readString(value)) {
    'comparable' => PrescriptionComparisonStatus.comparable,
    'expired' => PrescriptionComparisonStatus.expired,
    'unrelated' => PrescriptionComparisonStatus.unrelated,
    'no_history' => PrescriptionComparisonStatus.noHistory,
    _ =>
      hasPreviousPrescription
          ? PrescriptionComparisonStatus.comparable
          : PrescriptionComparisonStatus.noHistory,
  };
}

// 함수이름: _readChangeType
// 함수역할:
// - 백엔드의 변화 유형 문자열을 화면 열거형으로 변환한다.
// 매개변수:
// - value: 백엔드의 change_type 값
// 반환값:
// - 화면에서 사용할 PrescriptionChangeType
PrescriptionChangeType _readChangeType(dynamic value) {
  return switch (_readString(value)) {
    'added' => PrescriptionChangeType.added,
    'missing' => PrescriptionChangeType.missing,
    'schedule_changed' => PrescriptionChangeType.scheduleChanged,
    _ => PrescriptionChangeType.unknown,
  };
}

// 함수이름: _readSnapshot
// 함수역할:
// - 선택적인 JSON 일정 객체를 안전하게 스냅샷으로 변환한다.
// 매개변수:
// - value: 스냅샷으로 변환할 선택적 JSON 값
// 반환값:
// - 변환된 일정 스냅샷 또는 올바른 객체가 아니면 null
PrescriptionScheduleSnapshot? _readSnapshot(dynamic value) {
  if (value is! Map) {
    return null;
  }
  return PrescriptionScheduleSnapshot.fromJson(
    Map<String, dynamic>.from(value),
  );
}

// 함수이름: _readStringList
// 함수역할:
// - JSON 배열에서 비어 있지 않은 문자열 목록을 읽는다.
// 매개변수:
// - value: 문자열 배열로 변환할 JSON 값
// 반환값:
// - 비어 있지 않은 문자열 목록
List<String> _readStringList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map(_readString)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

// 함수이름: _readString
// 함수역할:
// - 선택적 JSON 값을 앞뒤 공백이 제거된 문자열로 변환한다.
// 매개변수:
// - value: 문자열로 변환할 값
// 반환값:
// - 정리된 문자열 또는 값이 없으면 빈 문자열
String _readString(dynamic value) => value?.toString().trim() ?? '';

// 함수이름: _readInt
// 함수역할:
// - 선택적 JSON 값을 정수로 변환한다.
// 매개변수:
// - value: 정수로 변환할 값
// 반환값:
// - 변환된 정수 또는 변환할 수 없으면 0
int _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(_readString(value)) ?? 0;
}

// 함수이름: _readDouble
// 함수역할:
// - 선택적 JSON 값을 실수로 변환한다.
// 매개변수:
// - value: 실수로 변환할 값
// 반환값:
// - 변환된 실수 또는 변환할 수 없으면 null
double? _readDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(_readString(value));
}

// 함수이름: _readDate
// 함수역할:
// - ISO 날짜 문자열을 DateTime으로 변환한다.
// 매개변수:
// - value: 날짜로 변환할 JSON 값
// 반환값:
// - 변환된 DateTime 또는 값이 올바르지 않으면 null
DateTime? _readDate(dynamic value) {
  final text = _readString(value);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
