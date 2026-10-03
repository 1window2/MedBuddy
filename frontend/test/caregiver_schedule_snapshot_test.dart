// File Name: caregiver_schedule_snapshot_test.dart
// Role: Validate the shared Home/widget read path without native widget APIs.
import 'dart:convert';
import 'dart:async';
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
  // 홈과 알림 감시가 겹쳐도 한 번만 읽고 다른 세션 객체는 재사용하지 않는다.
  test('home and monitoring share only the current session snapshot', () async {
    var reads = 0;
    final gate = Completer<http.Response>();
    final client = MockClient((_) async { reads++; return gate.future; });
    addTearDown(client.close);
    final control = CheckCaregiverMedication(caregiverHash: 'owner', client: client);
    final first = control.requestScheduleSnapshot();
    final second = control.requestScheduleSnapshot();
    final monitoring = control.requestMonitoringSnapshot();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    gate.complete(http.Response(jsonEncode({'data': {
      'caregiver_hash': 'owner', 'patients': [{
        'link': link, 'notification_settings': [],
        'today_medication_info': {'schedules': []},
      }],
    }}), 200));
    await Future.wait([first, second, monitoring]);
    await control.requestMonitoringSnapshot();
    expect(reads, 1);
    control.dispose();
    final newSession = CheckCaregiverMedication(caregiverHash: 'owner', client: client);
    await newSession.requestMonitoringSnapshot();
    expect(reads, 2);
    newSession.dispose();
  });
  test(
    'widget refresh retains schedules with alerts off and rereads links',
    () async {
      var linked = true;
      final paths = <String>[];
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        paths.add(request.url.path);
        expect(request.url.path, '/caregiver/schedules');
        expect(request.url.queryParameters['caregiver_hash'], 'owner');
        return http.Response(
          jsonEncode({
            'data': {
              'caregiver_hash': 'owner',
              'patients': linked ? [{
              'link': link,
              'notification_settings': [],
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
              }] : [],
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
        '/caregiver/schedules',
        '/caregiver/schedules',
        '/caregiver/schedules',
      ]);
    },
  );

  for (final failure in ['links', 'detail', 'caregiver', 'patient']) {
    // Failed reads must reach the widget's existing failed-cache path, not
    // replace previously known schedules with a successful empty result.
    test('$failure failure is not an empty successful schedule', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'caregiver_hash': failure == 'caregiver' ? 'someone' : 'owner',
              'patients': [{
              'link': {...link, if (failure == 'patient') 'caregiver_hash': 'someone'},
              'today_medication_info': {'schedules': []},
              }],
            },
          }),
          failure == 'detail' ? 403 : failure == 'links' ? 503 : 200,
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
