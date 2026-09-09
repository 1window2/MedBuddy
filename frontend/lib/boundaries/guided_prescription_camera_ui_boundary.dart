import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/prescription_camera_guide_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/camera_lifecycle_coordinator.dart';
import '../services/prescription_camera_orientation_service.dart';
import '../services/prescription_frame_analyzer.dart';
import '../services/prescription_guide_layout.dart';
import '../services/prescription_image_crop_service.dart';
import '../theme/medbuddy_theme.dart';

// 파일명: guided_prescription_camera_ui_boundary.dart
// 역할: 처방전 촬영 거리 안내와 카메라 생명주기 관리를 제공한다.

// 클래스명: GuidedPrescriptionCameraUI
// 역할: 실시간 거리 가이드와 처방전 촬영 결과 반환을 담당한다.
// 주요 책임:
// - 후면 카메라를 초기화하고 앱 생명주기에 맞춰 자원을 해제한다.
// - 처방전 후보가 화면에서 차지하는 비율을 주기적으로 분석한다.
// - 촬영한 이미지 파일을 기존 처방전 OCR 흐름으로 돌려보낸다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class GuidedPrescriptionCameraUI extends StatefulWidget {
  final UserSetting userSetting;

  // 함수이름: GuidedPrescriptionCameraUI
  // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 GuidedPrescriptionCameraUI 인스턴스.
  const GuidedPrescriptionCameraUI({super.key, required this.userSetting});

  // 함수이름: createState
  // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _GuidedPrescriptionCameraUIState 인스턴스.
  @override
  State<GuidedPrescriptionCameraUI> createState() =>
      _GuidedPrescriptionCameraUIState();
}

// Class Name: _GuidedPrescriptionCameraUIState
// Role: Manages state for live framing guidance and prescription-photo capture results.
// Responsibilities:
// - Releases the camera when inactive, paused, or detached and reinitializes it on resume.
// - Waits for sensor orientation activation before restoring portrait orientation.
// - Schedules camera initialization on the serialized lifecycle queue.
class _GuidedPrescriptionCameraUIState extends State<GuidedPrescriptionCameraUI>
    with WidgetsBindingObserver {
  static const Duration _analysisInterval = Duration(milliseconds: 650);

  final PrescriptionFrameAnalyzer _frameAnalyzer =
      const PrescriptionFrameAnalyzer();
  final PrescriptionImageCropService _imageCropService =
      const PrescriptionImageCropService();
  final CameraLifecycleCoordinator _cameraLifecycleCoordinator =
      CameraLifecycleCoordinator();
  final PrescriptionCameraOrientationService _orientationService =
      const PrescriptionCameraOrientationService();
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

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _isEnglish =>
      widget.userSetting.language.trim().toLowerCase().startsWith('en');

  // 함수이름: _text
  // 함수역할: 현재 언어에 맞는 처방전 촬영 거리 안내와 카메라 생명주기 관리 문구 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: _GuidedCameraText: 현재 화면 언어의 문구 제공 객체.
  _GuidedCameraText get _text => _GuidedCameraText(_isEnglish);

  // Function Name: initState
  // Description: Observes app lifecycle, activates sensor orientation, and starts camera initialization.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orientationActivation = _orientationService.enableSensorOrientation();
    unawaited(_initializeCamera());
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱이 비활성·중지·분리되면 카메라를 해제하고 복귀 시 다시 초기화한다.
  // 매개변수:
  // - state (AppLifecycleState): Flutter가 전달한 앱의 전경·배경 생명주기 상태.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // 함수이름: dispose
  // 함수역할: 화면이 소유한 자원 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseCamera());
    unawaited(_restoreOrientation());
    super.dispose();
  }

  // Function Name: _restoreOrientation
  // Description: Waits for sensor orientation activation before restoring portrait orientation.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _restoreOrientation() async {
    await _orientationActivation;
    await _orientationService.restorePortrait();
  }

  // Function Name: _initializeCamera
  // Description: Schedules camera initialization on the serialized lifecycle queue.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _initializeCamera() {
    return _cameraLifecycleCoordinator.schedule(_initializeCameraNow);
  }

  // 함수이름: _initializeCameraNow
  // 함수역할: 기존 제어 객체를 교체하고 후면 카메라 미리보기를 시작한다. 권한과 생명주기 전환이 겹치지 않도록 CameraLifecycleCoordinator 안에서만 실행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _initializeCameraNow() async {
    final generation = ++_cameraGeneration;
    await _disposeCurrentController();
    if (!mounted || generation != _cameraGeneration) {
      return;
    }

    // 함수이름: _initializeCameraNow.setState callback
    // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_cameraErrorMessage = ''; _guideStatus = PrescriptionCameraGuideStatus.searching; _isTorchEnabled = false`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
        // 함수이름: _initializeCameraNow.firstWhere callback
        // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환에 대해 `description.lensDirection == CameraLensDirection.back` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - description (콜백 계약에서 추론): 후면 렌즈 여부를 검사할 사용 가능한 카메라 정보.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        (description) => description.lensDirection == CameraLensDirection.back,
        // 함수이름: _initializeCameraNow.orElse callback
        // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 캡처된 상태에서 `cameras.first` 값을 제공한다.
        // 매개변수:
        // - 없음.
        // 반환값: `cameras.first`의 값.
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
        // 함수이름: _initializeCameraNow.setState callback
        // 함수역할: 캡처된 값을 변경하지 않는다. 호출자가 화면 갱신을 요청하거나 해당 상호작용을 비활성화한다.
        // 매개변수:
        // - 없음.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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

  // Function Name: _releaseCamera
  // Description: Schedules camera resource release on the serialized lifecycle queue.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _releaseCamera() {
    return _cameraLifecycleCoordinator.schedule(_releaseCameraNow);
  }

  // Function Name: _releaseCameraNow
  // Description: Invalidates the current camera generation and disposes the controller.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _releaseCameraNow() async {
    _cameraGeneration += 1;
    await _disposeCurrentController();
  }

  // 함수이름: _disposeCurrentController
  // 함수역할: 방향 리스너와 이미지 스트림을 정리하고 이미 중지된 경우에도 컨트롤러를 해제한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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

  // 함수이름: _handleCameraOrientationChanged
  // 함수역할: 카메라 센서 방향이 바뀌면 화면을 다시 구성해 가로 전용 배치를 즉시 적용한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _handleCameraOrientationChanged() {
    final orientation = _cameraController?.value.deviceOrientation;
    if (!mounted ||
        orientation == null ||
        orientation == _lastCameraOrientation) {
      return;
    }
    // 함수이름: _handleCameraOrientationChanged.setState callback
    // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_lastCameraOrientation = orientation`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _lastCameraOrientation = orientation;
    });
  }

  // 함수이름: _analyzeCameraImage
  // 함수역할: 일정 간격으로 밝기 평면을 분석해 처방전 거리 안내 상태를 갱신한다.
  // 매개변수:
  // - image (CameraImage): 분석 또는 미리보기에 사용할 카메라 프레임·이미지 바이트.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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
        normalizedRegion: _normalizedGuideRect,
        rotationDegrees: _cameraRotationDegrees(_cameraController),
      );
      if (mounted && result.status != _guideStatus) {
        // 함수이름: _analyzeCameraImage.setState callback
        // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_guideStatus = result.status`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
        setState(() {
          _guideStatus = result.status;
        });
      }
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  // 함수이름: _capturePrescription
  // 함수역할: 현재 카메라 프레임을 저장하고 화면 가이드 안쪽만 잘라 호출 화면에 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _capturePrescription() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    // 함수이름: _capturePrescription.setState callback
    // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_isCapturing = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _cameraRotationDegrees
  // 함수역할: 센서 방향·기기 방향·전후면 렌즈를 조합해 영상 회전각을 계산한다.
  // 매개변수:
  // - controller (CameraController?): 실시간 미리보기·촬영·플래시·방향 제어에 사용할 카메라 컨트롤러.
  // 반환값: int: 카메라 센서와 기기 방향을 반영한 회전각; 컨트롤러가 없으면 0.
  int _cameraRotationDegrees(CameraController? controller) {
    if (controller == null) {
      return 0;
    }
    const deviceOrientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final deviceRotation =
        deviceOrientations[controller.value.deviceOrientation] ?? 0;
    final sensorOrientation = controller.description.sensorOrientation;
    if (controller.description.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceRotation) % 360;
    }
    return (sensorOrientation - deviceRotation + 360) % 360;
  }

  // 함수이름: _recoverFromCaptureFailure
  // 함수역할: 촬영 실패 문구를 표시하고 실시간 거리 분석을 다시 시작한다.
  // 매개변수:
  // - controller (CameraController): 실시간 미리보기·촬영·플래시·방향 제어에 사용할 카메라 컨트롤러.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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
      // 함수이름: _recoverFromCaptureFailure.setState callback
      // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_isCapturing = false`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() {
        _isCapturing = false;
      });
    }
  }

  // 함수이름: _toggleTorch
  // 함수역할: 어두운 환경에서 사용할 후면 카메라 조명을 켜거나 끈다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
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
        // 함수이름: _toggleTorch.setState callback
        // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_isTorchEnabled = shouldEnable`로 갱신한다.
        // 매개변수:
        // - 없음.
        // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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

  // 함수이름: _showCameraError
  // 함수역할: 화면이 유지되는 경우에만 카메라 오류 문구를 표시 상태에 반영한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showCameraError(String message) {
    if (!mounted) {
      return;
    }
    // 함수이름: _showCameraError.setState callback
    // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환의 입력·요청 상태를 `_cameraErrorMessage = message`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _cameraErrorMessage = message;
    });
  }

  // 함수이름: _cameraErrorText
  // 함수역할: 카메라 접근 거부 코드는 권한 안내로, 그 외에는 플랫폼 설명 또는 기본 오류로 표시한다.
  // 매개변수:
  // - error (CameraException): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 실시간 거리 가이드와 처방전 촬영 결과 반환 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 실시간 거리 가이드와 처방전 촬영 결과 반환에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: LayoutBuilder(
            // 함수이름: build.builder callback
            // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
            // 매개변수:
            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
            // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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
                  PrescriptionGuideLayout.shouldUseLandscapeLayout(
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
                      width: PrescriptionGuideLayout.landscapePanelWidth(
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

  // 함수이름: _buildHeader
  // 함수역할: 뒤로가기와 카메라 초기화 여부에 따른 플래시 제어를 배치한다.
  // 매개변수:
  // - controller (CameraController?): 실시간 미리보기·촬영·플래시·방향 제어에 사용할 카메라 컨트롤러.
  // - isCompact (bool): 공간을 줄인 카드·상단 배치를 사용할지 여부.
  // 반환값: 실시간 거리 가이드와 처방전 촬영 결과 반환에 쓰는 위젯 트리.
  Widget _buildHeader(CameraController? controller, {bool isCompact = false}) {
    return SizedBox(
      height: isCompact ? 54 : 68,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            // 함수이름: _buildHeader.onPressed callback
            // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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

  // 함수이름: _buildPreview
  // 함수역할: 카메라 비율과 회전 방향에 맞춘 미리보기 위에 촬영 가이드·거리 상태를 겹친다.
  // 매개변수:
  // - controller (CameraController?): 실시간 미리보기·촬영·플래시·방향 제어에 사용할 카메라 컨트롤러.
  // 반환값: 실시간 거리 가이드와 처방전 촬영 결과 반환에 쓰는 위젯 트리.
  Widget _buildPreview(CameraController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    return LayoutBuilder(
      // 함수이름: _buildPreview.builder callback
      // 함수역할: 실시간 거리 가이드와 처방전 촬영 결과 반환에 Color을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - constraints (BoxConstraints): 부모 레이아웃이 허용한 너비·높이 범위.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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
        final guideRect = PrescriptionGuideLayout.guideRect(viewportSize);
        _normalizedGuideRect = PrescriptionGuideLayout.normalizedSourceRect(
          viewportSize: viewportSize,
          displayedImageSize: displayedImageSize,
          guideRect: guideRect,
        );
        final guideMessageTop = (guideRect.bottom + 14)
            .clamp(12.0, constraints.maxHeight - 78)
            .toDouble();
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
                top: guideMessageTop,
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

  // 함수이름: _buildCameraError
  // 함수역할: 카메라 오류 문구와 초기화 재시도 버튼을 표시한다.
  // 매개변수:
  // - 없음.
  // 반환값: 실시간 거리 가이드와 처방전 촬영 결과 반환에 쓰는 위젯 트리.
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

  // 함수이름: _buildCapturePanel
  // 함수역할: 가로·세로 배치에 맞춰 촬영 안내와 초기화·촬영 중 상태를 반영한 셔터를 구성한다.
  // 매개변수:
  // - controller (CameraController?): 실시간 미리보기·촬영·플래시·방향 제어에 사용할 카메라 컨트롤러.
  // - isLandscape (bool): 가로 방향용 배치를 사용할지 여부.
  // 반환값: 실시간 거리 가이드와 처방전 촬영 결과 반환에 쓰는 위젯 트리.
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

// 클래스명: _GuideMessage
// 역할: 처방전 배치·촬영 거리 상태 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방전 배치·촬영 거리 상태 안내 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
class _GuideMessage extends StatelessWidget {
  final String message;
  final Color color;

  // 함수이름: _GuideMessage
  // 함수역할: 처방전 배치·촬영 거리 상태 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - color (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // 반환값: 입력 설정이 반영된 _GuideMessage 인스턴스.
  const _GuideMessage({required this.message, required this.color});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방전 배치·촬영 거리 상태 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방전 배치·촬영 거리 상태 안내에 쓰는 위젯 트리.
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
// 역할: 가이드 바깥 음영과 거리 상태별 모서리 선을 담당한다.
// 주요 책임:
// - 가이드 바깥 영역을 어둡게 표시한다.
// - 거리 판정 상태 색상으로 네 모서리 선을 표시한다.
// 속성:
// - guideColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
// - guideRect (Rect): 화면 좌표에서 처방전을 배치할 가이드 사각형.
class _PrescriptionGuidePainter extends CustomPainter {
  final Color guideColor;
  final Rect guideRect;

  // 함수이름: _PrescriptionGuidePainter
  // 함수역할: 가이드 바깥 음영과 거리 상태별 모서리 선 관련 값을 _PrescriptionGuidePainter 인스턴스에 담는다.
  // 매개변수:
  // - guideColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - guideRect (Rect): 화면 좌표에서 처방전을 배치할 가이드 사각형.
  // 반환값: 입력 설정이 반영된 _PrescriptionGuidePainter 인스턴스.
  const _PrescriptionGuidePainter({
    required this.guideColor,
    required this.guideRect,
  });

  // 함수이름: paint
  // 함수역할: 가이드 바깥 영역을 어둡게 칠하고 가이드 색상으로 네 모서리 선을 그린다.
  // 매개변수:
  // - canvas (Canvas): 오버레이 도형을 그릴 캔버스.
  // - size (Size): 위젯 또는 캔버스의 표시 크기.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
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

  // 함수이름: shouldRepaint
  // 함수역할: 가이드 색상 또는 사각형이 바뀌었을 때만 다시 그리도록 판단한다.
  // 매개변수:
  // - oldDelegate (_PrescriptionGuidePainter): 다시 그릴 필요가 있는지 비교할 이전 페인터.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  @override
  bool shouldRepaint(covariant _PrescriptionGuidePainter oldDelegate) {
    return oldDelegate.guideColor != guideColor ||
        oldDelegate.guideRect != guideRect;
  }
}

// 클래스명: _GuidedCameraText
// 역할: 처방전 촬영 거리 안내와 카메라 생명주기 관리에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 처방전 촬영 거리 안내와 카메라 생명주기 관리에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
class _GuidedCameraText {
  final bool isEnglish;

  // 함수이름: _GuidedCameraText
  // 함수역할: 처방전 촬영 거리 안내와 카메라 생명주기 관리에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
  // 반환값: 입력 설정이 반영된 _GuidedCameraText 인스턴스.
  const _GuidedCameraText(this.isEnglish);

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 촬영" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Prescription Camera' : '처방전 촬영';
  // 함수이름: capture
  // 함수역할: 현재 언어와 입력값에 맞춰 "Take photo" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get capture => isEnglish ? 'Take photo' : '촬영';
  // 함수이름: captureHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름과 복용 정보 표를 초록색 가이드 안에 맞춰주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get captureHint => isEnglish
      ? 'Fit the medication table inside the green guide.'
      : '약 이름과 복용 정보 표를 초록색 가이드 안에 맞춰주세요';
  // 함수이름: cropNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "가이드 안쪽 영역만 촬영 결과로 사용합니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cropNotice => isEnglish
      ? 'Only the area inside the guide will be used.'
      : '가이드 안쪽 영역만 촬영 결과로 사용합니다.';
  // 함수이름: cameraUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "카메라를 사용할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cameraUnavailable =>
      isEnglish ? 'The camera is unavailable.' : '카메라를 사용할 수 없습니다.';
  // 함수이름: permissionDenied
  // 함수역할: 현재 언어와 입력값에 맞춰 "카메라 권한이 필요합니다. 시스템 설정에서 권한을 허용해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get permissionDenied => isEnglish
      ? 'Camera permission is required. Enable it in system settings.'
      : '카메라 권한이 필요합니다. 시스템 설정에서 권한을 허용해주세요.';
  // 함수이름: captureFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "사진을 촬영하지 못했습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get captureFailed =>
      isEnglish ? 'Could not take the photo.' : '사진을 촬영하지 못했습니다.';
  // 함수이름: flashUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "플래시를 사용할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get flashUnavailable =>
      isEnglish ? 'Flash is unavailable.' : '플래시를 사용할 수 없습니다.';
  // 함수이름: turnOnFlash
  // 함수역할: 현재 언어와 입력값에 맞춰 "플래시 켜기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get turnOnFlash => isEnglish ? 'Turn on flash' : '플래시 켜기';
  // 함수이름: turnOffFlash
  // 함수역할: 현재 언어와 입력값에 맞춰 "플래시 끄기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get turnOffFlash => isEnglish ? 'Turn off flash' : '플래시 끄기';
  // 함수이름: retry
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 시도" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retry => isEnglish ? 'Retry' : '다시 시도';

  // 함수이름: guideMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전이 너무 멀어요. 조금 더 가까이 이동해주세요." 문구를 제공한다.
  // 매개변수:
  // - status (PrescriptionCameraGuideStatus): 현재 연결·분석·비교 진행 상태.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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
            ? 'Fit the medication table inside the guide.'
            : '약 이름과 복용 정보 표를 가이드 안에 맞춰주세요.',
    };
  }
}
