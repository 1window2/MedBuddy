// 파일명: guardian_alert_setting_entity.dart
// 역할: 보호자 알림 설정 상태를 표현한다.

// 클래스명: GuardianAlertSetting
// 역할: 보호자/환자 식별자와 보호자 알림 활성 상태를 보관한다.
// 주요 책임:
// - 백엔드 guardian alert setting 응답을 앱에서 사용할 값으로 변환한다.
// - UML의 alertOption과 UI toggle 상태를 함께 보존한다.
class GuardianAlertSetting {
  final int? settingID;
  final String guardianID;
  final String patientID;
  final bool enabled;
  final String alertOption;

  const GuardianAlertSetting({
    this.settingID,
    this.guardianID = '',
    this.patientID = '',
    this.enabled = false,
    this.alertOption = 'disable',
  });

  factory GuardianAlertSetting.fromJson(Map<String, dynamic> json) {
    final rawAlertOption = _readString(
      json['alert_option'] ?? json['alertOption'],
    );
    final rawEnabled = json['is_enabled'] ?? json['enabled'];
    final enabled =
        rawEnabled == null ? _readBool(rawAlertOption) : _readBool(rawEnabled);
    return GuardianAlertSetting(
      settingID:
          _readInt(json['setting_id'] ?? json['settingID'] ?? json['id']),
      guardianID: _readString(
        json['guardian_hash'] ??
            json['guardian_id'] ??
            json['guardianID'] ??
            json['caregiver_hash'],
      ),
      patientID: _readString(
        json['patient_hash'] ?? json['patient_id'] ?? json['patientID'],
      ),
      enabled: enabled,
      alertOption: rawAlertOption.trim().isEmpty
          ? _alertOptionFromEnabled(enabled)
          : rawAlertOption,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'setting_id': settingID,
      'guardian_hash': guardianID,
      'patient_hash': patientID,
      'is_enabled': enabled,
      'alert_option': alertOption,
    };
  }

  // 함수명: saveGuardianAlertSetting
  // 함수역할:
  // - 클래스 다이어그램의 저장 연산에 대응하는 직렬화 payload를 반환한다.
  // 반환값:
  // - JSON-compatible guardian alert setting map
  Map<String, dynamic> saveGuardianAlertSetting() {
    return toJson();
  }

  GuardianAlertSetting enable() {
    return copyWith(enabled: true, alertOption: 'enable');
  }

  GuardianAlertSetting disable() {
    return copyWith(enabled: false, alertOption: 'disable');
  }

  GuardianAlertSetting copyWith({
    int? settingID,
    String? guardianID,
    String? patientID,
    bool? enabled,
    String? alertOption,
  }) {
    final nextEnabled = enabled ?? this.enabled;
    return GuardianAlertSetting(
      settingID: settingID ?? this.settingID,
      guardianID: guardianID ?? this.guardianID,
      patientID: patientID ?? this.patientID,
      enabled: nextEnabled,
      alertOption: alertOption ?? _alertOptionFromEnabled(nextEnabled),
    );
  }

  static String _readString(dynamic value) {
    return value?.toString() ?? '';
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalizedValue = value?.toString().trim().toLowerCase() ?? '';
    return normalizedValue == 'true' ||
        normalizedValue == '1' ||
        normalizedValue == 'enable' ||
        normalizedValue == 'enabled';
  }

  static String _alertOptionFromEnabled(bool enabled) {
    return enabled ? 'enable' : 'disable';
  }
}
