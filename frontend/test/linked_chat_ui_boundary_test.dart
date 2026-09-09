// 파일명: linked_chat_ui_boundary_test.dart
// 역할: 채팅 화면의 재전송 중복 방지와 큰 글씨 레이아웃을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';

// 클래스명: _RetryChatControl
// 역할: 첫 전송 실패, 재시도 식별자와 선택 복약 문맥을 기록하는 채팅 대역.
// 주요 책임:
// - 네트워크 조회 대신 주입한 채팅 이력을 제공한다.
// - 아침 약과 저녁 약 두 개를 채팅 선택 대상으로 제공한다.
// - 시간대별 진행 카드에 사용할 지정 일정 문맥을 제공한다.
// 속성:
// - failFirstSend (bool): 재시도 검사를 위해 첫 채팅 전송만 실패시킬지 여부.
// - sendAttempts (int): 같은 메시지 재시도를 포함한 채팅 전송 횟수.
// - detailRequests (int): 채팅에서 시작한 약 상세조회 횟수.
class _RetryChatControl extends ManageLinkedChat {
  final List<String> clientMessageIds = [];
  final List<int?> primaryMedicationIds = [];
  final List<List<int>> medicationIdGroups = [];
  final List<ChatMessageKind> messageKinds = [];
  final List<String?> slotKeys = [];
  final bool failFirstSend;
  final List<ChatScheduleContext> scheduleContexts;
  final List<ChatMessage> historyMessages;
  int sendAttempts = 0;
  int detailRequests = 0;

  // 함수이름: _RetryChatControl
  // 함수역할:
  // - 초기 채팅 이력·일정 문맥·첫 전송 실패 조건을 보관한다.
  // 매개변수:
  // - failFirstSend (bool): 재시도 검사를 위해 첫 채팅 전송만 실패시킬지 여부.
  // - scheduleContexts (List<ChatScheduleContext>): 대화에 표시할 시간대별 복약 진행 카드.
  // - historyMessages (List<ChatMessage>): 초기 또는 반복 조회에 제공할 채팅 기록.
  // 반환값:
  // - 재전송과 빠른 답장을 검사할 채팅 대역.
  _RetryChatControl({
    this.failFirstSend = true,
    this.scheduleContexts = const [],
    this.historyMessages = const [],
  }) : super(
         userHash: 'patient-a',
         // 함수이름: MockClient 콜백
         // 함수역할:
         // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
         // 매개변수:
         // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
         // 반환값:
         // - HTTP 200 응답 Future.
         client: MockClient((request) async => http.Response('{}', 200)),
       );

  // 함수이름: requestHistory
  // 함수역할:
  // - 네트워크 조회 대신 주입한 채팅 이력을 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - beforeMessageId (int?): 이 식별자보다 이전 기록을 가져오는 페이지 경계. 이 대역에서는 직접 사용하지 않는다.
  // - limit (int): 요청할 채팅 기록의 최대 개수. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 생성자에 지정한 메시지 목록.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async => historyMessages;

  // 함수이름: requestMedicationContexts
  // 함수역할:
  // - 아침 약과 저녁 약 두 개를 채팅 선택 대상으로 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 서로 다른 시간대와 복용량을 가진 두 약의 문맥.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => const [
    ChatMedicationContext(
      medicationId: 91,
      medicationName: '테스트정',
      dosagePerTime: '1정',
      scheduleSlotKeys: ['morning'],
    ),
    ChatMedicationContext(
      medicationId: 92,
      medicationName: '저녁정',
      dosagePerTime: '0.5정',
      scheduleSlotKeys: ['evening'],
    ),
  ];

  // 함수이름: requestScheduleContexts
  // 함수역할:
  // - 시간대별 진행 카드에 사용할 지정 일정 문맥을 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 생성자에 지정한 일정 문맥 목록.
  @override
  Future<List<ChatScheduleContext>> requestScheduleContexts({
    required int linkId,
  }) async => scheduleContexts;

  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 상세조회 횟수를 기록하고 식별자에 맞는 아침 또는 저녁 약 정보를 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - medicationId (int): 선택한 저장 약 식별자.
  // 반환값:
  // - 지정 약 식별자와 대응 복용량이 있는 상세정보.
  @override
  Future<MedicationDetail> requestMedicationDetail({
    required int linkId,
    required int medicationId,
  }) async {
    detailRequests += 1;
    return MedicationDetail(
      id: medicationId,
      itemName: medicationId == 92 ? '저녁정' : '테스트정',
      efficacy: '테스트 효능',
      usageMethod: '하루 한 번 복용하세요.',
      warning: '주의사항을 확인하세요.',
      dosagePerTime: medicationId == 92 ? '0.5정' : '1정',
    );
  }

  // 함수이름: sendMessage
  // 함수역할:
  // - 요청 식별자·약 목록·메시지 유형을 기록하고 필요 시 첫 전송만 실패시켜 재시도를 재현한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
  // - clientMessageId (String): 채팅 재전송에도 유지할 요청 식별자.
  // - body (String): 호출자가 전달한 알림 또는 메시지 본문.
  // - medicationId (int?): 선택한 저장 약 식별자.
  // - medicationIds (List<int>): 채팅 메시지에 함께 첨부한 약 식별자 목록.
  // - messageKind (ChatMessageKind): 일반 텍스트 또는 복약 문맥 메시지 유형.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키.
  // - pharmacyId (String?): 채팅 인터페이스의 선택적 약국 문맥 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 성공 시 선택 약 문맥이 포함된 메시지; 첫 실패 조건이면 StateError.
  @override
  Future<ChatMessage> sendMessage({
    required int linkId,
    required String clientMessageId,
    required String body,
    int? medicationId,
    List<int> medicationIds = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
  }) async {
    sendAttempts += 1;
    clientMessageIds.add(clientMessageId);
    primaryMedicationIds.add(medicationId);
    medicationIdGroups.add(List<int>.unmodifiable(medicationIds));
    messageKinds.add(messageKind);
    slotKeys.add(slotKey);
    if (failFirstSend && sendAttempts == 1) {
      throw StateError('temporary failure');
    }
    final contexts = medicationIds
        .map(
          // 함수이름: map 콜백
          // 함수역할:
          // - 선택 약 식별자를 아침 또는 저녁 약명과 복용량을 가진 채팅 문맥으로 바꾼다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자.
          // 반환값:
          // - 해당 식별자의 ChatMedicationContext.
          (id) => ChatMedicationContext(
            medicationId: id,
            medicationName: id == 92 ? '저녁정' : '테스트정',
            dosagePerTime: id == 92 ? '0.5정' : '1정',
          ),
        )
        .toList(growable: false);
    return ChatMessage(
      messageId: 1,
      linkId: linkId,
      senderHash: 'patient-a',
      clientMessageId: clientMessageId,
      body: body,
      createdAt: DateTime.utc(2026, 8, 23, 9),
      messageKind: messageKind,
      medicationContext: contexts.isEmpty ? null : contexts.first,
      medicationContexts: contexts,
    );
  }

  // 함수이름: markRead
  // 함수역할:
  // - 읽음 요청을 외부 서버로 보내지 않고 성공 처리해 화면 테스트를 격리한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - throughMessageId (int): 읽음 처리에 포함할 마지막 수신 메시지 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 읽음 처리 모의 완료.
  @override
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {}
}

// 클래스명: _ChatScheduleControl
// 역할: 채팅 일정 카드가 이동할 저녁 복약 일정을 제공한다.
// 주요 책임:
// - 채팅의 저녁 복약 카드가 이동할 일정 한 건을 제공한다.
class _ChatScheduleControl extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 채팅의 저녁 복약 카드가 이동할 일정 한 건을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 저녁에 반 단위 복용하는 일정.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationID: 'evening-medication',
        medicationName: '저녁정',
        dosage: '0.5',
        intakeTime: '1회',
        medicationTime: 1,
        scheduleSlotKeys: ['evening'],
      ),
    ];
  }
}

// 클래스명: _ChatSetNotification
// 역할: 채팅에서 일정 화면을 열 때 외부 알림 플러그인 없이 설정을 조회한다.
// 주요 책임:
// - 채팅에서 일정으로 이동할 때 플랫폼 알림 동기화를 유발하지 않는 빈 설정을 제공한다.
class _ChatSetNotification extends SetNotification {
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 채팅에서 일정으로 이동할 때 플랫폼 알림 동기화를 유발하지 않는 빈 설정을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 빈 알림 목록.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => const [];
}

// 클래스명: _FakeRealtimeService
// 역할: 실제 WebSocket 없이 채팅 이벤트와 연결 상태 스트림을 제공하는 대역.
// 주요 책임:
// - 채팅 화면에 테스트가 주입할 메시지 이벤트를 노출한다.
// - 연결·해제 상태를 채팅 화면에 전달할 스트림을 노출한다.
// - 실제 연결 없이 연결됨 상태를 스트림에 전달한다.
class _FakeRealtimeService extends LinkedChatRealtimeService {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LinkedChatConnectionState> _states =
      StreamController<LinkedChatConnectionState>.broadcast();

  // 함수이름: _FakeRealtimeService
  // 함수역할:
  // - 고정 연결 범위와 자격 증명이 없는 로컬 인증 클라이언트를 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 수동 이벤트 주입용 실시간 서비스 대역.
  _FakeRealtimeService()
    : super(
        linkId: 17,
        userHash: 'patient-a',
        authenticationClient: AuthenticatedApiClient(
          // 함수이름: MockClient 콜백
          // 함수역할:
          // - 네트워크 없이 HTTP 200 상태와 빈 JSON 객체를 제공한다.
          // 매개변수:
          // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - HTTP 200 응답 Future.
          inner: MockClient((request) async => http.Response('{}', 200)),
          // 함수이름: tokenProvider 콜백
          // 함수역할:
          // - Firebase 통신 없이 Firebase 인증 토큰 없음을 제공한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - null을 담은 Future<String?>.
          tokenProvider: () async => null,
          // 함수이름: appCheckTokenProvider 콜백
          // 함수역할:
          // - Firebase 통신 없이 App Check 토큰 없음을 제공한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - null을 담은 Future<String?>.
          appCheckTokenProvider: () async => null,
          trustedBaseUri: Uri.parse('http://localhost/api/v1/medication'),
        ),
      );

  // 함수이름: events
  // 함수역할:
  // - 채팅 화면에 테스트가 주입할 메시지 이벤트를 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 내부 이벤트 스트림.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  // 함수이름: states
  // 함수역할:
  // - 연결·해제 상태를 채팅 화면에 전달할 스트림을 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 내부 연결 상태 스트림.
  @override
  Stream<LinkedChatConnectionState> get states => _states.stream;

  // 함수이름: start
  // 함수역할:
  // - 실제 연결 없이 연결됨 상태를 스트림에 전달한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 연결 상태 이벤트 전송 완료.
  @override
  Future<void> start() async {
    _states.add(LinkedChatConnectionState.connected);
  }

  // 함수이름: stop
  // 함수역할:
  // - 연결 해제 상태를 스트림에 전달한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 해제 상태 이벤트 전송 완료.
  @override
  Future<void> stop() async {
    _states.add(LinkedChatConnectionState.disconnected);
  }

  // 함수이름: dispose
  // 함수역할:
  // - 메시지·연결 상태 스트림과 인증 HTTP 클라이언트를 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 모든 테스트용 통신 자원 정리 완료.
  @override
  Future<void> dispose() async {
    await _events.close();
    await _states.close();
    authenticationClient.close();
  }
}

// 클래스명: _DeleteChatControl
// 역할: 채팅 삭제 식별자와 범위를 기록하고 선택적으로 서버 실패를 재현하는 대역.
// 주요 책임:
// - 선택한 메시지 식별자와 삭제 범위를 기록하고 지정된 경우 오프라인 오류를 발생시킨다.
// 속성:
// - failDeletion (bool): 메시지 삭제 실패를 주입할지 여부.
class _DeleteChatControl extends _RetryChatControl {
  final bool failDeletion;
  final List<List<int>> deletionIds = [];
  final List<ChatDeletionScope> deletionScopes = [];

  // 함수이름: _DeleteChatControl
  // 함수역할:
  // - 초기 채팅 이력과 삭제 실패 조건을 보관하고 전송 실패는 비활성화한다.
  // 매개변수:
  // - historyMessages (List<ChatMessage>): 초기 또는 반복 조회에 제공할 채팅 기록.
  // - failDeletion (bool): 메시지 삭제 실패를 주입할지 여부.
  // 반환값:
  // - 삭제 흐름 전용 채팅 대역.
  _DeleteChatControl({
    required super.historyMessages,
    this.failDeletion = false,
  }) : super(failFirstSend: false);

  // 함수이름: deleteMessages
  // 함수역할:
  // - 선택한 메시지 식별자와 삭제 범위를 기록하고 지정된 경우 오프라인 오류를 발생시킨다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - messageIds (List<int>): 명시적으로 선택한 삭제 대상 메시지 식별자.
  // - scope (ChatDeletionScope): 나에게서 또는 모두에게서 삭제할 범위.
  // 반환값:
  // - 성공 시 완료; 실패 주입 시 StateError.
  @override
  Future<void> deleteMessages({
    required int linkId,
    required List<int> messageIds,
    required ChatDeletionScope scope,
  }) async {
    deletionIds.add(messageIds);
    deletionScopes.add(scope);
    if (failDeletion) throw StateError('offline');
  }
}

// 함수이름: _deletionMessage
// 함수역할:
// - 발신자와 경과 시간을 지정한 메시지로 삭제 가능 조건을 재현한다.
// 매개변수:
// - id (int): 약·메시지·알림 대역의 식별자.
// - sender (String): 가상 메시지 작성자 식별자.
// - hours (int): 가상 채팅 메시지 생성 후 경과 시간.
// 반환값:
// - 지정 시간만큼 과거에 생성된 채팅 메시지.
ChatMessage _deletionMessage({
  int id = 1,
  String sender = 'patient-a',
  int hours = 1,
}) => ChatMessage(
  messageId: id,
  linkId: 17,
  senderHash: sender,
  clientMessageId: 'delete_message_$id',
  body: 'Message $id',
  createdAt: DateTime.now().toUtc().subtract(Duration(hours: hours)),
);

// 함수이름: main
// 함수역할:
// - 복약 대화 삭제, 재시도 식별자, 빠른 답장과 복약 카드 이동 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 선택한 메시지를 나에게서 삭제한 뒤 오래된 조회가 돌아와도 삭제 상태와 선택하지 않은 기존 메시지를 유지하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets(
    'selected private deletion survives stale polling and preserves new messages',
    (tester) async {
      final control = _DeleteChatControl(
        historyMessages: [_deletionMessage(), _deletionMessage(id: 2)],
      );
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            userSetting: const UserSetting(language: 'en'),
            control: control,
            realtimeService: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selectChatMessage-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
      await tester.pumpAndSettle();
      expect(find.text('Delete for everyone'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(control.deletionIds, isEmpty);
      await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmChatDeletion')));
      await tester.pumpAndSettle();
      expect(control.deletionScopes, [ChatDeletionScope.me]);
      expect(control.deletionIds.single, [1]);
      expect(find.text('Message 1'), findsNothing);
      expect(find.text('Message 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text('Message 1'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 모두에게서 삭제한 본문이 지연 이벤트로 복구되지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets(
    'shared deletion removes body and prevents delayed events restoring it',
    (tester) async {
      final control = _DeleteChatControl(historyMessages: [_deletionMessage()]);
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            userSetting: const UserSetting(language: 'en'),
            control: control,
            realtimeService: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Message 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for everyone'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirmChatDeletion')));
      await tester.pumpAndSettle();
      expect(control.deletionScopes, [ChatDeletionScope.everyone]);
      expect(find.text('This message was deleted.'), findsOneWidget);
      expect(find.text('Message 1'), findsNothing);
      realtime._events.add({
        'type': 'chat_message',
        'message': {
          'message_id': 1,
          'link_id': 17,
          'sender_hash': 'patient-a',
          'client_message_id': 'delete_message_1',
          'body': 'Message 1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('Message 1'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  for (final sender in ['patient-a', 'caregiver-a']) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 발신자별 오래된 메시지나 수신 메시지 선택에는 나에게서 삭제만 제공하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets(
      'old or incoming selection offers private deletion only: $sender',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final control = _DeleteChatControl(
          historyMessages: [
            _deletionMessage(
              sender: sender,
              hours: sender == 'patient-a' ? 25 : 1,
            ),
          ],
          failDeletion: true,
        );
        final realtime = _FakeRealtimeService();
        await tester.pumpWidget(
          MaterialApp(
            // 함수이름: builder 콜백
            // 함수역할:
            // - 기존 하위 화면에 2배 글씨를 적용해 접근성 배치를 검사한다.
            // 매개변수:
            // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
            // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
            // 반환값:
            // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              control: control,
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Message 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
        await tester.pumpAndSettle();
        expect(find.text('모두에게서 삭제'), findsNothing);
        expect(find.text('나에게서만 삭제'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('confirmChatDeletion')));
        await tester.pumpAndSettle();
        expect(find.text('Message 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      },
    );
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 안내는 자동으로 사라지고 약 선택 없이 일반 메시지를 보낸다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('안내는 자동으로 사라지고 약 선택 없이 일반 메시지를 보낸다', (tester) async {
    final control = _RetryChatControl(failFirstSend: false);
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          patientHash: 'patient-a',
          control: control,
          realtimeService: realtimeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    const guide = '대화할 약을 선택하면 사진과 복용량이 메시지에 함께 표시됩니다.';
    expect(find.text(guide), findsOneWidget);
    final initialField = tester.widget<TextField>(find.byType(TextField));
    expect(initialField.enabled, isTrue);
    expect(initialField.decoration?.hintText, isNull);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text(guide), findsNothing);

    await tester.enterText(find.byType(TextField), '오늘은 몸 상태가 괜찮아요.');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chatSendButton')));
    await tester.pumpAndSettle();

    expect(control.sendAttempts, 1);
    expect(control.primaryMedicationIds, [null]);
    expect(control.medicationIdGroups, [isEmpty]);
    expect(find.text('오늘은 몸 상태가 괜찮아요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 큰 글씨에서도 메시지 실패 재시도는 같은 요청 식별자를 사용한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('큰 글씨에서도 메시지 실패 재시도는 같은 요청 식별자를 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    // 함수이름: addTearDown 콜백
    // 함수역할:
    // - 작은 화면 사례가 끝난 뒤 테스트 화면 크기를 기본값으로 복원한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 화면 크기 복원 완료.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final control = _RetryChatControl();
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            peerName: '보호자 이름이 매우 긴 경우',
            control: control,
            realtimeService: realtimeService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('chatMedicationSelector')));
    await tester.pumpAndSettle();
    expect(find.text('대화할 약 선택'), findsOneWidget);
    expect(find.text('아침'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionOption_91')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionConfirm')),
    );
    await tester.pumpAndSettle();
    final messageField = tester.widget<TextField>(find.byType(TextField));
    expect(messageField.controller?.text, isEmpty);
    expect(messageField.decoration?.hintText, '예: 테스트정 복용을 완료했어요.');
    await tester.enterText(find.byType(TextField), '저녁 약을 복용했어요.');
    await tester.pump();
    final sendButtonFinder = find.byKey(const ValueKey('chatSendButton'));
    final firstSendButton = tester.widget<IconButton>(sendButtonFinder);
    expect(firstSendButton.onPressed, isNotNull);
    firstSendButton.onPressed!();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('메시지를 보내지 못했습니다. 다시 눌러주세요.'), findsOneWidget);
    final retryButton = tester.widget<IconButton>(sendButtonFinder);
    expect(retryButton.onPressed, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '저녁 약을 복용했어요.',
    );
    retryButton.onPressed!();
    await tester.pumpAndSettle();

    expect(control.sendAttempts, 2);
    expect(control.clientMessageIds, hasLength(2));
    expect(control.clientMessageIds[0], control.clientMessageIds[1]);
    expect(find.text('저녁 약을 복용했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('테스트정'));
    await tester.pumpAndSettle();
    expect(control.detailRequests, 1);
    expect(find.text('약 상세정보'), findsOneWidget);
    expect(find.text('테스트 효능'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 보호자는 시간대 카드를 골라 환자에게 복약 확인을 요청한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보호자는 시간대 카드를 골라 환자에게 복약 확인을 요청한다', (tester) async {
    final control = _RetryChatControl(
      failFirstSend: false,
      scheduleContexts: const [
        ChatScheduleContext(
          slotKey: 'morning',
          alarmTime: '08:00',
          alarmEnabled: true,
          completedCount: 1,
          totalCount: 2,
          canRequestCheck: true,
          medications: [
            ChatMedicationContext(
              medicationId: 91,
              medicationName: '테스트정',
              dosagePerTime: '1정',
            ),
          ],
        ),
      ],
    );
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'caregiver-a',
          patientHash: 'patient-a',
          control: control,
          realtimeService: realtimeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chatScheduleSelector')));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 복약 시간대'), findsOneWidget);
    expect(find.text('아침 08:00'), findsOneWidget);

    await tester.tap(find.text('아침 08:00'));
    await tester.pumpAndSettle();

    expect(control.messageKinds, [ChatMessageKind.slotCheckRequest]);
    expect(control.slotKeys, ['morning']);
    expect(find.text('아침 복약을 확인해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자는 여러 약을 선택해 환자용 빠른 답장을 보낸다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자는 여러 약을 선택해 환자용 빠른 답장을 보낸다', (tester) async {
    final control = _RetryChatControl(failFirstSend: false);
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          patientHash: 'patient-a',
          control: control,
          realtimeService: realtimeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chatMedicationSelector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionOption_91')),
    );
    await tester.pumpAndSettle();
    final secondMedication = find.byKey(
      const ValueKey('scheduleMedicationSelectionOption_92'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(secondMedication);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionConfirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('먹었어요'), findsOneWidget);
    expect(find.text('지금은 못 먹어요'), findsOneWidget);
    expect(find.text('약이 부족해요'), findsOneWidget);
    expect(find.text('먹고 나서 불편해요'), findsOneWidget);

    final takenReply = find.widgetWithText(ActionChip, '먹었어요');
    await tester.ensureVisible(takenReply);
    await tester.tap(takenReply);
    await tester.pumpAndSettle();

    expect(control.primaryMedicationIds, [91]);
    expect(control.medicationIdGroups, [
      [91, 92],
    ]);
    expect(control.messageKinds, [ChatMessageKind.text]);
    expect(control.slotKeys, [null]);
    expect(find.text('테스트정, 저녁정 먹었어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 보호자는 환자 문구 대신 보호자용 빠른 답장을 사용한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보호자는 환자 문구 대신 보호자용 빠른 답장을 사용한다', (tester) async {
    final control = _RetryChatControl(failFirstSend: false);
    final realtimeService = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'caregiver-a',
          patientHash: 'patient-a',
          peerName: '환자 TEST',
          control: control,
          realtimeService: realtimeService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chatMedicationSelector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionOption_91')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('scheduleMedicationSelectionConfirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('복용하셨나요?'), findsOneWidget);
    expect(find.text('지금 복용 가능하세요?'), findsOneWidget);
    expect(find.text('남은 약이 충분한가요?'), findsOneWidget);
    expect(find.text('불편한 점은 없으세요?'), findsOneWidget);
    expect(find.text('먹었어요'), findsNothing);
    expect(find.text('지금은 못 먹어요'), findsNothing);

    final caregiverReply = find.widgetWithText(ActionChip, '복용하셨나요?');
    await tester.ensureVisible(caregiverReply);
    await tester.tap(caregiverReply);
    await tester.pumpAndSettle();

    expect(control.primaryMedicationIds, [91]);
    expect(control.medicationIdGroups, [
      [91],
    ]);
    expect(find.text('환자 TEST님, 테스트정 복용하셨나요?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자가 채팅의 시간대 카드를 누르면 해당 복약 일정으로 이동한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자가 채팅의 시간대 카드를 누르면 해당 복약 일정으로 이동한다', (tester) async {
    final scheduleContext = const ChatScheduleContext(
      slotKey: 'evening',
      alarmTime: '18:00',
      alarmEnabled: true,
      completedCount: 0,
      totalCount: 1,
      canRequestCheck: false,
      medications: [
        ChatMedicationContext(
          medicationId: 92,
          medicationName: '저녁정',
          dosagePerTime: '0.5정',
        ),
      ],
    );
    final control = _RetryChatControl(
      failFirstSend: false,
      historyMessages: [
        ChatMessage(
          messageId: 70,
          linkId: 17,
          senderHash: 'caregiver-a',
          clientMessageId: 'schedule_message_001',
          body: '저녁 복약을 확인해주세요.',
          createdAt: DateTime.utc(2026, 8, 24, 9),
          messageKind: ChatMessageKind.slotCheckRequest,
          scheduleContext: scheduleContext,
        ),
      ],
    );
    final realtimeService = _FakeRealtimeService();
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ChatScheduleControl(),
      setNotification: _ChatSetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            control: control,
            realtimeService: realtimeService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('저녁 18:00'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckScheduleUI), findsOneWidget);
    final scheduleScreen = tester.widget<CheckScheduleUI>(
      find.byType(CheckScheduleUI),
    );
    expect(scheduleScreen.initialSlotKey, 'evening');
    expect(find.text('오늘의 복약 일정'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });
}
