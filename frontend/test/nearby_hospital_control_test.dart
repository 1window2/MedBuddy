// 병원 조회 조건, 공통 표시 모델, 약국과 분리된 즐겨찾기를 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Location implements DeviceLocationBoundary {
  final Completer<DeviceCoordinate> result = Completer();
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() => result.future;
  @override
  Future<bool> openApplicationSettings() async => true;
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

const _area = NearbyCareSearchArea(
  center: DeviceCoordinate(latitude: 37.55, longitude: 126.92),
  radiusKm: 5,
  isMapArea: true,
);

// 실제 외부 병원 API를 호출하지 않고 모바일 응답 계약만 검사한다.
http.Response _response({Object? data = const []}) => http.Response(
  jsonEncode({'data': data, 'catalog_is_stale': false}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  // 지역 표본의 한계를 실제 조회 제한과 별개로 읽고 구버전 응답도 허용한다.
  for (final scope in [null, false, true]) {
    for (final truncated in [false, true]) {
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

  // 300m부터 결과가 있는 첫 범위에서 멈추고, 끝까지 비어 있어도 2km까지만 조회한다.
  for (final foundAt in <double?>[.3, .5, 1, 2, null]) {
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

  // 직접 고른 지도는 좁더라도 자동으로 확장하지 않는다.
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
  });

  // 위치 대체 상태와 중심을 유지해 보호자의 실제 위치로 오인하지 않게 한다.
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

  // 운영 판정 장애와 날짜 조건 불일치를 거리 부족으로 오인하지 않는다.
  for (final unknown in [true, false]) {
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

  // 확장 도중 장애도 정상 빈 결과로 숨기지 않고 추가 요청을 멈춘다.
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

  // 화면 종료 또는 새 검색이 시작되면 이전 응답이 다음 반경 요청을 만들지 않는다.
  for (final dispose in [true, false]) {
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

  // 진료과목과 운영 조건은 독립적으로 서버에 전달되어야 한다.
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

  // 과목 선택 해제 후에는 이전 과목 조건이 남지 않아야 한다.
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

  // GPS를 기다리는 동안 조건이 바뀌어도 각 요청은 시작 시점의 조건을 유지한다.
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

  // 실패 응답과 잘못된 목록은 정상적인 빈 검색 결과로 바꾸지 않는다.
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

  // 같은 사용자·같은 식별자라도 병원과 약국의 즐겨찾기는 서로 영향을 주지 않는다.
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
}
