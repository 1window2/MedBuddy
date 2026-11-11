// 파일명: chat_place_map_preview.dart
// 역할: 공유된 의료기관 좌표를 위치 권한 요청 없이 읽기 전용 지도로 표시한다.
// 공유된 병원·약국 좌표만 표시하는 지도. 사용자 위치 권한이나 새 검색은 요청하지 않는다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/naver_map_config.dart';
import '../theme/medbuddy_theme.dart';
import 'naver_map_sdk_gate.dart';
import 'keep_words_text.dart';

// 클래스명: ChatPlaceMapPreview
// 역할: 공유된 병원·약국 위치를 작고 읽기 전용인 지도로 보여 준다.
// 주요 책임: 좌표와 플랫폼 지원을 확인하고 지도 실패 시 상세 화면 이동을 유지한다.
// 속성: latitude/longitude (double): 공유 좌표; isEnglish (bool): 언어; onOpen (VoidCallback): 상세 화면 열기.
class ChatPlaceMapPreview extends StatefulWidget {
  // 함수이름: ChatPlaceMapPreview
  // 함수역할: 공유 좌표와 지도 탭 동작을 보관한다. 새 위치 검색이나 권한 요청은 하지 않는다.
  // 매개변수: key (Key?): 식별 키; latitude/longitude (double): 좌표; isEnglish (bool): 언어; onOpen (VoidCallback): 상세 이동.
  // 반환값: 지도 미리보기 위젯. 유효하지 않은 좌표는 build에서 대체 표시한다.
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

  // 함수이름: validCoordinates
  // 함수역할: 지도 SDK에 전달할 좌표의 유한성·범위를 검증하고 미설정 좌표 0,0을 제외한다.
  // 매개변수: latitude/longitude (double): 검사할 위도·경도.
  // 반환값: 위도 -90..90, 경도 -180..180이며 둘 다 0이 아니면 true.
  static bool validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  // 함수이름: createState
  // 함수역할: 지도 로딩과 실패 상태를 관리할 상태 객체를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _ChatPlaceMapPreviewState.
  @override
  State<ChatPlaceMapPreview> createState() => _ChatPlaceMapPreviewState();
}

// 클래스명: _ChatPlaceMapPreviewState
// 역할: 읽기 전용 지도 초기화·시간 초과·대체 표시를 관리한다.
// 주요 책임: 지원 여부를 판단하고 마커 추가 실패나 로딩 지연을 상세 이동 버튼으로 바꾼다.
// 속성: _timeout (Timer?): 15초 대기; _loaded/_failed (bool): 로딩 완료·실패 상태.
class _ChatPlaceMapPreviewState extends State<ChatPlaceMapPreview> {
  Timer? _timeout;
  bool _loaded = false;
  bool _failed = false;

  // 함수이름: _supported
  // 함수역할: 네이버 지도 설정·네이티브 모바일 플랫폼·공유 좌표의 유효성을 함께 검사한다.
  // 매개변수: 없음.
  // 반환값: 웹이 아닌 Android/iOS이며 지도가 설정되고 좌표가 유효하면 true.
  bool get _supported =>
      !kIsWeb &&
      isNaverMapConfigured &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      ChatPlaceMapPreview.validCoordinates(widget.latitude, widget.longitude);

  // 함수이름: initState
  // 함수역할: 지원되는 지도에만 15초 로딩 제한 타이머를 시작한다.
  // 매개변수: 없음.
  // 반환값: 없음. 제한 시점에도 마운트되어 있고 로딩 전이면 실패 표시로 바꾼다.
  @override
  void initState() {
    super.initState();
    if (_supported) {
      _timeout = Timer(const Duration(seconds: 15), () {
        if (mounted && !_loaded) setState(() => _failed = true);
      });
    }
  }

  // 함수이름: dispose
  // 함수역할: 화면 제거 뒤 타이머가 상태를 바꾸지 않도록 로딩 제한을 취소한다.
  // 매개변수: 없음.
  // 반환값: 없음. 지도 컨트롤러는 보관하거나 직접 정리하지 않는다.
  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  // 지도 준비·마커 추가 실패는 상세 화면 이동으로 대체하고 채팅을 막지 않는다.
  // 함수이름: _ready
  // 함수역할: 공유 좌표에 마커를 추가하고 SDK 실패 시 대체 표시를 선택한다.
  // 매개변수: controller (NaverMapController): 준비된 지도 컨트롤러.
  // 반환값: 마커 추가 시도 완료 Future. 예외는 삼키고 마운트 상태에서만 실패 표시를 갱신한다.
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

  // 함수이름: build
  // 함수역할: 제스처를 끈 좌표 지도를 표시하고 미지원·실패 시 상세 이동 버튼을 제공한다.
  // 매개변수: context (BuildContext): 현재 위젯 위치.
  // 반환값: 136px 지도와 로딩 표시 또는 대체 버튼. 어느 경로에서도 onOpen으로 상세 위치를 열 수 있다.
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
                      child: KeepWordsText(
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
          NaverMapSdkGate(
            placeholder: const SizedBox.shrink(),
            builder: (context) => NaverMap(
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
                    child: KeepWordsText(
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
