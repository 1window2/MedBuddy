// File Name: background_task_test.dart
// Role: Verifies scoped background task routing, idle authentication avoidance, client ownership and retry results.
// Uses real SQLite/encryption for pending doses with recording authentication, widget, reminder and monitoring substitutes.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/composition/caregiver_notification_background_service.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/dose_sync_harness.dart';

// Class Name: _ClosingClient
// Role: Tracks whether task cleanup requested client closure.
// Responsibilities: Delegates sends to the fixture server and records close without closing the inner fake.
// Attributes: _inner is the delegated client; closed records a close call.
class _ClosingClient extends http.BaseClient {
  // Function Name: _ClosingClient
  // Description:
  // - Wraps a fixture transport with observable close state.
  // Parameters:
  // - _inner (http.Client): Transport that handles each request.
  // Returns:
  // - A close-recording client.
  _ClosingClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  // Function Name: send
  // Description:
  // - Forwards the original request unchanged to the wrapped transport.
  // Parameters:
  // - request (http.BaseRequest): Request under test.
  // Returns:
  // - Future<http.StreamedResponse>: The inner transport result or error.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  // Function Name: close
  // Description:
  // - Marks the wrapper closed; deliberately does not dispose the wrapped fake transport.
  // Parameters:
  // - None.
  // Returns:
  // - No value; sets closed to true.
  @override
  void close() => closed = true;
}

// Class Name: _RecordingDeps
// Role: Records background task dependency calls and supplied resources.
// Responsibilities: Controls authentication restoration, network demand and reminder/caregiver outcomes without real platform services.
// Attributes: store/client are optional resources; calls preserves order; widgetSyncs/widgetClients capture reuse. needsNetwork overrides demand; reminderResult/caregiverResult select results; failure injects an error.
class _RecordingDeps extends BackgroundTaskDeps {
  // Function Name: _RecordingDeps
  // Description:
  // - Configures the store and restored session client available to a task.
  // Parameters:
  // - store (DoseOutboxStore?): Storage returned when requested.
  // - client (_ClosingClient?): Restored client; null means authentication unavailable.
  // Returns:
  // - A dependency recorder with successful default service outcomes.
  _RecordingDeps({this.store, this.client});

  final DoseOutboxStore? store;
  final _ClosingClient? client;
  final List<String> calls = [];
  final List<DoseSyncService?> widgetSyncs = [];
  final List<http.Client?> widgetClients = [];
  bool? needsNetwork;
  bool reminderResult = true;
  bool caregiverResult = true;
  Object? failure;

  // Function Name: openClient
  // Description:
  // - Records authentication/client restoration and returns the configured result.
  // Parameters:
  // - None.
  // Returns:
  // - Future<http.Client?>: Configured client, or null when session restoration fails.
  @override
  Future<http.Client?> openClient() async {
    calls.add('openClient');
    return client;
  }

  // Function Name: openDoseStore
  // Description:
  // - Records opening the shared encrypted dose store.
  // Parameters:
  // - None.
  // Returns:
  // - Future<DoseOutboxStore>: Configured store; fails its null assertion if none was supplied.
  @override
  Future<DoseOutboxStore> openDoseStore() async {
    calls.add('openDoseStore');
    return store!;
  }

  // Function Name: doseNeedsNetwork
  // Description:
  // - Records demand evaluation and uses the explicit override or production decision.
  // Parameters:
  // - owner (String): Account whose pending work and widget state are checked.
  // Returns:
  // - Future<bool>: Override when set, otherwise the base implementation result.
  @override
  Future<bool> doseNeedsNetwork(String owner) async {
    calls.add('doseNeedsNetwork');
    return needsNetwork ?? await super.doseNeedsNetwork(owner);
  }

  // Function Name: refreshDoseWidget
  // Description:
  // - Records a local-only or service-backed refresh and captures both resources without performing platform work.
  // Parameters:
  // - sync (DoseSyncService?): Caller-owned service to reuse.
  // - client (http.Client?): Caller-owned HTTP client.
  // Returns:
  // - Future<void>: Completes call and resource recording.
  @override
  Future<void> refreshDoseWidget({
    DoseSyncService? sync,
    http.Client? client,
  }) async {
    calls.add(sync == null ? 'refreshDoseWidget:local' : 'refreshDoseWidget');
    widgetSyncs.add(sync);
    widgetClients.add(client);
  }

  // Function Name: initializeNotifications
  // Description:
  // - Records notification initialization without loading a platform plugin.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes after recording the call.
  @override
  Future<void> initializeNotifications() async {
    calls.add('initializeNotifications');
  }

  // Function Name: refreshReminders
  // Description:
  // - Records patient/API scope, verifies client identity and returns the scripted reminder outcome.
  // Parameters:
  // - patientHash (String): Patient account.
  // - baseUrl (String): Task API base URL.
  // - client (http.Client): Must be the dependency's configured client.
  // Returns:
  // - Future<bool>: reminderResult; throws failure when configured or fails the identity expectation.
  @override
  Future<bool> refreshReminders({
    required String patientHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    calls.add('refreshReminders:$patientHash:$baseUrl');
    expect(client, same(this.client));
    if (failure != null) throw failure!;
    return reminderResult;
  }

  // Function Name: checkCaregiverAlerts
  // Description:
  // - Records caregiver/API scope, verifies client identity and returns the scripted monitor outcome.
  // Parameters:
  // - caregiverHash (String): Caregiver account.
  // - baseUrl (String): Task API base URL.
  // - client (http.Client): Must be the dependency's configured client.
  // Returns:
  // - Future<bool>: caregiverResult; throws failure when configured or fails the identity expectation.
  @override
  Future<bool> checkCaregiverAlerts({
    required String caregiverHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    calls.add('checkCaregiverAlerts:$caregiverHash:$baseUrl');
    expect(client, same(this.client));
    if (failure != null) throw failure!;
    return caregiverResult;
  }
}

// Class Name: _NoWidgetPlatform
// Role: Models a supported platform without installed widgets or pending clicks.
// Responsibilities: Lets production network-demand logic inspect the actual test store while finding no widget work.
// Attributes: store is the shared encrypted dose store.
class _NoWidgetPlatform extends DoseHomeWidgetPlatform {
  // Function Name: _NoWidgetPlatform
  // Description:
  // - Connects the no-widget fixture to the test store.
  // Parameters:
  // - store (DoseOutboxStore): Store used by network-demand checks.
  // Returns:
  // - A platform reporting no installed widgets.
  _NoWidgetPlatform(this.store);

  final DoseOutboxStore store;

  // Function Name: supported
  // Description:
  // - Allows widget demand logic to run on the test host.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Always true.
  @override
  bool get supported => true;

  // Function Name: readJournal
  // Description:
  // - Reports that no widget click awaits processing.
  // Parameters:
  // - None.
  // Returns:
  // - Future<String?>: JSON empty array.
  @override
  Future<String?> readJournal() async => '[]';

  // Function Name: hasInstalledWidget
  // Description:
  // - Reports that no widget requires refresh.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool>: Always false.
  @override
  Future<bool> hasInstalledWidget() async => false;

  // Function Name: openStore
  // Description:
  // - Returns the shared encrypted store.
  // Parameters:
  // - None.
  // Returns:
  // - Future<DoseOutboxStore>: Constructor-supplied store.
  @override
  Future<DoseOutboxStore> openStore() async => store;
}

// Function Name: main
// Description:
// - Registers dose, reminder and caregiver task routing, resource-reuse and retry regressions.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the cases and setup/cleanup hooks.
void main() {
  const owner = 'patient-a';
  late Database db;
  late DoseOutboxStore store;
  late List<http.Request> requests;
  late int uploadStatus;
  late _ClosingClient client;

  // Function Name: medication
  // Description:
  // - Creates the acknowledged morning dose returned by the fixture server.
  // Parameters:
  // - None.
  // Returns:
  // - MedicationSchedule: ID 91 with morning marked completed.
  MedicationSchedule medication() => const MedicationSchedule(
    medicationID: '91',
    medicationName: 'test medicine',
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': true},
  );

  // Function Name: enqueue
  // Description:
  // - Adds one unsent morning completion for today's medication date.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes durable storage of op-1; storage errors propagate.
  Future<void> enqueue() => store.enqueue(owner, {
    'operation_id': 'op-1',
    'schedule_date': doseScheduleDay(DateTime.now()),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
  });

  // Function Name: setUp
  // Description:
  // - Creates an independent encrypted in-memory store and a recording receipt client, then installs the no-widget platform.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes resource setup.
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
        singleInstance: false,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    requests = [];
    uploadStatus = 200;
    client = _ClosingClient(
      MockClient((request) async {
        requests.add(request);
        if (uploadStatus != 200) return http.Response('unavailable', uploadStatus);
        return doseSyncReceipt(request, [medication()]);
      }),
    );
    DoseHomeWidget.platform = _NoWidgetPlatform(store);
  });

  // Function Name: tearDown
  // Description:
  // - Resets widget globals and closes the test database.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes cleanup.
  tearDown(() async {
    DoseHomeWidget.resetForTest();
    await db.close();
  });

  group('복용 기록 작업', () {
    // Function Name: nothing to upload: no authentication, no request, local widget refresh only
    // Description:
    // - With an active owner but no pending dose or widget, performs only store/demand checks and a local widget refresh, leaving authentication and client closure untouched.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('nothing to upload: no authentication, no request, local widget refresh only', () async {
      await store.activate(owner);
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isTrue);
      expect(deps.calls, [
        'openDoseStore',
        'doseNeedsNetwork',
        'refreshDoseWidget:local',
      ]);
      expect(requests, isEmpty);
      expect(client.closed, isFalse);
    });

    // Function Name: pending record: one upload, the drained service is handed to the widget
    // Description:
    // - Uploads op-1 once, hands the same drained service and client to widget refresh, empties uploadable work and closes the task-owned client.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('pending record: one upload, the drained service is handed to the widget', () async {
      await store.activate(owner);
      await enqueue();
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isTrue);
      expect(deps.calls, [
        'openDoseStore',
        'doseNeedsNetwork',
        'openClient',
        'refreshDoseWidget',
      ]);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/schedule/completion-operations'));
      expect(jsonDecode(requests.single.body), containsPair('operation_id', 'op-1'));
      expect(deps.widgetSyncs.single!.owner, owner);
      expect(deps.widgetSyncs.single!.client, same(client));
      expect(deps.widgetClients.single, same(client));
      expect(await store.hasUploadableOperation(owner), isFalse);
      expect(client.closed, isTrue);
    });

    // Function Name: upload rejected temporarily: the record stays and the task asks for a retry
    // Description:
    // - On upload status 503, retains uploadable work, closes the client and returns false so the scheduler can retry.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('upload rejected temporarily: the record stays and the task asks for a retry', () async {
      await store.activate(owner);
      await enqueue();
      uploadStatus = 503;
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isFalse);
      expect(requests, hasLength(1));
      expect(await store.hasUploadableOperation(owner), isTrue);
      expect(client.closed, isTrue);
    });

    // Function Name: pending record without a restored session: no request and a retry
    // Description:
    // - When a pending dose exists but session restoration returns null, sends nothing, retains the operation and returns false.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('pending record without a restored session: no request and a retry', () async {
      await store.activate(owner);
      await enqueue();
      final deps = _RecordingDeps(store: store);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isFalse);
      expect(deps.calls, ['openDoseStore', 'doseNeedsNetwork', 'openClient']);
      expect(requests, isEmpty);
      expect(await store.hasUploadableOperation(owner), isTrue);
    });

    // Function Name: signed-out or foreign owner: nothing is opened beyond the store
    // Description:
    // - For a foreign active account, stops after store access; with no task account, skips even the store and sends no requests.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('signed-out or foreign owner: nothing is opened beyond the store', () async {
      await store.activate('patient-b');
      final deps = _RecordingDeps(store: store, client: client);

      expect(
        await runBackgroundTask(doseSyncBackgroundTask, {
          'patient_hash': owner,
        }, deps),
        isTrue,
      );
      expect(deps.calls, ['openDoseStore']);

      deps.calls.clear();
      expect(await runBackgroundTask(doseSyncBackgroundTask, {}, deps), isTrue);
      expect(deps.calls, isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('복약 알림 작업', () {
    // Function Name: reminder refresh runs with the task scope and returns its result
    // Description:
    // - For both true and false reminder outcomes, initializes notifications, preserves the task patient and API URL, returns that outcome and closes the client.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('reminder refresh runs with the task scope and returns its result', () async {
      for (final outcome in [true, false]) {
        final taskClient = _ClosingClient(MockClient((_) async => http.Response('{}', 200)));
        final deps = _RecordingDeps(client: taskClient)..reminderResult = outcome;

        final result = await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
          'base_url': 'https://api.test/v1',
        }, deps);

        expect(result, outcome);
        expect(deps.calls, [
          'openClient',
          'initializeNotifications',
          'refreshReminders:$owner:https://api.test/v1',
        ]);
        expect(taskClient.closed, isTrue);
      }
    });

    // Function Name: missing scope is ignored; missing session and errors ask for a retry
    // Description:
    // - Ignores blank patient scope, requests retry without a restored session, and closes the client when reminder refresh throws.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('missing scope is ignored; missing session and errors ask for a retry', () async {
      final empty = _RecordingDeps(client: client);
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': '  ',
        }, empty),
        isTrue,
      );
      expect(empty.calls, isEmpty);

      final signedOut = _RecordingDeps();
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
        }, signedOut),
        isFalse,
      );
      expect(signedOut.calls, ['openClient']);

      final failing = _RecordingDeps(client: client)
        ..failure = StateError('network unavailable');
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
        }, failing),
        isFalse,
      );
      expect(failing.calls.last, 'refreshReminders:$owner:${ApiConfig.baseUrl}');
      expect(client.closed, isTrue);
    });
  });

  group('보호자 감시 작업', () {
    // Function Name: caregiver check runs with the caregiver scope and returns its result
    // Description:
    // - For each scripted outcome, uses caregiver scope rather than the patient field, initializes notifications, returns the monitor result and closes the client.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('caregiver check runs with the caregiver scope and returns its result', () async {
      for (final outcome in [true, false]) {
        final taskClient = _ClosingClient(MockClient((_) async => http.Response('{}', 200)));
        final deps = _RecordingDeps(client: taskClient)..caregiverResult = outcome;

        final result = await runBackgroundTask(
          caregiverNotificationBackgroundTask,
          {'caregiver_hash': 'caregiver-a', 'patient_hash': owner},
          deps,
        );

        expect(result, outcome);
        expect(deps.calls, [
          'openClient',
          'initializeNotifications',
          'checkCaregiverAlerts:caregiver-a:${ApiConfig.baseUrl}',
        ]);
        expect(taskClient.closed, isTrue);
      }
    });

    // Function Name: missing caregiver scope and unknown task names do nothing
    // Description:
    // - Treats missing caregiver scope and an unknown task name as successful no-ops without opening or closing the client.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
    test('missing caregiver scope and unknown task names do nothing', () async {
      final deps = _RecordingDeps(client: client);

      expect(
        await runBackgroundTask(caregiverNotificationBackgroundTask, {
          'patient_hash': owner,
        }, deps),
        isTrue,
      );
      expect(await runBackgroundTask('some_other_task', null, deps), isTrue);

      expect(deps.calls, isEmpty);
      expect(client.closed, isFalse);
    });
  });
}
