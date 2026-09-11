// 파일명: nearby_pharmacy_map_widget.dart
// 역할: 약국 좌표와 선택 상태를 반영하는 네이버 지도를 제공한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../entities/nearby_pharmacy_entity.dart';
import '../services/naver_map_config.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: NearbyPharmacyMap
// 역할: 약국 마커·선택 강조·확대·출처 명령을 담당한다.
// 주요 책임:
// - 약국 마커·선택 강조·확대·출처 명령의 State가 사용할 화면 설정과 외부 의존성을 보관한다.
// 속성:
// - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
// - selectedPharmacyId (String?): 공유하거나 지도에서 선택한 약국 ID.
// - onPharmacySelected (ValueChanged<NearbyPharmacy>): 목록·마커에서 선택한 약국을 전달할 콜백.
// - onAttributionRequested (VoidCallback): 지도 데이터의 출처·저작권 안내를 여는 콜백.
class NearbyPharmacyMap extends StatefulWidget {
  final List<NearbyPharmacy> pharmacies;
  final String? selectedPharmacyId;
  final ValueChanged<NearbyPharmacy> onPharmacySelected;
  final VoidCallback onAttributionRequested;
  final String? statusText;
  final String selectMarkerHint;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final String configurationUnavailableText;
  final String unavailableText;

  // 함수이름: NearbyPharmacyMap
  // 함수역할: 약국 마커·선택 강조·확대·출처 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
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
  // 반환값: 입력 설정이 반영된 NearbyPharmacyMap 인스턴스.
  const NearbyPharmacyMap({
    super.key,
    required this.pharmacies,
    required this.selectedPharmacyId,
    required this.onPharmacySelected,
    required this.onAttributionRequested,
    required this.statusText,
    required this.selectMarkerHint,
    required this.zoomInTooltip,
    required this.zoomOutTooltip,
    required this.configurationUnavailableText,
    required this.unavailableText,
  });

  // 함수이름: createState
  // 함수역할: 약국 마커·선택 강조·확대·출처 명령의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _NearbyPharmacyMapState 인스턴스.
  @override
  State<NearbyPharmacyMap> createState() => _NearbyPharmacyMapState();
}

// 클래스명: _NearbyPharmacyMapState
// 역할: 약국 마커·선택 강조·확대·출처 명령의 화면 상태를 관리한다.
// 주요 책임:
// - 기존 약국 마커를 지운 뒤 최신 세대의 마커만 추가하고 카메라 범위를 갱신한다.
// - 약국 좌표에 선택 크기·색상·이름과 탭 선택 콜백을 갖춘 마커를 만든다.
// - 선택 약국은 확대 16, 단일 약국은 15로 이동하고 여러 약국은 모두 보이는 범위에 맞춘다.
class _NearbyPharmacyMapState extends State<NearbyPharmacyMap> {
  NaverMapController? _mapController;
  int _overlayGeneration = 0;

  // 함수이름: _mappablePharmacies
  // 함수역할: 유효한 위도·경도를 가진 약국만 지도 표시 목록으로 선택한다.
  // 매개변수:
  // - 없음.
  // 반환값: List<NearbyPharmacy>: 조회 또는 좌표 조건을 반영한 지도·목록용 약국 목록.
  List<NearbyPharmacy> get _mappablePharmacies =>
      widget.pharmacies.where(_hasValidCoordinate).toList(growable: false);

  // Function Name: didUpdateWidget
  // Description: Synchronizes map markers and camera when selection or the ID/coordinate list changes.
  // Parameters:
  // - oldWidget (NearbyPharmacyMap): Previous widget configuration used for change detection.
  // Returns: None; updates state or performs the documented action.
  @override
  void didUpdateWidget(covariant NearbyPharmacyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged =
        oldWidget.selectedPharmacyId != widget.selectedPharmacyId;
    final pharmaciesChanged =
        _coordinateSignature(oldWidget.pharmacies) !=
        _coordinateSignature(widget.pharmacies);
    if (selectionChanged || pharmaciesChanged) {
      unawaited(_synchronizeMap());
    }
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약국 마커·선택 강조·확대·출처 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약국 마커·선택 강조·확대·출처 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final pharmacies = _mappablePharmacies;
    if (!isNaverMapConfigured) {
      return _MapUnavailableState(message: widget.configurationUnavailableText);
    }
    if (pharmacies.isEmpty) {
      return _MapUnavailableState(message: widget.unavailableText);
    }

    final first = pharmacies.first;
    return Semantics(
      container: true,
      label: widget.statusText,
      child: Container(
        key: const Key('nearby-pharmacy-map'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MedBuddyColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MedBuddyColors.outline),
        ),
        child: Stack(
          children: [
            NaverMap(
              forceGesture: true,
              options: NaverMapViewOptions(
                initialCameraPosition: NCameraPosition(
                  target: NLatLng(first.latitude, first.longitude),
                  zoom: 13,
                ),
                minZoom: 5,
                maxZoom: 19,
                rotationGesturesEnable: false,
                tiltGesturesEnable: false,
                scaleBarEnable: false,
                compassEnable: false,
                logoClickEnable: true,
                contentPadding: const EdgeInsets.only(bottom: 28),
              ),
              // Function Name: build.onMapReady callback
              // Description: Updates the local input or request state for pharmacy markers, selected highlighting, zoom, and attribution controls: `_mapController = controller`.
              // Parameters:
              // - controller (inferred by callback contract): Object controlling the associated camera, map, input, or scrolling interaction.
              // Returns: No payload; applies the captured state changes.
              onMapReady: (controller) {
                _mapController = controller;
                unawaited(_synchronizeMap());
              },
            ),
            if (widget.statusText case final statusText?)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
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
            Positioned(
              right: 8,
              bottom: 8,
              child: _MapControlButton(
                tooltip: 'Naver Map',
                icon: Icons.info_outline,
                onPressed: widget.onAttributionRequested,
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
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

  // Function Name: _synchronizeMap
  // Description: Clears old markers, adds only the current generation's markers, and updates camera framing.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _synchronizeMap() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }
    final generation = ++_overlayGeneration;
    final pharmacies = _mappablePharmacies;
    final markers = pharmacies.map(_buildMarker).toSet();
    await controller.clearOverlays(type: NOverlayType.marker);
    if (!mounted || generation != _overlayGeneration) {
      return;
    }
    if (markers.isNotEmpty) {
      await controller.addOverlayAll(markers);
    }
    if (!mounted || generation != _overlayGeneration) {
      return;
    }
    await _updateCamera(controller, pharmacies);
  }

  // Function Name: _buildMarker
  // Description: Creates a pharmacy marker with selected size, color, caption, and a tap-selection callback.
  // Parameters:
  // - pharmacy (NearbyPharmacy): Pharmacy to display, call, obtain directions to, or share.
  // Returns: NMarker: Map marker with selection styling and pharmacy tap selection.
  NMarker _buildMarker(NearbyPharmacy pharmacy) {
    final isSelected = pharmacy.pharmacyId == widget.selectedPharmacyId;
    final marker = NMarker(
      id: 'pharmacy-${pharmacy.pharmacyId}',
      position: NLatLng(pharmacy.latitude, pharmacy.longitude),
      iconTintColor: isSelected
          ? MedBuddyColors.primaryDark
          : MedBuddyColors.primary,
      size: Size.square(isSelected ? 42 : 34),
      caption: isSelected
          ? NOverlayCaption(
              text: pharmacy.name,
              textSize: 12,
              color: MedBuddyColors.textStrong,
              haloColor: Colors.white,
            )
          : null,
    );
    // Function Name: _buildMarker.setOnTapListener callback
    // Description: Connects pharmacy markers, selected highlighting, zoom, and attribution controls to the captured operation `widget.onPharmacySelected(pharmacy)`.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    marker.setOnTapListener((_) => widget.onPharmacySelected(pharmacy));
    return marker;
  }

  // 함수이름: _updateCamera
  // 함수역할: 선택 약국은 확대 16, 단일 약국은 15로 이동하고 여러 약국은 모두 보이는 범위에 맞춘다.
  // 매개변수:
  // - controller (NaverMapController): 마커와 카메라 이동에 사용할 준비된 네이버 지도 컨트롤러.
  // - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _updateCamera(
    NaverMapController controller,
    List<NearbyPharmacy> pharmacies,
  ) async {
    if (pharmacies.isEmpty) {
      return;
    }
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
    if (pharmacies.length == 1) {
      final pharmacy = pharmacies.first;
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(pharmacy.latitude, pharmacy.longitude),
          zoom: 15,
        ),
      );
      return;
    }
    await controller.updateCamera(
      NCameraUpdate.fitBounds(
        NLatLngBounds.from(
          // 함수이름: _updateCamera.map callback
          // 함수역할: 약국 마커·선택 강조·확대·출처 명령의 변환값을 `NLatLng(item.latitude, item.longitude)` 규칙으로 계산한다.
          // 매개변수:
          // - item (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
          // 반환값: 컬렉션 연산에 전달할 변환값.
          pharmacies.map((item) => NLatLng(item.latitude, item.longitude)),
        ),
        padding: const EdgeInsets.fromLTRB(34, 58, 34, 34),
      ),
    );
  }

  // 함수이름: _findSelectedPharmacy
  // 함수역할: 현재 선택 ID에 해당하는 약국을 목록에서 찾고 없으면 null을 반환한다.
  // 매개변수:
  // - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
  // 반환값: NearbyPharmacy?: 선택 ID와 일치하는 약국; 없으면 null.
  NearbyPharmacy? _findSelectedPharmacy(List<NearbyPharmacy> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.pharmacyId == widget.selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  // Function Name: _changeZoom
  // Description: Applies the requested zoom increment when the map controller is ready.
  // Parameters:
  // - delta (double): Increment added to the current map zoom level.
  // Returns: None; updates state or performs the documented action.
  void _changeZoom(double delta) {
    final controller = _mapController;
    if (controller != null) {
      unawaited(controller.updateCamera(NCameraUpdate.zoomBy(delta)));
    }
  }

  // 함수이름: _hasValidCoordinate
  // 함수역할: 유한한 위도·경도 범위를 검증하고 둘 다 0인 좌표를 제외한다.
  // 매개변수:
  // - pharmacy (NearbyPharmacy): 표시하거나 전화·길찾기·공유할 약국.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool _hasValidCoordinate(NearbyPharmacy pharmacy) {
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

  // 함수이름: _coordinateSignature
  // 함수역할: 약국 ID·위도·경도를 순서대로 연결해 지도 갱신 여부 비교 키를 만든다.
  // 매개변수:
  // - pharmacies (List<NearbyPharmacy>): 지도 또는 목록에 배치할 약국 검색 결과.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _coordinateSignature(List<NearbyPharmacy> pharmacies) {
    return pharmacies
        .map(
          // 함수이름: _coordinateSignature.map callback
          // 함수역할: 약국 마커·선택 강조·확대·출처 명령의 변환값을 `'${pharmacy.pharmacyId}:${pharmacy.latitude}:${pharmacy.longitude}'` 규칙으로 계산한다.
          // 매개변수:
          // - pharmacy (콜백 계약에서 추론): 표시하거나 전화·길찾기·공유할 약국.
          // 반환값: 컬렉션 연산에 전달할 변환값.
          (pharmacy) =>
              '${pharmacy.pharmacyId}:${pharmacy.latitude}:${pharmacy.longitude}',
        )
        .join('|');
  }
}

// 클래스명: _MapControlButton
// 역할: 지도 위의 확대·축소·출처 아이콘 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 지도 위의 확대·축소·출처 아이콘 명령 위젯을 구성한다.
// 속성:
// - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MapControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

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

// 클래스명: _MapUnavailableState
// 역할: 지도 설정 또는 유효한 좌표 부재 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 지도 설정 또는 유효한 좌표 부재 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
class _MapUnavailableState extends StatelessWidget {
  final String message;

  // 함수이름: _MapUnavailableState
  // 함수역할: 지도 설정 또는 유효한 좌표 부재 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 입력 설정이 반영된 _MapUnavailableState 인스턴스.
  const _MapUnavailableState({required this.message});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 지도 설정 또는 유효한 좌표 부재 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 지도 설정 또는 유효한 좌표 부재 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nearby-pharmacy-map-unavailable'),
      height: 150,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
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
