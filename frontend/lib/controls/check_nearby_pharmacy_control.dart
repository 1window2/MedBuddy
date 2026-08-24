// 파일명: check_nearby_pharmacy_control.dart
// 역할: 현재 위치 조회, 약국 API 요청, 전화·길찾기 실행을 조정한다.

import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/nearby_pharmacy_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/authenticated_api_client.dart';
import '../services/device_location_service.dart';
import '../services/pharmacy_external_action_service.dart';

typedef ExternalUriLauncher = PharmacyUriLauncher;

// 클래스명: CheckNearbyPharmacy
// 역할: 위치 기반 약국 검색 사용 사례를 프론트엔드에서 수행한다.
// 주요 책임:
// - 기기 위치 경계를 통해 사용자의 현재 좌표를 요청한다.
// - 인증된 MedBuddy 백엔드에서 근처 약국 목록을 가져온다.
// - 전화와 외부 지도 실행을 검증된 URI로 위임한다.
class CheckNearbyPharmacy {
  final DeviceLocationBoundary _locationBoundary;
  final http.Client _client;
  final PharmacyExternalActionService _externalActionService;
  final bool _ownsClient;

  CheckNearbyPharmacy({
    DeviceLocationBoundary? locationBoundary,
    http.Client? client,
    ExternalUriLauncher? uriLauncher,
    PharmacyClipboardWriter? clipboardWriter,
  }) : _locationBoundary =
           locationBoundary ?? GeolocatorDeviceLocationService(),
       _client = client ?? AuthenticatedApiClient(),
       _externalActionService = PharmacyExternalActionService(
         uriLauncher: uriLauncher,
         clipboardWriter: clipboardWriter,
       ),
       _ownsClient = client == null;

  // 함수명: requestNearbyPharmacies
  // 역할:
  // - 현재 위치를 확인하고 최대 20km 안의 약국 목록을 서버에서 조회한다.
  // 반환값:
  // - 영업 중 약국이 먼저 정렬된 NearbyPharmacy 목록
  Future<List<NearbyPharmacy>> requestNearbyPharmacies({
    PharmacySearchMode searchMode = PharmacySearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
  }) async {
    final result = await requestNearbyPharmacySearch(
      searchMode: searchMode,
      targetDateTime: targetDateTime,
      maxDistanceKm: maxDistanceKm,
    );
    return result.data;
  }

  Future<NearbyPharmacySearchResult> requestNearbyPharmacySearch({
    PharmacySearchMode searchMode = PharmacySearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
  }) async {
    final coordinate = await _locationBoundary.requestCurrentCoordinate();
    final effectiveTarget = targetDateTime ?? DateTime.now();
    final uri = Uri.parse(ApiConfig.pharmacyUrl('/nearby')).replace(
      queryParameters: {
        'latitude': coordinate.latitude.toStringAsFixed(7),
        'longitude': coordinate.longitude.toStringAsFixed(7),
        'search_mode': searchMode.apiValue,
        'target_datetime': effectiveTarget.toIso8601String(),
        'limit': '30',
        'max_distance_km': maxDistanceKm.toStringAsFixed(1),
      },
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 25));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Nearby pharmacy request failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }
      final decoded = ApiResponseParser.decodeMap(responseBody);
      final rawItems = decoded['data'];
      if (rawItems is! List) {
        throw StateError('Server response did not include pharmacy data.');
      }
      final pharmacies = rawItems
          .whereType<Map>()
          .map(
            (item) => NearbyPharmacy.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.pharmacyId.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
      return NearbyPharmacySearchResult(
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
      );
    } on DeviceLocationException {
      rethrow;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Nearby pharmacy request failed.',
        name: 'CheckNearbyPharmacy',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Nearby pharmacy request failed.');
    }
  }

  Future<bool> requestPhoneCall(String telephone) async {
    return _externalActionService.requestPhoneCall(telephone);
  }

  // 함수명: requestDirections
  // 역할: 약국명과 주소를 목적지로 지정한 외부 지도 길찾기를 실행한다.
  Future<bool> requestDirections(NearbyPharmacy pharmacy) async {
    return _externalActionService.requestDirections(
      name: pharmacy.name,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수명: requestInstalledMapDirections
  // 역할: 사용자가 설치한 지도 앱 중 하나를 선택해 약국 길찾기를 시작한다.
  Future<bool> requestInstalledMapDirections(NearbyPharmacy pharmacy) {
    return _externalActionService.requestInstalledMapDirections(
      name: pharmacy.name,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수명: requestGoogleMapDirections
  // 역할: Google 지도 앱 또는 웹 브라우저에서 약국 길찾기를 시작한다.
  Future<bool> requestGoogleMapDirections(NearbyPharmacy pharmacy) {
    return _externalActionService.requestGoogleMapDirections(
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // 함수명: copyPharmacyAddress
  // 역할: 지도 앱을 열 수 없는 상황에 대비해 약국 주소를 복사한다.
  Future<bool> copyPharmacyAddress(String address) {
    return _externalActionService.copyAddress(address);
  }

  // 함수명: requestMapAttribution
  // 역할: 앱 내 지도 제공자인 네이버 지도의 안내 페이지를 연다.
  Future<bool> requestMapAttribution() {
    return _externalActionService.requestMapAttribution();
  }

  Future<bool> openApplicationSettings() =>
      _locationBoundary.openApplicationSettings();

  Future<bool> openDeviceLocationSettings() =>
      _locationBoundary.openDeviceLocationSettings();

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
