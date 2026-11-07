// 파일명: medication_photo_source_sheet_test.dart
// 역할: 사진 출처 선택창의 연속 선택·취소 후 오래된 콜백이 입력 화면을 닫지 않는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/medication_photo_source_sheet.dart';

// 함수이름: main
// 함수역할:
// - 사진 출처를 먼저 선택하거나 취소하는 두 경로의 재진입 검증을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록한 사례는 테스트 프레임워크에서 실행한다.
void main() {
  for (final cancelFirst in [false, true]) {
    // 함수이름: testWidgets callback
    // 함수역할:
    // - 카메라 선택 콜백을 보관한 뒤 선택 또는 뒤로가기를 수행하고 다시 호출해도 입력 화면이 남고 결과는 한 번만 반환되는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets(
      'source double tap preserves entry route (cancel=$cancelFirst)',
      (tester) async {
        final selections = <ImageSource?>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    child: const Text('open entry'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            child: const Text('select photo'),
                            onPressed: () async {
                              selections.add(
                                await showMedicationPhotoSourceOptions(
                                  context: context,
                                  language: 'en',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('open entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('select photo'));
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('Take Photo'),
          matching: find.byType(InkWell),
        );
        final select = tester.widget<InkWell>(row).onTap!;
        if (cancelFirst) {
          await tester.binding.handlePopRoute();
          await tester.pump();
        } else {
          select();
        }
        select();
        await tester.pumpAndSettle();
        expect(find.text('select photo'), findsOneWidget);
        expect(selections, [cancelFirst ? null : ImageSource.camera]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
