// File Name: dose_home_widget_service_test.dart
// Role: Verifies durable widget actions, single-upload background refresh, idle-work skipping and account cleanup.
// Real SQLite/crypto and the production DoseSyncService; the widget plugin, WorkManager and the
//   notification plugin are replaced by recording substitutes. No production accounts or records.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/composition/dose_home_widget_background.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/json_http.dart';

// Class Name: _RecordingWidgetPlatform
// Role: Records widget publication, journal consumption and background side effects.
// Responsibilities: Simulates installation checks and cancellation failures while sharing the encrypted test store and HTTP client.
// Attributes: store/client are shared resources; journal stores pending clicks; installed and failure flags control behavior. savedStates, scheduledUpdates, cancelledReminders and registered record calls; openedClients/cancelledScheduledUpdates count resource requests.
class _RecordingWidgetPlatform extends DoseHomeWidgetPlatform {
  // Function Name: _RecordingWidgetPlatform
  // Description:
  // - Connects widget operations to the shared test store and client.
  // Parameters:
  // - store (DoseOutboxStore): Encrypted fixture store.
  // - client (http.Client): Client returned by openClient; owned by test cleanup.
  // Returns:
  // - A recording platform with no published states.
  _RecordingWidgetPlatform(this.store, this.client);

  final DoseOutboxStore store;
  final http.Client client;
  String journal = '[]';
  bool installed = true;
  bool failInstalledLookup = false;
  bool failReminderCancel = false;
  final List<Map<String, dynamic>> savedStates = [];
  final List<DateTime> scheduledUpdates = [];
  final List<({String owner, String slotKey, DateTime date})>
  cancelledReminders = [];
  final List<String> registered = [];
  int openedClients = 0;
  int cancelledScheduledUpdates = 0;

  // Function Name: supported
  // Description:
  // - Enables widget paths independently of the host OS.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Always true.
  @override
  bool get supported => true;

  // Function Name: readJournal
  // Description:
  // - Reads pending platform clicks without consuming them.
  // Parameters:
  // - None.
  // Returns:
  // - Future<String?>: Current journal JSON.
  @override
  Future<String?> readJournal() async => journal;

  // Function Name: saveState
  // Description:
  // - Decodes a published state and appends a separate map to the publication log.
  // Parameters:
  // - state (String): JSON object produced by the widget service.
  // Returns:
  // - Future<void>: Completes after recording; malformed JSON or a non-map fails.
  @override
  Future<void> saveState(String state) async {
    savedStates.add(Map<String, dynamic>.from(jsonDecode(state) as Map));
  }

  // Function Name: updateWidget
  // Description:
  // - Removes journal clicks whose tokens appear in the last published handled list.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes journal reconciliation; requires at least one published state and valid journal JSON.
  @override
  Future<void> updateWidget() async {
    final handled = (savedStates.last['handled'] as List? ?? []).toSet();
    journal = jsonEncode([
      for (final entry in (jsonDecode(journal) as List).whereType<Map>())
        if (!handled.contains(entry['token'])) entry,
    ]);
  }

  // Function Name: scheduleUpdate
  // Description:
  // - Records the next requested widget refresh time without scheduling OS work.
  // Parameters:
  // - at (DateTime): Requested refresh time.
  // Returns:
  // - Future<void>: Completes after recording at.
  @override
  Future<void> scheduleUpdate(DateTime at) async => scheduledUpdates.add(at);

  // Function Name: cancelScheduledUpdates
  // Description:
  // - Counts cancellation of future widget updates without contacting the platform.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes after incrementing the cancellation counter.
  @override
  Future<void> cancelScheduledUpdates() async => cancelledScheduledUpdates++;

  // Function Name: hasInstalledWidget
  // Description:
  // - Returns the configured installation state or simulates a lookup failure.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool>: installed; throws StateError when failInstalledLookup is set.
  @override
  Future<bool> hasInstalledWidget() async {
    if (failInstalledLookup) throw StateError('widget lookup unavailable');
    return installed;
  }

  // Function Name: openStore
  // Description:
  // - Returns the shared encrypted store without reopening it.
  // Parameters:
  // - None.
  // Returns:
  // - Future<DoseOutboxStore>: The constructor-supplied store.
  @override
  Future<DoseOutboxStore> openStore() async => store;

  // Function Name: cancelReminder
  // Description:
  // - Records owner, slot and date only when simulated platform cancellation succeeds.
  // Parameters:
  // - owner (String): Reminder account.
  // - slotKey (String): Completed dose slot.
  // - date (DateTime): Reminder date.
  // Returns:
  // - Future<void>: Completes after recording, or throws StateError when failReminderCancel is set.
  @override
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {
    if (failReminderCancel) throw StateError('notification plugin unavailable');
    cancelledReminders.add((owner: owner, slotKey: slotKey, date: date));
  }

  // Function Name: registerSync
  // Description:
  // - Records the account requesting background dose transmission.
  // Parameters:
  // - owner (String): Account to schedule.
  // Returns:
  // - Future<void>: Completes after appending owner.
  @override
  Future<void> registerSync(String owner) async => registered.add(owner);

  // Function Name: openClient
  // Description:
  // - Counts service-owned client acquisition and returns the shared test client.
  // Parameters:
  // - None.
  // Returns:
  // - Future<http.Client>: The constructor-supplied client.
  @override
  Future<http.Client> openClient() async {
    openedClients++;
    return client;
  }
}

// Class Name: _RecordingWorkPlatform
// Role: Captures background-work ordering and store-open failure.
// Responsibilities: Records registration and cancellation calls; returns a configured store or fails when absent.
// Attributes: store is the optional encrypted store; calls preserves operation order.
class _RecordingWorkPlatform extends DoseSyncWorkPlatform {
  // Function Name: _RecordingWorkPlatform
  // Description:
  // - Configures whether the worker can open dose storage.
  // Parameters:
  // - store (DoseOutboxStore?): Store to return; null simulates an unavailable store.
  // Returns:
  // - A recording work platform.
  _RecordingWorkPlatform(this.store);

  final DoseOutboxStore? store;
  final List<String> calls = [];

  // Function Name: supported
  // Description:
  // - Enables the background-work path on the test host.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Always true.
  @override
  bool get supported => true;

  // Function Name: registerOneOff
  // Description:
  // - Records a one-off transmission request with its account.
  // Parameters:
  // - owner (String): Account to schedule.
  // Returns:
  // - Future<void>: Completes after appending one-off:owner.
  @override
  Future<void> registerOneOff(String owner) async => calls.add('one-off:$owner');

  // Function Name: registerPeriodic
  // Description:
  // - Records periodic transmission registration with its account.
  // Parameters:
  // - owner (String): Account to schedule.
  // Returns:
  // - Future<void>: Completes after appending periodic:owner.
  @override
  Future<void> registerPeriodic(String owner) async =>
      calls.add('periodic:$owner');

  // Function Name: cancelAll
  // Description:
  // - Records cancellation before subsequent storage cleanup can run.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes after appending cancel.
  @override
  Future<void> cancelAll() async => calls.add('cancel');

  // Function Name: openStore
  // Description:
  // - Records the open attempt and exposes the configured storage failure.
  // Parameters:
  // - None.
  // Returns:
  // - Future<DoseOutboxStore>: Shared store, or StateError when store is null.
  @override
  Future<DoseOutboxStore> openStore() async {
    calls.add('open');
    return store ?? (throw StateError('Dose storage unavailable.'));
  }
}

// Function Name: main
// Description:
// - Registers widget publication, background refresh, queued transmission and cleanup regressions using real SQLite and cryptography.
// Parameters:
// - None.
// Returns:
// - No value; the framework executes registered tests and lifecycle hooks.
void main() {
  sqfliteFfiInit();
  const owner = 'patient-a';
  late Database db;
  late DoseOutboxStore store;
  late Directory directory;
  late _RecordingWidgetPlatform platform;
  late http.Client client;
  late List<Map<String, dynamic>> uploads;
  late int scheduleReads;
  late int snapshotReads;
  late bool online;
  late int uploadStatus;
  late int snapshotStatus;
  late Duration uploadDelay;

  // Function Name: today
  // Description:
  // - Uses the production widget day policy to derive today's dose date.
  // Parameters:
  // - None.
  // Returns:
  // - String: Calendar day in YYYY-MM-DD form.
  String today() => doseWidgetDay(DateTime.now());

  // Function Name: medication
  // Description:
  // - Creates the fixed private-name morning medication for server and cache fixtures.
  // Parameters:
  // - taken (bool): Morning completion state; defaults to false.
  // Returns:
  // - MedicationSchedule: Numeric ID 91 with an explicit morning slot.
  MedicationSchedule medication({bool taken = false}) => MedicationSchedule(
    medicationID: '91',
    medicationName: 'private medicine',
    scheduleSlotKeys: const ['morning'],
    slotStatuses: {'morning': taken},
  );

  // Function Name: prepare
  // Description:
  // - Activates the fixture owner, saves a daily schedule and builds its persisted widget state.
  // Parameters:
  // - date (String?): Cache date; defaults to today.
  // - taken (bool): Morning completion state.
  // - config (Map<String, dynamic>): Widget-source and display options.
  // Returns:
  // - Future<DoseWidgetState>: Persisted widget state; fails if the store cannot produce one.
  Future<DoseWidgetState> prepare({
    String? date,
    bool taken = false,
    Map<String, dynamic> config = const {},
  }) async {
    await store.activate(owner);
    await store.saveCache(owner, {
      'date': date ?? today(),
      'schedules': [medication(taken: taken).toJson()],
    });
    return (await store.updateWidget(
      owner: owner,
      now: DateTime.now(),
      configuration: config,
    ))!;
  }

  // Function Name: enqueue
  // Description:
  // - Adds an unsent morning completion including a private local-only medication name.
  // Parameters:
  // - id (String): Stable operation ID.
  // - date (String?): Dose date; defaults to today.
  // Returns:
  // - Future<void>: Completes durable enqueue, propagating storage errors.
  Future<void> enqueue(String id, {String? date}) => store.enqueue(owner, {
    'operation_id': id,
    'schedule_date': date ?? today(),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
    'medication_names': ['private medicine'],
  });

  // Function Name: uploadedIds
  // Description:
  // - Extracts operation identifiers in the order the mock server received uploads.
  // Parameters:
  // - None.
  // Returns:
  // - List<Object?>: Uploaded operation_id values.
  List<Object?> uploadedIds() => [for (final u in uploads) u['operation_id']];

  // Function Name: setUp
  // Description:
  // - Installs production readers, creates a fresh encrypted file-backed store, and configures recording HTTP and widget substitutes.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes fixture setup; unexpected HTTP routes return 500.
  setUp(() async {
    // Production installs the server readers at every entry point; the tests use the same wiring.
    installDoseHomeWidgetReaders();
    directory = await Directory.systemTemp.createTemp('dose-widget-service-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    uploads = [];
    scheduleReads = 0;
    snapshotReads = 0;
    online = true;
    uploadStatus = 200;
    snapshotStatus = 200;
    uploadDelay = Duration.zero;
    client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      final path = request.url.path;
      if (request.method == 'POST' &&
          path.endsWith('/schedule/completion-operations')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        uploads.add(body);
        await Future<void>.delayed(uploadDelay);
        if (uploadStatus != 200) return http.Response('rejected', uploadStatus);
        return jsonResponse({
          'operation_id': body['operation_id'],
          'schedule_date': today(),
          'data': [medication(taken: body['completed'] == true).toJson()],
        });
      }
      if (request.method == 'GET' && path.endsWith('/schedule/today')) {
        scheduleReads++;
        return jsonResponse({
          'success': true,
          'data': [medication().toJson()],
        });
      }
      if (request.method == 'GET' && path.endsWith('/caregiver/schedules')) {
        snapshotReads++;
        if (snapshotStatus != 200) {
          return http.Response('unavailable', snapshotStatus);
        }
        return jsonResponse({
          'success': true,
          'data': {
            'caregiver_hash': owner,
            'patients': [
              {
                'link': {
                  'link_id': 3,
                  'patient_hash': 'patient-b',
                  'caregiver_hash': owner,
                  'patient_alias': '어머니',
                  'link_status': true,
                },
                'today_medication_info': [medication().toJson()],
              },
            ],
          },
        });
      }
      return http.Response('{"detail":"unexpected"}', 500);
    });
    platform = _RecordingWidgetPlatform(store, client);
    DoseHomeWidget.platform = platform;
  });

  // Function Name: tearDown
  // Description:
  // - Resets global widget/work platforms, closes shared clients and database, and removes the temporary directory.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes cleanup, propagating resource errors.
  tearDown(() async {
    DoseHomeWidget.resetForTest();
    DoseSyncBackgroundScheduler.platform = const DoseSyncWorkPlatform();
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  group('주기 작업의 건너뛰기 조건', () {
    // Function Name: nothing pending and no widget: no request, no publish, no job
    // Description:
    // - With no installed widget and no queued work, verifies no network client, publication or follow-up job is created.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('nothing pending and no widget: no request, no publish, no job', () async {
      await prepare();
      platform.installed = false;

      await DoseHomeWidget.refreshInBackground();

      expect(uploads, isEmpty);
      expect(scheduleReads, 0);
      expect(platform.savedStates, isEmpty);
      expect(platform.openedClients, 0);
      expect(platform.registered, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // Function Name: widget with today\'s schedule: one local publish, no request
    // Description:
    // - With a current daily cache, publishes exactly one local state without opening a client or scheduling work.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('widget with today\'s schedule: one local publish, no request', () async {
      await prepare();

      await DoseHomeWidget.refreshInBackground();

      expect(uploads, isEmpty);
      expect(scheduleReads, 0);
      expect(platform.openedClients, 0);
      expect(platform.savedStates, hasLength(1));
      expect(platform.savedStates.single['date'], today());
      expect(platform.registered, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // Function Name: widget without today\'s schedule: one read, two publishes
    // Description:
    // - With a stale daily cache, reads today's schedule once, publishes before and after recovery, and skips another read on the next refresh.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('widget without today\'s schedule: one read, two publishes', () async {
      await prepare(date: '2000-01-01');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 1);
      expect(uploads, isEmpty);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['total'], 1);
      expect((await store.readCache(owner))!['date'], today());
      expect(platform.registered, isEmpty);

      await DoseHomeWidget.refreshInBackground();
      expect(scheduleReads, 1);
    });

    // Function Name: no widget and no pending record: a stale schedule is not read
    // Description:
    // - With no widget and no queued work, leaves a stale cache alone without requesting or publishing a schedule.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('no widget and no pending record: a stale schedule is not read', () async {
      await prepare(date: '2000-01-01');
      platform.installed = false;

      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 0);
      expect(platform.savedStates, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // Function Name: an unknown widget state is treated as installed
    // Description:
    // - Treats installation lookup failure as potentially installed, requesting the stale schedule and publishing twice.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('an unknown widget state is treated as installed', () async {
      await prepare(date: '2000-01-01');
      platform.failInstalledLookup = true;

      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);
      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 1);
      expect(platform.savedStates, hasLength(2));
    });
  });

  group('전송 대기 기록', () {
    // Function Name: a pending record is uploaded once and the widget is refreshed
    // Description:
    // - Uploads one operation without its private medication_names field, publishes pending then acknowledged state, and does not repeat the upload or self-schedule.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a pending record is uploaded once and the widget is refreshed', () async {
      await prepare();
      await enqueue('op-1');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(uploads.single.containsKey('medication_names'), isFalse);
      expect(scheduleReads, 0);
      expect(await store.pending(owner), isEmpty);
      expect(platform.openedClients, 1);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.first['status'], contains('전송 대기 1건'));
      expect(platform.savedStates.last['status'], '서버 저장 완료');
      expect(platform.savedStates.last['done'], 1);
      // 갱신 작업이 스스로를 다시 예약하지 않는다.
      expect(platform.registered, isEmpty);

      await DoseHomeWidget.refreshInBackground();
      expect(uploadedIds(), ['op-1']);
    });

    // Function Name: a pending record is uploaded even without a widget
    // Description:
    // - Uploads the pending operation even without an installed widget, emptying the queue without a schedule read.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a pending record is uploaded even without a widget', () async {
      await prepare();
      await enqueue('op-1');
      platform.installed = false;
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(await store.pending(owner), isEmpty);
      expect(scheduleReads, 0);
    });

    // Function Name: a failed upload keeps the record and still publishes once more
    // Description:
    // - On a 503 upload response, retains the same operation, refreshes the stale schedule and publishes the pending state twice in total.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a failed upload keeps the record and still publishes once more', () async {
      await prepare(date: '2000-01-01');
      await enqueue('op-1', date: '2000-01-01');
      uploadStatus = 503;

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(scheduleReads, 1);
      expect(
        (await store.pending(owner)).map((op) => op['operation_id']),
        ['op-1'],
      );
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['status'], contains('전송 대기 1건'));
    });

    // Function Name: the app and the periodic worker never upload one record twice
    // Description:
    // - Runs foreground drain and periodic refresh concurrently, then refreshes again, verifying the durable lease permits only one upload.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('the app and the periodic worker never upload one record twice', () async {
      await prepare();
      await enqueue('op-1');
      uploadDelay = const Duration(milliseconds: 40);
      final foreground = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(foreground.dispose);

      await Future.wait([
        foreground.drain(),
        DoseHomeWidget.refreshInBackground(),
      ]);
      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(await store.pending(owner), isEmpty);
    });

    // Function Name: a rejected record does not wake the network every period
    // Description:
    // - After a 409 blocks the operation, skips further client acquisition and uploads while publishing the user-action-required status.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a rejected record does not wake the network every period', () async {
      await prepare();
      await enqueue('op-1');
      uploadStatus = 409;
      await DoseHomeWidget.refreshInBackground();
      expect((await store.pending(owner)).single['state'], 'blocked');
      final opened = platform.openedClients;

      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(platform.openedClients, opened);
      expect(
        platform.savedStates.last['status'],
        '전송 확인 필요 · 앱에서 확인',
      );
    });
  });

  group('호출자가 준비한 동기화 서비스', () {
    // Function Name: a caller-provided service is reused, not drained or disposed
    // Description:
    // - Reuses a caller's already-drained service and client without repeating its failed upload or disposing it; only fetches the needed schedule.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a caller-provided service is reused, not drained or disposed', () async {
      await prepare(date: '2000-01-01');
      await enqueue('op-1', date: '2000-01-01');
      uploadStatus = 503;
      final sync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(sync.dispose);
      await sync.drain();
      expect(uploadedIds(), ['op-1']);

      await DoseHomeWidget.refreshInBackground(sync: sync, client: client);

      // 호출자가 방금 시도한 전송을 반복하지 않고, 필요한 일정 조회만 한다.
      expect(uploadedIds(), ['op-1']);
      expect(scheduleReads, 1);
      expect(platform.openedClients, 0);
      expect(platform.savedStates, hasLength(2));
      expect(() => sync.addListener(() {}), returnsNormally);
      expect(sync.pendingCount, 1);
    });

    // Function Name: a service of another account is never used for this account
    // Description:
    // - Rejects a caller-supplied service for another account without uploading or removing the current owner's pending record.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a service of another account is never used for this account', () async {
      await prepare();
      await enqueue('op-1');
      final other = DoseSyncService(
        owner: 'patient-b',
        client: client,
        openStore: () async => store,
      );
      addTearDown(other.dispose);

      await DoseHomeWidget.refreshInBackground(sync: other, client: client);

      expect(uploads, isEmpty);
      expect(await store.pending(owner), hasLength(1));
    });
  });

  group('위젯에서 누른 버튼', () {
    // Function Name: journalFor
    // Description:
    // - Encodes one native widget click using the visible action and token.
    // Parameters:
    // - state (DoseWidgetState): Previously displayed widget state.
    // Returns:
    // - String: JSON journal containing the action, token and widget ID 1.
    String journalFor(DoseWidgetState state) => jsonEncode([
      {
        'action': state.view['action'],
        'token': state.view['token'],
        'widget': 1,
      },
    ]);

    // Function Name: a widget tap is stored, uploaded once and acknowledged
    // Description:
    // - Consumes a widget take token once, uploads its matching date and slot, clears the journal and publishes acknowledged state without rereading today's schedule.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a widget tap is stored, uploaded once and acknowledged', () async {
      final shown = await prepare();
      expect(shown.view['action'], 'take');
      platform.journal = journalFor(shown);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      expect(uploadedIds(), [shown.view['token']]);
      expect(uploads.single['completed'], isTrue);
      expect(uploads.single['slot_key'], 'morning');
      expect(uploads.single['schedule_date'], today());
      expect(platform.savedStates.first['handled'], [shown.view['token']]);
      expect(platform.journal, '[]');
      expect(platform.registered, [owner]);
      // 클릭으로 깨어난 갱신은 확인 응답의 일정을 쓰고 다시 조회하지 않는다.
      expect(scheduleReads, 0);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['done'], 1);
      expect(await store.pending(owner), isEmpty);
    });

    // Function Name: an offline widget tap stays queued and is shown as pending
    // Description:
    // - Keeps an offline widget action durably pending and visibly completed, schedules retry once, then uploads that same token after connectivity returns.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('an offline widget tap stays queued and is shown as pending', () async {
      final shown = await prepare();
      platform.journal = journalFor(shown);
      online = false;

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      final pending = await store.pending(owner);
      expect(pending.single['operation_id'], shown.view['token']);
      expect(pending.single['completed'], isTrue);
      expect(pending.single['state'], 'pending');
      expect(platform.savedStates.first['handled'], [shown.view['token']]);
      expect(platform.savedStates.last['done'], 1);
      expect(platform.savedStates.last['status'], contains('전송 대기 1건'));
      // 연결되면 전송하도록 작업을 한 번 예약한다.
      expect(platform.registered, [owner]);

      online = true;
      await DoseHomeWidget.refreshInBackground();
      expect(uploadedIds(), [shown.view['token']]);
      expect(await store.pending(owner), isEmpty);
    });

    // Function Name: a tap found after the caller drained is still uploaded
    // Description:
    // - Finds and uploads a journal action even after the caller's service already drained, reusing its client and refreshing its pending count.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a tap found after the caller drained is still uploaded', () async {
      final shown = await prepare();
      final sync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(sync.dispose);
      await sync.drain();
      platform.journal = journalFor(shown);

      await DoseHomeWidget.refreshInBackground(sync: sync, client: client);

      expect(uploadedIds(), [shown.view['token']]);
      expect(sync.pendingCount, 0);
      expect(platform.openedClients, 0);
    });

    // Function Name: a refresh requested by the widget always reads the server
    // Description:
    // - An explicit widget refresh rereads today's schedule despite a current cache, with two publications and no dose upload.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a refresh requested by the widget always reads the server', () async {
      await prepare();

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      expect(scheduleReads, 1);
      expect(uploads, isEmpty);
      expect(platform.savedStates, hasLength(2));
    });
  });

  group('환자 조회 위젯', () {
    const patients = {'source': 'patients'};

    // Function Name: patient snapshots are read once per day by the periodic worker
    // Description:
    // - Reads linked-patient data once for periodic refreshes on the cached day, preserves the alias, and rereads on an explicit widget request.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('patient snapshots are read once per day by the periodic worker', () async {
      await prepare(config: patients);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(snapshotReads, 1);
      expect(scheduleReads, 0);
      expect(platform.savedStates, hasLength(2));
      final shown = platform.savedStates.last['patients'] as List;
      expect((shown.single as Map)['title'], '어머니');

      await DoseHomeWidget.refreshInBackground();
      expect(snapshotReads, 1);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);
      expect(snapshotReads, 2);
    });

    // Function Name: a failed patient read is shown and retried next period
    // Description:
    // - Shows patient-read failure and keeps network refresh necessary, then retries successfully on the next period.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a failed patient read is shown and retried next period', () async {
      await prepare(config: patients);
      snapshotStatus = 503;

      await DoseHomeWidget.refreshInBackground();

      expect(snapshotReads, 1);
      expect(platform.savedStates.last['heading'], '환자 일정을 새로고침해주세요');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      snapshotStatus = 200;
      await DoseHomeWidget.refreshInBackground();
      expect(snapshotReads, 2);
      expect(platform.savedStates.last['patients'], hasLength(1));
    });
  });

  group('완료한 시간대의 재알림 취소', () {
    // Function Name: a completed slot is cancelled once, and again after an undo
    // Description:
    // - Cancels a completed slot's reminder only once across repeated publications, but allows a new cancellation after undo and recompletion.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a completed slot is cancelled once, and again after an undo', () async {
      await prepare(taken: true);

      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);

      expect(platform.cancelledReminders, hasLength(1));
      expect(platform.cancelledReminders.single.owner, owner);
      expect(platform.cancelledReminders.single.slotKey, 'morning');
      expect(platform.cancelledReminders.single.date, DateTime.parse(today()));
      expect(platform.scheduledUpdates, hasLength(3));

      await prepare(taken: false);
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(1));

      await prepare(taken: true);
      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(2));
    });

    // Function Name: a failed cancellation is retried by the next publish
    // Description:
    // - Allows publication and next-update scheduling despite reminder-cancel failure, then retries cancellation on the next publish.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('a failed cancellation is retried by the next publish', () async {
      await prepare(taken: true);
      platform.failReminderCancel = true;

      final state = await DoseHomeWidget.publish(owner: owner);

      expect(state, isNotNull);
      expect(platform.savedStates, hasLength(1));
      expect(platform.scheduledUpdates, hasLength(1));
      expect(platform.cancelledReminders, isEmpty);

      platform.failReminderCancel = false;
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(1));
    });
  });

  group('전송 작업 예약', () {
    // Function Name: register schedules the one-off and the periodic task
    // Description:
    // - Registers one-off work before periodic work, each exactly once for the account.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('register schedules the one-off and the periodic task', () async {
      final work = _RecordingWorkPlatform(store);
      DoseSyncBackgroundScheduler.platform = work;

      await DoseSyncBackgroundScheduler.register(owner);

      expect(work.calls, ['one-off:$owner', 'periodic:$owner']);
    });

    // Function Name: suspend cancels the workers and deactivates the account
    // Description:
    // - Cancels workers before opening the store, deactivates the owner and preserves its pending operation.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('suspend cancels the workers and deactivates the account', () async {
      await prepare();
      await enqueue('op-1');
      final work = _RecordingWorkPlatform(store);
      DoseSyncBackgroundScheduler.platform = work;

      await DoseSyncBackgroundScheduler.suspend();

      expect(work.calls, ['cancel', 'open']);
      expect(await store.isActive(owner), isFalse);
      expect(await store.pending(owner), hasLength(1));
    });

    // Function Name: suspend cancels the workers even when the store cannot open
    // Description:
    // - Cancels workers before a failed store open and propagates the storage error.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('suspend cancels the workers even when the store cannot open', () async {
      final work = _RecordingWorkPlatform(null);
      DoseSyncBackgroundScheduler.platform = work;

      await expectLater(DoseSyncBackgroundScheduler.suspend(), throwsStateError);

      expect(work.calls, ['cancel', 'open']);
    });
  });

  // Function Name: clear blanks the widget and discards unhandled taps
  // Description:
  // - Clears scheduled updates, publishes only handled stale clicks and the default language, then empties the journal.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('clear blanks the widget and discards unhandled taps', () async {
    SharedPreferences.setMockInitialValues({});
    platform.journal = jsonEncode([
      {'action': 'take', 'token': 'widget_old', 'widget': 1},
    ]);

    await DoseHomeWidget.clear();

    expect(platform.cancelledScheduledUpdates, 1);
    expect(platform.savedStates.single, {
      'handled': ['widget_old'],
      'language': 'ko',
    });
    expect(platform.journal, '[]');
  });

  // Function Name: clear keeps the app language for the sign-in prompt
  // Description:
  // - Preserves the persisted English app language in the cleared widget's sign-in state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('clear keeps the app language for the sign-in prompt', () async {
    SharedPreferences.setMockInitialValues({'medbuddy_app_language': 'en'});

    await DoseHomeWidget.clear();

    expect(platform.savedStates.single['language'], 'en');
  });
}
