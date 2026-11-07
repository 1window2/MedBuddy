// File Name: chat_push_navigation_test.dart
// Role: Verifies chat and caregiver-monitoring push routes, including malformed and cross-account payloads, without Firebase.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';

// 함수이름: main
// 함수역할:
// - 푸시 탭의 채팅·보호자 일정 이동과 계정·연동·시간대 보호 조건을 실제 Firebase나 서버 요청 없이 검사하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final selections = <MedicationNotificationSelection>[];
  late http.Client client;
  late PushNotificationService service;
  // Function Name: setUp
  // Description:
  // - Clear stored preferences and selections, install the selection recorder, and create a patient-scoped push service whose client rejects every network request.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    selections.clear();
    NotificationService.setNotificationSelectionHandler(selections.add);
    client = MockClient(
      (_) async => throw StateError('Navigation must not send API requests'),
    );
    service = PushNotificationService(userHash: 'patient', client: client);
  });
  // Function Name: tearDown
  // Description:
  // - Remove the global notification-selection callback and close the mock HTTP client after each case.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
    client.close();
  });
  for (final kind in ['slot_check_request', 'text', 'hospital_share', 'pharmacy_share', 'medication_discomfort', 'medication_shortage']) {
    for (final slot in ['morning', 'lunch', 'evening', 'bedtime', 'invalid']) {
      // Function Name: $kind / $slot opens the originating chat
      // Description:
      // - Every supported chat kind opens its originating link without a dose action or slot, even when the incoming slot is invalid.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completes after the asynchronous assertions.
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
    // Function Name: invalid link $id cannot navigate
    // Description:
    // - Empty, zero, negative, and nonnumeric link IDs produce no navigation selection.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
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
  // Function Name: another account cannot open a conversation
  // Description:
  // - A push addressed to another account cannot open the current account's conversation.
  // Parameters:
  // - None.
  // Returns:
  // - void; assertion failures fail the case.
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
  // 함수이름: unknown push type does not fall through to caregiver schedule
  // 함수역할:
  // - 알 수 없는 푸시 종류는 환자 해시가 들어 있어도 보호자 일정으로 잘못 이동하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 기대 결과와 다르면 테스트가 실패한다.
  test('unknown push type does not fall through to caregiver schedule', () {
    service.handleOpenedMessageForTesting(const RemoteMessage(data: {
      'type': 'unknown', 'recipient_hash': 'patient', 'patient_hash': 'another',
    }));
    expect(selections, isEmpty);
  });
  for (final type in ['caregiver_slot_completed', 'caregiver_dose_completed', 'caregiver_slot_missed']) {
    // 함수이름: $type opens the matching patient schedule
    // 함수역할:
    // - 보호자 시간대 완료·개별 복용 완료·미복용 알림은 payload의 환자 해시에 해당하는 보호자 일정으로 이동하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test('$type opens the matching patient schedule', () async {
      service.handleOpenedMessageForTesting(RemoteMessage(data: {
        'type': type, 'recipient_hash': 'patient', 'patient_hash': 'patient:two',
      }));
      await Future<void>.delayed(Duration.zero);
      expect(selections.single.destination, MedicationNotificationDestination.caregiverSchedule);
      expect(selections.single.patientHash, 'patient:two');
    });
  }
  // 함수이름: invalid schedule slots cannot navigate or perform an action
  // 함수역할:
  // - 빈 값·알 수 없는 값·복합 시간대 payload는 거절하되 공백과 대문자가 있는 Evening은 evening으로 정규화하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 기대 결과와 다르면 테스트가 실패한다.
  test('invalid schedule slots cannot navigate or perform an action', () {
    for (final slot in ['', 'unknown', 'morning/bedtime']) {
      expect(NotificationService.selectionFromPayload('schedule:$slot:1:2026-09-28'), isNull);
    }
    expect(NotificationService.selectionFromPayload('schedule: Evening :1')?.slotKey, 'evening');
  });
}
