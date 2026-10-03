// File Name: check_nearby_care_control.dart
// Role: Shares authenticated nearby-care search, location and external-action ownership.

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../entities/nearby_pharmacy_entity.dart';
import '../services/api_response_parser.dart';
import '../services/authenticated_api_client.dart';
import '../services/device_location_service.dart';
import '../services/pharmacy_external_action_service.dart';

// 함수이름: ExternalUriLauncher
// 함수역할: 약국 외부 동작 서비스의 URI 실행 콜백 계약을 조회 Control에서도 같은 타입으로 사용하게 한다.
// 매개변수:
// - 없음.
// 반환값:
// - PharmacyUriLauncher와 동일한 외부 URI 실행 콜백 타입.
typedef ExternalUriLauncher = PharmacyUriLauncher;

// Class Name: CheckNearbyCare
// Role: Owns shared hospital/pharmacy transport and device operations, not provider policy.
// Responsibilities:
// - Resolve fresh GPS or an explicitly selected map/fallback area.
// - Parse the existing shared display DTO without inventing provider availability.
// - Reject new HTTP work after disposal; close only internally created clients.
// Attributes: location, HTTP and external-action boundaries; client ownership and disposal flags.
abstract class CheckNearbyCare {
  final DeviceLocationBoundary _locationBoundary;
  final http.Client _client;
  final PharmacyExternalActionService _externalActionService;
  final bool _ownsClient;
  bool _disposed = false;

  // Function Name: nearbySearchUrl
  // Description: Selects the sibling control's authenticated search endpoint.
  // Parameters: None.
  // Returns: The pharmacy or hospital URL; no default provider is selected.
  @protected
  String get nearbySearchUrl;

  // Function Name: additionalSearchParameters
  // Description: Supplies provider-specific filters captured before GPS awaits.
  // Parameters: None.
  // Returns: An empty map unless a concrete provider adds filters.
  @protected
  Map<String, String> get additionalSearchParameters => const {};

  // Function Name: CheckNearbyCare
  // Description: Composes replaceable device/HTTP/action boundaries and owns only unprovided clients.
  // Parameters: locationBoundary, client, uriLauncher, clipboardWriter: optional adapters.
  // Returns: Shared operations initialized with fresh-location, not cached-location, search policy.
  CheckNearbyCare({
    DeviceLocationBoundary? locationBoundary,
    http.Client? client,
    ExternalUriLauncher? uriLauncher,
    PharmacyClipboardWriter? clipboardWriter,
  }) : _locationBoundary =
           locationBoundary ??
           GeolocatorDeviceLocationService(reuseRecentFix: false),
       _client = client ?? AuthenticatedApiClient(),
       _externalActionService = PharmacyExternalActionService(
         uriLauncher: uriLauncher,
         clipboardWriter: clipboardWriter,
       ),
       _ownsClient = client == null;

  // Function Name: requestNearbyCareSearch
  // Description: Searches an explicit area or fresh location, preserving fallback provenance and server failures.
  // Parameters: searchMode, targetDateTime, maxDistanceKm, searchArea: filter, time, radius and optional area.
  // Returns: The existing shared display result with catalog/calendar uncertainty unchanged.
  // Note: Pharmacy-named wire/display DTOs remain compatible; provider ownership is independent.
  Future<NearbyPharmacySearchResult> requestNearbyCareSearch({
    PharmacySearchMode searchMode = PharmacySearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
    PharmacySearchArea? searchArea,
  }) async {
    if (_disposed) throw StateError('Nearby care search is disposed.');
    final extraParameters = Map<String, String>.of(additionalSearchParameters);
    final area = searchArea ?? await requestSearchArea(radiusKm: maxDistanceKm);
    // A pending GPS result must not start HTTP after the screen closes.
    if (_disposed) throw StateError('Nearby care search is disposed.');
    if (!area.isValid) throw ArgumentError('Invalid nearby care search area.');
    final coordinate = area.center;
    final effectiveTarget = targetDateTime ?? DateTime.now();
    final uri = Uri.parse(nearbySearchUrl).replace(
      queryParameters: {
        'latitude': coordinate.latitude.toStringAsFixed(7),
        'longitude': coordinate.longitude.toStringAsFixed(7),
        'search_mode': searchMode.apiValue,
        'target_datetime': effectiveTarget.toIso8601String(),
        'limit': '30',
        'max_distance_km': area.radiusKm.toStringAsFixed(1),
        ...extraParameters,
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 25));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Nearby care request failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }
      final decoded = ApiResponseParser.decodeMap(responseBody);
      final rawItems = decoded['data'];
      if (rawItems is! List) {
        throw StateError('Server response did not include nearby care data.');
      }
      final pharmacies = rawItems
          .whereType<Map>()
          .map(
            // 함수이름: map 콜백
            // 함수역할: 주변 약국 응답 항목을 약국 정보 모델로 변환한다.
            // 매개변수:
            // - item (Map): 현재 변환·검사 중인 응답 또는 목록 항목
            // 반환값:
            // - 위치와 영업 정보를 담은 약국 모델.
            (item) => NearbyPharmacy.fromJson(Map<String, dynamic>.from(item)),
          )
          .where(
            /* 함수이름: where 콜백
           * 함수역할: 식별자와 이름이 모두 있는 약국만 검색 결과에 남긴다.
           * 매개변수:
           * - item (NearbyPharmacy): 현재 변환·검사 중인 응답 또는 목록 항목
           * 반환값:
           * - 두 필수 필드가 비어 있지 않으면 true.
           */
            (item) => item.pharmacyId.isNotEmpty && item.name.isNotEmpty,
          )
          .toList(growable: false);
      return NearbyPharmacySearchResult(
        searchArea: area,
        data: pharmacies,
        searchMode: searchMode,
        targetDateTime:
            DateTime.tryParse(decoded['target_datetime']?.toString() ?? '') ??
            effectiveTarget,
        catalogUpdatedAt: DateTime.tryParse(
          decoded['catalog_updated_at']?.toString() ?? '',
        ),
        catalogIsStale: decoded['catalog_is_stale'] == true,
        holidayScheduleStatus:
            decoded['holiday_schedule_status']?.toString() ?? 'not_applicable',
        searchTruncated: decoded['search_truncated'] == true,
        regionScopeUncertain: decoded['region_scope_uncertain'] == true,
      );
    } on DeviceLocationException {
      rethrow;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Nearby care request failed.',
        name: 'CheckNearbyCare',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Nearby care request failed.');
    }
  }

  // 함수이름: requestSearchArea
  // 함수역할: 현재 위치를 시도하고 권한·GPS·시간 초과·잘못된 좌표는 홍익대 기본 지역으로 대체한다.
  // 매개변수: radiusKm: 검색 반경. 반환값: 실제 위치 또는 기본 검색 지역.
  Future<PharmacySearchArea> requestSearchArea({double radiusKm = 20}) async {
    if (_disposed) throw StateError('Nearby care search is disposed.');
    if (!radiusKm.isFinite || radiusKm < 0.1 || radiusKm > 50) {
      throw ArgumentError('Invalid pharmacy search radius.');
    }
    try {
      final coordinate = await _locationBoundary
          .requestCurrentCoordinate()
          .timeout(const Duration(seconds: 16));
      final area = PharmacySearchArea(center: coordinate, radiusKm: radiusKm);
      if (!_disposed && area.isValid) return area;
    } catch (_) {
      // 위치 실패만 대체한다. 약국 API 실패를 정상 검색 결과로 숨기지 않는다.
    }
    if (_disposed) throw StateError('Nearby care search is disposed.');
    return PharmacySearchArea(
      center: PharmacySearchArea.hongik.center,
      radiusKm: radiusKm,
      isFallback: true,
    );
  }

  // 함수이름: requestPhoneCall
  // 함수역할: 약국 전화번호를 외부 동작 서비스에 전달해 전화 앱 실행을 요청한다.
  // 매개변수:
  // - telephone (String): 약국 전화번호 원문
  // 반환값:
  // - Future<bool>: 약국 전화번호를 외부 동작 서비스에 전달해 전화 앱 실행을 요청한다.
  Future<bool> requestPhoneCall(String telephone) async {
    return _externalActionService.requestPhoneCall(telephone);
  }

  // 함수이름: requestDirections
  // 함수역할: 약국명과 주소를 목적지로 지정한 외부 지도 길찾기를 실행한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 전화·주소·길찾기 대상 약국
  // 반환값:
  // - Future<bool>: 약국명과 주소를 목적지로 지정한 외부 지도 길찾기를 실행한다.
  Future<bool> requestDirections(NearbyPharmacy pharmacy) async {
    return _externalActionService.requestDirections(
      name: pharmacy.name,
      address: pharmacy.address,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수이름: requestInstalledMapDirections
  // 함수역할: 사용자가 설치한 지도 앱 중 하나를 선택해 약국 길찾기를 시작한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 전화·주소·길찾기 대상 약국
  // 반환값:
  // - Future<bool>: 사용자가 설치한 지도 앱 중 하나를 선택해 약국 길찾기를 시작한다.
  Future<bool> requestInstalledMapDirections(NearbyPharmacy pharmacy) {
    return _externalActionService.requestInstalledMapDirections(
      name: pharmacy.name,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수이름: requestGoogleMapDirections
  // 함수역할: Google 지도 앱 또는 웹 브라우저에서 약국 길찾기를 시작한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 전화·주소·길찾기 대상 약국
  // 반환값:
  // - Future<bool>: Google 지도 앱 또는 웹 브라우저에서 약국 길찾기를 시작한다.
  Future<bool> requestGoogleMapDirections(NearbyPharmacy pharmacy) {
    return _externalActionService.requestGoogleMapDirections(
      name: pharmacy.name,
      address: pharmacy.address,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수이름: copyPharmacyAddress
  // 함수역할: 지도 앱을 열 수 없는 상황에 대비해 약국 주소를 복사한다.
  // 매개변수:
  // - address (String): 복사하거나 표시할 약국 주소
  // 반환값:
  // - Future<bool>: 지도 앱을 열 수 없는 상황에 대비해 약국 주소를 복사한다.
  Future<bool> copyPharmacyAddress(String address) {
    return _externalActionService.copyAddress(address);
  }

  // 함수이름: requestMapAttribution
  // 함수역할: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 연다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 연다.
  Future<bool> requestMapAttribution() {
    return _externalActionService.requestMapAttribution();
  }

  // 함수이름: openApplicationSettings
  // 함수역할: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면을 연다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면을 연다.
  Future<bool> openApplicationSettings() =>
      _locationBoundary.openApplicationSettings();

  // 함수이름: openDeviceLocationSettings
  // 함수역할: 기기 위치 서비스 활성화를 위한 운영체제 설정 화면을 연다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 기기 위치 서비스 활성화를 위한 운영체제 설정 화면을 연다.
  Future<bool> openDeviceLocationSettings() =>
      _locationBoundary.openDeviceLocationSettings();

  // 함수이름: dispose
  // 함수역할: 직접 생성한 HTTP 클라이언트만 닫고 외부에서 주입한 클라이언트의 수명은 호출자에게 맡긴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) {
      _client.close();
    }
  }
}
