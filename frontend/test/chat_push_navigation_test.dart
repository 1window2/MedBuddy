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
  for (final kind in ['slot_check_request', 'text']) {
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
}
