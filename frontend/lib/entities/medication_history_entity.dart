// 파일명: medication_history_entity.dart
// 역할: 날짜별 사용자 복약 보고·정정 의도와 서버 응답을 검증한다.
import 'dose_widget_state.dart';
import 'medication_slot_label.dart';
import 'medication_schedule_entity.dart';

// 복약 이력의 날짜는 서버 일정과 같은 한국 시간 기준이며 실제 시각은 UTC로 보관한다.
// Class Name: MedicationHistoryDates
// Role: Separates dose-calendar values from real UTC instants.
// Responsibilities: Use the shared configured offset for display/day calculations and validate API date/time strings.
// Attributes: offset (Duration): APPLICATION_UTC_OFFSET_MINUTES, UTC+09:00 by default.
class MedicationHistoryDates {
  // 복용 대기열·위젯과 같은 앱 기준 시간대(APPLICATION_UTC_OFFSET_MINUTES, 기본 한국 시간)를 쓴다.
  static const offset = Duration(minutes: doseWidgetUtcOffset);

  // 함수이름: wallTime
  // 함수역할: 실제 시각을 설정된 복약 시간대의 달력·시계 숫자로 바꾼다.
  // 매개변수: instant (DateTime): 실제 시각.
  // 반환값: 표시 계산용으로 offset을 더한 UTC DateTime. 실제 사건 시각으로 재사용하지 않는다.
  static DateTime wallTime(DateTime instant) => instant.toUtc().add(offset);

  // 함수이름: day
  // 함수역할: 입력의 연·월·일을 DST 영향 없는 UTC 자정 비교값으로 만든다.
  // 매개변수: value (DateTime): 달력 날짜를 보존할 값.
  // 반환값: 시간·시간대 변환 없이 달력 숫자만 복사한 DateTime.
  static DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  // 함수이름: today
  // 함수역할: 실제 시각에 해당하는 설정된 복약 기준일을 구한다.
  // 매개변수: now (DateTime): 실제 현재 시각.
  // 반환값: 복약 시간대의 달력 날짜를 나타내는 UTC 자정 값.
  static DateTime today(DateTime now) => day(wallTime(now));

  // Function Name: earliest
  // Description: Finds the first retained day, including today in the maximum export window.
  // Parameters: today (DateTime): Already-normalized dose-calendar day.
  // Returns: UTC calendar date maximumExportDays minus one days earlier.
  static DateTime earliest(DateTime today) => DateTime.utc(
    today.year,
    today.month,
    today.day - (MedicationHistoryRange.maximumExportDays - 1),
  );

  // 함수이름: instant
  // 함수역할: 사용자가 고른 복약 기준 날짜·시·분을 실제 UTC 시각으로 변환한다.
  // 매개변수: date (DateTime): 달력 날짜; hour/minute (int): 기준 시간대의 시·분.
  // 반환값: offset을 뺀 UTC 시각. 범위를 벗어난 성분은 DateTime의 정규화 규칙을 따른다.
  static DateTime instant(DateTime date, int hour, int minute) => DateTime.utc(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  ).subtract(offset);

  // 함수이름: format
  // 함수역할: 입력 달력 숫자를 API 날짜 문자열로 만든다.
  // 매개변수: value (DateTime): 연·월·일을 읽을 값.
  // 반환값: YYYY-MM-DD 문자열. 시간대 변환은 수행하지 않는다.
  static String format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  // Function Name: clock
  // Description: Formats an instant's clock time in the configured dose timezone.
  // Parameters: instant (DateTime): Real event time.
  // Returns: Zero-padded HH:mm string.
  static String clock(DateTime instant) {
    final time = wallTime(instant);
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  // Function Name: timestamp
  // Description: Formats an optional instant as a dose-timezone date and clock value.
  // Parameters: instant (DateTime?): Real event time, possibly absent.
  // Returns: YYYY-MM-DD HH:mm, or '-' for null.
  static String timestamp(DateTime? instant) => instant == null
      ? '-'
      : '${format(wallTime(instant))} ${clock(instant)}';

  // 함수이름: parse
  // 함수역할: 시간 없는 정규 날짜 문자열을 읽고 존재하지 않는 날짜의 자동 보정을 거부한다.
  // 매개변수: value (Object?): YYYY-MM-DD로 표현되는 입력.
  // 반환값: UTC 자정 DateTime. 형식·달력 날짜 불일치는 FormatException.
  static DateTime parse(Object? value) {
    final text = value?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('Invalid history date.');
    }
    final parsed = DateTime.tryParse('${text}T00:00:00Z');
    if (parsed == null || format(parsed) != text) {
      throw const FormatException('Invalid history date.');
    }
    return parsed;
  }

  // 함수이름: parseTimestamp
  // 함수역할: 선택적 ISO 시각을 UTC로 읽고 시간대 없는 기존 서버 값은 UTC로 취급한다.
  // 매개변수: value (Object?): T를 포함한 ISO 시각 또는 null.
  // 반환값: UTC DateTime 또는 null. 파싱 실패·시간 구분자 누락은 FormatException.
  static DateTime? parseTimestamp(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    // 기존 서버의 UTC 시각에는 시간대 접미사가 없을 수 있다.
    final zoned = RegExp(
      r'(Z|[+-]\d{2}:\d{2})$',
      caseSensitive: false,
    ).hasMatch(text);
    final parsed = DateTime.tryParse(zoned ? text : '${text}Z');
    if (!text.contains('T') || parsed == null) {
      throw const FormatException('Invalid history timestamp.');
    }
    return parsed.toUtc();
  }
}

// Class Name: MedicationHistoryRange
// Role: Represents inclusive history dates with API-read and export retention limits.
// Responsibilities: Normalize calendar boundaries and validate order, length, future dates, and retention.
// Attributes: start/end (DateTime): UTC calendar days; maximumReadDays/maximumExportDays (int): 31/90-day limits.
class MedicationHistoryRange {
  // 함수이름: MedicationHistoryRange
  // 함수역할: 시작·끝의 달력 날짜만 보존한 범위를 만든다.
  // 매개변수: start/end (DateTime): 양 끝 날짜.
  // 반환값: 정규화한 범위. 순서·기간·미래 여부 검사는 validate가 맡는다.
  MedicationHistoryRange(DateTime start, DateTime end)
    : start = MedicationHistoryDates.day(start),
      end = MedicationHistoryDates.day(end);

  final DateTime start;
  final DateTime end;
  // 함수이름: days
  // 함수역할: 양 끝 날짜를 포함한 범위 길이를 계산한다.
  // 매개변수: 없음.
  // 반환값: 날짜 수 int. 역순 범위는 0 이하일 수 있다.
  int get days => end.difference(start).inDays + 1;

  // 함수이름: contains
  // 함수역할: 시간 성분을 제거한 입력 날짜가 양 끝을 포함하는 범위 안인지 검사한다.
  // 매개변수: date (DateTime): 검사할 날짜.
  // 반환값: 범위 안이면 true.
  bool contains(DateTime date) {
    final value = MedicationHistoryDates.day(date);
    return !value.isBefore(start) && !value.isAfter(end);
  }

  // 함수역할: 현재 시각 기준 미래·역순·조회 기간 초과를 예외로 거부한다. 서버 조회와 채팅 공유는
  //   한 번에 31일, 외부 텍스트 공유는 31일씩 나눠 읽어 보관 기간 전체(90일)까지 허용한다.
  static const maximumReadDays = 31;
  static const maximumExportDays = 90;

  // Function Name: validate
  // Description: Rejects reversed, oversized, future, or out-of-retention date ranges.
  // Parameters: now (DateTime): Current instant; maxDays (int): Allowed inclusive length, default 31.
  // Returns: No value; invalid ranges throw FormatException. The diagnostic text retains its fixed 31-day wording.
  void validate(DateTime now, {int maxDays = maximumReadDays}) {
    final today = MedicationHistoryDates.today(now);
    if (days < 1 ||
        days > maxDays ||
        end.isAfter(today) ||
        start.isBefore(MedicationHistoryDates.earliest(today))) {
      throw const FormatException(
        'Select up to 31 days within the last 90 days.',
      );
    }
  }

  // 함수이름: label
  // 함수역할: 확인·공유에 사용할 양 끝 날짜를 표시한다.
  // 매개변수: 없음.
  // 반환값: YYYY-MM-DD ~ YYYY-MM-DD 형식 문자열.
  String get label =>
      '${MedicationHistoryDates.format(start)} ~ '
      '${MedicationHistoryDates.format(end)}';
}

// 클래스명: MedicationHistoryStatus
// 역할: 자가 보고의 복용함·건너뜀·미기록 상태를 구분한다.
// 주요 책임: 미기록을 미복용으로 해석하지 않고 서버의 세 상태를 명시적으로 처리한다.
// 속성: taken/skipped/unrecorded: 허용된 상태 값.
enum MedicationHistoryStatus {
  taken,
  skipped,
  unrecorded;

  // 함수이름: label
  // 함수역할: 상태를 화면·내보내기에 사용할 한국어 또는 영어 문구로 바꾼다.
  // 매개변수: english (bool): 영어 여부.
  // 반환값: 현재 상태의 고정 번역 문자열.
  String label(bool english) => switch (this) {
    taken => english ? 'Taken' : '복용함',
    skipped => english ? 'Skipped' : '건너뜀',
    unrecorded => english ? 'Unrecorded' : '미기록',
  };

  // 함수이름: parse
  // 함수역할: 서버가 정의한 세 상태 문자열만 허용한다.
  // 매개변수: value (Object?): 상태 입력.
  // 반환값: 해당 열거값. 알 수 없는 값은 FormatException.
  static MedicationHistoryStatus parse(Object? value) => switch (value) {
    'taken' => taken,
    'skipped' => skipped,
    'unrecorded' => unrecorded,
    _ => throw const FormatException('Unknown history status.'),
  };
}

// 클래스명: MedicationHistoryEntry
// 역할: 날짜·약·시간대별 사용자의 복약 보고를 보존한다.
// 주요 책임: 정기와 필요시 이벤트를 구분하고 응답 필드의 기본 계약을 검증한다.
// 속성: medicationId/itemName: 약; scheduleDate/slotKey/dosingMode: 일정; status/revision: 보고·버전; actualTakenAt/recordedAt: 시각; reason: 건너뜀 사유.
class MedicationHistoryEntry {
  // 함수이름: MedicationHistoryEntry
  // 함수역할: 이미 준비된 일정 식별자와 보고 상태를 불변 항목으로 묶는다.
  // 매개변수: medicationId/itemName: 약; scheduleDate/slotKey: 일정; status/revision: 보고·버전; actualTakenAt/recordedAt: 선택 시각; reason/dosingMode: 사유·복용 유형.
  // 반환값: 항목 인스턴스. 직접 생성은 검증하지 않으며 외부 응답은 fromJson을 사용한다.
  const MedicationHistoryEntry({
    required this.medicationId,
    required this.itemName,
    required this.scheduleDate,
    required this.slotKey,
    required this.status,
    required this.revision,
    this.actualTakenAt,
    this.recordedAt,
    this.reason = '',
    this.dosingMode = 'scheduled',
  });

  final int medicationId;
  final String itemName;
  final DateTime scheduleDate;
  final String slotKey;
  final MedicationHistoryStatus status;
  final DateTime? actualTakenAt;
  final DateTime? recordedAt;
  final String reason;
  final int revision;
  final String dosingMode;

  // 함수이름: key
  // 함수역할: 같은 날짜의 독립 필요시 이벤트도 구분하는 항목 키를 만든다.
  // 매개변수: 없음.
  // 반환값: 약 ID/날짜/슬롯을 결합한 문자열.
  String get key =>
      '$medicationId/${MedicationHistoryDates.format(scheduleDate)}/$slotKey';
  // 함수이름: isAsNeeded
  // 함수역할: 저장된 복용 유형이 필요시인지 확인한다.
  // 매개변수: 없음.
  // 반환값: dosingMode가 정확히 as_needed이면 true.
  bool get isAsNeeded => dosingMode == 'as_needed';
  // 함수이름: slotLabel
  // 함수역할: 필요시 약 또는 정기 시간대를 표시 언어에 맞춰 이름 붙인다.
  // 매개변수: english (bool): 영어 여부.
  // 반환값: 필요시 복용 문구 또는 공통 시간대 라벨.
  String slotLabel(bool english) => isAsNeeded
      ? (english ? 'As needed' : '필요시 복용')
      : medicationSlotLabel(slotKey, isEnglish: english);

  // 함수이름: MedicationHistoryEntry.fromJson
  // 함수역할: 양수 약 ID·이름·비음수 버전·슬롯과 날짜·상태·시각을 검사하며 응답을 읽는다.
  // 매개변수: json (Map<String, dynamic>): 서버 항목.
  // 반환값: 검증한 항목. 필수 값·날짜·시각·상태가 잘못되면 형식 예외를 전달한다.
  factory MedicationHistoryEntry.fromJson(Map<String, dynamic> json) {
    final id = _integer(json['medication_id']);
    final revision = _integer(json['revision']);
    final slot = json['slot_key']?.toString() ?? '';
    final mode = json['dosing_mode']?.toString() ?? 'scheduled';
    final name = json['item_name']?.toString().trim() ?? '';
    if (id == null ||
        id < 1 ||
        revision == null ||
        revision < 0 ||
        name.isEmpty ||
        !validSlot(slot, mode)) {
      throw const FormatException('Invalid history entry.');
    }
    return MedicationHistoryEntry(
      medicationId: id,
      itemName: name,
      scheduleDate: MedicationHistoryDates.parse(json['schedule_date']),
      slotKey: slot,
      status: MedicationHistoryStatus.parse(json['status']),
      revision: revision,
      actualTakenAt: MedicationHistoryDates.parseTimestamp(
        json['actual_taken_at'],
      ),
      recordedAt: MedicationHistoryDates.parseTimestamp(json['recorded_at']),
      reason: json['reason']?.toString() ?? '',
      dosingMode: mode,
    );
  }

  // Function Name: validSlot
  // Description: Validates a slot against the regimen mode, allowing legacy as_needed or an as_needed:UUID event key.
  // Parameters: key (String): Slot/event key; mode (String): Dosing mode.
  // Returns: True for an accepted key; non-as_needed modes use the regular-slot set.
  static bool validSlot(String key, String mode) {
    if (mode == 'as_needed') {
      return key == 'as_needed' ||
          (key.startsWith('as_needed:') &&
              MedicationHistoryChange.isUuid(key.substring(10)));
    }
    return medicationScheduleSlotKeys.contains(key);
  }
}

// 클래스명: MedicationHistoryMedication
// 역할: 기록 화면에 필요한 저장 약 정보와 필요시 기록 가능 여부를 담는다.
// 주요 책임: 환자 해시 없이 이름·용량·사진·복용 유형만 전달한다.
// 속성: id/itemName/dosingMode: 약 식별·유형; dosage/imageUrl: 표시 값; canRecordAsNeeded: 서버의 기록 허용 표시.
class MedicationHistoryMedication {
  // 함수이름: MedicationHistoryMedication
  // 함수역할: 약 표시 정보와 필요시 기록 가능 여부를 보존한다.
  // 매개변수: id/itemName/dosingMode: 필수 약 정보; dosage/imageUrl: 선택 표시 값; canRecordAsNeeded: 기본 false인 기록 허용.
  // 반환값: 항목 인스턴스. 직접 생성 시 필드 검증은 하지 않는다.
  const MedicationHistoryMedication({
    required this.id,
    required this.itemName,
    required this.dosingMode,
    this.dosage = '',
    this.canRecordAsNeeded = false,
    this.imageUrl = '',
  });
  final int id;
  final String itemName;
  final String dosingMode;
  final String dosage;
  final bool canRecordAsNeeded;
  final String imageUrl;

  // 함수이름: MedicationHistoryMedication.fromJson
  // 함수역할: 양수 ID와 비어 있지 않은 약 이름을 요구하고 선택 표시 값은 기본값으로 읽는다.
  // 매개변수: json (Map<String, dynamic>): 저장 약 응답.
  // 반환값: 약 모델. 잘못된 ID·이름은 FormatException이며 can_record_as_needed는 true만 허용한다.
  factory MedicationHistoryMedication.fromJson(Map<String, dynamic> json) {
    final id = _integer(json['id'] ?? json['medication_id']);
    final name = json['item_name']?.toString().trim() ?? '';
    if (id == null || id < 1 || name.isEmpty) {
      throw const FormatException('Invalid history medication.');
    }
    return MedicationHistoryMedication(
      id: id,
      itemName: name,
      dosingMode: json['dosing_mode']?.toString() ?? 'scheduled',
      dosage: json['dosage_per_time']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      canRecordAsNeeded: json['can_record_as_needed'] == true,
    );
  }
}

// Class Name: MedicationHistorySnapshot
// Role: Holds one coherent history range and immutable record/medication lists.
// Responsibilities: Reject duplicate or out-of-range records during decoding and apply stable display ordering.
// Attributes: range (MedicationHistoryRange), items (List<MedicationHistoryEntry>), medications (List<MedicationHistoryMedication>): Snapshot data.
class MedicationHistorySnapshot {
  // 함수이름: MedicationHistorySnapshot
  // 함수역할: 기간과 항목 목록을 묶고 목록을 읽기 전용으로 복사한다.
  // 매개변수: range: 조회 기간; items: 보고 목록; medications: 저장 약 목록.
  // 반환값: 외부 목록 변경의 영향을 받지 않는 스냅샷. 내용 검증은 fromJson이 맡는다.
  MedicationHistorySnapshot({
    required this.range,
    required List<MedicationHistoryEntry> items,
    required List<MedicationHistoryMedication> medications,
  }) : items = List.unmodifiable(items),
       medications = List.unmodifiable(medications);

  final MedicationHistoryRange range;
  final List<MedicationHistoryEntry> items;
  final List<MedicationHistoryMedication> medications;

  // 함수이름: count
  // 함수역할: 지정한 보고 상태의 항목 수만 센다.
  // 매개변수: status (MedicationHistoryStatus): 집계할 상태.
  // 반환값: 일치 개수 int. 실제 복용률이나 복용 증거를 계산하지 않는다.
  int count(MedicationHistoryStatus status) =>
      items.where((item) => item.status == status).length;

  // Function Name: MedicationHistorySnapshot.fromJson
  // Description: Decodes history arrays, rejects duplicate/out-of-range entries, and sorts newest dates first with name/slot and as-needed time ordering.
  // Parameters: json (Map<String, dynamic>): Response with dates, items, and medications.
  // Returns: Immutable snapshot; malformed lists/fields or invalid entry scope throws. Retention limits are checked by the caller.
  factory MedicationHistorySnapshot.fromJson(Map<String, dynamic> json) {
    final range = MedicationHistoryRange(
      MedicationHistoryDates.parse(json['start_date']),
      MedicationHistoryDates.parse(json['end_date']),
    );
    if (json['items'] is! List || json['medications'] is! List) {
      throw const FormatException('Invalid history response.');
    }
    final items = (json['items'] as List)
        .map(
          (item) => MedicationHistoryEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    if (items.any((item) => !range.contains(item.scheduleDate)) ||
        items.map((item) => item.key).toSet().length != items.length) {
      throw const FormatException(
        'History contains invalid dates or duplicate entries.',
      );
    }
    items.sort((a, b) {
      final date = b.scheduleDate.compareTo(a.scheduleDate);
      if (date != 0) return date;
      final name = a.itemName.compareTo(b.itemName);
      if (name != 0) return name;
      // 필요시 복용의 슬롯 키는 임의 UUID이므로 같은 날 여러 번 먹은 기록은 복용 시각 순서로 둔다.
      if (a.isAsNeeded && b.isAsNeeded) {
        final aTime = a.actualTakenAt ?? a.recordedAt;
        final bTime = b.actualTakenAt ?? b.recordedAt;
        if (aTime != null && bTime != null && aTime != bTime) {
          return aTime.compareTo(bTime);
        }
        if ((aTime == null) != (bTime == null)) return aTime == null ? 1 : -1;
      }
      return a.slotKey.compareTo(b.slotKey);
    });
    return MedicationHistorySnapshot(
      range: range,
      items: items,
      medications: (json['medications'] as List)
          .map(
            (item) => MedicationHistoryMedication.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

// 클래스명: MedicationHistoryChange
// 역할: 기존 보고와 새 상태·시각·사유를 하나의 재시도 가능한 변경으로 묶는다.
// 주요 책임: 버전·작업 ID를 보존하고 저장 전 상태별 입력 제약을 검사한다.
// 속성: entry: 기존 항목; status: 새 상태; operationId: UUID; actualTakenAt: 선택 시각; reason: 건너뜀 사유.
class MedicationHistoryChange {
  // 함수이름: MedicationHistoryChange
  // 함수역할: 한 사용자 의도를 나타내는 원본 항목·새 상태·요청 ID를 보관한다.
  // 매개변수: entry/status/operationId: 대상·상태·ID; actualTakenAt: 선택 실제 복용 시각; reason: 기본 빈 사유.
  // 반환값: 불변 변경 모델. 유효성 검사는 validate에서 수행한다.
  const MedicationHistoryChange({
    required this.entry,
    required this.status,
    required this.operationId,
    this.actualTakenAt,
    this.reason = '',
  });
  final MedicationHistoryEntry entry;
  final MedicationHistoryStatus status;
  final String operationId;
  final DateTime? actualTakenAt;
  final String reason;

  // 함수이름: isUuid
  // 함수역할: 요청 또는 필요시 이벤트 식별자가 UUID의 8-4-4-4-12 형식인지 검사한다.
  // 매개변수: value (String): 검사할 식별자.
  // 반환값: 대소문자 16진수 형식이면 true. UUID 버전·variant는 검사하지 않는다.
  static bool isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  // Function Name: validate
  // Description: Validates retained dates, slot/ID/revision, UUID, reason length, and status-specific taken-time/reason rules.
  // Parameters: now (DateTime): Current instant used for future/retention checks.
  // Returns: No value; invalid input throws FormatException. Taken time is required only for taken and skip reasons only for skipped.
  void validate(DateTime now) {
    MedicationHistoryRange(
      entry.scheduleDate,
      entry.scheduleDate,
    ).validate(now);
    if (entry.medicationId < 1 ||
        entry.revision < 0 ||
        !MedicationHistoryEntry.validSlot(entry.slotKey, entry.dosingMode) ||
        !isUuid(operationId) ||
        reason.runes.length > 200) {
      throw const FormatException('Invalid history correction.');
    }
    if (status == MedicationHistoryStatus.taken) {
      if (actualTakenAt == null ||
          actualTakenAt!.isAfter(now) ||
          MedicationHistoryDates.today(actualTakenAt!).isBefore(
            MedicationHistoryDates.earliest(MedicationHistoryDates.today(now)),
          )) {
        throw const FormatException(
          'Choose an actual taken time that is not in the future.',
        );
      }
    } else if (actualTakenAt != null) {
      throw const FormatException('Only taken records may have a taken time.');
    }
    if (status != MedicationHistoryStatus.skipped && reason.trim().isNotEmpty) {
      throw const FormatException('A reason is only used for skipped records.');
    }
  }

  // 함수이름: toJson
  // 함수역할: 환자 범위·예상 버전·요청 ID를 서버 수정 계약으로 직렬화한다.
  // 매개변수: patientHash (String): 대상 환자.
  // 반환값: JSON 맵. 복용 시각은 UTC이고 건너뜀이 아니면 사유는 비우며 서버 기록 시각은 보내지 않는다.
  Map<String, dynamic> toJson(String patientHash) => {
    'patient_hash': patientHash,
    'status': status.name,
    'actual_taken_at': actualTakenAt?.toUtc().toIso8601String(),
    'reason': status == MedicationHistoryStatus.skipped ? reason.trim() : '',
    'expected_revision': entry.revision,
    'operation_id': operationId,
  };
}

// 함수이름: _integer
// 함수역할: 정수 값을 그대로 쓰거나 정수로 표현된 문자열을 파싱한다.
// 매개변수: value (Object?): 정수 또는 정수 문자열.
// 반환값: int 또는 파싱할 수 없으면 null.
int? _integer(Object? value) => value is int ? value : int.tryParse('$value');
