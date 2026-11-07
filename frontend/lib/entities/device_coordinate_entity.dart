// File Name: device_coordinate_entity.dart
// Role: Holds a provider-neutral WGS84 value for GPS, maps and nearby care.

// Class Name: DeviceCoordinate
// Role: Carry provider-neutral WGS84 coordinates.
// Responsibilities: Share latitude and longitude across location lookup, maps and directions.
// Attributes: latitude/longitude (double): WGS84 degrees.
class DeviceCoordinate {
  final double latitude;
  final double longitude;

  // Function Name: DeviceCoordinate
  // Description: Store supplied coordinates without range validation or plugin dependencies.
  // Parameters: latitude/longitude (double): WGS84 degrees.
  // Returns: DeviceCoordinate: coordinate pair.
  const DeviceCoordinate({required this.latitude, required this.longitude});
}
