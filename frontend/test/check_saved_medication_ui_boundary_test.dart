import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_saved_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/set_guardian_alert_setting_control.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('patient saved list does not expose guardian alert control',
      (tester) async {
    final client = MockClient(_savedMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('알림 설정'), findsNothing);
  });

  testWidgets('guardian bell reads and updates the persisted alert setting',
      (tester) async {
    Map<String, dynamic>? updatePayload;
    final client = MockClient((request) async {
      if (request.url.path == '/list') {
        expect(request.url.queryParameters['role'], 'guardian');
        expect(request.url.queryParameters['user_hash'], 'guardian-a');
        return _savedMedicationResponse(request);
      }
      if (request.url.path == '/guardian-alert/settings/patient-a') {
        expect(request.url.queryParameters['guardian_hash'], 'guardian-a');
        if (request.method == 'PUT') {
          updatePayload = jsonDecode(request.body) as Map<String, dynamic>;
          return _guardianAlertResponse(enabled: true);
        }
        return _guardianAlertResponse(enabled: false);
      }
      return http.Response('Not found', 404);
    });
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    viewModel.setMedicationAccessScope(
      patientHash: 'patient-a',
      userHash: 'guardian-a',
      role: 'guardian',
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          home: CheckSavedMedicationUI(
            guardianAlertControlFactory: (guardianHash) {
              return SetGuardianAlertSetting(
                baseUrl: 'http://medbuddy.test',
                guardianHash: guardianHash,
                client: client,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    await tester.tap(find.byTooltip('알림 설정'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(updatePayload?['alert_option'], 'enable');
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
  });
}

Future<http.Response> _savedMedicationResponse(http.Request request) async {
  return http.Response(
    jsonEncode({
      'success': true,
      'data': [
        {
          'id': 1,
          'patient_hash':
              request.url.queryParameters['patient_hash'] ?? 'local_patient',
          'created_date': '2026-07-15',
          'prescription_date': '2026-07-15',
          'item_seq': '200000001',
          'item_name': 'test-tablet',
          'efficacy': 'effect',
          'use_method': 'usage',
          'warning_message': 'warning',
          'image_url': 'https://example.com/tablet.jpg',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.Response _guardianAlertResponse({required bool enabled}) {
  return http.Response(
    jsonEncode({
      'success': true,
      'data': {
        'guardian_hash': 'guardian-a',
        'patient_hash': 'patient-a',
        'is_enabled': enabled,
        'alert_option': enabled ? 'enable' : 'disable',
      },
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
