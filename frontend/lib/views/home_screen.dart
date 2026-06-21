import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../boundaries/check_result_ui_boundary.dart';
import '../boundaries/check_saved_medication_ui_boundary.dart';
import '../boundaries/input_prescription_ui_boundary.dart';
import '../boundaries/manage_user_setting_ui_boundary.dart';
import '../boundaries/prescription_analysis_preview_ui_boundary.dart';
import '../boundaries/prescription_analysis_progress_ui_boundary.dart';
import '../boundaries/prescription_analysis_status_ui_boundary.dart';
import '../viewmodels/medbuddy_view_model.dart';

// 파일명: home_screen.dart
// 역할: ViewModel의 처방전 분석 상태에 따라 실제 표시할 화면을 선택한다.

// 클래스명: HomeScreen
// 역할: 홈, OCR 예비 결과, 분석중, 분석 성공/실패, 최종 결과 화면 사이를 전환한다.
// 주요 책임:
// - PrescriptionFlowState 값을 기준으로 하나의 화면만 렌더링한다.
// - 홈 화면에서 저장 목록과 설정 화면으로 이동하는 navigation을 연결한다.
// - 아직 미구현인 오늘 일정/환자-보호자 연동 기능은 안내 메시지로 처리한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();

    return switch (viewModel.prescriptionFlowState) {
      PrescriptionFlowState.recognizingPrescription =>
        PrescriptionAnalysisProgressUI(
          activeStep: viewModel.analysisProgressStep,
          userSetting: viewModel.userSetting,
          onBackRequested: viewModel.clearAnalysisResult,
        ),
      PrescriptionFlowState.previewReady => PrescriptionAnalysisPreviewUI(
          medicationScheduleList: viewModel.recognizedMedicationScheduleList,
          userSetting: viewModel.userSetting,
          onBackRequested: viewModel.clearAnalysisResult,
          onAnalysisRequested: viewModel.requestMedicationAnalysis,
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
          onRetryRequested: viewModel.requestPrescriptionImage,
          onHomeRequested: viewModel.clearAnalysisResult,
        ),
      PrescriptionFlowState.resultReady => CheckResultUI(
          analyzedMedicationList: viewModel.analyzedMedicationList,
          userSetting: viewModel.userSetting,
          statusMessageProvider: () => viewModel.statusMessage,
          savingMedicationIndex: viewModel.savingMedicationIndex,
          completedMedicationSaveIndexes:
              viewModel.completedMedicationSaveIndexes,
          isAllMedicationSaving: viewModel.isAllMedicationSaving,
          onCloseRequested: viewModel.clearAnalysisResult,
          onAllMedicationSaveRequested:
              viewModel.requestAllAnalyzedMedicationSave,
          onMedicationSaveRequested: viewModel.requestAnalyzedMedicationSave,
        ),
      PrescriptionFlowState.idle => _buildHomeInput(context, viewModel),
    };
  }

  // 함수명: _buildHomeInput
  // 함수역할:
  // - 기본 홈 화면에서 사용할 버튼 동작과 navigation 콜백을 구성한다.
  // 매개변수:
  // - context: 화면 이동과 Snackbar 표시를 위한 BuildContext
  // - viewModel: 앱 상태와 사용자 요청 함수를 제공하는 ViewModel
  // 반환값:
  // - 홈 입력 화면 Widget
  Widget _buildHomeInput(
    BuildContext context,
    MedBuddyViewModel viewModel,
  ) {
    final isEnglish = viewModel.userSetting.language == 'en';

    return InputPrescriptionUI(
      statusMessage: viewModel.statusMessage,
      userSetting: viewModel.userSetting,
      onPrescriptionScanRequested: viewModel.requestPrescriptionImage,
      onPrescriptionGalleryRequested:
          viewModel.requestPrescriptionImageFromGallery,
      onTodayScheduleRequested: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEnglish
                  ? 'Today\'s medication schedule is coming soon.'
                  : '오늘의 복약 일정은 준비 중입니다.',
            ),
          ),
        );
      },
      onSavedMedicationRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CheckSavedMedicationUI(),
          ),
        );
      },
      onPatientCaregiverLinkRequested: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEnglish
                  ? 'Patient/caregiver linking is coming soon.'
                  : '환자/보호자 연동은 준비 중입니다.',
            ),
          ),
        );
      },
      onUserSettingRequested: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ManageUserSettingUI(
              initialSetting: viewModel.userSetting,
              onSettingSaveRequested: viewModel.requestUserSettingSave,
            ),
          ),
        );
      },
    );
  }
}
