// File Name: medication_notification_payload_codec_test.dart
// Role: Verifies notification protocol parsing independently from platform scheduling.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
import 'package:medbuddy_frontend/entities/medication_notification_selection_entity.dart';
import 'package:medbuddy_frontend/services/medication_notification_payload_codec.dart';

// Function Name: _caregiverAlert
// Description: Creates a valid missed-dose delivery for versioned payload tests.
// Parameters: None.
// Returns: A caregiver-scoped delivery whose original and current event IDs differ.
CaregiverAlertContext _caregiverAlert() => CaregiverAlertContext(
  alertId: 2,
  sourceAlertId: 1,
  linkId: 7,
  eventId: '2'.padLeft(64, '0'),
  sourceEventId: '1'.padLeft(64, '0'),
  patientHash: 'patient-a',
  recipientHash: 'caregiver-a',
  slotKey: 'lunch',
  scheduleDate: '2026-10-02',
);

// Function Name: main
// Description: Registers payload contracts, compatibility semantics, and library-boundary checks.
// Parameters: None.
// Returns: None; registered tests report protocol regressions.
void main() {
  // Function Name: schedule actions test
  // Description: Preserves normalized slots, action IDs, platform ID overrides, and original dates.
  // Parameters: None.
  // Returns: None; unexpected arguments fail the test.
  test('schedule payload preserves slot, date, id, and matching action', () {
    final selection = MedicationNotificationPayloadCodec.decode(
      'schedule: LUNCH :17:2026-10-02',
      actionId: MedicationNotificationPayloadCodec.markSlotTakenActionId,
      notificationId: 900,
    )!;
    expect(selection.destination, MedicationNotificationDestination.schedule);
    expect(selection.slotKey, 'lunch');
    expect(selection.notificationId, 900);
    expect(selection.action, MedicationNotificationAction.markSlotTaken);
    expect(selection.isForDate(DateTime(2026, 10, 2, 23)), isTrue);
    expect(selection.isForDate(DateTime(2026, 10, 3)), isFalse);
    expect(selection.caregiverAlert, isNull);
    expect(
      MedicationNotificationPayloadCodec.decode(
        'schedule:bedtime:0',
        actionId: MedicationNotificationPayloadCodec.snoozeTenMinutesActionId,
      )!.action,
      MedicationNotificationAction.snoozeTenMinutes,
    );
  });

  // Function Name: legacy schedule test
  // Description: Keeps old schedules navigable but prevents undated actions from matching a dose day.
  // Parameters: None.
  // Returns: None; changed legacy compatibility fails the test.
  test('legacy schedule remains undated and mismatched actions only open', () {
    final selection = MedicationNotificationPayloadCodec.decode(
      'schedule:morning:17',
      actionId: MedicationNotificationPayloadCodec.caregiverSnoozeActionId,
    )!;
    expect(selection.action, MedicationNotificationAction.open);
    expect(selection.scheduleDate, isNull);
    expect(selection.isForDate(DateTime(2026, 10, 2)), isFalse);
    expect(
      MedicationNotificationPayloadCodec.decode(
        'schedule:morning:17',
        actionId: 'unknown-action',
      )!.action,
      MedicationNotificationAction.open,
    );
  });

  // Function Name: invalid payload test
  // Description: Rejects unknown destinations, malformed identifiers, invalid dates, and extra segments.
  // Parameters: None.
  // Returns: None; accepting an invalid route fails the test.
  test('malformed payloads cannot produce a navigation or action', () {
    for (final payload in <String?>[
      null,
      '',
      'settings:1',
      'schedule::17',
      'schedule:unknown:17',
      'schedule:lunch:-1',
      'schedule:lunch:not-a-number',
      'schedule:lunch:17:2026-02-31',
      'schedule:lunch:17:2026-10-2',
      'schedule:lunch:17:2026-10-02T12:00:00',
      'schedule:lunch:17:2026-10-02:extra',
      'caregiver:',
      'caregiver:%20',
      'caregiver:%invalid',
      'caregiver:%FF',
      'caregiver-v1:%invalid',
      'caregiver-v1:%FF',
      'chat:0',
      'chat:-1',
      'chat:not-a-number',
      'chat:7:extra',
    ]) {
      expect(
        MedicationNotificationPayloadCodec.decode(payload),
        isNull,
        reason: 'Unexpected route for $payload',
      );
    }
  });

  // Function Name: malformed caregiver context test
  // Description: Rejects malformed percent escapes and invalid UTF-8 at the entity boundary too.
  // Parameters: None.
  // Returns: None; malformed system payloads must not throw while decoding their context.
  test('caregiver context rejects malformed encoding without throwing', () {
    for (final payload in [
      'caregiver-v1:%invalid',
      'caregiver-v1:%FF',
      'caregiver-v1:%7Bnot-json%7D',
    ]) {
      expect(CaregiverAlertContext.fromPayload(payload), isNull);
    }
  });

  // Function Name: legacy destinations test
  // Description: Decodes escaped patient names and linked chat IDs without enabling caregiver actions.
  // Parameters: None.
  // Returns: None; incorrect scope or action fails the test.
  test(
    'legacy caregiver and chat routes retain only their navigation scope',
    () {
      final caregiver = MedicationNotificationPayloadCodec.decode(
        'caregiver:${Uri.encodeComponent(' patient:alpha ')}',
        actionId: MedicationNotificationPayloadCodec.caregiverChatActionId,
      )!;
      expect(
        caregiver.destination,
        MedicationNotificationDestination.caregiverSchedule,
      );
      expect(caregiver.patientHash, 'patient:alpha');
      expect(caregiver.action, MedicationNotificationAction.open);
      expect(caregiver.caregiverAlert, isNull);
      final chat = MedicationNotificationPayloadCodec.decode(
        'chat:7',
        actionId: MedicationNotificationPayloadCodec.markSlotTakenActionId,
      )!;
      expect(chat.destination, MedicationNotificationDestination.linkedChat);
      expect(chat.linkId, 7);
      expect(chat.patientHash, isNull);
      expect(chat.action, MedicationNotificationAction.open);
    },
  );

  // Function Name: versioned caregiver test
  // Description: Preserves the complete server delivery context and only allows caregiver-specific actions.
  // Parameters: None.
  // Returns: None; dropped identifiers or cross-type actions fail the test.
  test(
    'versioned caregiver payload preserves context and dedicated actions',
    () {
      final alert = _caregiverAlert();
      for (final entry in {
        MedicationNotificationPayloadCodec.caregiverSnoozeActionId:
            MedicationNotificationAction.caregiverSnooze,
        MedicationNotificationPayloadCodec.caregiverChatActionId:
            MedicationNotificationAction.caregiverRequestCheck,
        MedicationNotificationPayloadCodec.markSlotTakenActionId:
            MedicationNotificationAction.open,
        'unknown-action': MedicationNotificationAction.open,
      }.entries) {
        final selection = MedicationNotificationPayloadCodec.decode(
          alert.payload,
          actionId: entry.key,
        )!;
        expect(
          selection.destination,
          MedicationNotificationDestination.caregiverSchedule,
        );
        expect(selection.caregiverAlert!.toData(), alert.toData());
        expect(selection.patientHash, alert.patientHash);
        expect(selection.linkId, alert.linkId);
        expect(selection.slotKey, alert.slotKey);
        expect(selection.action, entry.value);
        expect(selection.isForDate(DateTime(2026, 10, 2)), isTrue);
      }
    },
  );

  // Function Name: cleanup classification test
  // Description: Keeps malformed but session-owned alerts eligible for cleanup without allowing navigation.
  // Parameters: None.
  // Returns: None; changed cleanup ownership fails the test.
  test('cleanup ownership is deliberately broader than valid routing', () {
    for (final payload in [
      'schedule:',
      'caregiver:',
      'caregiver-v1:',
      'chat:',
    ]) {
      expect(
        MedicationNotificationPayloadCodec.isSessionPayload(payload),
        isTrue,
      );
      expect(MedicationNotificationPayloadCodec.decode(payload), isNull);
    }
    for (final payload in <String?>[null, '', 'settings:17', 'chatty:7']) {
      expect(
        MedicationNotificationPayloadCodec.isSessionPayload(payload),
        isFalse,
      );
    }
  });

  // Function Name: neutral library test
  // Description: Prevents selection entities and payload validation from importing runtime or plugin services.
  // Parameters: None.
  // Returns: None; a forbidden dependency fails the test.
  test(
    'notification action contract and codec remain platform-independent',
    () {
      for (final path in [
        'lib/entities/medication_notification_selection_entity.dart',
        'lib/services/medication_notification_payload_codec.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('package:')));
        expect(source, isNot(contains("'notification_service.dart'")));
        expect(source, isNot(contains("'notification_inbox_store.dart'")));
      }
    },
  );
}
