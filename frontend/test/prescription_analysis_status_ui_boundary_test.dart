// File Name: prescription_analysis_status_ui_boundary_test.dart
// Role: Regression coverage for prescription-analysis retry routes, back navigation, and bulk-save
//   exclusion.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

// Class Name: _EmptyGalleryInputPrescription
// Role: Gallery-recognition spy with an empty successful OCR result.
// Responsibilities:
// - Count gallery retries, signal selection, and complete recognition without medication rows.
// Attributes:
// - galleryRequestCount (int): Gallery-recognition attempts initiated by retry navigation.
class _EmptyGalleryInputPrescription extends InputPrescription {
  int galleryRequestCount = 0;

  // Function Name: requestPrescriptionImageFromGallery
  // Description:
  // - Count gallery retries, signal selection, and complete recognition without medication rows.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Callback announcing that an image has been
  //   selected.
  // Returns:
  // - An empty recognized-schedule list.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    galleryRequestCount += 1;
    onImageSelected?.call();
    return const [];
  }
}

// Class Name: _SuccessfulGalleryInputPrescription
// Role: Gallery-recognition fixture with one successfully recognized prescription item.
// Responsibilities:
// - Signal image selection and supply a three-day, three-times-daily tablet schedule.
class _SuccessfulGalleryInputPrescription extends InputPrescription {
  // Function Name: requestPrescriptionImageFromGallery
  // Description:
  // - Signal image selection and supply a three-day, three-times-daily tablet schedule.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Callback announcing that an image has been
  //   selected.
  // Returns:
  // - One recognized medication schedule.
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

// Class Name: _SuccessfulMedicationDetail
// Role: Successful medication-detail fixture for analysis-result navigation.
// Responsibilities:
// - Resolve the recognized medication name to fixed efficacy, usage, and warning text.
class _SuccessfulMedicationDetail extends CheckMedicationDetail {
  // Function Name: requestMedicationDetail
  // Description:
  // - Resolve the recognized medication name to fixed efficacy, usage, and warning text.
  // Parameters:
  // - medicationSchedule (MedicationSchedule): Recognized or reviewed dose schedule for the medication.
  // Returns:
  // - Medication details retaining the requested name.
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

// Class Name: _DeferredSavedMedication
// Role: Saved-medication fixture that holds bulk saving pending for back-navigation checks.
// Responsibilities:
// - Keep saving pending until the test releases its completion barrier.
// - Return an empty cabinet after the controlled save without backend access.
class _DeferredSavedMedication extends CheckSavedMedication {
  final Completer<MedicationSaveResult> saveCompleter =
      Completer<MedicationSaveResult>();

  // Function Name: saveMedicationDetail
  // Description:
  // - Keep saving pending until the test releases its completion barrier.
  // Parameters:
  // - medicationDetail (MedicationDetail): Resolved medication details requested for saving. Accepted
  //   but not consumed by this fixture.
  // - medicationSchedule (MedicationSchedule?): Recognized or reviewed dose schedule for the medication.
  //   Accepted but not consumed by this fixture.
  // Returns:
  // - The controlled medication-save Future.
  @override
  Future<MedicationSaveResult> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) {
    return saveCompleter.future;
  }

  // Function Name: requestSavedMedicationInfo
  // Description:
  // - Return an empty cabinet after the controlled save without backend access.
  // Parameters:
  // - None.
  // Returns:
  // - An empty saved-medication list.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    return const [];
  }
}

// Class Name: _EmptySchedule
// Role: Empty schedule fixture for the analysis flow's destination refresh.
// Responsibilities:
// - Complete schedule refresh successfully without any due medications.
class _EmptySchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Complete schedule refresh successfully without any due medications.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule list.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

// 함수이름: main
// 함수역할:
// - 처방 분석 재시도 경로, 뒤로가기와 일괄 저장 중 이동 차단 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  for (final language in ['ko', 'en']) {
    testWidgets('success content remains usable at large text in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var resultRequests = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: PrescriptionAnalysisSuccessUI(
            analyzedMedicationList: const [
              AnalyzedMedication(
                schedule: MedicationSchedule(
                  medicationName: 'test-tablet',
                  medicationTime: 3,
                ),
                detail: MedicationDetail(itemName: 'test-tablet'),
              ),
            ],
            userSetting: UserSetting(language: language, fontSize: 20),
            onResultRequested: () => resultRequests++,
          ),
        ),
      );

      final button = find.byKey(
        const Key('prescription-analysis-result-button'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      await tester.tap(button);
      expect(resultRequests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(640, 360),
    ]) {
      for (final textScale in [1.0, 1.3, 2.0]) {
        // 함수이름: testWidgets 콜백
        // 함수역할: 실패 복구 버튼의 글자가 잘리지 않고 일반 휴대폰의 큰 글씨에서 한 줄인지 검사한다.
        // 매개변수: tester (WidgetTester): 화면 크기·글씨 배율과 버튼을 검사할 제어기.
        // 반환값: Future<void>: 화면 배치와 터치 영역 확인 완료.
        testWidgets('failure actions fit $language $size at $textScale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var galleryRequests = 0;
          await tester.pumpWidget(
            MaterialApp(
              // 함수이름: builder 콜백
              // 함수역할: 테스트할 시스템 글씨 배율을 적용한다.
              // 매개변수: context (BuildContext), child (Widget?): 기존 화면.
              // 반환값: 글씨 배율을 적용한 MediaQuery.
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: PrescriptionAnalysisFailureUI(
                message: '인터넷 연결을 확인한 뒤 다시 시도해주세요.',
                userSetting: UserSetting(language: language),
                failureStep: AnalysisProgressStep.prescriptionRecognition,
                onCameraRetryRequested: _ignoreRecovery,
                // 함수이름: onGalleryRetryRequested 콜백
                // 함수역할: 갤러리 복구 동작 횟수를 기록한다.
                // 매개변수: 없음. 반환값: 없음.
                onGalleryRetryRequested: () => galleryRequests++,
                onHomeRequested: _ignoreRecovery,
              ),
            ),
          );
          final button = find.byKey(
            const Key('prescription-gallery-retry-button'),
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final label = find.descendant(
            of: button,
            matching: find.byType(Text),
          );
          final paragraph = tester.renderObject<RenderParagraph>(label);
          final labelRect = tester.getRect(label);
          final buttonRect = tester.getRect(button);
          expect(buttonRect.height, greaterThanOrEqualTo(48));
          expect(buttonRect.contains(labelRect.topLeft), isTrue);
          expect(buttonRect.contains(labelRect.bottomRight), isTrue);
          if (language == 'ko' && size.width >= 390 && textScale <= 1.3) {
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length,
              ),
            );
            // 함수이름: map 콜백
            // 함수역할: 텍스트 조각의 윗좌표로 실제 줄 수를 확인한다.
            // 매개변수: box (TextBox): 선택된 글자 영역. 반환값: 해당 줄의 윗좌표.
            expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          }
          await tester.tap(button);
          expect(galleryRequests, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 처방 분석 실패 화면에서 카메라와 갤러리 재시도 명령을 제공하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('analysis failure offers camera and gallery retry actions', (
    tester,
  ) async {
    var cameraRetryCount = 0;
    var galleryRetryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en'),
          failureStep: AnalysisProgressStep.prescriptionRecognition,
          // Function Name: onCameraRetryRequested callback
          // Description:
          // - Record prescription camera retry so the test can assert the action was dispatched.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the callback completes after its recorded side effects.
          onCameraRetryRequested: () => cameraRetryCount += 1,
          // Function Name: onGalleryRetryRequested callback
          // Description:
          // - Record gallery-recognition retry so the test can assert the action was dispatched.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the callback completes after its recorded side effects.
          onGalleryRetryRequested: () => galleryRetryCount += 1,
          // Function Name: onHomeRequested callback
          // Description:
          // - Keep home navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHomeRequested: () {},
        ),
      ),
    );

    final cameraRetryButton = find.text('Retake Photo');
    await tester.ensureVisible(cameraRetryButton);
    await tester.tap(cameraRetryButton);
    await tester.pump();

    final galleryRetryButton = find.byKey(
      const Key('prescription-gallery-retry-button'),
    );
    await tester.ensureVisible(galleryRetryButton);
    await tester.tap(galleryRetryButton);

    expect(cameraRetryCount, 1);
    expect(galleryRetryCount, 1);
    expect(
      find.byKey(const Key('prescription-analysis-retry-button')),
      findsNothing,
    );
    expect(find.text('Possible reasons'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 약 상세 분석 실패에는 해당 단계의 재시도 명령을 제공하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('medication analysis failure offers stage-specific retry', (
    tester,
  ) async {
    var analysisRetryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: 'Medication lookup failed.',
          userSetting: const UserSetting(language: 'en'),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          // Function Name: onAnalysisRetryRequested callback
          // Description:
          // - Record medication-analysis retry so the test can assert the action was dispatched.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the callback completes after its recorded side effects.
          onAnalysisRetryRequested: () => analysisRetryCount += 1,
          // Function Name: onCameraRetryRequested callback
          // Description:
          // - Keep prescription camera retry available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onCameraRetryRequested: () {},
          // Function Name: onGalleryRetryRequested callback
          // Description:
          // - Keep gallery-recognition retry available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onGalleryRetryRequested: () {},
          // Function Name: onHomeRequested callback
          // Description:
          // - Keep home navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHomeRequested: () {},
        ),
      ),
    );

    expect(find.text('Medication analysis failed'), findsOneWidget);
    expect(find.text('Possible reasons'), findsNothing);

    final analysisRetryButton = find.byKey(
      const Key('prescription-analysis-retry-button'),
    );
    await tester.ensureVisible(analysisRetryButton);
    await tester.tap(analysisRetryButton);

    expect(analysisRetryCount, 1);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 갤러리 재시도가 갤러리 처방 인식 흐름으로 다시 진입하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('gallery retry re-enters the gallery recognition flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inputPrescription = _EmptyGalleryInputPrescription();
    final viewModel = MedBuddyViewModel(inputPrescription: inputPrescription);
    addTearDown(viewModel.dispose);

    await viewModel.requestPrescriptionImageFromGallery();
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisFailed,
    );
    expect(inputPrescription.galleryRequestCount, 1);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final galleryRetryButton = find.byKey(
      const Key('prescription-gallery-retry-button'),
    );
    await tester.ensureVisible(galleryRetryButton);
    await tester.tap(galleryRetryButton);
    await tester.pumpAndSettle();

    expect(inputPrescription.galleryRequestCount, 2);
    expect(
      viewModel.prescriptionFlowState,
      PrescriptionFlowState.analysisFailed,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 처방 결과 화면에서 시스템 뒤로가기를 누르면 홈으로 돌아가는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('system back from prescription result returns to home', (
    tester,
  ) async {
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 일괄 저장이 끝날 때까지 화면 뒤로가기 명령을 차단하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('back actions stay blocked until bulk save completes', (
    tester,
  ) async {
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 작은 화면과 큰 글씨에서도 분석 실패 후 명령이 넘치지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('analysis failure actions fit a compact large-text viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en', fontSize: 20),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          // Function Name: onAnalysisRetryRequested callback
          // Description:
          // - Keep medication-analysis retry available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRetryRequested: () {},
          // Function Name: onCameraRetryRequested callback
          // Description:
          // - Keep prescription camera retry available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onCameraRetryRequested: () {},
          // Function Name: onGalleryRetryRequested callback
          // Description:
          // - Keep gallery-recognition retry available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onGalleryRetryRequested: () {},
          // Function Name: onHomeRequested callback
          // Description:
          // - Keep home navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
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

// 함수이름: _ignoreRecovery
// 함수역할: 배치만 검사하는 테스트에서 화면 이동을 실행하지 않는다.
// 매개변수: 없음. 반환값: 없음.
void _ignoreRecovery() {}
