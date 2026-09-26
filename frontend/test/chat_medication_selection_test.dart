// 파일명: chat_medication_selection_test.dart
// 역할: 약/시간대별 전체·일부 선택, 선택 복원, 취소와 큰 글씨 배치를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

const _medications = [
  MedicationSchedule(
    medicationID: '11',
    medicationName: '아침저녁약',
    scheduleSlotKeys: ['morning', 'evening'],
    slotStatuses: {'morning': true},
  ),
  MedicationSchedule(
    medicationID: '22',
    medicationName: '점심약',
    scheduleSlotKeys: ['lunch'],
  ),
  MedicationSchedule(
    medicationID: '11',
    medicationName: '아침저녁약',
    scheduleSlotKeys: ['bedtime'],
  ),
];
const _allKey = Key('schedule-medication-select-all');
const _countKey = Key('schedule-medication-selection-count');
const _doneKey = Key('scheduleMedicationSelectionConfirm');

// 함수이름: _all
// 함수역할: 전체 선택 항목의 체크 상태와 활성 여부를 읽을 수 있도록 실제 위젯을 찾는다.
// 매개변수: tester: 화면 검증 도구. 반환값: 전체 선택 체크 항목.
CheckboxListTile _all(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(find.byKey(_allKey));

// 함수역할: 실제 첨부 선택 화면에 언어·큰 글씨 설정을 적용한다.
// 함수이름: _selectionApp
// 매개변수: schedules: 표시할 일정, selected: 초기 약·시간대 선택, language: 언어, scale: 글자 배율. 반환값: 선택 화면을 감싼 테스트 앱.
Widget _selectionApp({
  List<MedicationSchedule> schedules = _medications,
  Map<String, Set<String>> selected = const {},
  String language = 'ko',
  double scale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: CheckScheduleUI.selection(
    schedules: schedules,
    language: language,
    selectedMedicationSlots: selected,
  ),
);

// 함수이름: main
// 함수역할: 약·시간대별 선택, 취소와 접근성 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 전체·일부 선택 전환 테스트
  // 함수역할: 같은 약의 시간대별 선택을 독립적으로 계산하고 선택 조작이 기존 복용 상태를 바꾸지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  testWidgets('전체 선택은 약/시간대별로 계산하고 다른 시간대의 선택을 유지한다', (tester) async {
    await tester.pumpWidget(_selectionApp());
    await tester.pumpAndSettle();
    expect(_all(tester).value, isFalse);
    expect(tester.widget<FilledButton>(find.byKey(_doneKey)).onPressed, isNull);
    await tester.tap(find.byKey(_allKey));
    await tester.pumpAndSettle();
    expect(_all(tester).value, isTrue);
    expect(tester.widget<Text>(find.byKey(_countKey)).data, '4개 선택');
    expect(
      tester.widget<FilledButton>(find.byKey(_doneKey)).onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const Key('scheduleMedicationSelectionOption_morning_11')),
    );
    await tester.pumpAndSettle();
    expect(_all(tester).value, isNull);
    expect(tester.widget<Text>(find.byKey(_countKey)).data, '3개 선택');
    await tester.tap(find.byKey(_allKey));
    await tester.pumpAndSettle();
    expect(_all(tester).value, isTrue);
    await tester.tap(find.byKey(_allKey));
    await tester.pumpAndSettle();
    expect(_all(tester).value, isFalse);
    expect(tester.widget<Text>(find.byKey(_countKey)).data, '0개 선택');
    expect(tester.widget<FilledButton>(find.byKey(_doneKey)).onPressed, isNull);
    expect(_medications.first.isSlotCompleted('morning'), isTrue);
    expect(_medications.first.isSlotCompleted('evening'), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final confirm in [true, false]) {
    // 함수이름: 선택 결과 반환·취소 테스트
    // 함수역할: 완료하면 약별 시간대를 합친 복사본을 반환하고 뒤로가면 선택을 버리는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
    testWidgets('전체 선택 반환과 뒤로가기 취소: confirm=$confirm', (tester) async {
      List<MedicationSchedule>? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<List<MedicationSchedule>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CheckScheduleUI.selection(
                        schedules: _medications,
                        language: 'ko',
                        selectedMedicationSlots: {
                          '11': {'morning'},
                        },
                      ),
                    ),
                  );
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_all(tester).value, isNull);
      await tester.tap(find.byKey(_allKey));
      await tester.pumpAndSettle();
      if (confirm) {
        await tester.tap(find.byKey(_doneKey));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      if (confirm) {
        expect(result!.map((schedule) => schedule.medicationID), ['11', '22']);
        expect(result!.first.scheduleSlotKeys, [
          'morning',
          'evening',
          'bedtime',
        ]);
        expect(result!.last.scheduleSlotKeys, ['lunch']);
        expect(_medications.first.scheduleSlotKeys, ['morning', 'evening']);
      } else {
        expect(result, isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 선택 목록 정합성 테스트
  // 함수역할: 초기 선택의 무효 식별자를 걸러내고 일정이 바뀌면 삭제된 약의 선택도 제거하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  testWidgets('초기 선택에서 없는 ID를 제외하고 목록 변경 시 제거된 약을 선택에서 뺀다', (tester) async {
    await tester.pumpWidget(
      _selectionApp(
        selected: {
          '11': {'morning', 'evening', 'bedtime'},
          '22': {'lunch'},
          'missing': {'morning'},
          '': {'morning'},
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(_all(tester).value, isTrue);
    expect(tester.widget<Text>(find.byKey(_countKey)).data, '4개 선택');
    await tester.pumpWidget(_selectionApp(schedules: [_medications.first]));
    await tester.pumpAndSettle();
    expect(_all(tester).value, isTrue);
    expect(tester.widget<Text>(find.byKey(_countKey)).data, '2개 선택');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 선택 불가 상태 테스트
  // 함수역할: 일정이 없거나 약 식별자가 비어 있으면 전체 선택과 완료 버튼이 비활성화되는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  testWidgets('빈 목록과 빈 ID만 있는 목록에서는 전체 선택과 완료가 비활성화된다', (tester) async {
    for (final schedules in <List<MedicationSchedule>>[
      [],
      [const MedicationSchedule(medicationName: '식별자 없는 약', medicationID: ' ')],
    ]) {
      await tester.pumpWidget(
        _selectionApp(
          schedules: schedules,
          selected: {
            '': {'morning'},
            ' ': {'morning'},
            'missing': {'morning'},
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(_all(tester).value, isFalse);
      expect(_all(tester).onChanged, isNull);
      expect(tester.widget<Text>(find.byKey(_countKey)).data, '0개 선택');
      expect(
        tester.widget<FilledButton>(find.byKey(_doneKey)).onPressed,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 1.6, 2.0]) {
      // 함수이름: 선택 화면 접근성 테스트
      // 함수역할: 한국어·영어와 큰 글씨에서 굵기·색상·선택 수를 유지하고 스크롤로 선택 도구에 접근할 수 있는지 검증한다.
      // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
      testWidgets('다른 선택 화면의 굵은 글꼴과 접근 가능한 선택 도구: $language $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _selectionApp(language: language, scale: scale),
        );
        await tester.pumpAndSettle();
        if (scale > 1.6) {
          await tester.scrollUntilVisible(find.byKey(_allKey), 120);
          await tester.pumpAndSettle();
        }
        final title = tester.widget<Text>(
          find.text(language == 'en' ? 'Select all' : '전체 선택'),
        );
        expect(title.style!.fontWeight, FontWeight.w700);
        expect(title.style!.fontSize, 16);
        expect(title.style!.letterSpacing, 0);
        expect(_all(tester).activeColor, MedBuddyColors.primary);
        await tester.ensureVisible(find.byKey(_allKey));
        await tester.pumpAndSettle();
        final position = tester.getTopLeft(find.byKey(_allKey));
        await tester.tap(find.byKey(_allKey));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(_countKey)).data,
          language == 'en' ? '4 selected' : '4개 선택',
        );
        await tester.drag(find.byType(ListView), const Offset(0, -240));
        await tester.pumpAndSettle();
        if (scale <= 1.6) {
          expect(tester.getTopLeft(find.byKey(_allKey)), position);
        } else {
          await tester.scrollUntilVisible(find.byKey(_allKey), -120);
          await tester.pumpAndSettle();
        }
        expect(find.byKey(_allKey).hitTestable(), findsOneWidget);
        expect(find.byKey(_doneKey).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
