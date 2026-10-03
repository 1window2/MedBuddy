// File Name: linked_chat_history_view_model_test.dart
// Role: Characterizes independent chat recovery, evidence merging, and lifecycle cancellation.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';
import 'package:medbuddy_frontend/viewmodels/linked_chat_history_view_model.dart';

// Function Name: main
// Description: Registers deterministic state-machine tests without real sockets or accounts.
// Parameters: None. Returns: None.
void main() {
  // Enforces transport dependency inversion and rejects widget/navigation/facade coupling.
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

  // Verifies immutable snapshots and monotonic receipt/hiding/tombstone evidence.
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

  // Verifies repeated foreground/reconnect signals share one request and one follow-up.
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

  // Verifies recovery traverses every missed page rather than just the latest fifty messages.
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

  // Verifies a departed session cannot publish, start another page, or close caller-owned adapters.
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

  // Verifies an older page and concurrent realtime messages retain a single stable unread boundary.
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

  // Verifies late older-page completion cannot publish into a disposed owner.
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

  // Verifies acknowledgements require both visibility and latest position, and drain one newer message.
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

  // Verifies failed receipts remain retryable and a late successful receipt never drains after disposal.
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

  // Verifies explicit link mismatches, malformed payloads and foreign send results cannot alter state.
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

  // Uses the widget-test fake clock to prove reconnect noise does not postpone polling.
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
}

// Function Name: _message
// Description: Creates a synthetic message with explicit account/link identity.
// Parameters: id: Message ID; sender/linkId: Scope fields. Returns: A parsed message entity.
ChatMessage _message(int id, {String sender = 'self', int linkId = 17}) =>
    ChatMessage.fromJson(_wireMessage(id, sender: sender, linkId: linkId));

// Function Name: _wireMessage
// Description: Creates a non-sensitive server message payload.
// Parameters: id: Message ID; sender/linkId: Scope fields. Returns: API-shaped data.
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
// Description: Creates a contiguous synthetic history page.
// Parameters: first/last: Inclusive message bounds. Returns: Ordered messages.
List<ChatMessage> _page(int first, int last) => [
  for (var id = first; id <= last; id++) _message(id),
];

// Class Name: _HistoryFixture
// Role: Owns model and fake adapters while exposing controllable presentation ports.
// Responsibilities: Inject visibility/scroll state and cleanly dispose model and borrowed resources.
// Attributes: visible/atLatest: Presentation predicates; control/realtime: Deterministic adapters.
class _HistoryFixture {
  final control = _HistoryControl();
  final realtime = _HistoryRealtime();
  final deletedSelections = <List<int>>[];
  late final LinkedChatHistoryViewModel model;
  bool visible = true;
  bool atLatest = false;
  bool _modelDisposed = false;

  // Function Name: _HistoryFixture
  // Description: Connects a conversation model to independent test presentation ports.
  // Parameters: None. Returns: An isolated history fixture.
  _HistoryFixture() {
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
    );
  }

  // Function Name: disposeModel
  // Description: Ends the conversation lifetime without ending caller-owned adapter lifetimes.
  // Parameters: None. Returns: None.
  void disposeModel() {
    if (_modelDisposed) return;
    _modelDisposed = true;
    model.dispose();
  }

  // Function Name: dispose
  // Description: Cancels all fixture resources after asynchronous completions settle.
  // Parameters: None. Returns: Completion of borrowed transport disposal.
  Future<void> dispose() async {
    disposeModel();
    await realtime.dispose();
    control.dispose();
  }
}

// Class Name: _HistoryControl
// Role: Provides explicit completion gates and records authenticated history/read requests.
// Responsibilities: Supply deterministic pages, unread boundaries, and receipt outcomes.
// Attributes: historyHandler/readHandler: Optional completion/failure ports; request lists: Observed calls.
class _HistoryControl extends ManageLinkedChat {
  List<ChatMessage> history = [];
  ChatUnreadSummary unread = const ChatUnreadSummary(count: 0);
  Future<List<ChatMessage>> Function(int? before)? historyHandler;
  Future<void> Function(int id)? readHandler;
  final historyBoundaries = <int?>[];
  final readIds = <int>[];
  bool disposed = false;

  // Function Name: _HistoryControl
  // Description: Prevents external HTTP use while retaining the production control contract.
  // Parameters: None. Returns: A controllable adapter.
  _HistoryControl()
    : super(
        userHash: 'self',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  // Function Name: requestHistory
  // Description: Records a page boundary and uses the selected completion/failure handler.
  // Parameters: linkId: Conversation; beforeMessageId: Older-page boundary; limit: Page size.
  // Returns: Selected synthetic history page.
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
  // Description: Supplies a stable synthetic pre-read boundary.
  // Parameters: linkId: Conversation. Returns: Current summary.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async =>
      unread;

  // Function Name: markRead
  // Description: Records a receipt and optionally waits/fails under test control.
  // Parameters: linkId: Conversation; throughMessageId: Read boundary. Returns: Receipt completion.
  @override
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {
    readIds.add(throughMessageId);
    await readHandler?.call(throughMessageId);
  }

  // Function Name: dispose
  // Description: Records disposal to verify borrowed-resource ownership.
  // Parameters: None. Returns: None.
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

// Class Name: _HistoryRealtime
// Role: Emits transport state without creating sockets or timers.
// Responsibilities: Record foreground/background ownership and expose deterministic streams.
// Attributes: _events/_states: Event ports; starts/stops/disposed: Lifecycle observations.
class _HistoryRealtime implements LinkedChatSessionTransport {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<LinkedChatConnectionState>.broadcast();
  int starts = 0;
  int stops = 0;
  bool disposed = false;

  // Function Name: _HistoryRealtime
  // Description: Implements only the transport contract, with no HTTP or socket dependencies.
  // Parameters: None. Returns: A socket-free service.
  _HistoryRealtime();

  // Function Name: events
  // Description: Exposes the fake message stream.
  // Parameters: None. Returns: Borrowed event stream.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  // Function Name: states
  // Description: Exposes manually controlled connection states.
  // Parameters: None. Returns: Borrowed state stream.
  @override
  Stream<LinkedChatConnectionState> get states => _states.stream;

  // Function Name: emitState
  // Description: Sends a connection state at the test-selected time.
  // Parameters: state: Connection state. Returns: None.
  void emitState(LinkedChatConnectionState state) => _states.add(state);

  // Function Name: start
  // Description: Records transport start without implicit connection events.
  // Parameters: None. Returns: Completed start.
  @override
  Future<void> start() async {
    starts++;
  }

  // Function Name: stop
  // Description: Records background transport stop.
  // Parameters: None. Returns: Completed stop.
  @override
  Future<void> stop() async {
    stops++;
  }

  // Function Name: dispose
  // Description: Closes fixture-owned stream/client resources once.
  // Parameters: None. Returns: Disposal completion.
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _events.close();
    await _states.close();
  }
}
