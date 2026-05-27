import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/medbuddy_view_model.dart';
import 'prescription_input_ui.dart';
import 'prescription_loading_ui.dart';
import 'prescription_result_ui.dart';
import 'saved_medication_ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();

    if (viewModel.isPrescriptionAnalyzing) {
      return PrescriptionLoadingUI(statusMessage: viewModel.statusMessage);
    }

    if (viewModel.medicationCandidates.isNotEmpty) {
      return PrescriptionResultUI(
        medicationCandidates: viewModel.medicationCandidates,
        statusMessageProvider: () => viewModel.statusMessage,
        isMedicationSaving: viewModel.isMedicationSaving,
        onCloseRequested: viewModel.clearPrescriptionAnalysisResult,
        onMedicationSaveRequested: viewModel.requestMedicationSave,
      );
    }

    return PrescriptionInputUI(
      statusMessage: viewModel.statusMessage,
      onPrescriptionScanRequested: viewModel.requestPrescriptionImage,
      onSavedMedicationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SavedMedicationUI(),
          ),
        );
      },
    );
  }
}
