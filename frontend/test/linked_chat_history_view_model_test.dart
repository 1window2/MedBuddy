// File Name: linked_chat_history_view_model_test.dart
// Role: Characterizes independent chat recovery, evidence merging, and lifecycle cancellation.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';
import 'package:medbuddy_frontend/viewmodels/linked_chat_history_view_model.dart';

// 함수이름: main
// 함수역할:
// - 독립 채팅 이력 모델의 읽음·삭제 병합, 지연 응답, 페이지 복구와 생명주기 취소를 실제 소켓 없이 검사하는 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  for (final event in [
    {'link_id': 99, 'reader_hash': 'peer'},
    {'link_id': 17, 'reader_hash': 'self'},
    {'link_id': 17, 'reader_hash': 'peer', 'read_at': 'invalid'},
  ]) {
    // 함수이름: ignored early read event cannot affect a later message: $event
    // 함수역할:
    // - 다른 연동·본인 읽음·잘못된 읽음 시각 이벤트는 메시지보다 먼저 와도 무시되어 이후 메시지에 읽음 표시를 붙이지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - void; 기대 결과와 다르면 테스트가 실패한다.
    test('ignored early read event cannot affect a later message: $event', () {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.model.handleEvent({
        'type': 'chat_read',
        'through_message_id': 3,
        'read_at': '2026-10-03T03:02:00Z',
        ...event,
      });
      fixture.model.addMessage(_message(3));
      expect(fixture.model.messages.single.readAt, isNull);
    });
  }

  for (final delivery in ['history', 'send', 'realtime']) {
    // 함수이름: early read receipt survives delayed $delivery
    // 함수역할:
    // - 메시지보다 먼저 받은 상대 읽음 경계는 낮은 후속 경계로 되돌아가지 않고 이력·전송·실시간 경로의 늦은 메시지에 적용되며, 다른 메시지는 읽음 처리하지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    test('early read receipt survives delayed $delivery', () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      final gate = Completer<List<ChatMessage>>();
      fixture.control.historyHandler = (_) => gate.future;
      final pending = fixture.model.refresh(showLoading: true);
      fixture.model.handleEvent({
        'type': 'chat_read',
        'link_id': 17,
        'reader_hash': 'peer',
        'through_message_id': 3,
        'read_at': '2026-10-03T03:02:00Z',
      });
      // 뒤늦은 낮은 읽음 경계가 먼저 받은 경계를 되돌리지 않아야 한다.
      fixture.model.handleEvent({
        'type': 'chat_read',
        'reader_hash': 'peer',
        'through_message_id': 1,
        'read_at': '2026-10-03T03:01:00Z',
      });
      gate.complete(delivery == 'history' ? [_message(3)] : []);
      await pending;
      if (delivery == 'send') fixture.model.addMessage(_message(3));
      if (delivery == 'realtime') {
        fixture.model.handleEvent({
          'type': 'chat_message',
          'message': _wireMessage(3),
        });
      }
      expect(
        fixture.model.messages.single.readAt,
        DateTime.utc(2026, 10, 3, 3, 2),
      );
      fixture.model.addMessage(_message(4));
      fixture.model.addMessage(_message(2, sender: 'peer'));
      expect(fixture.model.messages.last.readAt, isNull);
      expect(fixture.model.messages.first.readAt, isNull);
      fixture.model.addMessage(_message(3));
      expect(
        fixture.model.messages.singleWhere((m) => m.messageId == 3).readAt,
        DateTime.utc(2026, 10, 3, 3, 2),
      );
    });
  }

  // Function Name: history owner remains an independent presentation-free library
  // Description:
  // - Keep the history model an independent library using the transport interface, without widget boundaries, material/navigation imports, the app facade, or the concrete socket service.
  // Parameters:
  // - None.
  // Returns:
  // - void; assertion failures fail the case.
  test('history owner remains an independent presentation-free library', () {
    final source = File(
      'lib/viewmodels/linked_chat_history_view_model.dart',
    ).readAsStringSync();
    final imports = RegExp(
      r'''^import\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!);
    expect(imports, isNot(anyElement(contains('boundaries/'))));
    expect(imports, isNot(contains('package:flutter/material.dart')));
    expect(imports, isNot(anyElement(contains('medbuddy_view_model.dart'))));
    expect(source, isNot(contains('part of')));
    expect(source, contains('final LinkedChatSessionTransport realtime;'));
    expect(source, isNot(contains('LinkedChatRealtimeService')));
  });

  // Function Name: late history cannot undo read receipts or message deletion
  // Description:
  // - Preserve immutable message snapshots and monotonic read/deletion evidence when stale history returns; hiding removes only the selected message and global deletion retains its tombstone.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('late history cannot undo read receipts or message deletion', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    fixture.control.history = [_message(1), _message(2), _message(3)];
    await fixture.model.refresh(showLoading: true);
    final snapshot = fixture.model.messages;
    expect(identical(snapshot, fixture.model.messages), isTrue);
    expect(() => snapshot.clear(), throwsUnsupportedError);
    fixture.model.handleEvent({
      'type': 'chat_read',
      'reader_hash': 'peer',
      'through_message_id': 3,
      'read_at': '2026-10-03T03:02:00Z',
    });
    fixture.model.handleEvent({
      'type': 'chat_read',
      'reader_hash': 'peer',
      'through_message_id': 3,
      'read_at': '2026-10-03T03:01:00Z',
    });
    fixture.model.applyDeletion([2], ChatDeletionScope.me);
    fixture.model.applyDeletion([3], ChatDeletionScope.everyone);
    await fixture.model.refresh(showLoading: false);
    expect(fixture.model.messages.map((m) => m.messageId), [1, 3]);
    expect(
      fixture.model.messages.first.readAt,
      DateTime.utc(2026, 10, 3, 3, 2),
    );
    expect(fixture.model.messages.last.deletedForEveryone, isTrue);
    expect(snapshot.map((m) => m.messageId), [1, 2, 3]);
    expect(fixture.deletedSelections, [
      [2],
      [3],
    ]);
  });

  // Function Name: history requests coalesce with one catch-up after an in-flight read
  // Description:
  // - Coalesce overlapping ordinary and catch-up refreshes onto the same future, then perform exactly one queued catch-up and merge both pages.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'history requests coalesce with one catch-up after an in-flight read',
    () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      final gate = Completer<List<ChatMessage>>();
      fixture.control.historyHandler = (_) async {
        if (fixture.control.historyBoundaries.length == 1) return gate.future;
        return [_message(2)];
      };
      final first = fixture.model.refresh(showLoading: true);
      final regular = fixture.model.refresh(showLoading: false);
      final reconnect = fixture.model.refresh(
        showLoading: false,
        catchUp: true,
      );
      fixture.model.refresh(showLoading: false, catchUp: true);
      expect(identical(first, regular), isTrue);
      expect(identical(first, reconnect), isTrue);
      expect(fixture.control.historyBoundaries, [null]);
      gate.complete([_message(1)]);
      await first;
      expect(fixture.control.historyBoundaries, [null, null]);
      expect(fixture.model.messages.map((m) => m.messageId), [1, 2]);
    },
  );

  // Function Name: reconnect recovers missed pages back to the last known message
  // Description:
  // - Reconnect recovery walks every full page back to the last known message, restoring all 102 messages instead of stopping at the latest fifty.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'reconnect recovers missed pages back to the last known message',
    () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.control.history = [_message(1)];
      await fixture.model.refresh(showLoading: true);
      fixture.control.historyHandler = (before) async => switch (before) {
        null => _page(53, 102),
        53 => _page(3, 52),
        3 => _page(1, 2),
        _ => throw StateError('Unexpected boundary $before'),
      };
      await fixture.model.refresh(showLoading: false, catchUp: true);
      expect(fixture.control.historyBoundaries, [null, null, 53, 3]);
      expect(
        fixture.model.messages.map((m) => m.messageId),
        List.generate(102, (i) => i + 1),
      );
    },
  );

  // Function Name: disposal invalidates in-flight recovery and queued catch-up
  // Description:
  // - After model disposal, late recovery and queued catch-up cannot publish, request further pages, or close borrowed adapters; subsequent calls remain inert.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('disposal invalidates in-flight recovery and queued catch-up', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    fixture.control.history = [_message(1)];
    await fixture.model.refresh(showLoading: true);
    final gate = Completer<List<ChatMessage>>();
    fixture.control.historyHandler = (_) => gate.future;
    var notifications = 0;
    fixture.model.addListener(() => notifications++);
    final pending = fixture.model.refresh(showLoading: false);
    fixture.model.refresh(showLoading: false, catchUp: true);
    fixture.disposeModel();
    gate.complete(_page(100, 149));
    await pending;
    expect(fixture.control.historyBoundaries, [null, null]);
    expect(fixture.model.messages.map((m) => m.messageId), [1]);
    expect(notifications, 0);
    expect(fixture.realtime.disposed, isFalse);
    expect(fixture.control.disposed, isFalse);
    await fixture.model.refresh(showLoading: true);
    fixture.model.addMessage(_message(200));
    fixture.model.handleEvent({
      'type': 'chat_messages_deleted',
      'message_ids': [1],
      'scope': 'me',
    });
    expect(fixture.control.historyBoundaries.length, 2);
    expect(fixture.model.messages.length, 1);
  });

  // Function Name: older pagination is serialized and preserves realtime unread evidence
  // Description:
  // - Serialize older-page requests while preserving realtime arrivals and the original unread boundary; failed pagination remains retryable and an empty recovery page ends pagination.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'older pagination is serialized and preserves realtime unread evidence',
    () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.control.history = _page(51, 100);
      fixture.control.unread = const ChatUnreadSummary(
        count: 1,
        firstMessageId: 20,
      );
      await fixture.model.refresh(showLoading: true);
      final gate = Completer<List<ChatMessage>>();
      fixture.control.historyHandler = (_) => gate.future;
      final older = fixture.model.loadOlderMessages();
      await fixture.model.loadOlderMessages();
      fixture.model.handleEvent({
        'type': 'chat_message',
        'message': _wireMessage(101, sender: 'peer'),
      });
      gate.complete(_page(1, 50));
      await older;
      expect(fixture.control.historyBoundaries, [null, 51]);
      expect(fixture.model.messages.length, 101);
      expect(fixture.model.firstUnreadMessageId, 20);
      expect(fixture.model.loadingOlderMessages, isFalse);
      fixture.control.historyHandler = (_) async => throw StateError('offline');
      await fixture.model.loadOlderMessages();
      expect(fixture.model.olderMessagesFailed, isTrue);
      expect(fixture.model.messages.length, 101);
      fixture.control.historyHandler = (_) async => [];
      await fixture.model.loadOlderMessages();
      expect(fixture.model.olderMessagesFailed, isFalse);
      expect(fixture.model.hasOlderMessages, isFalse);
    },
  );

  // Function Name: disposal cancels publication of a pending older page
  // Description:
  // - An older page completing after disposal cannot replace the previously loaded oldest message.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('disposal cancels publication of a pending older page', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    fixture.control.history = _page(51, 100);
    await fixture.model.refresh(showLoading: true);
    final gate = Completer<List<ChatMessage>>();
    fixture.control.historyHandler = (_) => gate.future;
    final pending = fixture.model.loadOlderMessages();
    fixture.disposeModel();
    gate.complete(_page(1, 50));
    await pending;
    expect(fixture.model.messages.first.messageId, 51);
  });

  // 함수이름: slow notification cleanup cannot block the next read receipt
  // 함수역할:
  // - 알림 정리 onRead 콜백이 지연되어도 다음 상대 메시지의 읽음 요청을 막지 않고 두 읽음 경계를 순서대로 전송하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  test(
    'slow notification cleanup cannot block the next read receipt',
    () async {
      final gate = Completer<void>();
      final fixture = _HistoryFixture(onRead: (_) => gate.future);
      addTearDown(fixture.dispose);
      fixture.control.history = [_message(1, sender: 'peer')];
      await fixture.model.refresh(showLoading: true);
      fixture.atLatest = true;
      await fixture.model.markLatestIncomingRead();
      fixture.model.addMessage(_message(2, sender: 'peer'));
      await fixture.model.markLatestIncomingRead();
      expect(fixture.control.readIds, [1, 2]);
      gate.complete();
      await pumpEventQueue();
    },
  );

  // Function Name: read acknowledgement is gated, coalesced and drains newer incoming messages
  // Description:
  // - Read acknowledgements require visibility at the latest position, coalesce duplicate attempts, and drain a newer incoming message once the pending receipt finishes.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'read acknowledgement is gated, coalesced and drains newer incoming messages',
    () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.control.history = [_message(1, sender: 'peer')];
      await fixture.model.refresh(showLoading: true);
      fixture.atLatest = true;
      fixture.visible = false;
      await fixture.model.markLatestIncomingRead();
      expect(fixture.control.readIds, isEmpty);
      fixture.visible = true;
      final gate = Completer<void>();
      fixture.control.readHandler = (id) =>
          id == 1 ? gate.future : Future.value();
      final pending = fixture.model.markLatestIncomingRead();
      await fixture.model.markLatestIncomingRead();
      fixture.model.addMessage(_message(2, sender: 'peer'));
      gate.complete();
      await pending;
      await pumpEventQueue();
      expect(fixture.control.readIds, [1, 2]);
      await fixture.model.markLatestIncomingRead();
      expect(fixture.control.readIds, [1, 2]);
    },
  );

  // Function Name: read failures retry but disposed receipt completion cannot start another read
  // Description:
  // - A failed read boundary can retry, but disposal before that retry finishes prevents acknowledgement of a newer incoming message.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'read failures retry but disposed receipt completion cannot start another read',
    () async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.control.history = [_message(1, sender: 'peer')];
      await fixture.model.refresh(showLoading: true);
      fixture.atLatest = true;
      fixture.control.readHandler = (_) async => throw StateError('offline');
      await fixture.model.markLatestIncomingRead();
      final gate = Completer<void>();
      fixture.control.readHandler = (_) => gate.future;
      final pending = fixture.model.markLatestIncomingRead();
      fixture.model.addMessage(_message(2, sender: 'peer'));
      fixture.disposeModel();
      gate.complete();
      await pending;
      await pumpEventQueue();
      expect(fixture.control.readIds, [1, 1]);
    },
  );

  // Function Name: foreign conversation events and results are ignored
  // Description:
  // - Ignore foreign-link sends, realtime messages, deletion and read events, plus malformed message payloads, without altering the current conversation.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('foreign conversation events and results are ignored', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    fixture.control.history = [_message(1)];
    await fixture.model.refresh(showLoading: true);
    fixture.model.addMessage(_message(2, linkId: 99));
    fixture.model.handleEvent({
      'type': 'chat_message',
      'message': _wireMessage(3, linkId: 99),
    });
    fixture.model.handleEvent({'type': 'chat_message', 'message': {}});
    fixture.model.handleEvent({
      'type': 'chat_messages_deleted',
      'link_id': 99,
      'message_ids': [1],
      'scope': 'me',
    });
    fixture.model.handleEvent({
      'type': 'chat_read',
      'link_id': 99,
      'reader_hash': 'peer',
      'through_message_id': 1,
      'read_at': '2026-10-03T03:01:00Z',
    });
    expect(fixture.model.messages.map((m) => m.messageId), [1]);
    expect(fixture.model.messages.single.readAt, isNull);
    expect(fixture.deletedSelections, isEmpty);
  });

  // Function Name: fallback cadence survives reconnect noise and stops in background
  // Description:
  // - Repeated reconnect signals do not postpone fallback polling; backgrounding stops polls and transport, foregrounding refreshes, and a connected transport suppresses fallback polls.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains lifecycle and polling work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets(
    'fallback cadence survives reconnect noise and stops in background',
    (tester) async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize();
      fixture.realtime.emitState(LinkedChatConnectionState.disconnected);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 4));
        fixture.realtime.emitState(LinkedChatConnectionState.connecting);
        await tester.pump();
      }
      expect(fixture.control.historyBoundaries.length, 2);
      fixture.model.setForeground(false);
      await tester.pump(const Duration(seconds: 36));
      expect(fixture.control.historyBoundaries.length, 2);
      expect(fixture.realtime.stops, 1);
      fixture.model.setForeground(true);
      await tester.pump();
      expect(fixture.control.historyBoundaries.length, 3);
      fixture.realtime.emitState(LinkedChatConnectionState.connected);
      await tester.pump();
      final afterReconnect = fixture.control.historyBoundaries.length;
      await tester.pump(const Duration(seconds: 36));
      expect(fixture.control.historyBoundaries.length, afterReconnect);
    },
  );

  // Verifies a removed or forbidden link ends the 12 s poll and the reconnect loop, while a
  // resume still tries once and a successful read resumes realtime delivery.
  for (final status in [403, 404]) {
    // Function Name: a $status history answer stops polling and the transport
    // Description:
    // - A terminal link-rejection response stops polling and transport while preserving loaded messages; resume retries once, and a successful explicit refresh restores transport and polling.
    // Parameters:
    // - tester (WidgetTester): advances the fake clock and drains lifecycle and polling work.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    testWidgets('a $status history answer stops polling and the transport', (
      tester,
    ) async {
      final fixture = _HistoryFixture();
      addTearDown(fixture.dispose);
      fixture.control.history = [_message(1)];
      await fixture.model.initialize();
      fixture.realtime.emitState(LinkedChatConnectionState.disconnected);
      await tester.pump();
      fixture.control.historyHandler = (_) async => throw ApiRequestException(
        'History lookup failed',
        statusCode: status,
        detail: 'An active patient-caregiver link is required.',
      );
      await tester.pump(const Duration(seconds: 12));
      expect(fixture.control.historyBoundaries.length, 2);
      expect(fixture.model.linkUnavailable, isTrue);
      expect(fixture.realtime.stops, 1);
      // The already loaded messages stay readable.
      expect(fixture.model.messages.single.messageId, 1);

      await tester.pump(const Duration(seconds: 60));
      expect(fixture.control.historyBoundaries.length, 2);

      // A resume retries once; a still rejected link stays quiet afterwards.
      fixture.model.setForeground(true);
      await tester.pump();
      expect(fixture.control.historyBoundaries.length, 3);
      expect(fixture.realtime.stops, 2);
      await tester.pump(const Duration(seconds: 60));
      expect(fixture.control.historyBoundaries.length, 3);

      // An explicit retry that succeeds leaves the terminal state and restarts the transport.
      fixture.control.historyHandler = null;
      final starts = fixture.realtime.starts;
      await fixture.model.refresh(showLoading: true);
      expect(fixture.model.linkUnavailable, isFalse);
      expect(fixture.realtime.starts, starts + 1);
      await tester.pump(const Duration(seconds: 12));
      expect(fixture.control.historyBoundaries.length, 5);
      // The fallback timer is running again; end the model before the pending-timer check.
      fixture.disposeModel();
    });
  }

  // Function Name: a server error keeps the fallback poll running
  // Description:
  // - HTTP 503 leaves the link nonterminal and preserves fallback polling cadence without stopping the transport.
  // Parameters:
  // - tester (WidgetTester): advances the fake clock and drains lifecycle and polling work.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a server error keeps the fallback poll running', (tester) async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    await fixture.model.initialize();
    fixture.realtime.emitState(LinkedChatConnectionState.disconnected);
    await tester.pump();
    fixture.control.historyHandler = (_) async =>
        throw ApiRequestException('History lookup failed', statusCode: 503);
    await tester.pump(const Duration(seconds: 36));
    expect(fixture.control.historyBoundaries.length, 4);
    expect(fixture.model.linkUnavailable, isFalse);
    expect(fixture.realtime.stops, 0);
    fixture.disposeModel();
  });

  // Function Name: a full server page with a skipped row still pages backwards
  // Description:
  // - Use server rowCount rather than parsed-message count to continue older pagination when malformed rows were skipped, then stop on a truly short page.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('a full server page with a skipped row still pages backwards', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.dispose);
    // Rows 52..101 arrived, row 60 could not be parsed.
    fixture.control.historyHandler = (before) async => switch (before) {
      null => ChatHistoryPage([
        for (var id = 52; id <= 101; id++)
          if (id != 60) _message(id),
      ], rowCount: 50),
      52 => ChatHistoryPage([
        for (var id = 2; id <= 51; id++)
          if (id != 2) _message(id),
      ], rowCount: 50),
      3 => ChatHistoryPage([_message(1)], rowCount: 1),
      _ => throw StateError('Unexpected boundary $before'),
    };
    await fixture.model.refresh(showLoading: true);
    expect(fixture.model.hasOlderMessages, isTrue);
    await fixture.model.loadOlderMessages();
    expect(fixture.model.hasOlderMessages, isTrue);
    await fixture.model.loadOlderMessages();
    expect(fixture.model.hasOlderMessages, isFalse);
    expect(fixture.control.historyBoundaries, [null, 52, 3]);
    expect(fixture.model.messages, hasLength(99));
  });
}

// Function Name: _message
// Description:
// - Parse a deterministic message payload with explicit sender and conversation scope.
// Parameters:
// - id (int): message ID and text suffix.
// - sender (String): sender account, default self.
// - linkId (int): conversation ID, default 17.
// Returns:
// - ChatMessage; parsed test payload with fixed UTC creation time.
ChatMessage _message(int id, {String sender = 'self', int linkId = 17}) =>
    ChatMessage.fromJson(_wireMessage(id, sender: sender, linkId: linkId));

// Function Name: _wireMessage
// Description:
// - Build a server-shaped message without personal content at the fixed test timestamp.
// Parameters:
// - id (int): message ID and suffix of client ID/body.
// - sender (String): sender account, default self.
// - linkId (int): conversation scope, default 17.
// Returns:
// - Map<String, dynamic>; wire payload accepted by ChatMessage.fromJson.
Map<String, dynamic> _wireMessage(
  int id, {
  String sender = 'self',
  int linkId = 17,
}) => {
  'message_id': id,
  'link_id': linkId,
  'sender_hash': sender,
  'client_message_id': 'history_test_$id',
  'body': 'Message $id',
  'created_at': '2026-10-03T03:00:00Z',
};

// Function Name: _page
// Description:
// - Build a contiguous ascending history page with inclusive message-ID bounds.
// Parameters:
// - first (int): first message ID.
// - last (int): last message ID; less than first produces an empty page.
// Returns:
// - List<ChatMessage>; generated messages in ascending ID order.
List<ChatMessage> _page(int first, int last) => [
  for (var id = first; id <= last; id++) _message(id),
];

// 클래스명: _HistoryFixture
// 역할: 이력 모델과 가짜 조회·실시간 포트를 함께 소유하는 테스트 fixture.
// 주요 책임:
// - 화면 표시·최신 위치 조건 및 읽음 후처리를 주입하고 모델과 대역의 해제 시점을 분리한다.
// 속성:
// - control (_HistoryControl), realtime (_HistoryRealtime): 조회·실시간 대역.
// - deletedSelections (List<List<int>>): 삭제 시 선택 해제할 ID 목록 기록.
// - model (LinkedChatHistoryViewModel): 연동 17·self 계정의 이력 모델.
// - visible, atLatest (bool): 읽음 처리에 전달할 화면 표시·최신 위치 상태.
// - _modelDisposed (bool): 모델 중복 해제 방지 플래그.
class _HistoryFixture {
  final control = _HistoryControl();
  final realtime = _HistoryRealtime();
  final deletedSelections = <List<int>>[];
  late final LinkedChatHistoryViewModel model;
  bool visible = true;
  bool atLatest = false;
  bool _modelDisposed = false;

  // 함수이름: _HistoryFixture
  // 함수역할:
  // - 현재 표시 상태를 읽는 콜백과 삭제 기록 수집기를 이력 모델에 연결하고 선택적인 읽음 후처리를 주입한다.
  // 매개변수:
  // - onRead (Future<void> Function(int)?): 읽음 경계 처리 후 실행할 비동기 후처리로, null이면 생략한다.
  // 반환값:
  // - _HistoryFixture; 아직 초기 조회를 시작하지 않은 독립 이력 fixture.
  _HistoryFixture({Future<void> Function(int)? onRead}) {
    model = LinkedChatHistoryViewModel(
      linkId: 17,
      userHash: 'self',
      control: control,
      realtime: realtime,
      isVisible: () => visible,
      isAtLatest: () => atLatest,
      onScrollRequested: (_) {},
      onScheduleChanged: () {},
      onDeleted: deletedSelections.add,
      onRead: onRead,
    );
  }

  // Function Name: disposeModel
  // Description:
  // - Dispose the model once while leaving fixture-owned adapters available for ownership assertions.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  void disposeModel() {
    if (_modelDisposed) return;
    _modelDisposed = true;
    model.dispose();
  }

  // Function Name: dispose
  // Description:
  // - Dispose the model, close realtime streams, and then dispose the HTTP control.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after fixture-owned resources are released.
  Future<void> dispose() async {
    disposeModel();
    await realtime.dispose();
    control.dispose();
  }
}

// Class Name: _HistoryControl
// Role: History adapter exposing controllable pages and read acknowledgements.
// Responsibilities:
// - Record request boundaries and receipt IDs while allowing delayed or failed responses.
// Attributes:
// - history (List<ChatMessage>): default page when no handler is installed.
// - unread (ChatUnreadSummary): configured initial unread boundary and count.
// - historyHandler (Future<List<ChatMessage>> Function(int?)?): optional page resolver.
// - readHandler (Future<void> Function(int)?): optional receipt completion/failure handler.
// - historyBoundaries (List<int?>), readIds (List<int>): requested page and read boundaries.
// - disposed (bool): whether control disposal was invoked.
class _HistoryControl extends ManageLinkedChat {
  List<ChatMessage> history = [];
  ChatUnreadSummary unread = const ChatUnreadSummary(count: 0);
  Future<List<ChatMessage>> Function(int? before)? historyHandler;
  Future<void> Function(int id)? readHandler;
  final historyBoundaries = <int?>[];
  final readIds = <int>[];
  bool disposed = false;

  // Function Name: _HistoryControl
  // Description:
  // - Create the history adapter for self using an inert HTTP client.
  // Parameters:
  // - None.
  // Returns:
  // - _HistoryControl; empty observations and a zero-count unread summary.
  _HistoryControl()
    : super(
        userHash: 'self',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  // Function Name: requestHistory
  // Description:
  // - Record the older-page boundary and resolve through the handler when provided, otherwise return the default page.
  // Parameters:
  // - linkId (int), limit (int): accepted conversation and page-size inputs, unused by this fake.
  // - beforeMessageId (int?): boundary recorded and passed to historyHandler; null denotes the latest page.
  // Returns:
  // - Future<List<ChatMessage>>; configured page or handler result/error.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async {
    historyBoundaries.add(beforeMessageId);
    return historyHandler == null ? history : historyHandler!(beforeMessageId);
  }

  // Function Name: requestUnreadSummary
  // Description:
  // - Return the configured unread summary without mutating history.
  // Parameters:
  // - linkId (int): accepted conversation ID, unused by the fake.
  // Returns:
  // - Future<ChatUnreadSummary>; current unread fixture.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async =>
      unread;

  // Function Name: markRead
  // Description:
  // - Record the requested read boundary and await the optional test-controlled handler.
  // Parameters:
  // - linkId (int): accepted conversation ID, unused by this fake.
  // - throughMessageId (int): incoming-message boundary to record and pass to readHandler.
  // Returns:
  // - Future<void>; completes immediately without a handler, otherwise with its completion or error.
  @override
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {
    readIds.add(throughMessageId);
    await readHandler?.call(throughMessageId);
  }

  // Function Name: dispose
  // Description:
  // - Mark the control disposed and delegate inherited resource cleanup.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

// Class Name: _HistoryRealtime
// Role: Socket-free implementation of the chat session transport.
// Responsibilities:
// - Expose broadcast event/state streams and record lifecycle operations without creating timers.
// Attributes:
// - _events (StreamController<Map<String, dynamic>>): broadcast message events.
// - _states (StreamController<LinkedChatConnectionState>): broadcast connection states.
// - starts, stops (int): lifecycle call counts.
// - disposed (bool): guards repeated stream closure.
class _HistoryRealtime implements LinkedChatSessionTransport {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<LinkedChatConnectionState>.broadcast();
  int starts = 0;
  int stops = 0;
  bool disposed = false;

  // Function Name: _HistoryRealtime
  // Description:
  // - Construct a transport with independent broadcast streams and zero lifecycle counts.
  // Parameters:
  // - None.
  // Returns:
  // - _HistoryRealtime; no network or scheduled work.
  _HistoryRealtime();

  // Function Name: events
  // Description:
  // - Expose the controlled realtime message stream.
  // Parameters:
  // - None.
  // Returns:
  // - Stream<Map<String, dynamic>>; broadcast events owned by this fixture.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  // Function Name: states
  // Description:
  // - Expose the manually driven connection-state stream.
  // Parameters:
  // - None.
  // Returns:
  // - Stream<LinkedChatConnectionState>; broadcast state changes.
  @override
  Stream<LinkedChatConnectionState> get states => _states.stream;

  // Function Name: emitState
  // Description:
  // - Publish one connection state through the fake stream.
  // Parameters:
  // - state (LinkedChatConnectionState): state emitted at the chosen test time.
  // Returns:
  // - void; no return value.
  void emitState(LinkedChatConnectionState state) => _states.add(state);

  // Function Name: start
  // Description:
  // - Count transport activation without automatically emitting a connected state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after incrementing starts.
  @override
  Future<void> start() async {
    starts++;
  }

  // Function Name: stop
  // Description:
  // - Count transport suspension without emitting an implicit state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after incrementing stops.
  @override
  Future<void> stop() async {
    stops++;
  }

  // Function Name: dispose
  // Description:
  // - Close both broadcast controllers once; subsequent disposal returns without repeating closure.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after stream closure.
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _events.close();
    await _states.close();
  }
}
