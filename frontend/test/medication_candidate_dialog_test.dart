import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_candidate_dialog.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';

void main() {
  for (final confirms in [false, true]) {
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
