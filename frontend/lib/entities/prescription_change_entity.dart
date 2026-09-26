// 파일명: prescription_change_entity.dart
// 역할: 이전 처방과 현재 처방의 비교 결과를 표현한다.

// 클래스명: PrescriptionChangeType
// 역할: 약 추가·미확인·일정 변경·알 수 없음 유형을 구분한다.
// 주요 책임:
// - 처방 변화 카드와 요약 집계에서 같은 변화 범주를 사용하게 한다.
enum PrescriptionChangeType { added, missing, scheduleChanged, unknown }

// 클래스명: PrescriptionComparisonStatus
// 역할: 이전 처방의 비교 가능·기간 만료·무관·이력 없음 상태를 구분한다.
// 주요 책임:
// - 화면이 실제 변화와 비교 불가 사유를 혼동하지 않도록 비교 결과를 분류한다.
enum PrescriptionComparisonStatus { comparable, noHistory, expired, unrelated }

// 클래스명: PrescriptionScheduleSnapshot
// 역할: 처방 변화 전후의 용량·횟수·기간을 보관한다.
// 주요 책임:
// - 서버 필드명으로 특정 일정 값을 읽어 전후 비교 행을 구성하게 한다.
// 속성:
// - dosagePerTime (String): 단위를 포함한 1회 복용량
// - dailyFrequency (String): 처방에 기록된 하루 복용 횟수 문자열
// - totalDays (String): 처방에 기록된 총 복용 일수 문자열
class PrescriptionScheduleSnapshot {
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;

  // 함수이름: PrescriptionScheduleSnapshot
  // 함수역할: 한 처방 시점의 1회 용량, 하루 횟수와 총 투약일을 비교용 스냅샷으로 보존한다.
  // 매개변수:
  // - dosagePerTime (String): 단위를 포함한 1회 복용량
  // - dailyFrequency (String): 처방에 기록된 하루 복용 횟수 문자열
  // - totalDays (String): 처방에 기록된 총 복용 일수 문자열
  // 반환값:
  // - PrescriptionScheduleSnapshot: 초기화된 인스턴스.
  const PrescriptionScheduleSnapshot({
    this.dosagePerTime = '',
    this.dailyFrequency = '',
    this.totalDays = '',
  });

  // 함수이름: PrescriptionScheduleSnapshot.fromJson
  // 함수역할: 백엔드의 복약 일정 JSON을 일정 스냅샷으로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 복약 일정 필드를 포함한 JSON 객체
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
  // 함수역할: 백엔드 필드명에 대응하는 일정 값을 반환한다.
  // 매개변수:
  // - fieldName (String): 조회할 snake_case 일정 필드명
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
// 역할: 약품 한 건에서 발견된 변화와 이전·현재 일정을 보관한다.
// 주요 책임:
// - 변경 필드 목록을 전후 스냅샷과 대응시켜 상세 비교를 지원한다.
// 속성:
// - type (PrescriptionChangeType): 약품의 추가·미확인·일정 변경 유형
// - itemName (String): 화면과 저장에 사용할 약 이름
// - changedFields (List<String>): 전후 비교에서 달라진 서버 필드명
// - previous (PrescriptionScheduleSnapshot?): 변경 전 복용량·횟수·기간 스냅샷
// - current (PrescriptionScheduleSnapshot?): 변경 후 복용량·횟수·기간 스냅샷
class PrescriptionMedicationChange {
  final PrescriptionChangeType type;
  final String itemName;
  final List<String> changedFields;
  final PrescriptionScheduleSnapshot? previous;
  final PrescriptionScheduleSnapshot? current;

  // 함수이름: PrescriptionMedicationChange
  // 함수역할: 약품의 변화 유형, 표시 이름, 변경 필드와 선택적인 전후 일정을 한 비교 항목으로 묶는다.
  // 매개변수:
  // - type (PrescriptionChangeType): 약품의 추가·미확인·일정 변경 유형
  // - itemName (String): 화면과 저장에 사용할 약 이름
  // - changedFields (List<String>): 전후 비교에서 달라진 서버 필드명
  // - previous (PrescriptionScheduleSnapshot?): 변경 전 복용량·횟수·기간 스냅샷
  // - current (PrescriptionScheduleSnapshot?): 변경 후 복용량·횟수·기간 스냅샷
  // 반환값:
  // - PrescriptionMedicationChange: 초기화된 인스턴스.
  const PrescriptionMedicationChange({
    required this.type,
    required this.itemName,
    this.changedFields = const [],
    this.previous,
    this.current,
  });

  // 함수이름: PrescriptionMedicationChange.fromJson
  // 함수역할: 백엔드의 약품별 변화 JSON을 화면 Entity로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 변화 유형과 전후 일정 정보를 포함한 JSON 객체
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
// 역할: 추가·미확인·일정 변경·유지 약품의 개수를 보관한다.
// 주요 책임:
// - 유지 항목을 제외한 실제 변화 수를 계산해 요약과 변화 존재 여부를 제공한다.
// 속성:
// - addedCount (int): 이전 처방에 없던 새 약 개수
// - missingCount (int): 이전에 있었으나 현재 확인되지 않은 약 개수
// - scheduleChangedCount (int): 용량·횟수·기간이 변경된 약 개수
// - unchangedCount (int): 이전 처방과 동일한 약 개수
class PrescriptionChangeSummary {
  final int addedCount;
  final int missingCount;
  final int scheduleChangedCount;
  final int unchangedCount;

  // 함수이름: PrescriptionChangeSummary
  // 함수역할: 처방 비교의 추가·미확인·일정 변경·유지 항목 수를 보존한다.
  // 매개변수:
  // - addedCount (int): 이전 처방에 없던 새 약 개수
  // - missingCount (int): 이전에 있었으나 현재 확인되지 않은 약 개수
  // - scheduleChangedCount (int): 용량·횟수·기간이 변경된 약 개수
  // - unchangedCount (int): 이전 처방과 동일한 약 개수
  // 반환값:
  // - PrescriptionChangeSummary: 초기화된 인스턴스.
  const PrescriptionChangeSummary({
    this.addedCount = 0,
    this.missingCount = 0,
    this.scheduleChangedCount = 0,
    this.unchangedCount = 0,
  });

  // 함수이름: PrescriptionChangeSummary.fromJson
  // 함수역할: 백엔드의 변화 유형별 개수 JSON을 요약 Entity로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 추가·미확인·일정 변경·유지 개수를 포함한 JSON 객체
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

  // 함수이름: changeCount
  // 함수역할: 유지된 약을 제외하고 추가·미확인·일정 변경 항목 수를 합산한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - int: 유지된 약을 제외하고 추가·미확인·일정 변경 항목 수를 합산한다.
  int get changeCount => addedCount + missingCount + scheduleChangedCount;
}

// 클래스명: PrescriptionChangeRadar
// 역할: 처방 비교 기준과 요약 및 약품별 상세 변화를 묶는다.
// 주요 책임:
// - 비교 가능 상태·기간·유사도·기준일과 변화 목록을 화면에 일관되게 전달한다.
// 속성:
// - hasPreviousPrescription (bool): 비교 가능한 이전 처방 존재 여부
// - comparisonStatus (PrescriptionComparisonStatus): 이전 처방 비교 가능 여부와 불가 사유
// - comparisonWindowDays (int): 이전 처방을 비교할 최대 일수 범위
// - similarityScore (double?): 이전 처방과 현재 처방의 유사도
// - matchBasis (String): 이전 처방과 연결한 비교 근거
// - previousPrescriptionDate (DateTime?): 비교 대상 이전 처방의 날짜
// - currentPrescriptionDate (DateTime?): 비교 중인 현재 처방의 날짜
// - summary (PrescriptionChangeSummary): 처방 변화 유형별 개수 요약
// - changes (List<PrescriptionMedicationChange>): 약품별 처방 변화 목록
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

  // 함수이름: PrescriptionChangeRadar
  // 함수역할: 비교 가능 여부와 기간·유사도·날짜·요약·상세 변화를 처방 변화 화면의 단일 결과로 묶는다.
  // 매개변수:
  // - hasPreviousPrescription (bool): 비교 가능한 이전 처방 존재 여부
  // - comparisonStatus (PrescriptionComparisonStatus): 이전 처방 비교 가능 여부와 불가 사유
  // - comparisonWindowDays (int): 이전 처방을 비교할 최대 일수 범위
  // - similarityScore (double?): 이전 처방과 현재 처방의 유사도
  // - matchBasis (String): 이전 처방과 연결한 비교 근거
  // - previousPrescriptionDate (DateTime?): 비교 대상 이전 처방의 날짜
  // - currentPrescriptionDate (DateTime?): 비교 중인 현재 처방의 날짜
  // - summary (PrescriptionChangeSummary): 처방 변화 유형별 개수 요약
  // - changes (List<PrescriptionMedicationChange>): 약품별 처방 변화 목록
  // 반환값:
  // - PrescriptionChangeRadar: 초기화된 인스턴스.
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
  // 함수역할: 비교 상태와 약품별 변화가 포함된 백엔드 응답을 화면 Entity로 변환한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 처방 변화 레이더 응답 JSON
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
                  // 함수이름: map 콜백
                  // 함수역할: 처방 비교 응답의 변경 항목을 약별 변경 모델로 변환한다.
                  // 매개변수:
                  // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
                  // 반환값:
                  // - 약별 처방 변경 정보.
                  (item) => PrescriptionMedicationChange.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  // 함수이름: hasChanges
  // 함수역할: 요약의 추가·미확인·일정 변경 합계가 양수인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 요약의 추가·미확인·일정 변경 합계가 양수인지 확인한다.
  bool get hasChanges => summary.changeCount > 0;
}

// 함수이름: _readComparisonStatus
// 함수역할: 백엔드 비교 상태를 열거형으로 변환하고 이전 응답 형식도 지원한다.
// 매개변수:
// - value (dynamic): 백엔드의 comparison_status 값
// - hasPreviousPrescription (bool): 이전 응답 형식의 비교 가능 여부
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
// 함수역할: 백엔드의 변화 유형 문자열을 화면 열거형으로 변환한다.
// 매개변수:
// - value (dynamic): 백엔드의 change_type 값
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
// 함수역할: 선택적인 JSON 일정 객체를 안전하게 스냅샷으로 변환한다.
// 매개변수:
// - value (dynamic): 스냅샷으로 변환할 선택적 JSON 값
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
// 함수역할: JSON 배열에서 비어 있지 않은 문자열 목록을 읽는다.
// 매개변수:
// - value (dynamic): 문자열 배열로 변환할 JSON 값
// 반환값:
// - 비어 있지 않은 문자열 목록
List<String> _readStringList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map(_readString)
      .where(/* 함수이름: where 콜백
       * 함수역할: 공백 정리 후 내용이 남은 변경 설명만 유지한다.
       * 매개변수:
       * - item (String): 현재 변환·검사 중인 응답 또는 목록 항목
       * 반환값:
       * - 설명 문자열이 비어 있지 않으면 true.
       */(item) => item.isNotEmpty)
      .toList(growable: false);
}

// 함수이름: _readString
// 함수역할: 선택적 JSON 값을 앞뒤 공백이 제거된 문자열로 변환한다.
// 매개변수:
// - value (dynamic): 문자열로 변환할 값
// 반환값:
// - 정리된 문자열 또는 값이 없으면 빈 문자열
String _readString(dynamic value) => value?.toString().trim() ?? '';

// 함수이름: _readInt
// 함수역할: 선택적 JSON 값을 정수로 변환한다.
// 매개변수:
// - value (dynamic): 정수로 변환할 값
// 반환값:
// - 변환된 정수 또는 변환할 수 없으면 0
int _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(_readString(value)) ?? 0;
}

// 함수이름: _readDouble
// 함수역할: 선택적 JSON 값을 실수로 변환한다.
// 매개변수:
// - value (dynamic): 실수로 변환할 값
// 반환값:
// - 변환된 실수 또는 변환할 수 없으면 null
double? _readDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(_readString(value));
}

// 함수이름: _readDate
// 함수역할: ISO 날짜 문자열을 DateTime으로 변환한다.
// 매개변수:
// - value (dynamic): 날짜로 변환할 JSON 값
// 반환값:
// - 변환된 DateTime 또는 값이 올바르지 않으면 null
DateTime? _readDate(dynamic value) {
  final text = _readString(value);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
