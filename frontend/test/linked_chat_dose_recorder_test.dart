// File Name: linked_chat_dose_recorder_test.dart
// Role: Verifies how a chat "taken" confirmation is planned and recorded: validation against
//   the selected day, the outbox path production takes, and the direct-endpoint fallback.
// Outbox cases run the production DoseSyncService and DoseOutboxStore on in-memory SQLite.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/linked_chat_dose_recorder.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_notification_service.dart';
import 'support/json_http.dart';

// Fixed patient and dose day shared by the outbox and direct-endpoint fixtures.
const _owner = 'patient-a';
const _day = '2026-09-21';
final _now = DateTime.utc(2026, 9, 21, 3); // 12:00 on the dose day (UTC+9)

// One stored medication with independently selectable morning and evening doses.
const _twoSlotMedication = MedicationSchedule(
  medicationID: '91',
  medicationName: '테스트정',
  dosage: '1정',
  scheduleSlotKeys: ['morning', 'evening'],
);
// A second medication used to distinguish evening-only selections from the first drug.
const _eveningMedication = MedicationSchedule(
  medicationID: '92',
  medicationName: '저녁정',
  dosage: '0.5정',
  scheduleSlotKeys: ['evening'],
);

// Function Name: _selected
// Description:
// - Build one medication selection with exactly the slots chosen by the patient.
// Parameters:
// - id (int): server medication ID.
// - name (String): display name retained in the planned request.
// - slots (List<String>): selected slot keys, including an empty list for no-schedule cases.
// Returns:
// - ChatMedicationContext; selected medication without additional slot inference.
ChatMedicationContext _selected(int id, String name, List<String> slots) =>
    ChatMedicationContext(
      medicationId: id,
      medicationName: name,
      scheduleSlotKeys: slots,
    );

// Function Name: _viewModel
// Description:
// - Create a session view model with a recording notification service and a mock client returning 404.
// Parameters:
// - owner (String): patient account, defaulting to patient-a; other values exercise account isolation.
// Returns:
// - MedBuddyViewModel; no live server or notification plugin is used.
MedBuddyViewModel _viewModel([String owner = _owner]) => MedBuddyViewModel(
  patientHash: owner,
  apiClient: MockClient(
    (_) async => jsonResponse({'detail': 'unused'}, status: 404),
  ),
  notificationService: RecordingNotificationService(),
);

// Class Name: _ChatControl
// Role: Direct-recording adapter with configurable server schedule contexts.
// Responsibilities:
// - Record fallback request IDs and slots, fail a chosen number of leading writes, and return a deterministic confirmation.
// Attributes:
// - takenRequestIds, takenSlots (List<String>): fallback write identifiers and slots in call order.
// - failures (int): remaining writes that throw StateError.
// - contexts (List<ChatScheduleContext>): configured server schedule response.
// - contextRequests (int): number of context reads.
class _ChatControl extends ManageLinkedChat {
  // Function Name: _ChatControl
  // Description:
  // - Initialize the chat fake for patient-a using an inert mock client.
  // Parameters:
  // - None.
  // Returns:
  // - _ChatControl; empty logs and contexts with no requested failures.
  _ChatControl()
    : super(
        userHash: _owner,
        client: MockClient((_) async => http.Response('{}', 200)),
      );

  final List<String> takenRequestIds = [];
  final List<String> takenSlots = [];
  int failures = 0;
  List<ChatScheduleContext> contexts = const [];
  int contextRequests = 0;

  // Function Name: requestScheduleContexts
  // Description:
  // - Count the read and return the configured server schedule contexts.
  // Parameters:
  // - linkId (int): accepted conversation scope, unused by this fake.
  // Returns:
  // - Future<List<ChatScheduleContext>>; the contexts list unchanged.
  @override
  Future<List<ChatScheduleContext>> requestScheduleContexts({
    required int linkId,
  }) async {
    contextRequests += 1;
    return contexts;
  }

  // Function Name: recordMedicationTaken
  // Description:
  // - Record request identity and slot, throw while failures remain, otherwise return a message and a fixed completed morning schedule.
  // Parameters:
  // - linkId (int): conversation ID copied to the returned message.
  // - clientMessageId (String): recorded request identity and returned message ID.
  // - scheduleDate (String): accepted dose date, unused by the fixed response.
  // - slotKey (String): slot appended to the write log.
  // - medicationIds (List<int>): accepted selection, unused by the fixed response.
  // Returns:
  // - Future<ChatMedicationTakenResult>; deterministic confirmation after failures reach zero; earlier attempts throw StateError.
  @override
  Future<ChatMedicationTakenResult> recordMedicationTaken({
    required int linkId,
    required String clientMessageId,
    required String scheduleDate,
    required String slotKey,
    required List<int> medicationIds,
  }) async {
    takenRequestIds.add(clientMessageId);
    takenSlots.add(slotKey);
    if (failures > 0) {
      failures -= 1;
      throw StateError('offline');
    }
    return ChatMedicationTakenResult(
      message: ChatMessage(
        messageId: 100 + takenRequestIds.length,
        linkId: linkId,
        senderHash: _owner,
        clientMessageId: clientMessageId,
        body: 'recorded',
        createdAt: DateTime.utc(2026, 9, 21),
      ),
      schedules: const [
        MedicationSchedule(
          medicationID: '91',
          medicationName: '테스트정',
          scheduleSlotKeys: ['morning'],
          slotStatuses: {'morning': true},
        ),
      ],
    );
  }
}

// Function Name: _recorder
// Description:
// - Create a link-17 recorder whose direct-send request IDs increment deterministically.
// Parameters:
// - control (_ChatControl): server-context and direct-recording fake.
// - user (String): active chat account, default patient-a.
// Returns:
// - LinkedChatDoseRecorder; fallback IDs start at request_1.
LinkedChatDoseRecorder _recorder(_ChatControl control, {String user = _owner}) {
  var next = 0;
  return LinkedChatDoseRecorder(
    linkId: 17,
    currentUserHash: user,
    control: control,
    createRequestId: () => 'request_${++next}',
  );
}

// Explicit morning selection used to compare direct API writes and durable outbox writes.
const _morningRequest = ChatDoseRequest(
  scheduleDate: _day,
  slotKey: 'morning',
  medicationIds: [91],
  medicationNames: ['테스트정'],
);

// Class Name: _FailsAfterStoringSyncService
// Role: Dose-sync service that simulates failure after a successful local insert.
// Responsibilities:
// - Use production storage first, then throw once to test recognition of an already-recorded operation.
// Attributes:
// - failNext (bool): initially true; cleared when the first post-insert exception is thrown.
class _FailsAfterStoringSyncService extends DoseSyncService {
  // Function Name: _FailsAfterStoringSyncService
  // Description:
  // - Bind production dose synchronization to the supplied store, fixed patient clock, and a transport returning 503.
  // Parameters:
  // - store (DoseOutboxStore): open local outbox used by the service.
  // Returns:
  // - _FailsAfterStoringSyncService; first completed record call is configured to throw after storage.
  _FailsAfterStoringSyncService(DoseOutboxStore store)
    : super(
        owner: _owner,
        client: MockClient((_) async => http.Response('offline', 503)),
        openStore: () async => store,
        clock: () => _now,
      );

  bool failNext = true;

  // Function Name: record
  // Description:
  // - Forward all recording inputs to production storage, then throw once after the insert; subsequent calls return its result.
  // Parameters:
  // - medicationIds (List<int>): medications to record.
  // - slotKey (String): target scheduled slot.
  // - completed (bool): requested completion state.
  // - scheduleDate (String?): explicit dose date, or the service default when null.
  // - linkId (int?): optional linked conversation.
  // - medicationNames (List<String>): display names retained with the operation, default empty.
  // Returns:
  // - Future<bool>; production storage result after the injected failure; the first completed write throws StateError.
  @override
  Future<bool> record({
    required List<int> medicationIds,
    required String slotKey,
    required bool completed,
    String? scheduleDate,
    int? linkId,
    List<String> medicationNames = const [],
  }) async {
    final stored = await super.record(
      medicationIds: medicationIds,
      slotKey: slotKey,
      completed: completed,
      scheduleDate: scheduleDate,
      linkId: linkId,
      medicationNames: medicationNames,
    );
    if (failNext) {
      failNext = false;
      throw StateError('refresh after the insert failed');
    }
    return stored;
  }
}

// Function Name: main
// Description:
// - Register dose planning, local outbox persistence/recovery, and direct-endpoint fallback tests.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // Function Name: plan
  // Description:
  // - Build a four-slot context fixture from cached medications and register selection-validation tests, including local nonnumeric IDs.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  group('plan', () {
    final contexts = LinkedChatDoseRecorder.contextsFromDoseCache(const [
      _twoSlotMedication,
      _eveningMedication,
      // A locally added entry without a server ID cannot be recorded from chat.
      MedicationSchedule(
        medicationID: 'local-entry',
        medicationName: '수동 입력',
        scheduleSlotKeys: ['morning'],
      ),
    ], _day);

    // Function Name: the dose cache becomes four dated slot contexts
    // Description:
    // - Map the cache into four dated slots, retaining slot membership and total counts while excluding nonnumeric local entries from selectable medications.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('the dose cache becomes four dated slot contexts', () {
      expect(contexts.map((context) => context.slotKey), [
        'morning',
        'lunch',
        'evening',
        'bedtime',
      ]);
      expect(contexts.map((context) => context.scheduleDate).toSet(), {_day});
      expect(contexts[0].medications.map((m) => m.medicationId), [91]);
      expect(contexts[0].totalCount, 2);
      expect(contexts[1].medications, isEmpty);
      expect(contexts[2].medications.map((m) => m.medicationId), [91, 92]);
      expect(contexts[2].medications.first.scheduleSlotKeys, [
        'morning',
        'evening',
      ]);
    });

    // Function Name: a selection becomes one request per selected slot in slot order
    // Description:
    // - Group selected medications into one request per slot in canonical slot order, with stable ID signatures and display names retained.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('a selection becomes one request per selected slot in slot order', () {
      final plan = LinkedChatDoseRecorder.plan(
        [
          _selected(92, '저녁정', ['evening']),
          _selected(91, '테스트정', ['evening', 'morning']),
        ],
        _day,
        contexts,
      );
      expect(plan.status, ChatDosePlanStatus.ready);
      expect(plan.requests.map((request) => request.signature), [
        '$_day:morning:91',
        '$_day:evening:91,92',
      ]);
      expect(plan.requests.first.medicationNames, ['테스트정']);
      expect(plan.requests.last.medicationNames, ['저녁정', '테스트정']);
    });

    // Function Name: a selection with an as-needed medication records nothing
    // Description:
    // - Reject an entire selection containing a PRN medication, whether alone or mixed with a scheduled medicine, instead of partially recording it.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('a selection with an as-needed medication records nothing', () {
      const asNeeded = ChatMedicationContext(
        medicationId: 93,
        medicationName: '진통제',
        dosingMode: 'as_needed',
      );
      for (final selected in [
        [asNeeded],
        [
          asNeeded,
          _selected(91, '테스트정', ['evening']),
        ],
      ]) {
        final plan = LinkedChatDoseRecorder.plan(selected, _day, contexts);
        expect(plan.status, ChatDosePlanStatus.asNeededSelected);
        expect(plan.requests, isEmpty);
      }
    });

    // Function Name: unselected slots of a selected medication are left out
    // Description:
    // - A medicine selected only for evening produces no request for its unselected morning slot.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('unselected slots of a selected medication are left out', () {
      final plan = LinkedChatDoseRecorder.plan(
        [
          _selected(91, '테스트정', ['evening']),
        ],
        _day,
        contexts,
      );
      expect(plan.requests.single.signature, '$_day:evening:91');
    });

    // Function Name: a stale selection is rejected as a whole
    // Description:
    // - Reject the complete selection when its date is missing or stale or a selected medicine has left the schedule; never create a partial request.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('a stale selection is rejected as a whole', () {
      final selection = [
        _selected(91, '테스트정', ['morning']),
        _selected(92, '저녁정', ['evening']),
      ];
      // The day rolled over after the selection was made.
      expect(
        LinkedChatDoseRecorder.plan(selection, '2026-09-20', contexts).status,
        ChatDosePlanStatus.scheduleChanged,
      );
      // The evening medication was removed from the schedule.
      final withoutEvening = LinkedChatDoseRecorder.contextsFromDoseCache(
        const [_twoSlotMedication],
        _day,
      );
      final plan = LinkedChatDoseRecorder.plan(selection, _day, withoutEvening);
      expect(plan.status, ChatDosePlanStatus.scheduleChanged);
      expect(plan.requests, isEmpty);
      // No selected day at all.
      expect(
        LinkedChatDoseRecorder.plan(selection, null, contexts).status,
        ChatDosePlanStatus.scheduleChanged,
      );
    });

    // Function Name: a selection without slots has no confirmable schedule
    // Description:
    // - An empty medication selection or a selected medication with no slots yields noSchedule rather than a confirmable plan.
    // Parameters:
    // - None.
    // Returns:
    // - void; assertion failures fail the case.
    test('a selection without slots has no confirmable schedule', () {
      expect(
        LinkedChatDoseRecorder.plan(
          [_selected(91, '테스트정', const [])],
          _day,
          contexts,
        ).status,
        ChatDosePlanStatus.noSchedule,
      );
      expect(
        LinkedChatDoseRecorder.plan(const [], _day, contexts).status,
        ChatDosePlanStatus.noSchedule,
      );
    });
  });

  // Function Name: record through the outbox
  // Description:
  // - Register tests using production dose synchronization and an in-memory outbox for persistence, failure, retry, and account isolation.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  group('record through the outbox', () {
    // Function Name: a dose is stored once with the link and the selected day
    // Description:
    // - Record the selected evening dose once through the local outbox with its original date and link, without direct chat writes; project evening taken while leaving morning untaken.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('a dose is stored once with the link and the selected day', () async {
      final viewModel = _viewModel();
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules(const [_twoSlotMedication]);
      final control = _ChatControl();
      final recorder = _recorder(control);

      expect(recorder.selectionDay(viewModel, const []), _day);
      final contexts = await recorder.loadScheduleContexts(viewModel);
      expect(control.contextRequests, 0);
      final plan = LinkedChatDoseRecorder.plan(
        [
          _selected(91, '테스트정', ['evening']),
        ],
        _day,
        contexts,
      );
      final message = await recorder.record(
        plan.requests.single,
        viewModel: viewModel,
      );

      expect(message, isNull);
      expect(control.takenRequestIds, isEmpty);
      final operation = harness.queued.single;
      expect(operation['schedule_date'], _day);
      expect(operation['slot_key'], 'evening');
      expect(operation['medication_ids'], [91]);
      expect(operation['completed'], isTrue);
      expect(operation['link_id'], 17);
      expect(operation['medication_names'], ['테스트정']);
      // The projected schedule shows the evening dose as taken, the morning dose not.
      final projected = harness.service.schedules.single;
      expect(projected.isSlotCompleted('evening'), isTrue);
      expect(projected.isSlotCompleted('morning'), isFalse);
      await harness.close();
    });

    // Function Name: a failed store write queues nothing and the retry queues once
    // Description:
    // - A SQLite insert rejection leaves no queued or pending operation; removing the failure and retrying creates exactly one stored dose.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('a failed store write queues nothing and the retry queues once', () async {
      final viewModel = _viewModel();
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules(const [_twoSlotMedication]);
      final recorder = _recorder(_ChatControl());
      await harness.store.db.execute(
        'CREATE TRIGGER reject_insert BEFORE INSERT ON operations '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );

      await expectLater(
        recorder.record(_morningRequest, viewModel: viewModel),
        throwsA(anything),
      );
      expect(harness.queued, isEmpty);
      expect(await harness.pending(), isEmpty);

      await harness.store.db.execute('DROP TRIGGER reject_insert');
      await recorder.record(_morningRequest, viewModel: viewModel);
      expect(harness.queued, hasLength(1));
      expect(await harness.pending(), hasLength(1));
      await harness.close();
    });

    // Function Name: a failure after the insert counts as stored
    // Description:
    // - A service failure after insertion still counts as a successful local recording, leaving one morning operation with the conversation ID.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('a failure after the insert counts as stored', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: DoseOutboxStore.createSchema,
          singleInstance: false,
        ),
      );
      addTearDown(db.close);
      final store = DoseOutboxStore(
        db,
        await AesGcm.with256bits().newSecretKey(),
      );
      final service = _FailsAfterStoringSyncService(store);
      final viewModel = _viewModel()..doseSync = service;
      addTearDown(viewModel.dispose);
      await service.initialize(activate: true);
      final recorder = _recorder(_ChatControl());

      await recorder.record(_morningRequest, viewModel: viewModel);

      final pending = await store.pending(_owner);
      expect(pending, hasLength(1));
      expect(pending.single['slot_key'], 'morning');
      expect(pending.single['link_id'], 17);
    });

    // Function Name: another account\'s outbox is not used
    // Description:
    // - Do not read or write another account's outbox or schedule; use server contexts and the direct recording fallback instead.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('another account\'s outbox is not used', () async {
      final viewModel = _viewModel('other-account');
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules(const [_twoSlotMedication]);
      final control = _ChatControl();
      final recorder = _recorder(control);

      expect(recorder.cachedMedicationContexts(viewModel), isNull);
      await recorder.loadScheduleContexts(viewModel);
      expect(control.contextRequests, 1);
      final message = await recorder.record(
        _morningRequest,
        viewModel: viewModel,
      );

      expect(message, isNotNull);
      expect(harness.queued, isEmpty);
      expect(control.takenSlots, ['morning']);
      // The other account's schedule is left untouched as well.
      expect(viewModel.todayMedicationScheduleList, isEmpty);
      await harness.close();
    });

    // Function Name: the outbox retries an upload with one operation ID
    // Description:
    // - A failed upload remains pending and retries with the same operation ID and link; a receipt clears it without creating another local operation.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('the outbox retries an upload with one operation ID', () async {
      final viewModel = _viewModel();
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      await harness.seedSchedules(const [_twoSlotMedication]);
      final recorder = _recorder(_ChatControl());

      await recorder.record(_morningRequest, viewModel: viewModel);
      await harness.service.drain();
      expect(await harness.pending(), hasLength(1));

      harness.respond = (request) async => doseSyncReceipt(request, const [
        MedicationSchedule(
          medicationID: '91',
          medicationName: '테스트정',
          scheduleSlotKeys: ['morning', 'evening'],
          slotStatuses: {'morning': true, 'evening': false},
        ),
      ]);
      await harness.service.drain();

      expect(await harness.pending(), isEmpty);
      expect(harness.queued, hasLength(1));
      final uploadedIds = {
        for (final upload in harness.uploads)
          (jsonDecode(upload.body) as Map)['operation_id'],
      };
      expect(harness.uploads.length, greaterThanOrEqualTo(2));
      expect(uploadedIds, {harness.queued.single['operation_id']});
      expect(
        (jsonDecode(harness.uploads.last.body) as Map)['link_id'],
        17,
      );
      await harness.close();
    });

    // Function Name: the cache supplies selectable medications
    // Description:
    // - Before seeding, cached selections are unavailable; afterward they retain numeric IDs, dosage, and slots while excluding local nonnumeric entries.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('the cache supplies selectable medications', () async {
      final viewModel = _viewModel();
      final harness = await attachTestDoseSync(viewModel, clock: () => _now);
      final recorder = _recorder(_ChatControl());
      expect(recorder.cachedMedicationContexts(viewModel), isNull);

      await harness.seedSchedules(const [
        _twoSlotMedication,
        MedicationSchedule(
          medicationID: 'local-entry',
          medicationName: '수동 입력',
          scheduleSlotKeys: ['morning'],
        ),
      ]);
      final cached = recorder.cachedMedicationContexts(viewModel)!;
      expect(cached.single.medicationId, 91);
      expect(cached.single.dosagePerTime, '1정');
      expect(cached.single.scheduleSlotKeys, ['morning', 'evening']);
      await harness.close();
    });
  });

  // Function Name: record without an outbox
  // Description:
  // - Register fallback-recording tests without a local outbox, covering stable retry IDs, account-scoped schedule updates, and server dates.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  group('record without an outbox', () {
    // Function Name: a failed request is retried with the same request ID
    // Description:
    // - Reuse one direct-request ID through two failures and successful retry; a later independent confirmation receives the next request ID.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('a failed request is retried with the same request ID', () async {
      final control = _ChatControl()..failures = 2;
      final recorder = _recorder(control);

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          recorder.record(_morningRequest),
          throwsStateError,
        );
      }
      final message = await recorder.record(_morningRequest);
      expect(message!.clientMessageId, 'request_1');
      expect(control.takenRequestIds, ['request_1', 'request_1', 'request_1']);

      // A later confirmation of the same dose is a new request.
      await recorder.record(_morningRequest);
      expect(control.takenRequestIds.last, 'request_2');
    });

    // Function Name: confirmed schedules reach only the same account\'s view model
    // Description:
    // - Apply server-confirmed schedules only to a view model for the recorder's account, leaving another account's schedule untouched.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('confirmed schedules reach only the same account\'s view model', () async {
      final control = _ChatControl();
      final own = _viewModel();
      addTearDown(own.dispose);
      final other = _viewModel('other-account');
      addTearDown(other.dispose);

      await _recorder(control).record(_morningRequest, viewModel: other);
      expect(other.todayMedicationScheduleList, isEmpty);

      await _recorder(control).record(_morningRequest, viewModel: own);
      expect(
        own.todayMedicationScheduleList.single.isSlotCompleted('morning'),
        isTrue,
      );
    });

    // Function Name: the server contexts name the selection day
    // Description:
    // - Without a local view model, derive the selection day and contexts from the server response and report no cached medication selection.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    test('the server contexts name the selection day', () async {
      final control = _ChatControl()
        ..contexts = const [
          ChatScheduleContext(
            scheduleDate: '2026-09-22',
            slotKey: 'morning',
            alarmTime: '08:00',
            alarmEnabled: true,
            completedCount: 0,
            totalCount: 1,
            medications: [
              ChatMedicationContext(medicationId: 91, medicationName: '테스트정'),
            ],
          ),
        ];
      final recorder = _recorder(control);
      expect(recorder.selectionDay(null, control.contexts), '2026-09-22');
      expect(await recorder.loadScheduleContexts(null), control.contexts);
      expect(recorder.cachedMedicationContexts(null), isNull);
    });
  });
}
