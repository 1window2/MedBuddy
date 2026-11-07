// 역할: 실제 암호화 대기열로 알림 버튼의 날짜·계정 격리, 멱등성과 백그라운드 전송을 검증한다.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/medication_notification_payload_codec.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';
import 'package:medbuddy_frontend/services/slot_check_notification_context.dart';
import 'package:medbuddy_frontend/services/slot_check_notification_service.dart';

final _now = DateTime.utc(2026, 11, 7, 3);
const _day = '2026-11-07';
Map<String, dynamic> _data([Map<String, dynamic> overrides = const {}]) => {
  'type': 'linked_chat_message',
  'message_kind': 'slot_check_request',
  'action_version': '1',
  'recipient_hash': 'patient',
  'patient_hash': 'patient',
  'link_id': '7',
  'message_id': '19',
  'event_id': 'chat:7:19',
  'schedule_date': _day,
  'slot_key': 'morning',
  'language': 'ko',
  'message_preview': '아침 약 복용을 확인해 주세요.',
  ...overrides,
};
SlotCheckNotificationContext _request([Map<String, dynamic> data = const {}]) =>
    SlotCheckNotificationContext.fromData(_data(data))!;
NotificationResponse _response([SlotCheckNotificationContext? request]) =>
    NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 99,
      actionId: SlotCheckNotificationContext.actionId,
      payload: (request ?? _request()).payload,
    );
const _schedules = [
  MedicationSchedule(
    medicationID: '11',
    medicationName: 'private-one',
    scheduleSlotKeys: ['morning', 'evening'],
    slotStatuses: {'morning': false, 'evening': false},
    regimenRevision: 2,
  ),
  MedicationSchedule(
    medicationID: '12',
    medicationName: 'private-two',
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': true},
    regimenRevision: 3,
  ),
  MedicationSchedule(
    medicationID: '13',
    medicationName: 'private-other-slot',
    scheduleSlotKeys: ['lunch'],
    slotStatuses: {'lunch': false},
  ),
];

class _Platform extends SlotCheckNotificationPlatform {
  final DoseOutboxStore store;
  final List<Map<String, dynamic>> posts = [];
  bool online = false;
  bool authFails = false;
  bool scheduleFails = false;
  Map<String, dynamic>? scheduleResponse;
  int scheduled = 0;
  int cancelled = 0;
  Future<void> Function()? duringOpen;
  _Platform(this.store);
  @override
  Future<DoseOutboxStore> openStore() async {
    await duringOpen?.call();
    return store;
  }

  @override
  Future<http.Client> openClient() async {
    if (authFails) throw StateError('No authentication');
    return MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.queryParameters['patient_hash'], 'patient');
        return scheduleResponse == null
            ? http.Response('offline', 503)
            : http.Response(jsonEncode(scheduleResponse), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      posts.add(body);
      expect(request.url.queryParameters['patient_hash'], 'patient');
      if (!online) return http.Response('offline', 503);
      return http.Response(
        jsonEncode({
          'operation_id': body['operation_id'],
          'schedule_date': _day,
          'data': _schedules.map((s) => s.toJson()).toList(),
        }),
        200,
      );
    });
  }

  @override
  Future<void> scheduleSync(String owner) async {
    scheduled++;
    if (scheduleFails) throw StateError('Work unavailable');
  }

  @override
  Future<void> cancel(SlotCheckNotificationContext request, int? id) async {
    cancelled++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late DoseOutboxStore store;
  late _Platform platform;
  late List<Map> shown;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    await store.activate('patient');
    await store.saveCache('patient', {
      'date': _day,
      'schedules': _schedules.map((s) => s.toJson()).toList(),
    });
    platform = _Platform(store);
    SlotCheckNotificationService.platform = platform;
    SlotCheckNotificationService.clock = () => _now;
    SharedPreferences.setMockInitialValues({
      NotificationInboxStore.activeUserKey: 'patient',
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    shown = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show') shown.add(call.arguments as Map);
          return call.method == 'initialize' ? true : null;
        });
  });
  tearDown(() async {
    SlotCheckNotificationService.platform =
        const SlotCheckNotificationPlatform();
    SlotCheckNotificationService.clock = DateTime.now;
    debugDefaultTargetPlatformOverride = null;
    NotificationService.setNotificationSelectionHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });

  test('잘못된 계정·날짜·식별자·필요시 시간대를 거부한다', () {
    for (final override in [
      {'patient_hash': 'other'},
      {'recipient_hash': ''},
      {'schedule_date': '2026-02-30'},
      {'schedule_date': '2026-11-7'},
      {'slot_key': 'as_needed'},
      {'slot_key': 'unknown'},
      {'link_id': '0'},
      {'message_id': '-1'},
      {'event_id': 'chat:7:20'},
      {'action_version': '2'},
      {'message_kind': 'text'},
    ]) {
      expect(
        SlotCheckNotificationContext.fromData(_data(override)),
        isNull,
        reason: '$override',
      );
    }
    expect(
      SlotCheckNotificationContext.fromPayload('slot-check-v1:{broken'),
      isNull,
    );
    final decoded = MedicationNotificationPayloadCodec.decode(
      _request().payload,
    );
    expect(decoded?.linkId, 7);
    expect(
      MedicationNotificationPayloadCodec.isSessionPayload(_request().payload),
      isTrue,
    );
  });

  test('백그라운드 푸시는 앱을 열지 않는 완료 버튼을 한 번만 표시한다', () async {
    await medBuddyPushBackgroundHandler(
      RemoteMessage(messageId: 'one', data: _data()),
    );
    await medBuddyPushBackgroundHandler(
      RemoteMessage(messageId: 'retry', data: _data()),
    );
    expect(shown, hasLength(1));
    final action =
        ((shown.single['platformSpecifics'] as Map)['actions'] as List).single
            as Map;
    expect(action['id'], SlotCheckNotificationContext.actionId);
    expect(action['title'], '복용 완료');
    expect(action['showsUserInterface'], isFalse);
    expect(action['cancelNotification'], isFalse);
    expect(
      (await NotificationInboxStore(userHash: 'patient').load()),
      hasLength(1),
    );
  });

  test('서버에서 숨긴 미리보기를 알림 본문으로 복원하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      RemoteMessage(data: _data({'message_preview': '', 'body': 'private'})),
    );
    expect(shown.single['body'], isNot(contains('private')));
    expect(shown.single['body'], isNot(contains('아침')));
  });

  test('백그라운드 진입점은 해당 날짜·시간대만 암호화 저장하고 UI를 열지 않는다', () async {
    var navigated = false;
    NotificationService.setNotificationSelectionHandler((_) {
      navigated = true;
    });
    await medBuddySlotCheckNotificationBackground(_response());
    final pending = await store.pending('patient');
    expect(pending, hasLength(1));
    expect(pending.single['medication_ids'], [11, 12]);
    expect(pending.single['schedule_date'], _day);
    expect(pending.single['slot_key'], 'morning');
    expect(pending.single['regimen_revisions'], {'11': 2, '12': 3});
    expect(pending.single['link_id'], 7);
    expect(platform.scheduled, 1);
    expect(navigated, isFalse);
    expect(
      jsonEncode(await db.query('operations')),
      isNot(contains('morning')),
    );
  });

  test('동시 중복 클릭·새 저장소 인스턴스·서버 ACK 뒤에도 한 요청만 유지한다', () async {
    final results = await Future.wait(
      List.generate(
        5,
        (_) => store.recordSlotCheck(_request(), clock: () => _now),
      ),
    );
    expect(results.every((value) => value), isTrue);
    final pending = await store.pending('patient');
    expect(pending, hasLength(1));
    final reopened = DoseOutboxStore(db, store.key);
    expect(
      await reopened.recordSlotCheck(_request(), clock: () => _now),
      isTrue,
    );
    platform.online = true;
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect(await store.pending('patient'), isEmpty);
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect(platform.posts, hasLength(1));
  });

  test('로그아웃·계정 변경·지난날·미래 알림은 저장하지 않는다', () async {
    for (final day in ['2026-11-06', '2026-11-08']) {
      expect(
        await SlotCheckNotificationService.handle(
          _response(_request({'schedule_date': day})),
        ),
        isFalse,
      );
    }
    await store.activate(null);
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    await store.activate('other');
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    await store.activate('patient');
    await (await SharedPreferences.getInstance()).setString(
      NotificationInboxStore.activeUserKey,
      'other',
    );
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(await store.pending('patient'), isEmpty);
    expect(platform.posts, isEmpty);
  });

  test('계정 확인 뒤 자정·계정 전환이 일어나도 다시 검사한다', () async {
    platform.duringOpen = () async {
      SlotCheckNotificationService.clock = () =>
          _now.add(const Duration(days: 1));
    };
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    SlotCheckNotificationService.clock = () => _now;
    platform.duringOpen = () => store.activate('other');
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(await store.pending('patient'), isEmpty);
  });

  test('인증·작업 예약 실패에도 이미 저장한 기록은 다음 전송까지 보존한다', () async {
    platform.authFails = true;
    platform.scheduleFails = true;
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    final id = (await store.pending('patient')).single['operation_id'];
    platform.authFails = false;
    platform.online = true;
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect(platform.posts.single['operation_id'], id);
    expect(await store.pending('patient'), isEmpty);
  });

  test('일정을 확인할 수 없으면 성공으로 처리하거나 알림을 지우지 않는다', () async {
    await store.clearAccount('patient');
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(platform.cancelled, 0);
    expect(await store.pending('patient'), isEmpty);
  });

  test('일반 본문 클릭이나 다른 동작 ID는 복용 기록을 만들지 않는다', () async {
    expect(
      await SlotCheckNotificationService.handle(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: _request().payload,
        ),
      ),
      isFalse,
    );
    expect(await store.pending('patient'), isEmpty);
  });

  test('다른 확인 요청도 이미 완료 대기 중인 정기복용을 다시 큐에 넣지 않는다', () async {
    expect(await store.recordSlotCheck(_request(), clock: () => _now), isTrue);
    expect(
      await store.recordSlotCheck(
        _request({'message_id': '20', 'event_id': 'chat:7:20'}),
        clock: () => _now,
      ),
      isTrue,
    );
    expect(await store.pending('patient'), hasLength(1));
  });

  test('서버에서 이미 완료된 시간대는 새 전송 요청 없이 확인만 한다', () async {
    await store.saveCache('patient', {
      'date': _day,
      'schedules': _schedules
          .map(
            (s) => s
                .copyWith(
                  slotStatuses: {for (final slot in s.slotKeys) slot: true},
                )
                .toJson(),
          )
          .toList(),
    });
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect(await store.pending('patient'), isEmpty);
    expect(platform.posts, isEmpty);
  });

  test('기록 취소 뒤 같은 버튼 재시도는 취소를 되돌리지 않는다', () async {
    await store.recordSlotCheck(_request(), clock: () => _now);
    final first = (await store.pending('patient')).single;
    final claimed = await store.claim(
      'patient',
      'test-lease',
      _now.millisecondsSinceEpoch,
    );
    expect(claimed?['operation_id'], first['operation_id']);
    await store.acknowledge(
      'patient',
      first['operation_id'] as String,
      'test-lease',
      {'date': _day, 'schedules': _schedules.map((s) => s.toJson()).toList()},
    );
    expect(await store.recordSlotCheck(_request(), clock: () => _now), isTrue);
    expect(await store.pending('patient'), isEmpty);
  });

  test('저장소 내부 처리 중 자정이 지나면 기록도 소비 표식도 남기지 않는다', () async {
    var reads = 0;
    expect(
      await store.recordSlotCheck(
        _request(),
        clock: () => reads++ == 0 ? _now : _now.add(const Duration(days: 1)),
      ),
      isFalse,
    );
    expect(await store.pending('patient'), isEmpty);
    expect(await store.recordSlotCheck(_request(), clock: () => _now), isTrue);
  });

  test('캐시가 없으면 날짜가 검증된 서버 기간으로 복용할 약만 복구한다', () async {
    await store.clearAccount('patient');
    platform.scheduleResponse = {
      'success': true,
      'window_start': _day,
      'window_end': '2026-11-20',
      'data': _schedules
          .map((item) => {...item.toJson(), 'created_date': _day})
          .toList(),
    };
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect((await store.pending('patient')).single['medication_ids'], [11, 12]);
    expect(platform.posts.single['schedule_date'], _day);
  });

  test('서버 일정의 날짜 범위가 다르면 캐시도 기록도 만들지 않는다', () async {
    await store.clearAccount('patient');
    platform.scheduleResponse = {
      'success': true,
      'window_start': '2026-11-06',
      'window_end': '2026-11-19',
      'data': _schedules
          .map((item) => {...item.toJson(), 'created_date': _day})
          .toList(),
    };
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(await store.pending('patient'), isEmpty);
    expect(platform.cancelled, 0);
  });

  test('디스크 저장 실패는 소비 표식을 남기지 않아 같은 버튼으로 재시도할 수 있다', () async {
    await db.execute(
      "CREATE TRIGGER fail_slot_check BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'test storage failure'); END",
    );
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(platform.cancelled, 0);
    expect(await store.pending('patient'), isEmpty);
    await db.execute('DROP TRIGGER fail_slot_check');
    expect(await SlotCheckNotificationService.handle(_response()), isTrue);
    expect(await store.pending('patient'), hasLength(1));
  });
}
