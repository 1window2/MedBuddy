// File Name: nearby_care_contract_test.dart
// Role: Guards provider-neutral display contracts without changing wire, radius or favorite-storage policy.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_care_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _UnavailableLocation
// Role: Simulates denied GPS without accessing a real device or permission settings.
// Responsibilities: Count requests and provide deterministic fallback evidence.
// Attributes: requests: number of attempted coordinate reads.
class _UnavailableLocation implements DeviceLocationBoundary {
  int requests = 0;

  // Function Name: requestCurrentCoordinate
  // Description: Records a coordinate attempt and preserves the typed denied-location failure.
  // Parameters: None. Returns: No coordinate; always throws the simulated failure.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    requests++;
    throw const DeviceLocationException(DeviceLocationFailure.denied);
  }

  // Function Name: openApplicationSettings
  // Description: Avoids changing system permissions.
  // Parameters: None. Returns: A simulated successful settings action.
  @override
  Future<bool> openApplicationSettings() async => true;

  // Function Name: openDeviceLocationSettings
  // Description: Avoids changing system location settings.
  // Parameters: None. Returns: A simulated successful settings action.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

// Function Name: main
// Description: Registers provider identity, metadata, radius, selection and architecture regressions.
// Parameters: None. Returns: None; tests report contract drift without network or device access.
void main() {
  for (final wireField in ['pharmacy_id', 'hospital_id']) {
    for (final identifier in <Object>['000123', 'A-0001', 37]) {
      // Function Name: provider identifier test
      // Description: Preserves the original wire identifier rather than guessing a provider from its format.
      // Parameters: wireField/identifier: original backend key and value. Returns: None.
      test('$wireField decodes neutral identifier $identifier', () {
        final place = NearbyCarePlace.fromJson({
          wireField: identifier,
          'name': 'Sample',
        });
        expect(place.placeId, identifier.toString());
        expect(place.isOpenNow, isNull);
      });
    }
  }

  // Function Name: legacy identifier precedence test
  // Description: Keeps the previous pharmacy_id precedence when both backend fields are supplied.
  // Parameters: None. Returns: None; no wire decoding behavior changes during the rename.
  test('legacy wire identity precedence remains unchanged', () {
    expect(
      NearbyCarePlace.fromJson({
        'pharmacy_id': 'P',
        'hospital_id': 'H',
      }).placeId,
      'P',
    );
  });

  // Function Name: reliability metadata test
  // Description: Retains optional hospital metadata, pharmacy designation and unknown operating status.
  // Parameters: None. Returns: None; unknown hours never become a confirmed closed/open state.
  test('neutral display preserves provider metadata and uncertainty', () {
    final place = NearbyCarePlace.fromJson({
      'hospital_id': '000123',
      'name': 'Sample',
      'departments': ['D001', 1],
      'institution_type': 'Clinic',
      'is_open_now': 'false',
      'is_official_late_night': true,
      'designation_source_name': 'Verified source',
      'designation_source_url': 'https://example.test/designation',
      'designation_verified_at': '2026-10-01T00:00:00Z',
      'designation_is_stale': true,
      'schedule_date': '2026-10-05',
      'schedule_source': 'date_specific_report',
      'schedule_is_date_specific': true,
      'source_updated_at': '2026-10-02T00:00:00Z',
    });
    expect(place.departments, ['D001']);
    expect(() => place.departments.add('D002'), throwsUnsupportedError);
    expect(place.institutionType, 'Clinic');
    expect(place.isOpenNow, isNull);
    expect(place.isOfficialLateNight, isTrue);
    expect(place.designationSourceName, 'Verified source');
    expect(place.designationSourceUrl, 'https://example.test/designation');
    expect(place.designationVerifiedAt, DateTime.utc(2026, 10, 1));
    expect(place.designationIsStale, isTrue);
    expect(place.scheduleDate, DateTime(2026, 10, 5));
    expect(place.scheduleSource, 'date_specific_report');
    expect(place.scheduleIsDateSpecific, isTrue);
    expect(place.sourceUpdatedAt, DateTime.utc(2026, 10, 2));
  });

  // Function Name: selection provenance test
  // Description: A neutral selection must preserve the user's place, phone confirmation and searched date.
  // Parameters: None. Returns: None; display identity does not imply a backend route.
  test('selection preserves exact phone and date provenance', () {
    final place = NearbyCarePlace.fromJson({
      'hospital_id': '000123',
      'name': 'Sample',
    });
    final date = DateTime(2026, 10, 5);
    final selection = NearbyCareSelection(
      place: place,
      phoneVerified: true,
      scheduleDate: date,
    );
    expect(selection.place, same(place));
    expect(selection.phoneVerified, isTrue);
    expect(selection.scheduleDate, same(date));
    expect(
      NearbyCareSelection(place: place, phoneVerified: false).scheduleDate,
      isNull,
    );
  });

  // Function Name: wire filter values test
  // Description: A shared enum must retain every existing backend query value exactly.
  // Parameters: None. Returns: None; provider-specific UI applicability remains outside this value contract.
  test('search mode wire values remain unchanged', () {
    expect(NearbyCareSearchMode.values.map((mode) => mode.apiValue), [
      'all',
      'open_at_time',
      'late_hours',
      'official_late_night',
      'weekend_holiday',
    ]);
  });

  for (final hospital in [false, true]) {
    // Function Name: provider fallback policy test
    // Description: GPS failure retains each provider's existing radius and never becomes a real device fix.
    // Parameters: hospital: selected provider. Returns: None; checks endpoint, ID and reliability together.
    test('fallback retains provider policy: hospital=$hospital', () async {
      final location = _UnavailableLocation();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': [
              {
                hospital ? 'hospital_id' : 'pharmacy_id': '000123',
                'name': 'Sample',
              },
            ],
            'catalog_updated_at': '2026-10-01T00:00:00Z',
            'catalog_is_stale': true,
            'holiday_schedule_status': 'unknown',
            'search_truncated': true,
            'region_scope_uncertain': true,
          }),
          200,
        );
      });
      final CheckNearbyCare control = hospital
          ? CheckNearbyHospital(locationBoundary: location, client: client)
          : CheckNearbyPharmacy(locationBoundary: location, client: client);
      addTearDown(control.dispose);
      addTearDown(client.close);
      final result = await control.requestNearbyCareSearch();
      final area = result.searchArea!;
      expect(area.center, same(NearbyCareSearchArea.fallbackCenter));
      expect(area.radiusKm, hospital ? .3 : 20);
      expect(area.isFallback, isTrue);
      expect(area.isMapArea, isFalse);
      expect(area.isValid, isTrue);
      expect(location.requests, 1);
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        hospital ? '/api/v1/hospitals/nearby' : '/api/v1/pharmacy/nearby',
      );
      expect(
        requests.single.url.queryParameters['max_distance_km'],
        hospital ? '0.3' : '20.0',
      );
      expect(result.data.single.placeId, '000123');
      expect(result.catalogUpdatedAt, DateTime.utc(2026, 10, 1));
      expect(result.catalogIsStale, isTrue);
      expect(result.holidayScheduleStatus, 'unknown');
      expect(result.searchTruncated, isTrue);
      expect(result.regionScopeUncertain, isTrue);
    });

    for (final userHash in ['', ' account ']) {
      // Function Name: legacy favorites namespace test
      // Description: Neutral display IDs must still use original provider/account preference keys.
      // Parameters: hospital/userHash: existing storage scope. Returns: None; other provider keys remain untouched.
      test(
        'legacy favorite keys remain: hospital=$hospital user=$userHash',
        () async {
          final suffix = userHash.trim().isEmpty ? '' : '.account';
          final pharmacyKey = 'medbuddy.favorite_pharmacy_ids$suffix';
          final hospitalKey = 'medbuddy.favorite_hospital_ids$suffix';
          SharedPreferences.setMockInitialValues({
            pharmacyKey: ['P'],
            hospitalKey: ['H'],
          });
          final preferences = await SharedPreferences.getInstance();
          final service = PharmacyFavoriteService(
            hospitals: hospital,
            userHash: userHash,
            preferencesLoader: () async => preferences,
          );
          expect(await service.loadFavoriteIds(), {hospital ? 'H' : 'P'});
          final place = NearbyCarePlace.fromJson({
            hospital ? 'hospital_id' : 'pharmacy_id': '000123',
          });
          expect(await service.saveFavoriteIds({place.placeId}), isTrue);
          expect(
            preferences.getStringList(hospital ? hospitalKey : pharmacyKey),
            ['000123'],
          );
          expect(
            preferences.getStringList(hospital ? pharmacyKey : hospitalKey),
            [hospital ? 'P' : 'H'],
          );
        },
      );
    }
  }

  // Function Name: entity architecture test
  // Description: Neutral entities must not depend on UI, controls, platform services or the retired pharmacy DTO.
  // Parameters: None. Returns: None; source checks prevent the old coupling from being reintroduced.
  test(
    'neutral contracts contain only values and no provider radius default',
    () {
      final source = File(
        'lib/entities/nearby_care_entity.dart',
      ).readAsStringSync();
      final imports = RegExp(
        r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)).toList();
      expect(imports, ['device_coordinate_entity.dart']);
      expect(source, contains('required this.radiusKm'));
      expect(source, isNot(contains('this.radiusKm =')));
      expect(source, isNot(contains('static const hongik')));
      expect(
        File('lib/entities/nearby_pharmacy_entity.dart').existsSync(),
        isFalse,
      );
      for (final entity in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        expect(
          entity.readAsStringSync(),
          isNot(contains('nearby_pharmacy_entity.dart')),
          reason: entity.path,
        );
      }
    },
  );
}
