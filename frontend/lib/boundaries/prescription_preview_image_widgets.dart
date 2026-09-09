part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_image_widgets.dart
// 역할: OCR 좌표 표시, 개인정보 마스킹 및 처방전 확대 보기를 제공한다.

// 클래스명: _ScrollableCenteredCard
// 역할: 공간이 부족하면 스크롤되는 중앙 정렬 본문을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 공간이 부족하면 스크롤되는 중앙 정렬 본문 위젯을 구성한다.
// 속성:
// - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
class _ScrollableCenteredCard extends StatelessWidget {
  final Widget child;

  // 함수이름: _ScrollableCenteredCard
  // 함수역할: 공간이 부족하면 스크롤되는 중앙 정렬 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
  // 반환값: 입력 설정이 반영된 _ScrollableCenteredCard 인스턴스.
  const _ScrollableCenteredCard({required this.child});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 공간이 부족하면 스크롤되는 중앙 정렬 본문 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 공간이 부족하면 스크롤되는 중앙 정렬 본문에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // 함수이름: build.builder callback
      // 함수역할: 공간이 부족하면 스크롤되는 중앙 정렬 본문에 BoxConstraints을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context, constraints) {
        const padding = EdgeInsets.symmetric(vertical: 24, horizontal: 16);
        final centeredHeight = constraints.maxHeight > padding.vertical
            ? constraints.maxHeight - padding.vertical
            : 0.0;

        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: centeredHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 328),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

// 클래스명: _RecognitionNoticeBanner
// 역할: OCR 인식 결과의 검토 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 OCR 인식 결과의 검토 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _RecognitionNoticeBanner extends StatelessWidget {
  final String message;
  final double scale;

  // 함수이름: _RecognitionNoticeBanner
  // 함수역할: OCR 인식 결과의 검토 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _RecognitionNoticeBanner 인스턴스.
  const _RecognitionNoticeBanner({required this.message, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 OCR 인식 결과의 검토 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: OCR 인식 결과의 검토 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF5D565)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: const Color(0xFFB7791F),
            size: 16 * scale,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: const Color(0xFF8A5A12),
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _RecognizedTextRegionPreview
// 역할: OCR 사용 영역과 개인정보 마스킹을 표시한 사진을 담당한다.
// 주요 책임:
// - 0~1000 정규화 좌표를 화면 크기에 맞는 사각형으로 변환한다.
// - 복약 정보 인식 영역은 초록색으로, 민감정보 영역은 불투명하게 보여준다.
// - 사용자가 사진을 눌러 전체 화면에서 확대해 확인하게 한다.
// 속성:
// - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
// - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _RecognizedTextRegionPreview extends StatelessWidget {
  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final double scale;

  // 함수이름: _RecognizedTextRegionPreview
  // 함수역할: OCR 사용 영역과 개인정보 마스킹을 표시한 사진에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _RecognizedTextRegionPreview 인스턴스.
  const _RecognizedTextRegionPreview({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 OCR 사용 영역과 개인정보 마스킹을 표시한 사진 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: OCR 사용 영역과 개인정보 마스킹을 표시한 사진에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.document_scanner_outlined,
              size: 17,
              color: MedBuddyColors.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                previewText.recognizedRegionGuide,
                style: const TextStyle(
                  color: MedBuddyColors.textBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Tooltip(
          message: previewText.openImagePreview,
          child: Semantics(
            button: true,
            label: previewText.openImagePreview,
            child: InkWell(
              key: const Key('ocr-preview-image'),
              borderRadius: BorderRadius.circular(8),
              // 함수이름: build.onTap callback
              // 함수역할: OCR 사용 영역과 개인정보 마스킹을 표시한 사진에서 캡처된 작업 `_showExpandedPreview(context)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onTap: () => _showExpandedPreview(context),
              child: Stack(
                children: [
                  _RecognizedImageCanvas(
                    imagePath: imagePath,
                    regions: regions,
                    previewText: previewText,
                    keyPrefix: 'ocr',
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(
                            Icons.open_in_full,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 함수이름: _showExpandedPreview
  // 함수역할: OCR 영역과 개인정보 마스킹이 유지된 원본 이미지를 전체 화면으로 연다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showExpandedPreview(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: previewText.close,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 180),
      // 함수이름: _showExpandedPreview.pageBuilder callback
      // 함수역할: OCR 사용 영역과 개인정보 마스킹을 표시한 사진에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - animation (Animation<double>): 대화상자 전환의 주 또는 보조 애니메이션.
      // - secondaryAnimation (Animation<double>): 대화상자 전환의 주 또는 보조 애니메이션.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ExpandedRecognizedImageView(
          imagePath: imagePath,
          regions: regions,
          previewText: previewText,
          scale: scale,
        );
      },
      // 함수이름: _showExpandedPreview.transitionBuilder callback
      // 함수역할: 확대 이미지 콘텐츠에 화면 전환 애니메이션의 투명도를 적용한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - animation (Animation<double>): 대화상자 전환의 주 또는 보조 애니메이션.
      // - secondaryAnimation (Animation<double>): 대화상자 전환의 주 또는 보조 애니메이션.
      // - child (콜백 계약에서 추론): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}

// 클래스명: _RecognizedImageCanvas
// 역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치를 담당한다.
// 주요 책임:
// - 작은 미리보기와 전체 화면 확대 보기에서 같은 영역 표시 규칙을 공유한다.
// - 정규화 좌표를 현재 이미지 크기에 맞는 화면 좌표로 변환한다.
// 속성:
// - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
// - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
// - keyPrefix (String): 관련 하위 위젯 키를 구분하는 접두어.
class _RecognizedImageCanvas extends StatefulWidget {
  static const double _fallbackPrescriptionAspectRatio = 21.5 / 15;

  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final String keyPrefix;

  // 함수이름: _RecognizedImageCanvas
  // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - keyPrefix (String): 관련 하위 위젯 키를 구분하는 접두어.
  // 반환값: 입력 설정이 반영된 _RecognizedImageCanvas 인스턴스.
  const _RecognizedImageCanvas({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.keyPrefix,
  });

  // 함수이름: createState
  // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _RecognizedImageCanvasState 인스턴스.
  @override
  State<_RecognizedImageCanvas> createState() => _RecognizedImageCanvasState();
}

// 클래스명: _RecognizedImageCanvasState
// 역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치의 화면 상태를 관리한다.
// 주요 책임:
// - 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 필요한 상태 변경과 사용자 동작을 연결한다.
class _RecognizedImageCanvasState extends State<_RecognizedImageCanvas> {
  double _aspectRatio = _RecognizedImageCanvas._fallbackPrescriptionAspectRatio;
  String _resolvedImagePath = '';
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  // 함수이름: didChangeDependencies
  // 함수역할: 이미지 설정에 영향을 주는 상위 의존성 변경 후 원본 이미지 비율을 다시 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspectRatio();
  }

  // 함수이름: didUpdateWidget
  // 함수역할: 사진 경로가 바뀌면 기존 비율을 기본값으로 되돌리고 새 이미지 비율을 요청한다.
  // 매개변수:
  // - oldWidget (_RecognizedImageCanvas): 변경 전 입력값과 비교할 이전 위젯.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void didUpdateWidget(covariant _RecognizedImageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _resolvedImagePath = '';
      _aspectRatio = _RecognizedImageCanvas._fallbackPrescriptionAspectRatio;
      _resolveAspectRatio();
    }
  }

  // 함수이름: dispose
  // 함수역할: 화면이 소유한 자원 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _removeImageStreamListener();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: Key('${widget.keyPrefix}-image-canvas'),
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: MedBuddyColors.surfaceSubtle,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                // 함수이름: build.errorBuilder callback
                // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
                // 매개변수:
                // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                // - error (콜백 계약에서 추론): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
                // - stackTrace (콜백 계약에서 추론): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
                // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      widget.previewText.imageUnavailable,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            LayoutBuilder(
              // 함수이름: build.builder callback
              // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 EdgeInsets.symmetric, TextStyle을 적용해 현재 배치를 구성한다.
              // 매개변수:
              // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
              // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
              // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
              builder: (context, constraints) {
                final hasVisibleRegions = widget.regions.any(
                  // 함수이름: build.any callback
                  // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 대해 `region.isVisibleInPreview` 조건으로 컬렉션 항목을 판별한다.
                  // 매개변수:
                  // - region (콜백 계약에서 추론): 이미지 좌표에 표시할 정규화 OCR 영역.
                  // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
                  (region) => region.isVisibleInPreview,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var index = 0; index < widget.regions.length; index++)
                      if (widget.regions[index].isVisibleInPreview)
                        _buildRegionBox(
                          constraints: constraints,
                          region: widget.regions[index],
                          index: index,
                        ),
                    if (!hasVisibleRegions)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          color: Colors.black.withValues(alpha: 0.62),
                          child: Text(
                            widget.previewText.regionUnavailable,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _resolveAspectRatio
  // 함수역할: 화면 렌더링과 같은 FileImage 스트림에서 이미지의 실제 종횡비를 가져온다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _resolveAspectRatio() {
    if (_resolvedImagePath == widget.imagePath) {
      return;
    }
    _resolvedImagePath = widget.imagePath;
    _removeImageStreamListener();
    final imageStream = FileImage(
      File(widget.imagePath),
    ).resolve(createLocalImageConfiguration(context));
    // 함수이름: _resolveAspectRatio.ImageStreamListener callback
    // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에서 캡처된 작업 `setState(() => _aspectRatio = nextAspectRatio)`을 실행한다.
    // 매개변수:
    // - imageInfo (콜백 계약에서 추론): 해석된 이미지의 실제 너비·높이 정보.
    // - synchronousCall (bool): 이미지 리스너가 동기적으로 호출되었는지 여부; 본문에서는 사용하지 않음.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    final listener = ImageStreamListener((imageInfo, synchronousCall) {
      final width = imageInfo.image.width;
      final height = imageInfo.image.height;
      if (!mounted || width <= 0 || height <= 0) {
        return;
      }
      final nextAspectRatio = width / height;
      if (_aspectRatio == nextAspectRatio) {
        return;
      }
      // 함수이름: _resolveAspectRatio.setState callback
      // 함수역할: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치의 입력·요청 상태를 `_aspectRatio = nextAspectRatio`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _aspectRatio = nextAspectRatio);
    // 함수이름: _resolveAspectRatio.onError callback
    // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
    // 매개변수:
    // - error (콜백 계약에서 추론): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
    // - stackTrace (콜백 계약에서 추론): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    }, onError: (error, stackTrace) {});
    _imageStream = imageStream;
    _imageStreamListener = listener;
    imageStream.addListener(listener);
  }

  // 함수이름: _removeImageStreamListener
  // 함수역할: 이전 이미지 스트림의 크기 수신기를 해제해 중복 갱신을 방지한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _removeImageStreamListener() {
    final imageStream = _imageStream;
    final listener = _imageStreamListener;
    if (imageStream != null && listener != null) {
      imageStream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  // 함수이름: _buildRegionBox
  // 함수역할: OCR 정규화 좌표를 현재 이미지 캔버스의 픽셀 좌표로 변환한다. 일반 인식 영역과 개인정보 마스킹 영역을 서로 다른 모양으로 표시한다.
  // 매개변수:
  // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
  // - region (RecognizedTextRegion): 이미지 좌표에 표시할 정규화 OCR 영역.
  // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // 반환값: 처방전 이미지와 정규화 OCR 영역의 공통 좌표 배치에 쓰는 위젯 트리.
  Widget _buildRegionBox({
    required BoxConstraints constraints,
    required RecognizedTextRegion region,
    required int index,
  }) {
    final top = region.box2d[0] / 1000 * constraints.maxHeight;
    final left = region.box2d[1] / 1000 * constraints.maxWidth;
    final bottom = region.box2d[2] / 1000 * constraints.maxHeight;
    final right = region.box2d[3] / 1000 * constraints.maxWidth;
    if (region.isSensitive) {
      return Positioned(
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
        child: Semantics(
          label: widget.previewText.sensitiveMaskLabel,
          child: DecoratedBox(
            key: Key('${widget.keyPrefix}-sensitive-region-$index'),
            decoration: BoxDecoration(
              color: const Color(0xFF9CA3AF),
              border: Border.all(color: const Color(0xFF4B5563), width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
      child: DecoratedBox(
        key: Key('${widget.keyPrefix}-region-$index'),
        decoration: BoxDecoration(
          color: MedBuddyColors.primary.withValues(alpha: 0.16),
          border: Border.all(color: MedBuddyColors.primary, width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

// 클래스명: _ExpandedRecognizedImageView
// 역할: 최대 5배 확대 가능한 OCR 처리 처방전 사진을 담당한다.
// 주요 책임:
// - 공통 이미지 캔버스를 최대 5배까지 확대할 수 있게 한다.
// - 닫기 동작으로 분석 예비 화면의 상태를 유지한 채 돌아간다.
// 속성:
// - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
// - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _ExpandedRecognizedImageView extends StatelessWidget {
  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final double scale;

  // 함수이름: _ExpandedRecognizedImageView
  // 함수역할: 최대 5배 확대 가능한 OCR 처리 처방전 사진에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - imagePath (String): 사진 미리보기 또는 확대에 사용할 로컬 파일 경로.
  // - regions (List<RecognizedTextRegion>): 이미지 좌표에 표시할 정규화 OCR 영역.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _ExpandedRecognizedImageView 인스턴스.
  const _ExpandedRecognizedImageView({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 최대 5배 확대 가능한 OCR 처리 처방전 사진 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 최대 5배 확대 가능한 OCR 처리 처방전 사진에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    key: const Key('ocr-expanded-close'),
                    tooltip: previewText.close,
                    // 함수이름: build.onPressed callback
                    // 함수역할: `Navigator.of(context).pop()`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      previewText.expandedImageTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                // 함수이름: build.builder callback
                // 함수역할: 최대 5배 확대 가능한 OCR 처리 처방전 사진에 Key, EdgeInsets.all을 적용해 현재 배치를 구성한다.
                // 매개변수:
                // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
                // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                builder: (context, constraints) {
                  return InteractiveViewer(
                    key: const Key('ocr-expanded-image-viewer'),
                    constrained: false,
                    minScale: 1,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: _RecognizedImageCanvas(
                        imagePath: imagePath,
                        regions: regions,
                        previewText: previewText,
                        keyPrefix: 'ocr-expanded',
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _PrivacyNoticeBanner(
                message: previewText.privacyNotice,
                scale: scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _PrivacyNoticeBanner
// 역할: 처방전 이미지 전송과 개인정보 처리 범위 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방전 이미지 전송과 개인정보 처리 범위 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _PrivacyNoticeBanner extends StatelessWidget {
  final String message;
  final double scale;

  // 함수이름: _PrivacyNoticeBanner
  // 함수역할: 처방전 이미지 전송과 개인정보 처리 범위 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _PrivacyNoticeBanner 인스턴스.
  const _PrivacyNoticeBanner({required this.message, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방전 이미지 전송과 개인정보 처리 범위 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방전 이미지 전송과 개인정보 처리 범위 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: MedBuddyColors.successSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MedBuddyColors.successBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: MedBuddyColors.primaryDark,
            size: 17 * scale,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: MedBuddyColors.textBody,
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _AnalysisBottomBar
// 역할: 스크롤과 무관하게 접근 가능한 분석 시작 명령을 담당한다.
// 주요 책임:
// - 본문 스크롤 위치와 관계없이 분석하기 버튼을 사용할 수 있게 한다.
// - 시스템 하단 영역과 겹치지 않도록 안전 영역을 반영한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _AnalysisBottomBar extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback? onPressed;

  // 함수이름: _AnalysisBottomBar
  // 함수역할: 스크롤과 무관하게 접근 가능한 분석 시작 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onPressed (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _AnalysisBottomBar 인스턴스.
  const _AnalysisBottomBar({
    required this.label,
    required this.scale,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 스크롤과 무관하게 접근 가능한 분석 시작 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 스크롤과 무관하게 접근 가능한 분석 시작 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: MedBuddyColors.outline.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              key: const Key('prescription-analyze-button'),
              style: FilledButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: MedBuddyRadii.card),
                textStyle: TextStyle(
                  fontSize: 19 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              onPressed: onPressed,
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _TopBackButton
// 역할: 처방전 검토에서 이전 단계로 이동을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방전 검토에서 이전 단계로 이동 위젯을 구성한다.
// 속성:
// - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
class _TopBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onBackRequested;

  // 함수이름: _TopBackButton
  // 함수역할: 처방전 검토에서 이전 단계로 이동에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - tooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _TopBackButton 인스턴스.
  const _TopBackButton({required this.tooltip, required this.onBackRequested});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방전 검토에서 이전 단계로 이동 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방전 검토에서 이전 단계로 이동에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(31, 37, 31, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onBackRequested,
          icon: const Icon(
            Icons.chevron_left,
            color: MedBuddyColors.textMuted,
            size: 31,
          ),
        ),
      ),
    );
  }
}
