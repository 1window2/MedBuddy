import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
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

  test('fetchHealthRecommendation uses selected medication access scope',
      () async {
    final client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/health/recommendation');
      expect(request.url.queryParameters['patient_hash'], 'patient-b');
      expect(request.url.queryParameters['user_hash'], 'guardian-a');
      expect(request.url.queryParameters['role'], 'guardian');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'diet_recommendation': 'diet',
            'exercise_recommendation': 'exercise',
            'caution_items': ['caution'],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final viewModel = MedBuddyViewModel(
      checkHealthRecommendation: CheckHealthRecommendation(
        baseUrl: 'http://localhost',
        client: client,
      ),
    );
    addTearDown(viewModel.dispose);

    viewModel.setMedicationAccessScope(
      patientHash: 'patient-b',
      userHash: 'guardian-a',
      role: 'guardian',
    );
    await viewModel.fetchHealthRecommendation();

    expect(viewModel.healthRecommendation?.dietRecommendation, 'diet');
  });
}
