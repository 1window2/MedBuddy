// 파일명: photo_dose_plan_entity.dart
// 역할: 사진으로 복용 기록의 서버 계획·기록 응답을 화면이 쓰는 값으로 읽는다.
//   형식은 backend/controls/plan_photo_dose_control.py와 docs/Photo Dose Recording.md를 따른다.

import 'json_value_reader.dart';
import 'medication_image_url_entity.dart';

// 열거형: PhotoDosePillStatus
// 역할: 알약 하나의 계획 결과.
// - matched: 기록할 약으로 정해짐, needsChoice: 사용자에게 물어야 함, skipped: "아니에요/모르겠어요",
//   unknown: 복약 중인 약이 아님, 나머지는 기록하지 않는 이유(확인 화면 맨 위 주의 띠).
enum PhotoDosePillStatus {
  matched,
  needsChoice,
  skipped,
  unknown,
  extra,
  recentlyTaken,
  alreadyTaken,
  tooEarly,
  unclearSlot,
  notDue;

  // 함수이름: parse
  // 함수역할: 서버 상태 문자열을 읽는다.
  // 매개변수: value (Object?): 서버 값.
  // 반환값: 상태. 모르는 값은 FormatException.
  static PhotoDosePillStatus parse(Object? value) => switch (value) {
    'matched' => matched,
    'needs_choice' => needsChoice,
    'skipped' => skipped,
    'unknown' => unknown,
    'extra' => extra,
    'recently_taken' => recentlyTaken,
    'already_taken' => alreadyTaken,
    'too_early' => tooEarly,
    'unclear_slot' => unclearSlot,
    'not_due' => notDue,
    _ => throw FormatException('Unknown photo dose status: $value'),
  };

  // 함수이름: isWarning
  // 함수역할: 확인 화면 맨 위 주의 띠에 보일 상태인지 알려 준다.
  // 매개변수: 없음.
  // 반환값: 기록하지 않으며 사용자가 먼저 알아야 하는 상태면 true.
  bool get isWarning => const {
    extra,
    recentlyTaken,
    alreadyTaken,
    tooEarly,
    unclearSlot,
    notDue,
  }.contains(this);
}

// 클래스명: PhotoDoseMedication
// 역할: 계획에 나온 본인 약 하나의 표시 정보.
class PhotoDoseMedication {
  final int id;
  final String name;
  final String dosage;
  final bool isAsNeeded;
  final List<String> slotKeys;
  final String imageUrl;

  const PhotoDoseMedication({
    required this.id,
    required this.name,
    this.dosage = '',
    this.isAsNeeded = false,
    this.slotKeys = const [],
    this.imageUrl = '',
  });

  // 함수이름: PhotoDoseMedication.fromJson
  // 함수역할: 약 정보를 읽는다.
  // 매개변수: json (Map<String, dynamic>): 서버 값.
  // 반환값: PhotoDoseMedication.
  factory PhotoDoseMedication.fromJson(Map<String, dynamic> json) =>
      PhotoDoseMedication(
        id: _requireInt(json['id'], 'id'),
        name: readJsonText(json['name']),
        dosage: readJsonText(json['dosage']),
        isAsNeeded: json['dosing_mode'] == 'as_needed',
        slotKeys: [
          for (final key in (json['slot_keys'] as List? ?? const []))
            key.toString(),
        ],
        imageUrl: safeMedicationImageUrl(json['image_url']),
      );
}

// 클래스명: PhotoDosePill
// 역할: 사진 속 알약 하나의 계획 결과.
class PhotoDosePill {
  final int index;
  final PhotoDosePillStatus status;
  final int? medicationId;
  final String? evidence;
  final List<int> options;
  final List<int> lookalikeIds;
  final DateTime? detailAt;

  const PhotoDosePill({
    required this.index,
    required this.status,
    this.medicationId,
    this.evidence,
    this.options = const [],
    this.lookalikeIds = const [],
    this.detailAt,
  });

  // 함수이름: foundByLook
  // 함수역할: 각인 없이 모양·색으로만 고른 약인지 알려 준다.
  // 매개변수: 없음. 반환값: 모양·색 근거면 true.
  bool get foundByLook => evidence == 'look';

  // 함수이름: PhotoDosePill.fromJson
  // 함수역할: 알약 결과를 읽는다.
  // 매개변수: json (Map<String, dynamic>): 서버 값.
  // 반환값: PhotoDosePill.
  factory PhotoDosePill.fromJson(Map<String, dynamic> json) => PhotoDosePill(
    index: _requireInt(json['index'], 'index'),
    status: PhotoDosePillStatus.parse(json['status']),
    medicationId: json['medication_id'] is int
        ? json['medication_id'] as int
        : null,
    evidence: json['evidence'] as String?,
    options: _ints(json['options']),
    lookalikeIds: _ints(json['lookalike_ids']),
    detailAt: _time(json['detail_at']),
  );
}

// 클래스명: PhotoDoseGroup
// 역할: 한 날짜·시간대에 기록할 약 묶음.
class PhotoDoseGroup {
  final String scheduleDate;
  final String slotKey;
  final DateTime reminderAt;
  final String timing;
  final List<int> medicationIds;
  final List<int> missingMedicationIds;

  const PhotoDoseGroup({
    required this.scheduleDate,
    required this.slotKey,
    required this.reminderAt,
    required this.timing,
    required this.medicationIds,
    this.missingMedicationIds = const [],
  });

  // 함수이름: isYesterday
  // 함수역할: 자정을 넘겨 어제 시간대로 기록하는 묶음인지 알려 준다.
  // 매개변수: 없음. 반환값: 어제 날짜면 true.
  bool get isOvernight => timing == 'overnight';

  // 함수이름: PhotoDoseGroup.fromJson
  // 함수역할: 시간대 묶음을 읽는다.
  // 매개변수: json (Map<String, dynamic>): 서버 값.
  // 반환값: PhotoDoseGroup.
  factory PhotoDoseGroup.fromJson(Map<String, dynamic> json) => PhotoDoseGroup(
    scheduleDate: readJsonText(json['schedule_date']),
    slotKey: readJsonText(json['slot_key']),
    reminderAt:
        _time(json['reminder_at']) ??
        (throw const FormatException('reminder_at is required.')),
    timing: readJsonText(json['timing']),
    medicationIds: _ints(json['medication_ids']),
    missingMedicationIds: _ints(json['missing_medication_ids']),
  );

  // 함수이름: toWriteJson
  // 함수역할: 확인 요청에 보낼 기록 묶음을 만든다.
  // 매개변수: 없음. 반환값: JSON map.
  Map<String, dynamic> toWriteJson() => {
    'schedule_date': scheduleDate,
    'slot_key': slotKey,
    'medication_ids': medicationIds,
  };
}

// 클래스명: PhotoDoseAsNeeded
// 역할: 지금 1회 기록할 필요시 복용 약과 오늘 횟수.
class PhotoDoseAsNeeded {
  final int medicationId;
  final int takenToday;
  final DateTime? lastTakenAt;

  const PhotoDoseAsNeeded({
    required this.medicationId,
    this.takenToday = 0,
    this.lastTakenAt,
  });
}

// 클래스명: PhotoDosePlan
// 역할: 서버가 계산한 사진 복용 기록 계획 전체.
class PhotoDosePlan {
  final String planToken;
  final DateTime asOf;
  final List<PhotoDosePill> pills;
  final List<PhotoDoseGroup> groups;
  final List<PhotoDoseAsNeeded> asNeeded;
  final Map<int, PhotoDoseMedication> medications;
  final Map<String, dynamic> write;
  final bool ready;

  const PhotoDosePlan({
    required this.planToken,
    required this.asOf,
    required this.pills,
    required this.groups,
    required this.asNeeded,
    required this.medications,
    required this.write,
    required this.ready,
  });

  // 함수이름: questions
  // 함수역할: 사용자에게 물어야 하는 알약을 번호 순으로 돌려준다.
  // 매개변수: 없음. 반환값: 질문할 알약 목록.
  List<PhotoDosePill> get questions => [
    for (final pill in pills)
      if (pill.status == PhotoDosePillStatus.needsChoice) pill,
  ];

  // 함수이름: warnings
  // 함수역할: 기록하지 않고 맨 위에 알릴 알약을 돌려준다.
  // 매개변수: 없음. 반환값: 주의할 알약 목록.
  List<PhotoDosePill> get warnings => [
    for (final pill in pills)
      if (pill.status.isWarning) pill,
  ];

  // 함수이름: hasWrite
  // 함수역할: 기록할 약이 하나라도 있는지 알려 준다.
  // 매개변수: 없음. 반환값: 정기 묶음이나 필요시 약이 있으면 true.
  bool get hasWrite => groups.isNotEmpty || asNeeded.isNotEmpty;

  // 함수이름: medicationCount
  // 함수역할: 기록할 약의 수.
  // 매개변수: 없음. 반환값: 정기·필요시 약 수의 합.
  int get medicationCount =>
      groups.fold<int>(0, (sum, g) => sum + g.medicationIds.length) +
      asNeeded.length;

  // 함수이름: PhotoDosePlan.fromJson
  // 함수역할: 계획 응답을 읽는다. 필수 값이 없거나 형식이 틀리면 FormatException.
  // 매개변수: json (Map<String, dynamic>): 서버 응답 본문.
  // 반환값: PhotoDosePlan.
  factory PhotoDosePlan.fromJson(Map<String, dynamic> json) {
    final token = json['plan_token'];
    final write = json['write'];
    if (json['success'] != true || token is! String || token.isEmpty) {
      throw const FormatException('The photo plan was not acknowledged.');
    }
    if (write is! Map) {
      throw const FormatException('write must be an object.');
    }
    final asNeededRows = (json['as_needed'] as List? ?? const []);
    return PhotoDosePlan(
      planToken: token,
      asOf:
          _time(json['as_of']) ??
          (throw const FormatException('as_of is required.')),
      pills: [
        for (final row in (json['pills'] as List? ?? const []))
          PhotoDosePill.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      groups: [
        for (final row in (json['groups'] as List? ?? const []))
          PhotoDoseGroup.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      asNeeded: [
        for (final raw in asNeededRows)
          PhotoDoseAsNeeded(
            medicationId: _requireInt((raw as Map)['medication_id'], 'id'),
            takenToday: raw['taken_today'] is int
                ? raw['taken_today'] as int
                : 0,
            lastTakenAt: _time(raw['last_taken_at']),
          ),
      ],
      medications: {
        for (final row in (json['medications'] as List? ?? const []))
          for (final medication in [
            PhotoDoseMedication.fromJson(Map<String, dynamic>.from(row as Map)),
          ])
            medication.id: medication,
      },
      write: Map<String, dynamic>.from(write),
      ready: json['ready'] == true,
    );
  }
}

// 클래스명: PhotoDoseRecordResult
// 역할: 확인 요청이 기록한 결과와, 서버가 함께 돌려준 오늘 일정 원본.
class PhotoDoseRecordResult {
  final String operationId;
  final DateTime takenAt;
  final String scheduleDate;
  final List<dynamic> todaySchedule;

  const PhotoDoseRecordResult({
    required this.operationId,
    required this.takenAt,
    required this.scheduleDate,
    required this.todaySchedule,
  });

  // 함수이름: PhotoDoseRecordResult.fromJson
  // 함수역할: 확인 응답을 읽는다.
  // 매개변수: json (Map<String, dynamic>): 서버 응답 본문.
  // 반환값: PhotoDoseRecordResult. 성공이 아니면 FormatException.
  factory PhotoDoseRecordResult.fromJson(Map<String, dynamic> json) {
    if (json['success'] != true) {
      throw const FormatException('The photo dose was not recorded.');
    }
    return PhotoDoseRecordResult(
      operationId: readJsonText(json['operation_id']),
      takenAt:
          _time(json['taken_at']) ??
          (throw const FormatException('taken_at is required.')),
      scheduleDate: readJsonText(json['schedule_date']),
      todaySchedule: json['data'] is List ? json['data'] as List : const [],
    );
  }
}

// 함수이름: _requireInt
// 함수역할: 필수 정수 값을 읽는다.
// 매개변수: value: 서버 값; field: 오류용 이름. 반환값: 정수. 아니면 FormatException.
int _requireInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field must be an integer.');
}

// 함수이름: _ints
// 함수역할: 정수 목록을 읽고 정수가 아닌 값은 버린다.
// 매개변수: value: 서버 값. 반환값: 정수 목록.
List<int> _ints(Object? value) => [
  for (final item in (value as List? ?? const []))
    if (item is int) item,
];

// 함수이름: _time
// 함수역할: ISO 시각을 서버가 적은 시간대의 벽시계 시각으로 읽는다. 서버는 복약 시간대(Asia/Seoul)로 답하며,
//   기기 시간대가 달라도 "오전 8:00 알림"처럼 서버 기준 시각을 보여야 한다.
// 매개변수: value: 서버 값. 반환값: 시간대 없는 벽시계 DateTime 또는 null.
DateTime? _time(Object? value) {
  if (value is! String) return null;
  final instant = DateTime.tryParse(value);
  if (instant == null) return null;
  final offset = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(value);
  if (offset == null) return value.endsWith('Z') ? instant.toUtc() : instant;
  final minutes =
      int.parse(offset.group(2)!) * 60 + int.parse(offset.group(3)!);
  final wall = instant.toUtc().add(
    Duration(minutes: offset.group(1) == '-' ? -minutes : minutes),
  );
  return DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
}
