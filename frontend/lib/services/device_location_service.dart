// 파일명: device_location_service.dart
// 역할: 기기 위치 권한과 현재 좌표 조회를 외부 플러그인에서 분리한다.

import 'package:geolocator/geolocator.dart';

import '../entities/nearby_pharmacy_entity.dart';
import 'recent_device_coordinate_cache.dart';

// 클래스명: DeviceLocationFailure
// 역할: 위치 서비스 꺼짐·권한 거절·영구 거절·조회 불가 원인을 구분한다.
// 주요 책임:
// - 약국 화면이 권한 변경 또는 위치 서비스 활성화 등 필요한 복구 경로를 선택하게 한다.
enum DeviceLocationFailure {
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

// 클래스명: DeviceLocationException
// 역할: 위치 조회 실패의 분류값을 전달한다.
// 주요 책임:
// - 플러그인 오류에 직접 의존하지 않고 화면에서 복구 안내를 선택할 수 있게 한다.
// 속성:
// - failure (DeviceLocationFailure): 화면 복구 안내를 선택할 실패 분류
class DeviceLocationException implements Exception {
  final DeviceLocationFailure failure;

  // 함수이름: DeviceLocationException
  // 함수역할: 위치 실패 원인을 보존해 약국 조회 호출자에게 전달한다.
  // 매개변수:
  // - failure (DeviceLocationFailure): 화면 복구 안내를 선택할 실패 분류
  // 반환값:
  // - DeviceLocationException: 초기화된 인스턴스.
  const DeviceLocationException(this.failure);
}

// 클래스명: DeviceLocationBoundary
// 역할: 약국 조회가 사용할 현재 좌표 및 설정 이동 계약이다.
// 주요 책임:
// - 구체 위치 플러그인을 감추고 권한·기기 위치 설정 이동을 교체 가능한 경계로 제공한다.
abstract interface class DeviceLocationBoundary {
  // 함수이름: requestCurrentCoordinate
  // 함수역할: 동의와 위치 사용 가능 여부를 확인한 현재 WGS84 좌표 조회 계약을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DeviceCoordinate>: 동의와 위치 사용 가능 여부를 확인한 현재 WGS84 좌표 조회 계약을 제공한다.
  Future<DeviceCoordinate> requestCurrentCoordinate();

  // 함수이름: openApplicationSettings
  // 함수역할: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면 실행을 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면 실행을 요청한다.
  Future<bool> openApplicationSettings();

  // 함수이름: openDeviceLocationSettings
  // 함수역할: 기기 위치 서비스를 켜거나 끌 수 있는 운영체제 설정 화면 실행을 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 기기 위치 서비스를 켜거나 끌 수 있는 운영체제 설정 화면 실행을 요청한다.
  Future<bool> openDeviceLocationSettings();
}

// 클래스명: GeolocatorDeviceLocationService
// 역할: Geolocator를 통해 사용자 동의 후 현재 좌표를 한 번 조회한다.
// 주요 책임:
// - 위치 서비스와 권한 상태를 검사하고 조회를 15초로 제한하며 실패를 공통 위치 오류로 변환한다.
class GeolocatorDeviceLocationService implements DeviceLocationBoundary {
  GeolocatorDeviceLocationService({this.reuseRecentFix = true});

  final bool reuseRecentFix;
  static final _recentFix = RecentDeviceCoordinateCache();
  // 함수이름: requestCurrentCoordinate
  // 함수역할: 위치 서비스·권한을 검사하고 필요한 권한을 요청한 뒤 최대 15초 동안 고정밀 좌표를 조회해 실패 원인을 공통 오류로 변환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DeviceCoordinate>: 위치 서비스·권한을 검사하고 필요한 권한을 요청한 뒤 최대 15초 동안 고정밀 좌표를 조회해 실패 원인을 공통 오류로 변환한다.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _recentFix.clear();
      throw const DeviceLocationException(
        DeviceLocationFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      _recentFix.clear();
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      _recentFix.clear();
      throw const DeviceLocationException(DeviceLocationFailure.deniedForever);
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      _recentFix.clear();
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }

    // Recheck GPS and permission even when a recent coordinate is available.
    final cached = reuseRecentFix ? _recentFix.read() : null;
    if (cached != null) return cached;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final coordinate = DeviceCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (position.accuracy.isFinite && position.accuracy >= 0 &&
          position.accuracy <= 100) {
        _recentFix.store(coordinate);
      } else {
        _recentFix.clear();
      }
      return coordinate;
    } catch (_) {
      _recentFix.clear();
      throw const DeviceLocationException(DeviceLocationFailure.unavailable);
    }
  }

  // 함수이름: openApplicationSettings
  // 함수역할: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면 실행을 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 앱별 위치 권한을 변경할 수 있는 운영체제 설정 화면 실행을 요청한다.
  @override
  Future<bool> openApplicationSettings() => Geolocator.openAppSettings();

  // 함수이름: openDeviceLocationSettings
  // 함수역할: 기기 위치 서비스를 켜거나 끌 수 있는 운영체제 설정 화면 실행을 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 기기 위치 서비스를 켜거나 끌 수 있는 운영체제 설정 화면 실행을 요청한다.
  @override
  Future<bool> openDeviceLocationSettings() =>
      Geolocator.openLocationSettings();
}
