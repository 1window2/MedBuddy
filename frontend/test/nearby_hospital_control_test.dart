// 병원 조회 조건, 공통 표시 모델, 약국과 분리된 즐겨찾기를 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
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

const _area = PharmacySearchArea(
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
      final result = await control.requestNearbyPharmacySearch(
        searchArea: _area,
        searchMode: PharmacySearchMode.lateHours,
      );
      final item = result.data.single;
      expect(item.pharmacyId, 'A123');
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
    await control.requestNearbyPharmacySearch(searchArea: _area);
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
    final pending = control.requestNearbyPharmacySearch();
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
        control.requestNearbyPharmacySearch(searchArea: _area),
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
