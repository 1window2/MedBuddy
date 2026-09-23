// File Name: caregiver_schedule_snapshot_test.dart
// Role: Validate the shared Home/widget read path without native widget APIs.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';

// Function Name: main
// Description: Exercise alert-independent reads, link changes, and rejected responses.
// Parameters: None. Returns: Test registration only; no real accounts are used.
void main() {
  final link = <String, dynamic>{
    'link_id': 1,
    'patient_id': 'patient',
    'caregiver_id': 'owner',
    'patient_hash': 'patient',
    'caregiver_hash': 'owner',
    'link_status': true,
  };
  test(
    'widget refresh retains schedules with alerts off and rereads links',
    () async {
      var linked = true;
      final paths = <String>[];
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        paths.add(request.url.path);
        if (request.url.path.endsWith('/link/list')) {
          return http.Response(
            jsonEncode({
              'data': linked
                  ? [
                      link,
                      {...link, 'link_id': 2, 'link_status': false},
                      {...link, 'link_id': 3, 'caregiver_hash': 'someone'},
                      {...link, 'link_id': 4, 'patient_hash': 'owner'},
                    ]
                  : [],
            }),
            200,
          );
        }
        expect(request.url.path, '/caregiver/medications/patient');
        expect(request.url.queryParameters['caregiver_hash'], 'owner');
        return http.Response(
          jsonEncode({
            'data': {
              'caregiver_hash': 'owner',
              'patient_hash': 'patient',
              'saved_medications': [],
              'today_medication_info': {
                'schedules': [
                  {
                    'medication_id': '91',
                    'medication_name': 'Test medicine',
                    'schedule_slot_keys': ['morning'],
                    'slot_statuses': {'morning': false},
                  },
                ],
              },
            },
          }),
          200,
        );
      });
      final control = CheckCaregiverMedication(
        caregiverHash: 'owner',
        baseUrl: 'https://medbuddy.test',
        client: client,
      );
      addTearDown(client.close);
      final first = await control.requestScheduleSnapshot();
      final refreshed = await control.requestScheduleSnapshot();
      expect(first.single.schedules, hasLength(1));
      expect(refreshed.single.schedules.single.medicationID, '91');
      expect(refreshed.single.notificationSettings, isEmpty);
      linked = false;
      expect(await control.requestScheduleSnapshot(), isEmpty);
      expect(paths, [
        '/link/list',
        '/caregiver/medications/patient',
        '/link/list',
        '/caregiver/medications/patient',
        '/link/list',
      ]);
    },
  );

  for (final failure in ['links', 'detail', 'caregiver', 'patient']) {
    // Failed reads must reach the widget's existing failed-cache path, not
    // replace previously known schedules with a successful empty result.
    test('$failure failure is not an empty successful schedule', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/link/list')) {
          return http.Response(
            jsonEncode({
              'data': [link],
            }),
            failure == 'links' ? 503 : 200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'caregiver_hash': failure == 'caregiver' ? 'someone' : 'owner',
              'patient_hash': failure == 'patient' ? 'someone' : 'patient',
              'saved_medications': [],
              'today_medication_info': {'schedules': []},
            },
          }),
          failure == 'detail' ? 403 : 200,
        );
      });
      addTearDown(client.close);
      final control = CheckCaregiverMedication(
        caregiverHash: 'owner',
        client: client,
      );
      await expectLater(control.requestScheduleSnapshot(), throwsStateError);
    });
  }
}
