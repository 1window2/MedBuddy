import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/controls/caregiver_alert_action_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
import 'package:medbuddy_frontend/services/caregiver_alert_delivery_service.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

CaregiverAlertContext context({int delivery = 1, String recipient = 'caregiver-a'}) => CaregiverAlertContext(
  alertId: delivery, sourceAlertId: 1, linkId: 7,
  eventId: delivery.toString().padLeft(64, '0'), sourceEventId: '1'.padLeft(64, '0'),
  patientHash: 'patient-a', recipientHash: recipient, slotKey: 'lunch', scheduleDate: '2026-09-21',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({NotificationInboxStore.activeUserKey: 'caregiver-a'}));

  test('versioned payload preserves original/delivery context and dedicated actions', () {
    final alert = context(delivery: 2);
    final selected = NotificationService.selectionFromPayload(alert.payload,
      actionId: NotificationService.caregiverSnoozeActionId)!;
    expect(selected.action, MedicationNotificationAction.caregiverSnooze);
    expect(selected.caregiverAlert!.toData(), alert.toData());
    expect(selected.destination, MedicationNotificationDestination.caregiverSchedule);
    expect(NotificationService.selectionFromPayload(alert.payload,
      actionId: NotificationService.caregiverChatActionId)!.action, MedicationNotificationAction.caregiverRequestCheck);
    expect(NotificationService.selectionFromPayload(alert.payload,
      actionId: NotificationService.markSlotTakenActionId)!.action, MedicationNotificationAction.open);
    expect(NotificationService.selectionFromPayload('caregiver:patient-a',
      actionId: NotificationService.caregiverSnoozeActionId)!.action, MedicationNotificationAction.open);
    expect(NotificationService.selectionFromPayload('caregiver-v1:%invalid'), isNull);
    expect(CaregiverAlertContext.fromData({...alert.toData(), 'schedule_date': '2026-02-31'}), isNull);
    expect(CaregiverAlertContext.fromData({...alert.toData(), 'slot_key': 'unknown'}), isNull);
    expect(context().notificationId, isNot(alert.notificationId));
  });

  test('snooze uses only the server delivery endpoint and surfaces failed or unknown receipt', () async {
    var status = 200;
    var valid = true;
    final requests = <http.Request>[];
    final actions = CaregiverAlertActionControl(userHash: 'caregiver-a', client: MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(valid ? {'success': true, 'data': {'alert_id': 2}} : {}), status);
    }));
    await actions.execute(context(), CaregiverAlertAction.snooze);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/medication/caregiver-alerts/1/snooze');
    expect(requests.single.body, isEmpty);
    for (final code in [401, 403, 409, 500]) {
      status = code;
      await expectLater(actions.execute(context(), CaregiverAlertAction.snooze), throwsStateError);
    }
    status = 200;
    valid = false;
    await expectLater(actions.execute(context(), CaregiverAlertAction.snooze), throwsStateError);
  });

  test('wrong account is rejected before any HTTP request', () async {
    final actions = CaregiverAlertActionControl(userHash: 'other', client: MockClient((_) async {
      fail('Must not send a request');
    }));
    await expectLater(actions.execute(context(), CaregiverAlertAction.requestCheck), throwsStateError);
  });

  test('lost response can retry the same chat key across snooze cycles without navigation', () async {
    final bodies = <Map<String, dynamic>>[];
    var failNetwork = true;
    final actions = CaregiverAlertActionControl(userHash: 'caregiver-a', client: MockClient((request) async {
      expect(request.url.path, '/api/v1/chat/links/7/messages');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      if (failNetwork) throw http.ClientException('lost response');
      return http.Response(jsonEncode({'success': true, 'created': false, 'data': {
        'message_id': 5, 'link_id': 7, 'sender_hash': 'caregiver-a',
        'client_message_id': body['client_message_id'], 'body': body['body'],
        'message_kind': 'slot_check_request', 'created_at': '2026-09-21T00:00:00Z',
      }}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await expectLater(actions.execute(context(), CaregiverAlertAction.requestCheck), throwsA(isA<http.ClientException>()));
    failNetwork = false;
    await actions.execute(context(delivery: 2), CaregiverAlertAction.requestCheck);
    expect(bodies.map((b) => b['client_message_id']).toSet(), {'missed_chat_1'});
    expect(bodies.last['source_alert_id'], 1);
    expect(bodies.last['slot_key'], 'lunch');
    expect(bodies.last['message_kind'], 'slot_check_request');
  });

  test('foreground/background duplicates display once, new cycles display again', () async {
    var calls = 0;
    Future<void> show(CaregiverAlertContext alert, String title, String body, String language) async { calls++; }
    expect(await CaregiverAlertDeliveryService.display(context().toData(), presenter: show), isTrue);
    expect(await CaregiverAlertDeliveryService.display(context().toData(), presenter: show), isFalse);
    expect(await CaregiverAlertDeliveryService.display(context(delivery: 2).toData(), presenter: show), isTrue);
    expect(await CaregiverAlertDeliveryService.display(context(recipient: 'other').toData(), presenter: show), isFalse);
    expect(calls, 2);
  });

  test('failed display remains retryable and local privacy is respected', () async {
    SharedPreferences.setMockInitialValues({NotificationInboxStore.activeUserKey: 'caregiver-a',
      'user_setting_caregiver-a_notification_detail_mode': 'type_only'});
    final data = {...context().toData(), 'title': 'private', 'body': 'private'};
    await expectLater(CaregiverAlertDeliveryService.display(data, presenter: (_, title, body, _) async {
      expect(title, isNot('private'));
      expect(body, isNot('private'));
      throw StateError('platform unavailable');
    }), throwsStateError);
    expect(await CaregiverAlertDeliveryService.display(data, presenter: (_, _, _, _) async {}), isTrue);
  });

  test('Android actions show UI and cold-launch payload dispatches caregiver action only', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    MedicationNotificationSelection? selected;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {
        'notificationLaunchedApp': true,
        'notificationResponse': {'notificationResponseType': 1, 'id': 1,
          'actionId': NotificationService.caregiverChatActionId, 'payload': context().payload},
        };
      }
      return true;
    });
    NotificationService.setNotificationSelectionHandler((value) => selected = value);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      NotificationService.setNotificationSelectionHandler(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });
    await NotificationService.instance.showCaregiverAlert(
      id: 1, title: 'test', body: 'test', patientHash: 'patient-a',
      historyUserHash: 'caregiver-a', alertContext: context(),
    );
    final args = calls.lastWhere((c) => c.method == 'show').arguments as Map;
    final actions = ((args['platformSpecifics'] as Map)['actions'] as List).cast<Map>();
    expect(actions.map((a) => a['id']).toSet(), {NotificationService.caregiverChatActionId, NotificationService.caregiverSnoozeActionId});
    expect(actions.every((a) => a['showsUserInterface'] == true), isTrue);
    expect(selected?.action, MedicationNotificationAction.caregiverRequestCheck);
    expect(selected?.caregiverAlert?.sourceAlertId, 1);
  });
}
