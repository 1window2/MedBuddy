import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/medication_notification_service.dart';

void main() {
  tearDown(() {
    MedicationNotificationService.setNotificationSelectionHandler(null);
  });

  test('schedule payload resolves to the dose screen destination', () {
    expect(
      MedicationNotificationService.destinationFromPayload(
        'schedule:morning:17',
      ),
      MedicationNotificationDestination.schedule,
    );
  });

  test('malformed notification payloads cannot trigger navigation', () {
    expect(
      MedicationNotificationService.destinationFromPayload(null),
      isNull,
    );
    expect(
      MedicationNotificationService.destinationFromPayload('schedule::17'),
      isNull,
    );
    expect(
      MedicationNotificationService.destinationFromPayload(
        'schedule:morning:not-an-id',
      ),
      isNull,
    );
    expect(
      MedicationNotificationService.destinationFromPayload('settings:17'),
      isNull,
    );
  });

  test('a selected schedule notification reaches the registered handler', () {
    final destinations = <MedicationNotificationDestination>[];
    MedicationNotificationService.setNotificationSelectionHandler(
      destinations.add,
    );

    MedicationNotificationService.handleNotificationPayload(
      'schedule:evening:29',
    );

    expect(destinations, [MedicationNotificationDestination.schedule]);
  });

  test('a cold-start notification is delivered after handler registration', () {
    MedicationNotificationService.handleNotificationPayload(
      'schedule:morning:31',
    );

    final destinations = <MedicationNotificationDestination>[];
    MedicationNotificationService.setNotificationSelectionHandler(
      destinations.add,
    );

    expect(destinations, [MedicationNotificationDestination.schedule]);
  });
}
