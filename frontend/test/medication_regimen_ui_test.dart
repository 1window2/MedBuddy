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

Future<void> _selectDay(WidgetTester tester, String key, int day) async {
  await _tap(tester, key);
  await tester.tap(find.text('$day'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
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

  // 영어 화면의 확인창은 저장용 한국어 주기 문구("격일, 1일 2회")를 그대로 보여주지 않는다.
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
        .map((text) => text.data ?? '')
        .join('\n');
    expect(texts, contains('a day'));
    expect(RegExp(r'\d회').hasMatch(texts), isFalse, reason: texts);
  });

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

  testWidgets('교체 시작일 이동 시 종료일을 보정하고 3650일 범위를 지킨다', (tester) async {
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
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
    testWidgets('선택 결과도 복용 기간의 양 끝을 포함해 검증한다: $days', (tester) async {
      MedicationRegimenChange? submitted;
      await _open(
        tester,
        MedicationRegimenEditorUI(
          medication: _medication(),
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

  testWidgets('서버가 기록 충돌을 알리면 같은 양식에서 날짜를 고쳐 재확인한다', (tester) async {
    final requests = <MedicationRegimenChange>[];
    await _open(
      tester,
      MedicationRegimenEditorUI(
        medication: _medication(),
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
              widget is Text &&
              widget.data == entry.key &&
              widget.style == MedBuddyTextStyles.formSectionTitle,
        );
        expect(
          tester.widget<Text>(title).style,
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
