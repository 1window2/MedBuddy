// 파일명: check_nearby_pharmacy_control.dart
// 역할: 현재 위치 조회, 약국 API 요청, 전화·길찾기 실행을 조정한다.

import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../entities/nearby_pharmacy_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/authenticated_api_client.dart';
import '../services/device_location_service.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

// 클래스명: CheckNearbyPharmacy
// 역할: 위치 기반 약국 검색 사용 사례를 프론트엔드에서 수행한다.
// 주요 책임:
// - 기기 위치 경계를 통해 사용자의 현재 좌표를 요청한다.
// - 인증된 MedBuddy 백엔드에서 근처 약국 목록을 가져온다.
// - 전화와 외부 지도 실행을 검증된 URI로 위임한다.
class CheckNearbyPharmacy {
  final DeviceLocationBoundary _locationBoundary;
  final http.Client _client;
  final ExternalUriLauncher _uriLauncher;
  final bool _ownsClient;

  CheckNearbyPharmacy({
    DeviceLocationBoundary? locationBoundary,
    http.Client? client,
    ExternalUriLauncher? uriLauncher,
  }) : _locationBoundary =
           locationBoundary ?? GeolocatorDeviceLocationService(),
       _client = client ?? AuthenticatedApiClient(),
       _uriLauncher =
           uriLauncher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication)),
       _ownsClient = client == null;

  // 함수명: requestNearbyPharmacies
  // 역할:
  // - 현재 위치를 확인하고 최대 20km 안의 약국 목록을 서버에서 조회한다.
  // 반환값:
  // - 영업 중 약국이 먼저 정렬된 NearbyPharmacy 목록
  Future<List<NearbyPharmacy>> requestNearbyPharmacies() async {
    final coordinate = await _locationBoundary.requestCurrentCoordinate();
    final uri = Uri.parse(ApiConfig.pharmacyUrl('/nearby')).replace(
      queryParameters: {
        'latitude': coordinate.latitude.toStringAsFixed(7),
        'longitude': coordinate.longitude.toStringAsFixed(7),
        'open_only': 'false',
        'limit': '30',
        'max_distance_km': '20',
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
      return rawItems
          .whereType<Map>()
          .map(
            (item) => NearbyPharmacy.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.pharmacyId.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
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
    final normalized = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) {
      return false;
    }
    return _uriLauncher(Uri(scheme: 'tel', path: normalized));
  }

  // 함수명: requestDirections
  // 역할: 약국명과 주소를 목적지로 지정한 외부 지도 길찾기를 실행한다.
  Future<bool> requestDirections(NearbyPharmacy pharmacy) {
    final normalizedAddress = pharmacy.address.trim();
    final destination = normalizedAddress.isNotEmpty
        ? '${pharmacy.name}, $normalizedAddress'
        : '${pharmacy.latitude},${pharmacy.longitude}';

    return _uriLauncher(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': destination,
      }),
    );
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
