// 파일명: check_nearby_pharmacy_ui_boundary.dart
// 역할: 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유를 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';
import '../controls/find_hospital_department_control.dart';
import '../widgets/medbuddy_search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/medbuddy_page_header.dart';
import 'package:flutter/rendering.dart';

import '../controls/check_nearby_hospital_control.dart';
import '../controls/check_nearby_pharmacy_control.dart';
import '../controls/check_nearby_care_control.dart';
import '../entities/device_coordinate_entity.dart';
import '../entities/json_value_reader.dart';
import '../entities/nearby_care_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/pharmacy_favorite_service.dart';
import '../theme/medbuddy_theme.dart';
import 'nearby_pharmacy_map_widget.dart';
import '../widgets/keep_words_text.dart';

part 'pharmacy_details_sheet.dart';
part 'pharmacy_list_panel.dart';
part 'hospital_department_sheet.dart';
part 'nearby_care_filter_sheet.dart';

// 클래스명: _PharmacyFilter
// 역할: 시설 검색의 운영시간 조건.
// 주요 책임: 현재 영업·저녁 운영·주말공휴일·전체 조회를 구분한다.
// 속성: openNow/lateHours/weekendHoliday/all: 검색 조건 값.
enum _PharmacyFilter { openNow, lateHours, weekendHoliday, all }

// 클래스명: _HospitalSearchWarning
// 역할: 일시 표시할 병원 검색 범위 경고 종류.
// 주요 책임: 일부 결과만 조회된 상태와 넓은 검색 반경을 구분한다.
// 속성: partialResults/wideArea: 경고 값.
enum _HospitalSearchWarning { partialResults, wideArea }

// 클래스명: _PharmacyDirectionsChoice
// 역할: 길찾기 또는 주소 전달 방식.
// 주요 책임: 설치 지도 앱·Google 지도·주소 복사 중 선택을 전달한다.
// 속성: installedMapApp/googleMaps/copyAddress: 이동 방식 값.
enum _PharmacyDirectionsChoice { installedMapApp, googleMaps, copyAddress }

const _refreshCooldownDuration = Duration(seconds: 10);
const _mapDistanceGuideDuration = Duration(seconds: 4);
const _hospitalSearchWarningDuration = Duration(seconds: 5);
const _hospitalSearchGuidePreference = 'medbuddy.hospital_search_guide_v1';
const _hospitalWideSearchRadiusKm = 3.0;

// 국립중앙의료원 진료과목 코드를 검색 요청과 표시 문구에 함께 사용한다.
const _hospitalDepartments = <String, (String, String)>{
  '': ('전체', 'All'),
  'D001': ('내과', 'Internal medicine'),
  'D013': ('이비인후과', 'ENT'),
  'D002': ('소아청소년과', 'Pediatrics'),
  'D008': ('정형외과', 'Orthopedics'),
  'D005': ('피부과', 'Dermatology'),
  'D026': ('치과', 'Dentistry'),
  'D012': ('안과', 'Ophthalmology'),
  'D011': ('산부인과', 'Obstetrics and gynecology'),
  'D022': ('가정의학과', 'Family medicine'),
  'D003': ('신경과', 'Neurology'),
  'D004': ('정신건강의학과', 'Psychiatry'),
  'D006': ('외과', 'Surgery'),
  'D007': ('흉부외과', 'Thoracic surgery'),
  'D009': ('신경외과', 'Neurosurgery'),
  'D010': ('성형외과', 'Plastic surgery'),
  'D014': ('비뇨기과', 'Urology'),
  'D016': ('재활의학과', 'Rehabilitation medicine'),
  'D017': ('마취통증의학과', 'Anesthesiology and pain medicine'),
  'D018': ('영상의학과', 'Radiology'),
  'D019': ('방사선종양학과', 'Radiation oncology'),
  'D020': ('진단검사의학과', 'Laboratory medicine'),
  'D021': ('병리과', 'Pathology'),
  'D023': ('핵의학과', 'Nuclear medicine'),
  'D024': ('응급의학과', 'Emergency medicine'),
  'D034': ('구강악안면외과', 'Oral and maxillofacial surgery'),
};

// 타입명: NearbyPharmacyMapBuilder
// 역할: 지도 구현을 화면의 목록·필터 로직과 분리하고 테스트 대체 지점을 제공한다.
// 함수이름: NearbyPharmacyMapBuilder
// 함수역할: 약국 목록·선택 상태·지도 동작과 오류 문구를 전달받아 대체 지도를 구성하는 콜백 계약이다.
// 매개변수:
// - pharmacies (List<NearbyCarePlace>): 지도 또는 목록에 배치할 약국 검색 결과.
// - selectedPharmacyId (String?): 공유하거나 지도에서 선택한 약국 ID.
// - onPharmacySelected (ValueChanged<NearbyCarePlace>): 목록·마커에서 선택한 약국을 전달할 콜백.
// - onAttributionRequested (VoidCallback): 지도 데이터의 출처·저작권 안내를 여는 콜백.
// - statusText (String?): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - selectMarkerHint (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - zoomInTooltip (String): 지도 확대 명령의 도움말.
// - zoomOutTooltip (String): 지도 축소 명령의 도움말.
// - configurationUnavailableText (String): 현재 빌드에 지도 설정이 없을 때의 안내.
// - unavailableText (String): 지도 또는 관련 정보를 표시할 수 없을 때의 안내.
// 반환값: 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유에 쓰는 위젯 트리.
typedef NearbyPharmacyMapBuilder =
    Widget Function({
      required NearbyCareSearchArea searchArea,
      required int centerRevision,
      required bool isSearching,
      required Future<bool> Function(NearbyCareSearchArea)
      onSearchAreaRequested,
      required VoidCallback onCurrentLocationRequested,
      required List<NearbyCarePlace> pharmacies,
      required String? selectedPharmacyId,
      required ValueChanged<NearbyCarePlace> onPharmacySelected,
      required VoidCallback onAttributionRequested,
      required String? statusText,
      required String selectMarkerHint,
      required String zoomInTooltip,
      required String zoomOutTooltip,
      required String configurationUnavailableText,
      required String unavailableText,
    });

// 클래스명: CheckNearbyPharmacyUI
// 역할: 위치 권한·조회 조건에 따른 약국 목록과 지도를 담당한다.
// 주요 책임:
// - 위치 권한, 로딩, 빈 결과, 오류 상태를 구분해 안내한다.
// - 영업 중 약국 필터와 새로고침을 제공한다.
// - 약국별 전화 및 외부 지도 길찾기 요청을 Control에 전달한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - control (CheckNearbyCare?): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
// - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
// - selectionMode (bool): 일반 검색(false) 또는 약국·전화 확인 여부를 반환하는 채팅 공유 선택(true) 모드.
class CheckNearbyPharmacyUI extends StatefulWidget {
  final UserSetting userSetting;
  final CheckNearbyCare? control;
  final NearbyPharmacyMapBuilder? mapBuilder;
  final PharmacyFavoriteService? favoriteService;
  final bool selectionMode;
  final bool hospitals;
  final DateTime Function()? clock;
  // 채팅에서 받은 장소는 최초 조회 후 선택할 ID와 검색 좌표로만 사용한다.
  final NearbyCarePlace? initialPlace;

  // 함수이름: CheckNearbyPharmacyUI
  // 함수역할: 주입된 검색·지도·즐겨찾기 의존성으로 일반 병원·약국 검색 화면을 구성하고 선택 모드는 끈다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (CheckNearbyCare?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
  // - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
  // - clock (DateTime Function()?): 검색 날짜와 결과 갱신 판단의 기준 시계. 생략하면 기기 현재 시각을 사용한다.
  // - hospitals (bool): true이면 병원 검색·문구·즐겨찾기를 사용하며 기본값 false는 약국 모드이다.
  // - initialPlace (NearbyCarePlace?): 공유 장소를 다시 열 때 사용할 검색 좌표와 선택 ID. 저장된 상세를 바로 표시하지 않고 최신 조회 결과를 사용한다.
  // 반환값: 입력 설정이 반영된 CheckNearbyPharmacyUI 인스턴스.
  const CheckNearbyPharmacyUI({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
    this.clock,
    this.hospitals = false,
    this.initialPlace,
  }) : selectionMode = false;

  // 함수이름: CheckNearbyPharmacyUI.selection
  // 함수역할: 시설과 전화 확인 여부를 채팅 공유 호출자에게 반환하도록 선택 모드를 켠 병원·약국 검색 화면을 구성한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (CheckNearbyCare?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
  // - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
  // - clock (DateTime Function()?): 검색 날짜와 결과 갱신 판단의 기준 시계. 생략하면 기기 현재 시각을 사용한다.
  // - hospitals (bool): 병원 선택 여부. 기본값 false는 약국 선택이며 초기 공유 장소는 사용하지 않는다.
  // 반환값: 입력 설정이 반영된 CheckNearbyPharmacyUI 인스턴스.
  const CheckNearbyPharmacyUI.selection({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
    this.clock,
    this.hospitals = false,
  }) : selectionMode = true,
       initialPlace = null;

  // 함수이름: createState
  // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _CheckNearbyPharmacyUIState 인스턴스.
  @override
  State<CheckNearbyPharmacyUI> createState() => _CheckNearbyPharmacyUIState();
}

// 클래스명: _CheckNearbyPharmacyUIState
// 역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 화면 상태를 관리한다.
// 주요 책임:
// - 현재 검색 조건으로 약국을 조회하고 선택 유지 여부·위치 오류·조회 시각을 갱신한다.
// - 진행 중·대기 제한을 확인한 뒤 현재 영업 조건의 기준 시각을 갱신해 재조회한다.
// - 24시간 운영·늦은 영업·공식 심야 지정 중 하나라도 해당하는지 확인한다.
// 속성:
// - _control (CheckNearbyPharmacy): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - _favoriteService (PharmacyFavoriteService): 사용자별 약국 즐겨찾기 저장소.
// - _pharmacies (List<NearbyCarePlace>): 지도 또는 목록에 배치할 약국 검색 결과.
// - _isLoading (bool): 진행 중 표시를 보여줄지 여부.
class _CheckNearbyPharmacyUIState extends State<CheckNearbyPharmacyUI>
    with WidgetsBindingObserver {
  late final CheckNearbyCare _control;
  late final bool _ownsControl;
  late final PharmacyFavoriteService _favoriteService;
  late final NearbyCarePlace? _initialPlace;
  bool _initialPlaceResolved = false;
  List<NearbyCarePlace> _pharmacies = const [];
  Set<String> _favoritePharmacyIds = const {};
  bool _favoritesLoaded = false;
  bool _isSavingFavorite = false;
  DeviceCoordinate? _deviceLocation;
  String? _errorMessage;
  bool _isLoading = true;
  bool _listExpanded = false;
  // 정보창 높이는 지도 영역만 다시 그리도록 setState 없이 알린다.
  final _detailExtent = ValueNotifier<double>(
    _PharmacyDetailsSheet.initialExtent,
  );
  // 정렬 결과는 원본 목록과 즐겨찾기 집합이 교체될 때만 다시 계산한다.
  List<NearbyCarePlace>? _sortedPharmacies;
  List<NearbyCarePlace>? _sortedFromPharmacies;
  Set<String>? _sortedFromFavorites;
  bool _isRefreshCoolingDown = false;
  Timer? _refreshCooldownTimer;
  Timer? _mapDistanceGuideTimer;
  Timer? _hospitalSearchWarningTimer;
  _HospitalSearchWarning? _lastHospitalSearchWarning;
  bool _showHospitalSearchWarning = false;
  bool _hasShownMapDistanceGuide = false;
  bool _showMapDistanceGuide = false;
  bool _showHospitalFirstGuide = false;
  bool _hasSelectedHospitalDepartment = false;
  _PharmacyFilter _filter = _PharmacyFilter.openNow;
  String? _selectedPharmacyId;
  DateTime _targetDateTime = DateTime.now();
  bool _hasSelectedSearchDate = false;

  // Function Name: _now
  // Description: Reads the injected search clock or falls back to the device clock.
  // Parameters: None.
  // Returns: Current DateTime used for search freshness and date choices.
  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  bool _catalogIsStale = false;
  bool _searchTruncated = false;
  bool _regionScopeUncertain = false;
  String _holidayScheduleStatus =
      NearbyCareSearchResult.holidayScheduleNotApplicable;
  DateTime? _lastRefreshedAt;
  bool _selectedPhoneVerified = false;
  NearbyCareSearchArea? _searchArea;
  int _searchGeneration = 0;
  int _centerRevision = 0;
  bool _wasBackgrounded = false;
  bool _resumeRefreshPending = false;
  DateTime? _lastSearchStartedAt;

  // 함수이름: _awaitingHospitalDepartment
  // 함수역할: 병원 화면에서 아직 진료과를 명시적으로 선택하지 않았는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 병원 첫 선택을 기다리면 true.
  bool get _awaitingHospitalDepartment =>
      widget.hospitals && !_hasSelectedHospitalDepartment;

  // Function Name: didChangeAppLifecycleState
  // Description: After backgrounding, refreshes a visible search when results are stale, the date changed or an error remains; an active request defers refresh.
  // Parameters: state (AppLifecycleState): new application state.
  // Returns: No return value; department selection and noncurrent routes suppress automatic lookup.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    if (!mounted ||
        _awaitingHospitalDepartment ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final now = _now();
    final previous = _lastSearchStartedAt;
    final stale =
        previous == null ||
        now.isBefore(previous) ||
        now.difference(previous) >= const Duration(minutes: 1) ||
        now.year != previous.year ||
        now.month != previous.month ||
        now.day != previous.day;
    if (!stale && _errorMessage == null) return;
    if (_isLoading) {
      _resumeRefreshPending = true;
    } else {
      unawaited(_loadPharmacies());
    }
  }

  // Function Name: _text
  // Description: Selects pharmacy or hospital copy with the current language and search/calendar uncertainty.
  // Parameters: None.
  // Returns: The appropriate _NearbyPharmacyText provider.
  _NearbyPharmacyText get _text => widget.hospitals
      ? _NearbyHospitalText(
          widget.userSetting.language,
          searchTruncated: _searchTruncated,
          regionScopeUncertain: _regionScopeUncertain,
          calendarUnknown:
              _holidayScheduleStatus ==
              NearbyCareSearchResult.holidayScheduleUnknown,
          requiresWeekendDate: _requiresHospitalHolidayDate,
        )
      // 전체 약국 조건은 영업 여부와 무관하므로 달력 미확인 안내 대상에서 제외한다.
      : _NearbyPharmacyText(
          widget.userSetting.language,
          calendarUnknown:
              _holidayScheduleStatus ==
                  NearbyCareSearchResult.holidayScheduleUnknown &&
              _filter != _PharmacyFilter.all,
        );

  // Function Name: _requiresHospitalHolidayDate
  // Description: Detects a successful hospital weekend search whose selected date is verified as a weekday.
  // Parameters: None.
  // Returns: True when a weekend/holiday date correction should be requested; unknown calendars are not treated as weekdays.
  bool get _requiresHospitalHolidayDate =>
      widget.hospitals &&
      !_isLoading &&
      _errorMessage == null &&
      CheckNearbyHospital.isWeekendSearchOnWeekday(
        searchMode: _searchModeForFilter(_filter),
        targetDateTime: _targetDateTime,
        holidayScheduleStatus: _holidayScheduleStatus,
      );

  // 함수이름: initState
  // 함수역할: 약국 조회·즐겨찾기 의존성을 준비하고 첫 프레임 뒤 두 정보를 불러온다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsControl = widget.control == null;
    _control =
        widget.control ??
        (widget.hospitals ? CheckNearbyHospital() : CheckNearbyPharmacy());
    _initialPlace = widget.initialPlace;
    final initialPlace = _initialPlace;
    _isLoading = initialPlace != null || !widget.hospitals;
    if (initialPlace != null) {
      // 현재 응답을 받기 전에는 공유 당시 상세를 화면에 배치하지 않는다.
      _hasSelectedHospitalDepartment = true;
      _filter = _PharmacyFilter.all;
    }
    _favoriteService =
        widget.favoriteService ??
        PharmacyFavoriteService(
          userHash: widget.userSetting.userHash,
          hospitals: widget.hospitals,
        );
    // 함수이름: initState.addPostFrameCallback callback
    // 함수역할: 현재 사용자의 저장된 약국 즐겨찾기를 화면 선택 집합에 반영한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadFavorites());
      if (initialPlace != null || !widget.hospitals) {
        unawaited(_loadPharmacies());
      }
      if (initialPlace == null && widget.hospitals) {
        unawaited(_loadHospitalFirstGuide());
      }
    });
  }

  // 함수이름: dispose
  // 함수역할: 새로고침·거리 안내 타이머와 _control을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshCooldownTimer?.cancel();
    _mapDistanceGuideTimer?.cancel();
    _hospitalSearchWarningTimer?.cancel();
    _detailExtent.dispose();
    if (_ownsControl) {
      _control.dispose();
    }
    super.dispose();
  }

  // 함수이름: _loadPharmacies
  // 함수역할: 검색 지역과 조건으로 약국을 조회하고 가장 최근 요청의 결과만 반영한다.
  // 매개변수:
  // - searchArea: 지도에서 선택한 지역. locate: 기존 지역 대신 기기 위치를 다시 확인할지 여부.
  // 반환값: 검색 성공 여부. 실패 시 기존 검색 지역을 유지한다.
  Future<bool> _loadPharmacies({
    NearbyCareSearchArea? searchArea,
    bool locate = false,
  }) async {
    if (!mounted || _awaitingHospitalDepartment) {
      return false;
    }
    final generation = ++_searchGeneration;
    _lastSearchStartedAt = _now();
    _resumeRefreshPending = false;
    final requestedArea = searchArea ?? (locate ? null : _searchArea);
    final resolveSharedPlace =
        _initialPlace != null &&
        (!_initialPlaceResolved ||
            _selectedPharmacyId == _initialPlace.placeId) &&
        searchArea == null &&
        !locate &&
        _filter == _PharmacyFilter.all;
    if (searchArea != null || locate) _initialPlaceResolved = true;
    // Only an explicitly chosen calendar date survives a later search.
    if (!_hasSelectedSearchDate) {
      _targetDateTime = _now();
    }
    // 함수이름: _loadPharmacies.setState callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_isLoading = true; _errorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      NearbyCareSearchResult result;
      var sharedPlaceMissing = false;
      try {
        result = resolveSharedPlace
            ? await _control.requestSelectedPlaceSearch(
                place: _initialPlace,
                targetDateTime: _targetDateTime,
                searchArea: requestedArea,
                maxDistanceKm: widget.hospitals
                    ? CheckNearbyHospital.defaultRadiusKm
                    : 20,
              )
            : await _control.requestNearbyCareSearch(
                searchArea: requestedArea,
                // 최초 조회와 내 위치 재검색만 좁힌다. 지도에서 고른 지역은 우선 유지한다.
                maxDistanceKm: widget.hospitals
                    ? CheckNearbyHospital.defaultRadiusKm
                    : 20,
                searchMode: _searchModeForFilter(_filter),
                targetDateTime: _targetDateTime,
              );
      } on SharedPlaceNotFound catch (missing) {
        // 공유된 장소가 지금 목록에 없으면 주변 결과를 보여 주고, 새로고침마다 같은 조회를 되풀이하지 않는다.
        result = missing.nearby;
        sharedPlaceMissing = true;
      }
      if (!mounted || generation != _searchGeneration) {
        return false;
      }
      // 자동 반경 확대 여부는 확대를 수행한 Control이 결과에 알린다.
      final expanded = result.searchRadiusExpanded && result.searchArea != null;
      // 함수이름: _loadPharmacies.setState callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_pharmacies = result.data; _catalogIsStale = result.catalogIsStale; _holidayScheduleStatus = result.holidayScheduleStatus`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _searchArea =
            result.searchArea ??
            requestedArea ??
            NearbyCareSearchArea(
              center: NearbyCareSearchArea.fallbackCenter,
              radiusKm: widget.hospitals
                  ? CheckNearbyHospital.defaultRadiusKm
                  : 20,
              isFallback: true,
            );
        _updateMapDistanceGuide();
        if (!_searchArea!.isFallback && !_searchArea!.isMapArea) {
          _deviceLocation = _searchArea!.center;
        } else if (_searchArea!.isFallback) {
          _deviceLocation = null;
        }
        if (locate || expanded) _centerRevision++;
        if (searchArea != null || locate) {
          _selectedPharmacyId = null;
          _selectedPhoneVerified = false;
        }
        _pharmacies = result.data;
        if (resolveSharedPlace) {
          if (!_initialPlaceResolved) _centerRevision++;
          _initialPlaceResolved = true;
          if (!sharedPlaceMissing) _selectedPharmacyId = _initialPlace.placeId;
        }
        _catalogIsStale = result.catalogIsStale;
        _searchTruncated = result.searchTruncated;
        _regionScopeUncertain = result.regionScopeUncertain;
        _holidayScheduleStatus = result.holidayScheduleStatus;
        _updateHospitalSearchWarning();
        final selectedStillExists = _pharmacies.any(
          // 함수이름: _loadPharmacies.any callback
          // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 대해 `pharmacy.placeId == _selectedPharmacyId` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - pharmacy (콜백 계약에서 추론): 표시하거나 전화·길찾기·공유할 약국.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
          (pharmacy) => pharmacy.placeId == _selectedPharmacyId,
        );
        if (!selectedStillExists) {
          _selectedPharmacyId = null;
          _selectedPhoneVerified = false;
        }
        _lastRefreshedAt = _now();
      });
      if (sharedPlaceMissing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: KeepWordsText(_text.sharedPlaceMissing)),
        );
      }
      if (expanded) {
        final radius = result.searchArea!.radiusKm;
        final distance = radius < 1
            ? '${(radius * 1000).round()}m'
            : '${radius.toStringAsFixed(0)}km';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: KeepWordsText(
              _text.isEnglish
                  ? 'Search expanded to $distance.'
                  : '반경 $distance까지 넓혀 검색했어요.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        // 함수이름: _loadPharmacies.setState callback
        // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_errorMessage = _text.loadFailed`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _errorMessage = _text.loadFailed;
          _hospitalSearchWarningTimer?.cancel();
          _lastHospitalSearchWarning = null;
          _showHospitalSearchWarning = false;
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        // 함수이름: _loadPharmacies.setState callback
        // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_isLoading = false`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _isLoading = false);
        if (_resumeRefreshPending &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            ModalRoute.of(context)?.isCurrent == true) {
          unawaited(_loadPharmacies());
        }
      }
    }
    return false;
  }

  // 함수이름: _updateMapDistanceGuide
  // 함수역할: 검색 성공 상태 갱신 안에서 거리 기준 안내를 화면 진입당 한 번만 시작한다.
  // 매개변수: 없음. 반환값: 없음. 조회 오류·기본 위치 안내는 자동으로 숨기지 않는다.
  void _updateMapDistanceGuide() {
    if (_searchArea?.isMapArea != true) {
      _mapDistanceGuideTimer?.cancel();
      _showMapDistanceGuide = false;
      return;
    }
    if (_hasShownMapDistanceGuide) return;
    _hasShownMapDistanceGuide = true;
    _showMapDistanceGuide = true;
    _mapDistanceGuideTimer = Timer(_mapDistanceGuideDuration, () {
      if (mounted) setState(() => _showMapDistanceGuide = false);
    });
  }

  // 함수이름: _updateHospitalSearchWarning
  // 함수역할: 부분 조회 또는 넓은 반경 경고가 새로 생길 때만 표시 타이머를 시작한다.
  // 매개변수: 없음.
  // 반환값: 없음. 같은 제한으로 재조회해도 경고 시간을 연장하지 않는다.
  void _updateHospitalSearchWarning() {
    final warning = !widget.hospitals
        ? null
        : _searchTruncated
        ? _HospitalSearchWarning.partialResults
        : (_searchArea?.radiusKm ?? 0) >= _hospitalWideSearchRadiusKm
        ? _HospitalSearchWarning.wideArea
        : null;
    if (warning == _lastHospitalSearchWarning) return;
    _hospitalSearchWarningTimer?.cancel();
    _lastHospitalSearchWarning = warning;
    _showHospitalSearchWarning = warning != null;
    if (warning != null) {
      _hospitalSearchWarningTimer = Timer(_hospitalSearchWarningDuration, () {
        if (mounted) setState(() => _showHospitalSearchWarning = false);
      });
    }
  }

  // 함수이름: _loadHospitalFirstGuide
  // 함수역할: 기기에 저장된 최초 병원 안내 확인 여부를 읽는다. 저장소 실패는 안내를 다시 표시하는 쪽으로 처리한다.
  // 매개변수: 없음.
  // 반환값: 조회 완료 Future<void>; 화면이 해제되었으면 갱신하지 않는다.
  Future<void> _loadHospitalFirstGuide() async {
    var seen = false;
    try {
      seen =
          (await SharedPreferences.getInstance()).getBool(
            _hospitalSearchGuidePreference,
          ) ??
          false;
    } catch (_) {
      // 저장소 장애가 검색을 막거나 제한 안내를 숨기지 않게 한다.
    }
    if (mounted) setState(() => _showHospitalFirstGuide = !seen);
  }

  // 함수이름: _acknowledgeHospitalGuide
  // 함수역할: 최초 병원 안내를 닫고 확인 여부를 저장한다. 저장 실패여도 조회 결과는 유지한다.
  // 매개변수: 없음.
  // 반환값: 저장 시도 완료 Future<void>.
  Future<void> _acknowledgeHospitalGuide() async {
    setState(() => _showHospitalFirstGuide = false);
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _hospitalSearchGuidePreference,
        true,
      );
    } catch (_) {
      // 다음 진입에서 안내가 다시 보이더라도 조회 결과는 그대로 유지한다.
    }
  }

  // 함수이름: _buildHospitalSearchNotice
  // 함수역할: 실제 반경·부분 응답 상태에 맞는 병원 안내를 선택하며 오류 중이거나 안내 시간이 끝나면 숨긴다.
  // 매개변수: 없음.
  // 반환값: 검색 안내 위젯 또는 SizedBox.shrink.
  Widget _buildHospitalSearchNotice() {
    final wide = (_searchArea?.radiusKm ?? 0) >= _hospitalWideSearchRadiusKm;
    if (!widget.hospitals ||
        _errorMessage != null ||
        (_searchTruncated || wide
            ? !_showHospitalSearchWarning
            : !_showHospitalFirstGuide)) {
      return const SizedBox.shrink();
    }
    final english = widget.userSetting.isEnglish;
    final message = _searchTruncated
        ? (english
              ? 'Some hospital data is unavailable. Try again.'
              : '일부 병원 정보를 확인하지 못했어요. 다시 검색하거나 조회 조건을 바꿔보세요.')
        : wide
        ? (english
              ? 'This search covers a wide area. Some hospitals may not appear.'
              : '검색 범위가 넓어 일부 병원이 표시되지 않을 수 있어요.')
        : (english
              ? 'Hospital listings and hours may be incomplete or outdated.'
              : '공공데이터에 일부 병원이 누락되거나 진료시간이 실제와 다를 수 있어요.');
    return Padding(
      key: const Key('hospital-search-notice'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: MedBuddyColors.textMuted,
            ),
          ),
          Expanded(
            child: KeepWordsText(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: MedBuddyColors.textMuted,
              ),
            ),
          ),
          if (_showHospitalFirstGuide && !_searchTruncated && !wide)
            IconButton(
              key: const Key('hospital-guide-acknowledge'),
              tooltip: english ? 'Dismiss introduction' : '첫 안내 닫기',
              onPressed: _acknowledgeHospitalGuide,
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }

  // Function Name: _searchMapArea
  // Description: Searches the visible map area under the active opening-hours filter; rejects overlapping loads.
  // Parameters: area (NearbyCareSearchArea): map center and radius.
  // Returns: Future<bool> indicating successful refresh, false if already loading.
  Future<bool> _searchMapArea(NearbyCareSearchArea area) async {
    if (_isLoading) return false;
    return _loadPharmacies(searchArea: area);
  }

  // 함수이름: _searchCurrentLocation
  // 함수역할: 기기 위치를 다시 시도하고 성공한 검색 기준으로 지도를 이동한다. 매개변수: 없음. 반환값: 없음.
  void _searchCurrentLocation() {
    if (!_isLoading) unawaited(_loadPharmacies(locate: true));
  }

  // Function Name: _requestRefresh
  // Description: Checks loading and cooldown limits, refreshes the open-now timestamp, and reloads pharmacies.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _requestRefresh() async {
    if (_isLoading) {
      _showActionMessage(_text.loadingAction);
      return;
    }
    if (_isRefreshCoolingDown) {
      _showActionMessage(_text.refreshLimited);
      return;
    }

    _isRefreshCoolingDown = true;
    _refreshCooldownTimer?.cancel();
    // 함수이름: _requestRefresh.Timer callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_isRefreshCoolingDown = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    _refreshCooldownTimer = Timer(_refreshCooldownDuration, () {
      _isRefreshCoolingDown = false;
    });
    await _loadPharmacies();
  }

  // Function Name: _visiblePharmacies
  // Description: Sorts a copy by opening status, late-night operation, favorites and distance; reuses it while source-list and favorite-set identities are unchanged.
  // Parameters: None.
  // Returns: The cached display list; callers must not mutate it.
  List<NearbyCarePlace> get _visiblePharmacies {
    final cached = _sortedPharmacies;
    // 두 필드는 항상 새 객체로 교체되므로 동일 객체 여부만으로 변경을 알 수 있다.
    if (cached != null &&
        identical(_pharmacies, _sortedFromPharmacies) &&
        identical(_favoritePharmacyIds, _sortedFromFavorites)) {
      return cached;
    }
    _sortedFromPharmacies = _pharmacies;
    _sortedFromFavorites = _favoritePharmacyIds;
    return _sortedPharmacies = sortNearbyCarePlaces(
      _pharmacies,
      favoriteIds: _favoritePharmacyIds,
      hospitals: widget.hospitals,
    );
  }

  // Function Name: _loadFavorites
  // Description: Loads this user's saved place IDs and applies them only while mounted; a failed load leaves favorites unavailable.
  // Parameters: None.
  // Returns: Future completing after the favorites lookup.
  Future<void> _loadFavorites() async {
    try {
      final favoriteIds = await _favoriteService.loadFavoriteIds();
      if (mounted) {
        setState(() {
          _favoritePharmacyIds = favoriteIds;
          _favoritesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) _showActionMessage(_text.favoriteLoadFailed);
    }
  }

  // Function Name: _toggleFavorite
  // Description: Serializes optimistic favorite changes and restores the prior set with feedback if persistence rejects or throws.
  // Parameters: pharmacy (NearbyCarePlace): place to toggle.
  // Returns: Future completing after save or rollback; no action before favorites load.
  Future<void> _toggleFavorite(NearbyCarePlace pharmacy) async {
    if (!_favoritesLoaded || _isSavingFavorite) return;
    final previousIds = _favoritePharmacyIds;
    final updatedIds = Set<String>.of(_favoritePharmacyIds);
    final isFavorite = updatedIds.remove(pharmacy.placeId);
    if (!isFavorite) {
      updatedIds.add(pharmacy.placeId);
    }
    setState(() {
      _favoritePharmacyIds = updatedIds;
      _isSavingFavorite = true;
    });
    var saved = false;
    try {
      saved = await _favoriteService.saveFavoriteIds(updatedIds);
    } catch (_) {
      // 저장소 예외도 저장 거절과 같은 복구 경로로 처리한다.
    }
    if (!mounted) return;
    setState(() {
      if (!saved) _favoritePharmacyIds = previousIds;
      _isSavingFavorite = false;
    });
    if (!saved) _showActionMessage(_text.favoriteSaveFailed);
  }

  // 함수이름: _canChangeFavorite
  // 함수역할: 초기 조회나 저장 도중에는 즐겨찾기 변경을 막아 저장 순서를 보존한다.
  // 매개변수: 없음. 반환값: 즐겨찾기 버튼 활성화 여부.
  bool get _canChangeFavorite => _favoritesLoaded && !_isSavingFavorite;

  // Function Name: _searchModeForFilter
  // Description: Maps the visible operating-hours filter to the pharmacy controller's search mode.
  // Parameters:
  // - filter (_PharmacyFilter): Pharmacy operating-hours filter to apply.
  // Returns: NearbyCareSearchMode: Controller search mode corresponding to the visible filter.
  NearbyCareSearchMode _searchModeForFilter(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow => NearbyCareSearchMode.openAtTime,
      _PharmacyFilter.lateHours => NearbyCareSearchMode.lateHours,
      _PharmacyFilter.weekendHoliday => NearbyCareSearchMode.weekendHoliday,
      _PharmacyFilter.all => NearbyCareSearchMode.all,
    };
  }

  // Function Name: _selectFilter
  // Description: Clears pharmacy selection after changing the search filter and reloads matching results.
  // Parameters:
  // - nextFilter (_PharmacyFilter): Pharmacy operating-hours filter to apply.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _selectFilter(_PharmacyFilter nextFilter) async {
    // Function Name: _selectFilter.setState callback
    // Description: Updates the local input or request state for the pharmacy list and map for location permission and search-filter state: `_filter = nextFilter; _selectedPharmacyId = null; _targetDateTime = DateTime.now()`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _filter = nextFilter;
      _selectedPharmacyId = null;
      // Never label the previous condition's pins as new-filter results.
      _pharmacies = [];
      if (nextFilter == _PharmacyFilter.openNow) {
        _hasSelectedSearchDate = false;
        _targetDateTime = _now();
      }
    });
    await _loadPharmacies();
  }

  // 함수이름: _showDepartmentPicker
  // 함수역할: 병원 검색이 쉬는 동안 진료과 선택창을 열고 명시적 선택만 적용한다.
  // 매개변수: 없음.
  // 반환값: 선택·재조회 완료 Future<void>; 취소·화면 종료는 무시한다.
  Future<void> _showDepartmentPicker() async {
    final control = _control;
    if (control is! CheckNearbyHospital || _isLoading) return;
    final department = control.department ?? '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => _HospitalDepartmentSheet(
        selected: department,
        english: _text.isEnglish,
        closeLabel: _text.close,
      ),
    );
    if (!mounted || selected == null) return;
    await _selectHospitalDepartment(selected);
  }

  // 함수이름: _selectHospitalDepartment
  // 함수역할: 진료과를 명시적으로 확정하고 기존 장소 선택을 비운 뒤 현재 지역·날짜로 다시 조회한다.
  // 매개변수: selected (String): 진료과 코드; 빈 문자열은 전체.
  // 반환값: 조회 완료 Future<void>; 동일 선택·진행 중·해제된 화면은 무시한다.
  Future<void> _selectHospitalDepartment(String selected) async {
    final control = _control;
    if (!mounted || control is! CheckNearbyHospital || _isLoading) return;
    if (_hasSelectedHospitalDepartment &&
        selected == (control.department ?? '')) {
      return;
    }
    setState(() {
      _hasSelectedHospitalDepartment = true;
      control.department = selected.isEmpty ? null : selected;
      _selectedPharmacyId = null;
      _selectedPhoneVerified = false;
      _pharmacies = [];
    });
    await _loadPharmacies();
  }

  // 함수이름: _departmentLabel
  // 함수역할: 진료과 코드를 현재 언어 이름으로 바꾼다.
  // 매개변수: code (String): 진료과 코드.
  // 반환값: 알려진 이름 또는 미등록 코드 원문.
  String _departmentLabel(String code) {
    final label = _hospitalDepartments[code];
    return label == null ? code : (_text.isEnglish ? label.$2 : label.$1);
  }

  // 함수이름: _buildHospitalFilters
  // 함수역할: 진료과와 운영 조건 선택 버튼을 같은 폭으로 나란히 배치한다.
  // 매개변수: map (bool): 지도용 식별 키 사용 여부.
  // 반환값: 가용 폭에 맞는 필터 LayoutBuilder.
  Widget _buildHospitalFilters({required bool map}) {
    final control = _control;
    final department = control is CheckNearbyHospital
        ? control.department ?? ''
        : '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _buildHospitalFilterButton(
                key: Key(
                  map
                      ? 'hospital-map-department-selector'
                      : 'hospital-department-selector',
                ),
                icon: Icons.medical_services_outlined,
                label: _departmentLabel(department),
                tooltip: _text.isEnglish ? 'Specialty' : '진료과목',
                onPressed: _showDepartmentPicker,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildHospitalFilterButton(
                key: Key(
                  map
                      ? 'pharmacy-map-filter-selector'
                      : 'pharmacy-filter-selector',
                ),
                icon: Icons.filter_alt_outlined,
                label: _text.filterPickerTitle,
                tooltip:
                    '${_text.filterPickerTitle}: ${_text.filterDescription(_filter)}',
                onPressed: _showFilterPicker,
              ),
            ),
          ],
        );
      },
    );
  }

  // 함수이름: _buildHospitalFilterButton
  // 함수역할: 필터 라벨을 줄바꿈 가능하게 배치하고 큰 글씨는 아이콘과 문구를 세로로 나눈다.
  // 매개변수: key (Key): 버튼 키; icon (IconData): 아이콘; label/tooltip (String): 문구; onPressed (VoidCallback): 선택 명령.
  // 반환값: 조회 중 비활성화되는 Tooltip 버튼.
  Widget _buildHospitalFilterButton({
    required Key key,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final labelWidget = KeepWordsText(
      label,
      style: const TextStyle(letterSpacing: 0),
    );
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        key: key,
        onPressed: _isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(0, 48),
        ),
        child: largeText
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(icon, size: 20),
                      const Icon(Icons.keyboard_arrow_down, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  labelWidget,
                ],
              )
            : Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: labelWidget),
                ],
              ),
      ),
    );
  }

  // 함수이름: _showFilterPicker
  // 함수역할: 날짜와 운영 조건을 한 번에 선택받고 기존 조건과 다를 때만 적용해 재조회한다.
  // 매개변수: 없음.
  // 반환값: 조회·선택 완료 Future<void>; 취소나 같은 선택은 유지한다.
  Future<void> _showFilterPicker() async {
    if (_isLoading) return;
    final selected = await showModalBottomSheet<_NearbyCareConditions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (_) => _NearbyCareFilterSheet(
        filter: _filter,
        selectedDate: _hasSelectedSearchDate ? _targetDateTime : null,
        now: _now,
        hospitals: widget.hospitals,
        text: _text,
        filterLabel: _filterLabel,
      ),
    );
    if (!mounted || selected == null) return;
    final previousDate = _hasSelectedSearchDate ? _targetDateTime : null;
    if (selected.filter == _filter &&
        DateUtils.isSameDay(selected.date, previousDate)) {
      return;
    }
    setState(() {
      _filter = selected.filter;
      _hasSelectedSearchDate = selected.date != null;
      _targetDateTime = selected.date ?? _now();
      _selectedPharmacyId = null;
      _selectedPhoneVerified = false;
      _pharmacies = [];
    });
    await _loadPharmacies();
  }

  // 함수이름: _filterLabel
  // 함수역할: 약국 검색 조건에 해당하는 현재 언어의 선택 라벨을 찾는다.
  // 매개변수:
  // - filter (_PharmacyFilter): 적용할 약국 영업 조건.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _filterLabel(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow => _text.openFilter,
      _PharmacyFilter.lateHours => _text.lateHours,
      _PharmacyFilter.weekendHoliday => _text.weekendHoliday,
      _PharmacyFilter.all => _text.allPharmacies,
    };
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 위치 권한·조회 조건에 따른 약국 목록과 지도 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_listExpanded && _selectedPharmacyId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildMapFirstBody()),
            ],
          ),
        ),
      ),
    );
  }

  // Function Name: _handleBack
  // Description: Closes the expanded list first, then selected-place details, then the nearby-care screen.
  // Parameters: None.
  // Returns: None.
  void _handleBack() {
    if (_listExpanded) {
      setState(() {
        _listExpanded = false;
        _detailExtent.value = _PharmacyDetailsSheet.initialExtent;
      });
    } else if (_selectedPharmacyId != null) {
      _closePharmacyDetails();
    } else {
      Navigator.pop(context);
    }
  }

  // 함수이름: _closePharmacyDetails
  // 함수역할: 지도 위치는 유지하고 약국 선택과 전화 확인 상태만 해제한다.
  // 매개변수: 없음. 반환값: 없음.
  void _closePharmacyDetails() => setState(() {
    _selectedPharmacyId = null;
    _selectedPhoneVerified = false;
  });

  // 함수이름: _buildHeader
  // 함수역할: 뒤로가기·조회 설명·새로고침을 약국 화면 상단에 배치한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  Widget _buildHeader(BuildContext context) {
    final text = _text;
    return MedBuddyPageHeader(
      title: text.title,
      subtitle: text.subtitle,
      titleMaxLines: 1,
      subtitleMaxLines: 2,
      backTooltip: text.back,
      onBackRequested: _handleBack,
      actions: [
        if (!_awaitingHospitalDepartment)
          IconButton(
            tooltip: text.refreshTooltip,
            onPressed: _requestRefresh,
            icon: const Icon(Icons.refresh),
          ),
      ],
    );
  }

  // Function Name: _buildMapFirstBody
  // Description: Keeps the map visible beneath the list or collapsible details; requests a hospital department first when required.
  // Parameters: None.
  // Returns: The map-first body or department picker.
  Widget _buildMapFirstBody() {
    if (_awaitingHospitalDepartment) {
      return _HospitalDepartmentSheet(
        selected: null,
        english: _text.isEnglish,
        closeLabel: _text.close,
        embedded: true,
        onSelected: (code) => unawaited(_selectHospitalDepartment(code)),
      );
    }
    final pharmacies = _visiblePharmacies;
    final selected = _findSelectedPharmacy(pharmacies);
    if (_searchArea == null) {
      return _buildBody();
    }
    final english = widget.userSetting.isEnglish;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // 큰 글씨에서도 상단 조건을 스크롤해 확인하고 지도 공간을 유지한다.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: widget.hospitals
                    ? constraints.maxHeight * .45
                    : double.infinity,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (widget.selectionMode)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: KeepWordsText(
                          _searchArea!.isFallback
                              ? (english
                                    ? 'Search area: Hongik University, Seoul (location unavailable)'
                                    : '검색 기준: 홍익대학교 서울캠퍼스 (위치 확인 불가)')
                              : _searchArea!.isMapArea
                              ? (english
                                    ? 'Search area: selected map area'
                                    : '검색 기준: 선택한 지도 지역')
                              : (english
                                    ? 'Search area: this device location'
                                    : '검색 기준: 이 기기 위치'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: MedBuddyColors.textMuted,
                          ),
                        ),
                      ),
                    if (_searchArea!.isFallback ||
                        (_searchArea!.isMapArea && _showMapDistanceGuide) ||
                        _errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        child: KeepWordsText(
                          _errorMessage != null
                              ? (english
                                    ? 'Search failed. Move the map to try again, or refresh.'
                                    : '검색하지 못했어요. 지도를 옮겨 다시 검색하거나 새로고침해주세요.')
                              : _searchArea!.isFallback
                              ? (english
                                    ? (widget.hospitals
                                          ? 'Location unavailable. Near Hongik University, Seoul.'
                                          : 'Location unavailable. Searching near Hongik University, Seoul.')
                                    : '위치를 확인하지 못해 홍익대학교 서울캠퍼스 기준으로 검색했어요.')
                              : (english
                                    ? 'Distances are measured from the searched map center.'
                                    : '거리는 검색한 지도 중심을 기준으로 표시해요.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            letterSpacing: 0,
                            color: MedBuddyColors.textMuted,
                          ),
                        ),
                      ),
                    if (!_listExpanded && widget.hospitals)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: _buildHospitalFilters(map: true),
                      ),
                    if (!_listExpanded && !widget.hospitals)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Center(
                          child: Tooltip(
                            message: _text.selectedFilter(
                              _filterLabel(_filter),
                            ),
                            child: OutlinedButton.icon(
                              key: const Key('pharmacy-map-filter-selector'),
                              onPressed: _isLoading ? null : _showFilterPicker,
                              icon: const Icon(Icons.filter_alt_outlined),
                              label: KeepWordsText(_text.filterPickerTitle),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showDetails = !_listExpanded && selected != null;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ExcludeSemantics(
                          excluding: _listExpanded || _isLoading,
                          child: IgnorePointer(
                            ignoring: _listExpanded || _isLoading,
                            // 정보창을 드래그하는 동안에는 이 지도 영역만 다시 빌드한다.
                            child: ValueListenableBuilder<double>(
                              valueListenable: _detailExtent,
                              builder: (context, detailExtent, _) {
                                final bottomInset = showDetails
                                    ? constraints.maxHeight *
                                          detailExtent.clamp(0.0, .92)
                                    : 0.0;
                                return _buildPharmacyMap(
                                  pharmacies,
                                  bottomInset: bottomInset,
                                  showControls:
                                      constraints.maxHeight - bottomInset >=
                                      128,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (showDetails)
                        _PharmacyDetailsSheet(
                          key: ValueKey(
                            'pharmacy-sheet-${selected.placeId}-$_centerRevision',
                          ),
                          isEnglish: english,
                          hospitals: widget.hospitals,
                          onExtentChanged: (extent) {
                            if ((_detailExtent.value - extent).abs() > .001) {
                              _detailExtent.value = extent;
                            }
                          },
                          contentBuilder: (context, compact) => Column(
                            children: [
                              _PharmacyCard(
                                pharmacy: selected,
                                text: _text,
                                usesSelectedTime:
                                    _filter != _PharmacyFilter.openNow,
                                isSelected: true,
                                isFavorite: _favoritePharmacyIds.contains(
                                  selected.placeId,
                                ),
                                embedded: true,
                                compact: compact,
                                onClose: _closePharmacyDetails,
                                onSelected: () => _selectPharmacy(selected),
                                onFavoriteRequested: _canChangeFavorite
                                    ? () => _toggleFavorite(selected)
                                    : null,
                                onPhoneRequested: selected.telephone.isEmpty
                                    ? null
                                    : () => _requestPhoneCall(selected),
                                onDirectionsRequested: () =>
                                    _requestDirections(selected),
                              ),
                              if (widget.selectionMode)
                                _buildSelectionFooter(
                                  pharmacies,
                                  embedded: true,
                                ),
                            ],
                          ),
                        ),
                      if (_listExpanded)
                        Positioned.fill(
                          top: 12,
                          child: _PharmacyListPanel(
                            header: _buildListStatus(),
                            showMapLabel: english ? 'Show map' : '지도 크게 보기',
                            onDismissed: _handleBack,
                            child: _buildBody(showStatus: false),
                          ),
                        ),
                      if (_isLoading)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            color: MedBuddyColors.primary,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            _buildHospitalSearchNotice(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('pharmacy-list-toggle'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                          _listExpanded = !_listExpanded;
                          _detailExtent.value =
                              _PharmacyDetailsSheet.initialExtent;
                        }),
                  icon: Icon(
                    _listExpanded ? Icons.map_outlined : Icons.list_alt,
                  ),
                  label: KeepWordsText(
                    _listExpanded
                        ? (english ? 'Show map' : '지도 크게 보기')
                        : _text.showList(pharmacies.length),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 함수이름: _buildListStatus
  // 함수역할: 조회 시각과 전화 확인 안내를 배치하고 큰 글씨에서는 줄을 나눈다.
  // 매개변수: 없음. 반환값: 목록 상단 상태 영역.
  Widget _buildListStatus() {
    if (_lastRefreshedAt == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.update_outlined,
                        size: 17,
                        color: MedBuddyColors.textSubtle,
                      ),
                    ),
                  ),
                  TextSpan(text: _text.refreshedAt(_lastRefreshedAt!)),
                ],
              ),
              style: const TextStyle(
                color: MedBuddyColors.textSubtle,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            KeepWordsText(
              _text.callBeforeVisit,
              style: const TextStyle(
                color: MedBuddyColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _buildBody
  // 함수역할: 조회 상태·필터·스크롤 목록을 제공한다.
  // 매개변수: showStatus: 별도 드래그 상단이 없을 때 조회 상태를 포함할지 여부.
  // 반환값: 약국 목록 또는 조회 상태 화면.
  Widget _buildBody({bool showStatus = true}) {
    final text = _text;
    if (_isLoading) {
      final loading = _PharmacyLoadingState(message: text.findingNearby);
      return widget.hospitals
          ? Center(child: SingleChildScrollView(child: loading))
          : loading;
    }
    final failureState = _errorMessage != null
        ? _PharmacyMessageState(
            icon: Icons.cloud_off_outlined,
            title: text.unavailableTitle,
            message: _errorMessage!,
            actionLabel: text.retry,
            onAction: _requestRefresh,
          )
        : null;
    // 병원 조회 실패 후에도 날짜·진료과·조회 조건을 바로 바꿀 수 있게 유지한다.
    if (failureState != null && !widget.hospitals) return failureState;

    final visiblePharmacies = _visiblePharmacies;
    final body = Column(
      mainAxisSize: widget.hospitals ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (showStatus) _buildListStatus(),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            visiblePharmacies.isEmpty ? 18 : 2,
            20,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.hospitals)
                _buildHospitalFilters(map: false)
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('pharmacy-filter-selector'),
                    onPressed: _showFilterPicker,
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      side: const BorderSide(color: MedBuddyColors.outline),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          color: MedBuddyColors.primaryDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KeepWordsText(
                            text.filterPickerTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: MedBuddyColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Flexible(
          fit: widget.hospitals ? FlexFit.loose : FlexFit.tight,
          child:
              failureState ??
              (visiblePharmacies.isEmpty
                  ? _PharmacyMessageState(
                      icon: widget.hospitals
                          ? Icons.local_hospital_outlined
                          : Icons.storefront_outlined,
                      title: switch (_filter) {
                        _PharmacyFilter.openNow => text.noOpenPharmacy,
                        _PharmacyFilter.lateHours => text.noLateNightPharmacy,
                        _PharmacyFilter.weekendHoliday =>
                          text.noWeekendHolidayPharmacy,
                        _PharmacyFilter.all => text.noNearbyPharmacy,
                      },
                      message: _filter == _PharmacyFilter.all
                          ? text.checkLocation
                          : text.tryAllPharmacies,
                      actionLabel: _requiresHospitalHolidayDate
                          ? (text.isEnglish
                                ? 'Change search conditions'
                                : '조회 조건 변경')
                          : _filter == _PharmacyFilter.all
                          ? text.refresh
                          : text.showAll,
                      onAction: _requiresHospitalHolidayDate
                          ? _showFilterPicker
                          : _filter == _PharmacyFilter.all
                          ? _requestRefresh
                          // Function Name: _buildBody.onAction callback
                          // Description: Clears pharmacy selection after changing the search filter and reloads matching results.
                          // Parameters:
                          // - None.
                          // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                          : () => _selectFilter(_PharmacyFilter.all),
                    )
                  : ListView.separated(
                      shrinkWrap: widget.hospitals,
                      physics: widget.hospitals
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      itemCount: visiblePharmacies.length + 1,
                      // 함수이름: _buildBody.separatorBuilder callback
                      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 인접 항목 사이에 지정한 간격 또는 구분선을 배치한다.
                      // 매개변수:
                      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      // 함수이름: _buildBody.itemBuilder callback
                      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
                      // 매개변수:
                      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                      // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
                      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                      itemBuilder: (context, index) {
                        if (index == visiblePharmacies.length) {
                          return _PharmacySourceNotice(
                            message: text.sourceNotice(
                              catalogIsStale: _catalogIsStale,
                              holidayScheduleStatus: _holidayScheduleStatus,
                            ),
                          );
                        }
                        final pharmacy = visiblePharmacies[index];
                        return _PharmacyCard(
                          pharmacy: pharmacy,
                          text: text,
                          usesSelectedTime: _filter != _PharmacyFilter.openNow,
                          isSelected: pharmacy.placeId == _selectedPharmacyId,
                          isFavorite: _favoritePharmacyIds.contains(
                            pharmacy.placeId,
                          ),
                          // 함수이름: _buildBody.onSelected callback
                          // 함수역할: 지도에 표시할 약국을 선택하고 다른 약국으로 바뀌면 전화 확인 상태를 지운다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onSelected: () => _selectPharmacy(pharmacy),
                          // 함수이름: _buildBody.onFavoriteRequested callback
                          // 함수역할: 즐겨찾기를 즉시 전환하고 저장 실패 시 해당 변경을 되돌려 안내한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onFavoriteRequested: _canChangeFavorite
                              ? () => _toggleFavorite(pharmacy)
                              : null,
                          onPhoneRequested: pharmacy.telephone.isEmpty
                              ? null
                              // 함수이름: _buildBody.onPhoneRequested callback
                              // 함수역할: 약국 전화번호로 전화 앱을 열고 실패 시 안내한다.
                              // 매개변수:
                              // - 없음.
                              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                              : () => _requestPhoneCall(pharmacy),
                          // 함수이름: _buildBody.onDirectionsRequested callback
                          // 함수역할: 지도 앱 선택을 처리하고 실행 불가 시 Google 지도와 주소 복사로 대체한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onDirectionsRequested: () =>
                              _requestDirections(pharmacy),
                        );
                      },
                    )),
        ),
        if (widget.selectionMode && _selectedPharmacyId != null)
          _buildSelectionFooter(visiblePharmacies),
      ],
    );
    // 병원 목록은 필터·날짜도 함께 스크롤해 큰 글씨에서 결과 공간을 확보한다.
    return widget.hospitals
        ? SingleChildScrollView(
            key: const Key('hospital-results-scroll'),
            child: body,
          )
        : body;
  }

  // Function Name: _buildSelectionFooter
  // Description: Shows the selected place's phone-confirmation checkbox and chat-share action; omits repeated identity in embedded details.
  // Parameters: visiblePharmacies (List<NearbyCarePlace>): current results; embedded (bool): render within the details sheet.
  // Returns: The selection footer, or an empty widget without a selected result.
  Widget _buildSelectionFooter(
    List<NearbyCarePlace> visiblePharmacies, {
    bool embedded = false,
  }) {
    final selectedPharmacy = _findSelectedPharmacy(visiblePharmacies);
    if (selectedPharmacy == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      elevation: embedded ? 0 : 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: embedded
              ? const EdgeInsets.fromLTRB(18, 0, 18, 12)
              : const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!embedded)
                Text(
                  selectedPharmacy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              if (!widget.hospitals)
                CheckboxListTile(
                  value: _selectedPhoneVerified,
                  // 함수이름: _buildSelectionFooter.onChanged callback
                  // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에서 캡처된 작업 `setState(() => _selectedPhoneVerified = value == true)`을 실행한다.
                  // 매개변수:
                  // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onChanged: (value) {
                    // 함수이름: _buildSelectionFooter.setState callback
                    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_selectedPhoneVerified = value == true`로 갱신한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                    setState(() => _selectedPhoneVerified = value == true);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: KeepWordsText(_text.phoneVerified),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // 함수이름: _buildSelectionFooter.onPressed callback
                  // 함수역할: `Navigator.pop(context, NearbyCareSelection(place: selectedPharmacy, phoneVerified: _selectedPhoneVerified))`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onPressed: () {
                    Navigator.pop(
                      context,
                      NearbyCareSelection(
                        place: selectedPharmacy,
                        phoneVerified: _selectedPhoneVerified,
                        scheduleDate: _targetDateTime,
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: KeepWordsText(_text.shareInChat),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Function Name: _buildPharmacyMap
  // Description: Connects result markers and selection to an injected map builder or the default Naver map.
  // Parameters: pharmacies (List<NearbyCarePlace>): results; bottomInset (double): obscured map height; showControls (bool): show map commands.
  // Returns: The configured map widget.
  Widget _buildPharmacyMap(
    List<NearbyCarePlace> pharmacies, {
    double bottomInset = 0,
    bool showControls = true,
  }) {
    final text = _text;
    final selectedPharmacy = _findSelectedPharmacy(pharmacies);
    final statusText = pharmacies.isEmpty
        ? text.noMapMatches
        : selectedPharmacy == null
        ? text.mapInstruction
        : null;
    final mapBuilder = widget.mapBuilder;
    if (mapBuilder != null) {
      return mapBuilder(
        searchArea: _searchArea!,
        centerRevision: _centerRevision,
        isSearching: _isLoading,
        onSearchAreaRequested: _searchMapArea,
        onCurrentLocationRequested: _searchCurrentLocation,
        pharmacies: pharmacies,
        selectedPharmacyId: _selectedPharmacyId,
        onPharmacySelected: _selectPharmacy,
        onAttributionRequested: _requestMapAttribution,
        statusText: statusText,
        selectMarkerHint: text.selectMarkerHint,
        zoomInTooltip: text.zoomInTooltip,
        zoomOutTooltip: text.zoomOutTooltip,
        configurationUnavailableText: text.mapConfigurationUnavailable,
        unavailableText: text.mapUnavailable,
      );
    }
    return NearbyPharmacyMap(
      hospitals: widget.hospitals,
      favoritePharmacyIds: _favoritePharmacyIds,
      bottomInset: bottomInset,
      showControls: showControls,
      searchArea: _searchArea!,
      deviceLocation: _deviceLocation,
      centerRevision: _centerRevision,
      isSearching: _isLoading,
      onSearchAreaRequested: _searchMapArea,
      onCurrentLocationRequested: _searchCurrentLocation,
      searchAreaLabel: text.isEnglish ? 'Search this area' : '이 지역에서 검색',
      myLocationTooltip: text.isEnglish ? 'My location' : '현재 위치로 이동',
      pharmacies: pharmacies,
      selectedPharmacyId: _selectedPharmacyId,
      onPharmacySelected: _selectPharmacy,
      onAttributionRequested: _requestMapAttribution,
      statusText: statusText,
      selectMarkerHint: text.selectMarkerHint,
      zoomInTooltip: text.zoomInTooltip,
      zoomOutTooltip: text.zoomOutTooltip,
      configurationUnavailableText: text.mapConfigurationUnavailable,
      unavailableText: text.mapUnavailable,
    );
  }

  // Function Name: _findSelectedPharmacy
  // Description: Looks up the selected place ID among the supplied results.
  // Parameters: pharmacies (List<NearbyCarePlace>): current candidates.
  // Returns: The matching place, or null.
  NearbyCarePlace? _findSelectedPharmacy(List<NearbyCarePlace> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.placeId == _selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  // Function Name: _selectPharmacy
  // Description: Moves map focus to the place and opens its details, clearing phone confirmation when selection changes.
  // Parameters: pharmacy (NearbyCarePlace): selected result.
  // Returns: None.
  void _selectPharmacy(NearbyCarePlace pharmacy) {
    // 함수이름: _selectPharmacy.setState callback
    // 함수역할: 약국 선택과 지도 이동 요청을 함께 반영하고 목록 대신 상세창을 연다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      if (_selectedPharmacyId != pharmacy.placeId) {
        _selectedPhoneVerified = false;
      }
      _selectedPharmacyId = pharmacy.placeId;
      _listExpanded = false;
      _detailExtent.value = _PharmacyDetailsSheet.initialExtent;
      _centerRevision++;
    });
  }

  // Function Name: _requestPhoneCall
  // Description: Launches the phone app for the place number and reports launch failure while mounted.
  // Parameters: pharmacy (NearbyCarePlace): place to call.
  // Returns: Future completing after the launch attempt.
  Future<void> _requestPhoneCall(NearbyCarePlace pharmacy) async {
    if (!await _control.requestPhoneCall(pharmacy.telephone) && mounted) {
      _showActionMessage(_text.phoneAppFailed);
    }
  }

  // 함수이름: _requestDirections
  // 함수역할: 지도 앱 선택을 처리하고 실행 불가 시 Google 지도와 주소 복사로 대체한다.
  // 매개변수:
  // - pharmacy (NearbyCarePlace): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestDirections(NearbyCarePlace pharmacy) async {
    ModalRoute<dynamic>? directionsRoute;
    var didSelect = false;
    final choice = await showModalBottomSheet<_PharmacyDirectionsChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      // 함수이름: _requestDirections.builder callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (sheetContext) {
        directionsRoute = ModalRoute.of(sheetContext);
        // 모달의 useSafeArea는 하단 시스템 바를 제외하지 않는다.
        return SafeArea(
          top: false,
          child: _PharmacyDirectionsSheet(
            pharmacy: pharmacy,
            text: _text,
            // 함수이름: _requestDirections.onSelected callback
            // 함수역할: `Navigator.of(sheetContext).pop(selected)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onSelected: (selected) {
              // 닫히는 시트를 연속으로 눌러 아래 약국 화면까지 pop하지 않도록 한다.
              if (didSelect || directionsRoute?.isCurrent != true) return;
              didSelect = true;
              Navigator.of(sheetContext).pop(selected);
            },
          ),
        );
      },
    );
    if (!mounted || choice == null) {
      return;
    }

    // 시트 종료 애니메이션까지 마친 뒤 외부 앱을 열어 복귀할 약국 화면을 유지한다.
    await directionsRoute?.completed;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    if (choice == _PharmacyDirectionsChoice.copyAddress) {
      await _copyPharmacyAddress(pharmacy, copiedAsFallback: false);
      return;
    }

    var opened = false;
    if (choice == _PharmacyDirectionsChoice.installedMapApp) {
      opened = await _control.requestInstalledMapDirections(pharmacy);
      // 실행 대기 중 떠난 화면의 실패 응답으로 새 외부 작업을 시작하지 않는다.
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!opened) {
        opened = await _control.requestGoogleMapDirections(pharmacy);
      }
    } else {
      opened = await _control.requestGoogleMapDirections(pharmacy);
    }
    if (!opened && mounted && ModalRoute.of(context)?.isCurrent == true) {
      await _copyPharmacyAddress(pharmacy, copiedAsFallback: true);
    }
  }

  // Function Name: _copyPharmacyAddress
  // Description: Copies the address, or name and coordinates when absent, and distinguishes a map-launch fallback from an explicit copy.
  // Parameters: pharmacy (NearbyCarePlace): place to copy; copiedAsFallback (bool): copy follows map-launch failure.
  // Returns: Future completing after clipboard update and feedback.
  Future<void> _copyPharmacyAddress(
    NearbyCarePlace pharmacy, {
    required bool copiedAsFallback,
  }) async {
    final address = pharmacy.address.trim();
    final value = address.isNotEmpty
        ? address
        : '${pharmacy.name} '
              '(${pharmacy.latitude.toStringAsFixed(7)}, '
              '${pharmacy.longitude.toStringAsFixed(7)})';
    final copied = await _control.copyPharmacyAddress(value);
    if (!mounted) {
      return;
    }
    if (!copied) {
      _showActionMessage(_text.mapAppFailed);
      return;
    }
    _showActionMessage(
      copiedAsFallback
          ? _text.mapUnavailableAddressCopied
          : _text.addressCopied,
    );
  }

  // Function Name: _requestMapAttribution
  // Description: Opens map attribution and reports launch failure while mounted.
  // Parameters: None.
  // Returns: Future completing after the attribution attempt.
  Future<void> _requestMapAttribution() async {
    if (!await _control.requestMapAttribution() && mounted) {
      _showActionMessage(_text.mapAttributionFailed);
    }
  }

  // 함수이름: _showActionMessage
  // 함수역할: 이전 Snackbar를 닫고 약국 관련 작업 결과를 표시한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: KeepWordsText(message)));
  }
}

// Class Name: _PharmacyDirectionsSheet
// Role: Place directions chooser.
// Responsibilities: Offers supported map applications and address copying for the selected place.
// Attributes: pharmacy: destination; text: localized labels; onSelected: chosen directions action.
class _PharmacyDirectionsSheet extends StatelessWidget {
  final NearbyCarePlace pharmacy;
  final _NearbyPharmacyText text;
  final ValueChanged<_PharmacyDirectionsChoice> onSelected;

  // 함수이름: _PharmacyDirectionsSheet
  // 함수역할: 약국 이름과 지도 앱·주소 복사 선택지에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (NearbyCarePlace): 표시하거나 전화·길찾기·공유할 약국.
  // - text (_NearbyPharmacyText): 해당 화면 구역의 언어별 표시 문구.
  // - onSelected (ValueChanged<_PharmacyDirectionsChoice>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _PharmacyDirectionsSheet 인스턴스.
  const _PharmacyDirectionsSheet({
    required this.pharmacy,
    required this.text,
    required this.onSelected,
  });

  // Function Name: build
  // Description: Displays the destination name and scrollable map-app/address-copy choices.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeepWordsText(
            text.directionsSheetTitle,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          KeepWordsText(
            text.directionsSheetDescription,
            style: const TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          KeepWordsText(
            pharmacy.address.isEmpty ? pharmacy.name : pharmacy.address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _DirectionsChoiceTile(
            key: const Key('directions-choice-installed-app'),
            icon: Icons.map_outlined,
            title: text.installedMapAppTitle,
            description: text.installedMapAppDescription,
            // 함수이름: build.onTap callback
            // 함수역할: 약국 이름과 지도 앱·주소 복사 선택지에서 캡처된 작업 `onSelected(_PharmacyDirectionsChoice.installedMapApp)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            onTap: () => onSelected(_PharmacyDirectionsChoice.installedMapApp),
          ),
          _DirectionsChoiceTile(
            key: const Key('directions-choice-google-maps'),
            icon: Icons.public_outlined,
            title: text.googleMapsTitle,
            description: text.googleMapsDescription,
            // 함수이름: build.onTap callback
            // 함수역할: 약국 이름과 지도 앱·주소 복사 선택지에서 캡처된 작업 `onSelected(_PharmacyDirectionsChoice.googleMaps)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            onTap: () => onSelected(_PharmacyDirectionsChoice.googleMaps),
          ),
          _DirectionsChoiceTile(
            key: const Key('directions-choice-copy-address'),
            icon: Icons.content_copy_outlined,
            title: text.copyAddressTitle,
            description: text.copyAddressDescription,
            // 함수이름: build.onTap callback
            // 함수역할: 약국 이름과 지도 앱·주소 복사 선택지에서 캡처된 작업 `onSelected(_PharmacyDirectionsChoice.copyAddress)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            onTap: () => onSelected(_PharmacyDirectionsChoice.copyAddress),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _DirectionsChoiceTile
// 역할: 길찾기 수단의 아이콘·설명과 선택 동작을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 길찾기 수단의 아이콘·설명과 선택 동작 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _DirectionsChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  // 함수이름: _DirectionsChoiceTile
  // 함수역할: 길찾기 수단의 아이콘·설명과 선택 동작에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _DirectionsChoiceTile 인스턴스.
  const _DirectionsChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 길찾기 수단의 아이콘·설명과 선택 동작 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 길찾기 수단의 아이콘·설명과 선택 동작에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: MedBuddyColors.primaryDark),
      title: KeepWordsText(
        title,
        style: const TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      subtitle: KeepWordsText(
        description,
        style: const TextStyle(
          color: MedBuddyColors.textBody,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: MedBuddyColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}

// 클래스명: _PharmacyLoadingState
// 역할: 주변 약국 검색 중 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 주변 약국 검색 중 표시 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
class _PharmacyLoadingState extends StatelessWidget {
  final String message;

  // 함수이름: _PharmacyLoadingState
  // 함수역할: 주변 약국 검색 중 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 입력 설정이 반영된 _PharmacyLoadingState 인스턴스.
  const _PharmacyLoadingState({required this.message});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 주변 약국 검색 중 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 주변 약국 검색 중 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: MedBuddyColors.primary),
          const SizedBox(height: 18),
          KeepWordsText(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// Class Name: _PharmacyMessageState
// Role: Search error or empty-result presentation.
// Responsibilities: Keeps the state message and recovery command reachable at large text sizes.
// Attributes: icon/title/message: state description; actionLabel/onAction: recovery command.
class _PharmacyMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  // 함수이름: _PharmacyMessageState
  // 함수역할: 약국 검색 오류·빈 결과와 해당 복구 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - actionLabel (String): 복구 또는 주요 명령의 버튼 문구.
  // - onAction (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _PharmacyMessageState 인스턴스.
  const _PharmacyMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  // Function Name: build
  // Description: Centers the search-state icon and explanation with a scrollable recovery action.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: MedBuddyColors.textLight),
            const SizedBox(height: 20),
            KeepWordsText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            KeepWordsText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textSubtle,
                fontSize: 15,
                height: 1.5,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: KeepWordsText(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// Class Name: _PharmacyCard
// Role: A nearby-place result with contact actions.
// Responsibilities: Shows operating hours, address, favorite and selection state with call and directions commands.
// Attributes: pharmacy: result data; text: labels; usesSelectedTime: searched-time context; isSelected/isFavorite: row state; callbacks: selection, favorite, call and directions.
class _PharmacyCard extends StatelessWidget {
  final NearbyCarePlace pharmacy;
  final _NearbyPharmacyText text;
  final bool usesSelectedTime;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onSelected;
  final VoidCallback? onFavoriteRequested;
  final VoidCallback? onPhoneRequested;
  final VoidCallback onDirectionsRequested;
  // 상세 정보창에서는 카드 테두리를 없애고 접힌 상태에 맞춰 정보를 줄인다.
  final bool embedded;
  final bool compact;
  final VoidCallback? onClose;

  // 함수이름: _PharmacyCard
  // 함수역할: 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (NearbyCarePlace): 표시하거나 전화·길찾기·공유할 약국.
  // - text (_NearbyPharmacyText): 해당 화면 구역의 언어별 표시 문구.
  // - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
  // - isFavorite (bool): 현재 사용자의 약국 즐겨찾기에 포함되는지 여부.
  // - onSelected (VoidCallback): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // - onFavoriteRequested (VoidCallback?): 약국 즐겨찾기를 전환할 콜백.
  // - onPhoneRequested (VoidCallback?): 해당 약국으로 전화 연결을 요청할 콜백.
  // - onDirectionsRequested (VoidCallback): 해당 약국의 길찾기를 요청할 콜백.
  // - embedded, compact (bool): 정보창 내부 표시와 간략 정보 표시 여부.
  // - onClose (VoidCallback?): 지도 위치를 유지하며 선택 정보를 닫는 콜백.
  // - usesSelectedTime (bool): 현재 시각 대신 선택한 검색 시각의 영업 상태·운영시간 문구를 표시하고 현재 기준 마감 안내를 숨길지 여부.
  // 반환값: 입력 설정이 반영된 _PharmacyCard 인스턴스.
  const _PharmacyCard({
    required this.pharmacy,
    required this.text,
    required this.usesSelectedTime,
    required this.isSelected,
    required this.isFavorite,
    required this.onSelected,
    required this.onFavoriteRequested,
    required this.onPhoneRequested,
    required this.onDirectionsRequested,
    this.embedded = false,
    this.compact = false,
    this.onClose,
  });

  // Function Name: build
  // Description: Displays place identity, operating status and schedule details alongside selection, favorite, call and directions actions.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final statusColor = pharmacy.isOpenNow == true
        ? MedBuddyColors.primaryDark
        : MedBuddyColors.textSubtle;
    final statusSurface = pharmacy.isOpenNow == true
        ? MedBuddyColors.successSurface
        : MedBuddyColors.surfaceSubtle;
    final statusLabel = switch (pharmacy.isOpenNow) {
      true => usesSelectedTime ? text.openAtSearchTime : text.openNow,
      false => usesSelectedTime ? text.closedAtSearchTime : text.closed,
      null => text.hoursNeedCheck,
    };
    final operatingStatusDetail = usesSelectedTime
        ? null
        : text.operatingStatusDetail(pharmacy);
    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusSurface,
        borderRadius: MedBuddyRadii.pill,
      ),
      child: KeepWordsText(
        statusLabel,
        style: TextStyle(
          color: statusColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );

    return Semantics(
      container: true,
      button: !embedded,
      selected: isSelected,
      label: '${pharmacy.name}, $statusLabel, ${pharmacy.distanceLabel}',
      hint: embedded ? null : text.showOnMap,
      child: Material(
        key: ValueKey(
          '${embedded ? 'pharmacy-detail' : 'pharmacy-card'}-${pharmacy.placeId}',
        ),
        color: !embedded && isSelected
            ? MedBuddyColors.successSurface
            : Colors.white,
        elevation: embedded
            ? 0
            : isSelected
            ? 2
            : 1,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        shape: embedded
            ? null
            : RoundedRectangleBorder(
                borderRadius: MedBuddyRadii.card,
                side: BorderSide(
                  color: isSelected
                      ? MedBuddyColors.primary
                      : MedBuddyColors.outline,
                  width: isSelected ? 2 : 1,
                ),
              ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: embedded ? null : onSelected,
          child: Padding(
            padding: embedded
                ? const EdgeInsets.fromLTRB(18, 0, 18, 8)
                : const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 좁은 화면의 큰 글씨에서는 운영 상태를 다음 줄로 내려 이름 공간을 확보한다.
                    final separateStatus =
                        !embedded &&
                        constraints.maxWidth <
                            200 * MediaQuery.textScalerOf(context).scale(1);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: embedded
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: KeepWordsText(
                                pharmacy.name,
                                key: embedded
                                    ? const Key('pharmacy-detail-name')
                                    : null,
                                maxLines: embedded && !compact ? null : 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: MedBuddyColors.textStrong,
                                  fontSize: 20,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              key: embedded
                                  ? const Key('pharmacy-detail-favorite')
                                  : null,
                              tooltip: isFavorite
                                  ? text.removeFavorite
                                  : text.addFavorite,
                              onPressed: onFavoriteRequested,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: isFavorite
                                    ? const Color(0xFFF2A900)
                                    : MedBuddyColors.textSubtle,
                              ),
                            ),
                            if (onClose != null)
                              IconButton(
                                key: const Key('pharmacy-detail-close'),
                                tooltip: text.closeDetails,
                                onPressed: onClose,
                                icon: const Icon(Icons.close),
                              ),
                            if (!embedded && !separateStatus) statusBadge,
                          ],
                        ),
                        if (separateStatus)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: statusBadge,
                          ),
                      ],
                    );
                  },
                ),
                SizedBox(height: embedded ? 2 : 12),
                if (embedded)
                  Wrap(
                    key: const Key('pharmacy-detail-status'),
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusBadge,
                      Text(
                        text.distance(pharmacy.distanceLabel),
                        style: const TextStyle(
                          fontSize: 15,
                          color: MedBuddyColors.textMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  )
                else
                  _PharmacyInfoLine(
                    icon: Icons.near_me_outlined,
                    text: text.distance(pharmacy.distanceLabel),
                  ),
                if (!compact) ...[
                  if (text.hospitals && pharmacy.departments.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _PharmacyInfoLine(
                      icon: Icons.medical_services_outlined,
                      text: pharmacy.departments.join(' · '),
                    ),
                  ],
                  if (text.hospitals &&
                      pharmacy.institutionType?.isNotEmpty == true) ...[
                    const SizedBox(height: 7),
                    _PharmacyInfoLine(
                      icon: Icons.local_hospital_outlined,
                      text: pharmacy.institutionType!,
                    ),
                  ],
                  const SizedBox(height: 7),
                  _PharmacyInfoLine(
                    icon: Icons.schedule_outlined,
                    text: text.todayHours(
                      pharmacy,
                      usesSelectedTime: usesSelectedTime,
                    ),
                  ),
                  if (operatingStatusDetail != null) ...[
                    const SizedBox(height: 7),
                    _PharmacyInfoLine(
                      icon: pharmacy.isOpenNow == true
                          ? Icons.timer_outlined
                          : Icons.event_available_outlined,
                      text: operatingStatusDetail,
                    ),
                  ],
                  if (text.scheduleTags(pharmacy).isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _PharmacyInfoLine(
                      icon: Icons.nightlight_outlined,
                      text: text.scheduleTags(pharmacy),
                    ),
                  ],
                  if (pharmacy.address.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _PharmacyInfoLine(
                      icon: Icons.location_on_outlined,
                      text: pharmacy.address,
                    ),
                  ],
                ],
                SizedBox(height: embedded ? 10 : 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPhoneRequested,
                        icon: const Icon(Icons.call_outlined),
                        label: Text(text.phone),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: ValueKey(
                          'pharmacy-directions-${pharmacy.placeId}',
                        ),
                        onPressed: onDirectionsRequested,
                        icon: const Icon(Icons.directions_outlined),
                        label: Text(text.directions),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _PharmacyInfoLine
// 역할: 약국 거리·시간·주소에 쓰는 아이콘과 정보 행을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약국 거리·시간·주소에 쓰는 아이콘과 정보 행 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
class _PharmacyInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  // 함수이름: _PharmacyInfoLine
  // 함수역할: 약국 거리·시간·주소에 쓰는 아이콘과 정보 행에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - text (String): 해당 라벨 또는 정보 행에 표시할 문자열.
  // 반환값: 입력 설정이 반영된 _PharmacyInfoLine 인스턴스.
  const _PharmacyInfoLine({required this.icon, required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 거리·시간·주소에 쓰는 아이콘과 정보 행 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 거리·시간·주소에 쓰는 아이콘과 정보 행에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: KeepWordsText(
            text,
            style: const TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 15,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _PharmacySourceNotice
// 역할: 약국 데이터 출처·신선도·방문 전 확인 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약국 데이터 출처·신선도·방문 전 확인 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
class _PharmacySourceNotice extends StatelessWidget {
  final String message;

  // 함수이름: _PharmacySourceNotice
  // 함수역할: 약국 데이터 출처·신선도·방문 전 확인 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 입력 설정이 반영된 _PharmacySourceNotice 인스턴스.
  const _PharmacySourceNotice({required this.message});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 데이터 출처·신선도·방문 전 확인 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 데이터 출처·신선도·방문 전 확인 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: KeepWordsText(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: MedBuddyColors.textSubtle,
          fontSize: 13,
          height: 1.45,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// Class Name: _NearbyPharmacyText
// Role: Localized pharmacy-search and contact copy.
// Responsibilities: Formats hours and operating status without treating an unknown holiday calendar as proof of no open results.
// Attributes: language (String): language code; calendarUnknown (bool): calendar verification unavailable.
class _NearbyPharmacyText {
  final String language;
  final bool calendarUnknown;

  // Function Name: _NearbyPharmacyText
  // Description: Stores language and calendar uncertainty for pharmacy-search messages.
  // Parameters: language (String): selected language; calendarUnknown (bool): opening status cannot be confirmed.
  // Returns: A _NearbyPharmacyText.
  const _NearbyPharmacyText(this.language, {this.calendarUnknown = false});

  // Function Name: isEnglish
  // Description: Applies the shared English-language-code rule.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: hospitals
  // 함수역할: 기본 문구가 약국 검색용임을 구분한다.
  // 매개변수: 없음.
  // 반환값: false. 병원 문구가 이를 재정의한다.
  bool get hospitals => false;

  // 함수이름: showList
  // 함수역할: 약국 목록 버튼에 결과 수를 포함한다.
  // 매개변수: count (int): 표시 결과 수.
  // 반환값: 현재 언어의 목록 버튼 문구.
  String showList(int count) =>
      isEnglish ? 'Show pharmacies ($count)' : '약국 목록 보기 ($count)';

  // 함수이름: closeDetails
  // 함수역할: 약국 상세를 닫는 접근성 문구를 선택한다.
  // 매개변수: 없음.
  // 반환값: 현재 언어의 닫기 문구.
  String get closeDetails => isEnglish ? 'Close pharmacy details' : '약국 정보 닫기';

  // Function Name: noMapMatches
  // Description: Selects the empty-map guidance, avoiding a definitive closed/no-result claim when the holiday calendar is unknown.
  // Parameters: None.
  // Returns: Localized map-result guidance.
  String get noMapMatches => calendarUnknown
      ? openingStatusUnverified
      : isEnglish
      ? 'No pharmacies match here. Move the map or change the filter.'
      : '조건에 맞는 약국이 없어요. 지도를 옮기거나 조회 조건을 바꿔보세요.';

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로 가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로 가기';
  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "근처 운영 약국" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Nearby Pharmacies' : '근처 운영 약국';
  // 함수이름: subtitle
  // 함수역할: GPS와 지도 선택 모두에 맞는 검색 위치 안내를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get subtitle =>
      isEnglish ? 'Find pharmacies in this area.' : '주변 약국을 확인합니다.';
  // 함수이름: refreshTooltip
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 목록 새로고침" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get refreshTooltip =>
      isEnglish ? 'Refresh pharmacy list' : '약국 목록 새로고침';
  // 함수이름: loadFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadFailed => isEnglish
      ? 'Could not load pharmacy information.\nPlease try again shortly.'
      : '약국 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.';
  // Function Name: sharedPlaceMissing
  // Description: Explains that the place from a shared card could not be found in the current lookup.
  // Parameters: None.
  // Returns: Localized missing-place notice.
  String get sharedPlaceMissing => isEnglish
      ? 'The shared place is not in the current list. Showing places nearby.'
      : '공유된 장소를 지금 목록에서 찾지 못했어요. 주변 장소를 보여드려요.';
  // 함수이름: loadingAction
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 정보를 불러오는 중입니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadingAction =>
      isEnglish ? 'Pharmacy information is loading.' : '약국 정보를 불러오는 중입니다.';
  // 함수이름: refreshLimited
  // 함수역할: 현재 언어와 입력값에 맞춰 "새로고침 요청이 많습니다. 잠시 후 다시 시도해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get refreshLimited => isEnglish
      ? 'Too many refresh requests. Please try again shortly.'
      : '새로고침 요청이 많습니다. 잠시 후 다시 시도해주세요.';
  // 함수이름: unavailableTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 정보를 확인할 수 없습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get unavailableTitle =>
      isEnglish ? 'Pharmacy information is unavailable' : '약국 정보를 확인할 수 없습니다';
  // 함수이름: retry
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 시도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retry => isEnglish ? 'Try again' : '다시 시도';
  // 함수이름: openNow
  // 함수역할: 현재 언어와 입력값에 맞춰 "영업 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openNow => isEnglish ? 'Open now' : '영업 중';
  // 함수이름: openAtSearchTime
  // 함수역할: 조회 시각의 약국 영업 중 상태를 표시한다.
  // 매개변수: 없음.
  // 반환값: 현재 언어의 조회 시각 영업 라벨.
  String get openAtSearchTime => isEnglish ? 'Open at search time' : '조회 시각 영업';
  // Function Name: closedAtSearchTime
  // Description: Labels a pharmacy closed at the search time rather than asserting its live state.
  // Parameters: None.
  // Returns: Localized search-time closed label.
  String get closedAtSearchTime =>
      isEnglish ? 'Closed at search time' : '조회 시각 영업 종료';
  // 함수이름: openFilter
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 영업 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openFilter => isEnglish ? 'Open now' : '현재 영업 중';
  // 함수이름: lateHours
  // 함수역할: 현재 언어와 입력값에 맞춰 "늦게까지 영업" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get lateHours => isEnglish ? 'Open late' : '늦게까지 영업';
  // 함수이름: weekendHoliday
  // 함수역할: 현재 언어와 입력값에 맞춰 "주말·공휴일 영업" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get weekendHoliday =>
      isEnglish ? 'Open on weekends / holidays' : '주말·공휴일 영업';
  // 함수이름: allPharmacies
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 약국" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get allPharmacies => isEnglish ? 'All pharmacies' : '전체 약국';
  // 함수이름: close
  // 함수역할: 현재 언어와 입력값에 맞춰 "Close" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get close => isEnglish ? 'Close' : '닫기';
  // 함수이름: filterPickerTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "조회 조건" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get filterPickerTitle => isEnglish ? 'Search filter' : '조회 조건';
  // 함수이름: selectedFilter
  // 함수역할: 현재 언어와 입력값에 맞춰 "조회 조건: $label" 문구를 제공한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String selectedFilter(String label) =>
      isEnglish ? 'Search filter: $label' : '조회 조건: $label';
  // 함수이름: filterDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "지금 바로 방문할 수 있는 약국을 표시합니다." 문구를 제공한다.
  // 매개변수:
  // - filter (_PharmacyFilter): 적용할 약국 영업 조건.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String filterDescription(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow =>
        isEnglish
            ? 'Show pharmacies you can visit right now.'
            : '지금 바로 방문할 수 있는 약국을 표시합니다.',
      _PharmacyFilter.lateHours =>
        isEnglish
            ? 'Find public late-night pharmacies and pharmacies with late operating hours.'
            : '공공심야약국과 늦은 시간까지 운영하는 약국을 함께 찾습니다.',
      _PharmacyFilter.weekendHoliday =>
        isEnglish
            ? 'Find pharmacies operating on the selected weekend or holiday.'
            : '선택한 주말이나 공휴일에 운영하는 약국을 찾습니다.',
      _PharmacyFilter.all =>
        isEnglish
            ? 'Show every nearby pharmacy regardless of operating hours.'
            : '운영시간과 관계없이 주변 약국을 모두 표시합니다.',
    };
  }

  // Function Name: noOpenPharmacy
  // Description: Reports no open pharmacies in this search area, or unverified opening status when the calendar is unknown.
  // Parameters: None.
  // Returns: The localized empty/uncertain result message.
  String get noOpenPharmacy => calendarUnknown
      ? openingStatusUnverified
      : isEnglish
      ? 'No open pharmacies were found in this search area'
      : '검색한 지역에 영업 중인 약국이 없습니다';
  // Function Name: openingStatusUnverified
  // Description: Explain an empty time-filtered search when calendar verification failed.
  // Parameters: None. Returns: Localized uncertainty message.
  String get openingStatusUnverified => isEnglish
      ? 'Pharmacy opening status could not be verified'
      : '약국 영업 여부를 확인할 수 없습니다';
  // Function Name: noLateNightPharmacy
  // Description: Reports no late-night results unless calendar uncertainty prevents that conclusion.
  // Parameters: None.
  // Returns: The localized late-night empty/uncertain message.
  String get noLateNightPharmacy => calendarUnknown
      ? openingStatusUnverified
      : isEnglish
      ? 'No late-night pharmacies were found in this search area'
      : '검색한 지역에 심야 운영 약국이 없습니다';
  // Function Name: noWeekendHolidayPharmacy
  // Description: Reports no weekend/holiday results unless calendar uncertainty prevents that conclusion.
  // Parameters: None.
  // Returns: The localized weekend/holiday empty/uncertain message.
  String get noWeekendHolidayPharmacy => calendarUnknown
      ? openingStatusUnverified
      : isEnglish
      ? 'No pharmacies with weekend or holiday hours were found in this search area'
      : '검색한 지역에 주말·공휴일 운영 약국이 없습니다';
  // 함수이름: noNearbyPharmacy
  // 함수역할: 현재 언어와 입력값에 맞춰 "주변 약국을 찾지 못했습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noNearbyPharmacy =>
      isEnglish ? 'No nearby pharmacies were found' : '주변 약국을 찾지 못했습니다';
  // 함수이름: checkLocation
  // 함수역할: 다른 검색 지역을 선택하도록 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get checkLocation => isEnglish
      ? 'Move the map to search another area.'
      : '지도를 옮겨 다른 지역을 검색해주세요.';
  // 함수이름: tryAllPharmacies
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 약국으로 전환하거나 잠시 후 다시 확인해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get tryAllPharmacies => isEnglish
      ? 'Switch to all pharmacies or try again shortly.'
      : '전체 약국으로 전환하거나 잠시 후 다시 확인해주세요.';
  // 함수이름: refresh
  // 함수역할: 현재 언어와 입력값에 맞춰 "새로고침" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get refresh => isEnglish ? 'Refresh' : '새로고침';
  // 함수이름: showAll
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 약국 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get showAll => isEnglish ? 'Show all pharmacies' : '전체 약국 보기';
  // 함수이름: phoneAppFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "전화 앱을 열 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get phoneAppFailed =>
      isEnglish ? 'Could not open the phone app.' : '전화 앱을 열 수 없습니다.';
  // 함수이름: mapAppFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도 앱을 열 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mapAppFailed =>
      isEnglish ? 'Could not open the map app.' : '지도 앱을 열 수 없습니다.';
  // 함수이름: mapAttributionFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도 저작권 정보를 열 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mapAttributionFailed => isEnglish
      ? 'Could not open the map copyright information.'
      : '지도 저작권 정보를 열 수 없습니다.';
  // Function Name: mapInstruction
  // Description: Explains that markers or the result list open place details.
  // Parameters: None.
  // Returns: The localized map instruction.
  String get mapInstruction => isEnglish
      ? 'Tap a marker or open the pharmacy list for details'
      : '지도 표시를 누르거나 약국 목록을 열어 상세 정보를 확인하세요';
  // 함수이름: selectMarkerHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 약국을 지도에서 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get selectMarkerHint =>
      isEnglish ? 'Show this pharmacy on the map' : '이 약국을 지도에서 보기';
  // 함수이름: showOnMap
  // 함수역할: 현재 언어와 입력값에 맞춰 "누르면 지도에서 위치를 표시합니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get showOnMap =>
      isEnglish ? 'Tap to show on the map' : '누르면 지도에서 위치를 표시합니다';
  // 함수이름: zoomInTooltip
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도 확대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get zoomInTooltip => isEnglish ? 'Zoom in' : '지도 확대';
  // 함수이름: zoomOutTooltip
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도 축소" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get zoomOutTooltip => isEnglish ? 'Zoom out' : '지도 축소';
  // 함수이름: mapConfigurationUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 실행 환경에는 앱 내 지도 설정이 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mapConfigurationUnavailable => isEnglish
      ? 'The in-app map is not configured for this build.'
      : '이 실행 환경에는 앱 내 지도 설정이 없습니다.';
  // 함수이름: mapUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "표시할 수 있는 약국 좌표가 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mapUnavailable => isEnglish
      ? 'Map coordinates are unavailable for these pharmacies.'
      : '표시할 수 있는 약국 좌표가 없습니다.';
  // 함수이름: findingNearby
  // 함수역할: 선택한 위치 주변 약국을 조회 중임을 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get findingNearby => isEnglish
      ? 'Finding pharmacies near the search location'
      : '검색 위치 주변 약국을 찾고 있습니다';
  // 함수이름: closed
  // 함수역할: 현재 언어와 입력값에 맞춰 "영업 종료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get closed => isEnglish ? 'Closed' : '영업 종료';
  // 함수이름: hoursNeedCheck
  // 함수역할: 현재 언어와 입력값에 맞춰 "시간 확인 필요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get hoursNeedCheck => isEnglish ? 'Check opening hours' : '시간 확인 필요';
  // 함수이름: distance
  // 함수역할: 현재 언어와 입력값에 맞춰 "$value 거리" 문구를 제공한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String distance(String value) => isEnglish ? '$value away' : '$value 거리';

  // Function Name: todayHours
  // Description: Formats 24-hour operation or an opening/closing range, with an unknown-hours fallback appropriate to the selected search time.
  // Parameters: pharmacy (NearbyCarePlace): hours data; usesSelectedTime (bool): selected-time rather than today wording.
  // Returns: Localized operating-hours text.
  String todayHours(NearbyCarePlace pharmacy, {bool usesSelectedTime = false}) {
    if (pharmacy.is24Hours) {
      return isEnglish ? 'Open 24 hours' : '24시간 운영';
    }
    if (pharmacy.todayOpenTime == null || pharmacy.todayCloseTime == null) {
      return usesSelectedTime
          ? (isEnglish ? 'Check search-date hours' : '조회일 영업시간 확인 필요')
          : (isEnglish ? 'Check today\'s opening hours' : '오늘 영업시간 확인 필요');
    }
    final dayLabel = usesSelectedTime
        ? (isEnglish ? 'Search date' : '조회일')
        : (isEnglish ? 'Today' : '오늘');
    return '$dayLabel ${pharmacy.todayOpenTime} - ${pharmacy.todayCloseTime}';
  }

  // Function Name: scheduleTags
  // Description: Combines applicable late-night and weekend/holiday schedule tags, including stale-designation warnings.
  // Parameters: pharmacy (NearbyCarePlace): schedule flags.
  // Returns: Localized joined tags, possibly empty.
  String scheduleTags(NearbyCarePlace pharmacy) {
    final labels = <String>[];
    if (pharmacy.isOfficialLateNight || pharmacy.isOpenLate) {
      labels.add(isEnglish ? 'Open late' : '늦게까지 영업');
      if (pharmacy.designationIsStale) {
        labels.add(isEnglish ? 'Schedule needs rechecking' : '운영 정보 재확인 필요');
      }
    }
    if (pharmacy.hasWeekendOrHolidayHours) {
      labels.add(isEnglish ? 'Weekend/holiday hours available' : '주말·공휴일 운영');
    }
    return labels.join(' · ');
  }

  // Function Name: searchDate
  // Description: Formats a search calendar date without a time component.
  // Parameters:
  // - value (DateTime): Input to validate, normalize, display, or pass through a selection callback.
  // Returns: The formatted display text or identifier described above.
  String searchDate(DateTime value) => formatJsonDate(value)!;

  // 함수이름: phone
  // 함수역할: 현재 언어와 입력값에 맞춰 "Call" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get phone => isEnglish ? 'Call' : '전화';
  // 함수이름: directions
  // 함수역할: 현재 언어와 입력값에 맞춰 "길찾기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get directions => isEnglish ? 'Directions' : '길찾기';
  // 함수이름: directionsSheetTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "어떤 앱으로 여시겠습니까?" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get directionsSheetTitle =>
      isEnglish ? 'How would you like to open directions?' : '어떤 앱으로 여시겠습니까?';
  // 함수이름: directionsSheetDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도 앱을 선택하거나 주소를 복사할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get directionsSheetDescription => isEnglish
      ? 'Choose a map app, open Google Maps, or copy the address.'
      : '지도 앱을 선택하거나 주소를 복사할 수 있습니다.';
  // 함수이름: installedMapAppTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "설치된 지도 앱 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get installedMapAppTitle =>
      isEnglish ? 'Choose an installed map app' : '설치된 지도 앱 선택';
  // 함수이름: installedMapAppDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "휴대폰에 설치된 지도 앱 중에서 선택합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get installedMapAppDescription => isEnglish
      ? 'Choose from map apps installed on this phone.'
      : '휴대폰에 설치된 지도 앱 중에서 선택합니다.';
  // 함수이름: googleMapsTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "Google 지도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get googleMapsTitle => isEnglish ? 'Google Maps' : 'Google 지도';
  // 함수이름: googleMapsDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "Google 지도 앱 또는 웹 브라우저로 엽니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get googleMapsDescription => isEnglish
      ? 'Open directions in the Google Maps app or browser.'
      : 'Google 지도 앱 또는 웹 브라우저로 엽니다.';
  // 함수이름: copyAddressTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "주소 복사" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get copyAddressTitle => isEnglish ? 'Copy address' : '주소 복사';
  // 함수이름: copyAddressDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "지도나 메모 앱에 붙여넣을 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get copyAddressDescription => isEnglish
      ? 'Paste the address into a map or notes app.'
      : '지도나 메모 앱에 붙여넣을 수 있습니다.';
  // 함수이름: addressCopied
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 주소를 복사했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addressCopied =>
      isEnglish ? 'The pharmacy address was copied.' : '약국 주소를 복사했습니다.';
  // 함수이름: mapUnavailableAddressCopied
  // 함수역할: 현재 언어와 입력값에 맞춰 "열 수 있는 지도 앱이 없어 약국 주소를 복사했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get mapUnavailableAddressCopied => isEnglish
      ? 'No map app could be opened, so the address was copied.'
      : '열 수 있는 지도 앱이 없어 약국 주소를 복사했습니다.';
  // 함수이름: addFavorite
  // 함수역할: 현재 언어와 입력값에 맞춰 "즐겨찾기 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addFavorite => isEnglish ? 'Add to favorites' : '즐겨찾기 추가';
  // 함수이름: removeFavorite
  // 함수역할: 현재 언어와 입력값에 맞춰 "즐겨찾기 해제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get removeFavorite => isEnglish ? 'Remove favorite' : '즐겨찾기 해제';
  // 함수이름: favoriteLoadFailed
  // 함수역할: 즐겨찾기 조회 실패와 재시도 방법을 현재 언어로 알린다.
  // 매개변수: 없음. 반환값: 오류 안내 문구.
  String get favoriteLoadFailed => isEnglish
      ? 'Could not load favorites. Reopen this screen to try again.'
      : '즐겨찾기를 불러오지 못했습니다. 화면을 다시 열어주세요.';
  // 함수이름: favoriteSaveFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 즐겨찾기를 저장하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get favoriteSaveFailed => isEnglish
      ? 'Could not save the pharmacy favorite.'
      : '약국 즐겨찾기를 저장하지 못했습니다.';
  // 함수이름: phoneVerified
  // 함수역할: 현재 언어와 입력값에 맞춰 "전화로 운영 여부를 확인했어요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get phoneVerified => isEnglish
      ? 'I called and confirmed the opening hours'
      : '전화로 운영 여부를 확인했어요';
  // 함수이름: shareInChat
  // 함수역할: 현재 언어와 입력값에 맞춰 "채팅에 공유" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get shareInChat => isEnglish ? 'Share in chat' : '채팅에 공유';
  // 함수이름: callBeforeVisit
  // 함수역할: 현재 언어와 입력값에 맞춰 "방문 전 전화 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get callBeforeVisit =>
      isEnglish ? 'Call before visiting' : '방문 전 전화 확인';

  // 함수이름: refreshedAt
  // 함수역할: 현재 언어와 입력값에 맞춰 "최근 조회 $time" 문구를 제공한다.
  // 매개변수:
  // - value (DateTime): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String refreshedAt(DateTime value) {
    final local = value.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return isEnglish ? 'Updated $time' : '최근 조회 $time';
  }

  // Function Name: operatingStatusDetail
  // Description: Formats closing-soon detail for 1 to 60 remaining minutes, or the next local opening weekday/time for a closed place.
  // Parameters: pharmacy (NearbyCarePlace): current status and next transition.
  // Returns: Localized status detail, or null without a relevant transition.
  String? operatingStatusDetail(NearbyCarePlace pharmacy) {
    final remainingMinutes = pharmacy.minutesUntilClose;
    if (pharmacy.isOpenNow == true &&
        remainingMinutes != null &&
        remainingMinutes > 0 &&
        remainingMinutes <= 60) {
      return isEnglish
          ? 'Closes in $remainingMinutes min'
          : '$remainingMinutes분 후 영업 종료';
    }
    final nextOpenAt = pharmacy.nextOpenAt?.toLocal();
    if (pharmacy.isOpenNow == false && nextOpenAt != null) {
      const koreanWeekdays = ['월', '화', '수', '목', '금', '토', '일'];
      const englishWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final weekday = isEnglish
          ? englishWeekdays[nextOpenAt.weekday - 1]
          : '${koreanWeekdays[nextOpenAt.weekday - 1]}요일';
      final time =
          '${nextOpenAt.hour.toString().padLeft(2, '0')}:'
          '${nextOpenAt.minute.toString().padLeft(2, '0')}';
      return isEnglish
          ? 'Next opening: $weekday $time'
          : '다음 영업: $weekday $time';
    }
    return null;
  }

  // Function Name: sourceNotice
  // Description: Provides localized wording for "The synchronized catalog is older than expected." using the current language and message inputs.
  // Parameters:
  // - catalogIsStale (bool): Whether the base pharmacy catalog is stale.
  // - holidayScheduleStatus (String): Exact-date, cached, or weekly fallback status of holiday hours.
  // Returns: The formatted display text or identifier described above.
  String sourceNotice({
    required bool catalogIsStale,
    required String holidayScheduleStatus,
  }) {
    final warning = catalogIsStale
        ? (isEnglish
              ? ' The synchronized catalog is older than expected.'
              : ' 동기화된 약국 목록이 예상보다 오래되었습니다.')
        : '';
    final holidayWarning = switch (holidayScheduleStatus) {
      NearbyCareSearchResult.holidayScheduleUnknown =>
        isEnglish
            ? ' The holiday calendar could not be verified; opening status may be unknown.'
            : ' 공휴일 여부를 확인하지 못해 영업 상태가 미확인일 수 있습니다.',
      'stale_fallback' =>
        isEnglish
            ? ' A cached holiday roster is being used.'
            : ' 저장된 명절 비상운영 목록을 사용 중입니다.',
      'weekly_fallback' =>
        isEnglish
            ? ' Exact-date holiday data is unavailable; weekly reported hours are shown.'
            : ' 날짜별 명절 정보가 없어 주간 신고 영업시간을 표시합니다.',
      _ => '',
    };
    final base = isEnglish
        ? 'Information is based on National Emergency Medical Center public data. Official late-night designations currently cover verified Seoul records.'
        : '국립중앙의료원 공공데이터를 기준으로 표시하며, 공식 공공심야 지정은 현재 검증된 서울시 목록을 제공합니다.';
    final callFirst = isEnglish
        ? ' Call before visiting to confirm actual opening hours.'
        : ' 방문 전 전화로 실제 운영 여부를 확인해주세요.';
    return '$base$warning$holidayWarning$callFirst';
  }
}

// Class Name: _NearbyHospitalText
// Role: Hospital-specific wording that preserves uncertainty about coverage and consultation hours.
// Responsibilities: Adapts shared pharmacy presentation without implying complete hospital coverage or pharmacy designations.
// Attributes: searchTruncated/regionScopeUncertain/requiresWeekendDate (bool): completeness/date flags; calendarUnknown (bool, inherited): calendar confidence.
class _NearbyHospitalText extends _NearbyPharmacyText {
  final bool searchTruncated;
  final bool regionScopeUncertain;
  final bool requiresWeekendDate;

  // Function Name: _NearbyHospitalText
  // Description: Binds language and hospital-specific coverage/date warning flags.
  // Parameters: language (String): display language; searchTruncated/regionScopeUncertain/calendarUnknown/requiresWeekendDate (bool): query limitations.
  // Returns: New _NearbyHospitalText.
  const _NearbyHospitalText(
    super.language, {
    this.searchTruncated = false,
    this.regionScopeUncertain = false,
    super.calendarUnknown,
    this.requiresWeekendDate = false,
  });

  // 함수이름: _chooseWeekendDate
  // 함수역할: 주말·공휴일 날짜 선택 요청를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  String get _chooseWeekendDate =>
      isEnglish ? 'Choose a weekend or public holiday' : '주말이나 공휴일을 선택해주세요';

  // 함수이름: _noPartialMatches
  // 함수역할: 조회한 병원 안에서만 조건 일치가 없다는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  String get _noPartialMatches => isEnglish
      ? 'No matches among the hospitals checked'
      : '조회한 병원 중 조건에 맞는 결과가 없습니다';

  // 함수이름: _incompleteCoverage
  // 함수역할: 부분 조회 또는 추정 지역 검색이면 주변 병원 전체를 확인하지 못한 것으로 판단한다.
  // 매개변수: 없음.
  // 반환값: 조회 범위가 불완전하면 true.
  bool get _incompleteCoverage => searchTruncated || regionScopeUncertain;

  // 함수이름: _consultationUnavailable
  // 함수역할: 진료 여부를 검증할 수 없다는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  String get _consultationUnavailable => isEnglish
      ? 'Consultation status cannot be verified'
      : '진료 여부를 확인할 수 없습니다';

  // 함수이름: hospitals
  // 함수역할: 공통 시설 표시를 병원 용어로 전환한다.
  // 매개변수: 없음.
  // 반환값: true.
  @override
  bool get hospitals => true;
  // 함수이름: title
  // 함수역할: 주변 병원 화면 제목를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get title => isEnglish ? 'Nearby Hospitals' : '근처 운영 병원';
  // 함수이름: subtitle
  // 함수역할: 주변 병원 조회 설명를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get subtitle =>
      isEnglish ? 'Find hospitals in this area.' : '주변 병원을 확인합니다.';
  // 함수이름: refreshTooltip
  // 함수역할: 병원 목록 새로고침 접근성 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get refreshTooltip =>
      isEnglish ? 'Refresh hospital list' : '병원 목록 새로고침';
  // 함수이름: loadFailed
  // 함수역할: 병원 정보 조회 실패와 재시도 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get loadFailed => isEnglish
      ? 'Could not load hospital information.\nPlease try again shortly.'
      : '병원 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.';
  // 함수이름: loadingAction
  // 함수역할: 병원 정보 조회 진행 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get loadingAction =>
      isEnglish ? 'Hospital information is loading.' : '병원 정보를 불러오는 중입니다.';
  // 함수이름: unavailableTitle
  // 함수역할: 병원 정보 이용 불가 제목를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get unavailableTitle =>
      isEnglish ? 'Hospital information is unavailable' : '병원 정보를 확인할 수 없습니다';
  // 함수이름: openNow
  // 함수역할: 현재 진료 중 상태를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get openNow => isEnglish ? 'Open now' : '진료 중';
  // 함수이름: openAtSearchTime
  // 함수역할: 조회 시각 진료 중 상태를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get openAtSearchTime => isEnglish ? 'Open at search time' : '조회 시각 진료';
  // 함수이름: closedAtSearchTime
  // 함수역할: 조회 시각 진료 종료 상태를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get closedAtSearchTime =>
      isEnglish ? 'Closed at search time' : '조회 시각 진료 종료';
  // 함수이름: closed
  // 함수역할: 진료 종료 상태를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get closed => isEnglish ? 'Closed' : '진료 종료';
  // 함수이름: hoursNeedCheck
  // 함수역할: 진료시간 재확인 필요 상태를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get hoursNeedCheck =>
      isEnglish ? 'Check consultation hours' : '진료시간 확인 필요';
  // 함수이름: openFilter
  // 함수역할: 현재 진료 병원 필터를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get openFilter => isEnglish ? 'Open now' : '현재 진료 중';
  // 함수이름: lateHours
  // 함수역할: 저녁 진료 필터를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get lateHours => isEnglish ? 'Evening consultations' : '저녁 진료';
  // 함수이름: weekendHoliday
  // 함수역할: 주말·공휴일 진료 필터를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get weekendHoliday => isEnglish ? 'Weekends / holidays' : '주말·공휴일 진료';
  // 함수이름: allPharmacies
  // 함수역할: 전체 병원 필터를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get allPharmacies => isEnglish ? 'All hospitals' : '전체 병원';
  // 함수이름: filterDescription
  // 함수역할: 병원 조건을 신고 진료시간 기준으로 설명하며 약국 지정 여부와 혼동하지 않게 한다.
  // 매개변수: filter (_PharmacyFilter): 공통 운영 조건.
  // 반환값: 현재 언어의 병원 조건 설명.
  @override
  String filterDescription(_PharmacyFilter filter) => switch (filter) {
    _PharmacyFilter.openNow =>
      isEnglish
          ? 'Find hospitals reporting consultation hours for the current time.'
          : '현재 시각에 진료시간이 등록된 병원을 찾습니다.',
    _PharmacyFilter.lateHours =>
      isEnglish
          ? 'Find hospitals with consultation hours after 6 PM on the selected date.'
          : '선택한 날짜에 오후 6시 이후에도 진료시간이 있는 병원을 찾습니다.',
    _PharmacyFilter.weekendHoliday =>
      isEnglish
          ? 'Find hospitals with reported weekend or holiday consultation hours.'
          : '주말이나 공휴일 진료시간이 등록된 병원을 찾습니다.',
    _PharmacyFilter.all =>
      isEnglish
          ? 'Show nearby hospitals regardless of consultation hours.'
          : '진료시간과 관계없이 주변 병원을 표시합니다.',
  };

  // 함수이름: noOpenPharmacy
  // 함수역할: 현재 진료 결과가 없을 때 달력 미확인·불완전 조회를 우선 안내한다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get noOpenPharmacy => calendarUnknown
      ? _consultationUnavailable
      : _incompleteCoverage
      ? _noPartialMatches
      : isEnglish
      ? 'No open hospitals were found in this search area'
      : '검색한 지역에 진료 중인 병원이 없습니다';
  // 함수이름: noLateNightPharmacy
  // 함수역할: 저녁 진료 결과가 없을 때 달력 미확인·불완전 조회를 우선 안내한다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get noLateNightPharmacy => calendarUnknown
      ? _consultationUnavailable
      : _incompleteCoverage
      ? _noPartialMatches
      : isEnglish
      ? 'No hospitals with consultation hours after 6 PM were found in this search area'
      : '검색한 지역에 오후 6시 이후 진료하는 병원이 없습니다';
  // 함수이름: noWeekendHolidayPharmacy
  // 함수역할: 주말 진료 결과가 없을 때 평일 날짜 선택·달력 미확인·불완전 조회를 구분한다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get noWeekendHolidayPharmacy => requiresWeekendDate
      ? _chooseWeekendDate
      : calendarUnknown
      ? _consultationUnavailable
      : _incompleteCoverage
      ? _noPartialMatches
      : isEnglish
      ? 'No hospitals with weekend or holiday hours were found in this search area'
      : '검색한 지역에 주말·공휴일 진료 병원이 없습니다';
  // 함수이름: noNearbyPharmacy
  // 함수역할: 전체 병원 결과가 없을 때 불완전 조회를 병원 부재로 단정하지 않는다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get noNearbyPharmacy => _incompleteCoverage
      ? _noPartialMatches
      : isEnglish
      ? 'No nearby hospitals were found'
      : '주변 병원을 찾지 못했습니다';
  // 함수이름: tryAllPharmacies
  // 함수역할: 평일로 조회한 주말 조건은 날짜 변경을, 그 외에는 전체 병원·진료과 변경을 안내한다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get tryAllPharmacies => requiresWeekendDate
      ? (isEnglish
            ? 'The selected date is a weekday. Choose the weekend or public holiday you plan to visit.'
            : '선택한 날짜는 평일입니다. 방문할 주말이나 공휴일로 조회 날짜를 바꿔주세요.')
      : isEnglish
      ? 'Switch to all hospitals, change the specialty, or try again shortly.'
      : '전체 병원으로 전환하거나 진료과목을 바꿔 다시 확인해주세요.';
  // 함수이름: showAll
  // 함수역할: 전체 병원으로 조건을 바꾸는 명령를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get showAll => isEnglish ? 'Show all hospitals' : '전체 병원 보기';
  // 함수이름: mapInstruction
  // 함수역할: 지도 표시 또는 병원 목록으로 상세를 여는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get mapInstruction => isEnglish
      ? 'Tap a marker or open the hospital list for details'
      : '지도 표시를 누르거나 병원 목록을 열어 상세 정보를 확인하세요';
  // 함수이름: selectMarkerHint
  // 함수역할: 선택 병원을 지도에서 보는 접근성 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get selectMarkerHint =>
      isEnglish ? 'Show this hospital on the map' : '이 병원을 지도에서 보기';
  // 함수이름: mapUnavailable
  // 함수역할: 지도에 표시할 병원 좌표가 없다는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get mapUnavailable => isEnglish
      ? 'Map coordinates are unavailable for these hospitals.'
      : '표시할 수 있는 병원 좌표가 없습니다.';
  // 함수이름: findingNearby
  // 함수역할: 검색 위치 주변 병원 조회 진행 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get findingNearby => isEnglish
      ? 'Finding hospitals near the search location'
      : '검색 위치 주변 병원을 찾고 있습니다';
  // 함수이름: addressCopied
  // 함수역할: 병원 주소 복사 완료 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get addressCopied =>
      isEnglish ? 'The hospital address was copied.' : '병원 주소를 복사했습니다.';
  // 함수이름: mapUnavailableAddressCopied
  // 함수역할: 지도 앱 대신 병원 주소를 복사했다는 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get mapUnavailableAddressCopied => isEnglish
      ? 'No map app could be opened, so the address was copied.'
      : '열 수 있는 지도 앱이 없어 병원 주소를 복사했습니다.';
  // 함수이름: favoriteSaveFailed
  // 함수역할: 병원 즐겨찾기 저장 실패 안내를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get favoriteSaveFailed => isEnglish
      ? 'Could not save the hospital favorite.'
      : '병원 즐겨찾기를 저장하지 못했습니다.';
  // 함수이름: showList
  // 함수역할: 병원 목록 버튼에 조회 결과 수를 표시한다.
  // 매개변수: count (int): 병원 수.
  // 반환값: 현재 언어의 목록 버튼 문구.
  @override
  String showList(int count) =>
      isEnglish ? 'Hospitals ($count)' : '병원 목록 보기 ($count)';
  // 함수이름: closeDetails
  // 함수역할: 병원 상세 닫기 접근성 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  @override
  String get closeDetails => isEnglish ? 'Close hospital details' : '병원 정보 닫기';
  // 함수이름: noMapMatches
  // 함수역할: 지도 결과가 없을 때 날짜·달력·조회 범위 한계를 먼저 설명한다.
  // 매개변수: 없음.
  // 반환값: 상태에 맞는 현재 언어 안내.
  @override
  String get noMapMatches => requiresWeekendDate
      ? _chooseWeekendDate
      : calendarUnknown
      ? _consultationUnavailable
      : _incompleteCoverage
      ? _noPartialMatches
      : isEnglish
      ? 'No hospitals match here. Move the map or change the filters.'
      : '조건에 맞는 병원이 없어요. 지도를 옮기거나 조회 조건을 바꿔보세요.';

  // Function Name: todayHours
  // Description: Formats hospital consultation hours, distinguishing 24-hour schedules, missing times and selected-date wording.
  // Parameters: pharmacy (NearbyCarePlace): hospital data; usesSelectedTime (bool): selected-date rather than today label.
  // Returns: Localized hours or a request to verify them.
  @override
  String todayHours(NearbyCarePlace pharmacy, {bool usesSelectedTime = false}) {
    if (pharmacy.is24Hours) {
      return isEnglish ? '24-hour consultation schedule' : '24시간 진료 일정';
    }
    if (pharmacy.todayOpenTime == null || pharmacy.todayCloseTime == null) {
      return usesSelectedTime
          ? (isEnglish
                ? 'Check search-date consultation hours'
                : '조회일 진료시간 확인 필요')
          : (isEnglish ? "Check today's consultation hours" : '오늘 진료시간 확인 필요');
    }
    return super.todayHours(pharmacy, usesSelectedTime: usesSelectedTime);
  }

  // Function Name: scheduleTags
  // Description: Lists only late and weekend/holiday consultation tags, excluding pharmacy-specific public-night designations.
  // Parameters: pharmacy (NearbyCarePlace): hospital schedule flags.
  // Returns: Joined localized tags, or empty text when none apply.
  @override
  String scheduleTags(NearbyCarePlace pharmacy) => [
    if (pharmacy.isOpenLate) lateHours,
    if (pharmacy.hasWeekendOrHolidayHours) weekendHoliday,
  ].join(' · ');

  // Function Name: operatingStatusDetail
  // Description: Reuses shared operating-time calculations and substitutes Korean consultation terminology.
  // Parameters: pharmacy (NearbyCarePlace): hospital operating data.
  // Returns: Localized detail, or null when no detail is available.
  @override
  String? operatingStatusDetail(NearbyCarePlace pharmacy) {
    final detail = super.operatingStatusDetail(pharmacy);
    return isEnglish ? detail : detail?.replaceAll('영업', '진료');
  }

  // 함수이름: sourceNotice
  // 함수역할: 병원 공공데이터 한계·방문 전 확인을 안내하고 오래된 자료·지역 추정 경고를 덧붙인다.
  // 매개변수: catalogIsStale (bool): 자료 노후 여부; holidayScheduleStatus (String): 공통 계약 인수로 이 재정의에서는 사용하지 않음.
  // 반환값: 현재 언어의 출처·제한 안내.
  @override
  String sourceNotice({
    required bool catalogIsStale,
    required String holidayScheduleStatus,
  }) {
    final warning = catalogIsStale
        ? (isEnglish
              ? ' Cached hospital information may be out of date.'
              : ' 저장된 병원 정보가 오래되었을 수 있습니다.')
        : '';
    final base = isEnglish
        ? 'Based on National Emergency Medical Center public hospital data. Reported consultation hours may differ on holidays or when appointments close. Call before visiting to confirm the specialty and actual consultation hours.'
        : '국립중앙의료원 병원 공공데이터를 기준으로 표시합니다. 공휴일·접수 마감 등에 따라 신고 진료시간과 다를 수 있으니 방문 전 전화로 진료과목과 실제 진료 여부를 확인해주세요.';
    final scope = regionScopeUncertain
        ? (isEnglish
              ? ' Search regions are inferred from nearby addresses; hospitals across administrative boundaries may be missing.'
              : ' 주변 주소로 검색 지역을 파악하므로 행정구역 경계의 일부 병원이 누락될 수 있습니다.')
        : '';
    return '$base$warning$scope';
  }
}
