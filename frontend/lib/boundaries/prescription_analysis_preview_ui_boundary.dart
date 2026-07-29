import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/medication_schedule_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';

// 타입명: MedicationScheduleChangedCallback
// 역할: 수정된 OCR 복약 일정과 원본 목록 인덱스를 상위 상태에 전달한다.
typedef MedicationScheduleChangedCallback =
    void Function(int scheduleIndex, MedicationSchedule medicationSchedule);

// 파일명: prescription_analysis_preview_ui_boundary.dart
// 역할: UC-1 OCR 결과를 사용자에게 먼저 확인시키는 분석 예비 화면을 구성한다.

// 클래스명: PrescriptionAnalysisPreviewUI
// 역할: 처방전에서 인식된 약 목록과 복약 횟수를 페이지 단위로 보여준다.
// 주요 책임:
// - OCR 결과가 여러 개인 경우 PageView로 나누어 보여준다.
// - 신뢰도가 낮거나 잘못 인식된 OCR 결과를 사용자가 직접 수정하게 한다.
// - 사용자가 인식 결과를 확인한 뒤 실제 약품 상세 분석을 시작하게 한다.
// - 분석 전에 뒤로가기를 통해 촬영 단계로 돌아갈 수 있게 한다.
class PrescriptionAnalysisPreviewUI extends StatefulWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final List<RecognizedTextRegion> recognizedTextRegions;
  final String previewImagePath;
  final String recognitionNotice;
  final UserSetting userSetting;
  final VoidCallback onBackRequested;
  final VoidCallback onAnalysisRequested;
  final MedicationScheduleChangedCallback onMedicationScheduleChanged;

  const PrescriptionAnalysisPreviewUI({
    super.key,
    required this.medicationScheduleList,
    this.recognizedTextRegions = const [],
    this.previewImagePath = '',
    this.recognitionNotice = '',
    required this.userSetting,
    required this.onBackRequested,
    required this.onAnalysisRequested,
    required this.onMedicationScheduleChanged,
  });

  @override
  State<PrescriptionAnalysisPreviewUI> createState() =>
      _PrescriptionAnalysisPreviewUIState();
}

class _PrescriptionAnalysisPreviewUIState
    extends State<PrescriptionAnalysisPreviewUI> {
  static const int _itemsPerPage = 4;

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _PreviewText(widget.userSetting.language);
    final scale = widget.userSetting.contentTextScale;
    final pageCount = _pageCount;
    final recognitionNotice = widget.recognitionNotice.trim();
    final hasNameCorrection = widget.medicationScheduleList.any(
      (schedule) => schedule.hasNameCorrection,
    );
    final systemTextScale = MediaQuery.textScalerOf(context).scale(18) / 18;
    final effectiveTextScale = scale * systemTextScale;
    final medicationPageHeight = _resolveMedicationPageHeight(
      hasNameCorrection: hasNameCorrection,
      effectiveTextScale: effectiveTextScale,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _AnalysisBottomBar(
        label: text.analyze,
        scale: scale,
        onPressed: widget.onAnalysisRequested,
      ),
      body: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MedBuddyColors.analysisBackground, Colors.white],
            ),
          ),
          child: Column(
            children: [
              _TopBackButton(
                tooltip: text.back,
                onBackRequested: widget.onBackRequested,
              ),
              Expanded(
                child: _ScrollableCenteredCard(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(31, 32, 31, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: MedBuddyColors.outline,
                        width: 2,
                      ),
                      boxShadow: MedBuddyShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text.title(DateTime.now()),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 26 * scale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        if (recognitionNotice.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _RecognitionNoticeBanner(
                            message: recognitionNotice,
                            scale: scale,
                          ),
                          const SizedBox(height: 20),
                        ] else
                          const SizedBox(height: 26),
                        if (widget.previewImagePath.trim().isNotEmpty) ...[
                          _RecognizedTextRegionPreview(
                            imagePath: widget.previewImagePath,
                            regions: widget.recognizedTextRegions,
                            previewText: text,
                            scale: scale,
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          height: medicationPageHeight,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: pageCount,
                            onPageChanged: (index) {
                              setState(() => _currentPageIndex = index);
                            },
                            itemBuilder: (context, pageIndex) {
                              return _PreviewMedicationPage(
                                medicationScheduleList: _pageItems(pageIndex),
                                firstScheduleIndex: pageIndex * _itemsPerPage,
                                previewText: text,
                                userSetting: widget.userSetting,
                                onEditRequested: _showMedicationEditor,
                              );
                            },
                          ),
                        ),
                        if (_remainingCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            text.moreCount(_remainingCount),
                            style: TextStyle(
                              color: MedBuddyColors.textLight,
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int index = 0; index < pageCount; index++)
                              _PreviewDot(
                                active: index == _currentPageIndex,
                                onTap: () => _animateToPage(index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int get _pageCount {
    final count = (widget.medicationScheduleList.length / _itemsPerPage).ceil();
    return count <= 0 ? 1 : count;
  }

  int get _remainingCount {
    final shownCount = (_currentPageIndex + 1) * _itemsPerPage;
    final remainingCount = widget.medicationScheduleList.length - shownCount;
    return remainingCount > 0 ? remainingCount : 0;
  }

  List<MedicationSchedule> _pageItems(int pageIndex) {
    final start = pageIndex * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(
      0,
      widget.medicationScheduleList.length,
    );
    if (start >= widget.medicationScheduleList.length) {
      return const [];
    }
    return widget.medicationScheduleList.sublist(start, end);
  }

  // 함수이름: _resolveMedicationPageHeight
  // 함수역할:
  // - 수정 버튼, 신뢰도 배지, OCR 원문을 포함한 최대 네 행의 필요 높이를 계산한다.
  // - 글자 크기가 커진 경우에도 PageView 내부가 넘치지 않도록 여유 높이를 반영한다.
  // 매개변수:
  // - hasNameCorrection: OCR 원문을 추가로 표시할 항목이 있는지 여부
  // - effectiveTextScale: 앱 설정과 시스템 접근성 설정을 합친 글자 배율
  // 반환값:
  // - OCR 결과 PageView에 적용할 높이
  double _resolveMedicationPageHeight({
    required bool hasNameCorrection,
    required double effectiveTextScale,
  }) {
    final medicationCount = widget.medicationScheduleList.length;
    final visibleRowCount = medicationCount <= 0
        ? 1
        : medicationCount > _itemsPerPage
        ? _itemsPerPage
        : medicationCount;
    final rowHeight = hasNameCorrection ? 52.0 : 44.0;
    final dividerHeight = (visibleRowCount - 1) * 22.0;
    final requiredHeight = visibleRowCount * rowHeight + dividerHeight;
    final minimumHeight = hasNameCorrection ? 238.0 : 206.0;
    final baseHeight = requiredHeight > minimumHeight
        ? requiredHeight
        : minimumHeight;
    final appliedScale = effectiveTextScale > 1 ? effectiveTextScale : 1.0;
    return baseHeight * appliedScale + 24;
  }

  void _animateToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  // 함수이름: _showMedicationEditor
  // 함수역할:
  // - 선택한 OCR 인식 결과를 수정하는 대화상자를 연다.
  // - 수정이 완료되면 목록의 실제 인덱스와 변경값을 상위 상태로 전달한다.
  // 매개변수:
  // - scheduleIndex: 전체 OCR 결과 목록에서 수정할 항목의 인덱스
  // - medicationSchedule: 대화상자에 표시할 현재 OCR 인식 결과
  // 반환값:
  // - 없음
  Future<void> _showMedicationEditor(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) async {
    final updatedSchedule = await showDialog<MedicationSchedule>(
      context: context,
      builder: (context) => _MedicationScheduleEditDialog(
        medicationSchedule: medicationSchedule,
        previewText: _PreviewText(widget.userSetting.language),
        userSetting: widget.userSetting,
      ),
    );
    if (!mounted || updatedSchedule == null) {
      return;
    }

    widget.onMedicationScheduleChanged(scheduleIndex, updatedSchedule);
  }
}

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
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var index = 0; index < widget.regions.length; index++)
                      _buildRegionBox(
                        constraints: constraints,
                        region: widget.regions[index],
                        index: index,
                      ),
                    if (widget.regions.isEmpty)
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
              color: const Color(0xFF374151),
              border: Border.all(color: const Color(0xFF111827), width: 1),
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

class _PreviewMedicationPage extends StatelessWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final int firstScheduleIndex;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final MedicationScheduleChangedCallback onEditRequested;

  const _PreviewMedicationPage({
    required this.medicationScheduleList,
    required this.firstScheduleIndex,
    required this.previewText,
    required this.userSetting,
    required this.onEditRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < medicationScheduleList.length; index++) ...[
          _PreviewMedicationRow(
            schedule: medicationScheduleList[index],
            scheduleIndex: firstScheduleIndex + index,
            previewText: previewText,
            userSetting: userSetting,
            onEditRequested: () => onEditRequested(
              firstScheduleIndex + index,
              medicationScheduleList[index],
            ),
          ),
          if (index != medicationScheduleList.length - 1)
            const Divider(height: 22),
        ],
      ],
    );
  }
}

class _PreviewMedicationRow extends StatelessWidget {
  final MedicationSchedule schedule;
  final int scheduleIndex;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final VoidCallback onEditRequested;

  const _PreviewMedicationRow({
    required this.schedule,
    required this.scheduleIndex,
    required this.previewText,
    required this.userSetting,
    required this.onEditRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final frequency = schedule.intakeTime.trim().isEmpty
        ? previewText.noInformation
        : schedule.intakeTime.trim();
    final isUserEdited = schedule.nameCorrectionSource == 'user_edit';
    final needsReview =
        schedule.nameCorrectionSource == 'unverified' ||
        (schedule.nameConfidence > 0 && schedule.nameConfidence < 0.75);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      schedule.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (isUserEdited) ...[
                    const SizedBox(width: 6),
                    _CorrectionBadge(
                      label: previewText.userEdited,
                      scale: scale,
                    ),
                  ] else if (schedule.hasNameCorrection) ...[
                    const SizedBox(width: 6),
                    _CorrectionBadge(
                      label: previewText.corrected,
                      scale: scale,
                    ),
                  ] else if (needsReview) ...[
                    const SizedBox(width: 6),
                    _CorrectionBadge(
                      label: previewText.reviewNeeded,
                      scale: scale,
                      isWarning: true,
                    ),
                  ],
                ],
              ),
              if (schedule.hasNameCorrection) ...[
                const SizedBox(height: 3),
                Text(
                  previewText.correctedFrom(schedule.rawMedicationName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textLight,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 56),
          child: Text(
            frequency,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        IconButton(
          key: Key('ocr-edit-$scheduleIndex'),
          tooltip: previewText.edit,
          onPressed: onEditRequested,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          icon: Icon(
            Icons.edit_outlined,
            size: 20 * scale,
            color: MedBuddyColors.primaryDark,
          ),
        ),
      ],
    );
  }
}

class _CorrectionBadge extends StatelessWidget {
  final String label;
  final double scale;
  final bool isWarning;

  const _CorrectionBadge({
    required this.label,
    required this.scale,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF4D6) : const Color(0xFFE6F7F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isWarning
              ? const Color(0xFF9A6700)
              : MedBuddyColors.primaryDark,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _MedicationScheduleEditDialog
// 역할: OCR로 인식된 약명과 복약 정보를 사용자가 수정하는 입력 창을 제공한다.
// 주요 책임:
// - 약명, 조제일자, 투약량, 횟수, 투약일의 현재 값을 입력란에 표시한다.
// - 실제 복약할 아침·점심·저녁·취침 전 시간대를 사용자가 확인하게 한다.
// - 입력 형식을 검증한 뒤 변경된 복약 일정 객체를 반환한다.
class _MedicationScheduleEditDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final _PreviewText previewText;
  final UserSetting userSetting;

  const _MedicationScheduleEditDialog({
    required this.medicationSchedule,
    required this.previewText,
    required this.userSetting,
  });

  @override
  State<_MedicationScheduleEditDialog> createState() =>
      _MedicationScheduleEditDialogState();
}

// 클래스명: _MedicationScheduleEditDialogState
// 역할: OCR 수정 입력값과 유효성 검사 상태를 대화상자의 생명주기에 맞춰 관리한다.
// 주요 책임:
// - 입력 컨트롤러를 생성하고 화면이 닫힐 때 안전하게 정리한다.
// - 유효한 입력만 MedicationSchedule로 변환해 호출 화면에 반환한다.
class _MedicationScheduleEditDialogState
    extends State<_MedicationScheduleEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _daysController;
  late final TextEditingController _prescriptionDateController;
  late Set<String> _selectedSlotKeys;
  bool _showSlotValidationError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.medicationSchedule.medicationName,
    );
    _dosageController = TextEditingController(
      text: widget.medicationSchedule.dosage,
    );
    _frequencyController = TextEditingController(
      text: widget.medicationSchedule.intakeTime,
    );
    _daysController = TextEditingController(
      text: widget.medicationSchedule.medicationTime <= 0
          ? ''
          : widget.medicationSchedule.medicationTime.toString(),
    );
    _prescriptionDateController = TextEditingController(
      text: _formatDate(
        widget.medicationSchedule.prescriptionDate ?? DateTime.now(),
      ),
    );
    _selectedSlotKeys = widget.medicationSchedule.slotKeys.toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _daysController.dispose();
    _prescriptionDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.previewText;
    final scale = widget.userSetting.contentTextScale;

    return AlertDialog(
      title: Text(
        text.editTitle,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 21 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('ocr-edit-name'),
                controller: _nameController,
                autofocus: true,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.medicationName),
                validator: (value) => value == null || value.trim().isEmpty
                    ? text.medicationNameRequired
                    : null,
              ),
              TextFormField(
                key: const Key('ocr-edit-prescription-date'),
                controller: _prescriptionDateController,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: text.prescriptionDate,
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: text.chooseDate,
                    onPressed: _selectPrescriptionDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                validator: _validatePrescriptionDate,
              ),
              TextFormField(
                key: const Key('ocr-edit-dosage'),
                controller: _dosageController,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dosage),
              ),
              TextFormField(
                key: const Key('ocr-edit-frequency'),
                controller: _frequencyController,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dailyFrequency),
              ),
              TextFormField(
                key: const Key('ocr-edit-days'),
                controller: _daysController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: text.totalDays),
                validator: _validateMedicationDays,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text.scheduleSlots,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slotKey in medicationScheduleSlotKeys)
                    FilterChip(
                      key: Key('ocr-edit-slot-$slotKey'),
                      label: Text(text.slotLabel(slotKey)),
                      selected: _selectedSlotKeys.contains(slotKey),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedSlotKeys.add(slotKey);
                          } else {
                            _selectedSlotKeys.remove(slotKey);
                          }
                          _showSlotValidationError = false;
                        });
                      },
                    ),
                ],
              ),
              if (_showSlotValidationError) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.scheduleSlotRequired,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12 * scale,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ocr-edit-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          key: const Key('ocr-edit-save'),
          onPressed: _submit,
          child: Text(text.apply),
        ),
      ],
    );
  }

  // 함수이름: _validateMedicationDays
  // 함수역할:
  // - 총 투약일 입력값이 비어 있거나 허용 범위의 양의 정수인지 확인한다.
  // 매개변수:
  // - value: 사용자가 입력한 총 투약일 문자열
  // 반환값:
  // - 유효하면 null, 유효하지 않으면 화면에 표시할 오류 문구
  String? _validateMedicationDays(String? value) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      return null;
    }
    final medicationDays = int.tryParse(trimmedValue);
    if (medicationDays == null ||
        medicationDays <= 0 ||
        medicationDays > 3650) {
      return widget.previewText.invalidTotalDays;
    }
    return null;
  }

  // 함수명: _validatePrescriptionDate
  // 역할:
  // - 조제일자가 실제 달력에 존재하는 YYYY-MM-DD 형식인지 확인한다.
  String? _validatePrescriptionDate(String? value) {
    return _parseDate(value?.trim() ?? '') == null
        ? widget.previewText.invalidPrescriptionDate
        : null;
  }

  // 함수명: _selectPrescriptionDate
  // 역할:
  // - 달력에서 조제일자를 선택하고 직접 입력 필드에 반영한다.
  Future<void> _selectPrescriptionDate() async {
    final initialDate =
        _parseDate(_prescriptionDateController.text.trim()) ?? DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || selectedDate == null) {
      return;
    }
    setState(() {
      _prescriptionDateController.text = _formatDate(selectedDate);
    });
  }

  // 함수이름: _submit
  // 함수역할:
  // - 수정 입력값을 검증하고 변경된 복약 일정 객체를 호출 화면으로 반환한다.
  // 반환값:
  // - 없음
  void _submit() {
    final hasSelectedSlot = _selectedSlotKeys.isNotEmpty;
    if (!hasSelectedSlot) {
      setState(() => _showSlotValidationError = true);
    }
    if (!(_formKey.currentState?.validate() ?? false) || !hasSelectedSlot) {
      return;
    }

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: _nameController.text.trim(),
        dosage: _dosageController.text.trim(),
        intakeTime: _frequencyController.text.trim(),
        medicationTime: int.tryParse(_daysController.text.trim()) ?? 0,
        prescriptionDate: _parseDate(_prescriptionDateController.text.trim()),
        scheduleSlotKeys: medicationScheduleSlotKeys
            .where(_selectedSlotKeys.contains)
            .toList(growable: false),
      ),
    );
  }

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsedDate = DateTime(year, month, day);
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      return null;
    }
    return parsedDate;
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class _PreviewDot extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _PreviewDot({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: active ? MedBuddyColors.primary : MedBuddyColors.outline,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PreviewText {
  final String language;

  const _PreviewText(this.language);

  bool get isEnglish => language == 'en';

  String get back => isEnglish ? 'Back' : '뒤로가기';
  String get analyze => isEnglish ? 'Analyze' : '분석하기';
  String get noInformation => isEnglish ? 'No info' : '정보 없음';
  String get corrected => isEnglish ? 'Corrected' : '보정';
  String get userEdited => isEnglish ? 'Edited' : '사용자 수정';
  String get reviewNeeded => isEnglish ? 'Review' : '검토 필요';
  String get edit => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get editTitle => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  String get dosage => isEnglish ? 'Dose per intake' : '1회 투약량';
  String get dailyFrequency => isEnglish ? 'Daily frequency' : '1일 횟수';
  String get totalDays => isEnglish ? 'Total days' : '총 투약일';
  String get cancel => isEnglish ? 'Cancel' : '취소';
  String get apply => isEnglish ? 'Apply' : '적용';
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  String get prescriptionDate => isEnglish ? 'Dispensing date' : '조제일자';
  String get chooseDate => isEnglish ? 'Choose date' : '날짜 선택';
  String get invalidPrescriptionDate => isEnglish
      ? 'Enter a valid date as YYYY-MM-DD.'
      : '올바른 날짜를 YYYY-MM-DD 형식으로 입력해주세요.';
  String get scheduleSlots => isEnglish ? 'Medication times' : '실제 복약 시간대';
  String get scheduleSlotRequired => isEnglish
      ? 'Select at least one medication time.'
      : '복약 시간대를 하나 이상 선택해주세요.';
  String get invalidTotalDays => isEnglish
      ? 'Enter a number between 1 and 3650.'
      : '1일 이상 3650일 이하의 숫자를 입력해주세요.';

  String slotLabel(String slotKey) {
    if (isEnglish) {
      return switch (slotKey) {
        'morning' => 'Morning',
        'lunch' => 'Lunch',
        'evening' => 'Evening',
        'bedtime' => 'Bedtime',
        _ => slotKey,
      };
    }
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => slotKey,
    };
  }

  String get recognizedRegionGuide => isEnglish
      ? 'Green boxes show medication text. Gray areas mask personal data.'
      : '초록색은 복약 정보 인식 영역이며 회색은 개인정보 마스킹 영역입니다.';
  String get imageUnavailable =>
      isEnglish ? 'Image preview unavailable' : '이미지를 표시할 수 없습니다.';
  String get regionUnavailable => isEnglish
      ? 'Region coordinates are unavailable. Review the list below.'
      : '인식 위치 정보가 없어 아래 추출 목록을 확인해주세요.';
  String get privacyNotice => isEnglish
      ? 'The original image stays on this device. Only OCR text with detected '
            'personal identifiers removed is sent for medication analysis.'
      : '원본 이미지는 이 기기에만 남습니다. 기기에서 OCR한 뒤 감지된 개인정보를 제거한 '
            '복약 관련 텍스트만 분석 서버로 전송합니다.';
  String get sensitiveMaskLabel =>
      isEnglish ? 'Personal information masked' : '개인정보 마스킹';
  String get openImagePreview => isEnglish ? 'Open image preview' : '이미지 크게 보기';
  String get expandedImageTitle =>
      isEnglish ? 'Recognized image' : '인식 영역 상세보기';
  String get close => isEnglish ? 'Close' : '닫기';

  String correctedFrom(String rawName) {
    return isEnglish ? 'OCR: $rawName' : 'OCR 원문: $rawName';
  }

  String title(DateTime date) {
    if (isEnglish) {
      return '${date.month}/${date.day} Prescription';
    }

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday) 처방 내역';
  }

  String moreCount(int count) {
    return isEnglish ? '+$count more' : '+$count개 더 있음';
  }
}
