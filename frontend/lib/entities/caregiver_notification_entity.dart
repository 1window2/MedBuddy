// 파일명: caregiver_notification_entity.dart
// 역할: 보호자 알림 설정 상태를 표현한다.

// 클래스명: CaregiverNotification
// 역할: 보호자/환자 식별자와 보호자 알림 활성 상태를 보관한다.
// 주요 책임:
// - 백엔드 caregiver notification 응답과 legacy guardian alias를 변환한다.
// - UML의 notificationType과 UI toggle 상태를 함께 보존한다.
class CaregiverNotification {
  final int? notificationId;
  final String caregiverHash;
  final String patientHash;
  final bool notificationEnabled;
  final String notificationType;

  const CaregiverNotification({
    this.notificationId,
    this.caregiverHash = '',
    this.patientHash = '',
    this.notificationEnabled = false,
    this.notificationType = 'disable',
  });

  factory CaregiverNotification.fromJson(Map<String, dynamic> json) {
    final rawAlertOption = _readString(
      json['notification_type'] ??
          json['notificationType'] ??
          json['alert_option'] ??
          json['alertOption'],
    );
    final rawEnabled = json['notification_enabled'] ??
        json['notificationEnabled'] ??
        json['is_enabled'] ??
        json['enabled'];
    final enabled =
        rawEnabled == null ? _readBool(rawAlertOption) : _readBool(rawEnabled);
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
      notificationEnabled: enabled,
      notificationType: rawAlertOption.trim().isEmpty
          ? _alertOptionFromEnabled(enabled)
          : rawAlertOption,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'caregiver_hash': caregiverHash,
      'patient_hash': patientHash,
      'notification_enabled': notificationEnabled,
      'notification_type': notificationType,
    };
  }

  CaregiverNotification updateNotificationSetting(bool notificationOption) {
    return copyWith(
      notificationEnabled: notificationOption,
      notificationType: _alertOptionFromEnabled(notificationOption),
    );
  }

  CaregiverNotification copyWith({
    int? notificationId,
    String? caregiverHash,
    String? patientHash,
    bool? notificationEnabled,
    String? notificationType,
  }) {
    final nextEnabled = notificationEnabled ?? this.notificationEnabled;
    return CaregiverNotification(
      notificationId: notificationId ?? this.notificationId,
      caregiverHash: caregiverHash ?? this.caregiverHash,
      patientHash: patientHash ?? this.patientHash,
      notificationEnabled: nextEnabled,
      notificationType:
          notificationType ?? _alertOptionFromEnabled(nextEnabled),
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
