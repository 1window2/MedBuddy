// 파일명: check_nearby_pharmacy_control_test.dart
// 역할: 근처 약국 Control의 위치 요청, 응답 변환, 외부 동작을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

// 클래스명: _FakeLocationBoundary
// 역할: 약국 검색에 고정 좌표와 설정 이동 성공을 제공하는 위치 대역.
// 주요 책임:
// - 실제 위치 권한이나 GPS 조회 없이 서울 중심부 좌표를 제공한다.
// - 앱 권한 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
// - 기기 위치 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
class _FakeLocationBoundary implements DeviceLocationBoundary {
  // 함수이름: requestCurrentCoordinate
  // 함수역할:
  // - 실제 위치 권한이나 GPS 조회 없이 서울 중심부 좌표를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 위도 37.5665, 경도 126.9780의 기기 좌표.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    return const DeviceCoordinate(latitude: 37.5665, longitude: 126.9780);
  }

  // 함수이름: openApplicationSettings
  // 함수역할:
  // - 앱 권한 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - true로 완료되는 Future<bool>.
  @override
  Future<bool> openApplicationSettings() async => true;

  // 함수이름: openDeviceLocationSettings
  // 함수역할:
  // - 기기 위치 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - true로 완료되는 Future<bool>.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

// 함수이름: main
// 함수역할:
// - 근처 약국 위치 요청과 외부 앱 실행 주소 검증 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 위치 좌표, 영업 시각과 검색 반경을 약국 요청에 전달하고 결과를 해석하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('requestNearbyPharmacies sends coordinates and decodes items', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 좌표·영업 검색 모드·시각·반경을 검사하고 운영 중 약국의 상세 필드를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 거리·영업시간·출처 시각이 있는 약국 HTTP 200 응답.
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/pharmacy/nearby');
      expect(request.url.queryParameters['latitude'], '37.5665000');
      expect(request.url.queryParameters['longitude'], '126.9780000');
      expect(request.url.queryParameters['search_mode'], 'open_at_time');
      expect(request.url.queryParameters['target_datetime'], isNotEmpty);
      expect(request.url.queryParameters['max_distance_km'], '20.0');
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
              'minutes_until_close': 35,
              'next_open_at': null,
              'source_updated_at': '2026-08-23T01:00:00+00:00',
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
    expect(result.single.minutesUntilClose, 35);
    expect(result.single.sourceUpdatedAt, DateTime.utc(2026, 8, 23, 1));
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 전화와 길찾기가 검증된 외부 URI를 사용하고 잘못된 전화번호를 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('phone and directions use validated external URIs', () async {
    final launchedUris = <Uri>[];
    final control = CheckNearbyPharmacy(
      locationBoundary: _FakeLocationBoundary(),
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
      // 매개변수:
      // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
      // 반환값:
      // - HTTP 200 응답 Future.
      client: MockClient((_) async => http.Response('{}', 200)),
      // 함수이름: uriLauncher 콜백
      // 함수역할:
      // - 외부 실행 URI를 기록하고 실제 앱 실행 없이 성공을 제공한다.
      // 매개변수:
      // - uri (Uri): 실행기에 전달한 검증 대상 외부 주소.
      // 반환값:
      // - true로 완료되는 Future<bool>.
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
    expect(launchedUris.last.scheme, 'geo');
    expect(launchedUris.last.path, '37.5666000,126.9781000');
    expect(
      launchedUris.last.queryParameters['q'],
      '37.5666000,126.9781000(메드버디약국)',
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: directions fall back to coordinate-based web directions.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('directions fall back to coordinate-based web directions', () async {
    Uri? launchedUri;
    final control = CheckNearbyPharmacy(
      locationBoundary: _FakeLocationBoundary(),
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
      // 매개변수:
      // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
      // 반환값:
      // - HTTP 200 응답 Future.
      client: MockClient((_) async => http.Response('{}', 200)),
      // Function Name: uriLauncher callback
      // Description:
      // - Record the attempted URI and accept only HTTPS to force web-direction fallback.
      // Parameters:
      // - uri (Uri): Validated external destination passed to the launcher.
      // Returns:
      // - True for HTTPS, false for native-app URI schemes.
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
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 외부 앱 실행 예외를 화면에서 처리 가능한 실패 값으로 변환하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('external launcher errors are converted to a safe failure', () async {
    final control = CheckNearbyPharmacy(
      locationBoundary: _FakeLocationBoundary(),
      // 함수이름: MockClient 콜백
      // 함수역할:
      // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
      // 매개변수:
      // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
      // 반환값:
      // - HTTP 200 응답 Future.
      client: MockClient((_) async => http.Response('{}', 200)),
      // 함수이름: uriLauncher 콜백
      // 함수역할:
      // - 외부 실행 앱이 없는 상황을 동기 예외로 재현한다.
      // 매개변수:
      // - _ (Uri): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
      // 반환값:
      // - 외부 앱 부재를 나타내는 StateError.
      uriLauncher: (_) => throw StateError('No external application'),
    );
    const pharmacy = NearbyPharmacy(
      pharmacyId: 'C1234',
      name: '메드버디약국',
      address: '서울특별시',
      telephone: '02-123-4567',
      latitude: 37.5666,
      longitude: 126.9781,
      distanceKm: 0.42,
      todayOpenTime: null,
      todayCloseTime: null,
      isOpenNow: null,
      is24Hours: false,
    );

    expect(await control.requestDirections(pharmacy), isFalse);
  });
}
