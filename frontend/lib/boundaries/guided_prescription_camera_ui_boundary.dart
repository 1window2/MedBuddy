import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/prescription_camera_guide_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/camera_lifecycle_coordinator.dart';
import '../services/prescription_camera_layout_service.dart';
import '../services/prescription_camera_orientation_service.dart';
import '../services/prescription_frame_analyzer.dart';
import '../services/prescription_image_crop_service.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: guided_prescription_camera_ui_boundary.dart
// 역할: 처방전을 카메라 가이드 안에 맞춰 촬영하는 전용 화면을 제공한다.

// 클래스명: GuidedPrescriptionCameraUI
// 역할: 실시간 카메라 미리보기, 거리 안내, 촬영 결과 반환을 담당한다.
// 주요 책임:
// - 후면 카메라를 초기화하고 앱 생명주기에 맞춰 자원을 해제한다.
// - 처방전 후보가 화면에서 차지하는 비율을 주기적으로 분석한다.
// - 촬영한 이미지 파일을 기존 처방전 OCR 흐름으로 돌려보낸다.
// 속성:
// - userSetting: 화면 언어와 접근성 문구에 사용할 사용자 설정
class GuidedPrescriptionCameraUI extends StatefulWidget {
  final UserSetting userSetting;

  const GuidedPrescriptionCameraUI({super.key, required this.userSetting});

  @override
  State<GuidedPrescriptionCameraUI> createState() =>
      _GuidedPrescriptionCameraUIState();
}

class _GuidedPrescriptionCameraUIState extends State<GuidedPrescriptionCameraUI>
    with WidgetsBindingObserver {
  static const Duration _analysisInterval = Duration(milliseconds: 650);

  final PrescriptionFrameAnalyzer _frameAnalyzer =
      const PrescriptionFrameAnalyzer();
  final CameraLifecycleCoordinator _cameraLifecycleCoordinator =
      CameraLifecycleCoordinator();
  final PrescriptionCameraOrientationService _orientationService =
      const PrescriptionCameraOrientationService();
  final PrescriptionImageCropService _imageCropService =
      const PrescriptionImageCropService();
  CameraController? _cameraController;
  PrescriptionCameraGuideStatus _guideStatus =
      PrescriptionCameraGuideStatus.searching;
  DateTime? _lastAnalysisAt;
  String _cameraErrorMessage = '';
  bool _isAnalyzingFrame = false;
  bool _isCapturing = false;
  bool _isTorchEnabled = false;
  int _cameraGeneration = 0;
  Rect _normalizedGuideRect = const Rect.fromLTWH(0, 0, 1, 1);
  DeviceOrientation? _lastCameraOrientation;
  late final Future<void> _orientationActivation;

  bool get _isEnglish =>
      widget.userSetting.language.trim().toLowerCase().startsWith('en');

  _GuidedCameraText get _text => _GuidedCameraText(_isEnglish);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orientationActivation = _orientationService.enableSensorRotation();
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseCamera());
      return;
    }
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseCamera());
    unawaited(_restoreOrientation());
    super.dispose();
  }

  // 함수명: _restoreOrientation
  // 역할: 촬영 화면에서 허용한 센서 회전을 해제하고 기존 앱 방향 정책을 복원한다.
  Future<void> _restoreOrientation() async {
    await _orientationActivation;
    await _orientationService.restoreOrientation();
  }

  // 함수이름: _initializeCamera
  // 함수역할:
  // - 사용 가능한 후면 카메라를 찾아 미리보기와 프레임 분석을 시작한다.
  // 반환값:
  // - 없음
  Future<void> _initializeCamera() {
    return _cameraLifecycleCoordinator.schedule(_initializeCameraNow);
  }

  // Function Name: _initializeCameraNow
  // Description:
  // - Replaces the current controller and starts the back-camera preview.
  // - Runs only through CameraLifecycleCoordinator to avoid permission lifecycle races.
  // Returns:
  // - Completes after the camera is ready or a recoverable error is shown.
  Future<void> _initializeCameraNow() async {
    final generation = ++_cameraGeneration;
    await _disposeCurrentController();
    if (!mounted || generation != _cameraGeneration) {
      return;
    }

    setState(() {
      _cameraErrorMessage = '';
      _guideStatus = PrescriptionCameraGuideStatus.searching;
      _isTorchEnabled = false;
    });

    CameraController? initializingController;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('camera_unavailable', _text.cameraUnavailable);
      }
      final camera = cameras.firstWhere(
        (description) => description.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      initializingController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await initializingController.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await initializingController.dispose();
        return;
      }

      _cameraController = initializingController;
      initializingController = null;
      _lastCameraOrientation = _cameraController!.value.deviceOrientation;
      _cameraController!.addListener(_handleCameraOrientationChanged);
      await _cameraController!.setFlashMode(FlashMode.off);
      await _cameraController!.startImageStream(_analyzeCameraImage);
      if (mounted) {
        setState(() {});
      }
    } on CameraException catch (error) {
      await initializingController?.dispose();
      await _disposeCurrentController();
      _showCameraError(_cameraErrorText(error));
    } catch (_) {
      await initializingController?.dispose();
      await _disposeCurrentController();
      _showCameraError(_text.cameraUnavailable);
    }
  }

  // 함수이름: _releaseCamera
  // 함수역할:
  // - 앱이 백그라운드로 이동하거나 화면이 닫힐 때 카메라 자원을 해제한다.
  // 반환값:
  // - 없음
  Future<void> _releaseCamera() {
    return _cameraLifecycleCoordinator.schedule(_releaseCameraNow);
  }

  // Function Name: _releaseCameraNow
  // Description:
  // - Invalidates the active generation and releases the current camera controller.
  // - Runs only after earlier queued camera transitions have completed.
  // Returns:
  // - Completes after camera resources are released.
  Future<void> _releaseCameraNow() async {
    _cameraGeneration += 1;
    await _disposeCurrentController();
  }

  Future<void> _disposeCurrentController() async {
    final controller = _cameraController;
    _cameraController = null;
    _lastCameraOrientation = null;
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleCameraOrientationChanged);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // 카메라가 이미 중지된 경우에도 dispose는 계속 수행한다.
    }
    await controller.dispose();
  }

  // 함수명: _handleCameraOrientationChanged
  // 역할: 카메라 센서 방향이 달라지면 현재 화면 비율에 맞게 촬영 화면을 다시 구성한다.
  void _handleCameraOrientationChanged() {
    final orientation = _cameraController?.value.deviceOrientation;
    if (!mounted ||
        orientation == null ||
        orientation == _lastCameraOrientation) {
      return;
    }
    setState(() {
      _lastCameraOrientation = orientation;
    });
  }

  // 함수이름: _analyzeCameraImage
  // 함수역할:
  // - 일정 간격으로 밝기 평면을 분석해 처방전 거리 안내 상태를 갱신한다.
  // 매개변수:
  // - image: 카메라 플러그인이 전달한 실시간 프레임
  // 반환값:
  // - 없음
  void _analyzeCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (_isCapturing ||
        _isAnalyzingFrame ||
        (_lastAnalysisAt != null &&
            now.difference(_lastAnalysisAt!) < _analysisInterval) ||
        image.planes.isEmpty) {
      return;
    }

    _isAnalyzingFrame = true;
    _lastAnalysisAt = now;
    try {
      final luminancePlane = image.planes.first;
      final result = _frameAnalyzer.analyze(
        luminanceBytes: luminancePlane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: luminancePlane.bytesPerRow,
        bytesPerPixel: luminancePlane.bytesPerPixel ?? 1,
      );
      if (mounted && result.status != _guideStatus) {
        setState(() {
          _guideStatus = result.status;
        });
      }
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  // 함수이름: _capturePrescription
  // 함수역할:
  // - 현재 카메라 프레임을 저장하고 화면 가이드 안쪽만 잘라 호출 화면에 반환한다.
  // 반환값:
  // - 없음
  Future<void> _capturePrescription() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final image = await controller.takePicture();
      final croppedImage = await _imageCropService.cropToGuide(
        sourceImage: image,
        normalizedGuideRect: _normalizedGuideRect,
      );
      if (mounted) {
        Navigator.pop(context, croppedImage);
      }
    } catch (_) {
      await _recoverFromCaptureFailure(controller);
    }
  }

  // 함수이름: _recoverFromCaptureFailure
  // 함수역할:
  // - 촬영 실패 문구를 표시하고 실시간 거리 분석을 다시 시작한다.
  // 매개변수:
  // - controller: 촬영에 사용했던 카메라 제어 객체
  // 반환값:
  // - 없음
  Future<void> _recoverFromCaptureFailure(CameraController controller) async {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_text.captureFailed)));
    }
    try {
      if (controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(_analyzeCameraImage);
      }
    } on CameraException {
      // 스트림 복구가 불가능해도 사용자가 화면을 닫거나 다시 시도할 수 있게 상태를 해제한다.
    }
    if (mounted) {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  // 함수이름: _toggleTorch
  // 함수역할:
  // - 어두운 환경에서 사용할 후면 카메라 조명을 켜거나 끈다.
  // 반환값:
  // - 없음
  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      final shouldEnable = !_isTorchEnabled;
      await controller.setFlashMode(
        shouldEnable ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() {
          _isTorchEnabled = shouldEnable;
        });
      }
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_text.flashUnavailable)));
      }
    }
  }

  void _showCameraError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraErrorMessage = message;
    });
  }

  String _cameraErrorText(CameraException error) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt' ||
        error.code == 'CameraAccessRestricted') {
      return _text.permissionDenied;
    }
    return error.description?.trim().isNotEmpty == true
        ? error.description!.trim()
        : _text.cameraUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final preview = _cameraErrorMessage.isNotEmpty
                  ? _buildCameraError()
                  : _buildPreview(controller);
              final viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final cameraOrientation =
                  controller?.value.deviceOrientation ?? _lastCameraOrientation;
              final cameraReportsLandscape =
                  cameraOrientation == DeviceOrientation.landscapeLeft ||
                  cameraOrientation == DeviceOrientation.landscapeRight;
              final useLandscapeLayout =
                  PrescriptionCameraLayoutService.shouldUseLandscapeLayout(
                    viewportSize: viewportSize,
                    cameraReportsLandscape: cameraReportsLandscape,
                  );
              if (useLandscapeLayout) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildHeader(controller, isCompact: true),
                          Expanded(child: preview),
                        ],
                      ),
                    ),
                    SizedBox(
                      width:
                          PrescriptionCameraLayoutService.landscapePanelWidth(
                            viewportSize,
                          ),
                      child: _buildCapturePanel(controller, isLandscape: true),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _buildHeader(controller),
                  Expanded(child: preview),
                  _buildCapturePanel(controller),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(CameraController? controller, {bool isCompact = false}) {
    return SizedBox(
      height: isCompact ? 54 : 68,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: Colors.white,
          ),
          Expanded(
            child: Text(
              _text.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 18 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: _isTorchEnabled ? _text.turnOffFlash : _text.turnOnFlash,
            onPressed: controller?.value.isInitialized == true
                ? _toggleTorch
                : null,
            icon: Icon(
              _isTorchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
            ),
            color: _isTorchEnabled ? Colors.amberAccent : Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final guideColor = _guideStatus == PrescriptionCameraGuideStatus.aligned
            ? MedBuddyColors.primary
            : const Color(0xFFFFC247);
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final previewSize = controller.value.previewSize;
        final isLandscape = viewportSize.width > viewportSize.height;
        final displayedImageSize = previewSize == null
            ? viewportSize
            : isLandscape
            ? Size(previewSize.width, previewSize.height)
            : Size(previewSize.height, previewSize.width);
        final guideRect = PrescriptionCameraLayoutService.guideRect(
          viewportSize,
        );
        _normalizedGuideRect =
            PrescriptionCameraLayoutService.normalizedSourceRect(
              viewportSize: viewportSize,
              displayedImageSize: displayedImageSize,
              guideRect: guideRect,
            );
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: displayedImageSize.width,
                  height: displayedImageSize.height,
                  child: CameraPreview(controller),
                ),
              ),
            ),
            CustomPaint(
              painter: _PrescriptionGuidePainter(
                guideColor: guideColor,
                guideRect: guideRect,
              ),
            ),
            if (!isLandscape)
              Positioned(
                left: 24,
                right: 24,
                bottom: 22,
                child: _GuideMessage(
                  message: _text.guideMessage(_guideStatus),
                  color: guideColor,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 52,
            ),
            const SizedBox(height: 18),
            Text(
              _cameraErrorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_text.retry),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturePanel(
    CameraController? controller, {
    bool isLandscape = false,
  }) {
    final canCapture =
        controller?.value.isInitialized == true &&
        !_isCapturing &&
        _cameraErrorMessage.isEmpty;
    final guideColor = _guideStatus == PrescriptionCameraGuideStatus.aligned
        ? MedBuddyColors.primary
        : const Color(0xFFFFC247);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLandscape) ...[
          _GuideMessage(
            message: _text.guideMessage(_guideStatus),
            color: guideColor,
          ),
          const SizedBox(height: 14),
        ],
        Text(
          _text.captureHint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: isLandscape ? 15 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _text.cropNotice,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: isLandscape ? 12 : 13,
          ),
        ),
        SizedBox(height: isLandscape ? 18 : 14),
        Semantics(
          button: true,
          label: _text.capture,
          child: SizedBox.square(
            dimension: isLandscape ? 72 : 76,
            child: IconButton.filled(
              tooltip: _text.capture,
              onPressed: canCapture ? _capturePrescription : null,
              style: IconButton.styleFrom(
                backgroundColor: MedBuddyColors.primary,
                disabledBackgroundColor: Colors.white24,
              ),
              icon: _isCapturing
                  ? const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Icon(
                      Icons.photo_camera_outlined,
                      color: Colors.white,
                      size: 36,
                    ),
            ),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 16 : 24,
        16,
        isLandscape ? 16 : 24,
        isLandscape ? 16 : 22,
      ),
      color: const Color(0xFF171717),
      child: isLandscape
          ? Center(child: SingleChildScrollView(child: content))
          : content,
    );
  }
}

class _GuideMessage extends StatelessWidget {
  final String message;
  final Color color;

  const _GuideMessage({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

// 클래스명: _PrescriptionGuidePainter
// 역할: 카메라 위에 처방전 배치 영역과 네 모서리 가이드 선을 그린다.
// 주요 책임:
// - 가이드 바깥 영역을 어둡게 표시한다.
// - 거리 판정 상태 색상으로 네 모서리 선을 표시한다.
class _PrescriptionGuidePainter extends CustomPainter {
  final Color guideColor;
  final Rect guideRect;

  const _PrescriptionGuidePainter({
    required this.guideColor,
    required this.guideRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guideRRect = RRect.fromRectAndRadius(
      guideRect,
      const Radius.circular(18),
    );
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(guideRRect);
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );

    final guidePaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const cornerLength = 34.0;

    canvas.drawLine(
      guideRect.topLeft,
      guideRect.topLeft + const Offset(cornerLength, 0),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.topLeft,
      guideRect.topLeft + const Offset(0, cornerLength),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.topRight,
      guideRect.topRight + const Offset(-cornerLength, 0),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.topRight,
      guideRect.topRight + const Offset(0, cornerLength),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.bottomLeft,
      guideRect.bottomLeft + const Offset(cornerLength, 0),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.bottomLeft,
      guideRect.bottomLeft + const Offset(0, -cornerLength),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.bottomRight,
      guideRect.bottomRight + const Offset(-cornerLength, 0),
      guidePaint,
    );
    canvas.drawLine(
      guideRect.bottomRight,
      guideRect.bottomRight + const Offset(0, -cornerLength),
      guidePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PrescriptionGuidePainter oldDelegate) {
    return oldDelegate.guideColor != guideColor ||
        oldDelegate.guideRect != guideRect;
  }
}

class _GuidedCameraText {
  final bool isEnglish;

  const _GuidedCameraText(this.isEnglish);

  String get title => isEnglish ? 'Prescription Camera' : '처방전 촬영';
  String get capture => isEnglish ? 'Take photo' : '촬영';
  String get captureHint => isEnglish
      ? 'Keep the entire prescription clear and inside the guide.'
      : '처방전 전체가 선명하게 보이도록 촬영해주세요';
  String get cropNotice => isEnglish
      ? 'Only the area inside the guide will be used.'
      : '가이드 안쪽 영역만 촬영 결과로 사용합니다.';
  String get cameraUnavailable =>
      isEnglish ? 'The camera is unavailable.' : '카메라를 사용할 수 없습니다.';
  String get permissionDenied => isEnglish
      ? 'Camera permission is required. Enable it in system settings.'
      : '카메라 권한이 필요합니다. 시스템 설정에서 권한을 허용해주세요.';
  String get captureFailed =>
      isEnglish ? 'Could not take the photo.' : '사진을 촬영하지 못했습니다.';
  String get flashUnavailable =>
      isEnglish ? 'Flash is unavailable.' : '플래시를 사용할 수 없습니다.';
  String get turnOnFlash => isEnglish ? 'Turn on flash' : '플래시 켜기';
  String get turnOffFlash => isEnglish ? 'Turn off flash' : '플래시 끄기';
  String get retry => isEnglish ? 'Retry' : '다시 시도';

  String guideMessage(PrescriptionCameraGuideStatus status) {
    return switch (status) {
      PrescriptionCameraGuideStatus.tooFar =>
        isEnglish
            ? 'The prescription is too far away. Move a little closer.'
            : '처방전이 너무 멀어요. 조금 더 가까이 이동해주세요.',
      PrescriptionCameraGuideStatus.tooClose =>
        isEnglish
            ? 'The prescription is too close. Move a little farther away.'
            : '처방전이 너무 가까워요. 조금 멀리 이동해주세요.',
      PrescriptionCameraGuideStatus.aligned =>
        isEnglish
            ? 'Good. Hold still and take the photo.'
            : '좋아요. 흔들리지 않게 촬영해주세요.',
      PrescriptionCameraGuideStatus.searching =>
        isEnglish
            ? 'Fit the entire prescription inside the guide.'
            : '처방전 전체를 가이드 안에 맞춰주세요.',
    };
  }
}
