// File Name: medbuddy_view_model_analysis_test.dart
// Role: Verifies prescription analysis state handling in MedBuddyViewModel.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

class _FakeInputPrescription extends InputPrescription {
  final List<MedicationSchedule> schedules;

  _FakeInputPrescription(this.schedules);

  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    onImageSelected?.call();
    return schedules;
  }
}

class _FakeCheckMedicationDetail extends CheckMedicationDetail {
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    if (medicationSchedule.medicationName == 'missing-tablet') {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

void main() {
  test('requestMedicationAnalysis surfaces partial lookup failures', () async {
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(
        const [
          MedicationSchedule(medicationName: 'found-tablet'),
          MedicationSchedule(medicationName: 'missing-tablet'),
        ],
      ),
      checkMedicationDetail: _FakeCheckMedicationDetail(),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestMedicationAnalysis();

    expect(viewModel.prescriptionFlowState,
        PrescriptionFlowState.analysisSucceeded);
    expect(viewModel.analyzedMedicationList, hasLength(1));
    expect(viewModel.statusMessage, contains('1개 약 정보'));
  });
}
