// File Name: linked_chat_composer_view_model_test.dart
// Role: Characterizes outgoing payload identity, concurrency and account-scoped disposal.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_draft_entity.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/viewmodels/linked_chat_composer_view_model.dart';

// Function Name: main
// Description: Registers deterministic retry/state tests without widget navigation or live transport.
// Parameters: None. Returns: None.
void main() {
  // Function Name: independent outgoing ownership test
  // Description: Rejects material/boundary/facade/nearby dependencies and transport logic in the UI.
  // Parameters: None. Returns: None.
  test('composer and payload remain independent of widget libraries', () {
    final source = File(
      'lib/viewmodels/linked_chat_composer_view_model.dart',
    ).readAsStringSync();
    final imports = RegExp(
      r'''^import\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!);
    expect(imports, isNot(anyElement(contains('boundaries/'))));
    expect(imports, isNot(contains('package:flutter/material.dart')));
    expect(imports, isNot(anyElement(contains('nearby'))));
    expect(imports, isNot(anyElement(contains('medbuddy_view_model.dart'))));
    expect(source, isNot(contains('part of')));
    final payload = File(
      'lib/entities/chat_message_draft_entity.dart',
    ).readAsStringSync();
    expect(payload, isNot(contains('package:flutter/')));
    expect(payload, isNot(contains('controls/')));
    final ui = File(
      'lib/boundaries/linked_chat_ui_boundary.dart',
    ).readAsStringSync();
    expect(ui, isNot(contains('_control.sendMessage(')));
    expect(ui, isNot(contains('_pendingMedicationIdsSignature')));
  });

  // Function Name: immutable payload and primary-order test
  // Description: Retains caller wire ordering while retries compare normalized text and sorted attachment IDs.
  // Parameters: None. Returns: Asynchronous assertions.
  test(
    'payload is immutable and retries preserve primary medication wire order',
    () async {
      final fixture = _ComposerFixture();
      addTearDown(fixture.dispose);
      final ids = [92, 91];
      final first = ChatMessageDraft(body: '  Hello  ', medicationIds: ids);
      ids.clear();
      expect(() => first.medicationIds.add(9), throwsUnsupportedError);
      await fixture.model.send(first);
      await fixture.model.send(
        ChatMessageDraft(body: 'Hello', medicationIds: [91, 92]),
      );
      expect(fixture.control.calls.map((call) => call.id), [
        'request_1',
        'request_1',
      ]);
      expect(fixture.control.calls.map((call) => call.primaryMedicationId), [
        92,
        91,
      ]);
      expect(fixture.control.calls.first.draft.medicationIds, [92, 91]);
      expect(fixture.control.calls.last.draft.medicationIds, [91, 92]);
      expect(fixture.control.calls.first.draft.body, 'Hello');
      expect(fixture.control.calls.every((call) => call.linkId == 17), isTrue);
    },
  );

  final changedPayloads = {
    'body': ChatMessageDraft(
      body: 'Changed',
      medicationIds: [91],
      slotKey: 'morning',
      pharmacyId: 'P1',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    ),
    'medications': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [92],
      slotKey: 'morning',
      pharmacyId: 'P1',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    ),
    'kind': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [91],
      messageKind: ChatMessageKind.hospitalShare,
      slotKey: 'morning',
      pharmacyId: 'P1',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    ),
    'slot': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [91],
      slotKey: 'evening',
      pharmacyId: 'P1',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    ),
    'pharmacy': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [91],
      slotKey: 'morning',
      pharmacyId: 'P2',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    ),
    'hospital': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [91],
      slotKey: 'morning',
      pharmacyId: 'P1',
      hospitalId: 'H2',
      hospitalScheduleDate: '2026-10-05',
    ),
    'date': ChatMessageDraft(
      body: 'Hello',
      medicationIds: [91],
      slotKey: 'morning',
      pharmacyId: 'P1',
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-06',
    ),
  };
  for (final change in changedPayloads.entries) {
    // Function Name: changed outgoing context test
    // Description: Prevents a different body/attachment/context from reusing the prior failed request ID.
    // Parameters: None. Returns: Asynchronous assertions for this context field.
    test('changed ${change.key} allocates a new retry identity', () async {
      final fixture = _ComposerFixture();
      addTearDown(fixture.dispose);
      await fixture.model.send(
        ChatMessageDraft(
          body: 'Hello',
          medicationIds: [91],
          slotKey: 'morning',
          pharmacyId: 'P1',
          hospitalId: 'H1',
          hospitalScheduleDate: '2026-10-05',
        ),
      );
      await fixture.model.send(change.value);
      expect(fixture.control.calls.map((call) => call.id), [
        'request_1',
        'request_2',
      ]);
    });
  }

  // Function Name: outgoing concurrency test
  // Description: Blocks empty/overlapping sends and clears a successfully acknowledged retry key once.
  // Parameters: None. Returns: Asynchronous assertions.
  test(
    'empty and concurrent sends are rejected without changing pending identity',
    () async {
      final fixture = _ComposerFixture();
      addTearDown(fixture.dispose);
      expect(await fixture.model.send(ChatMessageDraft(body: ' ')), isNull);
      expect(fixture.control.calls, isEmpty);
      final gate = Completer<ChatMessage>();
      fixture.control.gate = gate;
      final draft = ChatMessageDraft(body: 'Hello');
      final states = <bool>[];
      fixture.model.addListener(() => states.add(fixture.model.isSending));
      final pending = fixture.model.send(draft);
      expect(
        await fixture.model.send(ChatMessageDraft(body: 'Overlapping')),
        isNull,
      );
      expect(fixture.model.pendingRequestId, 'request_1');
      expect(fixture.control.calls.length, 1);
      gate.complete(_message('Hello'));
      expect(await pending, isNotNull);
      expect(states, [true, false]);
      expect(fixture.model.sendFailed, isFalse);
      expect(fixture.model.pendingRequestId, isNull);
      fixture.control.gate = null;
      fixture.control.fail = false;
      await fixture.model.send(draft);
      expect(fixture.control.calls.map((call) => call.id), [
        'request_1',
        'request_2',
      ]);
    },
  );

  // Function Name: explicit share identity test
  // Description: Keeps a separately retained care-share ID after another ordinary send fails.
  // Parameters: None. Returns: Asynchronous assertions.
  test('explicit care retry survives an intervening failed message', () async {
    final fixture = _ComposerFixture();
    addTearDown(fixture.dispose);
    final share = ChatMessageDraft(
      body: 'Hospital',
      messageKind: ChatMessageKind.hospitalShare,
      hospitalId: 'H1',
      hospitalScheduleDate: '2026-10-05',
    );
    await fixture.model.send(share);
    final shareId = fixture.model.pendingRequestId;
    expect(fixture.model.sendFailed, isTrue);
    await fixture.model.send(ChatMessageDraft(body: 'Other'));
    fixture.control.fail = false;
    expect(await fixture.model.send(share, requestId: shareId), isNotNull);
    expect(fixture.control.calls.map((call) => call.id), [
      'request_1',
      'request_2',
      'request_1',
    ]);
    expect(fixture.control.calls.last.draft.hospitalScheduleDate, '2026-10-05');
    expect(fixture.model.pendingRequestId, isNull);
  });

  // Function Name: attachment edit retry reset test
  // Description: Explicit attachment edits discard a previous request ID even if content later matches again.
  // Parameters: None. Returns: Asynchronous assertions.
  test(
    'resetting retry identity does not reuse the prior failed send',
    () async {
      final fixture = _ComposerFixture();
      addTearDown(fixture.dispose);
      final draft = ChatMessageDraft(body: 'Hello');
      await fixture.model.send(draft);
      fixture.model.resetRetry();
      expect(fixture.model.pendingRequestId, isNull);
      await fixture.model.send(draft);
      expect(fixture.control.calls.map((call) => call.id), [
        'request_1',
        'request_2',
      ]);
    },
  );

  for (final fails in [false, true]) {
    // Function Name: disposed outgoing completion test
    // Description: Rejects late success/failure and preserves borrowed adapter ownership.
    // Parameters: None. Returns: Asynchronous assertions.
    test(
      'disposed composer ignores late outgoing completion: failure=$fails',
      () async {
        final fixture = _ComposerFixture();
        addTearDown(fixture.dispose);
        final gate = Completer<ChatMessage>();
        fixture.control.gate = gate;
        var notifications = 0;
        fixture.model.addListener(() => notifications++);
        final pending = fixture.model.send(
          ChatMessageDraft(body: 'Old account'),
        );
        fixture.disposeModel();
        if (fails) {
          gate.completeError(StateError('offline'));
        } else {
          gate.complete(_message('Old account'));
        }
        expect(await pending, isNull);
        expect(notifications, 1);
        expect(fixture.control.disposed, isFalse);
        expect(fixture.model.pendingRequestId, isNull);
        expect(
          await fixture.model.send(ChatMessageDraft(body: 'Too late')),
          isNull,
        );
        expect(fixture.control.calls.length, 1);
        expect(fixture.model.createClientMessageId, throwsStateError);
      },
    );
  }

  // Function Name: default wire ID test
  // Description: Keeps the pre-refactor non-sensitive timestamp/random request-ID format.
  // Parameters: None. Returns: None.
  test('default request identity preserves the existing wire format', () {
    final control = _SendControl();
    final composer = LinkedChatComposerViewModel(linkId: 17, control: control);
    addTearDown(composer.dispose);
    addTearDown(control.dispose);
    expect(
      composer.createClientMessageId(),
      matches(RegExp(r'^msg_\d+_[0-9a-f]+$')),
    );
  });
}

// Function Name: _message
// Description: Creates a synthetic accepted message for completion gates.
// Parameters: body: Message content. Returns: A scoped server message.
ChatMessage _message(String body) => ChatMessage(
  messageId: 1,
  linkId: 17,
  senderHash: 'self',
  clientMessageId: 'fixture',
  body: body,
  createdAt: DateTime.utc(2026, 10, 5),
);

// Class Name: _ComposerFixture
// Role: Owns a deterministic outgoing model and its borrowed fake control.
// Responsibilities: Generate predictable IDs and dispose each owner once.
// Attributes: control/model: Isolated scoped collaborators; _nextId: Request identity counter.
class _ComposerFixture {
  final control = _SendControl();
  late final LinkedChatComposerViewModel model;
  int _nextId = 0;
  bool _modelDisposed = false;

  // Function Name: _ComposerFixture
  // Description: Injects request IDs without relying on randomness or wall-clock timing.
  // Parameters: None. Returns: An isolated fixture.
  _ComposerFixture() {
    model = LinkedChatComposerViewModel(
      linkId: 17,
      control: control,
      requestIdFactory: () => 'request_${++_nextId}',
    );
  }

  // Function Name: disposeModel
  // Description: Ends only the scoped outgoing lifetime for late-completion assertions.
  // Parameters: None. Returns: None.
  void disposeModel() {
    if (_modelDisposed) return;
    _modelDisposed = true;
    model.dispose();
  }

  // Function Name: dispose
  // Description: Closes all fixture owners after test completions settle.
  // Parameters: None. Returns: None.
  void dispose() {
    disposeModel();
    control.dispose();
  }
}

// Class Name: _SendControl
// Role: Records outgoing wire arguments and injects failures or deferred acknowledgements.
// Responsibilities: Retain production adapter signatures without network I/O.
// Attributes: calls: Recorded payloads; gate/fail: Completion controls; disposed: Ownership observation.
class _SendControl extends ManageLinkedChat {
  final calls =
      <
        ({
          String id,
          int linkId,
          int? primaryMedicationId,
          ChatMessageDraft draft,
        })
      >[];
  Completer<ChatMessage>? gate;
  bool fail = true;
  bool disposed = false;

  // Function Name: _SendControl
  // Description: Supplies a local HTTP stub while overriding all tested sends.
  // Parameters: None. Returns: A controllable send adapter.
  _SendControl()
    : super(
        userHash: 'self',
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  // Function Name: sendMessage
  // Description: Snapshots wire input and returns the selected completion/failure outcome.
  // Parameters: Existing production message/context/identity fields. Returns: Accepted or gated message; throws on configured failure.
  @override
  Future<ChatMessage> sendMessage({
    int? sourceAlertId,
    required int linkId,
    required String clientMessageId,
    required String body,
    int? medicationId,
    List<int> medicationIds = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    String? hospitalId,
    String? hospitalScheduleDate,
  }) async {
    calls.add((
      id: clientMessageId,
      linkId: linkId,
      primaryMedicationId: medicationId,
      draft: ChatMessageDraft(
        body: body,
        medicationIds: medicationIds,
        messageKind: messageKind,
        slotKey: slotKey,
        pharmacyId: pharmacyId,
        hospitalId: hospitalId,
        hospitalScheduleDate: hospitalScheduleDate,
      ),
    ));
    final pending = gate;
    if (pending != null) return pending.future;
    if (fail) throw StateError('Temporary failure');
    return _message(body);
  }

  // Function Name: dispose
  // Description: Records borrowed-resource disposal for ownership assertions.
  // Parameters: None. Returns: None.
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
