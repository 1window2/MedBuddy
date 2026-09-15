import '../entities/nearby_pharmacy_entity.dart';

/// Process-memory-only GPS reuse. Never persists or logs location.
class RecentDeviceCoordinateCache {
  RecentDeviceCoordinateCache({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DeviceCoordinate? _coordinate;
  DateTime? _capturedAt;

  DeviceCoordinate? read() {
    final captured = _capturedAt;
    if (captured == null) return null;
    final age = _now().difference(captured);
    if (age.isNegative || age >= const Duration(seconds: 30)) {
      clear();
      return null;
    }
    return _coordinate;
  }

  void store(DeviceCoordinate coordinate) {
    _coordinate = coordinate;
    _capturedAt = _now();
  }

  void clear() {
    _coordinate = null;
    _capturedAt = null;
  }
}
