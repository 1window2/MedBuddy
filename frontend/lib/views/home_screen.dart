import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/medbuddy_view_model.dart';
import '../boundaries/check_result_ui_boundary.dart';
import '../boundaries/check_saved_medication_ui_boundary.dart';
import '../boundaries/input_prescription_ui_boundary.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();

    if (viewModel.isPrescriptionAnalyzing) {
      return InputPrescriptionUI.analyzing(
        statusMessage: viewModel.statusMessage,
      );
    }

    if (viewModel.medicationScheduleList.isNotEmpty) {
      return CheckResultUI(
        medicationScheduleList: viewModel.medicationScheduleList,
        statusMessageProvider: () => viewModel.statusMessage,
        savingMedicationIndex: viewModel.savingMedicationIndex,
        onCloseRequested: viewModel.clearAnalysisResult,
        onMedicationSaveRequested: viewModel.requestMedicationSave,
      );
    }

    return InputPrescriptionUI(
      statusMessage: viewModel.statusMessage,
      onPrescriptionScanRequested: viewModel.requestPrescriptionImage,
      onPrescriptionGalleryRequested:
          viewModel.requestPrescriptionImageFromGallery,
      onSavedMedicationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CheckSavedMedicationUI(),
          ),
        );
      },
    );
  }
}
