// File Name: medbuddy_view_model_analysis_test.dart
// Role: Verifies prescription analysis state handling in MedBuddyViewModel.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

class _FakeInputPrescription extends InputPrescription {
  final List<MedicationSchedule> schedules;
  final int rawCount;
  final int parsedCount;
  final int skippedCount;

  _FakeInputPrescription(
    this.schedules, {
    this.rawCount = 0,
    this.parsedCount = 0,
    this.skippedCount = 0,
  });

  @override
  int get lastRawMedicationCount => rawCount;

  @override
  int get lastParsedMedicationCount => parsedCount;

  @override
  int get lastSkippedMedicationCount => skippedCount;

  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    onImageSelected?.call();
    return schedules;
  }
}

class _FakeCheckMedicationDetail extends CheckMedicationDetail {
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    if (medicationSchedule.medicationName == 'missing-tablet') {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

class _DeferredInputPrescription extends InputPrescription {
  final Completer<List<MedicationSchedule>?> completer =
      Completer<List<MedicationSchedule>?>();

  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) {
    onImageSelected?.call();
    return completer.future;
  }
}

class _DeferredCheckMedicationDetail extends CheckMedicationDetail {
  final Completer<MedicationDetail?> completer = Completer<MedicationDetail?>();

  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) {
    return completer.future;
  }
}

class _RetryableCheckMedicationDetail extends CheckMedicationDetail {
  int requestCount = 0;

  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    requestCount += 1;
    if (requestCount == 1) {
      return null;
    }
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

void main() {
  test('requestPrescriptionImageFromGallery exposes OCR correction notice',
      () async {
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(
        const [
          MedicationSchedule(
            medicationName: '프루코프정',
            rawMedicationName: '포루코프정',
            nameConfidence: 0.92,
            nameCorrectionSource: 'local_catalog_ocr_vowel_variant',
          ),
        ],
        rawCount: 2,
        parsedCount: 1,
        skippedCount: 1,
      ),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.previewReady);
    expect(viewModel.lastPrescriptionRawMedicationCount, 2);
    expect(viewModel.lastPrescriptionParsedMedicationCount, 1);
    expect(viewModel.lastPrescriptionSkippedMedicationCount, 1);
    expect(viewModel.correctedPrescriptionMedicationCount, 1);
    expect(viewModel.prescriptionRecognitionNotice, contains('약명 보정'));
    expect(viewModel.prescriptionRecognitionNotice, contains('OCR 항목 제외'));
    expect(viewModel.statusMessage, contains('인식 내역'));
  });

  test('requestPrescriptionAnalysis surfaces partial lookup failures',
      () async {
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(
        const [
          MedicationSchedule(medicationName: 'found-tablet'),
          MedicationSchedule(medicationName: 'missing-tablet'),
        ],
      ),
      checkMedicationDetail: _FakeCheckMedicationDetail(),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();

    expect(viewModel.prescriptionFlowState,
        PrescriptionFlowState.analysisSucceeded);
    expect(viewModel.analyzedMedicationList, hasLength(1));
    expect(viewModel.statusMessage, contains('1개 약 정보'));
  });

  test('medication analysis can retry without repeating prescription OCR',
      () async {
    final detailControl = _RetryableCheckMedicationDetail();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(
        const [MedicationSchedule(medicationName: 'retry-tablet')],
      ),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();

    expect(
        viewModel.prescriptionFlowState, PrescriptionFlowState.analysisFailed);
    expect(viewModel.canRetryPrescriptionAnalysis, isTrue);
    expect(viewModel.recognizedMedicationScheduleList, hasLength(1));

    await viewModel.requestPrescriptionAnalysis();

    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    expect(viewModel.canRetryPrescriptionAnalysis, isFalse);
    expect(viewModel.analyzedMedicationList, hasLength(1));
    expect(detailControl.requestCount, 2);
  });

  test('prescription recognition failure does not expose analysis retry',
      () async {
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(const []),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();

    expect(
        viewModel.prescriptionFlowState, PrescriptionFlowState.analysisFailed);
    expect(viewModel.canRetryPrescriptionAnalysis, isFalse);
  });

  test('clearing recognition ignores a late OCR result', () async {
    final prescriptionControl = _DeferredInputPrescription();
    final viewModel = MedBuddyViewModel(
      inputPrescription: prescriptionControl,
    );
    addTearDown(viewModel.dispose);

    final pendingRequest = viewModel.requestPrescriptionImageFromGallery();
    await Future<void>.delayed(Duration.zero);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.recognizingPrescription,
    );

    viewModel.clearAnalysisResult();
    prescriptionControl.completer.complete(
      const [MedicationSchedule(medicationName: 'late-tablet')],
    );
    await pendingRequest;

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
    expect(viewModel.recognizedMedicationScheduleList, isEmpty);
  });

  test('clearing analysis ignores a late medication detail result', () async {
    final detailControl = _DeferredCheckMedicationDetail();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _FakeInputPrescription(
        const [MedicationSchedule(medicationName: 'late-tablet')],
      ),
      checkMedicationDetail: detailControl,
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    final pendingRequest = viewModel.requestPrescriptionAnalysis();
    await Future<void>.delayed(Duration.zero);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analyzingMedication,
    );

    viewModel.clearAnalysisResult();
    detailControl.completer.complete(
      const MedicationDetail(
        itemName: 'late-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
    );
    await pendingRequest;

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
    expect(viewModel.analyzedMedicationList, isEmpty);
  });
}
