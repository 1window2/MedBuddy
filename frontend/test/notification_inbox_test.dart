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
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

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

// Function Name: main
// Description: Register inbox persistence, push deduplication/privacy, and accessible selection/navigation regressions.
// Parameters: None.
// Returns: void: Registers fixtures and test callbacks; assertions run in those callbacks.
void main() {
  // 함수이름: test: '필요시 복용 푸시 재전송은 읽음 상태를 보존하고 한 건으로 유지한다'
  // 함수역할: 같은 필요시 복용 event_key를 읽음 처리·재전송·삭제 뒤 재전송하고 다른 event_key도 수신한다.
  // 매개변수: 없음.
  // 반환값: 반환값 없음; 같은 복용은 한 건의 읽음 상태와 삭제를 유지하며 별도 복용만 새 안 읽음 항목으로 남는다.
  test('필요시 복용 푸시 재전송은 읽음 상태를 보존하고 한 건으로 유지한다', () async {
    final store = NotificationInboxStore(userHash: 'caregiver');
    final data = {
      'type': 'caregiver_dose_completed', 'slot_key': 'as_needed',
      'recipient_hash': 'caregiver', 'patient_hash': 'patient',
      'event_key': 'a' * 64,
    };
    await recordPushNotificationHistory(RemoteMessage(messageId: 'first', data: data),
      userHash: 'caregiver', markRead: true);
    await recordPushNotificationHistory(RemoteMessage(messageId: 'retry', data: data),
      userHash: 'caregiver');
    var entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.isRead, isTrue);
    await store.remove([entries.single.id]);
    await recordPushNotificationHistory(RemoteMessage(messageId: 'retry-again', data: data),
      userHash: 'caregiver');
    expect(await store.load(), isEmpty);
    await recordPushNotificationHistory(RemoteMessage(messageId: 'second-dose',
      data: {...data, 'event_key': 'b' * 64}), userHash: 'caregiver');
    entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.isRead, isFalse);
  });
  // Function Name: test: '채팅 푸시 재전송은 서버 event_id로 한 건만 남긴다'
  // Description: Deliver chat retries with different FCM message IDs but the same server event_id, then a new event_id.
  // Parameters: None.
  // Returns: No value; retries collapse to one entry while a distinct chat event creates a second entry.
  test('채팅 푸시 재전송은 서버 event_id로 한 건만 남긴다', () async {
    final store = NotificationInboxStore(userHash: 'caregiver');
    final data = {
      'type': 'linked_chat_message', 'recipient_hash': 'caregiver',
      'link_id': '3', 'event_id': 'chat:3:10', 'message_preview': '약 드셨어요?',
    };
    await recordPushNotificationHistory(RemoteMessage(messageId: 'fcm-1', data: data),
      userHash: 'caregiver');
    await recordPushNotificationHistory(RemoteMessage(messageId: 'fcm-2', data: data),
      userHash: 'caregiver');
    expect(await store.load(), hasLength(1));
    await recordPushNotificationHistory(RemoteMessage(messageId: 'fcm-3',
      data: {...data, 'event_id': 'chat:3:11'}), userHash: 'caregiver');
    expect(await store.load(), hasLength(2));
  });
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

  // 함수이름: test: '기존 정형 복약 알림은 현재 언어로 표시하고 채팅은 보존한다'
  // 함수역할: 기존 한글·영문 정형 복약 알림과 필요시 알림을 다른 언어로 표시하고 사용자 문구·채팅 본문을 비교한다.
  // 매개변수: 없음.
  // 반환값: 반환값 없음; 알려진 정형 제목·본문만 현재 언어로 바뀌며 사용자 작성 문구와 채팅은 보존된다.
  test('기존 정형 복약 알림은 현재 언어로 표시하고 채팅은 보존한다', () {
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    // 함수이름: reminder
    // 함수역할: 같은 고정 ID·기준 시각에 시간대와 원래 표시 문구가 다른 복약 알림을 만든다.
    // 매개변수: slot (String): schedule payload 시간대; title (String): 저장 제목; body (String): 저장 본문.
    // 반환값: NotificationInboxEntry: 번역 판별에 사용할 복약 알림.
    NotificationInboxEntry reminder(String slot, String title, String body) =>
        NotificationInboxEntry(
          id: 'reminder:12:1',
          title: title,
          body: body,
          payload: 'schedule:$slot:12:2026-09-11',
          category: NotificationInboxCategory.medication,
          occurredAt: now,
        );
    final korean = reminder('lunch', '점심 복약 일정 확인', '복약 일정과 복용 완료 기록을 확인해 주세요.');
    expect(control.titleFor(korean, isEnglish: true), 'Lunch medication schedule');
    expect(control.bodyFor(korean, isEnglish: true), 'Check your medication schedule and recorded completion status.');
    final english = reminder('morning', 'Morning medication schedule', 'Check your medication schedule and recorded completion status.');
    expect(control.titleFor(english, isEnglish: false), '아침 복약 일정 확인');
    expect(control.bodyFor(english, isEnglish: false), '복약 일정과 복용 완료 기록을 확인해 주세요.');
    final needed = reminder('as_needed', '필요시 약 확인', '필요시 약과 오늘 기록한 복용 내역을 확인해 주세요.');
    expect(control.titleFor(needed, isEnglish: true), 'As-needed medication check');
    expect(control.bodyFor(needed, isEnglish: true), 'Check your as-needed medication and recorded doses.');
    final custom = reminder('lunch', '사용자 제목', '사용자 내용');
    expect(control.titleFor(custom, isEnglish: true), custom.title);
    expect(control.bodyFor(custom, isEnglish: true), custom.body);
    final chat = _entry('chat', now, chat: true);
    expect(control.bodyFor(chat, isEnglish: true), chat.body);
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

  // Function Name: test: 'removing a notification erases its stored content'
  // Description: Delete one of two chat notifications, inspect its stored tombstone, then load again after 91 days.
  // Parameters: None.
  // Returns: No value; title/body/navigation payload are erased immediately, the other row remains, and expired tombstone keys are eventually removed.
  test('removing a notification erases its stored content', () async {
    final entry = _entry('chat:7:1', now, chat: true);
    final kept = _entry('chat:7:2', now, chat: true);
    await store.recordAll([entry, kept]);
    await store.remove([entry.id]);

    final preferences = await SharedPreferences.getInstance();
    final stored = [
      for (final key in preferences.getKeys())
        if (key.contains('chat%3A7%3A1')) '$key=${preferences.get(key)}',
    ].join('\n');
    expect(stored, contains('chat%3A7%3A1'));
    expect(stored, isNot(contains('테스트 알림 내용')));
    expect(stored, isNot(contains('새 메시지')));
    expect(stored, isNot(contains('"payload":"chat:7"')));
    expect((await store.load()).map((e) => e.id), ['chat:7:2']);

    final later = NotificationInboxStore(
      userHash: 'patient',
      now: () => now.add(const Duration(days: 91)),
    );
    expect(await later.load(), isEmpty);
    await preferences.reload();
    expect(
      preferences.getKeys().where((key) => key.contains('chat%3A7%3A1')),
      isEmpty,
    );
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

  // 함수이름: 보호자 푸시 설명 테스트
  // 함수역할: 완료·미복용 푸시의 실제 설명을 보존하고 다른 수신 계정은 제외한다.
  // 매개변수: 없음. 반환값: 저장된 설명과 계정 범위 검증 완료.
  test(
    'caregiver push history keeps completed and missed slot descriptions',
    () async {
      for (final (type, body) in [
        ('caregiver_slot_completed', '환자가 아침에 복용할 약을 모두 복용했습니다.'),
        ('caregiver_dose_completed', '환자의 약 복용이 확인되었습니다.'),
        ('caregiver_slot_missed', '연동된 환자의 점심 복약이 아직 확인되지 않았습니다.'),
      ]) {
        final message = RemoteMessage(
          messageId: type,
          data: {
            'type': type,
            'recipient_hash': 'caregiver',
            'patient_hash': 'patient',
            'slot_key': 'morning',
          },
          notification: RemoteNotification(title: '복약 확인', body: body),
        );
        await recordPushNotificationHistory(message, userHash: 'caregiver');
        await recordPushNotificationHistory(message, userHash: 'patient');
        final entry = (await NotificationInboxStore(
          userHash: 'caregiver',
        ).load()).singleWhere((entry) => entry.id == 'push:$type');
        expect(entry.title, '복약 확인');
        expect(entry.body, body);
        expect(entry.payload, 'caregiver:patient');
      }
      expect(await NotificationInboxStore(userHash: 'patient').load(), isEmpty);
    },
  );

  // 함수이름: 보호자 푸시 공개 범위 테스트
  // 함수역할: 기기 또는 서버의 숨김 결정을 지키며 본문 없는 푸시의 상세 상태를 추측하지 않는다.
  // 매개변수: 없음. 반환값: 숨김·누락 본문의 안전한 대체 문구 검증 완료.
  test(
    'caregiver push history does not reconstruct hidden or absent details',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'user_setting_caregiver_notification_detail_mode',
        'type_only',
      );
      const data = {
        'type': 'caregiver_slot_completed',
        'recipient_hash': 'caregiver',
        'patient_hash': 'patient',
        'slot_key': 'morning',
      };
      await recordPushNotificationHistory(
        const RemoteMessage(
          messageId: 'hidden-local',
          data: data,
          notification: RemoteNotification(
            title: '환자 복약 완료',
            body: '숨겨야 하는 아침 복약 상태',
          ),
        ),
        userHash: 'caregiver',
      );
      await preferences.setString(
        'user_setting_caregiver_notification_detail_mode',
        'full',
      );
      await recordPushNotificationHistory(
        const RemoteMessage(
          messageId: 'hidden-server',
          data: data,
          notification: RemoteNotification(
            title: '복약 상태 알림',
            body: '연동된 환자의 복약 상태를 확인해 주세요.',
          ),
        ),
        userHash: 'caregiver',
      );
      await recordPushNotificationHistory(
        const RemoteMessage(messageId: 'no-body', data: data),
        userHash: 'caregiver',
      );
      final entries = await NotificationInboxStore(
        userHash: 'caregiver',
      ).load();
      expect(entries, hasLength(3));
      expect(
        entries.every((entry) => entry.body == '연동된 환자의 복약 상태를 확인해 주세요.'),
        isTrue,
      );
      expect(entries.every((entry) => entry.title == '복약 상태 알림'), isTrue);
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

  // Function Name: test: 'batched records and cancellations announce a change only when rows change'
  // Description: Observe change events while batching future reminders, repeating unchanged writes, and cancelling absent or matching schedules.
  // Parameters: None.
  // Returns: No value; each real batch change emits one patient event, no-op operations emit none, and the cancelled reminder is absent when the remaining reminders become due.
  test(
    'batched records and cancellations announce a change only when rows change',
    () async {
      final events = <String>[];
      final subscription = NotificationInboxStore.changes.stream.listen(
        events.add,
      );
      addTearDown(subscription.cancel);
      // Function Name: reminder
      // Description: Construct a morning reminder with a stable ID and a day offset for batch-write and cancellation checks.
      // Parameters: id (int): Schedule identifier; day (int): Offset from the captured test date.
      // Returns: NotificationInboxEntry: Medication reminder with matching ID, payload date, and occurrence time.
      NotificationInboxEntry reminder(int id, int day) =>
          NotificationInboxEntry(
            id: 'reminder:$id:$day',
            title: '복약 시간',
            body: '테스트 알림 내용',
            payload: 'schedule:morning:$id:2026-09-${11 + day}',
            category: NotificationInboxCategory.medication,
            occurredAt: now.add(Duration(days: day)),
          );

      await store.recordAll([reminder(21, 1), reminder(22, 2), reminder(23, 3)]);
      await pumpEventQueue();
      expect(events, ['patient']);

      events.clear();
      await store.recordAll([reminder(21, 1), reminder(22, 2)]);
      await store.record(reminder(23, 3));
      await store.recordAll(const []);
      await store.cancelFutureReminders(id: 99);
      await store.cancelFutureReminders(slotKey: 'evening');
      await pumpEventQueue();
      expect(events, isEmpty);

      await store.cancelFutureReminders(id: 22);
      await pumpEventQueue();
      expect(events, ['patient']);
      now = now.add(const Duration(days: 4));
      expect((await store.load()).map((entry) => entry.id), [
        'reminder:23:3',
        'reminder:21:1',
      ]);
    },
  );

  // Function Name: test: 'control notifies only when the visible inbox changes'
  // Description: Count controller notifications across initial load, identical refreshes, a new row, reading, repeated storage failure, recovery, and removal.
  // Parameters: None.
  // Returns: No value; unchanged visible state stays silent, initial loading emits twice, and each later visible data/error transition emits once.
  test('control notifies only when the visible inbox changes', () async {
    var fails = false;
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
    var notified = 0;
    control.addListener(() => notified++);

    // 첫 조회만 불러오는 중 표시를 켜고 끈다. 빈 목록을 다시 조회할 때는 알리지 않는다.
    await control.refresh();
    expect(notified, 2);
    await control.refresh();
    expect(notified, 2);

    await store.record(
      _entry('first', now.subtract(const Duration(minutes: 1))),
    );
    await pumpEventQueue();
    expect(control.entries.single.id, 'first');

    notified = 0;
    await control.refresh();
    await control.refresh();
    expect(notified, 0);
    expect(control.isLoading, isFalse);

    await store.record(_entry('second', now));
    await pumpEventQueue();
    expect(notified, 1);
    expect(control.entries.map((entry) => entry.id), ['second', 'first']);

    notified = 0;
    await control.markRead(control.entries.first);
    await pumpEventQueue();
    expect(notified, 1);
    expect(control.unreadCount, 1);

    notified = 0;
    fails = true;
    await control.refresh();
    expect(notified, 1);
    expect(control.hasError, isTrue);
    await control.refresh();
    expect(notified, 1);
    fails = false;
    await control.refresh();
    expect(notified, 2);
    expect(control.hasError, isFalse);

    notified = 0;
    await control.remove();
    await pumpEventQueue();
    expect(control.entries, isEmpty);
    expect(notified, 1);
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

  // 함수이름: 알림 시각 형식 테스트
  // 함수역할: 알림 시각이 사용자의 오전/오후·24시간 설정을 따르는지 검증한다. 매개변수: tester. 반환값: 검증 완료.
  for (final format in ['12h', '24h']) {
    // Function Name: testWidgets: 'inbox time follows the $format setting'
    // Description: Render a notification at 13:05 with each supported time-format preference.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; the unread timestamp uses Korean PM 1:05 for 12h or 13:05 for 24h.
    testWidgets('inbox time follows the $format setting', (tester) async {
      await store.record(_entry('dose', DateTime(2026, 9, 10, 13, 5)));
      final control = ManageNotificationInbox(store: store);
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationInboxUI(
            control: control,
            userSetting: UserSetting(timeFormat: format),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(format == '12h' ? '9/10 오후 1:05 · 안 읽음' : '9/10 13:05 · 안 읽음'),
        findsOneWidget,
      );
    });
  }

  // Function Name: testWidgets: 'inbox shows one date heading per day'
  // Description: Load two entries for one day and a third for the previous day, then inspect the date heading semantics.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; each day has one heading and the previous-day heading exposes the accessibility header flag.
  testWidgets('inbox shows one date heading per day', (tester) async {
    await store.record(_entry('late', DateTime(2026, 9, 11, 9)));
    await store.record(_entry('early', DateTime(2026, 9, 11, 7)));
    await store.record(_entry('yesterday', DateTime(2026, 9, 10, 21)));
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxUI(
          control: control,
          userSetting: UserSetting(),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-entry-early')), findsOneWidget);
    expect(find.text('2026년 9월 11일'), findsOneWidget);
    expect(find.text('2026년 9월 10일'), findsOneWidget);
    final heading = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('2026년 9월 10일'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(heading.properties.header, isTrue);
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

  // Function Name: test: 'type-only mode masks both caregiver payload formats'
  // Description: Format sensitive medication entries with both caregiver payload versions under type-only and default detail settings.
  // Parameters: None.
  // Returns: No value; type-only uses generic title/body for both formats, while default formatting preserves the delivered sensitive text.
  test('type-only mode masks both caregiver payload formats', () async {
    final control = ManageNotificationInbox(store: store);
    addTearDown(control.dispose);
    for (final payload in const ['caregiver:patient', 'caregiver-v1:%7B%7D']) {
      final entry = NotificationInboxEntry(
        id: payload,
        title: '점심 복약 미확인',
        body: '숨겨야 하는 환자 복약 내용',
        payload: payload,
        category: NotificationInboxCategory.medication,
        occurredAt: now,
      );
      expect(
        control.titleFor(entry, isEnglish: false, showSensitiveDetails: false),
        '복약 상태 알림',
      );
      expect(
        control.bodyFor(entry, isEnglish: false, showSensitiveDetails: false),
        '연동된 환자의 복약 상태를 확인해 주세요.',
      );
      expect(control.titleFor(entry, isEnglish: false), '점심 복약 미확인');
      expect(control.bodyFor(entry, isEnglish: false), '숨겨야 하는 환자 복약 내용');
    }
  });

  // 함수이름: testWidgets: 'selection uses app typography and a clear selection count'
  // 함수역할: 알림 하나로 선택 모드를 연 뒤 선택 전·전체 선택 후의 문구와 스타일을 검사한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 굵기 700·자간 0·선택 색상이 공통 규칙에 맞고 개수와 삭제 문구가 0에서 1로 바뀌며 선택만으로 읽음 처리하지 않는다.
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
    final count = tester.widget<KeepWordsText>(
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
