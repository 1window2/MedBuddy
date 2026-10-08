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

const _owner = 'patient-a';
const _day = '2026-09-21';
final _now = DateTime.utc(2026, 9, 21, 3); // 12:00 on the dose day (UTC+9)

const _twoSlotMedication = MedicationSchedule(
  medicationID: '91',
  medicationName: '테스트정',
  dosage: '1정',
  scheduleSlotKeys: ['morning', 'evening'],
);
const _eveningMedication = MedicationSchedule(
  medicationID: '92',
  medicationName: '저녁정',
  dosage: '0.5정',
  scheduleSlotKeys: ['evening'],
);

// Function Name: _selected
// Description: Builds one selected medication with the slots the patient ticked.
// Parameters: id - medication ID; name - display name; slots - selected slot keys.
// Returns: The selection entry.
ChatMedicationContext _selected(int id, String name, List<String> slots) =>
    ChatMedicationContext(
      medicationId: id,
      medicationName: name,
      scheduleSlotKeys: slots,
    );

// Function Name: _viewModel
// Description: Creates a session view model that reaches no server and no notification plugin.
// Parameters: owner - account of the view model. Returns: The view model.
MedBuddyViewModel _viewModel([String owner = _owner]) => MedBuddyViewModel(
  patientHash: owner,
  apiClient: MockClient(
    (_) async => jsonResponse({'detail': 'unused'}, status: 404),
  ),
  notificationService: RecordingNotificationService(),
);

// Class Name: _ChatControl
// Role: Chat adapter fake for the direct-endpoint fallback and the server slot contexts.
// Attributes: takenRequestIds/takenSlots - recorded fallback writes; failures - number of
//   leading fallback writes that fail; contexts - server slot contexts; contextRequests -
//   number of server context reads.
class _ChatControl extends ManageLinkedChat {
  // Function Name: _ChatControl
  // Description: Creates the fake for the patient account without a reachable server.
  // Parameters: None. Returns: The chat fake.
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
  // Description: Returns the configured server slot contexts and counts the read.
  // Parameters: linkId - conversation (unused). Returns: The contexts.
  @override
  Future<List<ChatScheduleContext>> requestScheduleContexts({
    required int linkId,
  }) async {
    contextRequests += 1;
    return contexts;
  }

  // Function Name: recordMedicationTaken
  // Description: Records the request and fails while `failures` is positive.
  // Parameters: linkId, clientMessageId, scheduleDate, slotKey, medicationIds - the request.
  // Returns: A confirmation message and the morning dose as completed; throws while failing.
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
// Description: Creates a recorder for link 17 whose fallback request IDs count up from 1.
// Parameters: control - chat fake; user - signed-in account of the chat.
// Returns: The recorder.
LinkedChatDoseRecorder _recorder(_ChatControl control, {String user = _owner}) {
  var next = 0;
  return LinkedChatDoseRecorder(
    linkId: 17,
    currentUserHash: user,
    control: control,
    createRequestId: () => 'request_${++next}',
  );
}

const _morningRequest = ChatDoseRequest(
  scheduleDate: _day,
  slotKey: 'morning',
  medicationIds: [91],
  medicationNames: ['테스트정'],
);

// Class Name: _FailsAfterStoringSyncService
// Role: Production dose-sync service that reports a failure after the operation was stored,
//   the way a failing refresh after the insert would.
// Attributes: failNext - whether the next record call throws after storing.
class _FailsAfterStoringSyncService extends DoseSyncService {
  // Function Name: _FailsAfterStoringSyncService
  // Description: Builds the service on the given store with the fixed test clock.
  // Parameters: store - open outbox store. Returns: The service.
  _FailsAfterStoringSyncService(DoseOutboxStore store)
    : super(
        owner: _owner,
        client: MockClient((_) async => http.Response('offline', 503)),
        openStore: () async => store,
        clock: () => _now,
      );

  bool failNext = true;

  // Function Name: record
  // Description: Stores the operation with the production code, then throws once.
  // Parameters: Same as DoseSyncService.record. Returns: The production result when not failing.
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
// Description: Registers the planning and recording tests.
// Parameters: None. Returns: None.
void main() {
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

    // The cache mapping keeps slot membership and drops entries without a numeric ID.
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

    // One request per selected slot; only the ticked slots of a multi-slot medication.
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

    // A multi-slot medication selected for the evening only is not recorded for the morning.
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

    // Nothing is planned when any selected dose is no longer in the schedule of that day.
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

    // A selection without any slot has nothing to confirm.
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

  group('record through the outbox', () {
    // The production path: one stored operation carrying the link, nothing sent to the chat
    // endpoint, and the selection day taken from the same cache the plan is checked against.
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

    // A failed local write throws so the screen keeps the selection; the retry stores it once.
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

    // A failure reported after the operation was stored must not make a retry store it again:
    // each stored operation becomes a dose record and a chat message on the server.
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

    // The outbox of another account is never written; the server decides for the signed-in
    // account through the chat endpoint instead.
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

    // An offline upload is retried by the outbox with the same operation ID; the chat never
    // stores a second operation for it.
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

    // When the server list cannot be loaded the cached schedule is offered for selection,
    // with the slot keys and without entries that have no server ID.
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

  group('record without an outbox', () {
    // The fallback keeps one request ID per dose until that request succeeded.
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

    // Server-confirmed schedules update the shared schedule only for the same account.
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

    // Without a cache the selection day and the validation both come from the server.
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
