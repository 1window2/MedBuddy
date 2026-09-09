// 파일명: prescription_analysis_progress_ui_boundary_test.dart
// 역할: 언어별 두 단계 처방 분석 진행 표시을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_progress_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

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
  });
}
