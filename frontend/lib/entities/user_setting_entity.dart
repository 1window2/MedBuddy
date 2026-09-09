// 파일명: user_setting_entity.dart
// 역할: 사용자 접근성/언어 설정 값을 표현하는 모델을 정의한다.

// 클래스명: UserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 앱 전체에서 동일한 형식으로 사용하게 한다.
// 주요 책임:
// - 설정 화면 옵션 문자열과 실제 수치 값을 서로 변환한다.
// - 화면 텍스트 확대 비율을 계산한다.
// - 불변 객체 방식으로 변경된 설정 값을 생성한다.
// 속성:
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - fontSize (int): 사용자 기본 글씨 크기
// - readingSpeed (double): 사용자 읽기 배속 선택값
// - language (String): 표시·음성 안내에 사용할 언어 코드
// - languageMode (String): system·ko·en 언어 선택 모드
// - timeFormat (String): 12h 또는 24h 시각 표시 방식
// - medicationNotificationsEnabled (bool): 본인 복약 시간 알림 허용 여부
// - caregiverNotificationsEnabled (bool): 보호자 복약 상태 알림 허용 여부
// - chatNotificationsEnabled (bool): 가족 채팅 알림 허용 여부
// - notificationDetailMode (String): full 또는 type_only 알림 세부 표시 모드
// - defaultMorningTime (String): 새 아침 알림의 HH:mm 기본 시각
// - defaultLunchTime (String): 새 점심 알림의 HH:mm 기본 시각
// - defaultEveningTime (String): 새 저녁 알림의 HH:mm 기본 시각
// - defaultBedtime (String): 새 취침 전 알림의 HH:mm 기본 시각
// - multiPillIdentificationLabEnabled (bool): 다중 알약 식별 실험 기능 노출 여부
class UserSetting {
  final String userHash;
  final int fontSize;
  final double readingSpeed;
  final String language;
  final String languageMode;
  final String timeFormat;
  final bool medicationNotificationsEnabled;
  final bool caregiverNotificationsEnabled;
  final bool chatNotificationsEnabled;
  final String notificationDetailMode;
  final String defaultMorningTime;
  final String defaultLunchTime;
  final String defaultEveningTime;
  final String defaultBedtime;
  final bool multiPillIdentificationLabEnabled;

  // 함수이름: UserSetting
  // 함수역할: 사용자별 글씨·음성·언어·시간제·알림·기본 복약 시간과 기기 전용 실험실 선택을 보존한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - fontSize (int): 사용자 기본 글씨 크기
  // - readingSpeed (double): 사용자 읽기 배속 선택값
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // - languageMode (String): system·ko·en 언어 선택 모드
  // - timeFormat (String): 12h 또는 24h 시각 표시 방식
  // - medicationNotificationsEnabled (bool): 본인 복약 시간 알림 허용 여부
  // - caregiverNotificationsEnabled (bool): 보호자 복약 상태 알림 허용 여부
  // - chatNotificationsEnabled (bool): 가족 채팅 알림 허용 여부
  // - notificationDetailMode (String): full 또는 type_only 알림 세부 표시 모드
  // - defaultMorningTime (String): 새 아침 알림의 HH:mm 기본 시각
  // - defaultLunchTime (String): 새 점심 알림의 HH:mm 기본 시각
  // - defaultEveningTime (String): 새 저녁 알림의 HH:mm 기본 시각
  // - defaultBedtime (String): 새 취침 전 알림의 HH:mm 기본 시각
  // - multiPillIdentificationLabEnabled (bool): 다중 알약 식별 실험 기능 노출 여부
  // 반환값:
  // - UserSetting: 초기화된 인스턴스.
  const UserSetting({
    this.userHash = '',
    this.fontSize = 16,
    this.readingSpeed = 1.0,
    this.language = 'ko',
    this.languageMode = 'ko',
    this.timeFormat = '24h',
    this.medicationNotificationsEnabled = true,
    this.caregiverNotificationsEnabled = true,
    this.chatNotificationsEnabled = true,
    this.notificationDetailMode = 'full',
    this.defaultMorningTime = '08:00',
    this.defaultLunchTime = '12:00',
    this.defaultEveningTime = '18:00',
    this.defaultBedtime = '22:00',
    this.multiPillIdentificationLabEnabled = false,
  });

  // 함수이름: UserSetting.fromJson
  // 함수역할: 현재·구형 설정 필드를 읽고 누락 값에 기본값을 적용하며 언어 모드·시간제·알림 상세·시각 문자열을 정규화한다.
  // 매개변수:
  // - json (Map<String, dynamic>): 해당 모델의 서버 응답 또는 저장 JSON 객체
  // 반환값:
  // - UserSetting: 필드 검증과 기본값 처리를 거쳐 복원한 레코드.
  factory UserSetting.fromJson(Map<String, dynamic> json) {
    final language = _readString(json['language']);
    return UserSetting(
      userHash: _readString(json['user_hash'] ?? json['userHash']),
      fontSize: _readInt(json['font_size'] ?? json['fontSize']) ?? 16,
      readingSpeed:
          _readDouble(json['reading_speed'] ?? json['readingSpeed']) ?? 1.0,
      language: language.isEmpty ? 'ko' : language,
      languageMode: _normalizedLanguageMode(
        _readString(json['language_mode'] ?? json['languageMode']),
        fallbackLanguage: language,
      ),
      timeFormat: _normalizedTimeFormat(
        _readString(json['time_format'] ?? json['timeFormat']),
      ),
      medicationNotificationsEnabled: _readBool(
        json['medication_notifications_enabled'] ??
            json['medicationNotificationsEnabled'],
        fallback: true,
      ),
      caregiverNotificationsEnabled: _readBool(
        json['caregiver_notifications_enabled'] ??
            json['caregiverNotificationsEnabled'],
        fallback: true,
      ),
      chatNotificationsEnabled: _readBool(
        json['chat_notifications_enabled'] ?? json['chatNotificationsEnabled'],
        fallback: true,
      ),
      notificationDetailMode: _normalizedNotificationDetailMode(
        _readString(
          json['notification_detail_mode'] ?? json['notificationDetailMode'],
        ),
      ),
      defaultMorningTime: _normalizedTime(
        _readString(json['default_morning_time'] ?? json['defaultMorningTime']),
        fallback: '08:00',
      ),
      defaultLunchTime: _normalizedTime(
        _readString(json['default_lunch_time'] ?? json['defaultLunchTime']),
        fallback: '12:00',
      ),
      defaultEveningTime: _normalizedTime(
        _readString(json['default_evening_time'] ?? json['defaultEveningTime']),
        fallback: '18:00',
      ),
      defaultBedtime: _normalizedTime(
        _readString(json['default_bedtime'] ?? json['defaultBedtime']),
        fallback: '22:00',
      ),
      multiPillIdentificationLabEnabled:
          json['multi_pill_identification_lab_enabled'] == true ||
          json['multiPillIdentificationLabEnabled'] == true,
    );
  }

  // 함수이름: fontSizeOption
  // 함수역할: 14 이하를 small, 20 이상을 large, 그 사이를 medium으로 분류해 글씨 크기 선택 상태를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 14 이하를 small, 20 이상을 large, 그 사이를 medium으로 분류해 글씨 크기 선택 상태를 제공한다.
  String get fontSizeOption {
    if (fontSize <= 14) {
      return 'small';
    }
    if (fontSize >= 20) {
      return 'large';
    }
    return 'medium';
  }

  // 함수이름: readingSpeedOption
  // 함수역할: 읽기 배속이 1 미만이면 slow, 1 초과이면 fast, 같으면 medium 선택값을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 읽기 배속이 1 미만이면 slow, 1 초과이면 fast, 같으면 medium 선택값을 제공한다.
  String get readingSpeedOption {
    if (readingSpeed < 1.0) {
      return 'slow';
    }
    if (readingSpeed > 1.0) {
      return 'fast';
    }
    return 'medium';
  }

  // 함수이름: contentTextScale
  // 함수역할: 이미 앱 전역에서 적용된 글씨 확대를 콘텐츠에서 중복 적용하지 않도록 1.0 배율을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - double: 이미 앱 전역에서 적용된 글씨 확대를 콘텐츠에서 중복 적용하지 않도록 1.0 배율을 제공한다.
  double get contentTextScale {
    // 사용자 글씨 크기는 앱 최상단 MediaQuery에서 한 번만 적용한다.
    // 기존 화면의 개별 배율 코드는 1.0을 받아 이중 확대를 방지한다.
    return 1.0;
  }

  // 함수이름: use24HourTime
  // 함수역할: 사용자가 24시간제 시각 표시를 선택했는지 판정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 사용자가 24시간제 시각 표시를 선택했는지 판정한다.
  bool get use24HourTime => timeFormat == '24h';

  // 함수이름: showNotificationDetails
  // 함수역할: 알림 상세 모드가 full일 때에만 약명과 메시지 등 민감한 세부 정보 표시를 허용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 알림 상세 모드가 full일 때에만 약명과 메시지 등 민감한 세부 정보 표시를 허용한다.
  bool get showNotificationDetails => notificationDetailMode == 'full';

  // 함수이름: defaultTimeForSlot
  // 함수역할: 복약 시간대에 대응하는 신규 일정 기본 시각을 반환한다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 복약 시간대에 대응하는 신규 일정 기본 시각을 반환한다.
  String defaultTimeForSlot(String slotKey) {
    return switch (slotKey) {
      'morning' => defaultMorningTime,
      'lunch' => defaultLunchTime,
      'evening' => defaultEveningTime,
      'bedtime' => defaultBedtime,
      _ => '08:00',
    };
  }

  // 함수이름: formatTime
  // 함수역할: 사용자가 선택한 12시간제 또는 24시간제 방식으로 시각을 표시한다.
  // 매개변수:
  // - hour (int): 24시간제 지역 시각의 시
  // - minute (int): 지역 시각의 분
  // 반환값:
  // - String: 사용자가 선택한 12시간제 또는 24시간제 방식으로 시각을 표시한다.
  String formatTime(int hour, int minute) {
    final safeHour = hour.clamp(0, 23).toInt();
    final safeMinute = minute.clamp(0, 59).toInt();
    if (use24HourTime) {
      return '${safeHour.toString().padLeft(2, '0')}:'
          '${safeMinute.toString().padLeft(2, '0')}';
    }
    final period = safeHour < 12
        ? (language == 'en' ? 'AM' : '오전')
        : (language == 'en' ? 'PM' : '오후');
    final displayHour = safeHour % 12 == 0 ? 12 : safeHour % 12;
    return '$period $displayHour:${safeMinute.toString().padLeft(2, '0')}';
  }

  // 함수이름: formatTimeValue
  // 함수역할: HH:mm 저장값을 현재 시간 표시 방식으로 변환한다.
  // 매개변수:
  // - value (String): 사용자 시각 형식으로 표시할 저장된 시각 문구
  // 반환값:
  // - String: HH:mm 저장값을 현재 시간 표시 방식으로 변환한다.
  String formatTimeValue(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return value;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return value;
    }
    return formatTime(hour, minute);
  }

  // 함수이름: preferredTextScale
  // 함수역할: 환경설정에서 선택한 글씨 크기를 앱 전역 배율로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 작게 0.92배, 중간 1.0배, 크게 1.30배 중 하나
  double get preferredTextScale {
    if (fontSize <= 14) {
      return 0.92;
    }
    if (fontSize >= 20) {
      return 1.30;
    }
    return 1.0;
  }

  // 함수이름: resolveTextScale
  // 함수역할: 앱 설정과 운영체제 접근성 글씨 크기 중 더 읽기 쉬운 값을 선택한다. 운영체제 배율이 1배를 넘으면 사용자 설정으로 축소하지 않는다. 과도한 확대에 따른 화면 붕괴를 막기 위해 최대 2배로 제한한다.
  // 매개변수:
  // - systemTextScale (double): 운영체제가 제공한 현재 글씨 배율
  // 반환값:
  // - 앱 전체 MediaQuery에 적용할 최종 글씨 배율
  double resolveTextScale(double systemTextScale) {
    final normalizedSystemScale =
        systemTextScale.isFinite && systemTextScale > 0 ? systemTextScale : 1.0;
    final resolvedScale = normalizedSystemScale > 1.0
        ? (normalizedSystemScale > preferredTextScale
              ? normalizedSystemScale
              : preferredTextScale)
        : preferredTextScale;
    return resolvedScale.clamp(0.92, 2.0).toDouble();
  }

  // 함수이름: copyWith
  // 함수역할: 기존 설정을 유지하면서 일부 값만 바꾼 새 설정 객체를 만든다.
  // 매개변수:
  // - userHash (String?): 현재 사용자 소유권·표시·저장 범위의 해시
  // - fontSize (int?): 사용자 기본 글씨 크기
  // - readingSpeed (double?): 사용자 읽기 배속 선택값
  // - language (String?): 표시·음성 안내에 사용할 언어 코드
  // - languageMode (String?): system·ko·en 언어 선택 모드
  // - timeFormat (String?): 12h 또는 24h 시각 표시 방식
  // - medicationNotificationsEnabled (bool?): 본인 복약 시간 알림 허용 여부
  // - caregiverNotificationsEnabled (bool?): 보호자 복약 상태 알림 허용 여부
  // - chatNotificationsEnabled (bool?): 가족 채팅 알림 허용 여부
  // - notificationDetailMode (String?): full 또는 type_only 알림 세부 표시 모드
  // - defaultMorningTime (String?): 새 아침 알림의 HH:mm 기본 시각
  // - defaultLunchTime (String?): 새 점심 알림의 HH:mm 기본 시각
  // - defaultEveningTime (String?): 새 저녁 알림의 HH:mm 기본 시각
  // - defaultBedtime (String?): 새 취침 전 알림의 HH:mm 기본 시각
  // - multiPillIdentificationLabEnabled (bool?): 다중 알약 식별 실험 기능 노출 여부
  // 반환값:
  // - 변경값이 반영된 UserSetting 인스턴스
  UserSetting copyWith({
    String? userHash,
    int? fontSize,
    double? readingSpeed,
    String? language,
    String? languageMode,
    String? timeFormat,
    bool? medicationNotificationsEnabled,
    bool? caregiverNotificationsEnabled,
    bool? chatNotificationsEnabled,
    String? notificationDetailMode,
    String? defaultMorningTime,
    String? defaultLunchTime,
    String? defaultEveningTime,
    String? defaultBedtime,
    bool? multiPillIdentificationLabEnabled,
  }) {
    return UserSetting(
      userHash: userHash ?? this.userHash,
      fontSize: fontSize ?? this.fontSize,
      readingSpeed: readingSpeed ?? this.readingSpeed,
      language: language ?? this.language,
      languageMode: languageMode ?? this.languageMode,
      timeFormat: timeFormat ?? this.timeFormat,
      medicationNotificationsEnabled:
          medicationNotificationsEnabled ?? this.medicationNotificationsEnabled,
      caregiverNotificationsEnabled:
          caregiverNotificationsEnabled ?? this.caregiverNotificationsEnabled,
      chatNotificationsEnabled:
          chatNotificationsEnabled ?? this.chatNotificationsEnabled,
      notificationDetailMode:
          notificationDetailMode ?? this.notificationDetailMode,
      defaultMorningTime: defaultMorningTime ?? this.defaultMorningTime,
      defaultLunchTime: defaultLunchTime ?? this.defaultLunchTime,
      defaultEveningTime: defaultEveningTime ?? this.defaultEveningTime,
      defaultBedtime: defaultBedtime ?? this.defaultBedtime,
      multiPillIdentificationLabEnabled:
          multiPillIdentificationLabEnabled ??
          this.multiPillIdentificationLabEnabled,
    );
  }

  // Function Name: updateUserSetting
  // Description: Produces a settings copy with new text size, speech rate, and language while retaining unrelated preferences.
  // Parameters:
  // - fontSize (int): User-selected base text size.
  // - readingSpeed (double): User-selected speech-rate multiplier.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - UserSetting: Produces a settings copy with new text size, speech rate, and language while retaining unrelated preferences.
  UserSetting updateUserSetting({
    required int fontSize,
    required double readingSpeed,
    required String language,
  }) {
    return copyWith(
      fontSize: fontSize,
      readingSpeed: readingSpeed,
      language: language,
    );
  }

  // 함수이름: toJson
  // 함수역할: 사용자 접근성·언어·알림·기본 시간을 서버 필드명으로 직렬화하고 기기 전용 실험실 설정은 제외한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Map<String, dynamic>: 사용자 접근성·언어·알림·기본 시간을 서버 필드명으로 직렬화하고 기기 전용 실험실 설정은 제외한다.
  Map<String, dynamic> toJson() {
    return {
      'user_hash': userHash,
      'font_size': fontSize,
      'reading_speed': readingSpeed,
      'language': language,
      'language_mode': languageMode,
      'time_format': timeFormat,
      'medication_notifications_enabled': medicationNotificationsEnabled,
      'caregiver_notifications_enabled': caregiverNotificationsEnabled,
      'chat_notifications_enabled': chatNotificationsEnabled,
      'notification_detail_mode': notificationDetailMode,
      'default_morning_time': defaultMorningTime,
      'default_lunch_time': defaultLunchTime,
      'default_evening_time': defaultEveningTime,
      'default_bedtime': defaultBedtime,
    };
  }

  // 함수이름: fontSizeFromOption
  // 함수역할: 설정 화면의 글씨 크기 옵션 문자열을 실제 font size 값으로 변환한다.
  // 매개변수:
  // - option (String): small, medium, large 중 하나
  // 반환값:
  // - 앱에서 사용할 font size 정수값
  static int fontSizeFromOption(String option) {
    return switch (option) {
      'small' => 14,
      'large' => 20,
      _ => 16,
    };
  }

  // 함수이름: readingSpeedFromOption
  // 함수역할: 설정 화면의 읽기 속도 옵션 문자열을 실제 배속 값으로 변환한다.
  // 매개변수:
  // - option (String): slow, medium, fast 중 하나
  // 반환값:
  // - 음성/읽기 속도에 사용할 배속 값
  static double readingSpeedFromOption(String option) {
    return switch (option) {
      'slow' => 0.8,
      'fast' => 1.2,
      _ => 1.0,
    };
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
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  // Function Name: _readDouble
  // Description: Converts numeric input or a numeric string to a double, using null when conversion fails.
  // Parameters:
  // - value (dynamic): Raw response field to decode into the documented return type.
  // Returns:
  // - double?: Converts numeric input or a numeric string to a double, using null when conversion fails.
  static double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  // 함수이름: _readBool
  // 함수역할: 불리언·0 여부·true/false 및 1/0 문자열을 해석하고 알 수 없는 값은 지정한 기본값으로 처리한다.
  // 매개변수:
  // - value (dynamic): 반환 타입의 값으로 해석할 변환 전 응답 필드
  // - fallback (bool): 값이 없거나 해석 불가할 때 사용할 대체값
  // 반환값:
  // - bool: 불리언·0 여부·true/false 및 1/0 문자열을 해석하고 알 수 없는 값은 지정한 기본값으로 처리한다.
  static bool _readBool(dynamic value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return fallback;
  }

  // 함수이름: _normalizedLanguageMode
  // 함수역할: system·ko·en만 허용하고 다른 값은 대체 언어에 따라 영어 또는 한국어 모드로 보정한다.
  // 매개변수:
  // - value (String): system·ko·en으로 제한할 저장 언어 선택값
  // - fallbackLanguage (String): 유효한 모드가 없을 때 사용할 앱 언어
  // 반환값:
  // - String: system·ko·en만 허용하고 다른 값은 대체 언어에 따라 영어 또는 한국어 모드로 보정한다.
  static String _normalizedLanguageMode(
    String value, {
    required String fallbackLanguage,
  }) {
    if (value == 'system' || value == 'ko' || value == 'en') {
      return value;
    }
    return fallbackLanguage == 'en' ? 'en' : 'ko';
  }

  // 함수이름: _normalizedTimeFormat
  // 함수역할: 12h 선택만 12시간제로 인정하고 그 외 값은 24시간제로 보정한다.
  // 매개변수:
  // - value (String): 12h·24h로 제한할 저장 시각 형식
  // 반환값:
  // - String: 12h 선택만 12시간제로 인정하고 그 외 값은 24시간제로 보정한다.
  static String _normalizedTimeFormat(String value) {
    return value == '12h' ? '12h' : '24h';
  }

  // 함수이름: _normalizedNotificationDetailMode
  // 함수역할: type_only 선택만 세부 숨김으로 인정하고 그 외 값은 전체 표시로 보정한다.
  // 매개변수:
  // - value (String): full·type_only로 제한할 알림 상세 표시값
  // 반환값:
  // - String: type_only 선택만 세부 숨김으로 인정하고 그 외 값은 전체 표시로 보정한다.
  static String _normalizedNotificationDetailMode(String value) {
    return value == 'type_only' ? 'type_only' : 'full';
  }

  // 함수이름: _normalizedTime
  // 함수역할: H:mm 또는 HH:mm의 유효한 시·분을 두 자리로 맞추고 형식이나 범위가 잘못되면 지정된 기본 시각을 사용한다.
  // 매개변수:
  // - value (String): 시·분 범위를 검사할 저장된 HH:mm 문구
  // - fallback (String): 값이 없거나 해석 불가할 때 사용할 대체값
  // 반환값:
  // - String: H:mm 또는 HH:mm의 유효한 시·분을 두 자리로 맞추고 형식이나 범위가 잘못되면 지정된 기본 시각을 사용한다.
  static String _normalizedTime(String value, {required String fallback}) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (match == null) {
      return fallback;
    }
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return fallback;
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

// 클래스명: UserSettingSaveResult
// 역할: 설정값과 서버 동기화 성공 여부를 함께 전달한다.
// 주요 책임:
// - 화면이 서버 저장과 기기 전용 저장을 구분해 안내할 수 있게 한다.
// 속성:
// - setting (UserSetting): 복원·저장·적용할 사용자 환경 설정
// - synchronizedWithServer (bool): 기기 저장 외에 서버 동기화까지 성공했는지 여부
class UserSettingSaveResult {
  final UserSetting setting;
  final bool synchronizedWithServer;

  // 함수이름: UserSettingSaveResult
  // 함수역할: 저장 후 적용할 설정과 서버 동기화 성공 여부를 함께 보존해 기기 저장과 원격 저장을 구분한다.
  // 매개변수:
  // - setting (UserSetting): 복원·저장·적용할 사용자 환경 설정
  // - synchronizedWithServer (bool): 기기 저장 외에 서버 동기화까지 성공했는지 여부
  // 반환값:
  // - UserSettingSaveResult: 초기화된 인스턴스.
  const UserSettingSaveResult({
    required this.setting,
    required this.synchronizedWithServer,
  });
}
