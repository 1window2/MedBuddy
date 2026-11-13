// 파일명: medication_candidate_dialog_test.dart
// 역할: 약 후보창의 확인·취소 콜백을 연속 호출해도 아래 화면이 보존되는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_candidate_dialog.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';

// 함수이름: main
// 함수역할:
// - 후보 선택 후 확인하거나 취소하는 두 종료 경로의 재진입 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 위젯 테스트를 프레임워크에서 실행한다.
void main() {
  for (final confirms in [false, true]) {
    // 함수이름: 후보창 종료 콜백 재진입 테스트
    // 함수역할:
    // - 같은 프레임의 종료 콜백을 두 번 호출해도 후보창만 닫히고 진입 버튼은 남아야 한다.
    // - 확인은 선택 약을, 취소는 null을 반환하며 화면 예외를 남기지 않아야 한다.
    // 매개변수:
    // - tester(WidgetTester): 화면 렌더링과 콜백 재호출을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 결과 값과 아래 화면의 생존 여부 검증 완료.
    testWidgets('후보창 연속 종료가 아래 화면을 닫지 않는다: $confirms', (tester) async {
      const drug = MedicationDetail(
        itemSeq: '123',
        itemName: '시험약',
        manufacturer: '시험 제약',
        efficacy: '',
        usageMethod: '',
        warning: '',
      );
      MedicationDetail? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('후보 열기'),
                onPressed: () async {
                  selected = await showDialog<MedicationDetail>(
                    context: context,
                    builder: (_) => const MedicationCandidateDialog(
                      originalName: '시험약',
                      candidates: [drug],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('후보 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('medication-candidate-0')));
      await tester.pump();
      final close = confirms
          ? tester
                .widget<FilledButton>(
                  find.byKey(const Key('confirm-medication-candidate')),
                )
                .onPressed!
          : tester
                .widget<TextButton>(find.widgetWithText(TextButton, '취소'))
                .onPressed!;
      close();
      close();
      await tester.pumpAndSettle();
      expect(selected, confirms ? same(drug) : isNull);
      expect(find.text('후보 열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
