// 파일명: medication_search_ui_boundary_test.dart
// 역할: 약 검색 결과 선택, 오류 안내와 직접 등록 시 카탈로그 정보 연결을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/medication_search_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

const _drug = MedicationDetail(
  itemSeq: '123',
  itemName: '시험약 10mg',
  manufacturer: '시험 제약',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

// 클래스명: _Lookup
// 역할: 검색 결과나 지연·실패 응답을 주입하고 상세 조회 횟수를 기록하는 제어 대역이다.
// 주요 책임:
// - 실제 API 대신 request를 실행하여 조회 중 입력 변경과 화면 폐기를 재현한다.
// 속성:
// - request(Future<MedicationDetail?> Function()): 약 정보·null·오류를 반환하는 주입 동작.
// - calls(int): 상세 조회가 요청된 횟수.
class _Lookup extends CheckMedicationDetail {
  // 함수이름: _Lookup
  // 함수역할:
  // - 주입 동작을 저장하고 실제 네트워크 대신 500 응답 대역으로 상위 제어기를 구성한다.
  // 매개변수:
  // - request(Future<MedicationDetail?> Function()): 각 상세 조회에서 실행할 동작.
  // 반환값:
  // - _Lookup: 호출 횟수가 0인 검색 제어 대역.
  _Lookup(this.request)
    : super(client: MockClient((_) async => http.Response('{}', 500)));
  final Future<MedicationDetail?> Function() request;
  int calls = 0;
  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 호출 횟수를 늘린 뒤 주입한 조회의 결과나 오류를 그대로 전달한다.
  // 매개변수:
  // - schedule(MedicationSchedule): 인터페이스 호환용 검색 입력; 이 대역은 내용을 검사하지 않는다.
  // 반환값:
  // - Future<MedicationDetail?>: 주입된 약, 검색 결과 없음 또는 조회 실패.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule schedule,
  ) {
    calls++;
    return request();
  }
}

// 함수이름: _search
// 함수역할:
// - 검색 화면을 열고 고정 약 이름을 입력해 조회를 시작하되 지연 응답은 기다리지 않는다.
// 매개변수:
// - tester(WidgetTester): 화면 렌더링과 입력 도구.
// - lookup(_Lookup): 결과와 완료 시점을 제어하는 검색 대역.
// - selection(bool): true이면 약 선택 모드, false이면 상세 조회 모드.
// - english(bool): 영어 화면 사용 여부; 기본값은 한글이다.
// 반환값:
// - Future<void>: 검색 버튼을 누른 다음 프레임까지 완료.
Future<void> _search(
  WidgetTester tester,
  _Lookup lookup, {
  bool selection = false,
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MedicationSearchUI(
        userSetting: UserSetting(language: english ? 'en' : 'ko'),
        lookupControl: lookup,
        selectionMode: selection,
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const Key('medication-search-query')),
    '시험약',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('medication-search-submit')));
  await tester.pump();
}

// 함수이름: main
// 함수역할:
// - 검색 중 상태 변경, 후보 확인, 오류 종류별 안내와 카탈로그 연결 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 위젯 테스트를 프레임워크에서 실행한다.
void main() {
  for (final selection in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 동일 선택 콜백을 두 번 호출해도 상세 화면 또는 확인창이 하나만 열리고 닫은 뒤 다시 선택할 수 있는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
    testWidgets('검색 결과 연속 선택은 화면을 하나만 연다: $selection', (tester) async {
      await _search(tester, _Lookup(() async => _drug), selection: selection);
      await tester.pumpAndSettle();
      final open = tester
          .widget<ListTile>(find.byKey(const Key('medication-search-result-0')))
          .onTap!;
      open();
      open();
      await tester.pumpAndSettle();
      final routeWidget = selection
          ? find.byType(AlertDialog)
          : find.byType(CheckMedicationDetailUI);
      Navigator.of(tester.element(routeWidget)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CheckMedicationDetailUI), findsNothing);
      expect(find.byType(MedicationSearchUI), findsOneWidget);
      await tester.tap(find.byKey(const Key('medication-search-result-0')));
      await tester.pumpAndSettle();
      expect(routeWidget, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 선택 모드의 확인 콜백을 연속 호출해도 선택 약을 반환하고 검색 전 화면을 유지하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('검색 후보 연속 확인은 선택 결과를 한 번만 반환한다', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final lookup = _Lookup(() async => _drug);
    addTearDown(lookup.dispose);
    MedicationDetail? result;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('검색 전 화면')),
      ),
    );
    final selected = navigator.currentState!.push<MedicationDetail>(
      MaterialPageRoute(
        builder: (_) => MedicationSearchUI(
          userSetting: const UserSetting(),
          lookupControl: lookup,
          initialQuery: '시험약',
          selectionMode: true,
        ),
      ),
    );
    unawaited(selected.then((value) => result = value));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-search-result-0')));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '선택'))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(result, same(_drug));
    expect(find.text('검색 전 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 조회가 진행 중인 화면을 제거한 뒤 성공·실패 응답을 완료해도 화면 예외가 남지 않는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
    testWidgets('검색 중 폐기 후 응답을 무시한다: $fails', (tester) async {
      final response = Completer<MedicationDetail?>();
      final lookup = _Lookup(() => response.future);
      addTearDown(lookup.dispose);
      await _search(tester, lookup);
      await tester.pumpWidget(const SizedBox.shrink());
      if (fails) {
        response.completeError(StateError('late failure'));
      } else {
        response.complete(_drug);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 중복 후보 응답을 한 항목으로 표시하고 확인창에서 취소하면 추가 조회 없이 검색 화면에 머무르는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('후보는 사용자가 확인한 뒤 선택하며 취소하면 검색에 남는다', (tester) async {
    final lookup = _Lookup(
      () async => throw MedicationMatchReview([_drug, _drug]),
    );
    await _search(tester, lookup, selection: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-search-result-0')), findsOneWidget);
    expect(find.byKey(const Key('medication-search-result-1')), findsNothing);
    await tester.tap(find.byKey(const Key('medication-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.text('약품 정보 확인'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationSearchUI), findsOneWidget);
    expect(lookup.calls, 1);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 검색 요청 뒤 입력을 다른 이름으로 바꾸면 늦게 도착한 이전 약 결과가 표시되지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('입력 변경 후 도착한 이전 결과를 표시하지 않는다', (tester) async {
    final gate = Completer<MedicationDetail?>();
    final lookup = _Lookup(() => gate.future);
    await _search(tester, lookup);
    await tester.enterText(
      find.byKey(const Key('medication-search-query')),
      '다른약',
    );
    gate.complete(_drug);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-search-result-0')), findsNothing);
    expect(lookup.calls, 1);
  });

  // Function Name: testWidgets callback
  // Description:
  // - A failed lookup must expose neither private server details nor a no-results message; a successful null retry must show no results.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
  testWidgets('검색 실패는 빈 결과와 구별되며 다시 검색할 수 있다', (tester) async {
    var fail = true;
    final lookup = _Lookup(() async {
      if (fail) throw StateError('private server details');
      return null;
    });
    await _search(tester, lookup);
    await tester.pumpAndSettle();
    expect(find.textContaining('private server details'), findsNothing);
    expect(find.textContaining('찾은 약이 없어요'), findsNothing);
    fail = false;
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('찾은 약이 없어요'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Return HTTP 429 from the real lookup control and require a next-day retry notice without a connectivity warning.
  // Parameters:
  // - tester (WidgetTester): Driver for the rendered form and user interactions.
  // Returns:
  // - Future<void>: Completes the assertions; mismatched state or widget errors fail the test.
  testWidgets('하루 조회 한도는 연결 문제가 아니라 내일 다시 하라고 안내한다', (tester) async {
    final lookup = CheckMedicationDetail(
      client: MockClient(
        (_) async => http.Response(
          '{"detail":"오늘 사용할 수 있는 횟수를 모두 사용했습니다. 내일 다시 시도해주세요."}',
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(lookup.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MedicationSearchUI(
          userSetting: const UserSetting(),
          lookupControl: lookup,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('medication-search-query')),
      '시험약',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('내일 다시'), findsOneWidget);
    expect(find.textContaining('연결을 확인'), findsNothing);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기본 검색 모드에서 결과를 누르면 약 선택 확인 대신 기존 약 상세 화면으로 이동하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('독립 검색은 등록하지 않고 기존 상세 화면을 연다', (tester) async {
    await _search(tester, _Lookup(() async => _drug));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 폭 320·글씨 배율 1.4에서 긴 약 이름을 검색하고 화면 예외가 발생하지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
  // 반환값:
  // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
  testWidgets('좁은 화면 큰 글자에서도 긴 약 이름과 제조사가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: MedicationSearchUI(
          userSetting: const UserSetting(),
          initialQuery: '시험약',
          lookupControl: _Lookup(
            () async =>
                _drug.copyWith(itemName: '아주 긴 시험용 약 이름(함량과 제형이 포함된 제품명)'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final editName in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 직접 등록으로 돌아온 카탈로그 약은 그대로 제출하되 이름을 수정하면 연결을 해제하고 기본 복용량·시간대는 보존하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 사용자 입력을 제어하는 테스트 도구.
    // 반환값:
    // - Future<void>: 상태 검증 완료; 기대값 불일치나 화면 오류는 테스트 실패가 된다.
    testWidgets('직접 등록에서 검색 약 정보를 유지하고 이름 변경 시 해제 ($editName)', (tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ManualMedicationEntry? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMedicationEntryUI(
            userSetting: const UserSetting(),
            onSaveRequested: (entry) async {
              saved = entry;
              return const MedicationSaveResult(
                status: MedicationSaveStatus.failed,
                message: 'test',
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('manual-medication-search')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(MedicationSearchUI))).pop(_drug);
      await tester.pumpAndSettle();
      expect(find.text(_drug.itemName), findsOneWidget);
      if (editName) {
        await tester.enterText(
          find.byKey(const Key('manual-medication-name')),
          '다른약',
        );
      }
      await tester.tap(find.byKey(const Key('manual-medication-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.catalogMedication, editName ? isNull : same(_drug));
      expect(saved!.dosageAmount, '1');
      expect(saved!.scheduleSlotKeys, ['morning']);
    });
  }
}
