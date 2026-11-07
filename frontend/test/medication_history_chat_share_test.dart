// 파일명: medication_history_chat_share_test.dart
// 역할: 기록 공유의 대상 범위, 재시도, 세션 변경과 실제 화면 전송 흐름을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/medication_history_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/controls/share_medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

import 'medication_history_fixtures.dart';

// 클래스명: _Server
// 역할: 복약 기록 조회·수신자 조회·채팅 전송을 기록하고 실패시킬 수 있는 서버 대역.
// 주요 책임:
// - 지정 날짜 범위의 기록과 연동 목록을 반환하고 전송 지연·응답 유실을 재현한다.
// 속성:
// - posts (List<Map<String, dynamic>>): 전송 본문 기록.
// - reads (List<Uri>): 이력 조회 URL 기록.
// - items (List<Map<String, dynamic>>): 날짜별 기록 fixture로 테스트에서 수정할 수 있다.
// - failSend, failLinks, noLinks (bool): 전송 오류·연동 조회 오류·빈 연동 목록 설정.
// - pendingSend (Completer<http.Response>?): 전송 응답 완료 시점 제어.
class _Server {
  final posts = <Map<String, dynamic>>[];
  final reads = <Uri>[];
  final items = <Map<String, dynamic>>[
    historyTestEntry(date: '2026-10-16', name: 'Previous day medicine'),
    historyTestEntry(date: '2026-10-17', name: 'Today medicine'),
  ];
  bool failSend = false;
  bool failLinks = false;
  bool noLinks = false;
  Completer<http.Response>? pendingSend;

  // 함수이름: respond
  // 함수역할:
  // - 연동 GET은 구성된 목록, 이력 GET은 양 끝 날짜를 포함한 기록을 반환하고 다른 요청은 본문을 기록한 뒤 지연·실패·성공 응답을 선택한다.
  // 매개변수:
  // - request (http.Request): 링크 목록, 날짜 범위 조회 또는 JSON 전송 요청.
  // 반환값:
  // - Future<http.Response>; fixture 응답 또는 pendingSend 결과. 실패 설정은 ClientException, 잘못된 JSON·누락 날짜는 파싱 오류로 드러난다.
  Future<http.Response> respond(http.Request request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/link/list')) {
      if (failLinks) throw http.ClientException('offline');
      return historyTestResponse({
        'data': noLinks
            ? []
            : [
                {
                  'link_id': 1,
                  'patient_hash': 'test-patient',
                  'caregiver_hash': 'carer',
                  'link_status': true,
                  'caregiver_alias': 'Family',
                  'patient_alias': 'Patient',
                },
                {
                  'link_id': 2,
                  'patient_hash': 'other-patient',
                  'caregiver_hash': 'carer',
                  'link_status': true,
                },
                {
                  'link_id': 3,
                  'patient_hash': 'test-patient',
                  'caregiver_hash': 'ended',
                  'link_status': false,
                },
              ],
      });
    }
    if (request.method == 'GET') {
      reads.add(request.url);
      final start = request.url.queryParameters['start_date']!;
      final end = request.url.queryParameters['end_date']!;
      return historyTestResponse(
        historyTestBody(
          start: start,
          end: end,
          items: items
              .where(
                (item) =>
                    (item['schedule_date'] as String).compareTo(start) >= 0 &&
                    (item['schedule_date'] as String).compareTo(end) <= 0,
              )
              .toList(),
        ),
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    posts.add(body);
    if (pendingSend != null) return pendingSend!.future;
    if (failSend) throw http.ClientException('response lost');
    return responseFor(body);
  }

  // 함수이름: responseFor
  // 함수역할:
  // - 요청의 메시지 ID·본문·공유 날짜를 서버가 만든 건수 스냅샷과 결합해 성공 응답을 만든다.
  // 매개변수:
  // - body (Map<String, dynamic>): client_message_id, body, history_start_date, history_end_date를 포함하는 전송 본문.
  // 반환값:
  // - http.Response; 연동 1의 medication_history_share 메시지와 고정 건수를 가진 응답.
  http.Response responseFor(Map<String, dynamic> body) => historyTestResponse({
    'data': {
      'message_id': 7,
      'link_id': 1,
      'sender_hash': 'test-patient',
      'client_message_id': body['client_message_id'],
      'body': body['body'],
      'created_at': historyTestNow.toIso8601String(),
      'message_kind': 'medication_history_share',
      'context': {
        'history_context': {
          'start_date': body['history_start_date'],
          'end_date': body['history_end_date'],
          'taken_count': 0,
          'skipped_count': 0,
          'unrecorded_count': 2,
        },
      },
    },
  });
}

// 함수이름: _share
// 함수역할:
// - 고정 환자·시계와 서버 대역으로 공유 컨트롤을 만들고 테스트 종료 시 해제한다.
// 매개변수:
// - server (_Server): 요청을 기록하고 응답을 결정할 대역.
// - sender (String): 요청 행위자 계정, 기본 test-patient.
// - check (void Function()?): 세션 유효성 검사; null이면 아무 동작도 하지 않는다.
// 반환값:
// - ShareMedicationHistory; 영어로 표시하고 test-patient 기록을 공유하는 컨트롤.
ShareMedicationHistory _share(
  _Server server, {
  String sender = 'test-patient',
  void Function()? check,
}) {
  final control = ShareMedicationHistory(
    userHash: sender,
    patientHash: 'test-patient',
    ensureSession: check ?? () {},
    isEnglish: true,
    client: MockClient(server.respond),
    now: () => historyTestNow,
  );
  addTearDown(control.dispose);
  return control;
}

// 함수이름: _pump
// 함수역할:
// - 이력 화면과 공유 컨트롤을 같은 세션·서버에 연결하며 공유 범위나 현재 대화가 있으면 읽기 전용으로 연다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링 및 안정화 대기 도구.
// - server (_Server): 기록·연동·전송 요청 대역.
// - sharedRange (MedicationHistoryRange?): 수신한 공유 범위; null이면 일반 이력 범위.
// - scale (double): 기본 1인 글자 배율.
// - changes (Stream<String?>?): 세션 변경 알림 스트림.
// - chatLinkId (int?): 현재 대화 ID; 있으면 읽기 전용 화면에서 공유 영역을 처음부터 연다.
// 반환값:
// - Future<MedicationHistoryControl>; 안정화된 화면의 이력 컨트롤을 반환하며 종료 시 해제한다.
Future<MedicationHistoryControl> _pump(
  WidgetTester tester,
  _Server server, {
  MedicationHistoryRange? sharedRange,
  double scale = 1,
  Stream<String?>? changes,
  int? chatLinkId,
}) async {
  final history = MedicationHistoryControl(
    patientHash: 'test-patient',
    readOnly: sharedRange != null || chatLinkId != null,
    client: MockClient(server.respond),
    now: () => historyTestNow,
    sessionKeyProvider: () => 'test-user',
    sessionChanges: changes,
  );
  final share = _share(server, check: history.ensureSession);
  addTearDown(history.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ko')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: MedicationHistoryUI(
        patientHash: 'test-patient',
        isEnglish: true,
        currentUserHash: 'test-patient',
        control: history,
        chatShareControl: share,
        sharedRange: sharedRange,
        readOnly: chatLinkId != null,
        chatLinkId: chatLinkId,
        initiallyShowExport: chatLinkId != null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return history;
}

// Function Name: _openShare
// Description:
// - Open export actions, verify aligned and separated share buttons plus the chat privacy explanation, then open recipient selection.
// Parameters:
// - tester (WidgetTester): opens the English share menu and inspects button geometry.
// Returns:
// - Future<void>; completes with the chat-share dialog open; unexpected layout or missing privacy text fails assertions.
Future<void> _openShare(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Share'));
  await tester.pumpAndSettle();
  final chatButton = tester.getRect(
    find.byKey(const Key('history-share-chat')),
  );
  final shareButton = tester.getRect(
    find.byKey(const Key('history-export-share')),
  );
  expect(chatButton.left, shareButton.left);
  expect(chatButton.width, shareButton.width);
  expect(shareButton.top - chatButton.bottom, greaterThanOrEqualTo(8));
  // Distinguish the counts shared in chat from the record text exported to other apps.
  expect(
    tester
        .widget<Text>(find.byKey(const Key('history-share-privacy-notice')))
        .data,
    contains('the chat gets only the period and the counts'),
  );
  await tester.ensureVisible(find.byKey(const Key('history-share-chat')));
  await tester.tap(find.byKey(const Key('history-share-chat')));
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할:
// - 현재 대화의 수신자 고정, 공유 권한·기간 검증, 재시도 식별자, 세션 변경과 읽기 전용 공유 상세를 검사하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  // 함수이름: setUp
  // 함수역할:
  // - 각 공유 테스트 전에 기기 저장 설정을 빈 값으로 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final range = MedicationHistoryRange(
    DateTime.utc(2026, 10, 16),
    DateTime.utc(2026, 10, 17),
  );

  // 함수이름: 현재 대화에서 읽기 전용 기록 공유를 열고 수신자를 고정한다
  // 함수역할:
  // - 현재 대화에서 읽기 전용 공유를 열면 해당 수신자만 선택된 상태로 보이고, 열기·취소만으로는 서버 전송을 하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('현재 대화에서 읽기 전용 기록 공유를 열고 수신자를 고정한다', (tester) async {
    final server = _Server();
    await _pump(tester, server, chatLinkId: 1);
    expect(find.byKey(const Key('history-share-chat')), findsOneWidget);
    expect(server.posts, isEmpty);
    await tester.tap(find.byKey(const Key('history-share-chat')));
    await tester.pumpAndSettle();
    final send = tester.widget<FilledButton>(
      find.byKey(const Key('history-chat-send')),
    );
    expect(send.onPressed, isNotNull);
    expect(find.byKey(const Key('history-share-recipient-1')), findsOneWidget);
    expect(find.byKey(const Key('history-share-recipient-2')), findsNothing);
    expect(server.posts, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
  });

  // 함수이름: 현재 대화가 조회 권한 범위에 없으면 다른 대화로 대신 보내지 않는다
  // 함수역할:
  // - 현재 대화가 해당 환자의 공유 권한 범위에 없으면 다른 대화로 대체하지 않고 수신자 목록과 전송 버튼을 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('현재 대화가 조회 권한 범위에 없으면 다른 대화로 대신 보내지 않는다', (tester) async {
    final server = _Server();
    await _pump(tester, server, chatLinkId: 2);
    await tester.tap(find.byKey(const Key('history-share-chat')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-chat-send')))
          .onPressed,
      isNull,
    );
    expect(find.byType(RadioListTile<int>), findsNothing);
    expect(server.posts, isEmpty);
  });

  // Function Name: an external share failure replaces the chat period notice
  // Description:
  // - An oversized external record export replaces the existing chat-period notice with its own failure message, so the actionable export error remains visible.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('an external share failure replaces the chat period notice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = _Server();
    await _pump(tester, server);
    await tester.tap(find.byKey(const Key('history-tab-custom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-range-start')));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byType(DatePickerDialog)),
    ).pop(DateTime(2026, 9, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    final message = find.byKey(const Key('history-export-error'));
    expect(tester.widget<Text>(message).data, contains('Chat sharing covers'));
    server.items.first['item_name'] = List.filled(100001, 'x').join();
    await tester.tap(find.byKey(const Key('history-export-share')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(message).data, contains('Too many records'));
  });

  // 함수이름: recipient list is scoped to both patient and actor
  // 함수역할:
  // - 공유 대상은 환자와 요청 행위자에 모두 연결된 활성 연동만 남기고, 다른 환자의 연동으로 전송하면 StateError로 거절하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('recipient list is scoped to both patient and actor', () async {
    final share = _share(_Server(), sender: 'carer');
    expect((await share.loadRecipients()).map((link) => link.linkId), [1]);
    await expectLater(share.send(linkId: 2, range: range), throwsStateError);
  });

  // 함수이름: lookup failure cannot leave stale recipients sendable
  // 함수역할:
  // - 연동 목록 재조회가 실패하면 이전 수신자를 그대로 전송 가능 상태로 남기지 않고 이후 전송도 요청 전에 거절하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('lookup failure cannot leave stale recipients sendable', () async {
    final server = _Server();
    final share = _share(server);
    await share.loadRecipients();
    server.failLinks = true;
    await expectLater(share.loadRecipients(), throwsStateError);
    await expectLater(share.send(linkId: 1, range: range), throwsStateError);
    expect(server.posts, isEmpty);
  });

  // 함수이름: retry keeps request identity and sends only dates, not snapshot data
  // 함수역할:
  // - 응답 유실 후 재시도는 같은 client_message_id와 날짜만 보내며 환자·건수 스냅샷을 보내지 않고, 성공 후 새 공유에는 새 식별자를 쓰는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test(
    'retry keeps request identity and sends only dates, not snapshot data',
    () async {
      final server = _Server()..failSend = true;
      final share = _share(server);
      await share.loadRecipients();
      await expectLater(
        share.send(linkId: 1, range: range),
        throwsA(isA<Exception>()),
      );
      server.failSend = false;
      await share.send(linkId: 1, range: range);
      expect(
        server.posts[0]['client_message_id'],
        server.posts[1]['client_message_id'],
      );
      expect(server.posts[1]['history_start_date'], '2026-10-16');
      expect(server.posts[1]['history_end_date'], '2026-10-17');
      expect(server.posts[1].keys, isNot(contains('patient_hash')));
      expect(server.posts[1].keys, isNot(contains('history_context')));
      await share.send(linkId: 1, range: range);
      expect(
        server.posts[2]['client_message_id'],
        isNot(server.posts[1]['client_message_id']),
      );
    },
  );

  // 함수이름: session change and invalid dates prevent a write
  // 함수역할:
  // - 공유 기간 상한 초과는 FormatException으로, 세션 변경은 세션 예외로 전송 전에 거절하여 기록 요청을 만들지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test('session change and invalid dates prevent a write', () async {
    var active = true;
    final server = _Server();
    final share = _share(
      server,
      check: () {
        if (!active) throw const MedicationHistorySessionChanged();
      },
    );
    await share.loadRecipients();
    await expectLater(
      share.send(
        linkId: 1,
        range: MedicationHistoryRange(
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 10, 17),
        ),
      ),
      throwsFormatException,
    );
    active = false;
    await expectLater(
      share.send(linkId: 1, range: range),
      throwsA(isA<MedicationHistorySessionChanged>()),
    );
    expect(server.posts, isEmpty);
  });

  // 함수이름: sharing requires recipient selection and explicit send
  // 함수역할:
  // - 일반 공유는 허용된 수신자를 직접 선택하고 전송해야 한 번 저장되며, 성공 안내와 실제 조회 기간이 일치하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('sharing requires recipient selection and explicit send', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    await _openShare(tester);
    expect(server.posts, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-chat-send')))
          .onPressed,
      isNull,
    );
    expect(find.text('Family'), findsOneWidget);
    expect(find.byKey(const Key('history-share-recipient-2')), findsNothing);
    await tester.tap(find.byKey(const Key('history-share-recipient-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('history-chat-send')));
    await tester.pumpAndSettle();
    expect(server.posts, hasLength(1));
    expect(find.text('Shared in your chat with Family.'), findsOneWidget);
    expect(server.posts.single['history_start_date'], '2026-10-12');
    expect(server.posts.single['history_end_date'], '2026-10-17');
  });

  // 함수이름: a period over 31 days keeps external sharing but not chat sharing
  // 함수역할:
  // - 31일을 넘는 기간은 채팅 공유만 비활성화하고 외부 공유는 유지하며, 제한 안내를 표시하고 채팅 요청을 보내지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'a period over 31 days keeps external sharing but not chat sharing',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-export-start')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 8, 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-share-chat')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-export-share')))
            .onPressed,
        isNotNull,
      );
      expect(
        find.textContaining('Chat sharing covers up to 31 days'),
        findsOneWidget,
      );
      expect(server.posts, isEmpty);
    },
  );

  // 함수이름: cancel and empty recipients never send
  // 함수역할:
  // - 연결된 수신자가 없는 대화 선택창은 빈 상태를 안내하고 취소해도 전송 요청을 만들지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('cancel and empty recipients never send', (tester) async {
    final server = _Server()..noLinks = true;
    await _pump(tester, server);
    await _openShare(tester);
    expect(
      find.text('There are no connected chats for this patient.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
  });

  // 함수이름: failed send remains retryable without duplicated intention
  // 함수역할:
  // - 공유 전송 실패는 선택창에 오류를 남기고 다시 전송할 수 있게 하되, 재시도는 기존 메시지 식별자를 유지하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('failed send remains retryable without duplicated intention', (
    tester,
  ) async {
    final server = _Server()..failSend = true;
    await _pump(tester, server);
    await _openShare(tester);
    await tester.tap(find.byKey(const Key('history-share-recipient-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('history-chat-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-chat-share-error')), findsOneWidget);
    server.failSend = false;
    await tester.tap(find.byKey(const Key('history-chat-send')));
    await tester.pumpAndSettle();
    expect(
      server.posts[0]['client_message_id'],
      server.posts[1]['client_message_id'],
    );
  });

  // 함수이름: session change in recipient dialog disables sharing and closes safely
  // 함수역할:
  // - 수신자 선택 중 세션이 끝나면 전송을 제거하고 세션 변경 안내로 전환하며 안전하게 닫아도 요청이나 렌더링 예외가 없는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'session change in recipient dialog disables sharing and closes safely',
    (tester) async {
      final changes = StreamController<String?>.broadcast(sync: true);
      addTearDown(changes.close);
      final server = _Server();
      await _pump(tester, server, changes: changes.stream);
      await _openShare(tester);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Session changed'), findsOneWidget);
      expect(find.byKey(const Key('history-chat-send')), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(server.posts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: shared details load exact period, stay read only and group dates
  // 함수역할:
  // - 수신한 공유 상세는 정확한 시작·종료일을 조회하고 수정·날짜 이동 없이 읽기 전용으로 표시하며 날짜별 기록을 스크롤해 볼 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'shared details load exact period, stay read only and group dates',
    (tester) async {
      final server = _Server();
      await _pump(tester, server, sharedRange: range);
      expect(server.reads.single.queryParameters['start_date'], '2026-10-16');
      expect(server.reads.single.queryParameters['end_date'], '2026-10-17');
      expect(
        find.text('Latest records for the shared period · Read only'),
        findsOneWidget,
      );
      expect(find.byTooltip('Edit record'), findsNothing);
      expect(find.byKey(const Key('history-date-navigation')), findsNothing);
      expect(find.text('Today medicine'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Previous day medicine'), findsOneWidget);
    },
  );

  // 함수이름: chat selection fits narrow screen with large text
  // 함수역할:
  // - 320×640·2배 글자에서도 공유 수신자 선택창이 렌더링 오류 없이 열리고 취소로 닫히는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('chat selection fits narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, _Server(), scale: 2);
    await _openShare(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
