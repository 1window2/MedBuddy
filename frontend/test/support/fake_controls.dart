// File Name: fake_controls.dart
// Role: Shared minimal substitutes for the schedule control, the reminder control and the device
//   location boundary, replacing the identical private copies kept in several test files.
//
// Records: FakeDeviceLocation counts coordinate and settings requests. The two empty controls
//   record nothing.
// Does not simulate: the empty controls override only the one read that screens issue on entry;
//   every other operation is the production implementation and would use the HTTP client given
//   to the constructor. FakeDeviceLocation does not model permission prompts, the recent-fix
//   cache or location-service state; a failure is whatever `error` the test sets.

import 'dart:async';

import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

// Class Name: EmptyCheckSchedule
// Role: Schedule control whose today-schedule read returns no medication without a request.
// Responsibilities:
// - Let a screen or view model load an empty schedule in tests that are about something else.
// Note: Subclass it to add medication rows or to record status updates.
class EmptyCheckSchedule extends CheckSchedule {
  // Function Name: EmptyCheckSchedule
  // Description: Creates the control with the production defaults or the given scope and client.
  // Parameters: patientHash, client - forwarded to CheckSchedule.
  // Returns: The empty schedule control.
  EmptyCheckSchedule({super.patientHash, super.client});

  // Function Name: requestTodayMedicationSchedule
  // Description: Answers the today-schedule read with an empty list.
  // Parameters: None. Returns: An empty schedule list, without an HTTP request.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

// Class Name: EmptySetNotification
// Role: Reminder control whose alarm read returns no saved alarm without a request.
// Responsibilities:
// - Let a screen or view model load reminder settings in tests that are about something else.
class EmptySetNotification extends SetNotification {
  // Function Name: EmptySetNotification
  // Description: Creates the control with the production defaults or the given collaborators.
  // Parameters: patientHash, client, notificationRegistrar - forwarded to SetNotification.
  // Returns: The empty reminder control.
  EmptySetNotification({
    super.patientHash,
    super.client,
    super.notificationRegistrar,
  });

  // Function Name: requestMedicationAlarm
  // Description: Answers the alarm read with an empty list.
  // Parameters: None. Returns: An empty alarm list, without an HTTP request.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// Class Name: FakeDeviceLocation
// Role: Device-location substitute that returns a fixed coordinate, throws, or stays pending.
// Responsibilities:
// - Answer coordinate requests from test-controlled state and count them.
// - Report both settings screens as opened without leaving the test.
// Attributes:
// - coordinate (DeviceCoordinate): Position returned while error is null and pending is false.
// - error (Object?): Thrown by every coordinate request while it is not null.
// - pending (bool): When true, coordinate requests wait for `result` instead of answering.
// - result (Completer<DeviceCoordinate>): Completed by the test to release pending requests.
// - requests (int): Number of coordinate requests received.
// - applicationSettingsRequests, deviceSettingsRequests (int): Number of settings requests.
class FakeDeviceLocation implements DeviceLocationBoundary {
  // Function Name: FakeDeviceLocation
  // Description: Creates a location fake; by default it answers at once with Seoul City Hall.
  // Parameters: coordinate, error, pending - see the class attributes.
  // Returns: The location fake.
  FakeDeviceLocation({
    this.coordinate = seoulCityHall,
    this.error,
    this.pending = false,
  });

  static const DeviceCoordinate seoulCityHall = DeviceCoordinate(
    latitude: 37.5665,
    longitude: 126.9780,
  );

  DeviceCoordinate coordinate;
  Object? error;
  final bool pending;
  final Completer<DeviceCoordinate> result = Completer<DeviceCoordinate>();
  int requests = 0;
  int applicationSettingsRequests = 0;
  int deviceSettingsRequests = 0;

  // Function Name: requestCurrentCoordinate
  // Description: Counts the request, then throws error, waits for result, or returns coordinate.
  // Parameters: None.
  // Returns: The configured coordinate; a pending fake returns the future of `result`.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    requests++;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    if (pending) {
      return result.future;
    }
    return coordinate;
  }

  // Function Name: openApplicationSettings
  // Description: Counts the request and reports the application settings as opened.
  // Parameters: None. Returns: True.
  @override
  Future<bool> openApplicationSettings() async {
    applicationSettingsRequests++;
    return true;
  }

  // Function Name: openDeviceLocationSettings
  // Description: Counts the request and reports the device location settings as opened.
  // Parameters: None. Returns: True.
  @override
  Future<bool> openDeviceLocationSettings() async {
    deviceSettingsRequests++;
    return true;
  }
}
