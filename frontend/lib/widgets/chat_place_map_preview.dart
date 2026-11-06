// 공유된 병원·약국 좌표만 표시하는 지도. 사용자 위치 권한이나 새 검색은 요청하지 않는다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/naver_map_config.dart';
import '../theme/medbuddy_theme.dart';

class ChatPlaceMapPreview extends StatefulWidget {
  const ChatPlaceMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.isEnglish,
    required this.onOpen,
  });

  final double latitude;
  final double longitude;
  final bool isEnglish;
  final VoidCallback onOpen;

  static bool validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  @override
  State<ChatPlaceMapPreview> createState() => _ChatPlaceMapPreviewState();
}

class _ChatPlaceMapPreviewState extends State<ChatPlaceMapPreview> {
  Timer? _timeout;
  bool _loaded = false;
  bool _failed = false;

  bool get _supported =>
      !kIsWeb &&
      isNaverMapConfigured &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      ChatPlaceMapPreview.validCoordinates(widget.latitude, widget.longitude);

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _timeout = Timer(const Duration(seconds: 15), () {
        if (mounted && !_loaded) setState(() => _failed = true);
      });
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  // 지도 준비·마커 추가 실패는 상세 화면 이동으로 대체하고 채팅을 막지 않는다.
  Future<void> _ready(NaverMapController controller) async {
    try {
      await controller.addOverlay(
        NMarker(
          id: 'shared-place',
          position: NLatLng(widget.latitude, widget.longitude),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _failed) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Material(
          color: MedBuddyColors.surfaceSubtle,
          child: InkWell(
            key: const Key('chat-place-map-fallback'),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      color: MedBuddyColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.isEnglish ? 'View location' : '지도에서 위치 보기',
                        style: MedBuddyTextStyles.menuBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 136,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NaverMap(
            key: ValueKey('chat-map-${widget.latitude}-${widget.longitude}'),
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(widget.latitude, widget.longitude),
                zoom: 15,
              ),
              scrollGesturesEnable: false,
              zoomGesturesEnable: false,
              rotationGesturesEnable: false,
              tiltGesturesEnable: false,
              stopGesturesEnable: false,
              consumeSymbolTapEvents: false,
              scaleBarEnable: false,
              indoorLevelPickerEnable: false,
              locale: Locale(widget.isEnglish ? 'en' : 'ko'),
            ),
            onMapReady: (controller) => unawaited(_ready(controller)),
            onMapLoaded: () {
              _timeout?.cancel();
              if (mounted) setState(() => _loaded = true);
            },
            onMapTapped: (_, _) => widget.onOpen(),
          ),
          if (!_loaded)
            // 지도를 완전히 덮으면 네이티브 렌더링 완료 신호가 오지 않을 수 있다.
            Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MedBuddyColors.surface.withValues(alpha: .9),
                    borderRadius: MedBuddyRadii.small,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      widget.isEnglish ? 'Loading map...' : '지도 불러오는 중...',
                      style: MedBuddyTextStyles.menuBody.copyWith(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
