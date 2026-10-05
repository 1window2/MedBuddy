// 병원 검색의 진료과목 조건을 공통 위치·지도 조회 흐름에 연결한다.
import '../services/api_config.dart';
import '../entities/nearby_care_entity.dart';
import 'check_nearby_care_control.dart';

class CheckNearbyHospital extends CheckNearbyCare {
  static const defaultRadiusKm = .3;
  static const _expandedRadiiKm = [.5, 1.0, 2.0];
  String? department;
  int _searchGeneration = 0;
  bool _disposed = false;

  CheckNearbyHospital({
    this.department,
    super.locationBoundary,
    super.client,
    super.uriLauncher,
    super.clipboardWriter,
  });

  @override
  String get nearbySearchUrl => ApiConfig.hospitalUrl('/nearby');

  // 전체 진료과목은 조건을 보내지 않고, 선택한 과목만 서버에서 필터링한다.
  @override
  Map<String, String> get additionalSearchParameters => {
    if (department != null && department!.isNotEmpty) 'department': department!,
  };

  // Function Name: requestSearchArea
  // Description: Applies the hospital radius even when a caller requests only GPS/fallback scope.
  // Parameters: radiusKm: explicit override or the hospital's existing 300 m default.
  // Returns: A shared search area with preserved device/fallback provenance.
  @override
  Future<NearbyCareSearchArea> requestSearchArea({
    double radiusKm = defaultRadiusKm,
  }) => super.requestSearchArea(radiusKm: radiusKm);

  // 빈 위치 검색만 같은 중심·날짜·조건으로 넓힌다. 수동 지도 범위는 변경하지 않는다.
  @override
  Future<NearbyCareSearchResult> requestNearbyCareSearch({
    NearbyCareSearchMode searchMode = NearbyCareSearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = defaultRadiusKm,
    NearbyCareSearchArea? searchArea,
  }) async {
    if (_disposed) throw StateError('Hospital search is disposed.');
    final generation = ++_searchGeneration;
    final selectedDepartment = department;
    final target = targetDateTime ?? DateTime.now();
    final elapsed = Stopwatch()..start();
    var result = await super.requestNearbyCareSearch(
      searchArea: searchArea,
      maxDistanceKm: maxDistanceKm,
      searchMode: searchMode,
      targetDateTime: target,
    );
    for (final radius in _expandedRadiiKm) {
      final area = result.searchArea;
      if (_disposed ||
          generation != _searchGeneration ||
          department != selectedDepartment ||
          result.data.isNotEmpty ||
          area == null ||
          area.isMapArea ||
          elapsed.elapsed >= const Duration(seconds: 20)) {
        break;
      }
      // 달력 장애나 평일의 주말 조건은 거리를 넓혀도 해결되지 않는다.
      if ((result.holidayScheduleStatus == 'unknown' &&
              searchMode != NearbyCareSearchMode.all) ||
          (searchMode == NearbyCareSearchMode.weekendHoliday &&
              target.weekday < DateTime.saturday &&
              result.holidayScheduleStatus == 'not_applicable')) {
        break;
      }
      if (radius <= area.radiusKm) continue;
      result = await super.requestNearbyCareSearch(
        searchArea: NearbyCareSearchArea(
          center: area.center,
          radiusKm: radius,
          isFallback: area.isFallback,
        ),
        searchMode: searchMode,
        targetDateTime: target,
      );
    }
    return result;
  }

  // 화면을 닫은 뒤 완료된 응답이 추가 반경 조회를 시작하지 않게 한다.
  @override
  void dispose() {
    _disposed = true;
    _searchGeneration++;
    super.dispose();
  }
}
