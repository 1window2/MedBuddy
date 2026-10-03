import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/services/recent_device_coordinate_cache.dart';

void main() {
  test('reuses only a fix younger than 30 seconds without extending its age', () {
    var now = DateTime(2026, 9, 11, 12);
    final cache = RecentDeviceCoordinateCache(now: () => now);
    const coordinate = DeviceCoordinate(latitude: 37.5, longitude: 127);
    expect(cache.read(), isNull);
    cache.store(coordinate);
    now = now.add(const Duration(seconds: 29));
    expect(cache.read(), same(coordinate));
    now = now.add(const Duration(seconds: 1));
    expect(cache.read(), isNull);
  });

  test('clock rollback and permission-driven clear invalidate cached fixes', () {
    var now = DateTime(2026, 9, 11, 12);
    final cache = RecentDeviceCoordinateCache(now: () => now);
    const coordinate = DeviceCoordinate(latitude: 37.5, longitude: 127);
    cache.store(coordinate);
    now = now.subtract(const Duration(seconds: 1));
    expect(cache.read(), isNull);
    cache.store(coordinate);
    cache.clear();
    expect(cache.read(), isNull);
  });
}
