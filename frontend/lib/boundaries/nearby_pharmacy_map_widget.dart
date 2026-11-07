// 파일명: nearby_pharmacy_map_widget.dart
// 역할: 약국 좌표와 선택 상태를 반영하는 네이버 지도를 제공한다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../entities/device_coordinate_entity.dart';
import '../entities/nearby_care_entity.dart';
import '../services/naver_map_config.dart';
import '../services/nearby_care_marker_diff.dart';
import '../theme/medbuddy_theme.dart';
import 'pharmacy_map_symbols.dart';

// Class Name: NearbyPharmacyMap
// Role: Interactive nearby-care map with selection and favorites.
// Responsibilities: Keeps device location distinct from the searched area and changes camera focus only for explicit selection/recenter requests.
// Attributes: searchArea/deviceLocation/centerRevision: location and focus; pharmacies/selectedPharmacyId/favoritePharmacyIds: markers; bottomInset/showControls: viewport controls; callbacks and labels: search, current location, selection and attribution.
class NearbyPharmacyMap extends StatefulWidget {
  final bool hospitals;
  final NearbyCareSearchArea searchArea;

  /// Last device fix, independent from a manually moved search area.
  final DeviceCoordinate? deviceLocation;
  final int centerRevision;
  // 하단 정보창 높이만큼 지도 중심·로고·조작 버튼의 표시 영역을 확보한다.
  final double bottomInset;
  final bool showControls;
  final bool isSearching;
  final Future<bool> Function(NearbyCareSearchArea)? onSearchAreaRequested;
  final VoidCallback? onCurrentLocationRequested;
  final String searchAreaLabel;
  final List<NearbyCarePlace> pharmacies;
  // 현재 사용자가 저장한 약국 ID로 즐겨찾기 마커를 구분한다.
  final Set<String> favoritePharmacyIds;
  final String? selectedPharmacyId;
  final ValueChanged<NearbyCarePlace> onPharmacySelected;
  final VoidCallback onAttributionRequested;
  final String? statusText;
  final String selectMarkerHint;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final String configurationUnavailableText;
  final String unavailableText;
  final String myLocationTooltip;

  // Function Name: NearbyPharmacyMap
  // Description: Binds map results, viewport settings, explicit camera requests and localized control/failure labels.
  // Parameters: key: identity; hospitals: marker category; searchArea/deviceLocation/centerRevision: search center, device fix and recenter request; bottomInset/showControls: layout; isSearching/onSearchAreaRequested/searchAreaLabel: area query; onCurrentLocationRequested/myLocationTooltip: device action; pharmacies/selectedPharmacyId/favoritePharmacyIds/onPharmacySelected: markers and selection; onAttributionRequested: source action; statusText/selectMarkerHint/zoomInTooltip/zoomOutTooltip/configurationUnavailableText/unavailableText: status, control and fallback copy.
  // Returns: A NearbyPharmacyMap.
  const NearbyPharmacyMap({
    super.key,
    this.hospitals = false,
    required this.searchArea,
    this.deviceLocation,
    this.centerRevision = 0,
    this.bottomInset = 0,
    this.showControls = true,
    this.isSearching = false,
    this.onSearchAreaRequested,
    this.onCurrentLocationRequested,
    this.searchAreaLabel = '이 지역에서 검색',
    required this.pharmacies,
    this.favoritePharmacyIds = const {},
    required this.selectedPharmacyId,
    required this.onPharmacySelected,
    required this.onAttributionRequested,
    required this.statusText,
    required this.selectMarkerHint,
    required this.zoomInTooltip,
    required this.zoomOutTooltip,
    required this.configurationUnavailableText,
    required this.unavailableText,
    this.myLocationTooltip = '현재 위치로 이동',
  });

  // 함수이름: createState
  // 함수역할: 약국 마커·선택 강조·확대·출처 명령의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _NearbyPharmacyMapState 인스턴스.
  @override
  State<NearbyPharmacyMap> createState() => _NearbyPharmacyMapState();
}

// 정보창을 드래그하는 동안 지도 여백 변경을 플랫폼에 매 프레임 보내지 않도록 마지막 변경 뒤 기다리는 시간.
const _contentPaddingSettleDelay = Duration(milliseconds: 100);
// 일부만 추가된 마커 묶음을 화면 변경 없이 한 번 다시 맞추기 전에 기다리는 시간.
const _markerRetryDelay = Duration(seconds: 1);

// 클래스명: _NearbyPharmacyMapState
// 역할: 지도 마커와 카메라 갱신의 세대·수명을 관리한다.
// 주요 책임: 오래된 오버레이 작업을 버리고 실패 복구를 제한하며 사용자의 지도 이동과 선택 장소를 조율한다.
// 속성: _mapController (NaverMapController?): 지도; _overlayGeneration/_cameraGeneration (int): 작업 세대; _renderedMarkers (Map<String,NearbyCareMarkerStyle>): 반영 마커; _overlayWork (Future<void>): 직렬 작업; _markerRetryTimer (Timer?): 복구 예약.
class _NearbyPharmacyMapState extends State<NearbyPharmacyMap> {
  NaverMapController? _mapController;
  int _overlayGeneration = 0;
  final _renderedMarkers = <String, NearbyCareMarkerStyle>{};
  bool _markerStateUncertain = false;
  // 마커 추가 실패 뒤 자동 복구는 한 번만 예약하고, 마커 반영이 성공하면 다시 허용한다.
  bool _markerRetryUsed = false;
  Timer? _markerRetryTimer;
  Future<void> _overlayWork = Future.value();
  bool _pendingCameraMove = false;
  String? _pendingCameraSelection;
  int _pendingCameraGeneration = 0;
  bool _cameraMoved = false;
  NearbyCareSearchArea? _pendingArea;
  int _cameraGeneration = 0;
  Future<void>? _symbolLoading;
  NOverlayImage? _pinIcon;
  NOverlayImage? _selectedPinIcon;
  NOverlayImage? _favoritePinIcon;
  NOverlayImage? _locationIcon;
  // 지도 콘텐츠 여백에 쓰는 값. 조작 버튼은 widget.bottomInset을 그대로 따라간다.
  late double _paddingInset = widget.bottomInset;
  Timer? _paddingSettleTimer;

  // Function Name: dispose
  // Description: Cancels pending viewport-inset updates and marker-recovery timers before ending map state.
  // Parameters: None.
  // Returns: None.
  @override
  void dispose() {
    _paddingSettleTimer?.cancel();
    _markerRetryTimer?.cancel();
    super.dispose();
  }

  // Function Name: _loadSymbols
  // Description: Shares one symbol-generation future; clears a failed attempt so a later call can retry and rethrows that failure.
  // Parameters: None.
  // Returns: Future completing when symbols are ready.
  Future<void> _loadSymbols() => _symbolLoading ??= () async {
    try {
      await _createSymbols();
    } catch (_) {
      // 실패한 결과를 붙잡아 두면 화면을 다시 열 때까지 마커를 그릴 수 없으므로 다음 호출에서 다시 만든다.
      _symbolLoading = null;
      rethrow;
    }
  }();

  // Function Name: _createSymbols
  // Description: Creates regular, selected and favorite markers plus the device-location image; awaits the first image to serialize SDK temporary-directory initialization.
  // Parameters: None.
  // Returns: Future completing after icon generation, stopping state updates if unmounted.
  Future<void> _createSymbols() async {
    // 지도 SDK의 임시 이미지 폴더 초기화가 동시에 실행되지 않게 첫 이미지는 기다린다.
    _pinIcon = await NOverlayImage.fromWidget(
      widget: const PharmacyMapPin(),
      size: PharmacyMapPin.size,
      context: context,
    );
    if (!mounted) return;
    final icons = await Future.wait([
      NOverlayImage.fromWidget(
        widget: const PharmacyMapPin(selected: true),
        size: PharmacyMapPin.size,
        context: context,
      ),
      NOverlayImage.fromWidget(
        widget: const PharmacyDeviceLocationDot(),
        size: PharmacyDeviceLocationDot.size,
        context: context,
      ),
      NOverlayImage.fromWidget(
        widget: const PharmacyMapPin(favorite: true),
        size: PharmacyMapPin.size,
        context: context,
      ),
    ]);
    _selectedPinIcon = icons[0];
    _locationIcon = icons[1];
    _favoritePinIcon = icons[2];
  }

  // Function Name: _mappablePharmacies
  // Description: Filters results to places with valid map coordinates.
  // Parameters: None.
  // Returns: The mappable nearby-place list.
  List<NearbyCarePlace> get _mappablePharmacies =>
      widget.pharmacies.where(_hasValidCoordinate).toList(growable: false);

  // Function Name: didUpdateWidget
  // Description: Updates result/favorite markers while applying camera movement only for explicit selection or current-location requests.
  // Parameters: oldWidget (NearbyPharmacyMap): previous map configuration.
  // Returns: None.
  @override
  void didUpdateWidget(covariant NearbyPharmacyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged =
        oldWidget.selectedPharmacyId != widget.selectedPharmacyId;
    // 같은 목록 인스턴스가 다시 전달되는 재빌드(정보창 드래그 등)에서는 비교 문자열을 만들지 않는다.
    final pharmaciesChanged =
        !identical(oldWidget.pharmacies, widget.pharmacies) &&
        _coordinateSignature(oldWidget.pharmacies) !=
            _coordinateSignature(widget.pharmacies);
    final recenter = oldWidget.centerRevision != widget.centerRevision;
    if (recenter || (selectionChanged && widget.selectedPharmacyId != null)) {
      _cameraMoved = false;
      _pendingArea = null;
      _cameraGeneration++;
    }
    if (oldWidget.bottomInset != widget.bottomInset) {
      _paddingSettleTimer?.cancel();
      if (recenter || selectionChanged) {
        // 선택·닫기·위치 이동처럼 카메라가 함께 움직이는 변경은 기존처럼 같은 프레임에 반영한다.
        _paddingInset = widget.bottomInset;
      } else {
        _paddingSettleTimer = Timer(_contentPaddingSettleDelay, () {
          if (!mounted || _paddingInset == widget.bottomInset) return;
          setState(() => _paddingInset = widget.bottomInset);
        });
      }
    }
    if (selectionChanged ||
        pharmaciesChanged ||
        oldWidget.hospitals != widget.hospitals ||
        !setEquals(oldWidget.favoritePharmacyIds, widget.favoritePharmacyIds) ||
        recenter ||
        oldWidget.deviceLocation != widget.deviceLocation) {
      unawaited(
        _synchronizeMap(
          moveCamera:
              recenter ||
              (selectionChanged && widget.selectedPharmacyId != null),
        ),
      );
    }
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 마커·선택 강조·확대·출처 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 마커·선택 강조·확대·출처 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    if (!isNaverMapConfigured) {
      return _MapUnavailableState(message: widget.configurationUnavailableText);
    }
    // 채팅 등에서 장소를 선택한 채 처음 열어도 해당 마커가 정보창 뒤에 가리지 않게 한다.
    final initialSelection = _findSelectedPharmacy(_mappablePharmacies);
    return Semantics(
      container: true,
      label: widget.statusText,
      child: Container(
        key: const Key('nearby-pharmacy-map'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MedBuddyColors.surfaceSubtle,
          borderRadius: MedBuddyRadii.small,
          border: Border.all(color: MedBuddyColors.outline),
        ),
        child: Stack(
          children: [
            NaverMap(
              forceGesture: true,
              options: NaverMapViewOptions(
                initialCameraPosition: NCameraPosition(
                  target: NLatLng(
                    initialSelection?.latitude ??
                        widget.searchArea.center.latitude,
                    initialSelection?.longitude ??
                        widget.searchArea.center.longitude,
                  ),
                  zoom: initialSelection != null ? 16 : _searchAreaZoom,
                ),
                minZoom: 5,
                maxZoom: 19,
                rotationGesturesEnable: false,
                tiltGesturesEnable: false,
                scaleBarEnable: false,
                compassEnable: false,
                logoClickEnable: true,
                contentPadding: EdgeInsets.only(bottom: _paddingInset + 28),
              ),
              // Function Name: build.onMapReady callback
              // Description: Updates the local input or request state for pharmacy markers, selected highlighting, zoom, and attribution controls: `_mapController = controller`.
              // Parameters:
              // - controller (inferred by callback contract): Object controlling the associated camera, map, input, or scrolling interaction.
              // Returns: No payload; applies the captured state changes.
              onMapReady: (controller) {
                if (!mounted) return;
                if (!identical(_mapController, controller)) {
                  _renderedMarkers.clear();
                  _markerStateUncertain = false;
                  _markerRetryTimer?.cancel();
                  _markerRetryUsed = false;
                }
                setState(() => _mapController = controller);
                unawaited(_synchronizeMap());
              },
              onCameraChange: _onCameraChange,
              onCameraIdle: () => unawaited(_onCameraIdle()),
            ),
            if (_pendingArea != null && widget.onSearchAreaRequested != null)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Center(
                  child: FilledButton.icon(
                    key: const Key('pharmacy-search-this-area'),
                    onPressed: widget.isSearching ? null : _searchThisArea,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      widget.searchAreaLabel,
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              )
            else if (widget.statusText case final statusText?)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: MedBuddyRadii.small,
                      boxShadow: MedBuddyShadows.soft,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MedBuddyColors.textStrong,
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.showControls)
              Positioned(
                right: 8,
                bottom: widget.bottomInset + 8,
                child: _MapControlButton(
                  tooltip: 'Naver Map',
                  icon: Icons.info_outline,
                  onPressed: widget.onAttributionRequested,
                ),
              ),
            if (widget.showControls)
              Positioned(
                right: 8,
                bottom: widget.bottomInset + 54,
                child: _MapControlButton(
                  tooltip: widget.myLocationTooltip,
                  icon: Icons.my_location,
                  onPressed: widget.isSearching || _mapController == null
                      ? null
                      : widget.onCurrentLocationRequested,
                ),
              ),
            if (widget.showControls)
              Positioned(
                left: 8,
                bottom: widget.bottomInset + 8,
                child: Column(
                  children: [
                    _MapControlButton(
                      tooltip: widget.zoomInTooltip,
                      icon: Icons.add,
                      // 함수이름: build.onPressed callback
                      // 함수역할: 지도 준비가 끝난 경우 현재 확대 수준에 지정 변화량을 더한다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      onPressed: () => _changeZoom(1),
                    ),
                    const SizedBox(height: 6),
                    _MapControlButton(
                      tooltip: widget.zoomOutTooltip,
                      icon: Icons.remove,
                      // 함수이름: build.onPressed callback
                      // 함수역할: 지도 준비가 끝난 경우 현재 확대 수준에 지정 변화량을 더한다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      onPressed: () => _changeZoom(-1),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _onCameraChange
  // 함수역할: 사용자 이동 중에는 이전 지역 검색을 숨긴다. 매개변수: reason, animated. 반환값: 없음.
  void _onCameraChange(NCameraUpdateReason reason, bool animated) {
    if (reason == NCameraUpdateReason.gesture ||
        reason == NCameraUpdateReason.control) {
      _cameraMoved = true;
      _cameraGeneration++;
      if (_pendingArea != null) setState(() => _pendingArea = null);
    }
  }

  // Function Name: _onCameraIdle
  // Description: Records the settled map center and visible radius without automatically starting a search.
  // Parameters: None.
  // Returns: Future completing after viewport coordinates are read.
  Future<void> _onCameraIdle() async {
    final controller = _mapController;
    if (!_cameraMoved || controller == null) return;
    final generation = _cameraGeneration;
    try {
      final position = await controller.getCameraPosition();
      final bounds = await controller.getContentBounds();
      if (!mounted || generation != _cameraGeneration) return;
      final radius = [
        position.target.distanceTo(bounds.southWest),
        position.target.distanceTo(bounds.northEast),
      ].reduce((a, b) => a > b ? a : b);
      final area = NearbyCareSearchArea(
        center: DeviceCoordinate(
          latitude: position.target.latitude,
          longitude: position.target.longitude,
        ),
        radiusKm: (radius / 1000).clamp(0.1, 50).toDouble(),
        isMapArea: true,
      );
      if (area.isValid) setState(() => _pendingArea = area);
    } catch (_) {
      // 지도 준비가 풀리면 다음 이동 완료 시 다시 좌표를 확인한다.
    }
  }

  // 함수이름: _searchThisArea
  // 함수역할: 마지막 이동 지역을 검색하고 성공했을 때만 버튼을 숨긴다. 매개변수: 없음. 반환값: 검색 완료.
  Future<void> _searchThisArea() async {
    final area = _pendingArea;
    if (area == null || widget.isSearching) return;
    final generation = _cameraGeneration;
    final succeeded = await widget.onSearchAreaRequested?.call(area) ?? false;
    if (mounted && succeeded && generation == _cameraGeneration) {
      setState(() {
        _pendingArea = null;
        _cameraMoved = false;
      });
    }
  }

  // 함수이름: _synchronizeMap
  // 함수역할: 최신 결과의 마커만 표시하고 요청한 경우에만 카메라를 이동한다.
  // 매개변수: moveCamera: 명시적 위치 이동 여부. 반환값: 지도 갱신 완료.
  Future<void> _synchronizeMap({bool moveCamera = false}) async {
    if (moveCamera) {
      _pendingCameraMove = true;
      _pendingCameraSelection = widget.selectedPharmacyId;
      _pendingCameraGeneration = _cameraGeneration;
    }
    final generation = ++_overlayGeneration;
    // 플랫폼 마커 명령을 직렬화하고, 대기 중 들어온 요청은 최신 상태로 합친다.
    final work = _overlayWork.then((_) => _applyMapChanges(generation));
    _overlayWork = work.catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'nearby care map',
        ),
      );
    });
    await _overlayWork;
  }

  // Function Name: _applyMapChanges
  // Description: Applies the newest marker generation serially, repairing uncertain native overlays and updating cached markers only after successful removal/addition; ignores stale generations and only honors valid explicit camera requests.
  // Parameters: generation (int): queued overlay generation.
  // Returns: Future completing after synchronization; native errors propagate to the queue recovery handler.
  Future<void> _applyMapChanges(int generation) async {
    final controller = _mapController;
    if (!mounted || generation != _overlayGeneration || controller == null) {
      return;
    }
    await _loadSymbols();
    if (!mounted || generation != _overlayGeneration) return;
    if (_markerStateUncertain) {
      // A native batch may fail after adding some markers, so its cached diff is no longer authoritative.
      await controller.clearOverlays(type: NOverlayType.marker);
      if (!mounted || !identical(_mapController, controller)) return;
      _renderedMarkers.clear();
      _markerStateUncertain = false;
      if (generation != _overlayGeneration) return;
    }
    final locationOverlay = controller.getLocationOverlay();
    if (!mounted || generation != _overlayGeneration) return;
    final coordinate = widget.deviceLocation;
    final validLocation =
        coordinate != null &&
        NearbyCareSearchArea(
          center: coordinate,
          radiusKm: widget.searchArea.radiusKm,
        ).isValid;
    locationOverlay.setIsVisible(validLocation);
    if (validLocation) {
      locationOverlay.setPosition(
        NLatLng(coordinate.latitude, coordinate.longitude),
      );
      locationOverlay.setIcon(_locationIcon!);
      locationOverlay.setIconSize(PharmacyDeviceLocationDot.size);
      locationOverlay.setSubIcon(null);
    }
    final pharmacies = _mappablePharmacies;
    final next = {
      for (final place in pharmacies)
        place.placeId: nearbyCareMarkerStyle(
          place,
          selectedId: widget.selectedPharmacyId,
          favoriteIds: widget.favoritePharmacyIds,
        ),
    };
    final diff = NearbyCareMarkerDiff.between(_renderedMarkers, next);
    for (final id in diff.remove) {
      await controller.deleteOverlay(
        NOverlayInfo(type: NOverlayType.marker, id: 'pharmacy-$id'),
      );
      if (!mounted || !identical(_mapController, controller)) return;
      _renderedMarkers.remove(id);
      if (!mounted || generation != _overlayGeneration) return;
    }
    final markers = pharmacies
        .where((place) => diff.add.contains(place.placeId))
        .map(_buildMarker)
        .toSet();
    if (markers.isNotEmpty) {
      try {
        await controller.addOverlayAll(markers);
      } catch (_) {
        if (mounted && identical(_mapController, controller)) {
          _markerStateUncertain = true;
          _scheduleMarkerRetry();
        }
        rethrow;
      }
      if (!mounted || !identical(_mapController, controller)) return;
      for (final id in diff.add) {
        _renderedMarkers[id] = next[id]!;
      }
    }
    // 마커가 최신 결과와 일치하므로 다음 실패에는 자동 복구를 다시 한 번 허용한다.
    _markerRetryTimer?.cancel();
    _markerRetryUsed = false;
    if (!mounted || generation != _overlayGeneration) {
      return;
    }
    if (_pendingCameraMove) {
      _pendingCameraMove = false;
      // 갱신을 기다리던 중 선택을 해제하거나 지도를 직접 움직였다면 이동을 취소한다.
      if (_pendingCameraSelection == widget.selectedPharmacyId &&
          _pendingCameraGeneration == _cameraGeneration) {
        await _updateCamera(controller, pharmacies);
      }
    }
  }

  // Function Name: _scheduleMarkerRetry
  // Description: Schedules one automatic marker-recovery attempt after partial native failure; does not schedule further retries until a successful synchronization resets the allowance.
  // Parameters: None.
  // Returns: None.
  void _scheduleMarkerRetry() {
    if (_markerRetryUsed) return;
    _markerRetryUsed = true;
    _markerRetryTimer = Timer(_markerRetryDelay, () {
      // 그사이 다른 동기화가 복구를 마쳤다면 다시 지우고 그리지 않는다.
      if (mounted && _markerStateUncertain) unawaited(_synchronizeMap());
    });
  }

  // 함수이름: _buildMarker
  // 함수역할: 즐겨찾기는 골드색 별로 표시하고 선택한 약국은 크기로 강조한다.
  // 매개변수: pharmacy: 지도에 표시할 약국. 반환값: 이름과 선택 동작을 가진 마커.
  NMarker _buildMarker(NearbyCarePlace pharmacy) {
    final isSelected = pharmacy.placeId == widget.selectedPharmacyId;
    final isFavorite = widget.favoritePharmacyIds.contains(pharmacy.placeId);
    final marker = NMarker(
      id: 'pharmacy-${pharmacy.placeId}',
      position: NLatLng(pharmacy.latitude, pharmacy.longitude),
      icon: isFavorite
          ? _favoritePinIcon
          : (isSelected ? _selectedPinIcon : _pinIcon),
      size: isSelected ? PharmacyMapPin.selectedSize : PharmacyMapPin.size,
      caption: NOverlayCaption(
        text: pharmacy.name,
        textSize: 12,
        color: MedBuddyColors.textStrong,
        haloColor: Colors.white,
      ),
      captionAligns: const [NAlign.bottom],
      captionOffset: 3,
      // 밀집된 병원 이름은 겹침을 피하고 선택한 장소의 이름을 우선 표시한다.
      isHideCollidedCaptions: true,
      isForceShowCaption: isSelected,
    );
    // Function Name: _buildMarker.setOnTapListener callback
    // Description: Connects pharmacy markers, selected highlighting, zoom, and attribution controls to the captured operation `widget.onPharmacySelected(pharmacy)`.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    marker.setOnTapListener((_) {
      if (!mounted) return;
      // 마커 모양이 같아도 상세창에는 최신 영업시간·연락처를 전달한다.
      for (final current in widget.pharmacies) {
        if (current.placeId == pharmacy.placeId) {
          widget.onPharmacySelected(current);
          return;
        }
      }
    });
    return marker;
  }

  // Function Name: _updateCamera
  // Description: Moves the camera for place selection or current-location recentering while preserving zoom/center after ordinary area searches.
  // Parameters: controller (NaverMapController): ready map; pharmacies (List<NearbyCarePlace>): current results.
  // Returns: Future completing after the requested camera update.
  Future<void> _updateCamera(
    NaverMapController controller,
    List<NearbyCarePlace> pharmacies,
  ) async {
    final selected = _findSelectedPharmacy(pharmacies);
    if (selected != null) {
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(selected.latitude, selected.longitude),
          zoom: 16,
        ),
      );
      return;
    }
    await controller.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(
          widget.searchArea.center.latitude,
          widget.searchArea.center.longitude,
        ),
        zoom: _searchAreaZoom,
      ),
    );
  }

  // 함수이름: _searchAreaZoom
  // 함수역할: 병원은 실제 검색 반경으로 줌을 계산하고 5~18로 제한하며 약국의 기존 배율은 유지한다.
  // 매개변수: 없음.
  // 반환값: 병원 계산 줌 또는 약국 13.
  double get _searchAreaZoom => widget.hospitals
      ? (14 - math.log(widget.searchArea.radiusKm) / math.ln2)
            .clamp(5, 18)
            .toDouble()
      : 13;

  // Function Name: _findSelectedPharmacy
  // Description: Finds the currently selected place in the result list.
  // Parameters: pharmacies (List<NearbyCarePlace>): candidate results.
  // Returns: The matching place, or null.
  NearbyCarePlace? _findSelectedPharmacy(List<NearbyCarePlace> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.placeId == widget.selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  // 함수이름: _changeZoom
  // 함수역할: 지도 제어기가 준비되었을 때 현재 확대 수준에 요청한 증감량을 적용한다.
  // 매개변수: delta (double): 확대 수준 증감량.
  // 반환값: 없음.
  void _changeZoom(double delta) {
    final controller = _mapController;
    if (controller != null) {
      _cameraMoved = true;
      _cameraGeneration++;
      setState(() => _pendingArea = null);
      unawaited(controller.updateCamera(NCameraUpdate.zoomBy(delta)));
    }
  }

  // Function Name: _hasValidCoordinate
  // Description: Requires finite coordinates within latitude/longitude bounds and excludes the all-zero location.
  // Parameters: pharmacy (NearbyCarePlace): coordinates to test.
  // Returns: True when the place can be mapped.
  bool _hasValidCoordinate(NearbyCarePlace pharmacy) {
    final latitude = pharmacy.latitude;
    final longitude = pharmacy.longitude;
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        (latitude != 0 || longitude != 0);
  }

  // Function Name: _coordinateSignature
  // Description: Builds a result signature from place identity, name and coordinates to detect marker changes.
  // Parameters: pharmacies (List<NearbyCarePlace>): ordered results.
  // Returns: The comparison signature string.
  String _coordinateSignature(List<NearbyCarePlace> pharmacies) {
    return pharmacies
        .map(
          // 함수이름: _coordinateSignature.map callback
          // 함수역할: 약국 식별 정보와 이름·좌표를 지도 갱신 비교값으로 변환한다.
          // 매개변수:
          // - pharmacy (콜백 계약에서 추론): 표시하거나 전화·길찾기·공유할 약국.
          // 반환값: 컬렉션 연산에 전달할 변환값.
          (pharmacy) =>
              '${pharmacy.placeId}:${pharmacy.name}:${pharmacy.latitude}:${pharmacy.longitude}',
        )
        .join('|');
  }
}

// Class Name: _MapControlButton
// Role: Map overlay icon command.
// Responsibilities: Exposes zoom or attribution actions with an accessible tooltip.
// Attributes: tooltip: action description; icon: command symbol; onPressed: action callback.
class _MapControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  // 함수이름: _MapControlButton
  // 함수역할: 지도 위의 확대·축소·출처 아이콘 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MapControlButton 인스턴스.
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 지도 위의 확대·축소·출처 아이콘 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 지도 위의 확대·축소·출처 아이콘 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, color: MedBuddyColors.primaryDark),
      ),
    );
  }
}

// Class Name: _MapUnavailableState
// Role: Map-unavailable presentation.
// Responsibilities: Explains missing map configuration or usable coordinates.
// Attributes: message (String): unavailability explanation.
class _MapUnavailableState extends StatelessWidget {
  final String message;

  // 함수이름: _MapUnavailableState
  // 함수역할: 지도 설정 또는 유효한 좌표 부재 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 입력 설정이 반영된 _MapUnavailableState 인스턴스.
  const _MapUnavailableState({required this.message});

  // Function Name: build
  // Description: Displays the map-unavailable explanation in place of the interactive map.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nearby-pharmacy-map-unavailable'),
      height: 150,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.small,
        border: Border.all(color: MedBuddyColors.outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_outlined,
            color: MedBuddyColors.textLight,
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textSubtle,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
