// 파일명: user_setting_entity.dart
// 역할: 사용자 접근성/언어 설정 값을 표현하는 모델을 정의한다.

// 클래스명: UserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 앱 전체에서 동일한 형식으로 사용하게 한다.
// 주요 책임:
// - 설정 화면 옵션 문자열과 실제 수치 값을 서로 변환한다.
// - 화면 텍스트 확대 비율을 계산한다.
// - 불변 객체 방식으로 변경된 설정 값을 생성한다.
class UserSetting {
  final String userHash;
  final int fontSize;
  final double readingSpeed;
  final String language;
  final bool nearbyPharmacyLabEnabled;
  final bool linkedMedicationChatLabEnabled;

  const UserSetting({
    this.userHash = '',
    this.fontSize = 16,
    this.readingSpeed = 1.0,
    this.language = 'ko',
    this.nearbyPharmacyLabEnabled = false,
    this.linkedMedicationChatLabEnabled = false,
  });

  factory UserSetting.fromJson(Map<String, dynamic> json) {
    final language = _readString(json['language']);
    return UserSetting(
      userHash: _readString(json['user_hash'] ?? json['userHash']),
      fontSize: _readInt(json['font_size'] ?? json['fontSize']) ?? 16,
      readingSpeed:
          _readDouble(json['reading_speed'] ?? json['readingSpeed']) ?? 1.0,
      language: language.isEmpty ? 'ko' : language,
      nearbyPharmacyLabEnabled:
          json['nearby_pharmacy_lab_enabled'] == true ||
          json['nearbyPharmacyLabEnabled'] == true,
      linkedMedicationChatLabEnabled:
          json['linked_medication_chat_lab_enabled'] == true ||
          json['linkedMedicationChatLabEnabled'] == true,
    );
  }

  String get fontSizeOption {
    if (fontSize <= 14) {
      return 'small';
    }
    if (fontSize >= 20) {
      return 'large';
    }
    return 'medium';
  }

  String get readingSpeedOption {
    if (readingSpeed < 1.0) {
      return 'slow';
    }
    if (readingSpeed > 1.0) {
      return 'fast';
    }
    return 'medium';
  }

  double get contentTextScale {
    // 사용자 글씨 크기는 앱 최상단 MediaQuery에서 한 번만 적용한다.
    // 기존 화면의 개별 배율 코드는 1.0을 받아 이중 확대를 방지한다.
    return 1.0;
  }

  // 함수명: preferredTextScale
  // 함수역할:
  // - 환경설정에서 선택한 글씨 크기를 앱 전역 배율로 변환한다.
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

  // 함수명: resolveTextScale
  // 함수역할:
  // - 앱 설정과 운영체제 접근성 글씨 크기 중 더 읽기 쉬운 값을 선택한다.
  // - 운영체제 배율이 1배를 넘으면 사용자 설정으로 축소하지 않는다.
  // - 과도한 확대에 따른 화면 붕괴를 막기 위해 최대 2배로 제한한다.
  // 매개변수:
  // - systemTextScale: 운영체제가 제공한 현재 글씨 배율
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

  // 함수명: copyWith
  // 함수역할:
  // - 기존 설정을 유지하면서 일부 값만 바꾼 새 설정 객체를 만든다.
  // 반환값:
  // - 변경값이 반영된 UserSetting 인스턴스
  UserSetting copyWith({
    String? userHash,
    int? fontSize,
    double? readingSpeed,
    String? language,
    bool? nearbyPharmacyLabEnabled,
    bool? linkedMedicationChatLabEnabled,
  }) {
    return UserSetting(
      userHash: userHash ?? this.userHash,
      fontSize: fontSize ?? this.fontSize,
      readingSpeed: readingSpeed ?? this.readingSpeed,
      language: language ?? this.language,
      nearbyPharmacyLabEnabled:
          nearbyPharmacyLabEnabled ?? this.nearbyPharmacyLabEnabled,
      linkedMedicationChatLabEnabled:
          linkedMedicationChatLabEnabled ?? this.linkedMedicationChatLabEnabled,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'user_hash': userHash,
      'font_size': fontSize,
      'reading_speed': readingSpeed,
      'language': language,
    };
  }

  // 함수명: fontSizeFromOption
  // 함수역할:
  // - 설정 화면의 글씨 크기 옵션 문자열을 실제 font size 값으로 변환한다.
  // 매개변수:
  // - option: small, medium, large 중 하나
  // 반환값:
  // - 앱에서 사용할 font size 정수값
  static int fontSizeFromOption(String option) {
    return switch (option) {
      'small' => 14,
      'large' => 20,
      _ => 16,
    };
  }

  // 함수명: readingSpeedFromOption
  // 함수역할:
  // - 설정 화면의 읽기 속도 옵션 문자열을 실제 배속 값으로 변환한다.
  // 매개변수:
  // - option: slow, medium, fast 중 하나
  // 반환값:
  // - 음성/읽기 속도에 사용할 배속 값
  static double readingSpeedFromOption(String option) {
    return switch (option) {
      'slow' => 0.8,
      'fast' => 1.2,
      _ => 1.0,
    };
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

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
}

// 클래스명: UserSettingSaveResult
// 역할: 설정값과 서버 동기화 성공 여부를 함께 전달한다.
// 주요 책임:
// - 화면이 서버 저장과 기기 전용 저장을 구분해 안내할 수 있게 한다.
class UserSettingSaveResult {
  final UserSetting setting;
  final bool synchronizedWithServer;

  const UserSettingSaveResult({
    required this.setting,
    required this.synchronizedWithServer,
  });
}
