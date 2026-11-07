// 파일명: nearby_hospital_control_test.dart
// 역할: 병원 조회 조건, 공통 표시 모델, 약국과 분리된 즐겨찾기를 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _Location
// 역할: 위치 조회 완료 시점을 직접 제어하는 병원 검색 테스트 대역.
// 주요 책임:
// - GPS 대기 중 진료과 변경과 요청 상태를 재현하고 설정 이동은 실제 실행하지 않는다.
// 속성:
// - result (Completer<DeviceCoordinate>): 테스트가 좌표 또는 오류로 완료할 위치 응답.
class _Location implements DeviceLocationBoundary {
  final Completer<DeviceCoordinate> result = Completer();
  // 함수이름: requestCurrentCoordinate
  // 함수역할:
  // - 테스트가 준비한 위치 응답 Future를 그대로 반환하여 GPS 대기 상태를 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DeviceCoordinate>; result에 지정한 좌표 또는 오류로 완료한다.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() => result.future;
  // 함수이름: openApplicationSettings
  // 함수역할:
  // - 실제 앱 설정을 열지 않고 설정 이동 성공을 모의한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>; true로 완료한다.
  @override
  Future<bool> openApplicationSettings() async => true;
  // 함수이름: openDeviceLocationSettings
  // 함수역할:
  // - 실제 기기 위치 설정을 열지 않고 설정 이동 성공을 모의한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>; true로 완료한다.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

// Explicit 5km map-area fixture; unlike a device-location search, it must not auto-expand.
const _area = NearbyCareSearchArea(
  center: DeviceCoordinate(latitude: 37.55, longitude: 126.92),
  radiusKm: 5,
  isMapArea: true,
);

// 함수이름: _response
// 함수역할:
// - 병원 data 필드와 최신 카탈로그 표시를 가진 JSON 응답을 만들며 잘못된 data 형태도 그대로 인코딩한다.
// 매개변수:
// - data (Object?): 기본 빈 목록; 정상 병원 목록 또는 파싱 실패 검증용 문자열 등 JSON으로 인코딩 가능한 값.
// 반환값:
// - http.Response; UTF-8 JSON HTTP 200 응답. JSON으로 인코딩할 수 없는 값은 인코딩 오류가 난다.
http.Response _response({Object? data = const []}) => http.Response(
  jsonEncode({'data': data, 'catalog_is_stale': false}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// Function Name: main
// Description:
// - Initialize the widget binding and register hospital request, expansion, calendar, cancellation, favorites, and error-contract tests.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  for (final scope in [null, false, true]) {
    for (final truncated in [false, true]) {
      // Function Name: region scope $scope is independent of truncation $truncated
      // Description:
      // - Decode region_scope_uncertain independently from search_truncated; an omitted region flag behaves as false even for truncated results.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completes after the asynchronous checks.
      test(
        'region scope $scope is independent of truncation $truncated',
        () async {
          final control = CheckNearbyHospital(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'data': [],
                  'search_truncated': truncated,
                  'region_scope_uncertain': ?scope,
                }),
                200,
              ),
            ),
          );
          addTearDown(control.dispose);
          final result = await control.requestNearbyCareSearch(
            searchArea: _area,
          );
          expect(result.searchTruncated, truncated);
          expect(result.regionScopeUncertain, scope == true);
        },
      );
    }
  }

  for (final foundAt in <double?>[.3, .5, 1, 2, null]) {
    // Function Name: empty nearby search widens until $foundAt
    // Description:
    // - Expand empty device-location searches through 0.3, 0.5, 1, and 2km until a hospital is found or the limit is reached, preserving department, coordinates, and time and reporting whether expansion occurred.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
    test('empty nearby search widens until $foundAt', () async {
      final requests = <Uri>[];
      final location = _Location()..result.complete(_area.center);
      final time = DateTime(2026, 9, 29, 10);
      final control = CheckNearbyHospital(
        department: 'D013',
        locationBoundary: location,
        client: MockClient((request) async {
          requests.add(request.url);
          final radius = double.parse(
            request.url.queryParameters['max_distance_km']!,
          );
          return _response(
            data: radius == foundAt
                ? [
                    {'hospital_id': 'A1', 'name': 'Sample'},
                  ]
                : [],
          );
        }),
      );
      addTearDown(control.dispose);
      final result = await control.requestNearbyCareSearch(
        searchMode: NearbyCareSearchMode.all,
        targetDateTime: time,
      );
      final expected = [
        .3,
        .5,
        1.0,
        2.0,
      ].where((r) => foundAt == null || r <= foundAt).toList();
      expect(
        requests.map(
          (uri) => double.parse(uri.queryParameters['max_distance_km']!),
        ),
        expected,
      );
      expect(result.searchArea!.radiusKm, expected.last);
      expect(result.searchArea!.isMapArea, isFalse);
      // The UI uses this flag, not radius comparisons, to explain automatic expansion.
      expect(result.searchRadiusExpanded, expected.length > 1);
      expect(
        requests.every(
          (uri) =>
              uri.queryParameters['department'] == 'D013' &&
              uri.queryParameters['latitude'] == '37.5500000' &&
              uri.queryParameters['longitude'] == '126.9200000' &&
              uri.queryParameters['target_datetime'] == time.toIso8601String(),
        ),
        isTrue,
      );
    });
  }

  // Function Name: empty manually selected 300m area is preserved
  // Description:
  // - An explicitly chosen 300m map area stays unchanged after an empty result: perform one request and do not mark automatic expansion.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('empty manually selected 300m area is preserved', () async {
    var calls = 0;
    final area = NearbyCareSearchArea(
      center: _area.center,
      radiusKm: .3,
      isMapArea: true,
    );
    final control = CheckNearbyHospital(
      client: MockClient((_) async {
        calls++;
        return _response();
      }),
    );
    addTearDown(control.dispose);
    final result = await control.requestNearbyCareSearch(searchArea: area);
    expect(calls, 1);
    expect(result.searchArea, same(area));
    expect(result.searchRadiusExpanded, isFalse);
  });

  // Function Name: weekend search on a confirmed weekday is the only date mismatch
  // Description:
  // - Treat weekend/holiday mode as a date mismatch only on a weekday confirmed not to be a holiday; exclude weekends, holiday/unknown calendar states, and every other search mode.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  test('weekend search on a confirmed weekday is the only date mismatch', () {
    final tuesday = DateTime(2026, 9, 29);
    final saturday = DateTime(2026, 10, 3);
    // Function Name: mismatch
    // Description:
    // - Evaluate the hospital weekend-date guard for a supplied search mode and calendar classification.
    // Parameters:
    // - mode (NearbyCareSearchMode): search condition being checked.
    // - date (DateTime): target date whose weekday is evaluated.
    // - status (String): holiday status, including not_applicable, known fallback states, or unknown.
    // Returns:
    // - bool; whether the weekend/holiday search targets a confirmed non-holiday weekday.
    bool mismatch(NearbyCareSearchMode mode, DateTime date, String status) =>
        CheckNearbyHospital.isWeekendSearchOnWeekday(
          searchMode: mode,
          targetDateTime: date,
          holidayScheduleStatus: status,
        );
    expect(
      mismatch(NearbyCareSearchMode.weekendHoliday, tuesday, 'not_applicable'),
      isTrue,
    );
    expect(
      mismatch(
        NearbyCareSearchMode.weekendHoliday,
        DateTime(2026, 10, 2),
        NearbyCareSearchResult.holidayScheduleNotApplicable,
      ),
      isTrue,
    );
    // Exclude weekends, known holidays, unverified weekdays, and other search modes.
    expect(
      mismatch(NearbyCareSearchMode.weekendHoliday, saturday, 'not_applicable'),
      isFalse,
    );
    expect(
      mismatch(
        NearbyCareSearchMode.weekendHoliday,
        DateTime(2026, 10, 4),
        'not_applicable',
      ),
      isFalse,
    );
    for (final status in ['exact', 'stale_fallback', 'weekly_fallback']) {
      expect(
        mismatch(NearbyCareSearchMode.weekendHoliday, tuesday, status),
        isFalse,
      );
    }
    expect(
      mismatch(
        NearbyCareSearchMode.weekendHoliday,
        tuesday,
        NearbyCareSearchResult.holidayScheduleUnknown,
      ),
      isFalse,
    );
    for (final mode in NearbyCareSearchMode.values) {
      if (mode == NearbyCareSearchMode.weekendHoliday) continue;
      expect(mismatch(mode, tuesday, 'not_applicable'), isFalse);
    }
  });

  // Function Name: automatic expansion preserves fallback source
  // Description:
  // - When fallback-location results remain empty, expansion reaches 2km without losing the original center or isFallback provenance.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('automatic expansion preserves fallback source', () async {
    final control = CheckNearbyHospital(
      client: MockClient((_) async => _response()),
    );
    addTearDown(control.dispose);
    final result = await control.requestNearbyCareSearch(
      searchArea: NearbyCareSearchArea(
        center: _area.center,
        radiusKm: .3,
        isFallback: true,
      ),
    );
    expect(result.searchArea!.radiusKm, 2);
    expect(result.searchArea!.isFallback, isTrue);
    expect(result.searchArea!.center, _area.center);
  });

  for (final unknown in [true, false]) {
    // Function Name: calendar condition prevents expansion: unknown=$unknown
    // Description:
    // - Do not widen an empty 300m search when calendar status is unknown for open-at-time, or when weekend/holiday mode targets a confirmed weekday.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
    test('calendar condition prevents expansion: unknown=$unknown', () async {
      var calls = 0;
      final control = CheckNearbyHospital(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'data': [],
              'holiday_schedule_status': unknown ? 'unknown' : 'not_applicable',
            }),
            200,
          );
        }),
      );
      addTearDown(control.dispose);
      await control.requestNearbyCareSearch(
        searchArea: NearbyCareSearchArea(center: _area.center, radiusKm: .3),
        targetDateTime: DateTime(2026, 9, 29),
        searchMode: unknown
            ? NearbyCareSearchMode.openAtTime
            : NearbyCareSearchMode.weekendHoliday,
      );
      expect(calls, 1);
    });
  }

  // Function Name: expansion failure is propagated without further requests
  // Description:
  // - If the first radius expansion receives HTTP 503, propagate StateError after exactly two requests and do not try further radii.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('expansion failure is propagated without further requests', () async {
    var calls = 0;
    final control = CheckNearbyHospital(
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? _response() : http.Response('{}', 503);
      }),
    );
    addTearDown(control.dispose);
    await expectLater(
      control.requestNearbyCareSearch(
        searchArea: NearbyCareSearchArea(center: _area.center, radiusKm: .3),
      ),
      throwsStateError,
    );
    expect(calls, 2);
  });

  for (final dispose in [true, false]) {
    // Function Name: obsolete search does not expand: dispose=$dispose
    // Description:
    // - A delayed empty response must not trigger expansion after disposal or after a newer explicit-area search supersedes it.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
    test('obsolete search does not expand: dispose=$dispose', () async {
      final gate = Completer<http.Response>();
      var calls = 0;
      final control = CheckNearbyHospital(
        client: MockClient((_) async {
          calls++;
          return calls == 1 ? gate.future : _response();
        }),
      );
      final pending = control.requestNearbyCareSearch(
        searchArea: NearbyCareSearchArea(center: _area.center, radiusKm: .3),
      );
      await Future<void>.delayed(Duration.zero);
      if (dispose) {
        control.dispose();
      } else {
        await control.requestNearbyCareSearch(searchArea: _area);
      }
      gate.complete(_response());
      await pending;
      expect(calls, dispose ? 1 : 2);
      if (!dispose) control.dispose();
    });
  }

  // Function Name: hospital request combines department, operating filter and map area
  // Description:
  // - Combine specialty, late-hours mode, and map bounds in the hospital endpoint request, preserving hospital metadata and unknown opening status without assigning pharmacy-only designation flags.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test(
    'hospital request combines department, operating filter and map area',
    () async {
      final control = CheckNearbyHospital(
        department: 'D013',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/hospitals/nearby');
          expect(request.url.queryParameters['department'], 'D013');
          expect(request.url.queryParameters['search_mode'], 'late_hours');
          expect(request.url.queryParameters['max_distance_km'], '5.0');
          expect(request.url.queryParameters['latitude'], '37.5500000');
          return _response(
            data: [
              {
                'hospital_id': 'A123',
                'name': '테스트이비인후과',
                'address': '서울특별시',
                'telephone': '02-123-4567',
                'latitude': 37.551,
                'longitude': 126.922,
                'distance_km': 0.2,
                'is_open_now': null,
                'departments': ['이비인후과'],
                'institution_type': '의원',
              },
            ],
          );
        }),
      );
      final result = await control.requestNearbyCareSearch(
        searchArea: _area,
        searchMode: NearbyCareSearchMode.lateHours,
      );
      final item = result.data.single;
      expect(item.placeId, 'A123');
      expect(item.departments, ['이비인후과']);
      expect(item.institutionType, '의원');
      expect(item.isOpenNow, isNull);
      expect(item.isOfficialLateNight, isFalse);
      expect(result.searchArea, same(_area));
      control.dispose();
    },
  );

  // Function Name: all departments omits department from request
  // Description:
  // - Selecting all departments omits the department query parameter entirely from an explicit-area hospital request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('all departments omits department from request', () async {
    final control = CheckNearbyHospital(
      client: MockClient((request) async {
        expect(request.url.queryParameters.containsKey('department'), isFalse);
        return _response();
      }),
    );
    await control.requestNearbyCareSearch(searchArea: _area);
    control.dispose();
  });

  // Function Name: department is captured before awaiting location
  // Description:
  // - Capture the department when the search starts so changing it during GPS lookup cannot alter that pending search request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('department is captured before awaiting location', () async {
    final location = _Location();
    final control = CheckNearbyHospital(
      locationBoundary: location,
      department: 'D001',
      client: MockClient((request) async {
        expect(request.url.queryParameters['department'], 'D001');
        return _response();
      }),
    );
    final pending = control.requestNearbyCareSearch();
    control.department = 'D013';
    location.result.complete(_area.center);
    await pending;
    control.dispose();
  });

  // Function Name: malformed response and service errors are propagated
  // Description:
  // - Reject both a non-list data field and an HTTP 503 response as StateError rather than returning a successful empty hospital list.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('malformed response and service errors are propagated', () async {
    for (final response in [
      _response(data: 'invalid'),
      http.Response('{}', 503),
    ]) {
      final control = CheckNearbyHospital(
        client: MockClient((_) async => response),
      );
      await expectLater(
        control.requestNearbyCareSearch(searchArea: _area),
        throwsStateError,
      );
      control.dispose();
    }
  });

  // 함수이름: hospital favorites preserve existing pharmacy favorites
  // 함수역할:
  // - 병원 즐겨찾기를 저장해도 기존 약국 즐겨찾기를 보존하고, 같은 병원 저장값이 다른 사용자의 목록에 섞이지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  test('hospital favorites preserve existing pharmacy favorites', () async {
    SharedPreferences.setMockInitialValues({
      'medbuddy.favorite_pharmacy_ids.patient': ['C1'],
    });
    final pharmacy = PharmacyFavoriteService(userHash: 'patient');
    final hospital = PharmacyFavoriteService(
      userHash: 'patient',
      hospitals: true,
    );
    expect(await hospital.loadFavoriteIds(), isEmpty);
    await hospital.saveFavoriteIds({'A1'});
    expect(await pharmacy.loadFavoriteIds(), {'C1'});
    expect(await hospital.loadFavoriteIds(), {'A1'});
    expect(
      await PharmacyFavoriteService(
        userHash: 'caregiver',
        hospitals: true,
      ).loadFavoriteIds(),
      isEmpty,
    );
  });

  // Function Name: nearby request failures keep their message, status and cause
  // Description:
  // - Preserve transport causes and server status/detail in ApiRequestException, while a malformed successful response remains a distinct StateError.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('nearby request failures keep their message, status and cause', () async {
    // Function Name: search
    // Description:
    // - Run one explicit-area hospital search against the supplied transport and capture its thrown error; fail the test if the search succeeds.
    // Parameters:
    // - handler (MockClientHandler): response or transport failure used by the mock HTTP client.
    // Returns:
    // - Future<Object?>; resolves to the caught error object; unexpected success raises a test failure.
    Future<Object?> search(MockClientHandler handler) async {
      final control = CheckNearbyHospital(client: MockClient(handler));
      addTearDown(control.dispose);
      try {
        await control.requestNearbyCareSearch(searchArea: _area);
      } catch (error) {
        return error;
      }
      fail('The nearby search should have failed.');
    }

    expect(
      await search((_) async => throw http.ClientException('down')),
      isA<ApiRequestException>()
          .having((error) => error.message, 'message', 'Nearby care request failed.')
          .having((error) => error.statusCode, 'statusCode', isNull)
          .having((error) => error.cause, 'cause', isA<http.ClientException>()),
    );
    expect(
      await search(
        (_) async => http.Response(jsonEncode({'detail': 'boom'}), 500),
      ),
      isA<ApiRequestException>()
          .having(
            (error) => error.message,
            'message',
            'Nearby care request failed (500): boom',
          )
          .having((error) => error.statusCode, 'statusCode', 500),
    );
    expect(
      await search((_) async => http.Response('[]', 200)),
      allOf(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Server response format was invalid.',
        ),
        isNot(isA<ApiRequestException>()),
      ),
    );
  });
}
