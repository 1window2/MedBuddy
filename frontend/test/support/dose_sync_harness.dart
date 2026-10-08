// File Name: dose_sync_harness.dart
// Role: Attach a real DoseSyncService to a test view model the way main.dart does, so dose taps in
//   tests take the outbox path that production always takes instead of the direct PATCH branch.
//
// Uses the production DoseSyncService and DoseOutboxStore (schema, AES-GCM encryption, leases)
//   on a private in-memory SQLite database opened in the test isolate, so it also runs inside
//   testWidgets without runAsync.
// Records: every operation the service stored (`queued`) and, with the built-in client, every
//   upload request (`uploads`).
// Does not simulate: the backend (uploads answer 503 until a test sets `respond`), WorkManager
//   scheduling, the home widget (scheduleWork and onStateChanged stay at their no-op defaults),
//   the secure-storage key, or widget-button actions, which write to the store without passing
//   through the service and therefore do not appear in `queued`.
//
// Widget tests: the started service keeps a foreground retry timer, and testWidgets checks for
//   pending timers before tear-downs run. End such a test with
//   `await tester.pumpWidget(const SizedBox.shrink()); await harness.close();`.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'json_http.dart';

// Class Name: _RecordingDoseOutboxStore
// Role: Production outbox store that also remembers what the sync service stored.
// Responsibilities:
// - Keep a decoded copy of each operation after the real encrypted insert succeeded.
// Attributes:
// - enqueued (List<Map<String, dynamic>>): Stored operations, oldest first.
class _RecordingDoseOutboxStore extends DoseOutboxStore {
  // Function Name: _RecordingDoseOutboxStore
  // Description: Wraps the given database and key exactly as the production store does.
  // Parameters: db - open outbox database; key - AES-GCM key. Returns: The recording store.
  _RecordingDoseOutboxStore(super.db, super.key);

  final List<Map<String, dynamic>> enqueued = [];

  // Function Name: enqueue
  // Description: Stores the operation with the production code, then records a copy of it.
  // Parameters: owner - account; operation - dose request built by DoseSyncService.record.
  // Returns: Completion; a rejected insert throws and is not recorded.
  @override
  Future<void> enqueue(String owner, Map<String, dynamic> operation) async {
    await super.enqueue(owner, operation);
    enqueued.add(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(operation)) as Map),
    );
  }
}

// Class Name: DoseSyncHarness
// Role: Handle on the dose-sync service that attachTestDoseSync attached to a view model.
// Responsibilities:
// - Expose the operations the service queued and the uploads it attempted.
// - Let a test seed the same-day schedule cache and choose the upload response.
// - Dispose the view model and close the database once, in the test body or at tear-down.
// Attributes:
// - viewModel (MedBuddyViewModel): View model that owns `service` after the attachment.
// - service (DoseSyncService): Production service; also reachable as viewModel.doseSync.
// - store (DoseOutboxStore): Production store on the in-memory database.
// - uploads (List<http.Request>): Requests received by the built-in client, oldest first;
//   stays empty when the test passed its own client.
// - respond (function): Answer of the built-in client; offline (503) until a test replaces it.
class DoseSyncHarness {
  // Function Name: DoseSyncHarness._
  // Description: Bundles the attached collaborators; created only by attachTestDoseSync.
  // Parameters: viewModel, service, store, uploads - see the class attributes.
  // Returns: The harness.
  DoseSyncHarness._(this.viewModel, this.service, this._store, this.uploads);

  final MedBuddyViewModel viewModel;
  final DoseSyncService service;
  final _RecordingDoseOutboxStore _store;
  final List<http.Request> uploads;
  Future<http.Response> Function(http.Request request) respond = _offline;
  bool _closed = false;

  // Function Name: _offline
  // Description: Default upload answer; a 503 keeps every operation in the outbox for retry.
  // Parameters: request - upload request (unused). Returns: A 503 response.
  static Future<http.Response> _offline(http.Request request) async {
    return http.Response('offline', 503);
  }

  // Function Name: store
  // Description: Gives access to the production store, for example to inspect the cache.
  // Parameters: None. Returns: The store backing `service`.
  DoseOutboxStore get store => _store;

  // Function Name: owner
  // Description: Names the account the service was attached for.
  // Parameters: None. Returns: The view model's patient hash.
  String get owner => service.owner;

  // Function Name: queued
  // Description:
  // - Lists every operation the service stored since the attachment, whether or not it has been
  //   uploaded since. Each map carries operation_id, schedule_date, slot_key, medication_ids,
  //   completed, medication_names and, for chat records, link_id.
  // Parameters: None. Returns: An unmodifiable list, oldest first.
  List<Map<String, dynamic>> get queued => List.unmodifiable(_store.enqueued);

  // Function Name: pending
  // Description: Reads the operations still waiting in the outbox, with their `state`.
  // Parameters: None. Returns: The stored operations of `owner`, oldest first.
  Future<List<Map<String, dynamic>>> pending() => _store.pending(owner);

  // Function Name: seedSchedules
  // Description:
  // - Stores a same-day schedule snapshot as a server read would, so the service reports
  //   hasCache and projects queued operations onto these schedules without a schedule request.
  // Parameters: schedules - confirmed schedules for the service clock's current dose day.
  // Returns: Completion after the cache was written.
  Future<void> seedSchedules(List<MedicationSchedule> schedules) {
    return service.cacheSchedules(
      schedules,
      scheduleDate: doseScheduleDay(service.clock()),
    );
  }

  // Function Name: close
  // Description:
  // - Disposes the view model, which disposes the attached service and cancels its retry timer,
  //   then closes the database. Safe to call more than once; attachTestDoseSync also registers
  //   it as a tear-down.
  // Parameters: None. Returns: Completion after the database was closed.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    viewModel.dispose();
    await _store.db.close();
  }
}

// Function Name: attachTestDoseSync
// Description:
// - Open a private in-memory outbox, build a production DoseSyncService for the view model's
//   patient and attach it with MedBuddyViewModel.attachDoseSync, the call main.dart makes.
// - Wait until the store is active and the start-up drain finished, so the test continues from
//   a settled service.
// Parameters:
// - viewModel (MedBuddyViewModel): View model to attach to; the harness disposes it on close.
// - clock (DateTime Function()?): Time source of the service; the real clock when omitted.
// - client (http.Client?): Upload client; when omitted a built-in client records each request
//   in `uploads` and answers with `respond`.
// Returns:
// - Future<DoseSyncHarness>: Handle on the attached service; throws when the store cannot open.
Future<DoseSyncHarness> attachTestDoseSync(
  MedBuddyViewModel viewModel, {
  DateTime Function()? clock,
  http.Client? client,
}) async {
  // The service registers a lifecycle observer when it starts.
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // The no-isolate factory completes on microtasks, which testWidgets' fake clock can drive.
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: DoseOutboxStore.createSchema,
      singleInstance: false,
    ),
  );
  final store = _RecordingDoseOutboxStore(
    db,
    await AesGcm.with256bits().newSecretKey(),
  );
  final uploads = <http.Request>[];
  late final DoseSyncHarness harness;
  final service = DoseSyncService(
    owner: viewModel.patientHash,
    client:
        client ??
        MockClient((request) {
          uploads.add(request);
          return harness.respond(request);
        }),
    openStore: () async => store,
    clock: clock,
  );
  harness = DoseSyncHarness._(viewModel, service, store, uploads);
  addTearDown(harness.close);
  viewModel.attachDoseSync(service);
  await service.initialize(activate: true);
  await service.drain();
  return harness;
}

// Function Name: doseSyncReceipt
// Description:
// - Build the success receipt the backend returns for a completion-operation upload, echoing the
//   operation id and dose day of the request so the service accepts it and clears the operation.
// Parameters:
// - request (http.Request): Upload request received by the client.
// - schedules (List<MedicationSchedule>): Server schedule state after applying the operation.
// Returns:
// - http.Response: 200 JSON receipt with operation_id, schedule_date and data.
http.Response doseSyncReceipt(
  http.Request request,
  List<MedicationSchedule> schedules,
) {
  final operation = jsonDecode(request.body) as Map<String, dynamic>;
  return jsonResponse({
    'operation_id': operation['operation_id'],
    'schedule_date': operation['schedule_date'],
    'data': [for (final schedule in schedules) schedule.toJson()],
  });
}
