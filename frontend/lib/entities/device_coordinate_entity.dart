// File Name: device_coordinate_entity.dart
// Role: Holds a provider-neutral WGS84 value for GPS, maps and nearby care.

// 클래스명: DeviceCoordinate
// 역할: 위치 플러그인과 분리된 WGS84 위도·경도 값이다.
// 주요 책임:
// - 주변 약국 조회와 외부 길찾기에서 동일한 좌표 계약을 사용하게 한다.
// 속성:
// - latitude (double): WGS84 위도(도 단위)
// - longitude (double): WGS84 경도(도 단위)
class DeviceCoordinate {
  final double latitude;
  final double longitude;

  // 함수이름: DeviceCoordinate
  // 함수역할: 기기의 WGS84 위도와 경도를 외부 위치 플러그인에 의존하지 않는 값으로 묶는다.
  // 매개변수:
  // - latitude (double): WGS84 위도(도 단위)
  // - longitude (double): WGS84 경도(도 단위)
  // 반환값:
  // - DeviceCoordinate: 초기화된 인스턴스.
  const DeviceCoordinate({required this.latitude, required this.longitude});
}
