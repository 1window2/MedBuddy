// 파일명: unlink_confirmation_ui_test.dart
// 역할: 연동 해제 확인창의 취소·중복 요청·세션 변경과 한영 큰 글씨 배치를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _UnlinkHarness
// 역할: 연동 목록과 지연 DELETE 응답을 공유하여 확인창의 세션 경합을 재현한다.
// 주요 책임:
// - 계정별 제어기를 유지하고 해제 요청·화면 갱신 횟수를 관찰한다.
// 속성:
// - deletes(List<http.Request>): 실제로 전송된 해제 요청 목록.
// - response(Completer<http.Response>): 해제 완료를 제어하는 응답 신호.
// - linked(bool): 목록과 해제 응답에 반영할 현재 연동 상태.
// - updates(int): onLinksChanged 호출 횟수.
// - controls(Map<String, LinkPatientCaregiver>): 계정별로 재사용하는 제어기.
// - client(MockClient): 목록 조회와 지연 해제를 처리하는 공용 HTTP 대역.
class _UnlinkHarness {
  final deletes = <http.Request>[];
  final response = Completer<http.Response>();
  bool linked = true;
  int updates = 0;
  final controls = <String, LinkPatientCaregiver>{};
  late final client = MockClient((request) async {
    if (request.method == 'DELETE') {
      deletes.add(request);
      return response.future;
    }
    expect(request.method, 'GET');
    final user = request.url.queryParameters['user_hash'];
    return _json({
      'data':
          request.url.path.endsWith('/medications') ||
              !linked ||
              user == 'caregiver-b'
          ? []
          : [_link],
    });
  });

  // 함수이름: _link
  // 함수역할:
  // - 현재 linked 상태와 환자·보호자 별칭을 가진 연동 응답 한 건을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Map<String, Object>: 고정 연동 1의 새 응답 맵.
  Map<String, Object> get _link => {
    'link_id': 1,
    'patient_hash': 'patient-a',
    'caregiver_hash': 'caregiver-a',
    'patient_alias': '어머니',
    'caregiver_alias': '우리 딸',
    'link_status': linked,
  };

  // 함수이름: screen
  // 함수역할:
  // - 공용 HTTP 대역과 계정별 제어기를 연결한 연동 관리 화면을 구성한다.
  // 매개변수:
  // - user(String): 화면의 현재 계정; 기본값은 caregiver-a이다.
  // - language(String): 설정과 확인창에 적용할 화면 언어.
  // 반환값:
  // - Widget: 연동 변화 시 updates를 증가시키는 MaterialApp.
  Widget screen({String user = 'caregiver-a', String language = 'ko'}) =>
      MaterialApp(
        theme: MedBuddyTheme.light(),
        home: LinkPatientCaregiverUI(
          initialUserHash: user,
          userSetting: UserSetting(language: language),
          controlFactory: (hash) => controls.putIfAbsent(
            hash,
            () => LinkPatientCaregiver(
              baseUrl: 'http://localhost',
              userHash: hash,
              client: client,
            ),
          ),
          chatControlFactory: (hash) =>
              ManageLinkedChat(userHash: hash, client: client),
          onLinksChanged: () => updates++,
        ),
      );

  // 함수이름: complete
  // 함수역할:
  // - 연동을 해제 상태로 바꾸고 대기 DELETE를 성공 응답으로 한 번 완료한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 이미 완료한 response에 다시 호출하면 StateError가 발생한다.
  void complete() {
    linked = false;
    response.complete(_json({'data': _link}));
  }
}

// 함수이름: _json
// 함수역할:
// - 가상 연동 응답을 JSON 콘텐츠 형식의 성공 HTTP 응답으로 만든다.
// 매개변수:
// - body(Object): JSON으로 변환 가능한 본문.
// 반환값:
// - http.Response: 상태 코드 200 응답; 인코딩할 수 없는 본문은 오류를 발생시킨다.
http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// 함수이름: _pump
// 함수역할:
// - 430×900 화면에 새 연동 대역을 장착하고 초기 조회·애니메이션 완료를 기다린다.
// 매개변수:
// - tester(WidgetTester): 화면 조작 도구; 화면 크기 복원과 클라이언트 닫기를 정리 훅에 등록한다.
// - user(String): 초기 계정 식별자.
// - language(String): 초기 화면 언어.
// 반환값:
// - Future<_UnlinkHarness>: 요청 기록과 지연 응답을 제어할 대역.
Future<_UnlinkHarness> _pump(
  WidgetTester tester, {
  String user = 'caregiver-a',
  String language = 'ko',
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _UnlinkHarness();
  addTearDown(harness.client.close);
  await tester.pumpWidget(harness.screen(user: user, language: language));
  await tester.pumpAndSettle();
  return harness;
}

// 함수이름: _open
// 함수역할:
// - 연동 관리와 해제 버튼을 순서대로 눌러 확인창을 열고 이전 해제 콜백을 보관한다.
// 매개변수:
// - tester(WidgetTester): 스크롤과 버튼 입력을 실행할 도구.
// - language(String): 버튼 문구 검색에 사용할 ko 또는 en.
// 반환값:
// - Future<VoidCallback>: 확인창 재진입 검증용 원래 해제 버튼 콜백.
Future<VoidCallback> _open(
  WidgetTester tester, {
  String language = 'ko',
}) async {
  final manage = find.text(language == 'en' ? 'Manage link' : '연동 관리');
  await tester.ensureVisible(manage);
  await tester.tap(manage);
  await tester.pumpAndSettle();
  final remove = find.widgetWithText(
    TextButton,
    language == 'en' ? 'Remove link' : '연동 해제',
  );
  await tester.ensureVisible(remove);
  await tester.pumpAndSettle();
  final callback = tester.widget<TextButton>(remove).onPressed!;
  await tester.tap(remove);
  await tester.pumpAndSettle();
  return callback;
}

// 함수이름: main
// 함수역할:
// - 확인창과 지연 DELETE 대역으로 사용자 확인 범위와 세션별 해제 권한을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 이전 테스트의 연동 별칭·계정 설정이 남지 않도록 환경설정 대역을 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 각 사례에 새 저장 상태를 제공한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dismissal in ['cancel', 'back', 'barrier', 'enter']) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 취소·뒤로가기·바깥 누르기·Enter로 확인창을 닫은 뒤 오래된 확인 콜백을 호출해도 해제 요청과 갱신이 없으며 영향 범위 안내를 표시하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('unlink $dismissal sends zero DELETE requests', (tester) async {
      final harness = await _pump(tester);
      await _open(tester);
      expect(harness.deletes, isEmpty);
      final staleConfirm = tester.widget<FilledButton>(
        find.byKey(const Key('unlink-confirm')),
      ).onPressed!;
      expect(find.textContaining('어머니 님과의 복약 일정 공유가 중단됩니다.'), findsOneWidget);
      expect(
        find.textContaining('보호자 알림 설정과 두 사람의 대화 기록이 삭제됩니다.'),
        findsOneWidget,
      );
      expect(find.textContaining('환자의 약과 복약 기록은 삭제되지 않습니다.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('unlink-cancel')))
            .autofocus,
        isTrue,
      );
      if (dismissal == 'cancel') {
        await tester.tap(find.byKey(const Key('unlink-cancel')));
      } else if (dismissal == 'back') {
        await tester.binding.handlePopRoute();
      } else if (dismissal == 'barrier') {
        await tester.tapAt(const Offset(4, 4));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      staleConfirm();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlink-confirmation-dialog')), findsNothing);
      expect(harness.deletes, isEmpty);
      expect(harness.updates, 0);
      expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 열기·확인 콜백을 중복 호출하고 전송 대기 중 다시 열어도 올바른 계정의 DELETE 한 번만 보내며 응답 후 한 번 갱신하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'duplicate dialog and confirm inputs send exactly one pending DELETE',
    (tester) async {
      final harness = await _pump(tester);
      final remove = await _open(tester);
      remove();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('unlink-confirmation-dialog')),
        findsOneWidget,
      );
      final confirm = tester
          .widget<FilledButton>(find.byKey(const Key('unlink-confirm')))
          .onPressed!;
      confirm();
      confirm();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      remove();
      await tester.pump();
      expect(harness.deletes, hasLength(1));
      expect(harness.deletes.single.url.path, '/link/1');
      expect(
        harness.deletes.single.url.queryParameters['user_hash'],
        'caregiver-a',
      );
      expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
      harness.complete();
      await tester.pumpAndSettle();
      expect(harness.updates, 1);
      expect(find.text('환자-보호자 연동을 해제했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final returnToOriginal in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 확인창을 연 뒤 계정을 바꾸면 원래 계정으로 돌아와도 이전 확인으로 삭제할 수 없고 성공 안내도 표시하지 않는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets(
      'session change invalidates unlink confirmation, return=$returnToOriginal',
      (tester) async {
        final harness = await _pump(tester);
        await _open(tester);
        await tester.pumpWidget(harness.screen(user: 'caregiver-b'));
        await tester.pumpAndSettle();
        if (returnToOriginal) {
          await tester.pumpWidget(harness.screen());
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('unlink-confirm')));
        await tester.pumpAndSettle();
        expect(harness.deletes, isEmpty);
        expect(harness.updates, 0);
        expect(find.text('환자-보호자 연동을 해제했습니다.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 이전 계정의 DELETE 응답이 새 계정 화면에서 완료되어도 갱신·성공 안내를 발생시키거나 이전 계정 별칭을 지우지 않는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('old DELETE completion cannot clear state after session change', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _open(tester);
    await tester.tap(find.byKey(const Key('unlink-confirm')));
    await tester.pump();
    expect(harness.deletes, hasLength(1));
    await tester.pumpWidget(harness.screen(user: 'caregiver-b'));
    await tester.pumpAndSettle();
    harness.complete();
    await tester.pumpAndSettle();
    expect(harness.updates, 0);
    expect(find.text('환자-보호자 연동을 해제했습니다.'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('caregiver_patient_label.caregiver-a.patient-a'),
      '어머니',
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 환자가 여는 확인창은 보호자 별칭을 표시하고 폭 320·글씨 배율 2에서 두 언어의 취소·확인 버튼에 접근할 수 있는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets(
      'unlink dialog names caregiver and fits large text in $language',
      (tester) async {
        final harness = await _pump(
          tester,
          user: 'patient-a',
          language: language,
        );
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await _open(tester, language: language);
        expect(
          find.descendant(
            of: find.byKey(const Key('unlink-confirmation-dialog')),
            matching: find.textContaining('우리 딸'),
          ),
          findsOneWidget,
        );
        for (final key in ['unlink-cancel', 'unlink-confirm']) {
          final button = find.byKey(Key(key));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(harness.deletes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('unlink-cancel')));
        await tester.pumpAndSettle();
      },
    );
  }
}
