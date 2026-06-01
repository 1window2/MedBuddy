class MedicationInfo {
  final int? id;
  final String itemName;
  final String efficacy;
  final String useMethod;
  final String warningMessage;
  final String aiGuide;

  const MedicationInfo({
    this.id,
    required this.itemName,
    required this.efficacy,
    required this.useMethod,
    required this.warningMessage,
    this.aiGuide = '',
  });

  factory MedicationInfo.fromJson(Map<String, dynamic> json) {
    return MedicationInfo(
      id: _readInt(json['id']),
      itemName: _readString(json['item_name']),
      efficacy: _readString(json['efficacy']),
      useMethod: _readString(json['use_method']),
      warningMessage: _readString(json['warning_message']),
      aiGuide: _readString(json['ai_guide']),
    );
  }

  Map<String, dynamic> toSaveJson() {
    return {
      'item_name': itemName,
      'efficacy': efficacy,
      'use_method': useMethod,
      'warning_message': warningMessage,
      'ai_guide': aiGuide,
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
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
