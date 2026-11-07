// 파일명: prescription_analysis_progress_ui_boundary_test.dart
// 역할: 처방 인식 단계 전환, 약품 조회 진행률과 언어·큰 글씨별 복약 팁 배치를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_progress_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/widgets/medication_loading_tip.dart';

// 함수이름: main
// 함수역할:
// - 언어별 두 단계 처방 분석 진행 표시 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets: 'OCR visibly completes before switching to medication counts'
  // 함수역할: OCR 단계에서 약 정보 분석으로 전환하며 프레임 시간을 나누어 완료 표시와 다음 진행률을 관찰한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 먼저 OCR 100%와 막대 1을 보여준 뒤 4개 중 1개 조회·0.25로 전환하고 화면 제거 후 예외가 없다.
  testWidgets('OCR visibly completes before switching to medication counts', (
    tester,
  ) async {
    // 함수이름: show
    // 함수역할: 인식 세부 단계와 완료 수를 고정한 채 전체 분석 단계만 바꾸어 같은 진행 화면을 갱신한다.
    // 매개변수: step (AnalysisProgressStep): 표시할 전체 분석 단계.
    // 반환값: Future<void>: 구조화 단계·총 4개·완료 1개 화면의 첫 프레임 렌더링 완료.
    Future<void> show(AnalysisProgressStep step) => tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: step,
          recognitionStage: PrescriptionRecognitionStage.structuringMedication,
          totalMedicationCount: 4,
          completedMedicationCount: 1,
          userSetting: const UserSetting(),
          onBackRequested: () {},
        ),
      ),
    );
    await show(AnalysisProgressStep.prescriptionRecognition);
    await tester.pump(const Duration(milliseconds: 400));
    await show(AnalysisProgressStep.medicationAnalysis);
    expect(find.textContaining('100%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('약 4개 중 1개 조회 완료'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  // 함수이름: testWidgets: 'OCR bar advances only when a recognition stage completes'
  // 함수역할: 인식 시작 후 8초를 보내고 이후 각 실제 인식 단계를 주입하며 전환 중·완료 시 진행률을 비교한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 시간만 흘러서는 0이고 단계 변경 시에만 애니메이션으로 해당 progress와 백분율에 도달한다.
  testWidgets('OCR bar advances only when a recognition stage completes', (
    tester,
  ) async {
    // 함수이름: show
    // 함수역할: OCR 분석 화면에 지정한 인식 세부 단계를 전달해 진행률 전환을 시작한다.
    // 매개변수: stage (PrescriptionRecognitionStage): 완료 상태를 반영할 인식 단계.
    // 반환값: Future<void>: 주입한 단계로 첫 프레임을 그리며 애니메이션 완료는 호출자가 기다린다.
    Future<void> show(PrescriptionRecognitionStage stage) => tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.prescriptionRecognition,
          recognitionStage: stage,
          userSetting: const UserSetting(),
          onBackRequested: () {},
        ),
      ),
    );
    await show(PrescriptionRecognitionStage.recognizingText);
    await tester.pump(const Duration(seconds: 8));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    for (final stage in PrescriptionRecognitionStage.values.skip(1)) {
      await show(stage);
      await tester.pump(const Duration(milliseconds: 175));
      final moving = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(moving, lessThan(stage.progress));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        stage.progress,
      );
      expect(
        find.textContaining('${(stage.progress * 100).round()}%'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  // 함수이름: testWidgets: '분석 화면은 실제 처리 중인 두 단계만 표시한다'
  // 함수역할: 약 정보 분석 단계에 총 5개·완료 2개를 주입하고 진행 애니메이션이 끝날 때까지 기다린다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 처방 인식·약물 분석 두 단계만 보이고 진행률 0.4, 2개 완료 문구와 복약 팁이 표시된다.
  testWidgets('분석 화면은 실제 처리 중인 두 단계만 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.medicationAnalysis,
          completedMedicationCount: 2,
          totalMedicationCount: 5,
          userSetting: const UserSetting(),
          // 함수이름: onBackRequested 콜백
          // 함수역할:
          // - 뒤로가기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onBackRequested: () {},
        ),
      ),
    );

    expect(find.text('처방전 인식 중...'), findsOneWidget);
    expect(find.text('약물 정보 분석 중...'), findsOneWidget);
    expect(find.text('복용 일정 생성 중...'), findsNothing);

    await tester.pump(const Duration(milliseconds: 350));
    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressIndicator.value, 0.4);
    expect(find.text('약 5개 중 2개 조회 완료'), findsOneWidget);
    expect(find.byType(MedicationLoadingTip), findsOneWidget);
    expect(find.text('복약 팁'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets: '영어 분석 화면에도 복용 일정 생성 단계를 표시하지 않는다'
  // 함수역할: 영어 설정으로 처방전 인식 초기 화면을 렌더링한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 인식·약물 분석 영어 문구와 Medication tip은 보이고 일정 생성 단계는 없으며 진행률은 0이다.
  testWidgets('영어 분석 화면에도 복용 일정 생성 단계를 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.prescriptionRecognition,
          userSetting: const UserSetting(language: 'en'),
          // 함수이름: onBackRequested 콜백
          // 함수역할:
          // - 뒤로가기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onBackRequested: () {},
        ),
      ),
    );

    expect(find.text('Recognizing prescription...'), findsOneWidget);
    expect(find.text('Analyzing medication info...'), findsOneWidget);
    expect(find.text('Creating medication schedule...'), findsNothing);

    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressIndicator.value, 0);
    expect(find.byType(MedicationLoadingTip), findsOneWidget);
    expect(find.text('Medication tip'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets: 'tips stay at the top and the analysis panel stays near center'
  // 함수역할: 390x844 화면에 완료 0·총 5개의 약 분석 화면을 렌더링하고 팁·분석 영역 위치를 측정한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 팁은 상단 110 이내, 분석 영역 중심은 y=422의 90 오차 이내이며 0개 완료·진행률 0을 표시한다.
  testWidgets('tips stay at the top and the analysis panel stays near center', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.medicationAnalysis,
          userSetting: const UserSetting(),
          totalMedicationCount: 5,
          onBackRequested: () {},
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byType(MedicationLoadingTip)).dy,
      lessThan(110),
    );
    expect(
      tester.getCenter(find.byKey(const Key('analysis-progress-panel'))).dy,
      closeTo(422, 90),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(find.text('약 5개 중 0개 조회 완료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final step in AnalysisProgressStep.values) {
    for (final language in ['ko', 'en']) {
      for (final viewport in [
        (size: Size(320, 568), scale: 2.0),
        (size: Size(390, 844), scale: 1.3),
        (size: Size(640, 360), scale: 2.0),
      ]) {
        // 함수이름: 분석 팁 접근성 배치 테스트
        // 함수역할: OCR·API 양쪽에서 언어·화면 크기와 무관하게 팁 전체 및 뒤로가기에 접근한다.
        // 매개변수: tester. 반환값: 검증 완료.
        testWidgets('$step $language ${viewport.size} 팁은 잘림 없이 스크롤된다', (
          tester,
        ) async {
          tester.view.physicalSize = viewport.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var backCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(viewport.scale),
                ),
                child: PrescriptionAnalysisProgressUI(
                  activeStep: step,
                  userSetting: UserSetting(language: language, fontSize: 20),
                  // 함수이름: 뒤로가기 검증 콜백
                  // 함수역할: 호출 횟수를 기록한다. 매개변수: 없음. 반환값: 없음.
                  onBackRequested: () {
                    backCount++;
                  },
                ),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            final tip = find.byKey(const ValueKey('analysisMedicationTipText'));
            final tipRegion = find.byType(MedicationLoadingTip);
            final progress = find.text(language == 'en' ? 'Analyzing' : '분석중');
            expect(
              tester.getBottomLeft(tipRegion).dy,
              lessThan(tester.getTopLeft(progress).dy),
            );
            await tester.ensureVisible(tip);
            await tester.pump();
            final rect = tester.getRect(tip);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(viewport.size.width));
            expect(tester.widget<Text>(tip).maxLines, isNull);
            expect(tester.widget<Text>(tip).textAlign, TextAlign.center);
            final heading = find.text(
              language == 'en' ? 'Medication tip' : '복약 팁',
            );
            expect(tester.widget<Text>(heading).textAlign, TextAlign.center);
            expect(
              tester.getCenter(heading).dx,
              closeTo(viewport.size.width / 2, 0.01),
            );
            expect(tester.takeException(), isNull);
            await tester.pump(MedicationLoadingTip.rotationInterval);
          }
          final back = find.byTooltip(language == 'en' ? 'Back' : '뒤로가기');
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          expect(backCount, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 30));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
