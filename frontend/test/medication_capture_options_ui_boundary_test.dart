// 파일명: medication_capture_options_ui_boundary_test.dart
// 역할: 알약 촬영 방식 선택, 이전 단계 복귀와 큰 글씨 접근성을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할: 공통 약 등록 선택창의 탐색·취소 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  for (final language in ['ko', 'en']) {
    for (final multiple in [true, false]) {
      // 함수역할: 좁은 화면과 큰 글씨에서도 시트 하나로 방식을 선택하고 정확한 작업을 전달한다.
      // 매개변수: tester. 반환값: 선택 결과와 레이아웃 검사 완료.
      testWidgets('촬영 방식 선택 $language $multiple', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        MedicationCaptureTask? selected;
        final english = language == 'en';
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showMedicationCaptureTaskOptions(
                      context: context,
                      userSetting: UserSetting(
                        language: language,
                        fontSize: 20,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final pill = find.text(english ? 'Identify a loose pill' : '낱알약 식별');
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(selected, isNull);

        // 시스템 뒤로 가기는 현재 시트의 이전 단계로 돌아간다.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text(english ? 'Add manually' : '직접 등록'), findsOneWidget);
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pill-mode-back-button')));
        await tester.pumpAndSettle();
        expect(find.text(english ? 'Add manually' : '직접 등록'), findsOneWidget);
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pumpAndSettle();
        final option = find.text(
          multiple
              ? (english ? 'Find pills in one photo' : '여러 알약 한 번에 찾기')
              : (english ? 'Find pills individually' : '알약 하나씩 찾기'),
        );
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(
          selected,
          multiple
              ? MedicationCaptureTask.multiplePills
              : MedicationCaptureTask.individualPills,
        );
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
