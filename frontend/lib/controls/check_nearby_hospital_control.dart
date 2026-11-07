// 파일명: check_nearby_hospital_control.dart
// 역할: 진료과 조건과 빈 결과의 반경 확대를 공통 주변 의료기관 검색에 연결한다.
// 병원 검색의 진료과목 조건을 공통 위치·지도 조회 흐름에 연결한다.
import '../services/api_config.dart';
import '../entities/nearby_care_entity.dart';
import 'check_nearby_care_control.dart';

// Class Name: CheckNearbyHospital
// Role: Adds hospital departments and bounded automatic radius expansion to shared nearby search.
// Responsibilities: Keep one search's center/date stable and stop expansion after new queries, disposal, calendar limitations, or results.
// Attributes: department (String?): Selected department; defaultRadiusKm/_expandedRadiiKm: Search radii; _searchGeneration/_disposed: Stale-work guards.
class CheckNearbyHospital extends CheckNearbyCare {
  static const defaultRadiusKm = .3;
  static const _expandedRadiiKm = [.5, 1.0, 2.0];
  String? department;
  int _searchGeneration = 0;
  bool _disposed = false;

  // 함수이름: CheckNearbyHospital
  // 함수역할: 선택한 진료과와 위치·HTTP·외부 열기 의존성을 공통 검색 컨트롤에 연결한다.
  // 매개변수: department (String?): 진료과 필터; locationBoundary/client/uriLauncher/clipboardWriter: 부모 컨트롤에 전달할 선택적 의존성.
  // 반환값: 병원 검색 컨트롤. 생성만으로 위치 권한이나 검색을 요청하지 않는다.
  CheckNearbyHospital({
    this.department,
    super.locationBoundary,
    super.client,
    super.uriLauncher,
    super.clipboardWriter,
  });

  // 함수이름: nearbySearchUrl
  // 함수역할: 공통 주변 검색이 사용할 병원 전용 API 주소를 제공한다.
  // 매개변수: 없음.
  // 반환값: ApiConfig의 /nearby 병원 주소.
  @override
  String get nearbySearchUrl => ApiConfig.hospitalUrl('/nearby');

  // Function Name: isWeekendSearchOnWeekday
  // Description: Identifies weekend/holiday searches on a weekday the server confirms is not a holiday, so radius expansion cannot help.
  // Parameters: searchMode (NearbyCareSearchMode) - filter; targetDateTime (DateTime) - queried date;
  // - holidayScheduleStatus (String): Server holiday-calendar status.
  // Returns: True only for weekendHoliday mode, Monday-Friday, and holidayScheduleNotApplicable.
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
  // 함수이름: additionalSearchParameters
  // 함수역할: 진료과 선택이 비어 있지 않을 때만 서버 필터를 추가한다.
  // 매개변수: 없음.
  // 반환값: department 한 항목 또는 빈 맵. 진료과 문자열을 별도로 trim하지 않는다.
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
  // Function Name: requestNearbyCareSearch
  // Description: Expands empty device-centered searches through configured radii while preserving date/mode; manual map areas and stale searches are not expanded.
  // Parameters: searchMode (NearbyCareSearchMode): Opening-hours filter; targetDateTime (DateTime?): Reference time; maxDistanceKm (double): Initial radius; searchArea (NearbyCareSearchArea?): Explicit scope.
  // Returns: Latest result marked when expanded; disposed calls and underlying lookup failures throw. The 20-second check prevents further expansion, not cancellation of a running request.
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
  // 함수이름: dispose
  // 함수역할: 검색 세대를 변경하고 종료 상태를 표시해 늦은 응답이 추가 반경 조회를 시작하지 못하게 한다.
  // 매개변수: 없음.
  // 반환값: 없음. 부모 컨트롤의 자원 정리를 함께 실행한다.
  @override
  void dispose() {
    _disposed = true;
    _searchGeneration++;
    super.dispose();
  }
}
