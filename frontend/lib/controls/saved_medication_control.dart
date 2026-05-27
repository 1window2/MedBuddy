import '../models/saved_medication_info.dart';
import '../services/medication_api_boundary.dart';

class SavedMedicationControl {
  final MedicationAPIBoundary medicationAPIBoundary;

  SavedMedicationControl({MedicationAPIBoundary? medicationAPIBoundary})
      : medicationAPIBoundary =
            medicationAPIBoundary ?? MedicationAPIBoundary();

  Future<List<SavedMedicationInfo>> requestSavedMedicationInfo() {
    return medicationAPIBoundary.requestSavedMedicationInfoList();
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) {
    return medicationAPIBoundary.requestDeleteSavedMedication(
      savedMedicationId,
    );
  }
}
