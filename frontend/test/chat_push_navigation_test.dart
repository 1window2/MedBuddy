// File Name: chat_push_navigation_test.dart
// Role: Guard chat push routing without Firebase or real patient records.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';

// Function Name: main
// Description: Test the shared launch/background tap handler and scope guards.
// Parameters: None. Returns: Test registration; all network writes are rejected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final selections = <MedicationNotificationSelection>[];
  late http.Client client;
  late PushNotificationService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    selections.clear();
    NotificationService.setNotificationSelectionHandler(selections.add);
    client = MockClient(
      (_) async => throw StateError('Navigation must not send API requests'),
    );
    service = PushNotificationService(userHash: 'patient', client: client);
  });
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
    client.close();
  });
  for (final kind in ['slot_check_request', 'text', 'hospital_share', 'pharmacy_share', 'medication_discomfort', 'medication_shortage']) {
    for (final slot in ['morning', 'lunch', 'evening', 'bedtime', 'invalid']) {
      test('$kind / $slot opens the originating chat', () async {
        service.handleOpenedMessageForTesting(
          RemoteMessage(
            data: {
              'type': 'linked_chat_message',
              'recipient_hash': 'patient',
              'link_id': '37',
              'message_kind': kind,
              'slot_key': slot,
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          selections.single.destination,
          MedicationNotificationDestination.linkedChat,
        );
        expect(selections.single.linkId, 37);
        expect(selections.single.action, MedicationNotificationAction.open);
        expect(selections.single.slotKey, isNull);
      });
    }
  }
  for (final id in ['', '0', '-1', 'not-a-link']) {
    test('invalid link $id cannot navigate', () async {
      service.handleOpenedMessageForTesting(
        RemoteMessage(
          data: {
            'type': 'linked_chat_message',
            'recipient_hash': 'patient',
            'link_id': id,
            'message_kind': 'slot_check_request',
            'slot_key': 'morning',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(selections, isEmpty);
    });
  }
  test('another account cannot open a conversation', () {
    service.handleOpenedMessageForTesting(
      const RemoteMessage(
        data: {
          'type': 'linked_chat_message',
          'recipient_hash': 'someone',
          'link_id': '37',
          'message_kind': 'slot_check_request',
          'slot_key': 'morning',
        },
      ),
    );
    expect(selections, isEmpty);
  });
  // 알 수 없는 푸시가 환자 해시를 포함해도 복약 화면으로 잘못 보내지 않는다.
  test('unknown push type does not fall through to caregiver schedule', () {
    service.handleOpenedMessageForTesting(const RemoteMessage(data: {
      'type': 'unknown', 'recipient_hash': 'patient', 'patient_hash': 'another',
    }));
    expect(selections, isEmpty);
  });
  for (final type in ['caregiver_slot_completed', 'caregiver_dose_completed', 'caregiver_slot_missed']) {
    test('$type opens the matching patient schedule', () async {
      service.handleOpenedMessageForTesting(RemoteMessage(data: {
        'type': type, 'recipient_hash': 'patient', 'patient_hash': 'patient:two',
      }));
      await Future<void>.delayed(Duration.zero);
      expect(selections.single.destination, MedicationNotificationDestination.caregiverSchedule);
      expect(selections.single.patientHash, 'patient:two');
    });
  }
  // 잘못된 시간대는 복약 처리·재알림 동작으로 전달하지 않는다.
  test('invalid schedule slots cannot navigate or perform an action', () {
    for (final slot in ['', 'unknown', 'morning/bedtime']) {
      expect(NotificationService.selectionFromPayload('schedule:$slot:1:2026-09-28'), isNull);
    }
    expect(NotificationService.selectionFromPayload('schedule: Evening :1')?.slotKey, 'evening');
  });
}
