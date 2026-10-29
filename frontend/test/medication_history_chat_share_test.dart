// 기록 공유의 대상 범위, 재시도, 세션 변경과 실제 화면 전송 흐름을 검증한다.
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

Future<MedicationHistoryControl> _pump(
  WidgetTester tester,
  _Server server, {
  MedicationHistoryRange? sharedRange,
  double scale = 1,
  Stream<String?>? changes,
}) async {
  final history = MedicationHistoryControl(
    patientHash: 'test-patient',
    readOnly: sharedRange != null,
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
      ),
    ),
  );
  await tester.pumpAndSettle();
  return history;
}

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
  // 채팅에는 횟수만 간다는 점을 다른 앱으로 보내는 기록 글과 구분해 알린다.
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final range = MedicationHistoryRange(
    DateTime.utc(2026, 10, 16),
    DateTime.utc(2026, 10, 17),
  );

  test('recipient list is scoped to both patient and actor', () async {
    final share = _share(_Server(), sender: 'carer');
    expect((await share.loadRecipients()).map((link) => link.linkId), [1]);
    await expectLater(share.send(linkId: 2, range: range), throwsStateError);
  });

  test('lookup failure cannot leave stale recipients sendable', () async {
    final server = _Server();
    final share = _share(server);
    await share.loadRecipients();
    server.failLinks = true;
    await expectLater(share.loadRecipients(), throwsStateError);
    await expectLater(share.send(linkId: 1, range: range), throwsStateError);
    expect(server.posts, isEmpty);
  });

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
    expect(server.posts.single['history_start_date'], '2026-10-01');
    expect(server.posts.single['history_end_date'], '2026-10-17');
  });

  // 다른 앱 공유는 90일까지 되지만 채팅 공유는 서버가 31일만 받으므로 그보다 긴 기간이면 채팅만 막는다.
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
