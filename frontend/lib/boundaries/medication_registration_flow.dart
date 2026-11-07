// File Name: medication_registration_flow.dart
// Role: Connects the shared registration menu to manual entry, pill recognition and prescription analysis.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../viewmodels/medbuddy_view_model.dart';
import 'guided_prescription_camera_ui_boundary.dart';
import 'manual_medication_entry_ui_boundary.dart';
import 'medication_capture_options_ui_boundary.dart';
import 'pill_identification_ui_boundary.dart';

// Function Name: openPillIdentification
// Description: Opens pill recognition with the selected capture mode and the current account save callbacks.
// Parameters: context (BuildContext): Navigator location; viewModel (MedBuddyViewModel): account and save owner; mode (PillCaptureMode): capture workflow.
// Returns: Future<void> completed when the identification route closes.
Future<void> openPillIdentification(
  BuildContext context,
  MedBuddyViewModel viewModel,
  PillCaptureMode mode,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => PillIdentificationUI(
      userSetting: viewModel.userSetting,
      captureMode: mode,
      onSaveRequested: viewModel.saveIdentifiedPill,
      onBatchSaveRequested: viewModel.saveIdentifiedPills,
    ),
  ),
);

// Function Name: openMedicationRegistration
// Description: Opens the registration choices and routes to manual entry, pill recognition or prescription capture; manual saves share one final refresh.
// Parameters: context (BuildContext): Provider and Navigator location.
// Returns: Future<void> completed after the selected menu workflow; cancelling creates no medication.
Future<void> openMedicationRegistration(BuildContext context) async {
  final viewModel = context.read<MedBuddyViewModel>();
  await showMedicationCaptureTaskOptions(
    context: context,
    userSetting: viewModel.userSetting,
    onTaskSelected: (pageContext, task) async {
      if (task == MedicationCaptureTask.manual) {
        await Navigator.of(pageContext).push<bool>(
          MaterialPageRoute<bool>(
            // 선택한 계정의 저장 작업을 직접 등록 화면에 연결한다.
            builder: (_) => ManualMedicationEntryUI(
              userSetting: viewModel.userSetting,
              // 여러 약을 저장해도 목록·일정·알림은 마지막에 한 번만 갱신한다.
              onSaveRequested: (entry) =>
                  viewModel.saveManualMedication(entry, refreshAfterSave: false),
              onSavesFinished: viewModel.refreshAfterMedicationSaves,
            ),
          ),
        );
      } else {
        await openPillIdentification(
          pageContext,
          viewModel,
          task == MedicationCaptureTask.multiplePills
              ? PillCaptureMode.singlePhoto
              : PillCaptureMode.individualPhotos,
        );
      }
    },
    onSourceSelected: (pageContext, source) =>
        startPrescriptionFromRegistration(pageContext, viewModel, source),
  );
}

// 함수이름: startPrescriptionFromRegistration
// 함수역할: 카메라 확정 또는 갤러리 선택으로 분석을 시작하고, 분석 상태가 바뀔 때만 홈 화면을 드러낸다.
// 매개변수: context (BuildContext): 등록 경로; viewModel (MedBuddyViewModel): 분석 상태·요청 소유자; source (PrescriptionImageSource): 사진 출처.
// 반환값: 요청 후 완료; 촬영 취소 시 종료하며 실패해도 상태 감시자를 제거한다.
Future<void> startPrescriptionFromRegistration(
  BuildContext context,
  MedBuddyViewModel viewModel,
  PrescriptionImageSource source,
) async {
  final navigator = Navigator.of(context);
  final registrationRoute = ModalRoute.of(context);
  final initialState = viewModel.prescriptionFlowState;
  XFile? image;
  if (source == PrescriptionImageSource.camera) {
    image = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        // 촬영 가이드에서 확정한 이미지 파일만 분석 대상으로 반환받는다.
        builder: (_) =>
            GuidedPrescriptionCameraUI(userSetting: viewModel.userSetting),
      ),
    );
    if (!context.mounted || image == null) return;
  }
  // 사진을 실제로 선택한 경우에만 홈의 분석 화면을 드러낸다.
  var revealScheduled = false;
  // 함수이름: revealAnalysis
  // 함수역할: 실제 분석 상태 변화가 있으면 다음 프레임에 살아 있는 등록 경로를 홈까지 닫도록 한 번 예약한다.
  // 매개변수: 없음.
  // 반환값: 없음. 상태가 같거나 이미 예약했으면 무시한다.
  void revealAnalysis() {
    if (revealScheduled || viewModel.prescriptionFlowState == initialState) {
      return;
    }
    revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && registrationRoute?.isActive == true) {
        navigator.popUntil((route) => route.isFirst);
      }
    });
  }

  viewModel.addListener(revealAnalysis);
  try {
    if (image != null) {
      await viewModel.requestCapturedPrescriptionImage(image);
    } else {
      await viewModel.requestPrescriptionImageFromGallery();
    }
  } finally {
    viewModel.removeListener(revealAnalysis);
  }
}
