// 파일명: notification_inbox_test.dart
// 역할: 계정별 알림 저장·예약·푸시 처리와 알림함 화면을 검증한다.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/notification_inbox_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/manage_notification_inbox_control.dart';
import 'package:medbuddy_frontend/entities/notification_inbox_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: _entry
// 함수역할: 고정 시각의 테스트 알림을 만든다. 매개변수: id, date, chat. 반환값: 알림.
NotificationInboxEntry _entry(String id, DateTime date, {bool chat = false}) =>
    NotificationInboxEntry(
      id: id,
      title: chat ? '새 메시지' : '복약 시간',
      body: '테스트 알림 내용',
      payload: chat ? 'chat:7' : 'schedule:morning:12:2026-09-11',
      category: chat
          ? NotificationInboxCategory.chat
          : NotificationInboxCategory.medication,
      occurredAt: date,
    );

// 함수이름: main
// 함수역할: 저장·수신·화면 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late NotificationInboxStore store;

  // 함수이름: setUp 콜백
  // 함수역할: 테스트마다 계정과 시간을 초기화한다. 매개변수: 없음. 반환값: 없음.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 11, 12);
    store = NotificationInboxStore(userHash: 'patient', now: () => now);
  });

  // 함수이름: 계정 격리 테스트
  // 함수역할: 다른 계정의 기록이 섞이지 않는지 검사한다. 매개변수: 없음. 반환값: 검증 완료.
  test('entries are account scoped and newest first', () async {
    await store.record(_entry('older', now.subtract(const Duration(hours: 1))));
    await store.record(_entry('newer', now));
    await NotificationInboxStore(
      userHash: 'caregiver',
      now: () => now,
    ).record(_entry('other', now));
    expect((await store.load()).map((e) => e.id), ['newer', 'older']);
  });

  // 함수이름: 중복 수신 테스트
  // 함수역할: 다시 받은 알림이 읽음이나 삭제를 되돌리지 않는지 검사한다. 매개변수: 없음. 반환값: 검증 완료.
  test('duplicate delivery preserves read and deleted state', () async {
    final entry = _entry('chat:7:1', now, chat: true);
    await store.record(entry);
    await store.markRead([entry.id]);
    await store.record(entry);
    expect((await store.load()).single.isRead, isTrue);
    await store.remove([entry.id]);
    await store.record(entry);
    expect(await store.load(), isEmpty);
    final restored = NotificationInboxStore(
      userHash: 'patient',
      now: () => now,
    );
    expect(await restored.load(), isEmpty);
  });

  // 함수이름: 예약 시각 테스트
  // 함수역할: 미래 예약은 숨기고 취소 시 지난 내역은 유지한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'scheduled entries appear when due and only future ones are cancelled',
    () async {
      await store.record(_entry('reminder:12:past', now));
      await store.record(
        _entry('reminder:12:future', now.add(const Duration(hours: 1))),
      );
      expect((await store.load()).map((e) => e.id), ['reminder:12:past']);
      await store.cancelFutureReminders(slotKey: 'lunch');
      now = now.add(const Duration(hours: 1));
      expect((await store.load()).length, 2);
      await store.record(
        _entry('reminder:12:tomorrow', now.add(const Duration(days: 1))),
      );
      await store.cancelFutureReminders(slotKey: 'morning');
      now = now.add(const Duration(days: 1));
      expect((await store.load()).length, 2);
    },
  );

  // 함수이름: 보관 기간 테스트
  // 함수역할: 손상된 항목과 보관 기간 밖의 알림이 정상 목록을 막지 않는지 검사한다. 매개변수: 없음. 반환값: 검증 완료.
  test('invalid entries are isolated and expired entries are pruned', () async {
    await store.record(
      _entry('expires', now.subtract(const Duration(days: 89))),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('${store.prefix}entry.invalid', '{broken');
    now = now.add(const Duration(days: 2));
    await store.record(_entry('valid', now));
    expect((await store.load()).map((e) => e.id), ['valid']);
    expect(preferences.getString('${store.prefix}entry.expires'), isNull);
  });

  // 함수이름: 푸시 소유권 테스트
  // 함수역할: 수신 계정이 다른 푸시를 제외하고 허용된 메시지 미리보기를 저장한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'push recipient is checked and delivered chat previews are stored',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        NotificationInboxStore.activeUserKey,
        'patient',
      );
      const data = {
        'type': 'linked_chat_message',
        'link_id': '7',
        'recipient_hash': 'patient',
        'message_preview': '  약국에 도착했어요.\n곧 연락드릴게요.  ',
      };
      const message = RemoteMessage(messageId: 'one', data: data);
      await recordPushNotificationHistory(message);
      await recordPushNotificationHistory(message, markRead: true);
      await recordPushNotificationHistory(
        RemoteMessage(
          messageId: 'other',
          data: {...data, 'recipient_hash': 'caregiver'},
        ),
      );
      final entries = await NotificationInboxStore(userHash: 'patient').load();
      expect(entries, hasLength(1));
      expect(entries.single.isRead, isTrue);
      expect(entries.single.body, '약국에 도착했어요. 곧 연락드릴게요.');
      expect(entries.single.payload, 'chat:7');
      await preferences.remove(NotificationInboxStore.activeUserKey);
      await recordPushNotificationHistory(
        const RemoteMessage(messageId: 'signed-out', data: data),
      );
      expect(
        await NotificationInboxStore(userHash: 'patient').load(),
        hasLength(1),
      );
    },
  );

  // 함수이름: 푸시 내용 숨김 테스트
  // 함수역할: 서버에서 비운 미리보기는 알림 본문으로 우회해 저장하지 않는다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test(
    'explicitly hidden push content never falls back to its notification body',
    () async {
      await recordPushNotificationHistory(
        const RemoteMessage(
          messageId: 'hidden',
          data: {
            'type': 'linked_chat_message',
            'link_id': '7',
            'recipient_hash': 'patient',
            'message_preview': '',
          },
          notification: RemoteNotification(body: '숨겨야 하는 내용'),
        ),
        userHash: 'patient',
      );
      final entry = (await NotificationInboxStore(
        userHash: 'patient',
      ).load()).single;
      expect(entry.body, '연동된 가족에게 새 메시지가 도착했습니다.');
    },
  );

  // 함수이름: 구형 푸시 호환 테스트
  // 함수역할: 미리보기 필드가 없는 푸시는 실제 수신한 알림 본문을 사용한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test(
    'legacy push without preview field uses delivered notification body',
    () async {
      await recordPushNotificationHistory(
        const RemoteMessage(
          messageId: 'legacy',
          data: {
            'type': 'linked_chat_message',
            'link_id': '7',
            'recipient_hash': 'patient',
          },
          notification: RemoteNotification(body: 'I will call you soon.'),
        ),
        userHash: 'patient',
        language: 'en',
      );
      final entry = (await NotificationInboxStore(
        userHash: 'patient',
      ).load()).single;
      expect(entry.body, 'I will call you soon.');
    },
  );

  // 함수이름: 조회 실패 테스트
  // 함수역할: 저장소 장애를 오류 상태로 전달하고 복구 시 목록을 갱신한다. 매개변수: 없음. 반환값: 검증 완료.
  test('control reports storage failure and recovers', () async {
    var fails = true;
    final control = ManageNotificationInbox(
      store: NotificationInboxStore(
        userHash: 'patient',
        now: () => now,
        loadPreferences: () async {
          if (fails) throw StateError('unavailable');
          return SharedPreferences.getInstance();
        },
      ),
    );
    addTearDown(control.dispose);
    await control.refresh();
    expect(control.hasError, isTrue);
    fails = false;
    await control.refresh();
    expect(control.hasError, isFalse);
  });

  // 함수이름: 알림함 상호작용 테스트
  // 함수역할: 최신순 통합 목록·읽음·이동·삭제 확인을 검증한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('unified inbox opens, reads and confirms history deletion', (
    tester,
  ) async {
    await store.record(_entry('dose', now));
    await store.record(
      _entry('chat', now.subtract(const Duration(minutes: 1)), chat: true),
    );
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxUI(
          control: control,
          userSetting: const UserSetting(),
          onOpen: (entry) => opened = entry.payload,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(control.unreadCount, 2);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.text('전체'), findsNothing);
    expect(find.text('복약'), findsNothing);
    expect(find.text('채팅'), findsNothing);
    expect(find.text('복약 시간'), findsOneWidget);
    expect(find.text('새 메시지'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('inbox-entry-dose'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('inbox-entry-chat'))).dy,
      ),
    );
    await tester.tap(find.text('새 메시지'));
    await tester.pumpAndSettle();
    expect(opened, 'chat:7');
    expect(control.unreadCount, 1);
    await tester.tap(find.byKey(const Key('inbox-mark-all-read')));
    await tester.pumpAndSettle();
    expect(control.unreadCount, 0);
    await tester.tap(find.byKey(const Key('inbox-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(control.entries, hasLength(2));
    await tester.tap(find.byKey(const Key('inbox-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('아직 알림이 없어요'), findsOneWidget);
    expect(control.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 선택 삭제 테스트
  // 함수역할: 선택 중에는 이동·읽음 처리를 하지 않고 선택 당시 항목만 삭제한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets(
    'selection supports toggling and preserves arrivals during confirmation',
    (tester) async {
      await store.record(_entry('dose', now));
      await store.record(
        _entry('chat', now.subtract(const Duration(minutes: 1)), chat: true),
      );
      final control = ManageNotificationInbox(store: store);
      addTearDown(control.dispose);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInboxUI(
            control: control,
            userSetting: const UserSetting(),
            onOpen: (_) => opened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('inbox-entry-chat')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('inbox-check-chat')))
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('inbox-entry-dose')));
      await tester.pumpAndSettle();
      expect(opened, isFalse);
      expect(control.unreadCount, 2);
      await tester.tap(find.byKey(const Key('inbox-select-all')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('inbox-delete-selected')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('inbox-entry-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inbox-delete-selected')));
      await tester.pumpAndSettle();
      await store.record(_entry('new', now));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(
        control.entries.map((entry) => entry.id),
        unorderedEquals(['dose', 'new']),
      );
      expect(control.unreadCount, 2);
      expect(find.byKey(const Key('inbox-select-all')), findsNothing);
      expect(opened, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 전체 선택 스냅샷 테스트
  // 함수역할: 전체 선택 이후 새 알림은 선택되지 않고 뒤로가기는 선택만 취소한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('select all excludes new arrivals and back cancels selection', (
    tester,
  ) async {
    await store.record(_entry('first', now));
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxUI(
          control: control,
          userSetting: const UserSetting(),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-select-all')));
    await tester.pumpAndSettle();
    await store.record(_entry('later', now));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('inbox-check-later')))
          .value,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inbox-select')), findsOneWidget);
    expect(control.entries, hasLength(2));
    expect(control.unreadCount, 2);
  });

  // 함수이름: 알림 선택 스타일 테스트
  // 함수역할: 공통 글꼴 굵기·자간과 선택 색상·개수 안내를 검증한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('selection uses app typography and a clear selection count', (
    tester,
  ) async {
    await store.record(_entry('dose', now));
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxUI(
          control: control,
          userSetting: const UserSetting(),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox-select')));
    await tester.pumpAndSettle();
    final selectLabel = tester.widget<Text>(find.text('전체 선택'));
    expect(selectLabel.style?.fontWeight, FontWeight.w700);
    expect(selectLabel.style?.letterSpacing, 0);
    expect(selectLabel.style?.color, MedBuddyColors.textStrong);
    expect(find.text('0개 선택'), findsOneWidget);
    expect(find.text('선택한 알림 삭제'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('inbox-delete-selected')),
    );
    expect(button.style?.textStyle?.resolve({})?.fontWeight, FontWeight.w700);
    expect(button.style?.textStyle?.resolve({})?.letterSpacing, 0);
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('inbox-select-all')));
    await tester.pumpAndSettle();
    final count = tester.widget<Text>(
      find.byKey(const Key('inbox-selection-count')),
    );
    expect(count.data, '1개 선택');
    expect(count.style?.color, MedBuddyColors.primaryDark);
    expect(find.text('알림 1개 삭제'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('inbox-check-dose')))
          .activeColor,
      MedBuddyColors.primary,
    );
    expect(control.unreadCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 큰 글씨 알림함 테스트
    // 함수역할: 작은 화면과 큰 글씨에서도 알림 내용이 잘리지 않는지 확인한다. 매개변수: tester. 반환값: 검증 완료.
    testWidgets('inbox fits small screens at 2x in $language', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await store.record(_entry('dose', now));
      final control = ManageNotificationInbox(store: store);
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: NotificationInboxUI(
            control: control,
            userSetting: UserSetting(language: language),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('테스트 알림 내용'), findsOneWidget);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('inbox-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inbox-select-all')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('inbox-delete-selected')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text(language == 'en' ? '1 selected' : '1개 선택').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('inbox-delete-selected')));
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'en' ? 'Cancel' : '취소').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text(language == 'en' ? 'Cancel' : '취소'));
      await tester.pumpAndSettle();
      expect(control.entries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
