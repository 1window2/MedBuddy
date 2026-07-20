import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

class _EmptyGalleryInputPrescription extends InputPrescription {
  int galleryRequestCount = 0;

  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    galleryRequestCount += 1;
    onImageSelected?.call();
    return const [];
  }
}

class _SuccessfulGalleryInputPrescription extends InputPrescription {
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    onImageSelected?.call();
    return const [
      MedicationSchedule(
        medicationName: 'test-tablet',
        dosage: '1 tablet',
        intakeTime: '3 times',
        medicationTime: 3,
      ),
    ];
  }
}

class _SuccessfulMedicationDetail extends CheckMedicationDetail {
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    return MedicationDetail(
      itemName: medicationSchedule.medicationName,
      efficacy: 'effect',
      usageMethod: 'usage',
      warning: 'warning',
    );
  }
}

class _DeferredSavedMedication extends CheckSavedMedication {
  final Completer<MedicationSaveResult> saveCompleter =
      Completer<MedicationSaveResult>();

  @override
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) {
    return saveCompleter.future;
  }

  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    return const [];
  }
}

class _EmptySchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

void main() {
  testWidgets('analysis failure offers camera and gallery retry actions',
      (tester) async {
    var cameraRetryCount = 0;
    var galleryRetryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en'),
          failureStep: AnalysisProgressStep.prescriptionRecognition,
          onCameraRetryRequested: () => cameraRetryCount += 1,
          onGalleryRetryRequested: () => galleryRetryCount += 1,
          onHomeRequested: () {},
        ),
      ),
    );

    final cameraRetryButton = find.text('Retake Photo');
    await tester.ensureVisible(cameraRetryButton);
    await tester.tap(cameraRetryButton);
    await tester.pump();

    final galleryRetryButton =
        find.byKey(const Key('prescription-gallery-retry-button'));
    await tester.ensureVisible(galleryRetryButton);
    await tester.tap(
      galleryRetryButton,
    );

    expect(cameraRetryCount, 1);
    expect(galleryRetryCount, 1);
    expect(
      find.byKey(const Key('prescription-analysis-retry-button')),
      findsNothing,
    );
    expect(find.text('Possible reasons'), findsOneWidget);
  });

  testWidgets('medication analysis failure offers stage-specific retry',
      (tester) async {
    var analysisRetryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: 'Medication lookup failed.',
          userSetting: const UserSetting(language: 'en'),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          onAnalysisRetryRequested: () => analysisRetryCount += 1,
          onCameraRetryRequested: () {},
          onGalleryRetryRequested: () {},
          onHomeRequested: () {},
        ),
      ),
    );

    expect(find.text('Medication analysis failed'), findsOneWidget);
    expect(find.text('Possible reasons'), findsNothing);

    final analysisRetryButton =
        find.byKey(const Key('prescription-analysis-retry-button'));
    await tester.ensureVisible(analysisRetryButton);
    await tester.tap(analysisRetryButton);

    expect(analysisRetryCount, 1);
  });

  testWidgets('gallery retry re-enters the gallery recognition flow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inputPrescription = _EmptyGalleryInputPrescription();
    final viewModel = MedBuddyViewModel(inputPrescription: inputPrescription);
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    expect(
        viewModel.prescriptionFlowState, PrescriptionFlowState.analysisFailed);
    expect(inputPrescription.galleryRequestCount, 1);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final galleryRetryButton =
        find.byKey(const Key('prescription-gallery-retry-button'));
    await tester.ensureVisible(galleryRetryButton);
    await tester.tap(galleryRetryButton);
    await tester.pumpAndSettle();

    expect(inputPrescription.galleryRequestCount, 2);
    expect(
        viewModel.prescriptionFlowState, PrescriptionFlowState.analysisFailed);
  });

  testWidgets('system back from prescription result returns to home',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = MedBuddyViewModel(
      inputPrescription: _SuccessfulGalleryInputPrescription(),
      checkMedicationDetail: _SuccessfulMedicationDetail(),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();
    viewModel.showMedicationAnalysisResult();
    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.resultReady);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('back actions stay blocked until bulk save completes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedMedication = _DeferredSavedMedication();
    final viewModel = MedBuddyViewModel(
      inputPrescription: _SuccessfulGalleryInputPrescription(),
      checkMedicationDetail: _SuccessfulMedicationDetail(),
      checkSavedMedication: savedMedication,
      checkSchedule: _EmptySchedule(),
    );
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    await viewModel.requestPrescriptionAnalysis();
    viewModel.showMedicationAnalysisResult();

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final pendingSave = viewModel.requestAllAnalyzedMedicationSave();
    await tester.pump();
    expect(viewModel.isAllMedicationSaving, isTrue);

    final backButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    expect(backButton.onPressed, isNull);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.resultReady);

    savedMedication.saveCompleter.complete(
      const MedicationSaveResult(
        status: MedicationSaveStatus.saved,
        message: 'saved',
      ),
    );
    await pendingSave;
    await tester.pumpAndSettle();
    expect(viewModel.isAllMedicationSaving, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(viewModel.prescriptionFlowState, PrescriptionFlowState.idle);
  });

  testWidgets('analysis failure actions fit a compact large-text viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en', fontSize: 20),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          onAnalysisRetryRequested: () {},
          onCameraRetryRequested: () {},
          onGalleryRetryRequested: () {},
          onHomeRequested: () {},
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('prescription-gallery-retry-button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
