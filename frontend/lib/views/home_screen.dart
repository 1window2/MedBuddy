// 파일명: home_screen.dart
// 역할: 처방 분석 흐름과 홈·일정·복약함·조건부 채팅·내 정보의 탐색을 구성한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../boundaries/check_result_ui_boundary.dart';
import '../boundaries/chat_list_ui_boundary.dart';
import '../boundaries/check_nearby_pharmacy_ui_boundary.dart';
import '../boundaries/check_schedule_ui_boundary.dart';
import '../boundaries/check_saved_medication_ui_boundary.dart';
import '../boundaries/health_recommendation_ui_boundary.dart';
import '../boundaries/guided_prescription_camera_ui_boundary.dart';
import '../boundaries/input_prescription_ui_boundary.dart';
import '../boundaries/link_patient_caregiver_ui_boundary.dart';
import '../boundaries/manual_medication_entry_ui_boundary.dart';
import '../boundaries/manage_user_hub_ui_boundary.dart';
import '../boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import '../boundaries/medication_reminder_settings_ui_boundary.dart';
import '../boundaries/pill_identification_ui_boundary.dart';
import '../boundaries/manage_user_setting_ui_boundary.dart';
import '../boundaries/prescription_analysis_preview_ui_boundary.dart';
import '../boundaries/prescription_analysis_progress_ui_boundary.dart';
import '../boundaries/prescription_analysis_status_ui_boundary.dart';
import '../controls/app_language_control.dart';
import '../controls/authentication_control.dart';
import '../controls/manage_chat_list_control.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/notification_service.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/medbuddy_feature_updates.dart';

// 파일명: home_screen.dart
// 역할: ViewModel의 처방전 분석 상태에 따라 실제 표시할 화면을 선택한다.

// Class Name: HomeScreen
// Role: Represents the active screen selected by prescription flow and navigation destination.
// Responsibilities:
// - Renders one screen for the current PrescriptionFlowState.
// - Connects Home navigation to saved medications, today's schedule, and settings.
class HomeScreen extends StatefulWidget {
  final ManageChatList Function(String userHash)? chatListFactory;
  // 함수이름: HomeScreen
  // 함수역할: 처방 흐름과 하단 탐색을 관리하는 홈 화면을 생성한다.
  // 매개변수: key: 위젯 식별자, chatListFactory: 계정별 채팅 목록 Control의 선택적 생성 경계.
  // 반환값: 홈 화면.
  const HomeScreen({super.key, this.chatListFactory});

  // Function Name: createState
  // Description: Creates the state object that coordinates the active screen selected by prescription flow and navigation destination.
  // Parameters:
  // - None.
  // Returns: A new _HomeScreenState instance.
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Class Name: _HomeScreenState
// Role: Manages state for the active screen selected by prescription flow and navigation destination.
// Responsibilities:
// - Selects the screen for the prescription-flow stage and connects back handling that blocks exit during saving.
// - Builds the selected destination, persistent bottom navigation, and back behavior while preserving visited-screen state.
// - Defers unvisited screens and preserves visited-screen identity with a destination key.
// Attributes:
// - _selectedDestination (MedBuddyDestination): Top-level navigation destination to display or select.
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  MedBuddyDestination _selectedDestination = MedBuddyDestination.home;
  ManageChatList? _chatList;
  Timer? _chatRefreshTimer;
  bool _isForeground = true;
  String? _updatingHomeMedicationSlotKey;
  final Set<MedBuddyDestination> _visitedDestinations = {
    MedBuddyDestination.home,
  };

  // 함수이름: initState
  // 함수역할: 앱 활성 상태를 관찰해 백그라운드에서는 대화 목록 조회를 멈춘다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  // 함수이름: _syncChatControl
  // 함수역할: 계정 변경에 맞춰 목록 Control을 교체하고 이전 계정 상태를 비운다.
  // 매개변수: viewModel: 현재 계정과 설정. 반환값: 없음. 첫 조회는 빌드 완료 뒤 실행한다.
  void _syncChatControl(MedBuddyViewModel viewModel) {
    final userHash = viewModel.patientHash;
    if (_chatList?.userHash == userHash) return;
    _chatRefreshTimer?.cancel();
    _chatList?.removeListener(_onChatListChanged);
    _chatList?.dispose();
    _chatList = null;
    _visitedDestinations.remove(MedBuddyDestination.chat);
    if (_selectedDestination == MedBuddyDestination.chat) {
      _selectedDestination = MedBuddyDestination.home;
    }
    final control =
        widget.chatListFactory?.call(userHash) ??
        ManageChatList(userHash: userHash);
    _chatList = control;
    control.addListener(_onChatListChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      // 함수이름: 첫 연동 조회 콜백
      // 함수역할: 새 Control이 여전히 유효하면 현재 연동 조회와 주기 갱신을 시작한다.
      // 매개변수: time: 프레임 시각. 반환값: 없음.
      (time) {
        if (mounted && identical(_chatList, control)) _startChatRefresh();
      },
    );
  }

  // 함수이름: _onChatListChanged
  // 함수역할: 연동 유무에 따라 탭을 갱신하며 마지막 연동이 사라지면 홈으로 돌아간다.
  // 매개변수: 없음. 반환값: 없음.
  void _onChatListChanged() {
    if (!mounted) return;
    setState(
      // 함수이름: 연동 상태 갱신 콜백
      // 함수역할: 연동 없는 채팅 탭의 방문·선택 상태를 해제한다.
      // 매개변수: 없음. 반환값: 없음.
      () {
        if (_chatList?.links.isEmpty ?? true) {
          _visitedDestinations.remove(MedBuddyDestination.chat);
          if (_selectedDestination == MedBuddyDestination.chat) {
            _selectedDestination = MedBuddyDestination.home;
          }
        }
      },
    );
  }

  // 함수이름: _refreshChatList
  // 함수역할: 활성 앱의 연동을 갱신하고 대화 목록을 보고 있을 때만 미리보기를 읽는다.
  // 매개변수: 없음. 반환값: 없음.
  void _refreshChatList() {
    if (!_isForeground) return;
    unawaited(
      _chatList?.refresh(
        includeMessages:
            _selectedDestination == MedBuddyDestination.chat &&
            (ModalRoute.of(context)?.isCurrent ?? false),
      ),
    );
  }

  // 함수이름: _startChatRefresh
  // 함수역할: 즉시 연동을 조회하고 상대 기기의 연동 변경도 15초 간격으로 반영한다.
  // 매개변수: 없음. 반환값: 없음.
  void _startChatRefresh() {
    _chatRefreshTimer?.cancel();
    if (!_isForeground || _chatList == null) return;
    _refreshChatList();
    _chatRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      // 함수이름: 연동 조회 타이머 콜백
      // 함수역할: 활성 앱의 연동 상태를 갱신한다.
      // 매개변수: timer: 주기 타이머. 반환값: 없음.
      (timer) => _refreshChatList(),
    );
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱 복귀 시 즉시 조회하고 비활성 상태에서는 타이머를 중지한다.
  // 매개변수: state: 앱 실행 상태. 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      _startChatRefresh();
    } else {
      _chatRefreshTimer?.cancel();
    }
  }

  // 함수이름: dispose
  // 함수역할: 화면이 사라지면 감시와 소유한 계정별 목록 Control을 정리한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatRefreshTimer?.cancel();
    _chatList?.removeListener(_onChatListChanged);
    _chatList?.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 분석 단계와 앱 탐색 목적지별 활성 화면 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.prescription),
        viewModel.updatesFor(MedBuddyFeature.schedule),
        viewModel.updatesFor(MedBuddyFeature.reminder),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      // 함수이름: build.builder callback
      // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context, _) => _buildActiveScreen(context, viewModel),
    );
  }

  // 함수이름: _buildActiveScreen
  // 함수역할: 계정별 채팅 목록을 동기화하고 처방 흐름별 화면과 저장 중 뒤로가기 제한을 선택한다.
  // 매개변수: context, viewModel: 화면 문맥과 현재 사용자 상태.
  // 반환값: 활성 처방 또는 탐색 화면.
  Widget _buildActiveScreen(BuildContext context, MedBuddyViewModel viewModel) {
    _syncChatControl(viewModel);
    final flowState = viewModel.prescriptionFlowState;
    final isPrescriptionExitBlocked =
        viewModel.isMedicationSaving || viewModel.isAllMedicationSaving;

    final activeScreen = switch (flowState) {
      PrescriptionFlowState.recognizingPrescription =>
        PrescriptionAnalysisProgressUI(
          activeStep: viewModel.analysisProgressStep,
          userSetting: viewModel.userSetting,
          onBackRequested: viewModel.clearAnalysisResult,
        ),
      PrescriptionFlowState.previewReady => PrescriptionAnalysisPreviewUI(
        medicationScheduleList: viewModel.recognizedMedicationScheduleList,
        recognizedTextRegions: viewModel.recognizedTextRegionList,
        previewImagePath: viewModel.prescriptionPreviewImagePath,
        recognitionNotice: viewModel.prescriptionRecognitionNotice,
        userSetting: viewModel.userSetting,
        onBackRequested: viewModel.clearAnalysisResult,
        onAnalysisRequested: viewModel.requestPrescriptionAnalysis,
        onMedicationScheduleChanged:
            viewModel.updateRecognizedMedicationSchedule,
        onMedicationScheduleAdded: viewModel.addRecognizedMedicationSchedule,
      ),
      PrescriptionFlowState.medicationReviewRequired =>
        PrescriptionAnalysisPreviewUI(
          medicationScheduleList: viewModel.recognizedMedicationScheduleList,
          recognizedTextRegions: viewModel.recognizedTextRegionList,
          previewImagePath: viewModel.prescriptionPreviewImagePath,
          userSetting: viewModel.userSetting,
          onBackRequested: viewModel.returnToPrescriptionPreview,
          onAnalysisRequested: viewModel.requestPrescriptionAnalysis,
          onMedicationScheduleChanged:
              viewModel.updateRecognizedMedicationSchedule,
          onMedicationScheduleAdded: viewModel.addRecognizedMedicationSchedule,
          verifiedScheduleIndexes: viewModel.verifiedMedicationScheduleIndexes,
          isMedicationLookupReview: true,
          onVerifiedOnlyContinueRequested:
              viewModel.continueWithVerifiedMedicationAnalysis,
        ),
      PrescriptionFlowState.analyzingMedication =>
        PrescriptionAnalysisProgressUI(
          activeStep: viewModel.analysisProgressStep,
          userSetting: viewModel.userSetting,
          onBackRequested: viewModel.clearAnalysisResult,
        ),
      PrescriptionFlowState.analysisSucceeded => PrescriptionAnalysisSuccessUI(
        analyzedMedicationList: viewModel.analyzedMedicationList,
        userSetting: viewModel.userSetting,
        onResultRequested: viewModel.showMedicationAnalysisResult,
      ),
      PrescriptionFlowState.analysisFailed => PrescriptionAnalysisFailureUI(
        message: viewModel.analysisErrorMessage,
        userSetting: viewModel.userSetting,
        failureStep: viewModel.analysisProgressStep,
        onAnalysisRetryRequested: viewModel.canRetryPrescriptionAnalysis
            ? viewModel.requestPrescriptionAnalysis
            : null,
        onOcrReviewRequested: viewModel.canRetryPrescriptionAnalysis
            ? viewModel.returnToPrescriptionPreview
            : null,
        // 함수이름: _buildActiveScreen.onCameraRetryRequested callback
        // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `_requestGuidedPrescriptionImage(context, viewModel)`을 실행한다.
        // 매개변수:
        // - 없음.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onCameraRetryRequested: () =>
            _requestGuidedPrescriptionImage(context, viewModel),
        onGalleryRetryRequested: viewModel.requestPrescriptionImageFromGallery,
        onHomeRequested: viewModel.clearAnalysisResult,
      ),
      PrescriptionFlowState.resultReady => CheckResultUI(
        analyzedMedicationList: viewModel.analyzedMedicationList,
        prescriptionChangeRadar: viewModel.prescriptionChangeRadar,
        isPrescriptionChangeLoading: viewModel.isPrescriptionChangeLoading,
        userSetting: viewModel.userSetting,
        // Function Name: _buildActiveScreen.statusMessageProvider callback
        // Description: Supplies `viewModel.statusMessage` from the captured state of the active screen selected by prescription flow and navigation destination.
        // Parameters:
        // - None.
        // Returns: The value of `viewModel.statusMessage`.
        statusMessageProvider: () => viewModel.statusMessage,
        savingMedicationIndex: viewModel.savingMedicationIndex,
        completedMedicationSaveIndexes:
            viewModel.completedMedicationSaveIndexes,
        isAllMedicationSaving: viewModel.isAllMedicationSaving,
        onCloseRequested: isPrescriptionExitBlocked
            ? null
            : viewModel.clearAnalysisResult,
        onAllMedicationSaveRequested:
            viewModel.requestAllAnalyzedMedicationSave,
        onMedicationSaveRequested: viewModel.requestMedicationSave,
        // Function Name: _buildActiveScreen.onTodayScheduleRequested callback
        // Description: Refreshes revisited Schedule or Pillbox destinations and records a newly selected destination as visited.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onTodayScheduleRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.schedule);
        },
        // Function Name: _buildActiveScreen.onSavedMedicationRequested callback
        // Description: Refreshes revisited Schedule or Pillbox destinations and records a newly selected destination as visited.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onSavedMedicationRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.medicationCabinet);
        },
        // Function Name: _buildActiveScreen.onHomeRequested callback
        // Description: Refreshes revisited Schedule or Pillbox destinations and records a newly selected destination as visited.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onHomeRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.home);
        },
      ),
      PrescriptionFlowState.idle => _buildApplicationShell(context, viewModel),
    };

    return PopScope<void>(
      canPop: flowState == PrescriptionFlowState.idle,
      // Function Name: _buildActiveScreen.onPopInvokedWithResult callback
      // Description: Connects the active screen selected by prescription flow and navigation destination to the captured operation `viewModel.clearAnalysisResult()`.
      // Parameters:
      // - didPop (bool): Whether the navigation framework already popped the route.
      // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            flowState != PrescriptionFlowState.idle &&
            !isPrescriptionExitBlocked) {
          viewModel.clearAnalysisResult();
        }
      },
      child: activeScreen,
    );
  }

  // 함수이름: _buildApplicationShell
  // 함수역할: 방문한 화면 상태를 유지하고 활성 연동이 있을 때만 채팅 목적지와 탭을 추가한다.
  // 매개변수: context, viewModel: 화면 문맥과 현재 사용자 상태.
  // 반환값: 활성 목적지와 하단 탐색 막대.
  Widget _buildApplicationShell(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) {
    final showChat = _chatList?.links.isNotEmpty ?? false;
    final destinations = [
      MedBuddyDestination.home,
      MedBuddyDestination.schedule,
      MedBuddyDestination.medicationCabinet,
      if (showChat) MedBuddyDestination.chat,
      MedBuddyDestination.profile,
    ];
    final selectedIndex = destinations.indexOf(_selectedDestination);

    return PopScope<void>(
      canPop: _selectedDestination == MedBuddyDestination.home,
      // Function Name: _buildApplicationShell.onPopInvokedWithResult callback
      // Description: Refreshes revisited Schedule or Pillbox destinations and records a newly selected destination as visited.
      // Parameters:
      // - didPop (bool): Whether the navigation framework already popped the route.
      // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedDestination != MedBuddyDestination.home) {
          _selectDestination(MedBuddyDestination.home);
        }
      },
      child: Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        body: IndexedStack(
          index: selectedIndex,
          children: [
            _buildDestination(
              MedBuddyDestination.home,
              // Function Name: _buildApplicationShell._buildDestination callback
              // Description: Connects today's progress and view-model capture, manual entry, identification, navigation, and slot-completion actions to Home.
              // Parameters:
              // - None.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              () => _buildHomeInput(context, viewModel),
            ),
            _buildDestination(
              MedBuddyDestination.schedule,
              // Function Name: _buildApplicationShell._buildDestination callback
              // Description: Supplies `const CheckScheduleUI(showBackButton: false)` from the captured state of the active screen selected by prescription flow and navigation destination.
              // Parameters:
              // - None.
              // Returns: The value of `const CheckScheduleUI(showBackButton: false)`.
              () => const CheckScheduleUI(showBackButton: false),
            ),
            _buildDestination(
              MedBuddyDestination.medicationCabinet,
              // Function Name: _buildApplicationShell._buildDestination callback
              // Description: Supplies `const CheckSavedMedicationUI(showCloseButton: false)` from the captured state of the active screen selected by prescription flow and navigation destination.
              // Parameters:
              // - None.
              // Returns: The value of `const CheckSavedMedicationUI(showCloseButton: false)`.
              () => const CheckSavedMedicationUI(showCloseButton: false),
            ),
            if (showChat)
              _buildDestination(
                MedBuddyDestination.chat,
                // 함수이름: 채팅 목록 builder
                // 함수역할: 현재 사용자에 속한 대화 목록과 연동 관리 진입점을 표시한다.
                // 매개변수: 없음. 반환값: 대화 목록 UI.
                () => ChatListUI(
                  control: _chatList!,
                  userSetting: viewModel.userSetting,
                  // 함수이름: 연동 관리 요청 콜백
                  // 함수역할: 현재 사용자의 연동 관리 화면을 연다.
                  // 매개변수: 없음. 반환값: 연동 관리 화면 종료.
                  onManageLinks: () =>
                      _openPatientCaregiverLink(context, viewModel),
                ),
              ),
            _buildDestination(
              MedBuddyDestination.profile,
              // Function Name: _buildApplicationShell._buildDestination callback
              // 함수역할: 현재 사용자 정보로 환자·보호자 연동 관리 화면을 연다.
              // Parameters:
              // - None.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              () => ManageUserHubUI(
                userSetting: viewModel.userSetting,
                authenticationControl: context.read<AuthenticationControl>(),
                // Function Name: _buildApplicationShell.onPatientCaregiverLinkRequested callback
                // 함수역할: 현재 사용자 정보로 환자·보호자 연동 관리 화면을 연다.
                // Parameters:
                // - None.
                // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                onPatientCaregiverLinkRequested: () =>
                    _openPatientCaregiverLink(context, viewModel),
                // Function Name: _buildApplicationShell.onUserSettingRequested callback
                // Description: Opens settings wired to authentication, setting/language persistence, and ordered account deletion.
                // Parameters:
                // - None.
                // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                onUserSettingRequested: () =>
                    _openUserSettings(context, viewModel),
              ),
            ),
          ],
        ),
        bottomNavigationBar: MedBuddyBottomNavigationUI(
          selectedDestination: _selectedDestination,
          showChat: showChat,
          language: viewModel.userSetting.language,
          onDestinationSelected: _selectDestination,
        ),
      ),
    );
  }

  // Function Name: _buildDestination
  // Description: Defers unvisited screens and preserves visited-screen identity with a destination key.
  // Parameters:
  // - destination (MedBuddyDestination): Top-level navigation destination to display or select.
  // - builder (Widget Function()): Function creating the selected screen or content on demand.
  // Returns: Widget tree for the active screen selected by prescription flow and navigation destination.
  Widget _buildDestination(
    MedBuddyDestination destination,
    Widget Function() builder,
  ) {
    if (!_visitedDestinations.contains(destination)) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(key: ValueKey(destination), child: builder());
  }

  // 함수이름: _selectDestination
  // 함수역할: 연동 없는 채팅 진입을 막고 일정·복약함·채팅을 갱신한 뒤 목적지를 선택한다.
  // 매개변수: destination: 선택할 목적지. 반환값: 없음.
  void _selectDestination(MedBuddyDestination destination) {
    if (destination == MedBuddyDestination.chat &&
        (_chatList?.links.isEmpty ?? true)) {
      return;
    }
    if (destination == MedBuddyDestination.chat) {
      unawaited(_chatList?.refresh(includeMessages: true));
    }
    if (_visitedDestinations.contains(destination)) {
      final viewModel = context.read<MedBuddyViewModel>();
      switch (destination) {
        case MedBuddyDestination.schedule:
          unawaited(viewModel.refreshMedicationSchedule());
        case MedBuddyDestination.medicationCabinet:
          unawaited(viewModel.fetchSavedMedicationInfo());
        case MedBuddyDestination.home:
        case MedBuddyDestination.chat:
        case MedBuddyDestination.profile:
          break;
      }
    }
    if (_selectedDestination == destination) {
      return;
    }
    // Function Name: _selectDestination.setState callback
    // Description: Updates the local input or request state for the active screen selected by prescription flow and navigation destination: `_selectedDestination = destination`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _selectedDestination = destination;
      _visitedDestinations.add(destination);
    });
  }

  // Function Name: _buildHomeInput
  // Description: Connects today's progress and view-model capture, manual entry, identification, navigation, and slot-completion actions to Home.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: Widget tree for the active screen selected by prescription flow and navigation destination.
  Widget _buildHomeInput(BuildContext context, MedBuddyViewModel viewModel) {
    final todayMedicationProgress = viewModel.todayMedicationProgress;

    return InputPrescriptionUI(
      statusMessage: viewModel.statusMessage,
      userSetting: viewModel.userSetting,
      todayMedicationScheduleList: viewModel.todayMedicationScheduleList,
      medicationReminderSettings: viewModel.medicationReminderSettings,
      todayMedicationCompletedCount: todayMedicationProgress.completedCount,
      todayMedicationTotalCount: todayMedicationProgress.totalCount,
      isTodayScheduleLoading: viewModel.isTodayScheduleLoading,
      // 함수이름: _buildHomeInput.onPrescriptionScanRequested callback
      // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `_requestGuidedPrescriptionImage(context, viewModel)`을 실행한다.
      // 매개변수:
      // - 없음.
      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
      onPrescriptionScanRequested: () =>
          _requestGuidedPrescriptionImage(context, viewModel),
      onPrescriptionGalleryRequested:
          viewModel.requestPrescriptionImageFromGallery,
      // 함수이름: _buildHomeInput.onPillIdentificationRequested callback
      // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `Navigator.push(context, MaterialPageRoute(builder: (context) => PillIdentificationUI(userSetting: viewModel.userSetting, onSaveRequested: view...; MaterialPageRoute(builder: (context) => PillIdentificationUI(userSetting: viewModel.userSetting, onSaveRequested: viewModel.saveIdentifiedPill...`을 실행한다.
      // 매개변수:
      // - 없음.
      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
      onPillIdentificationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            // 함수이름: _buildHomeInput.builder callback
            // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
            // 매개변수:
            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
            builder: (context) => PillIdentificationUI(
              userSetting: viewModel.userSetting,
              onSaveRequested: viewModel.saveIdentifiedPill,
              onBatchSaveRequested: viewModel.saveIdentifiedPills,
            ),
          ),
        );
      },
      // 함수이름: _buildHomeInput.onManualMedicationRequested callback
      // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `Navigator.push(context, MaterialPageRoute(builder: (context) => ManualMedicationEntryUI(userSetting: viewModel.userSetting, onSaveRequested: v...; MaterialPageRoute(builder: (context) => ManualMedicationEntryUI(userSetting: viewModel.userSetting, onSaveRequested: viewModel.saveManualMedic...`을 실행한다.
      // 매개변수:
      // - 없음.
      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
      onManualMedicationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            // 함수이름: _buildHomeInput.builder callback
            // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
            // 매개변수:
            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
            builder: (context) => ManualMedicationEntryUI(
              userSetting: viewModel.userSetting,
              onSaveRequested: viewModel.saveManualMedication,
            ),
          ),
        );
      },
      // Function Name: _buildHomeInput.onTodayScheduleRequested callback
      // Description: Refreshes revisited Schedule or Pillbox destinations and records a newly selected destination as visited.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onTodayScheduleRequested: () {
        _selectDestination(MedBuddyDestination.schedule);
      },
      // Function Name: _buildHomeInput.onNextMedicationCompleteRequested callback
      // Description: Prevents overlapping home slot updates, marks the slot complete, and offers Undo after success.
      // Parameters:
      // - slotKey (inferred by callback contract): Key identifying morning, lunch, evening, or bedtime.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onNextMedicationCompleteRequested: (slotKey) =>
          _completeHomeMedicationSlot(viewModel, slotKey),
      isNextMedicationCompletionLoading: _updatingHomeMedicationSlotKey != null,
      // Function Name: _buildHomeInput.onHealthRecommendationRequested callback
      // Description: Connects the active screen selected by prescription flow and navigation destination to the captured operation `Navigator.push(context, MaterialPageRoute(builder: (context) => const HealthRecommendationUI())); MaterialPageRoute(builder: (context) => const HealthRecommendationUI())`.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onHealthRecommendationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            // Function Name: _buildHomeInput.builder callback
            // Description: Builds health-recommendation loading, errors, and completed results for this builder callback.
            // Parameters:
            // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
            // Returns: Widget subtree for the described layout or fallback.
            builder: (context) => const HealthRecommendationUI(),
          ),
        );
      },
      // Function Name: _buildHomeInput.onMedicationReminderRequested callback
      // Description: Connects the active screen selected by prescription flow and navigation destination to the captured operation `Navigator.push(context, MaterialPageRoute(builder: (context) => const MedicationReminderSettingsUI())); MaterialPageRoute(builder: (context) => const MedicationReminderSettingsUI())`.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onMedicationReminderRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            // Function Name: _buildHomeInput.builder callback
            // Description: Builds current per-slot reminder state, configuration, and disabling for this builder callback.
            // Parameters:
            // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
            // Returns: Widget subtree for the described layout or fallback.
            builder: (context) => const MedicationReminderSettingsUI(),
          ),
        );
      },
      onNearbyPharmacyRequested:
          // 함수이름: _buildHomeInput.onNearbyPharmacyRequested callback
          // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `Navigator.push(context, MaterialPageRoute(builder: (context) => CheckNearbyPharmacyUI(userSetting: viewModel.userSetting))); MaterialPageRoute(builder: (context) => CheckNearbyPharmacyUI(userSetting: viewModel.userSetting))`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                // 함수이름: _buildHomeInput.builder callback
                // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
                // 매개변수:
                // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                builder: (context) =>
                    CheckNearbyPharmacyUI(userSetting: viewModel.userSetting),
              ),
            );
          },
      // Function Name: _buildHomeInput.onUserSettingRequested callback
      // Description: Opens settings wired to authentication, setting/language persistence, and ordered account deletion.
      // Parameters:
      // - None.
      // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
      onUserSettingRequested: () => _openUserSettings(context, viewModel),
    );
  }

  // Function Name: _completeHomeMedicationSlot
  // Description: Prevents overlapping home slot updates, marks the slot complete, and offers Undo after success.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // - slotKey (String): Key identifying morning, lunch, evening, or bedtime.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _completeHomeMedicationSlot(
    MedBuddyViewModel viewModel,
    String slotKey,
  ) async {
    if (_updatingHomeMedicationSlotKey != null) {
      return;
    }
    // Function Name: _completeHomeMedicationSlot.setState callback
    // Description: Updates the local input or request state for the active screen selected by prescription flow and navigation destination: `_updatingHomeMedicationSlotKey = slotKey`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() => _updatingHomeMedicationSlotKey = slotKey);
    final success = await viewModel.requestMedicationSlotStatusUpdate(
      slotKey,
      true,
    );
    if (!mounted) {
      return;
    }
    // Function Name: _completeHomeMedicationSlot.setState callback
    // Description: Updates the local input or request state for the active screen selected by prescription flow and navigation destination: `_updatingHomeMedicationSlotKey = null`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() => _updatingHomeMedicationSlotKey = null);
    final isEnglish = viewModel.userSetting.language
        .trim()
        .toLowerCase()
        .startsWith('en');
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (isEnglish
                    ? 'The scheduled medications were marked as taken.'
                    : '예정된 약을 모두 복용 완료로 기록했습니다.')
              : (isEnglish
                    ? 'Could not save medication completion.'
                    : '복약 완료를 저장하지 못했습니다.'),
        ),
        duration: Duration(seconds: success ? 5 : 2),
        persist: false,
        action: success
            ? SnackBarAction(
                label: isEnglish ? 'Undo' : '실행 취소',
                // Function Name: _completeHomeMedicationSlot.onPressed callback
                // Description: Connects the active screen selected by prescription flow and navigation destination to the captured operation `viewModel.requestMedicationSlotStatusUpdate(slotKey, false)`.
                // Parameters:
                // - None.
                // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
                onPressed: () async {
                  await viewModel.requestMedicationSlotStatusUpdate(
                    slotKey,
                    false,
                  );
                },
              )
            : null,
      ),
    );
  }

  // 함수이름: _openPatientCaregiverLink
  // 함수역할: 연동 관리 화면을 열고 변경 성공 및 화면 복귀 시 채팅 탭과 대화 목록을 갱신한다.
  // 매개변수: context, viewModel: 화면 문맥과 현재 사용자 상태.
  // 반환값: 연동 관리 화면 종료.
  Future<void> _openPatientCaregiverLink(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        // Function Name: _openPatientCaregiverLink.builder callback
        // Description: Composes the active screen selected by prescription flow and navigation destination with the current parent constraints for the active layout.
        // Parameters:
        // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
        // Returns: Widget subtree for the described layout or fallback.
        builder: (context) => LinkPatientCaregiverUI(
          initialUserHash: viewModel.patientHash,
          userSetting: viewModel.userSetting,
          onLinksChanged: _refreshChatList,
        ),
      ),
    );
    if (mounted) _refreshChatList();
  }

  // Function Name: _openUserSettings
  // Description: Opens settings wired to authentication, setting/language persistence, and ordered account deletion.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: None; updates state or performs the documented action.
  void _openUserSettings(BuildContext context, MedBuddyViewModel viewModel) {
    final authenticationControl = context.read<AuthenticationControl>();
    final appLanguageControl = context.read<AppLanguageControl>();

    // Function Name: deleteCurrentAccount
    // Description: Prepares account deletion, deletes application data, then finalizes authentication-account deletion.
    // Parameters:
    // - None.
    // Returns: Future<void> completing when the requested interaction or refresh finishes.
    Future<void> deleteCurrentAccount() async {
      await authenticationControl.prepareAccountDeletion();
      await viewModel.requestAccountDataDeletion();
      await authenticationControl.finishAccountDeletion();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        // Function Name: _openUserSettings.builder callback
        // Description: Composes the active screen selected by prescription flow and navigation destination with the current parent constraints for the active layout.
        // Parameters:
        // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
        // Returns: Widget subtree for the described layout or fallback.
        builder: (context) => ManageUserSettingUI(
          initialSetting: viewModel.userSetting,
          authenticationControl: authenticationControl,
          // 함수이름: _openUserSettings.onMedicationScheduleRequested callback
          // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `Navigator.push(context, MaterialPageRoute(builder: (context) => const CheckScheduleUI())); MaterialPageRoute(builder: (context) => const CheckScheduleUI())`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onMedicationScheduleRequested: () {
            Navigator.push(
              context,
              // 함수이름: _openUserSettings.builder callback
              // 함수역할: builder에서 오늘의 시간대별 복약 체크·알림·첨부 선택 위젯을 구성한다.
              // 매개변수:
              // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
              // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
              MaterialPageRoute(builder: (context) => const CheckScheduleUI()),
            );
          },
          onDeviceNotificationSettingsRequested:
              NotificationService.instance.openSystemNotificationSettings,
          // 함수이름: _openUserSettings.onExtendedSettingSaveRequested callback
          // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에서 캡처된 작업 `viewModel.requestUserSettingSave(fontSizeOption: setting.fontSizeOption, readingSpeedOption: setting.readingSpeedOption, language: setting.lan...; appLanguageControl.setLanguageMode(result.setting.languageMode)`을 실행한다.
          // 매개변수:
          // - setting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onExtendedSettingSaveRequested: (UserSetting setting) async {
            final result = await viewModel.requestUserSettingSave(
              fontSizeOption: setting.fontSizeOption,
              readingSpeedOption: setting.readingSpeedOption,
              language: setting.language,
              languageMode: setting.languageMode,
              timeFormat: setting.timeFormat,
              medicationNotificationsEnabled:
                  setting.medicationNotificationsEnabled,
              caregiverNotificationsEnabled:
                  setting.caregiverNotificationsEnabled,
              chatNotificationsEnabled: setting.chatNotificationsEnabled,
              notificationDetailMode: setting.notificationDetailMode,
              defaultMorningTime: setting.defaultMorningTime,
              defaultLunchTime: setting.defaultLunchTime,
              defaultEveningTime: setting.defaultEveningTime,
              defaultBedtime: setting.defaultBedtime,
            );
            await appLanguageControl.setLanguageMode(
              result.setting.languageMode,
            );
            return result;
          },
          onSettingSaveRequested:
              // Function Name: _openUserSettings.onSettingSaveRequested callback
              // Description: Connects the active screen selected by prescription flow and navigation destination to the captured operation `viewModel.requestUserSettingSave(fontSizeOption: fontSizeOption, readingSpeedOption: readingSpeedOption, language: language); appLanguageControl.setLanguage(result.setting.language)`.
              // Parameters:
              // - fontSizeOption (String): Text-size or speech-rate option to persist.
              // - readingSpeedOption (String): Text-size or speech-rate option to persist.
              // - language (String): Language code selecting visible wording.
              // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
              ({
                required String fontSizeOption,
                required String readingSpeedOption,
                required String language,
              }) async {
                final result = await viewModel.requestUserSettingSave(
                  fontSizeOption: fontSizeOption,
                  readingSpeedOption: readingSpeedOption,
                  language: language,
                );
                await appLanguageControl.setLanguage(result.setting.language);
                return result;
              },
          onSignOutRequested: authenticationControl.isAnonymous
              ? deleteCurrentAccount
              : authenticationControl.signOut,
          onDeleteAccountRequested: deleteCurrentAccount,
        ),
      ),
    );
  }

  // 함수이름: _requestGuidedPrescriptionImage
  // 함수역할: 처방전 전용 카메라 화면을 열고 촬영된 파일을 ViewModel의 OCR 흐름에 전달한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _requestGuidedPrescriptionImage(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) async {
    final image = await Navigator.push<XFile>(
      context,
      MaterialPageRoute<XFile>(
        // 함수이름: _requestGuidedPrescriptionImage.builder callback
        // 함수역할: 처방 분석 단계와 앱 탐색 목적지별 활성 화면에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
        // 매개변수:
        // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
        // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
        builder: (context) =>
            GuidedPrescriptionCameraUI(userSetting: viewModel.userSetting),
      ),
    );
    if (!context.mounted || image == null) {
      return;
    }
    await viewModel.requestCapturedPrescriptionImage(image);
  }
}
