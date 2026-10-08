// File Name: nearby_care_control_lifecycle_test.dart
// Role: Guards sibling provider policies and HTTP/GPS ownership after screen disposal.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_care_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

// Class Name: _PendingLocation
// Role: Holds GPS completion until a deterministic lifecycle transition.
// Responsibilities: Count starts and complete with success or failure without a real plugin.
// Attributes: result: pending coordinate; requests: GPS start count.
class _PendingLocation implements DeviceLocationBoundary {
  final result = Completer<DeviceCoordinate>();
  int requests = 0;

  // Function Name: requestCurrentCoordinate
  // Description: Counts each GPS request and returns the controlled result.
  // Parameters: None. Returns: Pending WGS84 coordinates.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() {
    requests++;
    return result.future;
  }

  // Function Name: openApplicationSettings
  // Description: Avoids changing OS permissions in tests.
  // Parameters: None. Returns: A successful simulated settings action.
  @override
  Future<bool> openApplicationSettings() async => true;

  // Function Name: openDeviceLocationSettings
  // Description: Avoids changing OS location settings in tests.
  // Parameters: None. Returns: A successful simulated settings action.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

const _coordinate = DeviceCoordinate(latitude: 37.5, longitude: 127);

// Function Name: _create
// Description: Creates either sibling through the shared nearby-care contract.
// Parameters: hospital: provider choice; location, client: borrowed test adapters.
// Returns: A provider-specific control, not a hospital-as-pharmacy subtype.
CheckNearbyCare _create(
  bool hospital,
  DeviceLocationBoundary location,
  http.Client client,
) => hospital
    ? CheckNearbyHospital(locationBoundary: location, client: client)
    : CheckNearbyPharmacy(locationBoundary: location, client: client);

// Function Name: main
// Description: Registers policy, disposal and neutral dependency regressions.
// Parameters: None. Returns: None; registered tests report lifecycle violations.
void main() {
  for (final hospital in [false, true]) {
    // Function Name: sibling defaults test
    // Description: A shared contract must preserve hospital 300 m and pharmacy 20 km defaults.
    // Parameters: hospital: selected test provider. Returns: None.
    test(
      'shared contract retains provider radius: hospital=$hospital',
      () async {
        final location = _PendingLocation()..result.complete(_coordinate);
        final radii = <String?>[];
        final paths = <String>[];
        final client = MockClient((request) async {
          radii.add(request.url.queryParameters['max_distance_km']);
          paths.add(request.url.path);
          return http.Response(
            '{"data":[{"pharmacy_id":"p1","name":"Sample"}]}',
            200,
          );
        });
        final control = _create(hospital, location, client);
        addTearDown(control.dispose);
        addTearDown(client.close);
        expect(control, isA<CheckNearbyCare>());
        if (hospital) expect(control, isNot(isA<CheckNearbyPharmacy>()));
        await control.requestNearbyCareSearch();
        expect(radii, [hospital ? '0.3' : '20.0']);
        expect(paths, [
          hospital ? '/api/v1/hospitals/nearby' : '/api/v1/pharmacy/nearby',
        ]);
        expect(location.requests, 1);
        final area = await control.requestSearchArea();
        expect(area.radiusKm, hospital ? .3 : 20);
        expect(location.requests, 2);
      },
    );

    // Function Name: closed control test
    // Description: A disposed provider must not start GPS or HTTP for a new search.
    // Parameters: hospital: selected test provider. Returns: None.
    test('disposed provider starts no work: hospital=$hospital', () async {
      final location = _PendingLocation();
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"data":[]}', 200);
      });
      addTearDown(client.close);
      final control = _create(hospital, location, client)..dispose();
      await expectLater(control.requestNearbyCareSearch(), throwsStateError);
      await expectLater(control.requestSearchArea(), throwsStateError);
      expect(location.requests, 0);
      expect(calls, 0);
    });

    for (final failGps in [false, true]) {
      // Function Name: pending GPS disposal test
      // Description: Neither successful GPS nor fallback may initiate HTTP after disposal.
      // Parameters: hospital, failGps: provider and completion case. Returns: None.
      test(
        'pending GPS is inert after disposal: hospital=$hospital failure=$failGps',
        () async {
          final location = _PendingLocation();
          var calls = 0;
          final client = MockClient((_) async {
            calls++;
            return http.Response('{"data":[]}', 200);
          });
          addTearDown(client.close);
          final control = _create(hospital, location, client);
          final pending = control.requestNearbyCareSearch();
          final assertion = expectLater(pending, throwsStateError);
          expect(location.requests, 1);
          control.dispose();
          if (failGps) {
            location.result.completeError(
              const DeviceLocationException(DeviceLocationFailure.denied),
            );
          } else {
            location.result.complete(_coordinate);
          }
          await assertion;
          expect(calls, 0);
          // A borrowed client still belongs to its caller after repeated disposal.
          control.dispose();
          await client.get(Uri.parse('https://example.test/still-owned'));
          expect(calls, 1);
        },
      );
    }
  }

  // Function Name: provider dependency test
  // Description: Hospital and shared controls must never depend on the concrete pharmacy control.
  // Parameters: None. Returns: None; forbidden import/subtyping fails the test.
  test('provider siblings depend only on the shared nearby-care owner', () {
    for (final name in [
      'check_nearby_hospital_control',
      'check_nearby_care_control',
    ]) {
      final source = File('lib/controls/$name.dart').readAsStringSync();
      expect(
        source,
        isNot(contains("import 'check_nearby_pharmacy_control.dart'")),
      );
      expect(source, isNot(contains('extends CheckNearbyPharmacy')));
      expect(source, isNot(contains('requestNearbyPharmacies(')));
    }
  });

  // Function Name: location dependency test
  // Description: Generic GPS values must not acquire provider or platform entity dependencies, and the unused fix cache stays removed.
  // Parameters: None. Returns: None; domain-coupled imports fail the test.
  test('GPS service is independent of pharmacy records and keeps no cache', () {
    final source = File(
      'lib/services/device_location_service.dart',
    ).readAsStringSync();
    expect(source, contains('device_coordinate_entity.dart'));
    expect(source, isNot(contains('nearby_pharmacy_entity.dart')));
    expect(source, isNot(contains('recent_device_coordinate_cache')));
    expect(
      File('lib/services/recent_device_coordinate_cache.dart').existsSync(),
      isFalse,
    );
    final coordinate = File(
      'lib/entities/device_coordinate_entity.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'^\s*(import|export|part)\s',
        multiLine: true,
      ).hasMatch(coordinate),
      isFalse,
    );
  });
}
