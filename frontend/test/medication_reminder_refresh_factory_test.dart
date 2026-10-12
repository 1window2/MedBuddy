import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/composition/medication_reminder_refresh_factory.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'support/fake_notification_service.dart';

class _ReceiptDuringCacheReadStore extends DoseOutboxStore {
  _ReceiptDuringCacheReadStore(super.db, super.key, this.receive);

  final Future<void> Function() receive;
  bool received = false;

  @override
  Future<Map<String, dynamic>?> readCache(String owner) async {
    final snapshot = await super.readCache(owner);
    if (snapshot != null && !received) {
      received = true;
      await receive();
    }
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  timezone_data.initializeTimeZones();
  final seoul = timezone.getLocation('Asia/Seoul');
  late Directory directory;
  late Database db;
  late DoseOutboxStore store;
  late RecordingNotificationService notifications;
  late MockClient client;
  late DateTime now;
  late List<http.Request> requests;
  late bool serverTaken;
  late bool secondMorningMedication;
  late List<MedicationSchedule> futureCourses;
  Future<void> Function()? duringTodayRead;

  MedicationSchedule medication({String id = '91', bool taken = false}) =>
      MedicationSchedule(
        medicationID: id,
        medicationName: 'TEST_ONLY',
        prescriptionDate: DateTime(2026, 10, 10),
        medicationTime: 5,
        scheduleSlotKeys: const ['morning', 'evening'],
        slotStatuses: {'morning': taken, 'evening': false},
      );

  Future<void> enqueue(
    String id, {
    bool completed = true,
    String owner = 'patient-a',
  }) => store.enqueue(owner, {
    'operation_id': id,
    'schedule_date': doseScheduleDay(now),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': completed,
  });

  List<DateTime> dates(String slot) => notifications.registrations
      .lastWhere((registration) => registration.slotKey == slot)
      .activeDates;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('reminder-outbox-test-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    await store.activate('patient-a');
    notifications = RecordingNotificationService();
    now = timezone.TZDateTime(seoul, 2026, 10, 10, 7);
    requests = [];
    serverTaken = false;
    secondMorningMedication = false;
    futureCourses = [];
    duringTodayRead = null;
    client = MockClient((request) async {
      requests.add(request);
      if (request.method != 'GET' ||
          request.url.queryParameters['patient_hash'] != 'patient-a') {
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }
      switch (request.url.path) {
        case '/notification/settings':
          return http.Response(
            jsonEncode({
              'data': [
                for (final slot in ['morning', 'evening'])
                  {
                    'patient_hash': 'patient-a',
                    'slot_key': slot,
                    'hour': slot == 'morning' ? 8 : 20,
                    'minute': 0,
                    'enabled': true,
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        case '/schedule/window':
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                medication().toJson(),
                if (secondMorningMedication) medication(id: '92').toJson(),
                ...futureCourses.map((schedule) => schedule.toJson()),
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        case '/schedule/today':
          final snapshot = [
            medication(taken: serverTaken).toJson(),
            if (secondMorningMedication) medication(id: '92').toJson(),
          ];
          await duringTodayRead?.call();
          return http.Response(
            jsonEncode({'success': true, 'data': snapshot}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        default:
          throw StateError('Unexpected URL: ${request.url}');
      }
    });
  });

  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  MedicationReminderRefreshService build({
    Future<DoseOutboxStore> Function()? openDoseStore,
  }) {
    final service = MedicationReminderRefreshFactory.create(
      patientHash: 'patient-a',
      baseUrl: 'http://test.invalid',
      client: client,
      notificationService: notifications,
      openDoseStore: openDoseStore ?? () async => store,
      now: () => now,
    );
    addTearDown(service.dispose);
    return service;
  }

  test(
    'completed offline is not rearmed by the real background refresh factory',
    () async {
      await enqueue('offline-taken');
      final before = await store.pending('patient-a');
      final service = build();

      expect(await service.synchronize(), isTrue);
      expect(dates('morning'), isNot(contains(DateTime(2026, 10, 10))));
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(dates('evening').first, DateTime(2026, 10, 10));
      expect(await store.pending('patient-a'), before);
      expect(await store.isActive('patient-a'), isTrue);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  test(
    'refresh rereads durable undo and retake in queue order without sending them',
    () async {
      final service = build();
      for (final (id, completed) in [
        ('taken', true),
        ('undo', false),
        ('retake', true),
      ]) {
        await enqueue(id, completed: completed);
        serverTaken = !completed;
        final before = await store.pending('patient-a');
        expect(await service.synchronize(), isTrue);
        expect(dates('morning').contains(DateTime(2026, 10, 10)), !completed);
        expect(dates('evening').first, DateTime(2026, 10, 10));
        expect(await store.pending('patient-a'), before);
      }
      expect(
        (await store.pending('patient-a')).map((op) => op['operation_id']),
        ['taken', 'undo', 'retake'],
      );
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  test(
    'offline completion removes only today alongside a future weekly course',
    () async {
      futureCourses = [
        MedicationSchedule(
          medicationID: '92',
          medicationName: 'TEST_ONLY_WEEKLY',
          prescriptionDate: DateTime(2026, 10, 11),
          medicationTime: 14,
          scheduleSlotKeys: const ['morning'],
          doseCycleDays: 7,
          doseCycleOffsets: const [0],
          doseCycleAnchor: DateTime(2026, 10, 11),
        ),
      ];
      final service = build();
      final futureMorningDates = [
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 14),
        DateTime(2026, 10, 18),
      ];
      for (final (id, completed) in [('taken', true), ('undo', false)]) {
        await enqueue(id, completed: completed);
        final before = await store.pending('patient-a');

        expect(await service.synchronize(), isTrue);
        expect(dates('morning'), [
          if (!completed) DateTime(2026, 10, 10),
          ...futureMorningDates,
        ]);
        expect(dates('evening'), [
          for (var day = 10; day <= 14; day++) DateTime(2026, 10, day),
        ]);
        expect(await store.pending('patient-a'), before);
      }
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  test(
    'yesterday offline completion cannot remove the new day reminder',
    () async {
      final service = build();
      await enqueue('yesterday-taken');
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      now = timezone.TZDateTime(seoul, 2026, 10, 11, 7);

      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      final pending = await store.pending('patient-a');
      expect(pending, hasLength(1));
      expect(pending.single['schedule_date'], '2026-10-10');
    },
  );

  test(
    'a today read crossing midnight is retried without relabeling the cache',
    () async {
      final service = build();
      await enqueue('yesterday-taken');
      serverTaken = true;
      now = timezone.TZDateTime(seoul, 2026, 10, 10, 23, 59);
      duringTodayRead = () async {
        now = timezone.TZDateTime(seoul, 2026, 10, 11, 0, 1);
      };
      expect(await service.synchronize(), isFalse);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
      expect(await store.readCache('patient-a'), isNull);
      expect(await store.pending('patient-a'), hasLength(1));

      duringTodayRead = null;
      serverTaken = false;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(
        (await store.pending('patient-a')).single['schedule_date'],
        '2026-10-10',
      );
    },
  );

  test('a partial offline completion preserves the slot reminder', () async {
    secondMorningMedication = true;
    await enqueue('one-of-two-taken');
    expect(await build().synchronize(), isTrue);
    expect(dates('morning').first, DateTime(2026, 10, 10));
    expect(await store.pending('patient-a'), hasLength(1));
  });

  test(
    'another patient queue is not projected or activated by refresh',
    () async {
      await store.activate('patient-b');
      await enqueue('other-patient-taken', owner: 'patient-b');
      await store.activate('patient-a');
      expect(await build().synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 10));
      expect(await store.pending('patient-b'), hasLength(1));
      expect(await store.pending('patient-a'), isEmpty);
      expect(await store.isActive('patient-a'), isTrue);
    },
  );

  test(
    'temporary outbox failure leaves reminders and queued events intact then recovers',
    () async {
      await enqueue('offline-taken');
      var unavailable = true;
      final service = build(
        openDoseStore: () async {
          if (unavailable) throw StateError('temporary storage failure');
          return store;
        },
      );
      expect(await service.synchronize(), isFalse);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
      expect(await store.pending('patient-a'), hasLength(1));

      unavailable = false;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(await store.pending('patient-a'), hasLength(1));
    },
  );

  test(
    'a sync receipt arriving during the read wins over the stale server snapshot',
    () async {
      await enqueue('taken-in-flight');
      final claimed = await store.claim(
        'patient-a',
        'test-lease',
        now.millisecondsSinceEpoch,
      );
      expect(claimed, isNotNull);
      duringTodayRead = () =>
          store.acknowledge('patient-a', 'taken-in-flight', 'test-lease', {
            'date': doseScheduleDay(now),
            'schedules': [medication(taken: true).toJson()],
          });
      expect(await build().synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(await store.pending('patient-a'), isEmpty);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      final cache = await store.readCache('patient-a');
      expect(
        MedicationSchedule.fromScheduleJsonList(
          cache?['schedules'],
        ).single.isSlotCompleted('morning'),
        isTrue,
      );
    },
  );

  test(
    'a receipt changing during the local snapshot requests retry instead of rearming',
    () async {
      await enqueue('taken-in-flight');
      await store.claim('patient-a', 'test-lease', now.millisecondsSinceEpoch);
      final interleaved = _ReceiptDuringCacheReadStore(
        db,
        store.key,
        () => store.acknowledge('patient-a', 'taken-in-flight', 'test-lease', {
          'date': doseScheduleDay(now),
          'schedules': [medication(taken: true).toJson()],
        }),
      );
      final service = build(openDoseStore: () async => interleaved);
      expect(await service.synchronize(), isFalse);
      expect(interleaved.received, isTrue);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);

      serverTaken = true;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );
}
