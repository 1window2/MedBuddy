class DrugInfo {
  final String itemName;
  final String efficacy;
  final String useMethod;
  final String warningMessage;
  final String? aiGuide;

  DrugInfo({
    required this.itemName,
    required this.efficacy,
    required this.useMethod,
    required this.warningMessage,
    this.aiGuide,
  });

  // JSON 데이터를 Dart 객체로 변환하는 팩토리 생성자
  factory DrugInfo.fromJson(Map<String, dynamic> json) {
    return DrugInfo(
      itemName: json['item_name'] ?? '정보 없음',
      efficacy: json['efficacy'] ?? '정보 없음',
      useMethod: json['use_method'] ?? '정보 없음',
      warningMessage: json['warning_message'] ?? '정보 없음',
      aiGuide: json['ai_guide'],
    );
  }
}