// 파일명: caregiver_notification_entity.dart
// 역할: 보호자별 환자 복약 시간대의 알림 조건과 마감 시각을 표현한다.

const List<String> caregiverNotificationSlotKeys = [
  'morning',
  'lunch',
  'evening',
  'bedtime',
];

// 클래스명: CaregiverNotificationMode
// 역할: 보호자 알림의 비활성·복약 완료·마감 미복약 조건을 구분한다.
// 주요 책임:
// - 서버 전송값을 제공하고 구형 활성화 표현을 완료 알림 모드로 호환 변환한다.
enum CaregiverNotificationMode {
  disabled('disabled'),
  doseCompleted('dose_completed'),
  missedDeadline('missed_deadline');

  final String wireValue;

  // 함수이름: CaregiverNotificationMode
  // 함수역할: 각 알림 조건을 서버와 공유하는 문자열 값에 연결한다.
  // 매개변수:
  // - wireValue (String): 서버 계약에서 사용하는 전송 문자열
  // 반환값:
  // - CaregiverNotificationMode: 초기화된 인스턴스.
  const CaregiverNotificationMode(this.wireValue);

  // 함수이름: fromValue
  // 함수역할: 구형 enable·on·true·1 값은 복약 완료로 해석하고 명시된 마감 알림 이외의 알 수 없는 값은 비활성화한다.
  // 매개변수:
  // - value (dynamic): 보호자 알림 모드로 해석할 서버 전송 값
  // 반환값:
  // - CaregiverNotificationMode: 구형 enable·on·true·1 값은 복약 완료로 해석하고 명시된 마감 알림 이외의 알 수 없는 값은 비활성화한다.
  static CaregiverNotificationMode fromValue(dynamic value) {
    final normalizedValue = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalizedValue) {
      'enable' ||
      'enabled' ||
      'on' ||
      'true' ||
      '1' => CaregiverNotificationMode.doseCompleted,
      'dose_completed' => CaregiverNotificationMode.doseCompleted,
      'missed_deadline' => CaregiverNotificationMode.missedDeadline,
      _ => CaregiverNotificationMode.disabled,
    };
  }
}

// 클래스명: CaregiverNotification
// 역할: 보호자·환자 쌍의 한 복약 시간대에 적용할 알림 조건을 보관한다.
// 주요 책임:
// - 서버 필드 별칭을 읽고 마감 시각의 유효성 확인과 불변 설정 변경을 제공한다.
// 속성:
// - notificationId (int?): 플랫폼 알림 또는 서버 설정 식별자
// - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
// - mode (CaregiverNotificationMode): 적용할 보호자 알림 조건
// - deadlineHour (int?): 미복약 판정 마감의 24시간제 시
// - deadlineMinute (int?): 미복약 판정 마감의 분
class CaregiverNotification {
  final int? notificationId;
  final String caregiverHash;
  final String patientHash;
  final String slotKey;
  final CaregiverNotificationMode mode;
  final int? deadlineHour;
  final int? deadlineMinute;

  // 함수이름: CaregiverNotification
  // 함수역할: 보호자·환자·시간대 범위와 알림 모드 및 선택적 미복약 마감 시각을 보존한다.
  // 매개변수:
  // - notificationId (int?): 플랫폼 알림 또는 서버 설정 식별자
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - mode (CaregiverNotificationMode): 적용할 보호자 알림 조건
  // - deadlineHour (int?): 미복약 판정 마감의 24시간제 시
  // - deadlineMinute (int?): 미복약 판정 마감의 분
  // 반환값:
  // - CaregiverNotification: 초기화된 인스턴스.
  const CaregiverNotification({
    this.notificationId,
    this.caregiverHash = '',
    this.patientHash = '',
    this.slotKey = 'morning',
    this.mode = CaregiverNotificationMode.disabled,
    this.deadlineHour,
    this.deadlineMinute,
  });

  // 함수이름: notificationEnabled
  // 함수역할: 비활성 모드가 아닌 경우에만 보호자 알림이 켜진 것으로 판단한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 비활성 모드가 아닌 경우에만 보호자 알림이 켜진 것으로 판단한다.
  bool get notificationEnabled => mode != CaregiverNotificationMode.disabled;

  // 함수이름: notificationType
  // 함수역할: 현재 알림 조건을 서버가 사용하는 전송 문자열로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 현재 알림 조건을 서버가 사용하는 전송 문자열로 제공한다.
  String get notificationType => mode.wireValue;

  // 함수이름: hasValidDeadline
  // 함수역할: 마감 시와 분이 모두 존재하고 각각 0~23과 0~59 범위인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 마감 시와 분이 모두 존재하고 각각 0~23과 0~59 범위인지 확인한다.
  bool get hasValidDeadline {
    return deadlineHour != null &&
        deadlineMinute != null &&
        deadlineHour! >= 0 &&
        deadlineHour! <= 23 &&
        deadlineMinute! >= 0 &&
        deadlineMinute! <= 59;
  }

  // 함수이름: CaregiverNotification.fromJson
  // 함수역할: 구형 식별자·활성화 필드 이름을 함께 읽어 시간대별 보호자 알림 설정을 복원한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - CaregiverNotification: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
  factory CaregiverNotification.fromJson(Map<String, dynamic> json) {
    final rawMode =
        json['notification_type'] ??
        json['notificationType'] ??
        json['alert_option'] ??
        json['alertOption'];
    final rawEnabled =
        json['notification_enabled'] ??
        json['notificationEnabled'] ??
        json['is_enabled'] ??
        json['enabled'];
    final mode = rawMode == null
        ? CaregiverNotificationMode.fromValue(rawEnabled)
        : CaregiverNotificationMode.fromValue(rawMode);

    return CaregiverNotification(
      notificationId: _readInt(
        json['notification_id'] ??
            json['notificationId'] ??
            json['setting_id'] ??
            json['id'],
      ),
      caregiverHash: _readString(
        json['caregiver_hash'] ??
            json['guardian_hash'] ??
            json['caregiver_id'] ??
            json['caregiverID'] ??
            json['guardian_id'] ??
            json['guardianID'],
      ),
      patientHash: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      slotKey: _readString(json['slot_key'] ?? json['slotKey']).isEmpty
          ? 'morning'
          : _readString(json['slot_key'] ?? json['slotKey']),
      mode: mode,
      deadlineHour: _readInt(json['deadline_hour'] ?? json['deadlineHour']),
      deadlineMinute: _readInt(
        json['deadline_minute'] ?? json['deadlineMinute'],
      ),
    );
  }

  // 함수이름: toJson
  // 함수역할: 보호자·환자·시간대 식별자, 활성화 여부, 조건과 마감 시각을 서버 필드명으로 직렬화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Map<String, dynamic>: 보호자·환자·시간대 식별자, 활성화 여부, 조건과 마감 시각을 서버 필드명으로 직렬화한다.
  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'caregiver_hash': caregiverHash,
      'patient_hash': patientHash,
      'slot_key': slotKey,
      'notification_enabled': notificationEnabled,
      'notification_type': notificationType,
      'deadline_hour': deadlineHour,
      'deadline_minute': deadlineMinute,
    };
  }

  // 함수이름: updateNotificationSetting
  // 함수역할: 선택한 알림 모드를 반영하고 마감 미복약 모드가 아니면 이전 마감 시각을 제거한다.
  // 매개변수:
  // - nextMode (CaregiverNotificationMode): 적용할 보호자 알림 조건
  // - deadlineHour (int?): 미복약 판정 마감의 24시간제 시
  // - deadlineMinute (int?): 미복약 판정 마감의 분
  // 반환값:
  // - CaregiverNotification: 선택한 알림 모드를 반영하고 마감 미복약 모드가 아니면 이전 마감 시각을 제거한다.
  CaregiverNotification updateNotificationSetting(
    CaregiverNotificationMode nextMode, {
    int? deadlineHour,
    int? deadlineMinute,
  }) {
    final keepsDeadline = nextMode == CaregiverNotificationMode.missedDeadline;
    return copyWith(
      mode: nextMode,
      deadlineHour: keepsDeadline ? deadlineHour : null,
      deadlineMinute: keepsDeadline ? deadlineMinute : null,
      clearDeadline: !keepsDeadline,
    );
  }

  // 함수이름: copyWith
  // 함수역할: 지정한 보호자 알림 필드만 교체하며 clearDeadline이 true이면 마감 시·분을 명시적으로 지운다.
  // 매개변수:
  // - notificationId (int?): 플랫폼 알림 또는 서버 설정 식별자
  // - caregiverHash (String?): 조회·저장 범위를 제한할 보호자 해시
  // - patientHash (String?): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // - mode (CaregiverNotificationMode?): 적용할 보호자 알림 조건
  // - deadlineHour (int?): 미복약 판정 마감의 24시간제 시
  // - deadlineMinute (int?): 미복약 판정 마감의 분
  // - clearDeadline (bool): 기존 마감 시·분을 명시적으로 지울지 여부
  // 반환값:
  // - CaregiverNotification: 지정한 필드만 바꾼 사본. 단, clearDeadline이 true이면 기존 마감 시·분도 null로 지운다.
  CaregiverNotification copyWith({
    int? notificationId,
    String? caregiverHash,
    String? patientHash,
    String? slotKey,
    CaregiverNotificationMode? mode,
    int? deadlineHour,
    int? deadlineMinute,
    bool clearDeadline = false,
  }) {
    return CaregiverNotification(
      notificationId: notificationId ?? this.notificationId,
      caregiverHash: caregiverHash ?? this.caregiverHash,
      patientHash: patientHash ?? this.patientHash,
      slotKey: slotKey ?? this.slotKey,
      mode: mode ?? this.mode,
      deadlineHour: clearDeadline ? null : deadlineHour ?? this.deadlineHour,
      deadlineMinute: clearDeadline
          ? null
          : deadlineMinute ?? this.deadlineMinute,
    );
  }

  // 함수이름: _readString
  // 함수역할: 선택적 필드를 공백 정리한 문자열로 바꾸고 없는 값은 빈 문자열로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // 반환값:
  // - String: 공백 정리한 필드 문자열; null이면 빈 문자열.
  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  // Function Name: _readInt
  // Description: Reads an integer or numeric string, truncating other numeric inputs, and uses null when parsing fails.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - int?: Reads an integer or numeric string, truncating other numeric inputs, and uses null when parsing fails.
  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
