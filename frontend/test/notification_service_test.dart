import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

void main() {
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
  });

  test('schedule payload resolves to the dose screen destination', () {
    expect(
      NotificationService.destinationFromPayload(
        'schedule:morning:17',
      ),
      MedicationNotificationDestination.schedule,
    );
  });

  test('malformed notification payloads cannot trigger navigation', () {
    expect(
      NotificationService.destinationFromPayload(null),
      isNull,
    );
    expect(
      NotificationService.destinationFromPayload('schedule::17'),
      isNull,
    );
    expect(
      NotificationService.destinationFromPayload(
        'schedule:morning:not-an-id',
      ),
      isNull,
    );
    expect(
      NotificationService.destinationFromPayload('settings:17'),
      isNull,
    );
  });

  test('a selected schedule notification reaches the registered handler', () {
    final destinations = <MedicationNotificationDestination>[];
    NotificationService.setNotificationSelectionHandler(
      destinations.add,
    );

    NotificationService.handleNotificationPayload(
      'schedule:evening:29',
    );

    expect(destinations, [MedicationNotificationDestination.schedule]);
  });

  test('a cold-start notification is delivered after handler registration', () {
    NotificationService.handleNotificationPayload(
      'schedule:morning:31',
    );

    final destinations = <MedicationNotificationDestination>[];
    NotificationService.setNotificationSelectionHandler(
      destinations.add,
    );

    expect(destinations, [MedicationNotificationDestination.schedule]);
  });
}
