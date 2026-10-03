import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../viewmodels/medbuddy_view_model.dart';
import 'guided_prescription_camera_ui_boundary.dart';
import 'manual_medication_entry_ui_boundary.dart';
import 'medication_capture_options_ui_boundary.dart';
import 'pill_identification_ui_boundary.dart';

// context의 현재 계정으로 공통 약 등록 메뉴를 열고 선택한 입력 흐름이 끝날 때 완료한다.
// 입력 취소 시 데이터를 저장하지 않으며, OCR은 최상위 홈의 분석 화면으로 연결한다.
Future<void> openMedicationRegistration(BuildContext context) async {
  final viewModel = context.read<MedBuddyViewModel>();
  final task = await showMedicationCaptureTaskOptions(
    context: context,
    userSetting: viewModel.userSetting,
  );
  if (!context.mounted || task == null) return;
  if (task == MedicationCaptureTask.manual) {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        // 선택한 계정의 저장 작업을 직접 등록 화면에 연결한다.
        builder: (_) => ManualMedicationEntryUI(
          userSetting: viewModel.userSetting,
          onSaveRequested: viewModel.saveManualMedication,
        ),
      ),
    );
    return;
  }
  if (task == MedicationCaptureTask.multiplePills ||
      task == MedicationCaptureTask.individualPills) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        // 선택한 촬영 방식과 기존 저장 명령을 알약 식별 화면에 연결한다.
        builder: (_) => PillIdentificationUI(
          userSetting: viewModel.userSetting,
          captureMode: task == MedicationCaptureTask.multiplePills
              ? PillCaptureMode.singlePhoto
              : PillCaptureMode.individualPhotos,
          onSaveRequested: viewModel.saveIdentifiedPill,
          onBatchSaveRequested: viewModel.saveIdentifiedPills,
        ),
      ),
    );
    return;
  }
  final source = await showPrescriptionImageSourceOptions(
    context: context,
    userSetting: viewModel.userSetting,
  );
  if (!context.mounted || source == null) return;
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
  // 어느 화면에서 등록을 시작해도 홈의 OCR 진행 화면을 가리지 않는다.
  Navigator.of(context).popUntil((route) => route.isFirst);
  if (image != null) {
    await viewModel.requestCapturedPrescriptionImage(image);
  } else {
    await viewModel.requestPrescriptionImageFromGallery();
  }
}
