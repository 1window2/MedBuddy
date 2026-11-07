import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/json_http.dart';

class _DelayedOwnerKeyStore extends DoseOutboxStore {
  _DelayedOwnerKeyStore(super.db, super.key);

  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String> ownerKey(String owner) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.ownerKey(owner);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DoseOutboxStore store;
  late http.Client client;
  final now = DateTime.utc(2026, 10, 21, 3);

  setUp(() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
        singleInstance: false,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    client = MockClient((_) async => http.Response('offline', 503));
    await store.activate('patient-a');
  });

  tearDown(() async {
    client.close();
    await store.db.close();
  });

  for (final nextOwner in <String?>[null, 'patient-b']) {
    test('a disposed initializer cannot reactivate after $nextOwner', () async {
      final opened = Completer<DoseOutboxStore>();
      final sync = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () => opened.future,
        clock: () => now,
      );
      final initialization = sync.initialize(activate: true);
      sync.dispose();
      await store.activate(nextOwner);
      opened.complete(store);
      await initialization;

      expect(await store.isActive('patient-a'), isFalse);
      if (nextOwner != null) expect(await store.isActive(nextOwner), isTrue);
    });
  }

  test(
    'activation rechecks the session after asynchronous key lookup',
    () async {
      final delayed = _DelayedOwnerKeyStore(store.db, store.key);
      final sync = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => delayed,
        clock: () => now,
      );
      final initialization = sync.initialize(activate: true);
      await delayed.entered.future;
      sync.dispose();
      await store.activate('patient-b');
      delayed.release.complete();
      await initialization;

      expect(await store.isActive('patient-b'), isTrue);
      expect(await store.isActive('patient-a'), isFalse);
    },
  );

  for (final withOfflineWindow in [false, true]) {
    test(
      'a pre-midnight receipt preserves today (window=$withOfflineWindow)',
      () async {
        var current = now;
        const previousDay = '2026-10-21';
        const today = '2026-10-22';
        final medication = MedicationSchedule(
          medicationID: '91',
          medicationName: 'synthetic',
          prescriptionDate: DateTime(2026, 10, 21),
          medicationTime: 14,
          scheduleSlotKeys: const ['morning'],
          slotStatuses: const {'morning': false},
        );
        final requestStarted = Completer<void>();
        final receipt = Completer<http.Response>();
        client.close();
        client = MockClient((_) {
          requestStarted.complete();
          return receipt.future;
        });
        final sync = DoseSyncService(
          owner: 'patient-a',
          client: client,
          openStore: () async => store,
          clock: () => current,
        );
        addTearDown(sync.dispose);
        await sync.cacheSchedules([medication], scheduleDate: previousDay);
        if (withOfflineWindow) {
          await sync.cacheScheduleWindow(
            [medication],
            startDay: previousDay,
            expectedRevision: await sync.cacheRevision(),
          );
        }
        await store.enqueue('patient-a', {
          'operation_id': 'before-midnight',
          'schedule_date': previousDay,
          'slot_key': 'morning',
          'medication_ids': [91],
          'completed': false,
        });
        final draining = sync.drain();
        await requestStarted.future;
        current = current.add(const Duration(days: 1));
        final todayCache = {
          'date': today,
          'schedules': [
            medication
                .copyWith(
                  slotStatuses: {'morning': true},
                  medicationStatus: true,
                )
                .toJson(),
          ],
        };
        await store.saveCache('patient-a', todayCache);
        receipt.complete(
          jsonResponse({
            'operation_id': 'before-midnight',
            'schedule_date': previousDay,
            'data': [medication.toJson()],
          }),
        );
        await draining;

        expect(await store.pending('patient-a'), isEmpty);
        expect(await store.readCache('patient-a'), todayCache);
        expect(sync.hasCache, isTrue);
        expect(sync.schedules.single.isSlotCompleted('morning'), isTrue);
        expect(sync.acceptedRevision, 1);
        expect(sync.hasScheduledRetry, isFalse);
        final widget = await store.updateWidget(
          owner: 'patient-a',
          now: current,
        );
        expect(widget!.view['date'], doseWidgetDay(current));
        expect(widget.view['done'], 1);
      },
    );
  }
}
