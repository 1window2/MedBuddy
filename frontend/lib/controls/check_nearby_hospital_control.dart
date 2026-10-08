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

  // 함수이름: isWeekendSearchOnWeekday
  // 함수역할: 공휴일 달력이 평일로 확인한 날짜에 주말·공휴일 조건을 조회했는지 판정한다. 이 경우 반경을 넓혀도 결과가 없으므로 화면은 날짜 변경을 안내한다.
  // 매개변수: searchMode: 조회 조건, targetDateTime: 조회 날짜, holidayScheduleStatus: 서버가 알린 공휴일 달력 상태.
  // 반환값: 세 조건이 모두 맞으면 true.
  static bool isWeekendSearchOnWeekday({
    required NearbyCareSearchMode searchMode,
    required DateTime targetDateTime,
    required String holidayScheduleStatus,
  }) {
    return searchMode == NearbyCareSearchMode.weekendHoliday &&
        targetDateTime.weekday < DateTime.saturday &&
        holidayScheduleStatus ==
            NearbyCareSearchResult.holidayScheduleNotApplicable;
  }

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
    // 화면이 반경을 비교해 추측하지 않도록 자동 확대 여부를 결과에 직접 남긴다.
    var expanded = false;
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
      if ((result.holidayScheduleStatus ==
                  NearbyCareSearchResult.holidayScheduleUnknown &&
              searchMode != NearbyCareSearchMode.all) ||
          isWeekendSearchOnWeekday(
            searchMode: searchMode,
            targetDateTime: target,
            holidayScheduleStatus: result.holidayScheduleStatus,
          )) {
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
      expanded = true;
    }
    return expanded ? result.withSearchRadiusExpanded() : result;
  }

  // 화면을 닫은 뒤 완료된 응답이 추가 반경 조회를 시작하지 않게 한다.
  @override
  void dispose() {
    _disposed = true;
    _searchGeneration++;
    super.dispose();
  }
}
