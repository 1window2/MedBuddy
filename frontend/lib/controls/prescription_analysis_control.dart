import 'package:image_picker/image_picker.dart';

import '../models/prescription_analysis_result.dart';
import '../services/medication_api_boundary.dart';

class PrescriptionAnalysisControl {
  final MedicationAPIBoundary medicationAPIBoundary;
  final ImagePicker _imagePicker;

  PrescriptionAnalysisControl({
    MedicationAPIBoundary? medicationAPIBoundary,
    ImagePicker? imagePicker,
  })  : medicationAPIBoundary =
            medicationAPIBoundary ?? MedicationAPIBoundary(),
        _imagePicker = imagePicker ?? ImagePicker();

  Future<PrescriptionAnalysisResult?> requestPrescriptionImage() async {
    final pickedFile = await _imagePicker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) {
      return null;
    }

    return medicationAPIBoundary.requestPrescriptionAnalysis(pickedFile.path);
  }
}
