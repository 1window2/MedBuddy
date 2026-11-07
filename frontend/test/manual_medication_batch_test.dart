import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_dose_rhythm.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

const failed = MedicationSaveResult(
  status: MedicationSaveStatus.failed,
  message: '',
);
const saved = MedicationSaveResult(
  status: MedicationSaveStatus.saved,
  message: '',
);
const duplicate = MedicationSaveResult(
  status: MedicationSaveStatus.duplicate,
  message: '',
);

Finder field(String suffix, [int index = 0]) =>
    find.byKey(Key('manual-medication-$suffix')).at(index);

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, Finder target, String value) async {
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester, {
  Future<MedicationSaveResult> Function(ManualMedicationEntry)? save,
  Future<void> Function()? savesFinished,
  String language = 'ko',
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ManualMedicationEntryUI(
        userSetting: UserSetting(language: language),
        onSaveRequested: save ?? (_) async => failed,
        onSavesFinished: savesFinished,
      ),
    ),
  );
}

void main() {
  testWidgets('약 이름과 복용량 제목 아래의 간격을 동일하게 유지한다', (tester) async {
    await mount(tester);
    final nameGap =
        tester.getTopLeft(field('name')).dy -
        tester.getBottomLeft(find.text('약 이름')).dy;
    final doseGap =
        tester.getTopLeft(field('dosage')).dy -
        tester.getBottomLeft(find.text('1회 복용량')).dy;
    expect(nameGap, doseGap);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('작은 화면 큰 글씨에서 모든 입력이 넘치지 않는다 $language', (tester) async {
      await mount(tester, width: 320, scale: 2, language: language);
      await tap(tester, field('dose-days-custom'));
      await tap(tester, field('add'));
      expect(
        find.text(language == 'ko' ? '약 2' : 'Medication 2').hitTestable(),
        findsOneWidget,
      );
      await tap(tester, field('as-needed', 1));
      expect(
        find.text(language == 'ko' ? '약 2' : 'Medication 2'),
        findsOneWidget,
      );
    });
  }

  for (final value in [
    '',
    '0',
    '91',
    '1.5',
    '-3',
    'abc',
    '999999999999999999999',
  ]) {
    testWidgets('잘못된 사용자 지정 주기는 저장하지 않는다: $value', (tester) async {
      var calls = 0;
      await mount(
        tester,
        save: (_) async {
          calls++;
          return failed;
        },
      );
      await enter(tester, field('name'), '주기 시험약');
      await tap(tester, field('dose-days-custom'));
      await enter(tester, field('interval'), value);
      await tap(tester, field('save'));
      expect(calls, 0);
      expect(find.text('1~90 사이의 일수를 입력해주세요.'), findsOneWidget);
    });
  }

  for (final days in [1, 3, 90]) {
    testWidgets('사용자 지정 $days일 주기를 기존 일정 규칙으로 저장한다', (tester) async {
      ManualMedicationEntry? submitted;
      await mount(
        tester,
        language: 'en',
        save: (entry) async {
          submitted = entry;
          return failed;
        },
      );
      await enter(tester, field('name'), 'Interval test');
      await tap(tester, field('dose-days-custom'));
      await enter(tester, field('interval'), '$days');
      await tap(tester, field('save'));
      expect(submitted!.doseDays, '$days일마다');
      final cycle = readDoseCycle(submitted!.toMedicationSchedule().intakeTime);
      final start = DateTime(2026, 1, 1);
      expect(cycle.cycleDays, days);
      expect(cycle.includes(start, start.add(Duration(days: days))), isTrue);
      if (days > 1) {
        expect(
          cycle.includes(start, start.add(const Duration(days: 1))),
          isFalse,
        );
      }
    });
  }

  testWidgets('기본 주기로 전환하면 숨겨진 기타 입력은 저장을 막지 않는다', (tester) async {
    ManualMedicationEntry? submitted;
    await mount(
      tester,
      save: (entry) async {
        submitted = entry;
        return failed;
      },
    );
    await enter(tester, field('name'), '기본 주기 시험약');
    await tap(tester, field('dose-days-custom'));
    await enter(tester, field('interval'), '0');
    await tap(tester, field('dose-days-주 1회'));
    await tap(tester, field('save'));
    expect(submitted!.doseDays, '주 1회');
  });

  testWidgets('필요시 약은 숨겨진 주기와 시간대를 일정으로 저장하지 않는다', (tester) async {
    ManualMedicationEntry? submitted;
    await mount(
      tester,
      save: (entry) async {
        submitted = entry;
        return failed;
      },
    );
    await enter(tester, field('name'), '필요시 시험약');
    await tap(tester, field('dose-days-custom'));
    await tap(tester, field('as-needed'));
    expect(find.textContaining('정해진 시간의 복용 알림과'), findsNothing);
    expect(find.textContaining('복약 안내에 적힌 시간대를'), findsNothing);
    await tap(tester, field('save'));
    expect(submitted!.dosingMode, 'as_needed');
    expect(submitted!.doseDays, '');
    expect(submitted!.toMedicationSchedule().scheduleSlotKeys, isEmpty);
  });

  testWidgets('모든 약을 검증한 뒤 저장하고 실패한 약만 재시도한다', (tester) async {
    final requests = <ManualMedicationEntry>[];
    await mount(
      tester,
      save: (entry) async {
        requests.add(entry);
        return entry.medicationName == '첫째 약' ? saved : failed;
      },
    );
    await enter(tester, field('name'), '첫째 약');
    await tap(tester, field('add'));
    await tap(tester, field('save'));
    expect(requests, isEmpty);
    await enter(tester, field('name', 1), '둘째 약');
    await enter(tester, field('dosage', 1), '0.5');
    await tap(tester, field('as-needed', 1));
    await tap(tester, field('save'));
    expect(requests.map((entry) => entry.medicationName), ['첫째 약', '둘째 약']);
    expect(find.text('저장 완료'), findsOneWidget);
    expect(requests[0].dosageAmount, '1');
    expect(requests[0].dosingMode, 'scheduled');
    expect(requests[1].dosageAmount, '0.5');
    expect(requests[1].dosingMode, 'as_needed');
    await tap(tester, field('save'));
    expect(requests.map((entry) => entry.medicationName), [
      '첫째 약',
      '둘째 약',
      '둘째 약',
    ]);
  });

  testWidgets('여러 약은 마지막에 한 번만 갱신하고 이미 추가된 약은 저장 개수에서 뺀다', (tester) async {
    var refreshes = 0;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 저장 후 화면을 닫아도 안내가 보이도록 아래 화면에서 직접 등록을 연다.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => ManualMedicationEntryUI(
                    userSetting: const UserSetting(),
                    onSaveRequested: (entry) async =>
                        entry.medicationName == '둘째 약' ? duplicate : saved,
                    onSavesFinished: () async => refreshes++,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await enter(tester, field('name'), '첫째 약');
    await tap(tester, field('add'));
    await enter(tester, field('name', 1), '둘째 약');
    await tap(tester, field('save'));
    expect(refreshes, 1);
    expect(
      find.text('약 1개의 복약 정보를 저장했습니다. 이미 추가된 약 1개는 다시 저장하지 않았습니다.'),
      findsOneWidget,
    );
  });

  testWidgets('중간 약이 실패해도 앞서 저장한 약을 위해 한 번 갱신한다', (tester) async {
    var refreshes = 0;
    await mount(
      tester,
      save: (entry) async => entry.medicationName == '첫째 약' ? saved : failed,
      savesFinished: () async => refreshes++,
    );
    await enter(tester, field('name'), '첫째 약');
    await tap(tester, field('add'));
    await enter(tester, field('name', 1), '둘째 약');
    await tap(tester, field('save'));
    expect(refreshes, 1);
    expect(find.text('저장 완료'), findsOneWidget);
    expect(find.text('첫째 약'), findsOneWidget);
    await tap(tester, field('save'));
    // 다시 실패하면 새로 저장한 약이 없으므로 갱신하지 않는다.
    expect(refreshes, 1);
  });

  testWidgets('앞쪽 약을 삭제해도 나머지 약의 입력과 주기가 유지된다', (tester) async {
    ManualMedicationEntry? submitted;
    await mount(
      tester,
      save: (entry) async {
        submitted = entry;
        return failed;
      },
    );
    await enter(tester, field('name'), '삭제할 약');
    await tap(tester, field('add'));
    await enter(tester, field('name', 1), '남길 약');
    await tap(tester, field('dose-days-custom', 1));
    await enter(tester, field('interval'), '4');
    await tap(tester, find.byTooltip('약 입력 삭제').first);
    expect(find.text('약 2'), findsNothing);
    expect(
      tester.widget<TextFormField>(field('name')).controller!.text,
      '남길 약',
    );
    await tap(tester, field('save'));
    expect(submitted!.doseDays, '4일마다');
    expect(submitted!.medicationName, '남길 약');
  });

  testWidgets('여러 약 저장 중 중복 클릭과 추가 삭제를 막는다', (tester) async {
    final pending = Completer<MedicationSaveResult>();
    var calls = 0;
    await mount(
      tester,
      save: (_) {
        calls++;
        return pending.future;
      },
    );
    await enter(tester, field('name'), '첫째 약');
    await tap(tester, field('add'));
    await enter(tester, field('name', 1), '둘째 약');
    await tester.tap(field('save'));
    await tester.pump();
    expect(tester.widget<FilledButton>(field('save')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(field('add')).onPressed, isNull);
    final remove = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '약 입력 삭제',
    );
    expect(tester.widget<IconButton>(remove.first).onPressed, isNull);
    expect(calls, 1);
    pending.complete(failed);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(field('save')).onPressed, isNotNull);
  });
}
