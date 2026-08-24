// 파일명: check_nearby_pharmacy_control_test.dart
// 역할: 근처 약국 Control의 위치 요청, 응답 변환, 외부 동작을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

class _FakeLocationBoundary implements DeviceLocationBoundary {
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    return const DeviceCoordinate(latitude: 37.5665, longitude: 126.9780);
  }

  @override
  Future<bool> openApplicationSettings() async => true;

  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

void main() {
  test('requestNearbyPharmacies sends coordinates and decodes items', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/pharmacy/nearby');
      expect(request.url.queryParameters['latitude'], '37.5665000');
      expect(request.url.queryParameters['longitude'], '126.9780000');
      expect(request.url.queryParameters['open_only'], 'false');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'pharmacy_id': 'C1234',
              'name': '메드버디약국',
              'address': '서울특별시',
              'telephone': '02-123-4567',
              'latitude': 37.5666,
              'longitude': 126.9781,
              'distance_km': 0.42,
              'today_open_time': '09:00',
              'today_close_time': '24:00',
              'is_open_now': true,
              'is_24_hours': false,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckNearbyPharmacy(
      locationBoundary: _FakeLocationBoundary(),
      client: client,
    );

    final result = await control.requestNearbyPharmacies();

    expect(result, hasLength(1));
    expect(result.single.name, '메드버디약국');
    expect(result.single.distanceLabel, '420m');
    expect(result.single.todayHoursLabel, '오늘 09:00 - 24:00');
  });

  test('phone and directions use validated external URIs', () async {
    final launchedUris = <Uri>[];
    final control = CheckNearbyPharmacy(
      locationBoundary: _FakeLocationBoundary(),
      client: MockClient((_) async => http.Response('{}', 200)),
      uriLauncher: (uri) async {
        launchedUris.add(uri);
        return true;
      },
    );
    const pharmacy = NearbyPharmacy(
      pharmacyId: 'C1234',
      name: '메드버디약국',
      address: '서울특별시',
      telephone: '02-123-4567',
      latitude: 37.5666,
      longitude: 126.9781,
      distanceKm: 0.42,
      todayOpenTime: '09:00',
      todayCloseTime: '24:00',
      isOpenNow: true,
      is24Hours: false,
    );

    expect(await control.requestPhoneCall(pharmacy.telephone), isTrue);
    expect(await control.requestDirections(pharmacy), isTrue);

    expect(launchedUris.first.toString(), 'tel:021234567');
    expect(launchedUris.last.scheme, 'nmap');
    expect(launchedUris.last.host, 'route');
    expect(launchedUris.last.path, '/public');
    expect(launchedUris.last.queryParameters['dlat'], '37.5666000');
    expect(launchedUris.last.queryParameters['dlng'], '126.9781000');
    expect(launchedUris.last.queryParameters['dname'], '메드버디약국');
  });

  test(
    'directions fall back to coordinate-based web directions',
    () async {
      Uri? launchedUri;
      final control = CheckNearbyPharmacy(
        locationBoundary: _FakeLocationBoundary(),
        client: MockClient((_) async => http.Response('{}', 200)),
        uriLauncher: (uri) async {
          launchedUri = uri;
          return uri.scheme == 'https';
        },
      );
      const pharmacy = NearbyPharmacy(
        pharmacyId: 'C1234',
        name: '메드버디약국',
        address: '',
        telephone: '',
        latitude: 37.5666,
        longitude: 126.9781,
        distanceKm: 0.42,
        todayOpenTime: null,
        todayCloseTime: null,
        isOpenNow: null,
        is24Hours: false,
      );

      expect(await control.requestDirections(pharmacy), isTrue);
      expect(launchedUri?.host, 'www.google.com');
      expect(launchedUri?.path, '/maps/dir/');
      expect(launchedUri?.queryParameters['destination'], '37.5666,126.9781');
    },
  );
}
