import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

void main() {
  test('setMedicationAccessScope persists selected guardian medication scope',
      () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      userHash: 'guardian-a',
      role: 'guardian',
    );

    expect(viewModel.medicationPatientHash, 'patient-a');
    expect(viewModel.medicationUserHash, 'guardian-a');
    expect(viewModel.medicationRole, 'guardian');
  });

  test('setMedicationAccessScope normalizes empty patient scope to default',
      () {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: ' ',
      role: 'patient',
    );

    expect(viewModel.medicationPatientHash, PatientHash.defaultPatientHash);
    expect(viewModel.medicationUserHash, isNull);
    expect(viewModel.medicationRole, 'patient');
  });
}
