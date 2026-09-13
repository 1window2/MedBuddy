// 파일명: check_nearby_pharmacy_ui_boundary.dart
// 역할: 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유를 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/check_nearby_pharmacy_control.dart';
import '../entities/nearby_pharmacy_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/device_location_service.dart';
import '../services/pharmacy_favorite_service.dart';
import '../theme/medbuddy_theme.dart';
import 'nearby_pharmacy_map_widget.dart';

part 'pharmacy_details_sheet.dart';

// 클래스명: _PharmacyFilter
// 역할: 현재 영업·심야·주말공휴일·전체 약국 조회 조건을 담당한다.
// 주요 책임:
// - 현재 영업·심야·주말공휴일·전체 약국 조회 조건에서 지원하는 선택지를 열거하고 구분한다: openNow, lateHours, weekendHoliday, all.
enum _PharmacyFilter { openNow, lateHours, weekendHoliday, all }

// 클래스명: _PharmacyDirectionsChoice
// 역할: 설치 지도 앱·Google 지도·주소 복사 경로를 담당한다.
// 주요 책임:
// - 설치 지도 앱·Google 지도·주소 복사 경로에서 지원하는 선택지를 열거하고 구분한다: installedMapApp, googleMaps, copyAddress.
enum _PharmacyDirectionsChoice { installedMapApp, googleMaps, copyAddress }

const _refreshCooldownDuration = Duration(seconds: 10);

// 클래스명: NearbyPharmacySelection
// 역할: 채팅에 공유할 약국과 사용자의 전화 확인 여부를 함께 반환한다.
// 주요 책임:
// - 선택한 약국과 사용자의 전화 확인 여부를 하나의 화면 반환값으로 보존한다.
// - 채팅 공유 호출자가 약국 정보와 확인 상태를 함께 받게 한다.
// 속성:
// - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
// - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
class NearbyPharmacySelection {
  final NearbyPharmacy pharmacy;
  final bool phoneVerified;

  // 함수이름: NearbyPharmacySelection
  // 함수역할: 채팅 공유 호출자에게 돌려줄 약국과 전화 확인 여부를 변경 불가능한 결과 객체에 담는다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // - phoneVerified (bool): 사용자가 전화로 운영 여부를 확인했는지 여부.
  // 반환값: 입력 설정이 반영된 NearbyPharmacySelection 인스턴스.
  const NearbyPharmacySelection({
    required this.pharmacy,
    required this.phoneVerified,
  });
}

// 타입명: NearbyPharmacyMapBuilder
// 역할: 지도 구현을 화면의 목록·필터 로직과 분리하고 테스트 대체 지점을 제공한다.
// 함수이름: NearbyPharmacyMapBuilder
// 함수역할: 약국 목록·선택 상태·지도 동작과 오류 문구를 전달받아 대체 지도를 구성하는 콜백 계약이다.
// 매개변수:
// - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
// - selectedPharmacyId (String?): 공유하거나 지도에서 선택한 약국 ID.
// - onPharmacySelected (ValueChanged<NearbyPharmacy>): 목록·마커에서 선택한 약국을 전달할 콜백.
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
      required PharmacySearchArea searchArea,
      required int centerRevision,
      required bool isSearching,
      required Future<bool> Function(PharmacySearchArea) onSearchAreaRequested,
      required VoidCallback onCurrentLocationRequested,
      required List<NearbyPharmacy> pharmacies,
      required String? selectedPharmacyId,
      required ValueChanged<NearbyPharmacy> onPharmacySelected,
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
// - control (CheckNearbyPharmacy?): 화면의 조회·변경 요청을 처리할 컨트롤러.
// - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
// - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
// - selectionMode (bool): 일반 검색(false) 또는 약국·전화 확인 여부를 반환하는 채팅 공유 선택(true) 모드.
class CheckNearbyPharmacyUI extends StatefulWidget {
  final UserSetting userSetting;
  final CheckNearbyPharmacy? control;
  final NearbyPharmacyMapBuilder? mapBuilder;
  final PharmacyFavoriteService? favoriteService;
  final bool selectionMode;
  final DateTime Function()? clock;

  // 함수이름: CheckNearbyPharmacyUI
  // 함수역할: 주입된 검색·지도·즐겨찾기 의존성으로 일반 약국 검색 화면을 구성하고 선택 모드는 끈다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (CheckNearbyPharmacy?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
  // - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
  // 반환값: 입력 설정이 반영된 CheckNearbyPharmacyUI 인스턴스.
  const CheckNearbyPharmacyUI({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
    this.clock,
  }) : selectionMode = false;

  // 함수이름: CheckNearbyPharmacyUI.selection
  // 함수역할: 약국과 전화 확인 여부를 채팅 공유 호출자에게 반환하도록 선택 모드를 켠 약국 검색 화면을 구성한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - control (CheckNearbyPharmacy?): 화면의 조회·변경 요청을 처리할 컨트롤러.
  // - mapBuilder (NearbyPharmacyMapBuilder?): 약국 목록과 선택 상태로 지도 위젯을 만드는 주입 함수.
  // - favoriteService (PharmacyFavoriteService?): 사용자별 약국 즐겨찾기 저장소.
  // 반환값: 입력 설정이 반영된 CheckNearbyPharmacyUI 인스턴스.
  const CheckNearbyPharmacyUI.selection({
    super.key,
    required this.userSetting,
    this.control,
    this.mapBuilder,
    this.favoriteService,
    this.clock,
  }) : selectionMode = true;

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
// - _pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
// - _isLoading (bool): 진행 중 표시를 보여줄지 여부.
class _CheckNearbyPharmacyUIState extends State<CheckNearbyPharmacyUI>
    with WidgetsBindingObserver {
  late final CheckNearbyPharmacy _control;
  late final bool _ownsControl;
  late final PharmacyFavoriteService _favoriteService;
  List<NearbyPharmacy> _pharmacies = const [];
  Set<String> _favoritePharmacyIds = const {};
  DeviceLocationFailure? _locationFailure;
  DeviceCoordinate? _deviceLocation;
  String? _errorMessage;
  bool _isLoading = true;
  bool _listExpanded = false;
  double _detailExtent = _PharmacyDetailsSheet.initialExtent;
  bool _isRefreshCoolingDown = false;
  Timer? _refreshCooldownTimer;
  _PharmacyFilter _filter = _PharmacyFilter.openNow;
  String? _selectedPharmacyId;
  DateTime _targetDateTime = DateTime.now();
  bool _hasSelectedSearchDate = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  bool _catalogIsStale = false;
  String _holidayScheduleStatus = 'not_applicable';
  DateTime? _lastRefreshedAt;
  bool _selectedPhoneVerified = false;
  PharmacySearchArea? _searchArea;
  int _searchGeneration = 0;
  int _centerRevision = 0;
  bool _wasBackgrounded = false;
  bool _resumeRefreshPending = false;
  DateTime? _lastSearchStartedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final now = _now();
    final previous = _lastSearchStartedAt;
    final stale =
        previous == null ||
        now.isBefore(previous) ||
        now.difference(previous) >= const Duration(minutes: 1) ||
        now.year != previous.year ||
        now.month != previous.month ||
        now.day != previous.day;
    if (!stale && _errorMessage == null && _locationFailure == null) return;
    if (_isLoading) {
      _resumeRefreshPending = true;
    } else {
      unawaited(_loadPharmacies());
    }
  }

  // 함수이름: _text
  // 함수역할: 현재 언어에 맞는 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유 문구 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: _NearbyPharmacyText: 현재 화면 언어의 문구 제공 객체.
  _NearbyPharmacyText get _text =>
      _NearbyPharmacyText(widget.userSetting.language);

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
    _control = widget.control ?? CheckNearbyPharmacy();
    _favoriteService =
        widget.favoriteService ??
        PharmacyFavoriteService(userHash: widget.userSetting.userHash);
    // 함수이름: initState.addPostFrameCallback callback
    // 함수역할: 현재 사용자의 저장된 약국 즐겨찾기를 화면 선택 집합에 반영한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadFavorites());
      unawaited(_loadPharmacies());
    });
  }

  // 함수이름: dispose
  // 함수역할: _refreshCooldownTimer, _control 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshCooldownTimer?.cancel();
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
    PharmacySearchArea? searchArea,
    bool locate = false,
  }) async {
    if (!mounted) {
      return false;
    }
    final generation = ++_searchGeneration;
    _lastSearchStartedAt = _now();
    _resumeRefreshPending = false;
    final requestedArea = searchArea ?? (locate ? null : _searchArea);
    // Only an explicitly chosen calendar date survives a later search.
    if (!_hasSelectedSearchDate) {
      _targetDateTime = _now();
    }
    // 함수이름: _loadPharmacies.setState callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_isLoading = true; _locationFailure = null; _errorMessage = null`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _isLoading = true;
      _locationFailure = null;
      _errorMessage = null;
    });
    try {
      final result = await _control.requestNearbyPharmacySearch(
        searchArea: requestedArea,
        searchMode: _searchModeForFilter(_filter),
        targetDateTime: _targetDateTime,
      );
      if (!mounted || generation != _searchGeneration) {
        return false;
      }
      // 함수이름: _loadPharmacies.setState callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_pharmacies = result.data; _catalogIsStale = result.catalogIsStale; _holidayScheduleStatus = result.holidayScheduleStatus`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _searchArea =
            result.searchArea ?? requestedArea ?? PharmacySearchArea.hongik;
        if (!_searchArea!.isFallback && !_searchArea!.isMapArea) {
          _deviceLocation = _searchArea!.center;
        } else if (_searchArea!.isFallback) {
          _deviceLocation = null;
        }
        if (locate) _centerRevision++;
        if (searchArea != null || locate) {
          _selectedPharmacyId = null;
          _selectedPhoneVerified = false;
        }
        _pharmacies = result.data;
        _catalogIsStale = result.catalogIsStale;
        _holidayScheduleStatus = result.holidayScheduleStatus;
        final selectedStillExists = result.data.any(
          // 함수이름: _loadPharmacies.any callback
          // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 대해 `pharmacy.pharmacyId == _selectedPharmacyId` 조건으로 컬렉션 항목을 판별한다.
          // 매개변수:
          // - pharmacy (콜백 계약에서 추론): 표시하거나 전화·길찾기·공유할 약국.
          // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
          (pharmacy) => pharmacy.pharmacyId == _selectedPharmacyId,
        );
        if (!selectedStillExists) {
          _selectedPharmacyId = null;
          _selectedPhoneVerified = false;
        }
        _lastRefreshedAt = _now();
      });
      return true;
    } on DeviceLocationException catch (error) {
      if (mounted && generation == _searchGeneration) {
        // 함수이름: _loadPharmacies.setState callback
        // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_locationFailure = error.failure`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() => _locationFailure = error.failure);
      }
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        // 함수이름: _loadPharmacies.setState callback
        // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_errorMessage = _text.loadFailed`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _errorMessage = _text.loadFailed;
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

  // 함수이름: _searchMapArea
  // 함수역할: 지도 중심·반경을 현재 영업 조건으로 조회한다. 매개변수: area. 반환값: 갱신 성공 여부.
  Future<bool> _searchMapArea(PharmacySearchArea area) async {
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
      _showActionFailure(_text.loadingAction);
      return;
    }
    if (_isRefreshCoolingDown) {
      _showActionFailure(_text.refreshLimited);
      return;
    }

    _isRefreshCoolingDown = true;
    if (_filter == _PharmacyFilter.openNow) {
      _targetDateTime = DateTime.now();
    }
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

  // 함수이름: _visiblePharmacies
  // 함수역할: 영업 중·심야 운영·즐겨찾기·거리 순으로 약국 사본을 정렬한다.
  // 매개변수:
  // - 없음.
  // 반환값: List<NearbyPharmacy>: 조회 또는 좌표 조건을 반영한 지도·목록용 약국 목록.
  List<NearbyPharmacy> get _visiblePharmacies {
    final visiblePharmacies = List<NearbyPharmacy>.of(_pharmacies);
    // 함수이름: _visiblePharmacies.sort callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 정렬 비교값을 `leftOpenRank.compareTo(rightOpenRank); leftLateRank.compareTo(rightLateRank); leftFavorite ? -1 : 1` 규칙으로 계산한다.
    // 매개변수:
    // - left (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
    // - right (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
    // 반환값: 컬렉션 연산에 전달할 정렬 비교값.
    visiblePharmacies.sort((left, right) {
      final leftOpenRank = left.isOpenNow == true ? 0 : 1;
      final rightOpenRank = right.isOpenNow == true ? 0 : 1;
      if (leftOpenRank != rightOpenRank) {
        return leftOpenRank.compareTo(rightOpenRank);
      }
      final leftLateRank = _operatesLate(left) ? 0 : 1;
      final rightLateRank = _operatesLate(right) ? 0 : 1;
      if (leftLateRank != rightLateRank) {
        return leftLateRank.compareTo(rightLateRank);
      }
      final leftFavorite = _favoritePharmacyIds.contains(left.pharmacyId);
      final rightFavorite = _favoritePharmacyIds.contains(right.pharmacyId);
      if (leftFavorite != rightFavorite) {
        return leftFavorite ? -1 : 1;
      }
      return left.distanceKm.compareTo(right.distanceKm);
    });
    return visiblePharmacies;
  }

  // 함수이름: _operatesLate
  // 함수역할: 24시간 운영·늦은 영업·공식 심야 지정 중 하나라도 해당하는지 확인한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool _operatesLate(NearbyPharmacy pharmacy) {
    return pharmacy.is24Hours ||
        pharmacy.isOpenLate ||
        pharmacy.isOfficialLateNight;
  }

  // 함수이름: _loadFavorites
  // 함수역할: 현재 사용자의 저장된 약국 즐겨찾기를 화면 선택 집합에 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _loadFavorites() async {
    final favoriteIds = await _favoriteService.loadFavoriteIds();
    if (mounted) {
      // 함수이름: _loadFavorites.setState callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_favoritePharmacyIds = favoriteIds`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _favoritePharmacyIds = favoriteIds);
    }
  }

  // 함수이름: _toggleFavorite
  // 함수역할: 즐겨찾기를 즉시 전환하고 저장 실패 시 해당 변경을 되돌려 안내한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _toggleFavorite(NearbyPharmacy pharmacy) async {
    final updatedIds = Set<String>.of(_favoritePharmacyIds);
    final isFavorite = updatedIds.remove(pharmacy.pharmacyId);
    if (!isFavorite) {
      updatedIds.add(pharmacy.pharmacyId);
    }
    // 함수이름: _toggleFavorite.setState callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_favoritePharmacyIds = updatedIds`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() => _favoritePharmacyIds = updatedIds);
    if (!await _favoriteService.saveFavoriteIds(updatedIds) && mounted) {
      final restoredIds = Set<String>.of(_favoritePharmacyIds);
      if (isFavorite) {
        restoredIds.add(pharmacy.pharmacyId);
      } else {
        restoredIds.remove(pharmacy.pharmacyId);
      }
      // 함수이름: _toggleFavorite.setState callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_favoritePharmacyIds = restoredIds`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _favoritePharmacyIds = restoredIds);
      _showActionFailure(_text.favoriteSaveFailed);
    }
  }

  // Function Name: _searchModeForFilter
  // Description: Maps the visible operating-hours filter to the pharmacy controller's search mode.
  // Parameters:
  // - filter (_PharmacyFilter): Pharmacy operating-hours filter to apply.
  // Returns: PharmacySearchMode: Controller search mode corresponding to the visible filter.
  PharmacySearchMode _searchModeForFilter(_PharmacyFilter filter) {
    return switch (filter) {
      _PharmacyFilter.openNow => PharmacySearchMode.openAtTime,
      _PharmacyFilter.lateHours => PharmacySearchMode.lateHours,
      _PharmacyFilter.weekendHoliday => PharmacySearchMode.weekendHoliday,
      _PharmacyFilter.all => PharmacySearchMode.all,
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
      if (nextFilter == _PharmacyFilter.openNow) {
        _hasSelectedSearchDate = false;
        _targetDateTime = _now();
      }
    });
    await _loadPharmacies();
  }

  // 함수이름: _showFilterPicker
  // 함수역할: 약국 조회 조건 시트를 열고 취소·동일 선택을 제외한 변경을 적용한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showFilterPicker() async {
    final selectedFilter = await showModalBottomSheet<_PharmacyFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      // 함수이름: _showFilterPicker.builder callback
      // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 EdgeInsets.fromLTRB, TextStyle, SizedBox, Icon, Divider을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text.filterPickerTitle,
                            style: const TextStyle(
                              color: MedBuddyColors.textStrong,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _text.filterPickerDescription,
                            style: const TextStyle(
                              color: MedBuddyColors.textMuted,
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _text.close,
                      // 함수이름: _showFilterPicker.onPressed callback
                      // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _PharmacyFilter.values.length,
                  // 함수이름: _showFilterPicker.separatorBuilder callback
                  // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 인접 항목 사이에 지정한 간격 또는 구분선을 배치한다.
                  // 매개변수:
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  // 함수이름: _showFilterPicker.itemBuilder callback
                  // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도에 EdgeInsets.symmetric, SizedBox, TextStyle을 적용해 현재 배치를 구성한다.
                  // 매개변수:
                  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
                  // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                  itemBuilder: (context, index) {
                    final filter = _PharmacyFilter.values[index];
                    final isSelected = filter == _filter;
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: Material(
                        color: isSelected
                            ? MedBuddyColors.successSurface
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? MedBuddyColors.primary
                                : MedBuddyColors.outline,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          key: ValueKey(
                            'pharmacy-filter-option-${filter.name}',
                          ),
                          borderRadius: BorderRadius.circular(8),
                          // 함수이름: _showFilterPicker.onTap callback
                          // 함수역할: `Navigator.pop(sheetContext, filter)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                          onTap: () => Navigator.pop(sheetContext, filter),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? MedBuddyColors.primary
                                      : MedBuddyColors.textSubtle,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _filterLabel(filter),
                                        style: const TextStyle(
                                          color: MedBuddyColors.textStrong,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _text.filterDescription(filter),
                                        style: const TextStyle(
                                          color: MedBuddyColors.textMuted,
                                          fontSize: 14,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || selectedFilter == null || selectedFilter == _filter) {
      return;
    }
    await _selectFilter(selectedFilter);
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

  // 함수이름: _pickSearchDate
  // 함수역할: 조회 날짜를 선택받아 정오를 기준 시각으로 지정하고 약국을 다시 찾는다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _pickSearchDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _targetDateTime,
      firstDate: today.subtract(const Duration(days: 7)),
      lastDate: today.add(const Duration(days: 366)),
    );
    if (selected == null || !mounted) {
      return;
    }
    // 함수이름: _pickSearchDate.setState callback
    // 함수역할: 위치 권한·조회 조건에 따른 약국 목록과 지도의 입력·요청 상태를 `_targetDateTime = DateTime(selected.year, selected.month, selected.day, 12, 0)`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _hasSelectedSearchDate = true;
      _targetDateTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        12,
        0,
      );
    });
    await _loadPharmacies();
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

  // 함수이름: _handleBack
  // 함수역할: 목록, 선택 정보창, 약국 화면 순서로 닫는다.
  // 매개변수: 없음. 반환값: 없음.
  void _handleBack() {
    if (_listExpanded) {
      setState(() {
        _listExpanded = false;
        _detailExtent = _PharmacyDetailsSheet.initialExtent;
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
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 14,
        18,
        20,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: text.back,
            // 함수이름: _buildHeader.onPressed callback
            // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  text.subtitle,
                  maxLines: 2,
                  style: TextStyle(
                    color: Color(0xFFE7FFF5),
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: text.refreshTooltip,
            onPressed: _requestRefresh,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  // 함수이름: _buildMapFirstBody
  // 함수역할: 지도를 유지하면서 목록 또는 접이식 상세창과 목록 전환 버튼을 배치한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  Widget _buildMapFirstBody() {
    final pharmacies = _visiblePharmacies;
    final selected = _findSelectedPharmacy(pharmacies);
    if (_searchArea == null) {
      return _buildBody();
    }
    final english = widget.userSetting.language.toLowerCase().startsWith('en');
    return Column(
      children: [
        if (_searchArea!.isFallback ||
            _searchArea!.isMapArea ||
            _errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Text(
              _errorMessage != null
                  ? (english
                        ? 'Search failed. Move the map to try again, or refresh.'
                        : '검색하지 못했어요. 지도를 옮겨 다시 검색하거나 새로고침해주세요.')
                  : _searchArea!.isFallback
                  ? (english
                        ? 'Location unavailable. Searching near Hongik University, Seoul.'
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showDetails = !_listExpanded && selected != null;
              final minimumExtent = _PharmacyDetailsSheet.minimumExtent(
                context,
                constraints.maxHeight,
              );
              final bottomInset = showDetails
                  ? constraints.maxHeight *
                        _detailExtent.clamp(minimumExtent, .92)
                  : 0.0;
              return Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      excluding: _listExpanded || _isLoading,
                      child: IgnorePointer(
                        ignoring: _listExpanded || _isLoading,
                        child: _buildPharmacyMap(
                          pharmacies,
                          bottomInset: bottomInset,
                          showControls:
                              constraints.maxHeight - bottomInset >= 128,
                        ),
                      ),
                    ),
                  ),
                  if (showDetails)
                    _PharmacyDetailsSheet(
                      key: ValueKey(
                        'pharmacy-sheet-${selected.pharmacyId}-$_centerRevision',
                      ),
                      minimumSize: minimumExtent,
                      isEnglish: english,
                      onExtentChanged: (extent) {
                        if ((_detailExtent - extent).abs() > .001) {
                          setState(() => _detailExtent = extent);
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
                              selected.pharmacyId,
                            ),
                            embedded: true,
                            compact: compact,
                            onClose: _closePharmacyDetails,
                            onSelected: () => _selectPharmacy(selected),
                            onFavoriteRequested: () =>
                                _toggleFavorite(selected),
                            onPhoneRequested: selected.telephone.isEmpty
                                ? null
                                : () => _requestPhoneCall(selected),
                            onDirectionsRequested: () =>
                                _requestDirections(selected),
                          ),
                          if (widget.selectionMode)
                            _buildSelectionFooter(pharmacies),
                        ],
                      ),
                    ),
                  if (_listExpanded)
                    Positioned.fill(
                      child: Material(
                        key: const Key('pharmacy-list-panel'),
                        elevation: 8,
                        color: MedBuddyColors.pageBackground,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildBody(),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                      _listExpanded = !_listExpanded;
                      _detailExtent = _PharmacyDetailsSheet.initialExtent;
                    }),
              icon: Icon(_listExpanded ? Icons.map_outlined : Icons.list_alt),
              label: Text(
                _listExpanded
                    ? (english ? 'Show map' : '지도 크게 보기')
                    : (english
                          ? 'Show pharmacies (${pharmacies.length})'
                          : '약국 목록 보기 (${pharmacies.length})'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final text = _text;
    if (_isLoading) {
      return _PharmacyLoadingState(message: text.findingNearby);
    }
    if (_locationFailure != null) {
      return _buildLocationFailure(_locationFailure!);
    }
    if (_errorMessage != null) {
      return _PharmacyMessageState(
        icon: Icons.cloud_off_outlined,
        title: text.unavailableTitle,
        message: _errorMessage!,
        actionLabel: text.retry,
        onAction: _requestRefresh,
      );
    }

    final visiblePharmacies = _visiblePharmacies;
    return Column(
      children: [
        if (_lastRefreshedAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.update_outlined,
                  size: 17,
                  color: MedBuddyColors.textSubtle,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text.refreshedAt(_lastRefreshedAt!),
                    style: const TextStyle(
                      color: MedBuddyColors.textSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Text(
                  text.callBeforeVisit,
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
              if (_filter != _PharmacyFilter.openNow) ...[
                OutlinedButton.icon(
                  key: const Key('pharmacy-search-date'),
                  onPressed: _pickSearchDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(text.searchDate(_targetDateTime)),
                ),
                const SizedBox(height: 8),
              ],
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_alt_outlined,
                        color: MedBuddyColors.primaryDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text.selectedFilter(_filterLabel(_filter)),
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
        Expanded(
          child: visiblePharmacies.isEmpty
              ? _PharmacyMessageState(
                  icon: Icons.local_pharmacy_outlined,
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
                  actionLabel: _filter == _PharmacyFilter.all
                      ? text.refresh
                      : text.showAll,
                  onAction: _filter == _PharmacyFilter.all
                      ? _requestRefresh
                      // Function Name: _buildBody.onAction callback
                      // Description: Clears pharmacy selection after changing the search filter and reloads matching results.
                      // Parameters:
                      // - None.
                      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                      : () => _selectFilter(_PharmacyFilter.all),
                )
              : ListView.separated(
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
                      isSelected: pharmacy.pharmacyId == _selectedPharmacyId,
                      isFavorite: _favoritePharmacyIds.contains(
                        pharmacy.pharmacyId,
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
                      onFavoriteRequested: () => _toggleFavorite(pharmacy),
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
                      onDirectionsRequested: () => _requestDirections(pharmacy),
                    );
                  },
                ),
        ),
        if (widget.selectionMode && _selectedPharmacyId != null)
          _buildSelectionFooter(visiblePharmacies),
      ],
    );
  }

  // 함수이름: _buildSelectionFooter
  // 함수역할: 선택한 약국의 전화 확인 체크와 채팅 공유 확정 버튼을 표시한다.
  // 매개변수:
  // - visiblePharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  Widget _buildSelectionFooter(List<NearbyPharmacy> visiblePharmacies) {
    final selectedPharmacy = _findSelectedPharmacy(visiblePharmacies);
    if (selectedPharmacy == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedPharmacy.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
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
                title: Text(_text.phoneVerified),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // 함수이름: _buildSelectionFooter.onPressed callback
                  // 함수역할: `Navigator.pop(context, NearbyPharmacySelection(pharmacy: selectedPharmacy, phoneVerified: _selectedPhoneVerified))`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onPressed: () {
                    Navigator.pop(
                      context,
                      NearbyPharmacySelection(
                        pharmacy: selectedPharmacy,
                        phoneVerified: _selectedPhoneVerified,
                      ),
                    );
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_text.shareInChat),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildPharmacyMap
  // 함수역할: 주입된 지도 빌더 또는 기본 네이버 지도를 약국 목록·선택 상태에 연결한다.
  // 매개변수:
  // - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  Widget _buildPharmacyMap(
    List<NearbyPharmacy> pharmacies, {
    double bottomInset = 0,
    bool showControls = true,
  }) {
    final text = _text;
    final selectedPharmacy = _findSelectedPharmacy(pharmacies);
    final statusText = pharmacies.isEmpty
        ? (text.isEnglish
              ? 'No pharmacies match here. Move the map or change the filter.'
              : '조건에 맞는 약국이 없어요. 지도를 옮기거나 조회 조건을 바꿔보세요.')
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
        onPharmacySelected: _selectMapPharmacy,
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
      locationFailureText: text.isEnglish
          ? 'Could not find your location. Check location permission and GPS settings.'
          : '현재 위치를 확인할 수 없습니다. 위치 권한과 GPS 설정을 확인해 주세요.',
      pharmacies: pharmacies,
      selectedPharmacyId: _selectedPharmacyId,
      onPharmacySelected: _selectMapPharmacy,
      onAttributionRequested: _requestMapAttribution,
      statusText: statusText,
      selectMarkerHint: text.selectMarkerHint,
      zoomInTooltip: text.zoomInTooltip,
      zoomOutTooltip: text.zoomOutTooltip,
      configurationUnavailableText: text.mapConfigurationUnavailable,
      unavailableText: text.mapUnavailable,
    );
  }

  // 함수이름: _selectMapPharmacy
  // 함수역할: 마커 선택을 목록과 같은 지도 상세 보기 동작으로 연결한다.
  // 매개변수: pharmacy: 선택한 약국. 반환값: 없음.
  void _selectMapPharmacy(NearbyPharmacy pharmacy) {
    _selectPharmacy(pharmacy);
  }

  // 함수이름: _findSelectedPharmacy
  // 함수역할: 현재 선택 ID에 해당하는 약국을 찾는다.
  // 매개변수: pharmacies: 검색 결과. 반환값: 선택한 약국 또는 null.
  NearbyPharmacy? _findSelectedPharmacy(List<NearbyPharmacy> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.pharmacyId == _selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  // 함수이름: _selectPharmacy
  // 함수역할: 선택한 약국 위치로 지도를 이동하고 상세창을 펼치며 다른 약국이면 전화 확인을 지운다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _selectPharmacy(NearbyPharmacy pharmacy) {
    // 함수이름: _selectPharmacy.setState callback
    // 함수역할: 약국 선택과 지도 이동 요청을 함께 반영하고 목록 대신 상세창을 연다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      if (_selectedPharmacyId != pharmacy.pharmacyId) {
        _selectedPhoneVerified = false;
      }
      _selectedPharmacyId = pharmacy.pharmacyId;
      _listExpanded = false;
      _detailExtent = _PharmacyDetailsSheet.initialExtent;
      _centerRevision++;
    });
  }

  // 함수이름: _buildLocationFailure
  // 함수역할: 위치 서비스·권한·위치 확인 실패 유형에 맞는 복구 버튼과 안내를 표시한다.
  // 매개변수:
  // - failure (DeviceLocationFailure): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // 반환값: 위치 권한·조회 조건에 따른 약국 목록과 지도에 쓰는 위젯 트리.
  Widget _buildLocationFailure(DeviceLocationFailure failure) {
    final text = _text;
    final (title, message, actionLabel, action) = switch (failure) {
      DeviceLocationFailure.serviceDisabled => (
        text.locationDisabledTitle,
        text.locationDisabledMessage,
        text.openLocationSettings,
        _openLocationSettings,
      ),
      DeviceLocationFailure.deniedForever => (
        text.locationBlockedTitle,
        text.locationBlockedMessage,
        text.openAppSettings,
        _openApplicationSettings,
      ),
      DeviceLocationFailure.denied => (
        text.locationPermissionTitle,
        text.locationPermissionMessage,
        text.requestAgain,
        _loadPharmacies,
      ),
      DeviceLocationFailure.unavailable => (
        text.locationUnavailableTitle,
        text.locationUnavailableMessage,
        text.retry,
        _loadPharmacies,
      ),
    };
    return _PharmacyMessageState(
      icon: Icons.location_off_outlined,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: action,
    );
  }

  // 함수이름: _openApplicationSettings
  // 함수역할: 위치 권한을 수정할 수 있도록 앱 설정 열기를 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openApplicationSettings() async {
    await _control.openApplicationSettings();
  }

  // 함수이름: _openLocationSettings
  // 함수역할: 위치 서비스를 켤 수 있도록 기기 위치 설정 열기를 요청한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _openLocationSettings() async {
    await _control.openDeviceLocationSettings();
  }

  // 함수이름: _requestPhoneCall
  // 함수역할: 약국 전화번호로 전화 앱을 열고 실패 시 안내한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestPhoneCall(NearbyPharmacy pharmacy) async {
    if (!await _control.requestPhoneCall(pharmacy.telephone) && mounted) {
      _showActionFailure(_text.phoneAppFailed);
    }
  }

  // 함수이름: _requestDirections
  // 함수역할: 지도 앱 선택을 처리하고 실행 불가 시 Google 지도와 주소 복사로 대체한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestDirections(NearbyPharmacy pharmacy) async {
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
      builder: (sheetContext) => _PharmacyDirectionsSheet(
        pharmacy: pharmacy,
        text: _text,
        // 함수이름: _requestDirections.onSelected callback
        // 함수역할: `Navigator.of(sheetContext).pop(selected)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
        // 매개변수:
        // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
        // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
        onSelected: (selected) => Navigator.of(sheetContext).pop(selected),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }

    if (choice == _PharmacyDirectionsChoice.copyAddress) {
      await _copyPharmacyAddress(pharmacy, copiedAsFallback: false);
      return;
    }

    var opened = false;
    if (choice == _PharmacyDirectionsChoice.installedMapApp) {
      opened = await _control.requestInstalledMapDirections(pharmacy);
      if (!opened) {
        opened = await _control.requestGoogleMapDirections(pharmacy);
      }
    } else {
      opened = await _control.requestGoogleMapDirections(pharmacy);
    }
    if (!opened && mounted) {
      await _copyPharmacyAddress(pharmacy, copiedAsFallback: true);
    }
  }

  // 함수이름: _copyPharmacyAddress
  // 함수역할: 약국 주소 또는 주소가 없을 때 이름·좌표를 복사하고 대체 동작 여부에 맞게 안내한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // - copiedAsFallback (bool): 지도 앱 실행 실패의 대체 동작으로 주소를 복사했는지 여부.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _copyPharmacyAddress(
    NearbyPharmacy pharmacy, {
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
      _showActionFailure(_text.mapAppFailed);
      return;
    }
    _showActionMessage(
      copiedAsFallback
          ? _text.mapUnavailableAddressCopied
          : _text.addressCopied,
    );
  }

  // 함수이름: _requestMapAttribution
  // 함수역할: 지도 저작권 정보 열기를 요청하고 실패 시 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestMapAttribution() async {
    if (!await _control.requestMapAttribution() && mounted) {
      _showActionFailure(_text.mapAttributionFailed);
    }
  }

  // 함수이름: _showActionFailure
  // 함수역할: 약국 관련 명령 실패 문구를 공통 Snackbar 경로로 전달한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showActionFailure(String message) {
    _showActionMessage(message);
  }

  // 함수이름: _showActionMessage
  // 함수역할: 이전 Snackbar를 닫고 약국 관련 작업 결과를 표시한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// 클래스명: _PharmacyDirectionsSheet
// 역할: 약국 이름과 지도 앱·주소 복사 선택지를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약국 이름과 지도 앱·주소 복사 선택지 위젯을 구성한다.
// 속성:
// - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
// - onSelected (ValueChanged<_PharmacyDirectionsChoice>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _PharmacyDirectionsSheet extends StatelessWidget {
  final NearbyPharmacy pharmacy;
  final _NearbyPharmacyText text;
  final ValueChanged<_PharmacyDirectionsChoice> onSelected;

  // 함수이름: _PharmacyDirectionsSheet
  // 함수역할: 약국 이름과 지도 앱·주소 복사 선택지에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // - text (_NearbyPharmacyText): 해당 화면 구역의 언어별 표시 문구.
  // - onSelected (ValueChanged<_PharmacyDirectionsChoice>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _PharmacyDirectionsSheet 인스턴스.
  const _PharmacyDirectionsSheet({
    required this.pharmacy,
    required this.text,
    required this.onSelected,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 이름과 지도 앱·주소 복사 선택지 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 이름과 지도 앱·주소 복사 선택지에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.directionsSheetTitle,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text.directionsSheetDescription,
            style: const TextStyle(
              color: MedBuddyColors.textBody,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
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
      title: Text(
        title,
        style: const TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      subtitle: Text(
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
          Text(
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

// 클래스명: _PharmacyMessageState
// 역할: 약국 검색 오류·빈 결과와 해당 복구 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약국 검색 오류·빈 결과와 해당 복구 명령 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - title (String): 화면·구역·항목에 표시할 제목.
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - actionLabel (String): 복구 또는 주요 명령의 버튼 문구.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 검색 오류·빈 결과와 해당 복구 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 검색 오류·빈 결과와 해당 복구 명령에 쓰는 위젯 트리.
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
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
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _PharmacyCard
// 역할: 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령 위젯을 구성한다.
// 속성:
// - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
// - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
// - isFavorite (bool): 현재 사용자의 약국 즐겨찾기에 포함되는지 여부.
// - onSelected (VoidCallback): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _PharmacyCard extends StatelessWidget {
  final NearbyPharmacy pharmacy;
  final _NearbyPharmacyText text;
  final bool usesSelectedTime;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onSelected;
  final VoidCallback onFavoriteRequested;
  final VoidCallback? onPhoneRequested;
  final VoidCallback onDirectionsRequested;
  // 상세 정보창에서는 카드 테두리를 없애고 접힌 상태에 맞춰 정보를 줄인다.
  final bool embedded;
  final bool compact;
  final VoidCallback? onClose;

  // 함수이름: _PharmacyCard
  // 함수역할: 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // - text (_NearbyPharmacyText): 해당 화면 구역의 언어별 표시 문구.
  // - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
  // - isFavorite (bool): 현재 사용자의 약국 즐겨찾기에 포함되는지 여부.
  // - onSelected (VoidCallback): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // - onFavoriteRequested (VoidCallback): 약국 즐겨찾기를 전환할 콜백.
  // - onPhoneRequested (VoidCallback?): 해당 약국으로 전화 연결을 요청할 콜백.
  // - onDirectionsRequested (VoidCallback): 해당 약국의 길찾기를 요청할 콜백.
  // - embedded, compact (bool): 정보창 내부 표시와 간략 정보 표시 여부.
  // - onClose (VoidCallback?): 지도 위치를 유지하며 선택 정보를 닫는 콜백.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 운영시간·주소·즐겨찾기와 전화·길찾기 명령에 쓰는 위젯 트리.
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
      child: Text(
        statusLabel,
        style: TextStyle(
          color: statusColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
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
          '${embedded ? 'pharmacy-detail' : 'pharmacy-card'}-${pharmacy.pharmacyId}',
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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pharmacy.name,
                        maxLines: embedded && !compact ? null : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
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
                        tooltip: text.isEnglish
                            ? 'Close pharmacy details'
                            : '약국 정보 닫기',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    if (!embedded) statusBadge,
                  ],
                ),
                const SizedBox(height: 12),
                if (embedded)
                  Wrap(
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
                  if (pharmacy.isOfficialLateNight ||
                      pharmacy.isOpenLate ||
                      pharmacy.hasWeekendOrHolidayHours) ...[
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
                const SizedBox(height: 16),
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
                          'pharmacy-directions-${pharmacy.pharmacyId}',
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
          child: Text(
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
      child: Text(
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

// 클래스명: _NearbyPharmacyText
// 역할: 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _NearbyPharmacyText {
  final String language;

  // 함수이름: _NearbyPharmacyText
  // 함수역할: 위치·운영시간별 약국 검색과 전화·길찾기·채팅 공유에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _NearbyPharmacyText 인스턴스.
  const _NearbyPharmacyText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

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
  String get subtitle => isEnglish
      ? 'Find pharmacies near the search location'
      : '검색 위치 주변의 약국을 확인하세요';
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
  String get openAtSearchTime => isEnglish ? 'Open at search time' : '조회 시각 영업';
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
  // 함수이름: all
  // 함수역할: 현재 언어와 입력값에 맞춰 "All" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get all => isEnglish ? 'All' : '전체';
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
  // 함수이름: filterPickerDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "약국 목록에 적용할 조건을 하나 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get filterPickerDescription => isEnglish
      ? 'Choose one condition for the pharmacy list.'
      : '약국 목록에 적용할 조건을 하나 선택해주세요.';
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

  // 함수이름: noOpenPharmacy
  // 함수역할: 선택한 검색 지역에 영업 중인 약국이 없음을 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noOpenPharmacy => isEnglish
      ? 'No open pharmacies were found in this search area'
      : '검색한 지역에 영업 중인 약국이 없습니다';
  // 함수이름: noLateNightPharmacy
  // 함수역할: 선택 지역의 심야 약국 검색 결과가 없음을 안내한다. 매개변수: 없음. 반환값: 번역 문구.
  String get noLateNightPharmacy => isEnglish
      ? 'No late-night pharmacies were found in this search area'
      : '검색한 지역에 심야 운영 약국이 없습니다';
  // 함수이름: noWeekendHolidayPharmacy
  // 함수역할: 선택 지역의 주말·공휴일 약국 결과가 없음을 안내한다. 매개변수: 없음. 반환값: 번역 문구.
  String get noWeekendHolidayPharmacy => isEnglish
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
  // 함수이름: locationDisabledTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "기기 위치가 꺼져 있습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationDisabledTitle =>
      isEnglish ? 'Device location is turned off' : '기기 위치가 꺼져 있습니다';
  // 함수이름: locationDisabledMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 위치에서 가까운 약국을 찾으려면 기기 위치를 켜주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationDisabledMessage => isEnglish
      ? 'Turn on device location to find pharmacies near you.'
      : '현재 위치에서 가까운 약국을 찾으려면 기기 위치를 켜주세요.';
  // 함수이름: openLocationSettings
  // 함수역할: 현재 언어와 입력값에 맞춰 "위치 설정 열기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openLocationSettings =>
      isEnglish ? 'Open location settings' : '위치 설정 열기';
  // 함수이름: locationBlockedTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "위치 권한이 차단되어 있습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationBlockedTitle =>
      isEnglish ? 'Location permission is blocked' : '위치 권한이 차단되어 있습니다';
  // 함수이름: locationBlockedMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "앱 설정에서 MedBuddy의 위치 권한을 허용해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationBlockedMessage => isEnglish
      ? 'Allow MedBuddy to use location in the app settings.'
      : '앱 설정에서 MedBuddy의 위치 권한을 허용해주세요.';
  // 함수이름: openAppSettings
  // 함수역할: 현재 언어와 입력값에 맞춰 "앱 설정 열기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openAppSettings => isEnglish ? 'Open app settings' : '앱 설정 열기';
  // 함수이름: locationPermissionTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "위치 권한이 필요합니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationPermissionTitle =>
      isEnglish ? 'Location permission is required' : '위치 권한이 필요합니다';
  // 함수이름: locationPermissionMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "위치는 근처 약국을 찾을 때만 사용하며 서버 DB에 저장하지 않습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationPermissionMessage => isEnglish
      ? 'Location is used only to find nearby pharmacies and is not stored in the server database.'
      : '위치는 근처 약국을 찾을 때만 사용하며 서버 DB에 저장하지 않습니다.';
  // 함수이름: requestAgain
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 요청" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get requestAgain => isEnglish ? 'Request again' : '다시 요청';
  // 함수이름: locationUnavailableTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 위치를 확인하지 못했습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationUnavailableTitle => isEnglish
      ? 'Could not determine your current location'
      : '현재 위치를 확인하지 못했습니다';
  // 함수이름: locationUnavailableMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "잠시 이동한 뒤 또는 위치 신호가 좋은 곳에서 다시 시도해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get locationUnavailableMessage => isEnglish
      ? 'Move briefly or try again where the location signal is stronger.'
      : '잠시 이동한 뒤 또는 위치 신호가 좋은 곳에서 다시 시도해주세요.';
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
  // 함수이름: mapInstruction
  // 함수역할: 현재 언어와 입력값에 맞춰 "아래 약국을 누르면 지도에서 위치를 확인할 수 있습니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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
  // 함수이름: todayHours
  // 함수역할: 현재 언어와 입력값에 맞춰 "24시간 운영" 문구를 제공한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String todayHours(NearbyPharmacy pharmacy, {bool usesSelectedTime = false}) {
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

  // 함수이름: scheduleTags
  // 함수역할: 현재 언어와 입력값에 맞춰 "늦게까지 영업" 문구를 제공한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String scheduleTags(NearbyPharmacy pharmacy) {
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
  // Description: Provides localized wording for "${value.year.toString().padLeft(4," using the current language and message inputs.
  // Parameters:
  // - value (DateTime): Input to validate, normalize, display, or pass through a selection callback.
  // Returns: The formatted display text or identifier described above.
  String searchDate(DateTime value) {
    final formatted =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return isEnglish ? 'Search date: $formatted' : '조회 날짜: $formatted';
  }

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

  // 함수이름: operatingStatusDetail
  // 함수역할: 현재 언어와 입력값에 맞춰 "$remainingMinutes분 후 영업 종료" 문구를 제공한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? operatingStatusDetail(NearbyPharmacy pharmacy) {
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
