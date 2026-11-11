// 파일명: medication_regimen_ui_test.dart
// 역할: 직접 등록·복약 정보 수정·중단·교체·일정 검토의 입력 검증, 번역, 재시도와 날짜 경계를 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_regimen_editor_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_schedule_review_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/widgets/medication_entry_fields.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

// 함수이름: _medication
// 함수역할:
// - 수정·교체 화면의 공통 기준으로 아침 1회 복용 중인 30일 처방을 만든다.
// 매개변수:
// - 없음.
// 반환값:
// - MedicationDetail; ID 7, 버전 4이며 처방일은 실행 시점 이틀 전인 테스트 약.
MedicationDetail _medication() => MedicationDetail(
  id: 7,
  itemName: '테스트 약',
  efficacy: '',
  usageMethod: '',
  warning: '',
  prescriptionDate: DateTime.now().subtract(const Duration(days: 2)),
  totalDays: '30일',
  dosagePerTime: '1정',
  dailyFrequency: '1회',
  scheduleSlotKeys: ['morning'],
  regimenRevision: 4,
);

// 함수이름: _open
// 함수역할:
// - 400×860 화면에서 버튼을 통해 대상 화면을 새 경로로 열어 뒤로 가기까지 검증할 수 있게 하고, 종료 시 화면 설정을 복원한다.
// 매개변수:
// - tester (WidgetTester): 크기 설정과 화면 이동을 수행한다.
// - child (Widget): 새 경로에 표시할 입력·수정 화면.
// 반환값:
// - Future<void>; 경로 전환이 끝나면 완료한다.
Future<void> _open(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<Object?>(builder: (_) => child),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// 함수이름: _tap
// 함수역할:
// - 지정 키의 입력이 아직 생성되지 않았으면 목록을 스크롤하고, 화면 중앙에 노출해 누를 수 있는지 확인한 뒤 탭한다.
// 매개변수:
// - tester (WidgetTester): 목록 이동과 입력을 수행한다.
// - key (String): 탭할 위젯의 Key 값.
// 반환값:
// - Future<void>; 탭 후 화면이 안정되면 완료하며 대상이 없거나 눌리지 않으면 검증이 실패한다.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// 함수이름: _selectDay
// 함수역할:
// - 지정한 날짜 버튼을 열어 현재 달의 일자를 선택하고 확인한다.
// 매개변수:
// - tester (WidgetTester): 달력 입력을 수행한다.
// - key (String): 날짜 선택기를 여는 버튼 키.
// - day (int): 현재 표시된 달에서 선택할 날짜 숫자.
// 반환값:
// - Future<void>; 날짜 선택창이 닫히고 화면이 갱신되면 완료한다.
Future<void> _selectDay(WidgetTester tester, String key, int day) async {
  await _tap(tester, key);
  await tester.tap(find.text('$day'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할:
// - 직접 등록·처방 변경·일정 검토의 공통 입력, 수량·기간 검증, 요청 재시도와 한국 날짜 경계를 검사하는 테스트를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 테스트를 등록하며 직접 저장 요청을 보내지 않는다.
void main() {
  // 함수이름: 직접 등록과 처방 변경이 같은 입력 위젯을 사용한다
  // 함수역할:
  // - 직접 등록 화면에 이름·복용량·기간·주기·시간대의 공통 입력 컴포넌트가 각각 하나씩 배치되는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('직접 등록과 처방 변경이 같은 입력 위젯을 사용한다', (tester) async {
    await _open(
      tester,
      ManualMedicationEntryUI(
        userSetting: const UserSetting(),
        onSaveRequested: (_) async => const MedicationSaveResult(
          status: MedicationSaveStatus.failed,
          message: 'test',
        ),
      ),
    );
    for (final type in [
      MedicationEntryNameField,
      MedicationEntryDoseFields,
      MedicationEntryPeriodFields,
      MedicationEntryCycleChoices,
      MedicationEntrySlotChoices,
    ]) {
      expect(find.byType(type), findsOneWidget);
    }
  });

  for (final dosage in ['0.50 정', '1/2정', '2패치', '1정 (증상 시)', '5 mg']) {
    // 함수이름: 기존 복용량을 다른 항목 수정 중 손실하지 않는다: $dosage
    // 함수역할:
    // - 이름만 수정할 때 소수 표기·분수·패치·추가 지시·mg 복용량 원문을 보존하고, 분리 가능한 소수 정제 표현에만 단위 선택기를 표시하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    testWidgets('기존 복용량을 다른 항목 수정 중 손실하지 않는다: $dosage', (tester) async {
      MedicationRegimenChange? submitted;
      await _open(
        tester,
        MedicationRegimenEditorUI(
          medication: _medication().copyWith(dosagePerTime: dosage),
          action: MedicationRegimenAction.edit,
          onSubmit: (value) async {
            submitted = value;
            return const MedicationRegimenResult(medicationId: 8, revision: 5);
          },
        ),
      );
      final dose = tester.widget<TextFormField>(
        find.byKey(const Key('regimen-dosage')),
      );
      expect(dose.controller!.text, dosage == '0.50 정' ? '0.50' : dosage);
      expect(
        find.byKey(const Key('regimen-unit')),
        dosage == '0.50 정' ? findsOneWidget : findsNothing,
      );
      await tester.enterText(find.byKey(const Key('regimen-name')), '수정 이름');
      await _tap(tester, 'regimen-submit');
      await _tap(tester, 'regimen-confirm');
      expect(submitted!.changes['dosage_per_time'], dosage);
    });
  }

  // 함수이름: 지원하지 않는 단위가 있는 기존 복용량도 그대로 편집할 수 있다
  // 함수역할:
  // - 지원하지 않는 패치 단위는 자유 입력 상태로 유지하여 기존 2패치를 1패치로 수정하고 그대로 전송할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('지원하지 않는 단위가 있는 기존 복용량도 그대로 편집할 수 있다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(dosagePerTime: '2패치'),
        action: MedicationRegimenAction.edit,
        onSubmit: (value) async {
          submitted = value;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1패치');
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.changes['dosage_per_time'], '1패치');
  });

  for (final amount in ['0', '-1', '1..5', '10001', '']) {
    // 함수이름: 잘못된 수량은 확인창을 열지 않는다: $amount
    // 함수역할:
    // - 0·음수·잘못된 소수·상한 초과·빈 수량을 주입하면 확인창을 열거나 저장 콜백을 실행하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    testWidgets('잘못된 수량은 확인창을 열지 않는다: $amount', (tester) async {
      var calls = 0;
      await _open(
        tester,
        MedicationRegimenEditorUI(
          medication: _medication(),
          action: MedicationRegimenAction.edit,
          onSubmit: (_) async {
            calls++;
            return const MedicationRegimenResult();
          },
        ),
      );
      tester
              .widget<TextFormField>(find.byKey(const Key('regimen-dosage')))
              .controller!
              .text =
          amount;
      await _tap(tester, 'regimen-submit');
      expect(calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  // 함수이름: 영어 변경 확인창은 복용 주기를 영어로 보여준다
  // 함수역할:
  // - 영어 수정 확인창이 복용 주기와 정제 수량을 영어로 표시하고 저장용 한국어 횟수·단위 표기를 노출하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('영어 변경 확인창은 복용 주기를 영어로 보여준다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        isEnglish: true,
        onSubmit: (_) async =>
            const MedicationRegimenResult(medicationId: 8, revision: 5),
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '2');
    await _tap(tester, 'regimen-submit');
    final dialog = find.byKey(const Key('regimen-confirm'));
    expect(dialog, findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .join('\n');
    expect(texts, contains('a day'));
    expect(texts, contains('2 tablets'));
    expect(texts, isNot(contains('2정')));
    expect(RegExp(r'\d회').hasMatch(texts), isFalse, reason: texts);
  });

  for (final action in [MedicationRegimenAction.edit, MedicationRegimenAction.replace]) {
    // 함수이름: 영어 확인창은 복용량만 번역하고 원본으로 저장한다: ${action.name}
    // 함수역할:
    // - 영어 수정·교체 확인창은 수량 단위만 번역하고 약 이름은 유지하며, 확인 전에는 전송하지 않고 확인 후에는 원래 저장용 복용량을 보내는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    testWidgets('영어 확인창은 복용량만 번역하고 원본으로 저장한다: ${action.name}', (tester) async {
      MedicationRegimenChange? submitted;
      final replacing = action == MedicationRegimenAction.replace;
      await _open(
        tester,
        MedicationRegimenEditorUI(
          medication: _medication().copyWith(
            prescriptionDate: DateTime(2026, 10, 15),
            dosagePerTime: '0.50 정',
          ),
          clock: () => DateTime.utc(2026, 10, 17, 3),
          action: action,
          isEnglish: true,
          onSubmit: (value) async {
            submitted = value;
            return const MedicationRegimenResult(medicationId: 8, revision: 5);
          },
        ),
      );
      if (replacing) {
        await tester.enterText(find.byKey(const Key('regimen-dosage')), '2');
        await _tap(tester, 'regimen-as-needed');
      }
      await _tap(tester, 'regimen-submit');
      final texts = tester.widgetList<Text>(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)),
      ).map((text) => text.data ?? text.textSpan?.toPlainText() ?? '').join('\n');
      expect(texts, contains(replacing ? '2 tablets' : '0.50 tablet'));
      expect(texts, isNot(contains(replacing ? '2정' : '0.50 정')));
      expect(texts, contains('테스트 약'));
      expect(submitted, isNull);
      await _tap(tester, 'regimen-confirm');
      expect(submitted!.changes['dosage_per_time'], replacing ? '2정' : '0.50 정');
    });
  }

  // 함수이름: 교체는 수량과 단위 및 필요시 모드를 새 처방으로 전송한다
  // 함수역할:
  // - 처방 교체 확인 후 버전 4와 0.5캡슐·필요시 모드·빈 시간대·1일 기간을 전송하고, 기존 복용 기록 보존 안내를 확인 전에 표시하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('교체는 수량과 단위 및 필요시 모드를 새 처방으로 전송한다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.replace,
        onSubmit: (value) async {
          submitted = value;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    expect(find.byKey(const Key('manual-medication-photo')), findsNothing);
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '0.5');
    await _tap(tester, 'regimen-unit');
    await tester.tap(find.text('캡슐').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'regimen-as-needed');
    expect(find.byKey(const Key('regimen-slot-morning')), findsNothing);
    await _tap(tester, 'regimen-submit');
    expect(submitted, isNull);
    expect(find.textContaining('기존 복용 기록은 삭제하지 않습니다'), findsOneWidget);
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.action, MedicationRegimenAction.replace);
    expect(submitted!.expectedRevision, 4);
    expect(submitted!.changes['dosage_per_time'], '0.5캡슐');
    expect(submitted!.changes['dosing_mode'], 'as_needed');
    expect(submitted!.changes['schedule_slot_keys'], isEmpty);
    expect(submitted!.changes['total_days'], '1');
  });

  // 함수이름: 필요시에서 정기로 돌아오면 시간대를 반드시 선택한다
  // 함수역할:
  // - 필요시에서 정기 복용으로 되돌린 뒤 시간대를 고르지 않으면 주기·시간대 안내를 표시하고 확인·전송을 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('필요시에서 정기로 돌아오면 시간대를 반드시 선택한다', (tester) async {
    var calls = 0;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.replace,
        onSubmit: (_) async {
          calls++;
          return const MedicationRegimenResult();
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
    await _tap(tester, 'regimen-as-needed');
    await _tap(tester, 'regimen-scheduled');
    await _tap(tester, 'regimen-submit');
    expect(find.textContaining('처방에 맞는 복용 주기와 시간대'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, 0);
  });

  // 함수이름: 알 수 없는 주기는 보존하고 지원하는 선택을 하기 전에는 막는다
  // 함수역할:
  // - 해석할 수 없는 감량 지시를 선택값으로 보존하되 제출을 막고, 지원하는 격일 주기를 명시적으로 고른 뒤에만 확인창을 여는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('알 수 없는 주기는 보존하고 지원하는 선택을 하기 전에는 막는다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(dailyFrequency: '상태에 따라 감량'),
        action: MedicationRegimenAction.edit,
        onSubmit: (_) async => const MedicationRegimenResult(),
      ),
    );
    expect(find.byKey(const Key('regimen-cycle-상태에 따라 감량')), findsOneWidget);
    await _tap(tester, 'regimen-submit');
    expect(find.byType(AlertDialog), findsNothing);
    await _tap(tester, 'regimen-cycle-격일');
    await _tap(tester, 'regimen-submit');
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  // 함수이름: 미래 변경일은 원래 시작일을 유지하고 종료일로 총 기간을 계산한다
  // 함수역할:
  // - 변경일을 미래로 옮겨도 원래 처방 시작일을 고정하고, 종료일까지 양 끝을 포함한 총 기간과 3650일 달력 상한을 원래 시작일 기준으로 유지하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('미래 변경일은 원래 시작일을 유지하고 종료일로 총 기간을 계산한다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 10),
        ),
        action: MedicationRegimenAction.edit,
        clock: () => DateTime.utc(2026, 10, 17),
        onSubmit: (value) async {
          submitted = value;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('regimen-course-start')))
          .onPressed,
      isNull,
    );
    await _selectDay(tester, 'regimen-effective-date', 20);
    await _tap(tester, 'regimen-end-date');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.firstDate, DateTime(2026, 10, 20));
    expect(picker.lastDate, DateTime(2026, 10, 10 + 3649));
    Navigator.of(
      tester.element(find.byType(DatePickerDialog)),
    ).pop(DateTime(2026, 10, 25));
    await tester.pumpAndSettle();
    expect(find.text('총 16일 복용'), findsOneWidget);
    expect(find.text('2026-10-10'), findsOneWidget);
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.effectiveDate, DateTime(2026, 10, 20));
    expect(submitted!.changes['total_days'], '16');
    expect(submitted!.changes.containsKey('prescription_date'), isFalse);
  });

  // 함수이름: 종료일 뒤로 변경일을 옮기면 기간을 고치기 전 전송하지 않는다
  // 함수역할:
  // - 변경일이 기존 종료일을 넘으면 확인을 막고, 종료일을 고친 뒤에는 원래 시작일부터 계산한 13일 기간으로 확인할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('종료일 뒤로 변경일을 옮기면 기간을 고치기 전 전송하지 않는다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 10),
          totalDays: '10',
        ),
        action: MedicationRegimenAction.edit,
        clock: () => DateTime.utc(2026, 10, 17),
        onSubmit: (_) async => const MedicationRegimenResult(),
      ),
    );
    await _selectDay(tester, 'regimen-effective-date', 20);
    await _tap(tester, 'regimen-submit');
    expect(find.textContaining('복용 종료일보다 늦습니다'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await _selectDay(tester, 'regimen-end-date', 22);
    await _tap(tester, 'regimen-submit');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('총 13일'),
      ),
      findsOneWidget,
    );
  });

  // Function Name: 교체 시작일 이동 시 종료일을 보정하고 3650일 범위를 지킨다
  // Description:
  // - With a fixed clock and prescription date, moving replacement start to October 20 moves the end date with it and bounds the end-date picker to an inclusive 3650-day course.
  // Parameters:
  // - tester (WidgetTester): renders widgets, performs gestures, and inspects the resulting UI.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  testWidgets('교체 시작일 이동 시 종료일을 보정하고 3650일 범위를 지킨다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        // Pin the prescription to the injected clock so real-world dates cannot change the result.
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 15),
        ),
        action: MedicationRegimenAction.replace,
        clock: () => DateTime.utc(2026, 10, 17),
        onSubmit: (_) async => const MedicationRegimenResult(),
      ),
    );
    await _selectDay(tester, 'regimen-effective-date', 20);
    expect(find.text('2026-10-20'), findsNWidgets(2));
    expect(find.text('총 1일 복용'), findsOneWidget);
    await _tap(tester, 'regimen-end-date');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.firstDate, DateTime(2026, 10, 20));
    expect(picker.lastDate, DateTime(2026, 10, 20 + 3649));
  });

  for (final days in [0, 1, 3650, 3651]) {
    // Function Name: 선택 결과도 복용 기간의 양 끝을 포함해 검증한다: $days
    // Description:
    // - Inject picker results for 0, 1, 3650, and 3651 inclusive days: reject out-of-range results without submitting, but persist both valid endpoints exactly.
    // Parameters:
    // - tester (WidgetTester): renders widgets, performs gestures, and inspects the resulting UI.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
    testWidgets('선택 결과도 복용 기간의 양 끝을 포함해 검증한다: $days', (tester) async {
      MedicationRegimenChange? submitted;
      await _open(
        tester,
        MedicationRegimenEditorUI(
          // Pin the prescription to the injected clock so the start date cannot drift with real time.
          medication: _medication().copyWith(
            prescriptionDate: DateTime(2026, 10, 15),
          ),
          action: MedicationRegimenAction.replace,
          clock: () => DateTime.utc(2026, 10, 17),
          onSubmit: (value) async {
            submitted = value;
            return const MedicationRegimenResult(medicationId: 8, revision: 5);
          },
        ),
      );
      await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
      await _tap(tester, 'regimen-as-needed');
      await _tap(tester, 'regimen-end-date');
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 10, 17 + days - 1));
      await tester.pumpAndSettle();
      await _tap(tester, 'regimen-submit');
      if (days == 0 || days == 3651) {
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining('1~3650일'), findsOneWidget);
        expect(submitted, isNull);
      } else {
        await _tap(tester, 'regimen-confirm');
        expect(submitted!.changes['total_days'], '$days');
      }
    });
  }

  // 함수이름: 원래 날짜가 없는 약도 변경일 이동으로 총 기간의 기준을 바꾸지 않는다
  // 함수역할:
  // - 원래 처방일이 없는 약은 화면을 연 날짜를 기간 기준으로 고정하며, 변경일을 옮겨도 30일 기간을 유지하고 처방일을 새로 전송하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('원래 날짜가 없는 약도 변경일 이동으로 총 기간의 기준을 바꾸지 않는다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: const MedicationDetail(
          id: 7,
          itemName: '이전 약',
          efficacy: '',
          usageMethod: '',
          warning: '',
          totalDays: '30',
          dosagePerTime: '1정',
          dailyFrequency: '1회',
          scheduleSlotKeys: ['morning'],
        ),
        action: MedicationRegimenAction.edit,
        clock: () => DateTime.utc(2026, 10, 17),
        onSubmit: (value) async {
          submitted = value;
          return const MedicationRegimenResult(medicationId: 8, revision: 1);
        },
      ),
    );
    await _selectDay(tester, 'regimen-effective-date', 20);
    expect(find.text('2026-10-17'), findsOneWidget);
    expect(find.text('총 30일 복용'), findsOneWidget);
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.effectiveDate, DateTime(2026, 10, 20));
    expect(submitted!.changes['total_days'], '30');
    expect(submitted!.changes.containsKey('prescription_date'), isFalse);
  });

  // Function Name: 서버가 기록 충돌을 알리면 같은 양식에서 날짜를 고쳐 재확인한다
  // Description:
  // - A recorded-date conflict leaves replacement inputs editable; choosing a later date creates a new confirmed request while retaining the entered dose.
  // Parameters:
  // - tester (WidgetTester): renders widgets, performs gestures, and inspects the resulting UI.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  testWidgets('서버가 기록 충돌을 알리면 같은 양식에서 날짜를 고쳐 재확인한다', (tester) async {
    final requests = <MedicationRegimenChange>[];
    await _open(
      tester,
      MedicationRegimenEditorUI(
        // Pin the prescription to the injected clock so real-world dates cannot change the result.
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 15),
        ),
        action: MedicationRegimenAction.replace,
        clock: () => DateTime.utc(2026, 10, 17),
        onSubmit: (value) async {
          requests.add(value);
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.recordedDate,
          );
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
    await _tap(tester, 'regimen-as-needed');
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('regimen-unit')),
          )
          .onChanged,
      isNotNull,
    );
    await _selectDay(tester, 'regimen-effective-date', 18);
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isFalse);
    expect(requests[1].effectiveDate, DateTime(2026, 10, 18));
    expect(requests[1].changes['dosage_per_time'], '1정');
  });

  // 함수이름: 교체 재시도는 수량 단위 날짜 주기를 잠그고 같은 요청을 재사용한다
  // 함수역할:
  // - 교체 확인 취소는 전송하지 않고, 네트워크 실패 뒤에는 이름·수량·단위·날짜·주기를 잠근 채 동일 요청 객체로 재시도하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('교체 재시도는 수량 단위 날짜 주기를 잠그고 같은 요청을 재사용한다', (tester) async {
    final requests = <MedicationRegimenChange>[];
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.replace,
        onSubmit: (value) async {
          requests.add(value);
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.network,
          );
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
    await _tap(tester, 'regimen-slot-morning');
    await _tap(tester, 'regimen-submit');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    for (final key in ['regimen-name', 'regimen-dosage']) {
      expect(
        tester.widget<TextFormField>(find.byKey(Key(key))).enabled,
        isFalse,
      );
    }
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('regimen-unit')),
          )
          .onChanged,
      isNull,
    );
    for (final key in ['regimen-effective-date', 'regimen-end-date']) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('regimen-cycle-')))
          .onSelected,
      isNull,
    );
    await _tap(tester, 'regimen-submit');
    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isTrue);
  });

  // 함수이름: 작은 화면의 큰 영어 글씨에서도 기간과 확인창이 넘치지 않는다
  // 함수역할:
  // - 320×640 화면과 2배 영어 글자에서 교체 입력·확인창을 스크롤해 기록 보존 안내까지 볼 수 있고 레이아웃 예외가 없는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('작은 화면의 큰 영어 글씨에서도 기간과 확인창이 넘치지 않는다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.replace,
        isEnglish: true,
        onSubmit: (_) async => const MedicationRegimenResult(),
      ),
    );
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await _tap(tester, 'regimen-dosage');
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, 'regimen-as-needed');
    await _tap(tester, 'regimen-submit');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.ensureVisible(
      find.textContaining('Earlier records will not be deleted'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 직접 등록의 복용 유형 제목은 다른 항목과 같은 스타일이다
  // 함수역할:
  // - 직접 등록 화면의 복용 기간·유형·주기·시간대 제목이 모두 공통 폼 섹션 제목 스타일을 사용하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('직접 등록의 복용 유형 제목은 다른 항목과 같은 스타일이다', (tester) async {
    await _open(
      tester,
      ManualMedicationEntryUI(
        userSetting: const UserSetting(),
        onSaveRequested: (_) async => const MedicationSaveResult(
          status: MedicationSaveStatus.saved,
          message: 'ok',
        ),
      ),
    );
    await _tap(tester, 'manual-medication-scheduled');
    for (final title in ['복용 기간', '복용 유형', '복용 주기', '복용 시간대']) {
      expect(
        tester.widget<Text>(find.text(title)).style,
        MedBuddyTextStyles.formSectionTitle,
      );
    }
  });

  for (final english in [false, true]) {
    for (final action in MedicationRegimenAction.values) {
      // 함수이름: 약 관리 날짜 제목은 작업의 의미를 구분한다 $action english=$english
      // 함수역할:
      // - 한국어·영어의 수정·중단·교체 작업별 날짜 제목과 스타일이 의미에 맞고, 불필요한 적용일 문구 없이 달력을 열 수 있는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증이 끝나면 완료한다.
      testWidgets('약 관리 날짜 제목은 작업의 의미를 구분한다 $action english=$english', (
        tester,
      ) async {
        await _open(
          tester,
          MedicationRegimenEditorUI(
            medication: _medication(),
            action: action,
            isEnglish: english,
            onSubmit: (_) async => const MedicationRegimenResult(),
          ),
        );
        final label = switch (action) {
          MedicationRegimenAction.edit =>
            english ? 'Change start date' : '변경 시작일',
          MedicationRegimenAction.stop => english ? 'Stop date' : '복용 중단일',
          MedicationRegimenAction.replace =>
            english ? 'Medication start date' : '복용 시작일',
        };
        await tester.ensureVisible(find.text(label));
        expect(
          tester
              .widget<Text>(
                find.text(
                  action == MedicationRegimenAction.replace
                      ? english
                            ? 'Medication period'
                            : '복용 기간'
                      : label,
                ),
              )
              .style,
          MedBuddyTextStyles.formSectionTitle,
        );
        expect(find.textContaining('적용일'), findsNothing);
        expect(
          find.textContaining(
            english ? 'Follow your prescription' : '처방·복약지도에 따라 변경해 주세요',
          ),
          findsNothing,
        );
        await _tap(tester, 'regimen-effective-date');
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      // 함수이름: 약 관리 공통 헤더와 큰 글씨 레이아웃 $action english=$english
      // 함수역할:
      // - 각 작업의 한국어·영어 화면이 부제 있는 공통 헤더를 사용하고 320×640·2배 글자에서 깨지지 않으며, 필요시 전환 시 시간대를 숨기는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증이 끝나면 완료한다.
      testWidgets('약 관리 공통 헤더와 큰 글씨 레이아웃 $action english=$english', (
        tester,
      ) async {
        await _open(
          tester,
          MedicationRegimenEditorUI(
            medication: _medication(),
            action: action,
            isEnglish: english,
            onSubmit: (_) async => const MedicationRegimenResult(),
          ),
        );
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        final header = tester.widget<MedBuddyPageHeader>(
          find.byType(MedBuddyPageHeader),
        );
        expect(header.subtitle, isNotEmpty);
        expect(find.byType(AppBar), findsNothing);
        expect(tester.takeException(), isNull);
        if (action != MedicationRegimenAction.stop) {
          await _tap(tester, 'regimen-as-needed');
          expect(find.byKey(const Key('regimen-slot-morning')), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final action in [
    MedicationRegimenAction.edit,
    MedicationRegimenAction.replace,
  ]) {
    // 함수이름: 약 이름은 입력칸에 한 번만 표시하고 제목과 입력 간격을 통일한다 $action
    // 함수역할:
    // - 수정·교체 화면에서 약 이름을 한 번만 표시하고 이름·복용량 제목 아래 10px 간격 및 공통 입력 컴포넌트를 유지하며 불필요한 글자 수 표시를 숨기는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
    testWidgets('약 이름은 입력칸에 한 번만 표시하고 제목과 입력 간격을 통일한다 $action', (tester) async {
      await _open(
        tester,
        MedicationRegimenEditorUI(
          medication: _medication(),
          action: action,
          onSubmit: (_) async => const MedicationRegimenResult(),
        ),
      );
      final nameField = find.byKey(const Key('regimen-name'));
      expect(tester.widget<TextFormField>(nameField).controller!.text, '테스트 약');
      expect(find.text('테스트 약'), findsOneWidget);
      final pairs = {'약 이름': 'regimen-name', '1회 복용량': 'regimen-dosage'};
      for (final entry in pairs.entries) {
        await _tap(tester, entry.value);
        final title = find.byWidgetPredicate(
          (widget) =>
              widget is KeepWordsText &&
              widget.data == entry.key &&
              widget.style == MedBuddyTextStyles.formSectionTitle,
        );
        expect(
          tester.widget<KeepWordsText>(title).style,
          MedBuddyTextStyles.formSectionTitle,
        );
        expect(
          tester.getTopLeft(find.byKey(Key(entry.value))).dy -
              tester.getBottomLeft(title).dy,
          10,
        );
      }
      expect(find.byType(MedicationEntryNameField), findsOneWidget);
      expect(find.byType(MedicationEntryDoseFields), findsOneWidget);
      expect(find.byType(MedicationEntryPeriodFields), findsOneWidget);
      expect(find.byType(MedicationEntryCycleChoices), findsOneWidget);
      expect(find.byType(MedicationEntrySlotChoices), findsOneWidget);
      expect(find.textContaining('/200'), findsNothing);
      expect(find.textContaining('/120'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 해외 시간대에서도 적용일과 달력 범위는 한국 날짜를 사용한다
  // 함수역할:
  // - 해외 오프셋 시각을 주입해도 중단일·달력의 현재일과 선택 범위·전송 문자열이 한국 날짜인 10월 17일을 기준으로 일치하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('해외 시간대에서도 적용일과 달력 범위는 한국 날짜를 사용한다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 10),
        ),
        action: MedicationRegimenAction.stop,
        clock: () => DateTime.parse('2026-10-16T08:30:00-07:00'),
        onSubmit: (change) async {
          submitted = change;
          return const MedicationRegimenResult(medicationId: 7, revision: 5);
        },
      ),
    );
    expect(find.text('2026-10-17'), findsOneWidget);
    await _tap(tester, 'regimen-effective-date');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2026, 10, 17));
    expect(picker.firstDate, DateTime(2026, 10, 17));
    expect(picker.currentDate, DateTime(2026, 10, 17));
    expect(picker.lastDate, DateTime(2027, 10, 17));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.toJson('')['effective_date'], '2026-10-17');
  });

  // 함수이름: 입력 중 한국 자정이 지나면 이전 날짜를 제출하지 않는다
  // 함수역할:
  // - 입력 중 한국 자정이 지나면 이전 날짜로 확인·전송하지 않고 날짜 변경 안내를 표시하며, 달력 최소일을 새 한국 날짜로 갱신하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('입력 중 한국 자정이 지나면 이전 날짜를 제출하지 않는다', (tester) async {
    var now = DateTime.utc(2026, 10, 16, 14, 59);
    var calls = 0;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 10),
        ),
        action: MedicationRegimenAction.stop,
        clock: () => now,
        onSubmit: (_) async {
          calls++;
          return const MedicationRegimenResult();
        },
      ),
    );
    now = DateTime.utc(2026, 10, 16, 15, 1);
    await _tap(tester, 'regimen-submit');
    expect(calls, 0);
    expect(find.byKey(const Key('regimen-confirm')), findsNothing);
    expect(find.textContaining('한국 날짜가 바뀌었습니다'), findsOneWidget);
    await _tap(tester, 'regimen-effective-date');
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2026, 10, 17));
    expect(picker.firstDate, DateTime(2026, 10, 17));
  });

  // 함수이름: 중단은 확인 전 전송하지 않고 진행 중 중복 제출을 막는다
  // 함수역할:
  // - 중단은 기록 보존 확인 이후에만 빈 변경 내용과 현재 버전으로 한 번 전송하고, 응답 대기 중 재제출을 막은 뒤 성공 시 이전 화면으로 돌아가는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('중단은 확인 전 전송하지 않고 진행 중 중복 제출을 막는다', (tester) async {
    final response = Completer<MedicationRegimenResult>();
    final requests = <MedicationRegimenChange>[];
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.stop,
        onSubmit: (change) {
          requests.add(change);
          return response.future;
        },
      ),
    );
    await _tap(tester, 'regimen-submit');
    expect(requests, isEmpty);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(
          '기존 복용 기록은 삭제하지 않습니다. 처방·복약지도에 따른 변경이 맞나요?',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('regimen-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, hasLength(1));
    expect(requests.single.action, MedicationRegimenAction.stop);
    expect(requests.single.changes, isEmpty);
    expect(requests.single.expectedRevision, 4);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('regimen-submit')))
          .onPressed,
      isNull,
    );
    response.complete(
      const MedicationRegimenResult(medicationId: 7, revision: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  // 함수이름: 수정은 원래 처방 시작일을 새 날짜처럼 보내지 않는다
  // 함수역할:
  // - 기존 처방 수정 시 0.5정 복용량은 전송하되 원래 처방 시작일을 새로운 prescription_date로 보내지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('수정은 원래 처방 시작일을 새 날짜처럼 보내지 않는다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        onSubmit: (change) async {
          submitted = change;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '0.5');
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.changes['dosage_per_time'], '0.5정');
    expect(submitted!.changes.containsKey('prescription_date'), isFalse);
  });

  // 함수이름: 새 처방은 빈 필수값을 그대로 제출하지 않는다
  // 함수역할:
  // - 새 처방의 필수값을 채우지 않으면 오류를 표시하고 확인창과 저장 콜백 실행을 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('새 처방은 빈 필수값을 그대로 제출하지 않는다', (tester) async {
    var calls = 0;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.replace,
        onSubmit: (_) async {
          calls++;
          return const MedicationRegimenResult();
        },
      ),
    );
    await _tap(tester, 'regimen-submit');
    expect(calls, 0);
    expect(find.byKey(const Key('regimen-confirm')), findsNothing);
    expect(find.text('필수 항목입니다.'), findsWidgets);
  });

  // 함수이름: 처방 교체의 복용 시작일을 새 처방 날짜로 전송한다
  // 함수역할:
  // - 교체 시작일을 10월 18일, 종료일을 24일로 고르면 확인 후 새 처방일·적용일·7일 기간·새 이름·복용량·아침 시간대와 기존 버전을 함께 전송하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('처방 교체의 복용 시작일을 새 처방 날짜로 전송한다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication().copyWith(
          prescriptionDate: DateTime(2026, 10, 10),
        ),
        action: MedicationRegimenAction.replace,
        clock: () => DateTime.utc(2026, 10, 17, 0),
        onSubmit: (change) async {
          submitted = change;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-name')), '새 테스트 약');
    await tester.enterText(find.byKey(const Key('regimen-dosage')), '1');
    await _tap(tester, 'regimen-slot-morning');
    await _tap(tester, 'regimen-effective-date');
    await tester.tap(find.text('18'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _tap(tester, 'regimen-end-date');
    await tester.tap(find.text('24'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('총 7일 복용'), findsOneWidget);
    await _tap(tester, 'regimen-submit');
    expect(find.textContaining('복용 시작일: 2026-10-18'), findsOneWidget);
    expect(submitted, isNull);
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.effectiveDate, DateTime(2026, 10, 18));
    expect(submitted!.changes['prescription_date'], '2026-10-18');
    expect(submitted!.changes['item_name'], '새 테스트 약');
    expect(submitted!.changes['total_days'], '7');
    expect(submitted!.action, MedicationRegimenAction.replace);
    expect(submitted!.expectedRevision, 4);
    expect(submitted!.changes['dosage_per_time'], '1정');
    expect(submitted!.changes['schedule_slot_keys'], ['morning']);
  });

  // 함수이름: 하단까지 스크롤해도 위쪽 빈 약 이름을 검사한다
  // 함수역할:
  // - 상단 약 이름을 비운 뒤 하단까지 이동해 제출해도 필수값 검증이 누락되지 않고 확인과 저장을 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('하단까지 스크롤해도 위쪽 빈 약 이름을 검사한다', (tester) async {
    var calls = 0;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        onSubmit: (_) async {
          calls++;
          return const MedicationRegimenResult();
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('regimen-name')), '');
    await _tap(tester, 'regimen-cycle-');
    await _tap(tester, 'regimen-submit');
    expect(calls, 0);
    expect(find.byKey(const Key('regimen-confirm')), findsNothing);
    expect(find.text('필수 항목입니다.'), findsOneWidget);
  });

  // 함수이름: 실패 후 입력을 유지하고 같은 요청 ID로 재시도한다
  // 함수역할:
  // - 수정 요청의 네트워크 실패 뒤 입력을 잠그고, 별도 재확인 없이 동일 요청 객체를 다시 보내는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('실패 후 입력을 유지하고 같은 요청 ID로 재시도한다', (tester) async {
    final requests = <MedicationRegimenChange>[];
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        onSubmit: (change) async {
          requests.add(change);
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.network,
          );
        },
      ),
    );
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(find.textContaining('같은 내용으로 다시 시도해 주세요'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('regimen-name')))
          .enabled,
      isFalse,
    );
    await _tap(tester, 'regimen-submit');
    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isTrue);
    expect(find.byKey(const Key('regimen-confirm')), findsNothing);
  });

  // 함수이름: 오래된 버전의 변경은 입력을 남기고 덮어쓰기 재시도를 막는다
  // 함수역할:
  // - 다른 기기의 버전 변경으로 충돌하면 입력 이름을 보존하면서 오류를 알리고, 오래된 내용으로 덮어쓰는 재제출을 비활성화하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('오래된 버전의 변경은 입력을 남기고 덮어쓰기 재시도를 막는다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        onSubmit: (_) async => const MedicationRegimenResult(
          failure: MedicationRegimenFailure.conflict,
        ),
      ),
    );
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(find.textContaining('다른 기기에서 약 정보가 변경됐습니다'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('regimen-name')))
          .controller!
          .text,
      '테스트 약',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('regimen-submit')))
          .onPressed,
      isNull,
    );
  });

  // 함수이름: 적용일에 기록이 있으면 날짜를 다시 고를 수 있다
  // 함수역할:
  // - 중단일에 복용 기록이 있다는 서버 오류는 더 늦은 날짜를 안내하고 날짜 선택 버튼을 다시 사용할 수 있게 하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('적용일에 기록이 있으면 날짜를 다시 고를 수 있다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.stop,
        onSubmit: (_) async => const MedicationRegimenResult(
          failure: MedicationRegimenFailure.recordedDate,
        ),
      ),
    );
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(find.textContaining('더 나중의 날짜'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('regimen-effective-date')));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('regimen-effective-date')),
          )
          .onPressed,
      isNotNull,
    );
  });

  // 함수이름: 약 정보 수정에서 필요시로 바꾸면 자동 시간대가 빠진다
  // 함수역할:
  // - 기존 약을 필요시 복용으로 수정하면 시간대 입력을 숨기고 as_needed와 빈 시간대를 전송하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('약 정보 수정에서 필요시로 바꾸면 자동 시간대가 빠진다', (tester) async {
    MedicationRegimenChange? submitted;
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
        action: MedicationRegimenAction.edit,
        onSubmit: (change) async {
          submitted = change;
          return const MedicationRegimenResult(medicationId: 8, revision: 5);
        },
      ),
    );
    await _tap(tester, 'regimen-as-needed');
    expect(find.byKey(const Key('regimen-slot-morning')), findsNothing);
    await _tap(tester, 'regimen-submit');
    await _tap(tester, 'regimen-confirm');
    expect(submitted!.changes['dosing_mode'], 'as_needed');
    expect(submitted!.changes['schedule_slot_keys'], isEmpty);
  });

  // 함수이름: 직접 등록에서도 필요시 복용은 시간대 없이 저장한다
  // 함수역할:
  // - 직접 등록에서 필요시 복용을 선택하면 시간대 없이 저장되고 일정 변환 결과도 자동 시간대를 만들지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('직접 등록에서도 필요시 복용은 시간대 없이 저장한다', (tester) async {
    ManualMedicationEntry? entry;
    await _open(
      tester,
      ManualMedicationEntryUI(
        userSetting: const UserSetting(),
        onSaveRequested: (value) async {
          entry = value;
          return const MedicationSaveResult(
            status: MedicationSaveStatus.saved,
            message: 'ok',
            savedMedicationId: 8,
          );
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '필요시 테스트 약',
    );
    await _tap(tester, 'manual-medication-as-needed');
    expect(
      find.byKey(const Key('manual-medication-slot-morning')),
      findsNothing,
    );
    await _tap(tester, 'manual-medication-save');
    expect(entry, isNotNull);
    expect(entry!.toMedicationSchedule().slotKeys, isEmpty);
    expect(entry!.dosingMode, 'as_needed');
  });

  // 함수이름: 검토 화면은 필요시 지시를 매일로 정규화하지 않는다
  // 함수역할:
  // - PRN 지시가 있는 일정을 검토·확인해도 필요시 모드를 유지하고 정기 시간대를 자동으로 추가하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('검토 화면은 필요시 지시를 매일로 정규화하지 않는다', (tester) async {
    List<MedicationSchedule>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () async {
                result = await showMedicationScheduleReview(
                  context: context,
                  userSetting: const UserSetting(),
                  initialSchedules: [
                    MedicationSchedule(
                      medicationName: 'Test',
                      dosage: '1정',
                      intakeTime: 'PRN',
                      medicationTime: 7,
                      prescriptionDate: DateTime.now(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('필요시 복용'), findsOneWidget);
    await _tap(tester, 'schedule-review-confirm');
    expect(result!.single.isAsNeeded, isTrue);
    expect(result!.single.slotKeys, isEmpty);
  });

  // 함수이름: 알 수 없는 복용 지시를 매일로 바꿔서 확인 완료하지 않는다
  // 함수역할:
  // - 해석하지 못한 감량 지시는 검토 확인을 눌러도 결과를 반환하지 않고 검토 화면에 남겨 임의의 매일 일정 저장을 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
  testWidgets('알 수 없는 복용 지시를 매일로 바꿔서 확인 완료하지 않는다', (tester) async {
    List<MedicationSchedule>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () async {
                result = await showMedicationScheduleReview(
                  context: context,
                  userSetting: const UserSetting(),
                  initialSchedules: [
                    MedicationSchedule(
                      medicationName: 'Test',
                      dosage: '1정',
                      intakeTime: '상태에 따라 감량',
                      medicationTime: 7,
                      prescriptionDate: DateTime.now(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _tap(tester, 'schedule-review-confirm');
    expect(result, isNull);
    expect(find.byKey(const Key('schedule-review-confirm')), findsOneWidget);
  });
}
