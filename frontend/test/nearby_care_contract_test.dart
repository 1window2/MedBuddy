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
import 'package:medbuddy_frontend/services/api_response_parser.dart';
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

// Function Name: _place
// Description: Builds a synthetic result that differs only in the fields the display order reads.
// Parameters: id: place identifier; open/late/official/allDay: operating evidence; distanceKm: query distance.
// Returns: A place with no network or device origin.
NearbyCarePlace _place(
  String id, {
  bool? open,
  bool late = false,
  bool official = false,
  bool allDay = false,
  double distanceKm = 1,
}) => NearbyCarePlace(
  placeId: id,
  name: id,
  address: '',
  telephone: '',
  latitude: 37.55,
  longitude: 126.92,
  distanceKm: distanceKm,
  todayOpenTime: null,
  todayCloseTime: null,
  isOpenNow: open,
  is24Hours: allDay,
  isOpenLate: late,
  isOfficialLateNight: official,
);

// Function Name: main
// Description: Registers provider identity, metadata, radius, selection and architecture regressions.
// Parameters: None. Returns: None; tests report contract drift without network or device access.
void main() {
  // Function Name: display order test
  // Description: Results are ordered by open state, late operation, favorite membership and distance, without touching the input.
  // Parameters: None. Returns: None.
  test('display order is open, late, favorite, then nearest', () {
    final places = [
      _place('closed-near', open: false, distanceKm: .1),
      _place('unknown-late', late: true, distanceKm: .2),
      _place('open-far', open: true, distanceKm: 9),
      _place('open-near', open: true, distanceKm: 2),
      _place('open-favorite', open: true, distanceKm: 5),
      _place('open-late', open: true, late: true, distanceKm: 8),
      _place('open-all-day', open: true, allDay: true, distanceKm: 7),
    ];
    final original = List.of(places);
    final sorted = sortNearbyCarePlaces(
      places,
      favoriteIds: {'open-favorite', 'closed-near'},
      hospitals: false,
    );
    expect(sorted.map((place) => place.placeId), [
      'open-all-day',
      'open-late',
      'open-favorite',
      'open-near',
      'open-far',
      'unknown-late',
      'closed-near',
    ]);
    expect(places, original);
    expect(sorted, isNot(same(places)));
  });

  // Function Name: late-operation provider test
  // Description: The official late-night designation counts for pharmacies only; reported late hours count for both.
  // Parameters: None. Returns: None.
  test('official late-night designation ranks pharmacies only', () {
    final official = _place('official', open: true, official: true);
    expect(nearbyCarePlaceOperatesLate(official, hospitals: false), isTrue);
    expect(nearbyCarePlaceOperatesLate(official, hospitals: true), isFalse);
    for (final hospitals in [false, true]) {
      expect(
        nearbyCarePlaceOperatesLate(
          _place('late', late: true),
          hospitals: hospitals,
        ),
        isTrue,
      );
      expect(
        nearbyCarePlaceOperatesLate(
          _place('all-day', allDay: true),
          hospitals: hospitals,
        ),
        isTrue,
      );
      expect(
        nearbyCarePlaceOperatesLate(_place('plain'), hospitals: hospitals),
        isFalse,
      );
    }
    final places = [
      _place('plain-near', open: true, distanceKm: 1),
      _place('official-far', open: true, official: true, distanceKm: 5),
    ];
    expect(
      sortNearbyCarePlaces(
        places,
        favoriteIds: const {},
        hospitals: false,
      ).first.placeId,
      'official-far',
    );
    expect(
      sortNearbyCarePlaces(
        places,
        favoriteIds: const {},
        hospitals: true,
      ).first.placeId,
      'plain-near',
    );
  });

  for (final hospital in [false, true]) {
    // Function Name: typed request failure test
    // Description: A rejected response keeps its message and status; a transport error keeps its message and original cause.
    // Parameters: hospital: selected provider. Returns: None.
    test('request failures stay typed: hospital=$hospital', () async {
      const area = NearbyCareSearchArea(
        center: NearbyCareSearchArea.fallbackCenter,
        radiusKm: 5,
        isMapArea: true,
      );
      var offline = false;
      final client = MockClient((_) async {
        if (offline) throw const SocketException('offline');
        return http.Response(jsonEncode({'detail': 'busy'}), 503);
      });
      final CheckNearbyCare control = hospital
          ? CheckNearbyHospital(client: client)
          : CheckNearbyPharmacy(client: client);
      addTearDown(control.dispose);
      addTearDown(client.close);
      await expectLater(
        control.requestNearbyCareSearch(searchArea: area),
        throwsA(
          isA<ApiRequestException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having(
                (error) => error.message,
                'message',
                'Nearby care request failed (503): busy',
              ),
        ),
      );
      offline = true;
      await expectLater(
        control.requestNearbyCareSearch(searchArea: area),
        throwsA(
          isA<ApiRequestException>()
              .having((error) => error.statusCode, 'statusCode', isNull)
              .having((error) => error.cause, 'cause', isA<SocketException>())
              .having(
                (error) => error.message,
                'message',
                'Nearby care request failed.',
              ),
        ),
      );
    });
  }

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
      expect(imports, [
        'device_coordinate_entity.dart',
        'json_value_reader.dart',
      ]);
      // The shared JSON reader must stay a dependency-free value helper.
      expect(
        File('lib/entities/json_value_reader.dart').readAsStringSync(),
        isNot(
          contains(RegExp(r'^\s*(?:import|export|part)\s', multiLine: true)),
        ),
      );
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
