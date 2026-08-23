// 파일명: nearby_pharmacy_map_widget.dart
// 역할: 근처 약국 좌표를 앱 내 지도에 표시하고 선택한 약국으로 이동한다.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../entities/nearby_pharmacy_entity.dart';
import '../theme/medbuddy_theme.dart';

const _defaultMapTileUrl = String.fromEnvironment(
  'MEDBUDDY_MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

// 클래스명: NearbyPharmacyMap
// 역할: 약국 목록을 지도 마커로 표현하고 외부에서 선택된 약국을 중심에 표시한다.
// 주요 책임:
// - 유효한 위도·경도만 지도에 표시한다.
// - 목록 또는 마커에서 선택한 약국으로 지도 카메라를 이동한다.
// - 지도 제공자 출처와 기본 확대·축소 조작을 제공한다.
class NearbyPharmacyMap extends StatefulWidget {
  final List<NearbyPharmacy> pharmacies;
  final String? selectedPharmacyId;
  final ValueChanged<NearbyPharmacy> onPharmacySelected;
  final VoidCallback onAttributionRequested;
  final String? statusText;
  final String selectMarkerHint;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final String unavailableText;

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
    required this.unavailableText,
  });

  @override
  State<NearbyPharmacyMap> createState() => _NearbyPharmacyMapState();
}

class _NearbyPharmacyMapState extends State<NearbyPharmacyMap> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;

  List<NearbyPharmacy> get _mappablePharmacies =>
      widget.pharmacies.where(_hasValidCoordinate).toList(growable: false);

  @override
  void didUpdateWidget(covariant NearbyPharmacyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged =
        oldWidget.selectedPharmacyId != widget.selectedPharmacyId;
    final pharmaciesChanged =
        _coordinateSignature(oldWidget.pharmacies) !=
        _coordinateSignature(widget.pharmacies);
    if (selectionChanged || pharmaciesChanged) {
      _scheduleCameraUpdate();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pharmacies = _mappablePharmacies;
    if (pharmacies.isEmpty) {
      return _MapUnavailableState(message: widget.unavailableText);
    }

    final initialCenter = LatLng(
      pharmacies.first.latitude,
      pharmacies.first.longitude,
    );

    return Semantics(
      container: true,
      label: widget.statusText,
      child: Container(
        key: const Key('nearby-pharmacy-map'),
        height: 224,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MedBuddyColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MedBuddyColors.outline),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 13,
                minZoom: 5,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _isMapReady = true;
                  _scheduleCameraUpdate();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _defaultMapTileUrl,
                  userAgentPackageName: 'com.medbuddy.app',
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: pharmacies.map(_buildMarker).toList(growable: false),
                ),
                SimpleAttributionWidget(
                  source: const Text(
                    'OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, letterSpacing: 0),
                  ),
                  onTap: widget.onAttributionRequested,
                  backgroundColor: Colors.white.withValues(alpha: 0.86),
                ),
              ],
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
              left: 8,
              bottom: 8,
              child: Column(
                children: [
                  _MapControlButton(
                    tooltip: widget.zoomInTooltip,
                    icon: Icons.add,
                    onPressed: () => _changeZoom(1),
                  ),
                  const SizedBox(height: 6),
                  _MapControlButton(
                    tooltip: widget.zoomOutTooltip,
                    icon: Icons.remove,
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

  Marker _buildMarker(NearbyPharmacy pharmacy) {
    final isSelected = pharmacy.pharmacyId == widget.selectedPharmacyId;
    final markerSize = isSelected ? 50.0 : 42.0;
    return Marker(
      key: ValueKey('pharmacy-map-marker-${pharmacy.pharmacyId}'),
      point: LatLng(pharmacy.latitude, pharmacy.longitude),
      width: markerSize,
      height: markerSize,
      alignment: Alignment.topCenter,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '${pharmacy.name}, ${widget.selectMarkerHint}',
        child: Tooltip(
          message: pharmacy.name,
          child: InkResponse(
            key: isSelected
                ? ValueKey(
                    'selected-pharmacy-map-marker-${pharmacy.pharmacyId}',
                  )
                : null,
            radius: markerSize / 2,
            onTap: () => widget.onPharmacySelected(pharmacy),
            child: Icon(
              Icons.location_on,
              size: markerSize,
              color: isSelected
                  ? MedBuddyColors.primaryDark
                  : MedBuddyColors.primary,
              shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleCameraUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateCamera();
      }
    });
  }

  void _updateCamera() {
    if (!_isMapReady) {
      return;
    }

    final pharmacies = _mappablePharmacies;
    if (pharmacies.isEmpty) {
      return;
    }

    final selected = _findSelectedPharmacy(pharmacies);
    if (selected != null) {
      _mapController.move(LatLng(selected.latitude, selected.longitude), 16);
      return;
    }

    if (pharmacies.length == 1) {
      final pharmacy = pharmacies.first;
      _mapController.move(LatLng(pharmacy.latitude, pharmacy.longitude), 15);
      return;
    }

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: pharmacies
            .map((item) => LatLng(item.latitude, item.longitude))
            .toList(growable: false),
        padding: const EdgeInsets.fromLTRB(34, 58, 34, 34),
        maxZoom: 15,
      ),
    );
  }

  NearbyPharmacy? _findSelectedPharmacy(List<NearbyPharmacy> pharmacies) {
    for (final pharmacy in pharmacies) {
      if (pharmacy.pharmacyId == widget.selectedPharmacyId) {
        return pharmacy;
      }
    }
    return null;
  }

  void _changeZoom(double delta) {
    if (!_isMapReady) {
      return;
    }
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta).clamp(5.0, 19.0);
    _mapController.move(camera.center, nextZoom);
  }

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

  String _coordinateSignature(List<NearbyPharmacy> pharmacies) {
    return pharmacies
        .map(
          (pharmacy) =>
              '${pharmacy.pharmacyId}:${pharmacy.latitude}:${pharmacy.longitude}',
        )
        .join('|');
  }
}

class _MapControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

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

class _MapUnavailableState extends StatelessWidget {
  final String message;

  const _MapUnavailableState({required this.message});

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
