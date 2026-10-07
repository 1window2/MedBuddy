// 파일명: prescription_analysis_progress_ui_boundary_test.dart
// 역할: 언어별 두 단계 처방 분석 진행 표시을 검증한다.
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
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 분석 화면은 실제 처리 중인 두 단계만 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('분석 화면은 실제 처리 중인 두 단계만 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.medicationAnalysis,
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

    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressIndicator.value, 0.85);
    expect(find.byType(MedicationLoadingTip), findsOneWidget);
    expect(find.text('복약 팁'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영어 분석 화면에도 복용 일정 생성 단계를 표시하지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
    expect(progressIndicator.value, 0.5);
    expect(find.byType(MedicationLoadingTip), findsOneWidget);
    expect(find.text('Medication tip'), findsOneWidget);
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
