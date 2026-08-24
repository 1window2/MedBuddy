// File name: nearby_pharmacy_map_widget.dart
// Role: Shows nearby pharmacy coordinates on an embedded Naver map.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../entities/nearby_pharmacy_entity.dart';
import '../services/naver_map_config.dart';
import '../theme/medbuddy_theme.dart';

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
  NaverMapController? _mapController;
  int _overlayGeneration = 0;

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
      unawaited(_synchronizeMap());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pharmacies = _mappablePharmacies;
    if (!isNaverMapConfigured || pharmacies.isEmpty) {
      return _MapUnavailableState(message: widget.unavailableText);
    }

    final first = pharmacies.first;
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
    marker.setOnTapListener((_) => widget.onPharmacySelected(pharmacy));
    return marker;
  }

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
          pharmacies.map(
            (item) => NLatLng(item.latitude, item.longitude),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(34, 58, 34, 34),
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
    final controller = _mapController;
    if (controller != null) {
      unawaited(controller.updateCamera(NCameraUpdate.zoomBy(delta)));
    }
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
