import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_saved_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('patient saved list does not expose guardian alert control', (
    tester,
  ) async {
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

  testWidgets('group delete reports mixed results instead of full success', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_mixedDeleteResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      checkSchedule: CheckSchedule(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);
    await viewModel.requestUserSettingSave(
      fontSizeOption: 'medium',
      readingSpeedOption: 'medium',
      language: 'en',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted: 1. Failed: 1.'), findsOneWidget);
    expect(find.text('Deleted.'), findsNothing);
    expect(
      viewModel.savedMedicationInfoList
          .map((medication) => medication.id)
          .toList(),
      [2],
    );
  });

  testWidgets(
    'saved medication list switches between registration and medication dates',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient(_sortableMedicationResponse);
      final viewModel = MedBuddyViewModel(
        checkSavedMedication: CheckSavedMedication(
          baseUrl: 'http://medbuddy.test',
          client: client,
        ),
        manageUserSetting: ManageUserSetting(useRemotePersistence: false),
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

      final newestRegistration = find.text('등록최신약');
      final newestMedicationDate = find.text('복용최신약');
      expect(find.text('등록일자순'), findsOneWidget);
      expect(find.text('복용날짜순'), findsOneWidget);
      expect(
        tester.getTopLeft(newestRegistration).dy,
        lessThan(tester.getTopLeft(newestMedicationDate).dy),
      );

      await tester.tap(find.text('복용날짜순'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(newestMedicationDate).dy,
        lessThan(tester.getTopLeft(newestRegistration).dy),
      );

      await tester.tap(
        find.byKey(const ValueKey('savedMedicationSortDirectionButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(
        tester.getTopLeft(newestRegistration).dy,
        lessThan(tester.getTopLeft(newestMedicationDate).dy),
      );
    },
  );
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

Future<http.Response> _mixedDeleteResponse(http.Request request) async {
  if (request.method == 'GET' && request.url.path == '/list') {
    return http.Response(
      jsonEncode({
        'success': true,
        'data': [
          _savedMedicationJson(request, 1, 'tablet-one'),
          _savedMedicationJson(request, 2, 'tablet-two'),
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  if (request.method == 'DELETE') {
    final id = int.parse(request.url.pathSegments.last);
    return http.Response(
      jsonEncode({'success': id == 1}),
      id == 1 ? 200 : 500,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  if (request.method == 'GET' && request.url.path == '/schedule/today') {
    return http.Response(
      jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('Not found', 404);
}

Future<http.Response> _sortableMedicationResponse(http.Request request) async {
  if (request.method != 'GET' || request.url.path != '/list') {
    return http.Response('Not found', 404);
  }
  return http.Response(
    jsonEncode({
      'success': true,
      'data': [
        {
          ..._savedMedicationJson(request, 1, '등록최신약'),
          'created_date': '2026-07-22',
          'prescription_date': '2026-07-01',
        },
        {
          ..._savedMedicationJson(request, 2, '복용최신약'),
          'created_date': '2026-07-20',
          'prescription_date': '2026-07-21',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _savedMedicationJson(
  http.Request request,
  int id,
  String name,
) {
  return {
    'id': id,
    'patient_hash':
        request.url.queryParameters['patient_hash'] ?? 'local_patient',
    'created_date': '2026-07-15',
    'prescription_date': '2026-07-15',
    'item_seq': '20000000$id',
    'item_name': name,
    'efficacy': 'effect',
    'use_method': 'usage',
    'warning_message': 'warning',
    'image_url': 'https://example.com/tablet.jpg',
  };
}
