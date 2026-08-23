// 파일명: device_location_service.dart
// 역할: 기기 위치 권한과 현재 좌표 조회를 외부 플러그인에서 분리한다.

import 'package:geolocator/geolocator.dart';

import '../entities/nearby_pharmacy_entity.dart';

enum DeviceLocationFailure {
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

class DeviceLocationException implements Exception {
  final DeviceLocationFailure failure;

  const DeviceLocationException(this.failure);
}

// 추상 클래스명: DeviceLocationBoundary
// 역할: 약국 조회 Control이 Geolocator 구현을 직접 알지 않게 한다.
abstract interface class DeviceLocationBoundary {
  Future<DeviceCoordinate> requestCurrentCoordinate();

  Future<bool> openApplicationSettings();

  Future<bool> openDeviceLocationSettings();
}

// 클래스명: GeolocatorDeviceLocationService
// 역할: 사용자 동의 후 현재 좌표를 한 번 조회한다.
class GeolocatorDeviceLocationService implements DeviceLocationBoundary {
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        DeviceLocationFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(DeviceLocationFailure.deniedForever);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      throw const DeviceLocationException(DeviceLocationFailure.unavailable);
    }
  }

  @override
  Future<bool> openApplicationSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openDeviceLocationSettings() =>
      Geolocator.openLocationSettings();
}
