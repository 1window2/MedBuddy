import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../boundaries/check_result_ui_boundary.dart';
import '../boundaries/check_schedule_ui_boundary.dart';
import '../boundaries/check_saved_medication_ui_boundary.dart';
import '../boundaries/health_recommendation_ui_boundary.dart';
import '../boundaries/guided_prescription_camera_ui_boundary.dart';
import '../boundaries/input_prescription_ui_boundary.dart';
import '../boundaries/link_patient_caregiver_ui_boundary.dart';
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
import '../entities/prescription_flow_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/medbuddy_feature_updates.dart';

// 파일명: home_screen.dart
// 역할: ViewModel의 처방전 분석 상태에 따라 실제 표시할 화면을 선택한다.

// 클래스명: HomeScreen
// 역할: 홈, OCR 예비 결과, 분석중, 분석 성공/실패, 최종 결과 화면 사이를 전환한다.
// 주요 책임:
// - PrescriptionFlowState 값을 기준으로 하나의 화면만 렌더링한다.
// - 홈 화면에서 저장 목록, 오늘 일정, 설정 화면으로 이동하는 navigation을 연결한다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MedBuddyDestination _selectedDestination = MedBuddyDestination.home;
  final Set<MedBuddyDestination> _visitedDestinations = {
    MedBuddyDestination.home,
  };

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
      builder: (context, _) => _buildActiveScreen(context, viewModel),
    );
  }

  Widget _buildActiveScreen(BuildContext context, MedBuddyViewModel viewModel) {
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
        onTodayScheduleRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.schedule);
        },
        onSavedMedicationRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.medicationCabinet);
        },
        onHomeRequested: () {
          viewModel.clearAnalysisResult();
          _selectDestination(MedBuddyDestination.home);
        },
      ),
      PrescriptionFlowState.idle => _buildApplicationShell(context, viewModel),
    };

    return PopScope<void>(
      canPop: flowState == PrescriptionFlowState.idle,
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
  // 함수역할:
  // - 홈, 일정, 복약함, 내 정보의 최상위 목적지와 공통 하단 탐색 막대를 구성한다.
  // - 최초로 선택한 목적지만 생성하고 이후에는 IndexedStack으로 화면 상태를 보존한다.
  // 매개변수:
  // - context: Provider와 화면 이동에 사용할 BuildContext
  // - viewModel: 각 목적지에서 공유하는 MedBuddyViewModel
  // 반환값:
  // - 선택 목적지와 공통 하단 탐색 막대를 포함한 Widget
  Widget _buildApplicationShell(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) {
    final destinations = MedBuddyDestination.values;
    final selectedIndex = destinations.indexOf(_selectedDestination);

    return PopScope<void>(
      canPop: _selectedDestination == MedBuddyDestination.home,
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
              () => _buildHomeInput(context, viewModel),
            ),
            _buildDestination(
              MedBuddyDestination.schedule,
              () => const CheckScheduleUI(showBackButton: false),
            ),
            _buildDestination(
              MedBuddyDestination.medicationCabinet,
              () => const CheckSavedMedicationUI(showCloseButton: false),
            ),
            _buildDestination(
              MedBuddyDestination.profile,
              () => ManageUserHubUI(
                userSetting: viewModel.userSetting,
                authenticationControl: context.read<AuthenticationControl>(),
                onPatientCaregiverLinkRequested: () =>
                    _openPatientCaregiverLink(context, viewModel),
                onUserSettingRequested: () =>
                    _openUserSettings(context, viewModel),
              ),
            ),
          ],
        ),
        bottomNavigationBar: MedBuddyBottomNavigationUI(
          selectedDestination: _selectedDestination,
          language: viewModel.userSetting.language,
          onDestinationSelected: _selectDestination,
        ),
      ),
    );
  }

  Widget _buildDestination(
    MedBuddyDestination destination,
    Widget Function() builder,
  ) {
    if (!_visitedDestinations.contains(destination)) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(key: ValueKey(destination), child: builder());
  }

  void _selectDestination(MedBuddyDestination destination) {
    if (destination == MedBuddyDestination.schedule &&
        _visitedDestinations.contains(MedBuddyDestination.schedule)) {
      unawaited(context.read<MedBuddyViewModel>().refreshMedicationSchedule());
    }
    if (_selectedDestination == destination) {
      return;
    }
    setState(() {
      _selectedDestination = destination;
      _visitedDestinations.add(destination);
    });
  }

  // 함수명: _buildHomeInput
  // 함수역할:
  // - 홈 화면의 버튼 동작과 navigation 콜백을 구성한다.
  // 매개변수:
  // - context: 화면 이동과 Snackbar 표시를 위한 BuildContext
  // - viewModel: 홈 화면 상태와 사용자 요청 함수를 제공하는 ViewModel
  // 반환값:
  // - 홈 입력 화면 Widget
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
      onPrescriptionScanRequested: () =>
          _requestGuidedPrescriptionImage(context, viewModel),
      onPrescriptionGalleryRequested:
          viewModel.requestPrescriptionImageFromGallery,
      onPillIdentificationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                PillIdentificationUI(userSetting: viewModel.userSetting),
          ),
        );
      },
      onTodayScheduleRequested: () {
        _selectDestination(MedBuddyDestination.schedule);
      },
      onHealthRecommendationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HealthRecommendationUI(),
          ),
        );
      },
      onMedicationReminderRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MedicationReminderSettingsUI(),
          ),
        );
      },
      onUserSettingRequested: () => _openUserSettings(context, viewModel),
    );
  }

  void _openPatientCaregiverLink(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LinkPatientCaregiverUI(initialUserHash: viewModel.patientHash),
      ),
    );
  }

  // 함수이름: _openUserSettings
  // 함수역할:
  // - 홈 헤더와 내 정보 화면이 동일한 사용자 설정 및 계정 생명주기 흐름을 사용하게 한다.
  // 매개변수:
  // - context: 인증 및 언어 Control 조회와 화면 이동에 사용할 BuildContext
  // - viewModel: 사용자 설정 저장 및 계정 데이터 삭제 요청을 제공하는 ViewModel
  // 반환값:
  // - 없음
  void _openUserSettings(BuildContext context, MedBuddyViewModel viewModel) {
    final authenticationControl = context.read<AuthenticationControl>();
    final appLanguageControl = context.read<AppLanguageControl>();

    Future<void> deleteCurrentAccount() async {
      await authenticationControl.prepareAccountDeletion();
      await viewModel.requestAccountDataDeletion();
      await authenticationControl.finishAccountDeletion();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageUserSettingUI(
          initialSetting: viewModel.userSetting,
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
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
  // 함수역할:
  // - 처방전 전용 카메라 화면을 열고 촬영된 파일을 ViewModel의 OCR 흐름에 전달한다.
  // 매개변수:
  // - context: 전용 카메라 화면을 표시할 BuildContext
  // - viewModel: 촬영 파일을 분석할 MedBuddyViewModel
  // 반환값:
  // - 없음
  Future<void> _requestGuidedPrescriptionImage(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) async {
    final image = await Navigator.push<XFile>(
      context,
      MaterialPageRoute<XFile>(
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
