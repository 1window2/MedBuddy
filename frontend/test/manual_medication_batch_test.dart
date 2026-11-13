// 파일명: manual_medication_batch_test.dart
// 역할: 여러 약 직접 입력의 주기 검증, 부분 저장 재시도, 갱신 및 화면 접근성을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_dose_rhythm.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

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

// 함수이름: field
// 함수역할:
// - 공통 키를 가진 반복 입력 중 지정 위치의 항목을 선택한다.
// 매개변수:
// - suffix(String): manual-medication- 뒤에 붙는 입력 또는 버튼 식별자.
// - index(int): 같은 키를 가진 위젯의 0부터 시작하는 순서; 기본값은 첫 항목이다.
// 반환값:
// - Finder: 해당 순서의 항목을 찾는 검색자; 실제 존재 여부는 사용하는 테스트가 검증한다.
Finder field(String suffix, [int index = 0]) =>
    find.byKey(Key('manual-medication-$suffix')).at(index);

// 함수이름: tap
// 함수역할:
// - 대상을 스크롤로 노출한 뒤 애니메이션을 기다려 누르고 화면 변화를 완료한다.
// 매개변수:
// - tester(WidgetTester): 화면 조작 도구.
// - target(Finder): 화면 안으로 이동시켜 누를 위젯.
// 반환값:
// - Future<void>: 탭 뒤 화면 안정화 완료; 대상을 찾지 못하거나 안정화가 지연되면 실패한다.
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

// 함수이름: enter
// 함수역할:
// - 입력창을 노출하고 기존 내용을 주어진 문자열로 바꾼 뒤 화면 갱신을 기다린다.
// 매개변수:
// - tester(WidgetTester): 텍스트 입력 도구.
// - target(Finder): 편집할 입력창.
// - value(String): 새 입력값; 유효성 검증용 잘못된 값도 그대로 전달한다.
// 반환값:
// - Future<void>: 입력 후 화면 안정화 완료.
Future<void> enter(WidgetTester tester, Finder target, String value) async {
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

// Function Name: mount
// Description:
// - Mount the entry form with controlled save/refresh callbacks, viewport and text scale.
// - Register view resets so the physical surface does not leak into another test.
// Parameters:
// - tester (WidgetTester): Driver that mounts the form.
// - save (Future<MedicationSaveResult> Function(ManualMedicationEntry)?): Save stub; defaults to failure.
// - savesFinished (Future<void> Function()? ): Optional post-batch refresh stub, including delayed failures.
// - language (String): Display language, defaulting to Korean.
// - width (double): Logical viewport width; height is fixed at 900 and pixel ratio at 1.
// - scale (double): MediaQuery text scale, defaulting to 1.
// Returns:
// - Future<void>: Completion of the initial widget pump, without waiting for a save.
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

// 함수이름: main
// 함수역할:
// - 일괄 직접 등록의 입력 검증, 저장·갱신 경합과 좁은 화면 회귀 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 개별 화면 검증은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 부분 저장 후 갱신을 대기시키면 저장·추가 버튼이 잠기고, 갱신 완료 뒤 실패한 약만 재시도되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('일부 저장 후 갱신이 끝나기 전에는 재저장할 수 없다', (tester) async {
    final refresh = Completer<void>();
    var saves = 0;
    await mount(
      tester,
      save: (_) async => ++saves == 1 ? saved : failed,
      savesFinished: () => refresh.future,
    );
    await enter(tester, field('name'), '첫째 약');
    await tap(tester, field('add'));
    await enter(tester, field('name', 1), '둘째 약');
    await tester.tap(field('save'));
    await tester.pump();
    expect(saves, 2);
    expect(tester.widget<FilledButton>(field('save')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(field('add')).onPressed, isNull);
    refresh.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(field('save')).onPressed, isNotNull);
    await tap(tester, field('save'));
    expect(saves, 3);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 첫 목록 갱신 실패를 안내한 뒤 재시도하면 저장 요청은 한 번, 갱신은 두 번이며 이전 화면으로 돌아오는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('저장 후 갱신 실패는 저장한 약을 다시 보내지 않고 재시도한다', (tester) async {
    var saves = 0;
    var refreshes = 0;
    final navigator = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('등록 전 화면')),
      ),
    );
    unawaited(
      navigator.currentState!.push<bool>(
        MaterialPageRoute(
          builder: (_) => ManualMedicationEntryUI(
            userSetting: const UserSetting(),
            onSaveRequested: (_) async {
              saves++;
              return saved;
            },
            onSavesFinished: () async {
              if (++refreshes == 1) throw StateError('refresh failed');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enter(tester, field('name'), '이미 저장한 약');
    await tap(tester, field('save'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('목록을 갱신하지 못했습니다'), findsOneWidget);
    expect(tester.widget<FilledButton>(field('save')).onPressed, isNotNull);
    // 하단 안내가 사라진 뒤 실제로 누를 수 있는 저장 버튼을 재시도한다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, field('save'));
    expect(saves, 1);
    expect(refreshes, 2);
    expect(find.text('등록 전 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 저장 완료 후 화면을 제거한 상태에서 갱신 오류를 발생시켜 처리되지 않은 화면 예외가 없는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('화면 폐기 뒤 갱신 실패도 처리되지 않은 예외를 남기지 않는다', (tester) async {
    final refresh = Completer<void>();
    await mount(
      tester,
      save: (_) async => saved,
      savesFinished: () => refresh.future,
    );
    await enter(tester, field('name'), '저장할 약');
    await tester.tap(field('save'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    refresh.completeError(StateError('late refresh failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 약 이름과 1회 복용량 제목의 아래 경계에서 입력창까지 거리를 비교해 두 항목의 간격 일치를 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 폭 320·글씨 배율 2에서 사용자 지정 주기와 두 번째 약을 추가하고 필요시 모드로 바꿔도 약 제목에 접근할 수 있는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 빈 값·범위 밖 정수·소수·문자열 주기를 제출해 저장 호출 없이 1~90일 안내가 표시되는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 영어 화면의 사용자 지정 간격이 한국어 주기 계약으로 저장되고 일정 규칙이 주기일과 비주기일을 구분하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 잘못된 사용자 지정 간격을 남긴 채 주 1회로 전환해도 선택한 기본 주기로 제출되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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

  // Function Name: testWidgets callback
  // Description:
  // - Switch from a custom interval to as-needed dosing; verify the exclusion notice and a submitted entry with no cycle or scheduled slots.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
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
    // 필요시 복용은 정해진 알림에서 빠진다는 안내를 보여 주고, 숨겨진 시간대 안내는 없다.
    expect(find.textContaining('정해진 시간의 복용 알림과'), findsOneWidget);
    expect(find.textContaining('복약 안내에 적힌 시간대를'), findsNothing);
    await tap(tester, field('save'));
    expect(submitted!.dosingMode, 'as_needed');
    expect(submitted!.doseDays, '');
    expect(submitted!.toMedicationSchedule().scheduleSlotKeys, isEmpty);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 두 번째 약 이름이 비면 전송하지 않고, 보완 후 첫 약만 성공하면 다음 시도에서 두 번째 약만 다시 전송하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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

  // Function Name: testWidgets callback
  // Description:
  // - Check that a valid custom interval shows its preview, an invalid interval hides it, and as-needed dosing explains missed-dose exclusion.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
  testWidgets('사용자 지정 간격과 필요시 복용도 저장 전 안내를 보여 준다', (tester) async {
    await mount(tester);
    final notice = find.byKey(const Key('manual-medication-dose-days-notice'));
    await tap(tester, field('dose-days-custom'));
    expect(notice, findsNothing);
    await enter(tester, field('interval'), '3');
    expect(notice, findsOneWidget);
    expect(
      tester.widget<KeepWordsText>(notice).data,
      contains('3일마다'),
    );
    await enter(tester, field('interval'), '0');
    expect(notice, findsNothing);
    await tap(tester, field('as-needed'));
    expect(find.textContaining('미복약 알림에서 제외'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Save one new and one duplicate medicine; require one refresh and a notice that counts the duplicate separately from the new save.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
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

  // Function Name: testWidgets callback
  // Description:
  // - After one success and one failure, require a single refresh; retrying only the failed item must not refresh when nothing new was saved.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 앞 약을 삭제하여 인덱스가 바뀌어도 남은 약 이름과 사용자 지정 4일 주기가 제출되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 첫 저장 응답을 지연하면 저장·추가·삭제가 잠기고 요청은 한 번이며, 실패 응답 뒤 저장 버튼이 복구되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
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
