// 파일명: slot_check_notification_test.dart
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
// 함수이름: _data
// 함수역할:
// - 기본 환자·날짜·아침 시간대의 확인 요청에 지정 필드를 덮어써 정상 및 손상 푸시 입력을 만든다.
// 매개변수:
// - overrides(Map<String, dynamic>): 기본 값을 대체할 필드; 기본값은 빈 맵.
// 반환값:
// - Map<String, dynamic>: 호출마다 새로 만든 FCM 데이터.
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
// 함수이름: _request
// 함수역할:
// - 기본 확인 요청에 변경값을 적용하고 유효한 컨텍스트로 파싱한다.
// 매개변수:
// - data(Map<String, dynamic>): 기본 푸시 필드의 변경값.
// 반환값:
// - SlotCheckNotificationContext: 파싱 결과; 유효하지 않은 입력은 null 단언에서 실패한다.
SlotCheckNotificationContext _request([Map<String, dynamic> data = const {}]) =>
    SlotCheckNotificationContext.fromData(_data(data))!;
// 함수이름: _response
// 함수역할:
// - 완료 동작 ID와 지정 요청 페이로드를 갖는 알림 버튼 응답을 만든다.
// 매개변수:
// - request(SlotCheckNotificationContext?): 사용할 요청; 생략하면 기본 요청.
// 반환값:
// - NotificationResponse: 고정 알림 ID 99의 완료 버튼 선택.
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

// 클래스명: _Platform
// 역할: 실제 암호화 저장소와 가짜 네트워크·알림 동작을 연결하는 테스트 플랫폼.
// 주요 책임: 인증/예약 실패 및 저장소 개방 중 상태 변경을 주입하고 전송과 후속 작업을 기록한다.
// 속성: store는 저장소, posts/scheduleResponse는 요청 기록과 일정 응답, 실패 플래그와 각 카운터는 시나리오 상태이며 duringOpen은 개방 시 실행 훅이다.
class _Platform extends SlotCheckNotificationPlatform {
  final DoseOutboxStore store;
  final List<Map<String, dynamic>> posts = [];
  bool online = false;
  bool authFails = false;
  bool scheduleFails = false;
  Map<String, dynamic>? scheduleResponse;
  int scheduled = 0;
  int cancelled = 0;
  int dismissed = 0;
  int widgetRefreshes = 0;
  Future<void> Function()? duringOpen;
  // 함수이름: _Platform
  // 함수역할:
  // - 알림 동작이 사용할 실제 테스트 저장소를 연결한다.
  // 매개변수:
  // - store(DoseOutboxStore): 각 테스트에서 초기화한 암호화 저장소.
  // 반환값:
  // - 새 _Platform 인스턴스.
  _Platform(this.store);
  // 함수이름: openStore
  // 함수역할:
  // - 선택적 개방 훅이 완료된 뒤 저장소를 반환해 날짜·계정 변경 경합을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DoseOutboxStore>: 주입한 저장소; 훅의 오류는 호출자에게 전달된다.
  @override
  Future<DoseOutboxStore> openStore() async {
    await duringOpen?.call();
    return store;
  }

  // 함수이름: openClient
  // 함수역할:
  // - 인증 실패를 주입하거나 환자 쿼리를 검증하는 가짜 일정 조회·복용 전송 클라이언트를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<http.Client>: 설정에 따라 503 또는 일정/승인 JSON을 반환하는 클라이언트; authFails이면 StateError.
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

  // 함수이름: scheduleSync
  // 함수역할:
  // - 동기화 예약 호출 수를 늘리고 선택적으로 작업 예약 실패를 발생시킨다.
  // 매개변수:
  // - owner(String): 예약 대상 계정; 이 가짜 구현은 값 대신 호출 횟수만 기록한다.
  // 반환값:
  // - Future<void>: 예약 호출 기록 완료; scheduleFails이면 StateError.
  @override
  Future<void> scheduleSync(String owner) async {
    scheduled++;
    if (scheduleFails) throw StateError('Work unavailable');
  }

  // 함수이름: cancel
  // 함수역할:
  // - 알림 취소 호출 수를 기록하며 실제 플랫폼 알림은 조작하지 않는다.
  // 매개변수:
  // - request(SlotCheckNotificationContext): 취소 대상 요청; 값은 검사하지 않는다.
  // - id(int?): 알림 ID; 값은 검사하지 않는다.
  // 반환값:
  // - Future<void>: 취소 카운터 갱신 완료.
  @override
  Future<void> cancel(SlotCheckNotificationContext request, int? id) async {
    cancelled++;
  }

  // Function Name: dismiss
  // Description:
  // - Counts stale-notification dismissal without contacting the platform.
  // Parameters:
  // - request (SlotCheckNotificationContext): Requested notification; not inspected.
  // - id (int?): Notification identifier; not inspected.
  // Returns:
  // - Future<void>: Completes after incrementing dismissed.
  @override
  Future<void> dismiss(SlotCheckNotificationContext request, int? id) async {
    dismissed++;
  }

  // Function Name: refreshWidget
  // Description:
  // - Counts widget refresh requests after a dose is recorded.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes after incrementing widgetRefreshes.
  @override
  Future<void> refreshWidget() async {
    widgetRefreshes++;
  }
}

// 함수이름: main
// 함수역할:
// - 알림 페이로드 해석부터 빠른 복용 기록·중복 방지·계정 변경과 오프라인 전송까지 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late DoseOutboxStore store;
  late _Platform platform;
  late List<Map> shown;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  // 함수이름: setUp
  // 함수역할:
  // - 메모리 DB와 암호화 키·환자 캐시를 생성하고 고정 시계 및 Android 알림 채널을 주입한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 독립된 테스트 환경 준비 완료.
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
  // 함수이름: tearDown
  // 함수역할:
  // - 서비스 플랫폼·시계·선택 핸들러와 모의 채널을 원복하고 메모리 DB를 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 전역 상태 및 저장소 정리 완료.
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

  // 함수이름: 잘못된 계정·날짜·식별자·필요시 시간대를 거부한다
  // 함수역할:
  // - 계정 불일치·잘못된 날짜/식별자/시간대/버전을 거부하고 정상 페이로드의 연결 ID와 세션 표시를 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 백그라운드 푸시는 앱을 열지 않는 완료 버튼을 한 번만 표시한다
  // 함수역할:
  // - 같은 요청을 두 번 수신해도 알림과 받은함 항목을 한 번만 만들며 완료 버튼이 앱을 열거나 즉시 알림을 취소하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // Function Name: 자정을 넘겨 도착한 요청은 버튼 없이 표시한다
  // Description:
  // - Delivers a request one day late and verifies the notification has no completion action.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('자정을 넘겨 도착한 요청은 버튼 없이 표시한다', () async {
    SlotCheckNotificationService.clock = () => _now.add(const Duration(days: 1));
    await medBuddyPushBackgroundHandler(RemoteMessage(data: _data()));
    expect(shown, hasLength(1));
    expect((shown.single['platformSpecifics'] as Map)['actions'], isNull);
  });

  // Function Name: 지난날 요청의 버튼은 기록하지 않고 알림만 지운다
  // Description:
  // - Rejects both past and future actions without recording a dose, dismissing only the past notification.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('지난날 요청의 버튼은 기록하지 않고 알림만 지운다', () async {
    expect(
      await SlotCheckNotificationService.handle(
        _response(_request({'schedule_date': '2026-11-06'})),
      ),
      isFalse,
    );
    expect(platform.dismissed, 1);
    expect(
      await SlotCheckNotificationService.handle(
        _response(_request({'schedule_date': '2026-11-08'})),
      ),
      isFalse,
    );
    expect(platform.dismissed, 1);
    expect(await store.pending('patient'), isEmpty);
  });

  // 함수이름: 서버에서 숨긴 미리보기를 알림 본문으로 복원하지 않는다
  // 함수역할:
  // - 서버가 미리보기를 비운 경우 대체 body나 기본 시간대 문구에서 비공개 내용을 복원하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('서버에서 숨긴 미리보기를 알림 본문으로 복원하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      RemoteMessage(data: _data({'message_preview': '', 'body': 'private'})),
    );
    expect(shown.single['body'], isNot(contains('private')));
    expect(shown.single['body'], isNot(contains('아침')));
  });

  // Function Name: 백그라운드 진입점은 해당 날짜·시간대만 암호화 저장하고 UI를 열지 않는다
  // Description:
  // - Records only the requested morning medications with revisions, names and link metadata; checks encrypted storage, scheduled sync and widget refresh without navigation.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
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
    expect(pending.single['medication_names'], ['private-one', 'private-two']);
    expect(platform.scheduled, 1);
    expect(platform.widgetRefreshes, 1);
    expect(navigated, isFalse);
    expect(
      jsonEncode(await db.query('operations')),
      isNot(contains('morning')),
    );
  });

  // 함수이름: 동시 중복 클릭·새 저장소 인스턴스·서버 ACK 뒤에도 한 요청만 유지한다
  // 함수역할:
  // - 동시 클릭·저장소 재생성·서버 승인 후 재시도를 거쳐도 대기 작업과 서버 전송이 각각 한 번인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 로그아웃·계정 변경·지난날·미래 알림은 저장하지 않는다
  // 함수역할:
  // - 과거·미래 날짜, 로그아웃, 저장소나 받은함의 다른 계정에서는 기록과 서버 전송을 만들지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 계정 확인 뒤 자정·계정 전환이 일어나도 다시 검사한다
  // 함수역할:
  // - 저장소를 여는 동안 날짜나 활성 계정이 바뀌면 최초 확인을 통과했어도 기록을 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 인증·작업 예약 실패에도 이미 저장한 기록은 다음 전송까지 보존한다
  // 함수역할:
  // - 인증과 작업 예약이 실패해도 저장한 작업을 유지하고 복구 후 같은 operation_id로 전송하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 일정을 확인할 수 없으면 성공으로 처리하거나 알림을 지우지 않는다
  // 함수역할:
  // - 일정 캐시도 서버 응답도 없으면 실패를 반환하고 알림 취소나 복용 기록을 만들지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('일정을 확인할 수 없으면 성공으로 처리하거나 알림을 지우지 않는다', () async {
    await store.clearAccount('patient');
    expect(await SlotCheckNotificationService.handle(_response()), isFalse);
    expect(platform.cancelled, 0);
    expect(await store.pending('patient'), isEmpty);
  });

  // 함수이름: 일반 본문 클릭이나 다른 동작 ID는 복용 기록을 만들지 않는다
  // 함수역할:
  // - 완료 동작이 아닌 알림 본문 선택은 처리하지 않고 대기 기록도 만들지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 다른 확인 요청도 이미 완료 대기 중인 정기복용을 다시 큐에 넣지 않는다
  // 함수역할:
  // - 서로 다른 확인 메시지가 같은 미전송 복용을 가리켜도 기존 대기 작업 하나만 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 서버에서 이미 완료된 시간대는 새 전송 요청 없이 확인만 한다
  // 함수역할:
  // - 모든 시간대가 이미 완료된 서버 캐시에서는 성공을 반환하되 새 작업이나 전송을 만들지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 기록 취소 뒤 같은 버튼 재시도는 취소를 되돌리지 않는다
  // 함수역할:
  // - 처리된 요청을 미완료 상태의 서버 캐시로 승인한 뒤 같은 버튼을 눌러도 취소된 기록을 다시 생성하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 저장소 내부 처리 중 자정이 지나면 기록도 소비 표식도 남기지 않는다
  // 함수역할:
  // - 저장소 내부 두 번째 시각 검사에서 자정이 지나면 거부하고, 원래 날짜로 재시도할 수 있도록 소비 표식을 남기지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 캐시가 없으면 날짜가 검증된 서버 기간으로 복용할 약만 복구한다
  // 함수역할:
  // - 캐시가 없을 때 요청 날짜와 맞는 서버 기간으로 복구하고 해당 아침 약 ID와 날짜만 기록하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 서버 일정의 날짜 범위가 다르면 캐시도 기록도 만들지 않는다
  // 함수역할:
  // - 서버 기간의 시작일이 요청 날짜와 다르면 실패를 반환하고 대기 기록과 알림 취소를 만들지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 디스크 저장 실패는 소비 표식을 남기지 않아 같은 버튼으로 재시도할 수 있다
  // 함수역할:
  // - DB 삽입 실패 시 알림과 재시도 가능 상태를 유지하며 오류 트리거를 제거한 뒤 같은 버튼으로 한 번 기록하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
