// File Name: check_nearby_care_control.dart
// Role: Shares authenticated nearby-care search, location and external-action ownership.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../entities/device_coordinate_entity.dart';
import '../entities/nearby_care_entity.dart';
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

// Function Name: nearbyCarePlaceOperatesLate
// Description: Tells whether a place counts as late-operating for list ordering: 24-hour, late hours, or an official late-night pharmacy.
// Parameters: place: result to classify; hospitals: true for hospital results, where the pharmacy designation is ignored.
// Returns: True when any applicable late-operation evidence is present.
bool nearbyCarePlaceOperatesLate(
  NearbyCarePlace place, {
  required bool hospitals,
}) {
  return place.is24Hours ||
      place.isOpenLate ||
      (!hospitals && place.isOfficialLateNight);
}

// Function Name: sortNearbyCarePlaces
// Description: Orders results for the map and list: open now, then late-operating, then favorites, then nearest first.
// Parameters: places: search results, left unmodified; favoriteIds: the user's saved place IDs; hospitals: provider kind.
// Returns: A new list in display order.
List<NearbyCarePlace> sortNearbyCarePlaces(
  Iterable<NearbyCarePlace> places, {
  required Set<String> favoriteIds,
  required bool hospitals,
}) {
  final sorted = List<NearbyCarePlace>.of(places);
  // Function Name: sortNearbyCarePlaces.sort callback
  // Description: Compares open state, late operation, favorite membership and distance, in that order.
  // Parameters: left, right: the two places being ordered.
  // Returns: A negative, zero or positive comparison value.
  sorted.sort((left, right) {
    final leftOpenRank = left.isOpenNow == true ? 0 : 1;
    final rightOpenRank = right.isOpenNow == true ? 0 : 1;
    if (leftOpenRank != rightOpenRank) {
      return leftOpenRank.compareTo(rightOpenRank);
    }
    final leftLateRank = nearbyCarePlaceOperatesLate(left, hospitals: hospitals)
        ? 0
        : 1;
    final rightLateRank =
        nearbyCarePlaceOperatesLate(right, hospitals: hospitals) ? 0 : 1;
    if (leftLateRank != rightLateRank) {
      return leftLateRank.compareTo(rightLateRank);
    }
    final leftFavorite = favoriteIds.contains(left.placeId);
    final rightFavorite = favoriteIds.contains(right.placeId);
    if (leftFavorite != rightFavorite) {
      return leftFavorite ? -1 : 1;
    }
    return left.distanceKm.compareTo(right.distanceKm);
  });
  return sorted;
}

// Class Name: SharedPlaceNotFound
// Role: Reports that a shared place could not be found in fresh recipient-side searches.
// Responsibilities: Preserve the already fetched nearby results when the selected place is unavailable.
// Attributes: nearby: The usable NearbyCareSearchResult from the initial area.
class SharedPlaceNotFound implements Exception {
  // Function Name: SharedPlaceNotFound
  // Description: Attaches nearby results to a missing shared-place exception.
  // Parameters: nearby: Fresh initial-area search results.
  // Returns: An exception carrying those results without repeating the search.
  const SharedPlaceNotFound(this.nearby);

  final NearbyCareSearchResult nearby;
}

// 클래스명: CheckNearbyCare
// 역할: 병원·약국 조회의 위치와 HTTP 및 외부 앱 실행 경계를 공유한다.
// 주요 책임: 명시된 지역 또는 새 위치로 검색하고 원본 응답의 운영 정보 불확실성을 유지하며 종료 후 새 요청을 막는다.
// 속성: 위치·HTTP·외부 동작 의존성, 클라이언트 소유권과 종료 상태; 제공자별 정책은 하위 Control이 결정한다.
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
  // Returns: Shared operations that request a fresh device location for each located search.
  CheckNearbyCare({
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

  // 함수이름: requestNearbyCareSearch
  // 함수역할: 지정 지역 또는 현재 위치로 주변 의료 장소를 조회하고 운영 정보의 불확실성을 그대로 전달한다.
  // 매개변수: searchMode: 조회 조건; targetDateTime: 기준 시각; maxDistanceKm: 위치 조회 반경; searchArea: 명시적 검색 지역.
  // 반환값: 장소 목록과 기준 지역·갱신 정보를 담은 결과; 종료·잘못된 지역·통신·응답 오류는 전파한다.
  Future<NearbyCareSearchResult> requestNearbyCareSearch({
    NearbyCareSearchMode searchMode = NearbyCareSearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
    NearbyCareSearchArea? searchArea,
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

    return ApiResponseParser.guardRequest(
      operation: 'Nearby care request failed',
      logName: 'CheckNearbyCare',
      logMessage: 'Nearby care request failed.',
      request: () async {
        final response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 25));
        final responseBody = ApiResponseParser.requireOkBody(
          'Nearby care request failed',
          response,
        );
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
              (item) =>
                  NearbyCarePlace.fromJson(Map<String, dynamic>.from(item)),
            )
            .where(
              /* 함수이름: where 콜백
             * 함수역할: 식별자와 이름이 모두 있는 약국만 검색 결과에 남긴다.
             * 매개변수:
             * - item (NearbyCarePlace): 현재 변환·검사 중인 응답 또는 목록 항목
             * 반환값:
             * - 두 필수 필드가 비어 있지 않으면 true.
             */
              (item) => item.placeId.isNotEmpty && item.name.isNotEmpty,
            )
            .toList(growable: false);
        return NearbyCareSearchResult(
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
              decoded['holiday_schedule_status']?.toString() ??
              NearbyCareSearchResult.holidayScheduleNotApplicable,
          searchTruncated: decoded['search_truncated'] == true,
          regionScopeUncertain: decoded['region_scope_uncertain'] == true,
        );
      },
    );
  }

  // Function Name: requestSelectedPlaceSearch
  // Description: Finds a shared place by ID in fresh local results, retrying in a 0.3 km area around the shared coordinates if necessary.
  // Parameters: place: Shared ID and coordinate hint, not trusted opening details; targetDateTime: Search time; maxDistanceKm/searchArea: Initial area.
  // Returns: Fresh combined results with distance from the original center; SharedPlaceNotFound retains nearby results if the ID remains absent.
  Future<NearbyCareSearchResult> requestSelectedPlaceSearch({
    required NearbyCarePlace place,
    required DateTime targetDateTime,
    double maxDistanceKm = 20,
    NearbyCareSearchArea? searchArea,
  }) async {
    final area = searchArea ?? await requestSearchArea(radiusKm: maxDistanceKm);
    final nearby = await requestNearbyCareSearch(
      searchArea: area,
      searchMode: NearbyCareSearchMode.all,
      targetDateTime: targetDateTime,
    );
    if (_disposed) throw StateError('Nearby care search is disposed.');
    if (nearby.data.any((item) => item.placeId == place.placeId)) return nearby;
    // 가까운 결과 개수 제한이나 먼 공유 장소 때문에 대상이 빠졌을 때만 추가 조회한다.
    final focused = await requestNearbyCareSearch(
      searchArea: NearbyCareSearchArea(
        center: DeviceCoordinate(
          latitude: place.latitude,
          longitude: place.longitude,
        ),
        radiusKm: .3,
        isMapArea: true,
      ),
      searchMode: NearbyCareSearchMode.all,
      targetDateTime: targetDateTime,
    );
    if (_disposed) throw StateError('Nearby care search is disposed.');
    final selected = focused.data
        .where((item) => item.placeId == place.placeId)
        .firstOrNull;
    if (selected == null) throw SharedPlaceNotFound(nearby);
    final distance =
        Geolocator.distanceBetween(
          area.center.latitude,
          area.center.longitude,
          selected.latitude,
          selected.longitude,
        ) /
        1000;
    return NearbyCareSearchResult(
      searchArea: nearby.searchArea ?? area,
      data: [...nearby.data, selected.withDistanceKm(distance)],
      searchMode: NearbyCareSearchMode.all,
      targetDateTime: nearby.targetDateTime,
      catalogUpdatedAt: nearby.catalogUpdatedAt,
      catalogIsStale: nearby.catalogIsStale || focused.catalogIsStale,
      holidayScheduleStatus:
          nearby.holidayScheduleStatus ==
              NearbyCareSearchResult.holidayScheduleUnknown
          ? nearby.holidayScheduleStatus
          : focused.holidayScheduleStatus,
      searchTruncated: nearby.searchTruncated || focused.searchTruncated,
      regionScopeUncertain:
          nearby.regionScopeUncertain || focused.regionScopeUncertain,
      searchRadiusExpanded: nearby.searchRadiusExpanded,
    );
  }

  // Function Name: requestSearchArea
  // Description: Requests a fresh location and falls back to the configured Hongik-area center on location failure.
  // Parameters: radiusKm: Finite radius from 0.1 to 50 km.
  // Returns: A search area marked as fallback when needed; invalid radius and disposal throw rather than starting a search.
  Future<NearbyCareSearchArea> requestSearchArea({double radiusKm = 20}) async {
    if (_disposed) throw StateError('Nearby care search is disposed.');
    if (!radiusKm.isFinite || radiusKm < 0.1 || radiusKm > 50) {
      throw ArgumentError('Invalid pharmacy search radius.');
    }
    try {
      final coordinate = await _locationBoundary
          .requestCurrentCoordinate()
          .timeout(const Duration(seconds: 16));
      final area = NearbyCareSearchArea(center: coordinate, radiusKm: radiusKm);
      if (!_disposed && area.isValid) return area;
    } catch (_) {
      // 위치 실패만 대체한다. 약국 API 실패를 정상 검색 결과로 숨기지 않는다.
    }
    if (_disposed) throw StateError('Nearby care search is disposed.');
    return NearbyCareSearchArea(
      center: NearbyCareSearchArea.fallbackCenter,
      radiusKm: radiusKm,
      isFallback: true,
    );
  }

  // Function Name: requestPhoneCall
  // Description: Delegates opening the dialer for a care location.
  // Parameters: telephone: Raw telephone number.
  // Returns: The external-action service's launch result.
  Future<bool> requestPhoneCall(String telephone) async {
    return _externalActionService.requestPhoneCall(telephone);
  }

  // Function Name: requestDirections
  // Description: Delegates directions using a care location's name, address and coordinates.
  // Parameters: pharmacy: Shared place DTO used for either care-provider type.
  // Returns: The external-action service's directions result.
  Future<bool> requestDirections(NearbyCarePlace pharmacy) async {
    return _externalActionService.requestDirections(
      name: pharmacy.name,
      address: pharmacy.address,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // Function Name: requestInstalledMapDirections
  // Description: Delegates destination opening through installed map applications.
  // Parameters: pharmacy: Place name and destination coordinates.
  // Returns: The external-action service's launch result.
  Future<bool> requestInstalledMapDirections(NearbyCarePlace pharmacy) {
    return _externalActionService.requestInstalledMapDirections(
      name: pharmacy.name,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // Function Name: requestGoogleMapDirections
  // Description: Delegates Google Maps directions for the selected care location.
  // Parameters: pharmacy: Destination name, address and coordinates.
  // Returns: The external-action service's launch result.
  Future<bool> requestGoogleMapDirections(NearbyCarePlace pharmacy) {
    return _externalActionService.requestGoogleMapDirections(
      name: pharmacy.name,
      address: pharmacy.address,
      latitude: pharmacy.latitude,
      longitude: pharmacy.longitude,
    );
  }

  // Function Name: copyPharmacyAddress
  // Description: Copies a care location's address through the external-action boundary.
  // Parameters: address: Text to place on the clipboard.
  // Returns: The service's copy result.
  Future<bool> copyPharmacyAddress(String address) {
    return _externalActionService.copyAddress(address);
  }

  // Function Name: requestMapAttribution
  // Description: Opens the embedded map provider's attribution page.
  // Parameters: None.
  // Returns: The external-action service's launch result.
  Future<bool> requestMapAttribution() {
    return _externalActionService.requestMapAttribution();
  }

  // Function Name: openApplicationSettings
  // Description: Opens application settings where location permission can be changed.
  // Parameters: None.
  // Returns: The location boundary's settings-launch result.
  Future<bool> openApplicationSettings() =>
      _locationBoundary.openApplicationSettings();

  // Function Name: openDeviceLocationSettings
  // Description: Opens the device location-service settings.
  // Parameters: None.
  // Returns: The location boundary's settings-launch result.
  Future<bool> openDeviceLocationSettings() =>
      _locationBoundary.openDeviceLocationSettings();

  // Function Name: dispose
  // Description: Prevents further searches and closes only a client created by this control.
  // Parameters: None.
  // Returns: None; repeated disposal is ignored and injected clients remain open.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) {
      _client.close();
    }
  }
}
