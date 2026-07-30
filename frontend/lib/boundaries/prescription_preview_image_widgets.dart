part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_image_widgets.dart
// 역할: OCR 인식 영역, 개인정보 마스킹, 확대 이미지와 공통 레이아웃을 구성한다.

class _ScrollableCenteredCard extends StatelessWidget {
  final Widget child;

  const _ScrollableCenteredCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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

class _RecognitionNoticeBanner extends StatelessWidget {
  final String message;
  final double scale;

  const _RecognitionNoticeBanner({required this.message, required this.scale});

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
// 역할: 원본 처방전 이미지 위에 OCR이 복약 정보로 사용한 영역을 표시한다.
// 주요 책임:
// - 0~1000 정규화 좌표를 화면 크기에 맞는 사각형으로 변환한다.
// - 복약 정보 인식 영역은 초록색으로, 민감정보 영역은 불투명하게 보여준다.
// - 사용자가 사진을 눌러 전체 화면에서 확대해 확인하게 한다.
class _RecognizedTextRegionPreview extends StatelessWidget {
  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final double scale;

  const _RecognizedTextRegionPreview({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.scale,
  });

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
  // 함수역할:
  // - OCR 영역과 개인정보 마스킹이 유지된 원본 이미지를 전체 화면으로 연다.
  // 매개변수:
  // - context: 전체 화면 경로를 열 현재 화면의 BuildContext
  // 반환값:
  // - 확대 화면이 닫힐 때 완료되는 Future
  Future<void> _showExpandedPreview(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: previewText.close,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ExpandedRecognizedImageView(
          imagePath: imagePath,
          regions: regions,
          previewText: previewText,
          scale: scale,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}

// 클래스명: _RecognizedImageCanvas
// 역할: 처방전 이미지와 OCR 영역, 개인정보 마스킹을 동일한 좌표계에 그린다.
// 주요 책임:
// - 작은 미리보기와 전체 화면 확대 보기에서 같은 영역 표시 규칙을 공유한다.
// - 정규화 좌표를 현재 이미지 크기에 맞는 화면 좌표로 변환한다.
class _RecognizedImageCanvas extends StatefulWidget {
  static const double _fallbackPrescriptionAspectRatio = 21.5 / 15;

  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final String keyPrefix;

  const _RecognizedImageCanvas({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.keyPrefix,
  });

  @override
  State<_RecognizedImageCanvas> createState() => _RecognizedImageCanvasState();
}

class _RecognizedImageCanvasState extends State<_RecognizedImageCanvas> {
  double _aspectRatio = _RecognizedImageCanvas._fallbackPrescriptionAspectRatio;
  String _resolvedImagePath = '';
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _RecognizedImageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _resolvedImagePath = '';
      _aspectRatio = _RecognizedImageCanvas._fallbackPrescriptionAspectRatio;
      _resolveAspectRatio();
    }
  }

  @override
  void dispose() {
    _removeImageStreamListener();
    super.dispose();
  }

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
              builder: (context, constraints) {
                final hasVisibleRegions = widget.regions.any(
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
  // 함수역할:
  // - 화면 렌더링과 같은 FileImage 스트림에서 이미지의 실제 종횡비를 가져온다.
  // 매개변수:
  // - 없음
  // 반환값:
  // - 없음
  void _resolveAspectRatio() {
    if (_resolvedImagePath == widget.imagePath) {
      return;
    }
    _resolvedImagePath = widget.imagePath;
    _removeImageStreamListener();
    final imageStream = FileImage(
      File(widget.imagePath),
    ).resolve(createLocalImageConfiguration(context));
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
      setState(() => _aspectRatio = nextAspectRatio);
    }, onError: (error, stackTrace) {});
    _imageStream = imageStream;
    _imageStreamListener = listener;
    imageStream.addListener(listener);
  }

  // 함수이름: _removeImageStreamListener
  // 함수역할:
  // - 이전 이미지 스트림의 크기 수신기를 해제해 중복 갱신을 방지한다.
  // 매개변수:
  // - 없음
  // 반환값:
  // - 없음
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
  // 함수역할:
  // - OCR 정규화 좌표를 현재 이미지 캔버스의 픽셀 좌표로 변환한다.
  // - 일반 인식 영역과 개인정보 마스킹 영역을 서로 다른 모양으로 표시한다.
  // 매개변수:
  // - constraints: 이미지 캔버스의 실제 화면 크기
  // - region: 표시할 OCR 영역 정보
  // - index: 위젯 식별 키에 사용할 영역 순번
  // 반환값:
  // - 계산한 위치와 크기로 배치된 OCR 영역 위젯
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
// 역할: OCR 처리 이미지를 전체 화면에서 확대하거나 이동해 확인하게 한다.
// 주요 책임:
// - 공통 이미지 캔버스를 최대 5배까지 확대할 수 있게 한다.
// - 닫기 동작으로 분석 예비 화면의 상태를 유지한 채 돌아간다.
class _ExpandedRecognizedImageView extends StatelessWidget {
  final String imagePath;
  final List<RecognizedTextRegion> regions;
  final _PreviewText previewText;
  final double scale;

  const _ExpandedRecognizedImageView({
    required this.imagePath,
    required this.regions,
    required this.previewText,
    required this.scale,
  });

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
// 역할: 처방전 이미지 전송과 개인정보 처리 범위를 사용자에게 정확히 안내한다.
class _PrivacyNoticeBanner extends StatelessWidget {
  final String message;
  final double scale;

  const _PrivacyNoticeBanner({required this.message, required this.scale});

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
// 역할: 분석 예비 화면의 주요 분석 동작을 화면 하단에 항상 표시한다.
// 주요 책임:
// - 본문 스크롤 위치와 관계없이 분석하기 버튼을 사용할 수 있게 한다.
// - 시스템 하단 영역과 겹치지 않도록 안전 영역을 반영한다.
class _AnalysisBottomBar extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onPressed;

  const _AnalysisBottomBar({
    required this.label,
    required this.scale,
    required this.onPressed,
  });

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

class _TopBackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onBackRequested;

  const _TopBackButton({required this.tooltip, required this.onBackRequested});

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
