// 파일명: medication_history_entity.dart
// 역할: 날짜별 사용자 복약 보고·정정 의도와 서버 응답을 검증한다.
import 'medication_slot_label.dart';
import 'medication_schedule_entity.dart';

// 복약 이력의 날짜는 서버 일정과 같은 한국 시간 기준이며 실제 시각은 UTC로 보관한다.
// 클래스명: MedicationHistoryDates
// 역할: 조회 날짜·한국 시각·UTC 저장 시각을 혼동하지 않게 변환한다.
class MedicationHistoryDates {
  static const offset = Duration(hours: 9);

  // 함수역할: 입력 시각을 한국 달력·시계 숫자로 바꾼다. 반환값은 표시 계산용이다.
  static DateTime wallTime(DateTime instant) => instant.toUtc().add(offset);

  // 함수역할: 입력의 달력 날짜만 보존해 DST 영향을 받지 않는 비교값을 만든다.
  static DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  // 함수역할: 입력 실제 시각에 해당하는 한국의 오늘 날짜를 반환한다.
  static DateTime today(DateTime now) => day(wallTime(now));

  // 함수역할: 사용자가 고른 한국 날짜·시·분을 실제 UTC 시각으로 변환한다.
  static DateTime instant(DateTime date, int hour, int minute) => DateTime.utc(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  ).subtract(offset);

  // 함수역할: 입력 달력 날짜를 API와 화면의 YYYY-MM-DD 문자열로 표현한다.
  static String format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  // 함수역할: 선택적 실제 시각을 한국 시간 문자열로 표시하고 없는 시각은 '-'로 남긴다.
  static String timestamp(DateTime? instant) {
    if (instant == null) return '-';
    final time = wallTime(instant);
    return '${format(time)} ${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  // 함수역할: 날짜 문자열을 엄격히 읽으며 존재하지 않는 날짜나 시간 포함 입력은 거부한다.
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

  // 함수역할: 선택적 ISO 시각을 UTC로 읽고 잘못된 응답은 FormatException으로 거부한다.
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

// 클래스명: MedicationHistoryRange
// 역할: 양 끝 날짜를 포함하는 조회 범위와 최대 31일·최근 90일 제한을 보존한다.
class MedicationHistoryRange {
  // 함수역할: 시작·끝 입력에서 시각을 제거해 달력 날짜 범위를 만든다.
  MedicationHistoryRange(DateTime start, DateTime end)
    : start = MedicationHistoryDates.day(start),
      end = MedicationHistoryDates.day(end);

  final DateTime start;
  final DateTime end;
  // 함수역할: 시작일과 마지막 날을 모두 포함한 날짜 수를 반환한다.
  int get days => end.difference(start).inDays + 1;

  // 함수역할: 입력 날짜가 조회 범위 안인지 시각과 무관하게 판정한다.
  bool contains(DateTime date) {
    final value = MedicationHistoryDates.day(date);
    return !value.isBefore(start) && !value.isAfter(end);
  }

  // 함수역할: 현재 시각 기준 미래·역순·조회 기간 초과를 예외로 거부한다.
  void validate(DateTime now) {
    final today = MedicationHistoryDates.today(now);
    if (days < 1 ||
        days > 31 ||
        end.isAfter(today) ||
        start.isBefore(today.subtract(const Duration(days: 89)))) {
      throw const FormatException(
        'Select up to 31 days within the last 90 days.',
      );
    }
  }

  // 함수역할: 실제 조회 범위를 사용자가 확인할 수 있는 날짜 문자열로 반환한다.
  String get label =>
      '${MedicationHistoryDates.format(start)} ~ '
      '${MedicationHistoryDates.format(end)}';
}

// 열거형: MedicationHistoryStatus
// 역할: 실제 복용의 증명이 아닌 사용자의 복용·건너뜀·미기록 상태를 구분한다.
enum MedicationHistoryStatus {
  taken,
  skipped,
  unrecorded;

  // 함수역할: 상태를 선택 언어의 화면·내보내기 용어로 반환한다.
  String label(bool english) => switch (this) {
    taken => english ? 'Taken' : '복용함',
    skipped => english ? 'Skipped' : '건너뜀',
    unrecorded => english ? 'Unrecorded' : '미기록',
  };

  // 함수역할: 서버의 명시적 세 상태만 읽으며 알 수 없는 값을 미기록으로 숨기지 않는다.
  static MedicationHistoryStatus parse(Object? value) => switch (value) {
    'taken' => taken,
    'skipped' => skipped,
    'unrecorded' => unrecorded,
    _ => throw const FormatException('Unknown history status.'),
  };
}

// 클래스명: MedicationHistoryEntry
// 역할: 예정일·시간대·정정 버전·실제 복용 시각·서버 기록 시각을 한 보고로 보존한다.
class MedicationHistoryEntry {
  // 함수역할: 검증된 일정 식별자와 보고 내용을 변경 불가능한 항목으로 묶는다.
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

  // 함수역할: 같은 날짜의 독립 필요시 복용 이벤트까지 구분하는 식별 키를 반환한다.
  String get key =>
      '$medicationId/${MedicationHistoryDates.format(scheduleDate)}/$slotKey';
  // 함수역할: 약의 복용 방식이 필요시 복용인지 반환한다.
  bool get isAsNeeded => dosingMode == 'as_needed';
  // 함수역할: 일반 시간대 또는 필요시 복용을 선택한 언어로 표시한다.
  String slotLabel(bool english) => isAsNeeded
      ? (english ? 'As needed' : '필요시 복용')
      : medicationSlotLabel(slotKey, isEnglish: english);

  // 함수역할: 서버 항목의 식별자·상태·시각을 검증하고 잘못된 응답은 거부한다.
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

  // 함수역할: 정기 복용 시간대와 필요시 UUID 시간대를 약의 모드에 맞게 검증한다.
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
// 역할: 필요시 기록 선택과 내보내기에 필요한 약·처방 버전 정보를 보존한다.
class MedicationHistoryMedication {
  // 함수역할: 약 이름·용량·적용일·중단일과 교체 여부를 입력받아 보존한다.
  const MedicationHistoryMedication({
    required this.id,
    required this.itemName,
    required this.dosingMode,
    this.dosage = '',
    this.frequency = '',
    this.startDate,
    this.stoppedOn,
    this.totalDays = '',
    this.superseded = false,
    this.canRecordAsNeeded = false,
    this.imageUrl = '',
  });
  final int id;
  final String itemName;
  final String dosingMode;
  final String dosage;
  final String frequency;
  final DateTime? startDate;
  final DateTime? stoppedOn;
  final String totalDays;
  final bool superseded;
  final bool canRecordAsNeeded;
  final String imageUrl;

  // 함수역할: 저장 약 응답에서 필요한 정보만 읽고 환자 해시와 상세 의료 정보는 보관하지 않는다.
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
      frequency: json['daily_frequency']?.toString() ?? '',
      startDate:
          _optionalDate(json['regimen_effective_from']) ??
          _optionalDate(json['prescription_date']) ??
          _optionalDate(json['created_date']),
      stoppedOn: _optionalDate(json['stopped_on']),
      totalDays: json['total_days']?.toString() ?? '',
      superseded: json['superseded_by_id'] != null,
      canRecordAsNeeded: json['can_record_as_needed'] == true,
    );
  }
}

// 클래스명: MedicationHistorySnapshot
// 역할: 한 번 조회한 기간·복약 보고·약 목록을 함께 보존한다.
class MedicationHistorySnapshot {
  // 함수역할: 입력 목록을 읽기 전용으로 복사해 내보내기 중 내용이 달라지지 않게 한다.
  MedicationHistorySnapshot({
    required this.range,
    required List<MedicationHistoryEntry> items,
    required List<MedicationHistoryMedication> medications,
  }) : items = List.unmodifiable(items),
       medications = List.unmodifiable(medications);

  final MedicationHistoryRange range;
  final List<MedicationHistoryEntry> items;
  final List<MedicationHistoryMedication> medications;

  // 함수역할: 입력 상태에 해당하는 보고 수를 세며 복용률이나 실제 복용 여부로 해석하지 않는다.
  int count(MedicationHistoryStatus status) =>
      items.where((item) => item.status == status).length;

  // 함수역할: 조회 응답을 검증하고 중복·범위 밖 항목을 거부한 뒤 최신 날짜부터 정렬한다.
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
// 역할: 한 번 확인한 정정 내용과 재전송에 재사용할 작업 UUID를 보존한다.
class MedicationHistoryChange {
  // 함수역할: 기존 항목과 새 상태·시각·사유를 한 사용자 의도로 고정한다.
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

  // 함수역할: 작업 또는 필요시 이벤트 ID가 UUID 형식인지 검사한다.
  static bool isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  // 함수역할: 날짜·상태·시각·200자 사유 상한을 확인하며 미래 복용 기록을 거부한다.
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
            MedicationHistoryDates.today(
              now,
            ).subtract(const Duration(days: 89)),
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

  // 함수역할: 대상 환자와 버전·작업 ID를 쓰기 계약으로 직렬화하고 서버 기록 시각은 보내지 않는다.
  Map<String, dynamic> toJson(String patientHash) => {
    'patient_hash': patientHash,
    'status': status.name,
    'actual_taken_at': actualTakenAt?.toUtc().toIso8601String(),
    'reason': status == MedicationHistoryStatus.skipped ? reason.trim() : '',
    'expected_revision': entry.revision,
    'operation_id': operationId,
  };
}

// 함수역할: 정수 또는 정수 문자열만 읽고 소수·잘못된 값은 null로 반환한다.
int? _integer(Object? value) => value is int ? value : int.tryParse('$value');

// 함수역할: 저장 약의 선택적 적용 날짜를 읽으며 빈 값은 없는 날짜로 유지한다.
DateTime? _optionalDate(Object? value) =>
    value == null || value.toString().trim().isEmpty
    ? null
    : MedicationHistoryDates.parse(value);
