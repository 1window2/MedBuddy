import 'medication_info.dart';

class SavedMedicationInfo extends MedicationInfo {
  const SavedMedicationInfo({
    required int id,
    required super.itemName,
    required super.efficacy,
    required super.useMethod,
    required super.warningMessage,
    super.aiGuide = '',
  }) : super(id: id);

  factory SavedMedicationInfo.fromJson(Map<String, dynamic> json) {
    final medicationInfo = MedicationInfo.fromJson(json);

    return SavedMedicationInfo(
      id: medicationInfo.id ?? 0,
      itemName: medicationInfo.itemName,
      efficacy: medicationInfo.efficacy,
      useMethod: medicationInfo.useMethod,
      warningMessage: medicationInfo.warningMessage,
      aiGuide: medicationInfo.aiGuide,
    );
  }
}
