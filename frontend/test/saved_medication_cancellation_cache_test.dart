import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_saved_medication_view_model.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_notification_service.dart';

const _owner = 'cancellation-cache-patient';
const _otherOwner = 'next-cache-patient';
const _day = '2026-11-16';
final _now = DateTime.utc(2026, 11, 16, 3);
final _detail = MedicationDetail(
  itemName: 'Reviewed medication',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

MedicationSchedule _schedule(int id) => MedicationSchedule(
  medicationID: '$id',
  medicationName: 'Existing medication $id',
  prescriptionDate: _now,
  dosage: '1 tablet',
  intakeTime: '1 time',
  medicationTime: 7,
  scheduleSlotKeys: const ['morning'],
  slotStatuses: const {'morning': true},
  regimenRevision: id,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late _Fixture fixture;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await _Fixture.create();
  });
  tearDown(() => fixture.close());

  test(
    'already cancelled request leaves both populated caches untouched',
    () async {
      final cache = await fixture.store.readCache(_owner);
      final window = await fixture.store.readOfflineScheduleWindow(_owner);
      final revision = await fixture.sync.cacheRevision();
      fixture.requestCurrent = false;

      expect((await fixture.save()).status, MedicationSaveStatus.failed);
      expect(await fixture.store.readCache(_owner), cache);
      expect(await fixture.store.readOfflineScheduleWindow(_owner), window);
      expect(await fixture.sync.cacheRevision(), revision);
      expect(fixture.saveCalls, 0);
      expect(fixture.suspendCalls, 0);
    },
  );

  test(
    'cancellation during suspension restores both caches without sending',
    () async {
      final cache = await fixture.store.readCache(_owner);
      final window = await fixture.store.readOfflineScheduleWindow(_owner);
      final gate = fixture.suspendGate = _Gate();
      final saving = fixture.save();
      final assertion = expectLater(saving, throwsStateError);
      await gate.started.future;
      final suspendedRevision = await fixture.sync.cacheRevision();
      await fixture.expectNoCache();
      fixture.requestCurrent = false;
      final notifications = fixture.notifications;
      gate.release();

      await assertion;
      expect(fixture.saveCalls, 0);
      expect(fixture.restoreCalls, 1);
      expect(fixture.invalidateCalls, 0);
      expect(fixture.notifications, notifications);
      expect(await fixture.store.readCache(_owner), cache);
      expect(await fixture.store.readOfflineScheduleWindow(_owner), window);
      expect(await fixture.sync.cacheRevision(), suspendedRevision + 1);
      expect(fixture.sync.schedules.single.isSlotCompleted('morning'), isTrue);
    },
  );

  for (final cancelled in [false, true]) {
    test(
      'definite save rejection restores populated caches; cancelled=$cancelled',
      () async {
        final cache = await fixture.store.readCache(_owner);
        final window = await fixture.store.readOfflineScheduleWindow(_owner);
        final gate = fixture.saveGate = _Gate();
        final saving = fixture.save();
        await gate.started.future;
        await fixture.expectNoCache();
        fixture.requestCurrent = !cancelled;
        final notifications = fixture.notifications;
        gate.release();

        final result = await saving;
        expect(result.failureKind, MedicationSaveFailureKind.limitReached);
        expect(fixture.restoreCalls, 1);
        expect(fixture.invalidateCalls, 0);
        expect(await fixture.store.readCache(_owner), cache);
        expect(await fixture.store.readOfflineScheduleWindow(_owner), window);
        expect(fixture.sync.hasCache, isTrue);
        expect(fixture.sync.schedules.single.regimenRevision, 11);
        if (cancelled) expect(fixture.notifications, notifications);
        expect(fixture.listRefreshes, 0);
        expect(fixture.reminderRefreshes, 0);
      },
    );
  }

  for (final outcome in [
    'saved',
    'duplicate',
    'timeout',
    'client failure',
    'socket failure',
    'server error',
    'malformed reply',
    'unclassified failure',
  ]) {
    test('cancelled $outcome never restores an old regimen', () async {
      fixture.respond = () async => switch (outcome) {
        'saved' => _json({'success': true, 'id': 23}),
        'duplicate' => _json({'duplicate': true, 'id': 23}),
        'timeout' => throw TimeoutException('Save acknowledgement timed out'),
        'client failure' => throw http.ClientException('Connection lost'),
        'socket failure' => throw const SocketException('Connection lost'),
        'server error' => _json({'detail': 'Server error'}, status: 500),
        'malformed reply' => http.Response('not-json', 200),
        _ => _json({'success': false}),
      };
      final gate = fixture.saveGate = _Gate();
      final saving = fixture.save();
      await gate.started.future;
      fixture.requestCurrent = false;
      // A read can refill pre-save data while the acknowledgement is pending.
      await fixture.seed(11);
      final revision = await fixture.sync.cacheRevision();
      final notifications = fixture.notifications;
      gate.release();

      await saving;
      expect(fixture.restoreCalls, 0);
      expect(fixture.invalidateCalls, 1);
      expect(await fixture.sync.cacheRevision(), revision + 1);
      await fixture.expectNoCache();
      expect(fixture.notifications, notifications);
      expect(fixture.listRefreshes, 0);
      expect(fixture.reminderRefreshes, 0);
    });
  }

  for (final phase in ['suspension', 'response']) {
    for (final ending in ['clear', 'dispose', 'store account switch']) {
      test(
        '$ending during $phase cannot restore another account cache',
        () async {
          final gate = _Gate();
          if (phase == 'suspension') {
            fixture.suspendGate = gate;
          } else {
            fixture.saveGate = gate;
          }
          final saving = fixture.save();
          final assertion = phase == 'suspension'
              ? expectLater(saving, throwsStateError)
              : expectLater(saving, completion(isA<MedicationSaveResult>()));
          await gate.started.future;
          fixture.requestCurrent = false;
          if (ending == 'clear') fixture.model.clear();
          if (ending == 'dispose') fixture.model.dispose();
          await fixture.store.activate(_otherOwner);
          await fixture.seed(99, owner: _otherOwner);
          final cache = await fixture.store.readCache(_otherOwner);
          final window = await fixture.store.readOfflineScheduleWindow(
            _otherOwner,
          );
          final revision = await fixture.store.cacheRevision(_otherOwner);
          gate.release();

          await assertion;
          expect(await fixture.store.readCache(_owner), isNull);
          expect(await fixture.store.readOfflineScheduleWindow(_owner), isNull);
          expect(await fixture.store.readCache(_otherOwner), cache);
          expect(
            await fixture.store.readOfflineScheduleWindow(_otherOwner),
            window,
          );
          expect(await fixture.store.cacheRevision(_otherOwner), revision);
          expect(await fixture.store.isActive(_otherOwner), isTrue);
          if (ending != 'store account switch') {
            expect(fixture.restoreCalls, 0);
            expect(fixture.invalidateCalls, 0);
          }
        },
      );
    }

    for (final newerState in ['new schedule', 'new mutation']) {
      test(
        'cancelled $phase cannot resurrect a backup after $newerState',
        () async {
          final gate = _Gate();
          if (phase == 'suspension') {
            fixture.suspendGate = gate;
          } else {
            fixture.saveGate = gate;
          }
          final saving = fixture.save();
          final assertion = phase == 'suspension'
              ? expectLater(saving, throwsStateError)
              : expectLater(saving, completion(isA<MedicationSaveResult>()));
          await gate.started.future;
          final revision = await fixture.sync.cacheRevision();
          fixture.requestCurrent = false;
          if (newerState == 'new schedule') {
            await fixture.seed(22);
          } else {
            await fixture.sync.invalidateSchedule();
          }
          expect(await fixture.sync.cacheRevision(), greaterThan(revision));
          gate.release();

          await assertion;
          expect(fixture.restoreCalls, 1);
          // Production restoreSchedule fails closed when the backup revision lost.
          await fixture.expectNoCache();
        },
      );
    }
  }

  test(
    'production factory recovers offline doses after leaving registration',
    () async {
      final model = MedBuddyViewModel(
        patientHash: _owner,
        apiClient: fixture.client,
        notificationService: RecordingNotificationService(),
      );
      model.attachDoseSync(fixture.sync);
      try {
        final entry = ManualMedicationEntry(
          medicationName: _detail.itemName,
          dosageAmount: '1',
          dosageUnit: 'tablet',
          startDate: _now,
          endDate: _now.add(const Duration(days: 6)),
          scheduleSlotKeys: const ['morning'],
          catalogMedication: _detail,
        );
        expect(model.showManualMedicationRegistrationResults([entry]), isTrue);
        final gate = fixture.saveGate = _Gate();
        final saving = model.requestAllAnalyzedMedicationSave();
        await gate.started.future;
        await fixture.expectNoCache();
        model.clearAnalysisResult();
        expect(model.showManualMedicationRegistrationResults([entry]), isTrue);
        final newResults = model.analyzedMedicationList;
        gate.release();

        expect(await saving, isFalse);
        expect(model.analyzedMedicationList, newResults);
        expect(model.completedMedicationSaveIndexes, isEmpty);
        expect(model.isAllMedicationSaving, isFalse);
        expect(model.todayMedicationScheduleList.single.medicationID, '11');
        expect(
          fixture.sync.schedules.single.isSlotCompleted('morning'),
          isTrue,
        );
        expect(
          await fixture.store.readOfflineScheduleWindow(_owner),
          isNotNull,
        );
        expect(fixture.scheduleReads, 1);
        expect(fixture.listRefreshes, 0);
      } finally {
        fixture.saveGate?.release();
        model.dispose();
        fixture.syncDisposed = true;
      }
    },
  );
}

class _Gate {
  final started = Completer<void>();
  final released = Completer<void>();

  Future<void> wait() async {
    if (!started.isCompleted) started.complete();
    await released.future;
  }

  void release() {
    if (!released.isCompleted) released.complete();
  }
}

class _Fixture {
  final DoseOutboxStore store;
  late final MockClient client;
  late final DoseSyncService sync;
  late final MedBuddySavedMedicationViewModel model;
  _Gate? suspendGate;
  _Gate? saveGate;
  bool requestCurrent = true;
  bool syncDisposed = false;
  int suspendCalls = 0;
  int restoreCalls = 0;
  int invalidateCalls = 0;
  int notifications = 0;
  int saveCalls = 0;
  int scheduleReads = 0;
  int listRefreshes = 0;
  int reminderRefreshes = 0;
  Future<http.Response> Function() respond = () async =>
      _json({'detail': 'Medication limit reached'}, status: 409);

  _Fixture(this.store) {
    client = MockClient((request) async {
      if (request.url.path.endsWith('/save')) {
        saveCalls++;
        await saveGate?.wait();
        return respond();
      }
      if (request.url.path.endsWith('/schedule/today')) {
        scheduleReads++;
        return _json({'detail': 'Offline'}, status: 503);
      }
      if (request.url.path.endsWith('/list')) listRefreshes++;
      throw StateError('Unexpected request: ${request.url}');
    });
    sync = DoseSyncService(
      owner: _owner,
      client: client,
      openStore: () async => store,
      clock: () => _now,
    );
    model = MedBuddySavedMedicationViewModel(
      checkSavedMedication: CheckSavedMedication(
        patientHash: _owner,
        client: client,
      ),
      checkMedicationDetail: CheckMedicationDetail(client: client),
      manualMedicationImageStore: ManualMedicationImageStore(),
      patientHash: _owner,
      readEnglishSetting: () => true,
      fetchTodayMedicationSchedule: () async => scheduleReads++,
      suspendSchedule: () async {
        suspendCalls++;
        final backup = await sync.suspendSchedule();
        await suspendGate?.wait();
        return backup;
      },
      restoreSchedule: (backup) async {
        restoreCalls++;
        await sync.restoreSchedule(
          backup is DoseScheduleBackup ? backup : null,
        );
      },
      invalidateSchedule: () async {
        invalidateCalls++;
        await sync.invalidateSchedule();
      },
      synchronizeReminders: () async => reminderRefreshes++,
      onChanged: (_) => notifications++,
    );
  }

  static Future<_Fixture> create() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
        singleInstance: false,
      ),
    );
    final fixture = _Fixture(
      DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey()),
    );
    await fixture.sync.initialize(activate: true);
    await fixture.seed(11);
    return fixture;
  }

  Future<void> seed(int medicationId, {String owner = _owner}) async {
    final schedules = [_schedule(medicationId).toJson()];
    expect(
      await store.saveAuthoritativeDoseCache(owner, {
        'date': _day,
        'schedules': schedules,
      }),
      isTrue,
    );
    expect(
      await store.saveOfflineScheduleWindow(owner, {
        'start': _day,
        'end': '2026-11-22',
        'courses': schedules,
      }, expectedRevision: await store.cacheRevision(owner)),
      isTrue,
    );
    await sync.reload();
  }

  Future<MedicationSaveResult> save() => model.saveMedicationInfo(
    _detail,
    medicationSchedule: _schedule(23),
    refreshAfterSave: false,
    isRequestCurrent: () => requestCurrent,
  );

  Future<void> expectNoCache() async {
    expect(await store.readCache(_owner), isNull);
    expect(await store.readOfflineScheduleWindow(_owner), isNull);
    expect(sync.hasCache, isFalse);
    expect(sync.schedules, isEmpty);
  }

  Future<void> close() async {
    suspendGate?.release();
    saveGate?.release();
    model.dispose();
    if (!syncDisposed) sync.dispose();
    await pumpEventQueue();
    client.close();
    await store.db.close();
  }
}

http.Response _json(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
