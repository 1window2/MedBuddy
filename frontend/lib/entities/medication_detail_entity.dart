class MedicationDetail {
  final int? id;
  final String itemName;
  final String efficacy;
  final String usageMethod;
  final String warning;
  final String precaution;
  final String interaction;
  final String sideEffect;
  final String storageMethod;
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;
  final String aiGuide;

  const MedicationDetail({
    this.id,
    required this.itemName,
    required this.efficacy,
    required this.usageMethod,
    required this.warning,
    this.precaution = '',
    this.interaction = '',
    this.sideEffect = '',
    this.storageMethod = '',
    this.dosagePerTime = '',
    this.dailyFrequency = '',
    this.totalDays = '',
    this.aiGuide = '',
  });

  factory MedicationDetail.fromJson(Map<String, dynamic> json) {
    return MedicationDetail(
      id: _readInt(json['id']),
      itemName: _readString(json['item_name']),
      efficacy: _readString(json['efficacy']),
      usageMethod: _readString(json['usage_method'] ?? json['use_method']),
      warning: _readString(json['warning'] ?? json['warning_message']),
      precaution: _readString(json['precaution']),
      interaction: _readString(json['interaction']),
      sideEffect: _readString(json['side_effect']),
      storageMethod: _readString(json['storage_method']),
      dosagePerTime: _readString(json['dosage_per_time']),
      dailyFrequency: _readString(json['daily_frequency']),
      totalDays: _readString(json['total_days']),
      aiGuide: _readString(json['ai_guide']),
    );
  }

  Map<String, dynamic> toSaveJson() {
    return {
      'item_name': itemName,
      'efficacy': efficacy,
      'use_method': usageMethod,
      'warning_message': warning,
      'dosage_per_time': dosagePerTime,
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
      'ai_guide': aiGuide,
    };
  }

  bool get hasScheduleInfo {
    return dosagePerTime.trim().isNotEmpty ||
        dailyFrequency.trim().isNotEmpty ||
        totalDays.trim().isNotEmpty;
  }

  void saveMedicationDetail() {
    throw UnsupportedError('약 상세 정보 저장은 CheckSavedMedication에서 처리합니다.');
  }

  MedicationDetail checkMedicationDetail() {
    return this;
  }

  MedicationDetail getMedicationDetail() {
    return this;
  }

  String getVoiceGuideText() {
    return [
      itemName,
      efficacy,
      usageMethod,
      dosagePerTime,
      dailyFrequency,
      totalDays,
      warning,
      aiGuide,
    ].where((text) => text.trim().isNotEmpty).join('\n');
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
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
