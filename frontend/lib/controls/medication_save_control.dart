import '../models/medication_candidate.dart';
import '../models/medication_info.dart';
import '../services/medication_api_boundary.dart';

class MedicationSaveControl {
  final MedicationAPIBoundary medicationAPIBoundary;

  MedicationSaveControl({MedicationAPIBoundary? medicationAPIBoundary})
      : medicationAPIBoundary =
            medicationAPIBoundary ?? MedicationAPIBoundary();

  Future<MedicationInfo?> requestMedicationInfo(
    MedicationCandidate medicationCandidate,
  ) async {
    final drugName = medicationCandidate.drugName.trim();
    if (drugName.isEmpty) {
      return null;
    }

    final medicationInfoList =
        await medicationAPIBoundary.requestMedicationInfo(drugName);
    return medicationInfoList.isEmpty ? null : medicationInfoList.first;
  }

  Future<bool> requestMedicationSave(MedicationInfo medicationInfo) {
    return medicationAPIBoundary.saveMedicationInfo(medicationInfo);
  }
}
