// 파일명: notification_inbox_peer_name_test.dart
// 역할: 알림 제목이 같은 계정의 현재 대화 상대 이름과 일치하는지 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/notification_inbox_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/controls/manage_notification_inbox_control.dart';
import 'package:medbuddy_frontend/entities/notification_inbox_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';

// 함수이름: _unusedRequest
// 함수역할: 테스트의 실제 통신을 막는다. 매개변수: request. 반환값: 빈 응답.
Future<http.Response> _unusedRequest(http.Request request) async =>
    http.Response('{}', 200);

// 클래스명: _Links
// 역할: 서버의 활성 연동과 별칭 변경을 재현한다.
class _Links extends LinkPatientCaregiver {
  List<PatientCaregiverLink> result = [];
  // 함수이름: _Links
  // 함수역할: 외부 통신 없는 연동 제어기를 만든다. 매개변수: 없음. 반환값: 테스트 제어기.
  _Links() : super(client: MockClient(_unusedRequest));
  // 함수이름: requestLinkScreen
  // 함수역할: 준비한 연동 목록을 반환한다. 매개변수: 없음. 반환값: 연동 목록.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async => result;
}

// 함수이름: _link
// 함수역할: 별칭을 가진 환자·보호자 관계를 만든다. 매개변수: id, alias. 반환값: 연동.
PatientCaregiverLink _link(int id, String alias) => PatientCaregiverLink(
  linkId: id,
  patientHash: 'patient-$id',
  caregiverHash: 'caregiver',
  patientAlias: alias,
  linkStatus: true,
);

// 함수이름: _entry
// 함수역할: 기존 일반 제목으로 저장된 알림을 만든다. 매개변수: payload, chat. 반환값: 알림.
NotificationInboxEntry _entry(String payload, {bool chat = true}) =>
    NotificationInboxEntry(
      id: payload,
      title: chat ? '새 가족 메시지' : '복약 시간',
      body: '알림 내용',
      payload: payload,
      category: chat
          ? NotificationInboxCategory.chat
          : NotificationInboxCategory.medication,
      occurredAt: DateTime(2026, 9, 12),
    );

// 함수이름: main
// 함수역할: 이름 조회·갱신·계정 분리와 실제 제목 표시를 검증한다. 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Links links;
  late ManageChatList chats;
  late ManageNotificationInbox inbox;
  // 함수이름: setUp 콜백
  // 함수역할: 테스트마다 기기 저장소를 초기화한다. 매개변수: 없음. 반환값: 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: createControls
  // 함수역할: 현재 테스트의 비동기 영역에서 구독을 생성한다. 매개변수: 없음. 반환값: 없음.
  void createControls() {
    links = _Links()..result = [_link(1, '엄마'), _link(2, '아빠')];
    chats = ManageChatList(userHash: 'caregiver', linkControl: links);
    inbox = ManageNotificationInbox(
      store: NotificationInboxStore(
        userHash: 'caregiver',
        now: () => DateTime(2026, 9, 12, 12),
      ),
      chatList: chats,
    );
  }

  // 함수이름: tearDown 콜백
  // 함수역할: 알림함의 빌린 구독과 각 제어기를 정리한다. 매개변수: 없음. 반환값: 없음.
  tearDown(() {
    inbox.dispose();
    chats.dispose();
    links.dispose();
  });

  // 함수이름: 이름과 범위 테스트
  // 함수역할: 각 연동의 별칭을 구분하며 숨김·비채팅·알 수 없는 경로는 일반 제목을 유지한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test(
    'uses the correct peer alias without changing privacy or medication titles',
    () async {
      createControls();
      await chats.refresh();
      expect(inbox.titleFor(_entry('chat:1'), isEnglish: false), '엄마');
      expect(inbox.titleFor(_entry('chat:2'), isEnglish: false), '아빠');
      expect(
        inbox.titleFor(
          _entry('chat:1'),
          isEnglish: false,
          showSensitiveDetails: false,
        ),
        '새 가족 메시지',
      );
      expect(
        inbox.titleFor(_entry('chat:1', chat: false), isEnglish: false),
        '복약 시간',
      );
      for (final payload in ['chat:99', 'chat:1:extra', 'chat:bad']) {
        expect(inbox.titleFor(_entry(payload), isEnglish: false), '새 가족 메시지');
      }
    },
  );

  // 함수이름: 환자 관점 테스트
  // 함수역할: 환자에게 자신의 별칭 대신 채팅 목록의 보호자 이름을 표시한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'patient sees the caregiver name and another account is rejected',
    () async {
      createControls();
      final patientChats = ManageChatList(
        userHash: 'patient-1',
        linkControl: links,
      );
      final patientInbox = ManageNotificationInbox(
        store: NotificationInboxStore(userHash: 'patient-1'),
        chatList: patientChats,
      );
      try {
        await patientChats.refresh();
        expect(
          patientInbox.titleFor(_entry('chat:1'), isEnglish: false),
          '보호자 caregiver',
        );
        expect(
          patientInbox.titleFor(_entry('chat:1'), isEnglish: true),
          'Caregiver caregiver',
        );
        expect(
          () => ManageNotificationInbox(
            store: NotificationInboxStore(userHash: 'other'),
            chatList: chats,
          ),
          throwsArgumentError,
        );
      } finally {
        patientInbox.dispose();
        patientChats.dispose();
      }
    },
  );

  // 함수이름: 기존 알림의 이름 갱신 테스트
  // 함수역할: 별칭을 바꾸거나 연동을 해제하면 이미 열린 알림 제목도 갱신하며 저장된 읽음 상태는 유지한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('existing notifications follow alias changes and unlinking', (
    tester,
  ) async {
    createControls();
    final entry = _entry('chat:1');
    await inbox.store.record(entry);
    await inbox.store.markRead([entry.id]);
    await chats.refresh();
    await inbox.refresh();
    expect(inbox.entries, hasLength(1));
    expect(chats.links, hasLength(2));
    expect(inbox.titleFor(inbox.entries.single, isEnglish: false), '엄마');
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxUI(
          control: inbox,
          userSetting: const UserSetting(),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('엄마'), findsOneWidget);
    expect(find.text('새 가족 메시지'), findsNothing);
    links.result = [_link(1, '가족 별칭 변경')];
    await tester.runAsync(() => chats.refresh());
    await tester.pumpAndSettle();
    expect(find.text('가족 별칭 변경'), findsOneWidget);
    links.result = [];
    await tester.runAsync(() => chats.refresh());
    await tester.pumpAndSettle();
    expect(find.text('새 가족 메시지'), findsOneWidget);
    expect(inbox.entries.single.isRead, isTrue);
    expect((await inbox.store.load()).single.title, '새 가족 메시지');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
