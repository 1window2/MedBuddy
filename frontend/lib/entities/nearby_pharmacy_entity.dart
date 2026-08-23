// 파일명: nearby_pharmacy_entity.dart
// 역할: 현재 위치와 근처 약국 조회 결과를 표현한다.

// 클래스명: DeviceCoordinate
// 역할: 외부 위치 모듈에 종속되지 않는 WGS84 기기 좌표를 보관한다.
class DeviceCoordinate {
  final double latitude;
  final double longitude;

  const DeviceCoordinate({required this.latitude, required this.longitude});
}

// 클래스명: NearbyPharmacy
// 역할: 근처 약국 화면에서 표시할 영업 상태와 위치 정보를 표현한다.
class NearbyPharmacy {
  final String pharmacyId;
  final String name;
  final String address;
  final String telephone;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? todayOpenTime;
  final String? todayCloseTime;
  final bool? isOpenNow;
  final bool is24Hours;

  const NearbyPharmacy({
    required this.pharmacyId,
    required this.name,
    required this.address,
    required this.telephone,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.todayOpenTime,
    required this.todayCloseTime,
    required this.isOpenNow,
    required this.is24Hours,
  });

  factory NearbyPharmacy.fromJson(Map<String, dynamic> json) {
    return NearbyPharmacy(
      pharmacyId: _readString(json['pharmacy_id']),
      name: _readString(json['name']),
      address: _readString(json['address']),
      telephone: _readString(json['telephone']),
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      distanceKm: _readDouble(json['distance_km']),
      todayOpenTime: _readNullableString(json['today_open_time']),
      todayCloseTime: _readNullableString(json['today_close_time']),
      isOpenNow: json['is_open_now'] is bool
          ? json['is_open_now'] as bool
          : null,
      is24Hours: json['is_24_hours'] is bool && json['is_24_hours'] as bool,
    );
  }

  String get distanceLabel {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m';
    }
    return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)}km';
  }

  String get todayHoursLabel {
    if (is24Hours) {
      return '24시간 운영';
    }
    if (todayOpenTime == null || todayCloseTime == null) {
      return '오늘 영업시간 확인 필요';
    }
    return '오늘 $todayOpenTime - $todayCloseTime';
  }

  static String _readString(dynamic value) => value?.toString().trim() ?? '';

  static String? _readNullableString(dynamic value) {
    final normalized = _readString(value);
    return normalized.isEmpty ? null : normalized;
  }

  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
