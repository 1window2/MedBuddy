import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_progress_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('분석 화면은 실제 처리 중인 두 단계만 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.medicationAnalysis,
          userSetting: const UserSetting(),
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
  });

  testWidgets('영어 분석 화면에도 복용 일정 생성 단계를 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisProgressUI(
          activeStep: AnalysisProgressStep.prescriptionRecognition,
          userSetting: const UserSetting(language: 'en'),
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
  });
}
