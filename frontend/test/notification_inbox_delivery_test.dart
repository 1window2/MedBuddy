// 파일명: notification_inbox_delivery_test.dart
// 역할: 플랫폼 알림 표시·예약 결과와 알림함 기록의 연결을 검증한다.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';

// 함수이름: main
// 함수역할: 실제 Service와 플랫폼 호출 대역을 연결한다. 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  final service = NotificationService.instance;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var failShow = false;
  var switchDuringSchedule = false;

  // 함수이름: setUp 콜백
  // 함수역할: 기록과 플랫폼 호출을 초기화한다. 매개변수: 없음. 반환값: 없음.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    service.setHistoryUser('patient', persistSession: false);
    service.setShowSensitiveDetails(true);
    calls.clear();
    failShow = false;
    switchDuringSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {'notificationLaunchedApp': false};
          }
          if (call.method == 'pendingNotificationRequests' ||
              call.method == 'getActiveNotifications') {
            return <dynamic>[];
          }
          if (call.method == 'show' && failShow) {
            throw PlatformException(code: 'failed');
          }
          if (call.method == 'zonedSchedule' && switchDuringSchedule) {
            service.setHistoryUser('caregiver', persistSession: false);
          }
          return true;
        });
  });

  // 함수이름: tearDown 콜백
  // 함수역할: 플랫폼 대역을 해제한다. 매개변수: 없음. 반환값: 없음.
  tearDown(() {
    service.setHistoryUser(null, persistSession: false);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 함수이름: 로컬 알림 기록 테스트
  // 함수역할: 표시 성공한 알림만 소유 계정에 중복 없이 저장한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'chat inbox keeps the displayed preview in the correct account',
    () async {
      await service.showLinkedChatAlert(
        id: 101,
        linkId: 7,
        messagePreview: '  저녁 약은 식사 후에 챙겨 드세요.\n확인 부탁해요.  ',
        historyUserHash: 'patient',
      );
      await service.showLinkedChatAlert(
        id: 101,
        linkId: 7,
        historyUserHash: 'patient',
      );
      await service.showCaregiverAlert(
        id: 102,
        title: 'test',
        body: 'private status',
        patientHash: 'patient',
        historyUserHash: 'caregiver',
      );
      final patient = await NotificationInboxStore(userHash: 'patient').load();
      expect(patient, hasLength(1));
      expect(patient.single.payload, 'chat:7');
      expect(patient.single.body, '저녁 약은 식사 후에 챙겨 드세요. 확인 부탁해요.');
      expect(
        (calls.firstWhere((call) => call.method == 'show').arguments
            as Map)['body'],
        patient.single.body,
      );
      expect(
        await NotificationInboxStore(userHash: 'caregiver').load(),
        hasLength(1),
      );
      failShow = true;
      await expectLater(
        service.showLinkedChatAlert(id: 103, linkId: 7),
        throwsA(isA<PlatformException>()),
      );
      expect(
        await NotificationInboxStore(userHash: 'patient').load(),
        hasLength(1),
      );
    },
  );

  // 함수이름: 내용 숨김 테스트
  // 함수역할: 종류만 표시하는 설정은 시스템 알림과 알림함 양쪽에서 본문을 숨긴다.
  // 매개변수: 없음. 반환값: 표시·저장 내용 검증 완료.
  test('type-only privacy excludes chat content from history', () async {
    service.setShowSensitiveDetails(false);
    await service.showLinkedChatAlert(
      id: 104,
      linkId: 7,
      messagePreview: '숨겨야 하는 채팅 내용',
      language: 'en',
    );
    final entry = (await NotificationInboxStore(
      userHash: 'patient',
    ).load()).single;
    expect(
      entry.body,
      'You received a new message from a linked family member.',
    );
    expect(
      (calls.singleWhere((call) => call.method == 'show').arguments
          as Map)['body'],
      entry.body,
    );
  });

  // 함수이름: 미리보기 정규화 테스트
  // 함수역할: 공백만 있는 메시지는 대체 문구로, 긴 메시지는 제한된 미리보기로 표시한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('chat previews handle blank and long messages', () {
    expect(
      NotificationService.buildLinkedChatNotificationBody(
        messagePreview: ' \n ',
      ),
      '연동된 가족에게 새 메시지가 도착했습니다.',
    );
    final preview = NotificationService.buildLinkedChatNotificationBody(
      messagePreview: List.filled(180, '약').join(),
    );
    expect(preview.length, 120);
    expect(preview.endsWith('…'), isTrue);
  });

  // 함수이름: 예약 연결 테스트
  // 함수역할: 예약 시각 전 숨김·시각 후 표시·취소를 검증한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'scheduled reminder events stay hidden until due and cancellation removes future entries',
    () async {
      await service.initialize();
      final tomorrow = tz.TZDateTime.now(tz.local).add(const Duration(days: 1));
      await service.registerNotification(
        id: 12,
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 8,
        minute: 0,
        medicationNames: const ['private pill'],
        activeDates: [tomorrow],
      );
      expect(await NotificationInboxStore(userHash: 'patient').load(), isEmpty);
      final later = NotificationInboxStore(
        userHash: 'patient',
        now: () => tomorrow.add(const Duration(days: 1)),
      );
      final entries = await later.load();
      expect(entries, hasLength(1));
      expect(entries.single.body, isNot(contains('private pill')));
      expect(
        calls.where((call) => call.method == 'zonedSchedule'),
        hasLength(1),
      );
      await service.cancelReminder(12, slotKey: 'morning');
      expect(await later.load(), isEmpty);
    },
  );

  // 함수이름: 예약 중 계정 변경 테스트
  // 함수역할: 이전 계정의 남은 예약을 새 계정에 저장하지 않는다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'account change during scheduling cannot write remaining reminders to the new user',
    () async {
      await service.initialize();
      final tomorrow = tz.TZDateTime.now(tz.local).add(const Duration(days: 1));
      switchDuringSchedule = true;
      await service.registerNotification(
        id: 12,
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 8,
        minute: 0,
        medicationNames: const [],
        activeDates: [tomorrow, tomorrow.add(const Duration(days: 1))],
      );
      final later = tomorrow.add(const Duration(days: 3));
      expect(
        await NotificationInboxStore(
          userHash: 'caregiver',
          now: () => later,
        ).load(),
        isEmpty,
      );
      expect(
        await NotificationInboxStore(
          userHash: 'patient',
          now: () => later,
        ).load(),
        hasLength(1),
      );
    },
  );
}
