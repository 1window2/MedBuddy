// 파일명: linked_chat_ui_boundary_test.dart
// 역할: 채팅의 재전송·첨부·공유 화면 이동, 연동 종료·지연 응답과 큰 글씨 레이아웃을 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_search_ui_boundary.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/chat_date_divider.dart';
import 'package:medbuddy_frontend/boundaries/medication_history_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/linked_chat_realtime_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
import 'medication_history_fixtures.dart';

// 클래스명: _RetryChatControl
// 역할: 채팅 조회·전송·읽음 처리의 응답과 실패 시점을 제어하는 대역.
// 주요 책임:
// - 요청 인자를 기록하고 페이지·지연 응답을 주입하여 재시도, 첨부, 공유 및 경합을 검증한다.
// 속성:
// - clientMessageIds (List<String>): 시도별 클라이언트 메시지 ID.
// - primaryMedicationIds (List<int?>): 시도별 대표 약 ID.
// - medicationIdGroups (List<List<int>>): 시도별 저장 약 ID의 불변 복사본.
// - referenceGroups (List<List<ChatMedicationReference>>): 시도별 약 참조의 불변 복사본.
// - messageKinds (List<ChatMessageKind>): 시도별 메시지 유형.
// - slotKeys (List<String?>): 시도별 복약 시간대.
// - hospitalIds (List<String?>): 시도별 병원 ID.
// - pharmacyIds (List<String?>): 시도별 약국 ID.
// - hospitalDates (List<String?>): 시도별 병원 일정 날짜.
// - failFirstSend (bool): 첫 전송만 실패시킬지 여부.
// - failSends (bool): 모든 전송을 실패시킬지 여부.
// - scheduleContexts (List<ChatScheduleContext>): 조회에 반환할 일정 문맥.
// - historyMessages (List<ChatMessage>): 기본 이력과 미확인 요약의 원본.
// - sendAttempts (int): 실패를 포함한 전송 횟수.
// - detailRequests (int): 약 상세 조회 횟수.
// - historyRequests (int): 실패를 포함한 이력 조회 횟수.
// - failHistory (bool): 이력 조회를 StateError로 실패시킬지 여부.
// - historyGate (Completer<List<ChatMessage>>?): 페이지 대역이 없을 때 이력 응답을 보류하는 완료자.
// - detailGate (Completer<MedicationDetail>?): 약 상세 응답을 보류하는 완료자.
// - historyPages (Map<int?, List<ChatMessage>>?): 이전 메시지 커서별 응답.
// - historyBoundaries (List<int?>): 실패하지 않은 이력 요청의 커서 기록.
// - markedReadIds (List<int>): 읽음 요청의 마지막 메시지 ID 기록.
// - unreadSummary (ChatUnreadSummary?): 이력 집계 대신 반환할 입장 시 미확인 요약.
class _RetryChatControl extends ManageLinkedChat {
  final List<String> clientMessageIds = [];
  final List<int?> primaryMedicationIds = [];
  final List<List<int>> medicationIdGroups = [];
  final List<List<ChatMedicationReference>> referenceGroups = [];
  final List<ChatMessageKind> messageKinds = [];
  final List<String?> slotKeys = [];
  final List<String?> hospitalIds = [];
  final List<String?> pharmacyIds = [];
  final List<String?> hospitalDates = [];
  final bool failFirstSend;
  bool failSends = false;
  final List<ChatScheduleContext> scheduleContexts;
  final List<ChatMessage> historyMessages;
  int sendAttempts = 0;
  int detailRequests = 0;
  int historyRequests = 0;
  bool failHistory = false;
  Completer<List<ChatMessage>>? historyGate;
  Completer<MedicationDetail>? detailGate;
  Map<int?, List<ChatMessage>>? historyPages;
  final historyBoundaries = <int?>[];
  final markedReadIds = <int>[];
  ChatUnreadSummary? unreadSummary;

  // 함수이름: requestUnreadSummary
  // 함수역할:
  // - 지정된 요약을 우선 반환하며, 없으면 이력에서 patient-a 이외 발신자의 미확인·미삭제 메시지를 집계한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 이 대역의 집계에는 사용하지 않는다.
  // 반환값:
  // - Future<ChatUnreadSummary>; 미확인 수와 이력 순서상 첫 ID 또는 null.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async {
    if (unreadSummary != null) return unreadSummary!;
    final incoming = historyMessages
        .where(
          (m) =>
              m.senderHash != 'patient-a' &&
              m.readAt == null &&
              !m.deletedForEveryone,
        )
        .toList();
    return ChatUnreadSummary(
      count: incoming.length,
      firstMessageId: incoming.isEmpty ? null : incoming.first.messageId,
    );
  }

  // 함수이름: _RetryChatControl
  // 함수역할:
  // - patient-a 계정의 빈 HTTP 응답 클라이언트를 구성하고 기본 이력·일정·첫 전송 실패 조건을 보관한다.
  // 매개변수:
  // - failFirstSend (bool): 첫 전송 실패 여부이며 기본값은 true이다.
  // - scheduleContexts (List<ChatScheduleContext>): 조회에 반환할 일정 문맥이며 기본값은 빈 목록이다.
  // - historyMessages (List<ChatMessage>): 기본 이력과 미확인 집계 원본이며 기본값은 빈 목록이다.
  // 반환값:
  // - _RetryChatControl; 요청과 실패 시점을 제어할 대역.
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
  // - 조회 횟수를 늘리고 failHistory이면 StateError로 실패한다. 성공 요청의 커서를 기록하며 페이지 맵, 지연 응답, 기본 이력 순으로 결과를 선택한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 응답 선택에는 사용하지 않는다.
  // - beforeMessageId (int?): 페이지 맵 조회 키이며 null은 최신 페이지를 뜻한다.
  // - limit (int): 기본값 50인 요청 한도이며 이 대역은 결과를 자르지 않는다.
  // 반환값:
  // - Future<List<ChatMessage>>; 선택한 페이지나 이력이며 없는 페이지는 빈 목록이다.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async {
    historyRequests++;
    if (failHistory) throw StateError('history unavailable');
    historyBoundaries.add(beforeMessageId);
    if (historyPages != null) return historyPages![beforeMessageId] ?? [];
    return historyGate != null ? historyGate!.future : historyMessages;
  }

  // 함수이름: requestMedicationContexts
  // 함수역할:
  // - 복용량과 시간대가 다른 아침 약 91번과 저녁 약 92번을 고정 선택 대상으로 제공한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 고정 응답에는 사용하지 않는다.
  // 반환값:
  // - Future<List<ChatMedicationContext>>; 아침 1정과 저녁 0.5정의 약 문맥.
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
  // - 화면의 복약 진행 카드에 사용할 지정 일정 문맥을 그대로 제공한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 응답에는 사용하지 않는다.
  // 반환값:
  // - Future<List<ChatScheduleContext>>; 생성자에 전달한 scheduleContexts.
  @override
  Future<List<ChatScheduleContext>> requestScheduleContexts({
    required int linkId,
  }) async => scheduleContexts;

  // 함수이름: requestMedicationDetail
  // 함수역할:
  // - 상세 조회 횟수를 늘리고 detailGate가 있으면 그 결과를 기다린다. 없으면 92번은 저녁 약, 그 외에는 아침 약 설명을 반환한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 상세 생성에는 사용하지 않는다.
  // - medicationId (int): 반환할 약 ID와 이름·복용량을 선택할 식별자.
  // 반환값:
  // - Future<MedicationDetail>; 지정 ID의 상세 또는 완료자가 전달한 결과·오류.
  @override
  Future<MedicationDetail> requestMedicationDetail({
    required int linkId,
    required int medicationId,
  }) async {
    detailRequests += 1;
    if (detailGate != null) return detailGate!.future;
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
  // - 전송 인자를 기록한 뒤 설정에 따라 StateError로 실패한다. 성공 시 선택 약 문맥과 참조를 담은 고정 ID의 환자 메시지를 반환한다.
  // 매개변수:
  // - sourceAlertId (int?): 원본 알림 ID이며 이 대역에서는 사용하지 않는다.
  // - linkId (int): 응답 메시지의 연동 ID.
  // - clientMessageId (String): 재시도 동일성을 검사할 요청 ID.
  // - body (String): 응답 메시지에 그대로 담을 본문.
  // - medicationId (int?): 기록할 대표 저장 약 ID.
  // - medicationIds (List<int>): 기록하고 약 문맥으로 변환할 ID 목록이며 기본값은 빈 목록이다.
  // - medicationReferences (List<ChatMedicationReference>): 기록하고 응답에 포함할 약 참조이며 기본값은 빈 목록이다.
  // - messageKind (ChatMessageKind): 기록 및 응답에 사용할 유형이며 기본값은 text이다.
  // - slotKey (String?): 기록할 복약 시간대.
  // - pharmacyId (String?): 기록할 약국 ID.
  // - hospitalId (String?): 기록할 병원 ID.
  // - hospitalScheduleDate (String?): 기록할 병원 일정 날짜.
  // - historyStartDate (String?): 이력 공유 시작일이며 이 대역에서는 사용하지 않는다.
  // - historyEndDate (String?): 이력 공유 종료일이며 이 대역에서는 사용하지 않는다.
  // 반환값:
  // - Future<ChatMessage>; 약 문맥·참조를 포함한 메시지 또는 설정된 전송 오류.
  @override
  Future<ChatMessage> sendMessage({
    int? sourceAlertId,
    required int linkId,
    required String clientMessageId,
    required String body,
    int? medicationId,
    List<int> medicationIds = const [],
    List<ChatMedicationReference> medicationReferences = const [],
    ChatMessageKind messageKind = ChatMessageKind.text,
    String? slotKey,
    String? pharmacyId,
    String? hospitalId,
    String? hospitalScheduleDate,
    String? historyStartDate,
    String? historyEndDate,
  }) async {
    sendAttempts += 1;
    clientMessageIds.add(clientMessageId);
    primaryMedicationIds.add(medicationId);
    medicationIdGroups.add(List<int>.unmodifiable(medicationIds));
    referenceGroups.add(List.unmodifiable(medicationReferences));
    messageKinds.add(messageKind);
    slotKeys.add(slotKey);
    hospitalIds.add(hospitalId);
    pharmacyIds.add(pharmacyId);
    hospitalDates.add(hospitalScheduleDate);
    if (failSends || (failFirstSend && sendAttempts == 1)) {
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
      medicationReferences: medicationReferences,
    );
  }

  // 함수이름: markRead
  // 함수역할:
  // - 서버 호출 없이 마지막 읽음 메시지 ID를 기록하여 중복 읽음 처리 여부를 검사할 수 있게 한다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 이 대역에서는 사용하지 않는다.
  // - throughMessageId (int): 읽음 처리 범위의 마지막 ID로 기록할 값.
  // 반환값:
  // - Future<void>; ID 기록 후 완료한다.
  @override
  Future<void> markRead({
    required int linkId,
    required int throughMessageId,
  }) async {
    markedReadIds.add(throughMessageId);
  }
}

// 클래스명: _TakenChatControl
// 역할: 전송 대기열이 없을 때 사용하는 채팅 복용 확인 API의 대역.
// 주요 책임:
// - 복용 확인 대상과 요청 ID를 수집하고 저장 완료를 지연할 수 있다.
// 속성:
// - takenRequestIds (List<String>): 복용 확인 요청 ID 기록.
// - takenMedicationIds (List<List<int>>): 요청별 선택 약 목록.
// - takenSlotKeys (List<String>): 요청별 복약 시간대.
// - multiSlotMedication (bool): 91번 약을 아침·저녁 복용으로 노출할지 여부.
// - saveGate (Completer<void>?): 복용 확인 응답을 보류할 완료자.
class _TakenChatControl extends _RetryChatControl {
  final List<String> takenRequestIds = [];
  final List<List<int>> takenMedicationIds = [];
  final List<String> takenSlotKeys = [];
  final bool multiSlotMedication;
  final Completer<void>? saveGate;

  // 함수이름: _TakenChatControl
  // 함수역할:
  // - 일반 전송 실패를 끄고 지정 일정 또는 아침 약 두 건의 기본 일정으로 복용 확인 대역을 생성한다.
  // 매개변수:
  // - multiSlotMedication (bool): 91번 약의 아침·저녁 시간대 노출 여부이며 기본값은 false이다.
  // - saveGate (Completer<void>?): 복용 확인 응답을 보류할 선택적 완료자.
  // - contexts (List<ChatScheduleContext>?): 사용할 일정 문맥이며 null이면 2026-09-21 아침 기본 일정을 쓴다.
  // 반환값:
  // - _TakenChatControl; 복용 확인 요청을 기록할 대역.
  _TakenChatControl({
    this.multiSlotMedication = false,
    this.saveGate,
    List<ChatScheduleContext>? contexts,
  }) : super(
         failFirstSend: false,
         scheduleContexts:
             contexts ??
             const [
               ChatScheduleContext(
                 scheduleDate: '2026-09-21',
                 slotKey: 'morning',
                 alarmTime: '08:00',
                 alarmEnabled: true,
                 completedCount: 0,
                 totalCount: 2,
                 medications: [
                   ChatMedicationContext(
                     medicationId: 91,
                     medicationName: '테스트정',
                     dosagePerTime: '1정',
                   ),
                   ChatMedicationContext(
                     medicationId: 93,
                     medicationName: '선택하지 않은 약',
                     dosagePerTime: '1정',
                   ),
                 ],
               ),
             ],
       );

  // 함수이름: requestMedicationContexts
  // 함수역할:
  // - 부모의 약 문맥을 가져오고 다중 시간대 설정이 켜진 경우에만 91번 약의 시간대를 아침·저녁으로 확장한다.
  // 매개변수:
  // - linkId (int): 부모 조회에 전달할 연동 ID.
  // 반환값:
  // - Future<List<ChatMedicationContext>>; 선택 범위 검사용 약 문맥.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async {
    final medications = await super.requestMedicationContexts(linkId: linkId);
    return [
      for (final medication in medications)
        if (multiSlotMedication && medication.medicationId == 91)
          medication.withScheduleSlots(['morning', 'evening'])
        else
          medication,
    ];
  }

  // 함수이름: recordMedicationTaken
  // 함수역할:
  // - 기준 날짜가 2026-09-21인지 검사하고 시간대·요청 ID·선택 약을 기록한다. 지정한 저장 대기 후 확인 메시지와 91번 약의 아침 완료 일정을 반환한다.
  // 매개변수:
  // - linkId (int): 반환 메시지의 연동 ID.
  // - clientMessageId (String): 기록하고 응답에 사용할 복용 확인 요청 ID.
  // - scheduleDate (String): 기대 기준일과 일치해야 하는 일정 날짜.
  // - slotKey (String): 기록할 선택 시간대.
  // - medicationIds (List<int>): 기록할 선택 약 목록.
  // 반환값:
  // - Future<ChatMedicationTakenResult>; 확인 메시지와 갱신된 일정이며 날짜 불일치 시 검증이 실패한다.
  @override
  Future<ChatMedicationTakenResult> recordMedicationTaken({
    required int linkId,
    required String clientMessageId,
    required String scheduleDate,
    required String slotKey,
    required List<int> medicationIds,
  }) async {
    expect(scheduleDate, '2026-09-21');
    takenSlotKeys.add(slotKey);
    takenRequestIds.add(clientMessageId);
    takenMedicationIds.add(medicationIds);
    if (saveGate != null) await saveGate!.future;
    return ChatMedicationTakenResult(
      message: ChatMessage(
        messageId: 100 + takenRequestIds.length,
        linkId: linkId,
        senderHash: 'patient-a',
        clientMessageId: clientMessageId,
        body: '아침 테스트정 복용을 기록했습니다.',
        createdAt: DateTime.utc(2026, 9, 21),
      ),
      schedules: const [
        MedicationSchedule(
          medicationID: '91',
          medicationName: '테스트정',
          scheduleSlotKeys: ['morning'],
          slotStatuses: {'morning': true},
        ),
      ],
    );
  }
}

// 운영 경로와 같은 기기 전송 대기열을 채팅 테스트에 연결할 때 쓰는 기준 시각(2026-09-21 12:00 KST).
final DateTime _doseNow = DateTime.utc(2026, 9, 21, 3);

// 아침·저녁에 복용하는 약 한 건으로 구성한 오늘 일정 캐시.
const List<MedicationSchedule> _cachedTwoSlotSchedule = [
  MedicationSchedule(
    medicationID: '91',
    medicationName: '테스트정',
    dosage: '1정',
    intakeTime: '1회',
    medicationTime: 2,
    scheduleSlotKeys: ['morning', 'evening'],
  ),
];

// Function Name: _attachChatDoseSync
// Description:
// - Attaches the production dose-sync service and outbox to a patient view model, then seeds its schedule cache at the fixed test clock.
// Parameters:
// - schedules (List<MedicationSchedule>): cached schedules; defaults to one medication with morning and evening slots.
// Returns:
// - Future<DoseSyncHarness>; the attached harness after seeding completes.
Future<DoseSyncHarness> _attachChatDoseSync([
  List<MedicationSchedule> schedules = _cachedTwoSlotSchedule,
]) async {
  final harness = await attachTestDoseSync(
    MedBuddyViewModel(
      patientHash: 'patient-a',
      checkSchedule: _ChatScheduleControl(),
      setNotification: _ChatSetNotification(),
    ),
    clock: () => _doseNow,
  );
  await harness.seedSchedules(schedules);
  return harness;
}

// Function Name: _pumpPatientChat
// Description:
// - Mounts patient chat under the dose-sync view model and settles initial loading, optionally applying explicit display constraints.
// Parameters:
// - tester (WidgetTester): mounts and settles the widget tree.
// - harness (DoseSyncHarness): supplies the patient view model and outbox.
// - control (ManageLinkedChat): chat request provider.
// - realtime (LinkedChatRealtimeService): event and connection-state provider.
// - mediaQuery (MediaQueryData?): optional screen and text-scaling configuration.
// Returns:
// - Future<void>; completes when initial frames settle.
Future<void> _pumpPatientChat(
  WidgetTester tester,
  DoseSyncHarness harness, {
  required ManageLinkedChat control,
  required LinkedChatRealtimeService realtime,
  MediaQueryData? mediaQuery,
}) async {
  final Widget chat = LinkedChatUI(
    linkId: 17,
    currentUserHash: 'patient-a',
    patientHash: 'patient-a',
    control: control,
    realtimeService: realtime,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: harness.viewModel,
      child: MaterialApp(
        home: mediaQuery == null
            ? chat
            : MediaQuery(data: mediaQuery, child: chat),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: _selectDoseSlots
// 함수역할:
// - 채팅의 약 선택 화면에서 91번 약의 지정 시간대들을 눌러 선택하고 확인하여 채팅으로 돌아온다.
// 매개변수:
// - tester (WidgetTester): 메뉴·선택 화면의 입력과 애니메이션을 처리한다.
// - slots (List<String>): 91번 약에서 누를 시간대 키 목록.
// 반환값:
// - Future<void>; 선택 확인 후 화면이 안정되면 완료한다.
Future<void> _selectDoseSlots(WidgetTester tester, List<String> slots) async {
  await tester.tap(find.byKey(const ValueKey('chatActions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('chat-action-0')));
  await tester.pumpAndSettle();
  for (final slot in slots) {
    final row = find.byKey(
      ValueKey('scheduleMedicationSelectionOption_${slot}_91'),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.byKey(const ValueKey('scheduleMedicationSelectionConfirm')),
  );
  await tester.pumpAndSettle();
}

// Function Name: _tapTaken
// Description:
// - Reveals and taps the taken quick reply, then settles the dose recording and resulting frames.
// Parameters:
// - tester (WidgetTester): finds, reveals, and taps the quick reply.
// Returns:
// - Future<void>; completes after the resulting frames settle.
Future<void> _tapTaken(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(ActionChip, '먹었어요'));
  await tester.tap(find.widgetWithText(ActionChip, '먹었어요'));
  await tester.pumpAndSettle();
}

// Function Name: _closeChat
// Description:
// - Unmounts chat and closes its realtime service, request control, and dose-sync harness before retry timers can outlive the test.
// Parameters:
// - tester (WidgetTester): replaces chat with an empty widget.
// - harness (DoseSyncHarness): owns the dose queue and sync resources to close.
// - control (ManageLinkedChat): chat request control to dispose.
// - realtime (_FakeRealtimeService): broadcast streams and authentication client to close.
// Returns:
// - Future<void>; completes after all listed resources close.
Future<void> _closeChat(
  WidgetTester tester,
  DoseSyncHarness harness, {
  required ManageLinkedChat control,
  required _FakeRealtimeService realtime,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await realtime.dispose();
  control.dispose();
  await harness.close();
}

// 클래스명: _ChatScheduleControl
// 역할: 채팅에서 이동한 복약 일정 화면에 저녁 약을 제공하는 대역.
// 주요 책임:
// - 서버 조회 대신 저녁 0.5정 일정 한 건을 반환한다.
// 속성:
// - 직접 선언한 속성 없음; CheckSchedule을 상속한다.
class _ChatScheduleControl extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 저녁 카드의 이동 대상을 확인할 수 있도록 저녁 전용 약 한 건을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationSchedule>>; evening-medication ID의 저녁 일정.
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
// 역할: 채팅에서 일정 화면으로 이동할 때 사용할 빈 알림 설정 대역.
// 주요 책임:
// - 서버 조회 없이 알림 목록을 비워 테스트를 격리한다.
// 속성:
// - 직접 선언한 속성 없음; SetNotification을 상속한다.
class _ChatSetNotification extends SetNotification {
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 실제 알림 설정 조회 없이 빈 목록을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<MedicationAlarm>>; 빈 알림 목록.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => const [];
}

// 클래스명: _FakeRealtimeService
// 역할: WebSocket 없이 메시지와 연결 상태를 주입하는 실시간 서비스 대역.
// 주요 책임:
// - 방송 스트림으로 이벤트를 전달하고 시작·중지·정리 동작을 재현한다.
// 속성:
// - _events (StreamController<Map<String, dynamic>>): 직접 주입하는 메시지 이벤트 방송 스트림.
// - _states (StreamController<LinkedChatConnectionState>): 연결 상태 방송 스트림.
class _FakeRealtimeService extends LinkedChatRealtimeService {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LinkedChatConnectionState> _states =
      StreamController<LinkedChatConnectionState>.broadcast();

  // 함수이름: _FakeRealtimeService
  // 함수역할:
  // - 연동 17과 patient-a 계정에 대해 토큰이 없는 로컬 인증 클라이언트를 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - _FakeRealtimeService; 수동 이벤트 주입용 서비스.
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
  // - 테스트가 직접 주입한 메시지 이벤트를 여러 구독자에게 전달하는 스트림을 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<Map<String, dynamic>>; _events의 방송 스트림.
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  // 함수이름: states
  // 함수역할:
  // - 테스트가 지정한 연결 상태를 구독할 수 있도록 방송 스트림을 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Stream<LinkedChatConnectionState>; _states의 방송 스트림.
  @override
  Stream<LinkedChatConnectionState> get states => _states.stream;

  // 함수이름: start
  // 함수역할:
  // - 실제 소켓을 열지 않고 connected 상태 이벤트를 발행한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 상태 이벤트를 추가한 뒤 완료한다.
  @override
  Future<void> start() async {
    _states.add(LinkedChatConnectionState.connected);
  }

  // 함수이름: stop
  // 함수역할:
  // - 실제 소켓 작업 없이 disconnected 상태 이벤트를 발행한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 상태 이벤트를 추가한 뒤 완료한다.
  @override
  Future<void> stop() async {
    _states.add(LinkedChatConnectionState.disconnected);
  }

  // 함수이름: dispose
  // 함수역할:
  // - 메시지와 상태 스트림을 순서대로 닫고 인증 HTTP 클라이언트를 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 스트림 종료와 클라이언트 정리 후 완료한다.
  @override
  Future<void> dispose() async {
    await _events.close();
    await _states.close();
    authenticationClient.close();
  }
}

// Class Name: _NoMedicationChatControl
// Role: A chat control for a patient with no saved medications.
// Responsibilities:
// - Returns an empty attachment list while retaining normal chat behavior.
// Attributes:
// - No declared attributes; inherits request tracking from _RetryChatControl.
class _NoMedicationChatControl extends _RetryChatControl {
  // Function Name: _NoMedicationChatControl
  // Description:
  // - Creates a no-medication control with the initial-send failure disabled.
  // Parameters:
  // - None.
  // Returns:
  // - _NoMedicationChatControl; a successful-send fake with no saved medications.
  _NoMedicationChatControl() : super(failFirstSend: false);

  // Function Name: requestMedicationContexts
  // Description:
  // - Returns no saved medications regardless of the requested link.
  // Parameters:
  // - linkId (int): interface-compatible link identifier; unused by this fixed response.
  // Returns:
  // - Future<List<ChatMedicationContext>>; an empty list.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => const [];
}

// Class Name: _GatedMedicationChatControl
// Role: A chat control that delays the medication attachment list.
// Responsibilities:
// - Releases the inherited list only after the test completes the gate.
// Attributes:
// - gate (Completer<void>): controls when medication loading can finish.
class _GatedMedicationChatControl extends _RetryChatControl {
  final gate = Completer<void>();

  // Function Name: _GatedMedicationChatControl
  // Description:
  // - Creates a gated medication loader with the initial-send failure disabled.
  // Parameters:
  // - None.
  // Returns:
  // - _GatedMedicationChatControl; a loader whose gate is initially pending.
  _GatedMedicationChatControl() : super(failFirstSend: false);

  // Function Name: requestMedicationContexts
  // Description:
  // - Waits for the gate, then delegates to the inherited medication list; a gate error propagates to the caller.
  // Parameters:
  // - linkId (int): forwarded to the inherited medication lookup.
  // Returns:
  // - Future<List<ChatMedicationContext>>; the default list after the gate opens.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async {
    await gate.future;
    return super.requestMedicationContexts(linkId: linkId);
  }
}

// 클래스명: _DeleteChatControl
// 역할: 메시지 삭제 대상과 범위를 기록하는 채팅 대역.
// 주요 책임:
// - 삭제 요청을 수집한 후 선택적으로 오프라인 오류를 발생시킨다.
// 속성:
// - failDeletion (bool): 삭제 요청 실패 여부.
// - deletionIds (List<List<int>>): 요청별 삭제 메시지 ID 목록.
// - deletionScopes (List<ChatDeletionScope>): 요청별 삭제 범위.
class _DeleteChatControl extends _RetryChatControl {
  final bool failDeletion;
  final List<List<int>> deletionIds = [];
  final List<ChatDeletionScope> deletionScopes = [];

  // 함수이름: _DeleteChatControl
  // 함수역할:
  // - 지정 이력과 삭제 실패 조건을 보관하고 일반 메시지의 첫 전송 실패는 끈다.
  // 매개변수:
  // - historyMessages (List<ChatMessage>): 부모 대역에 전달할 초기 채팅 이력.
  // - failDeletion (bool): 삭제를 StateError로 실패시킬지 여부이며 기본값은 false이다.
  // 반환값:
  // - _DeleteChatControl; 삭제 요청 기록용 대역.
  _DeleteChatControl({
    required super.historyMessages,
    this.failDeletion = false,
  }) : super(failFirstSend: false);

  // 함수이름: deleteMessages
  // 함수역할:
  // - 삭제 ID와 범위를 기록하고 failDeletion이 켜져 있으면 StateError를 던진다. 이력 자체를 변경하지는 않는다.
  // 매개변수:
  // - linkId (int): 인터페이스의 연동 ID이며 이 대역에서는 사용하지 않는다.
  // - messageIds (List<int>): 기록할 삭제 대상 ID 목록.
  // - scope (ChatDeletionScope): 기록할 개인 또는 전체 삭제 범위.
  // 반환값:
  // - Future<void>; 요청 기록 후 완료하거나 설정된 오류로 실패한다.
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

// Class Name: _RemovableLinkChatControl
// Role: A chat control that simulates a link being removed during a conversation.
// Responsibilities:
// - Rejects subsequent history requests with HTTP 404 after removal.
// Attributes:
// - linkRemoved (bool): whether history access must be denied.
class _RemovableLinkChatControl extends _DeleteChatControl {
  bool linkRemoved = false;

  // Function Name: _RemovableLinkChatControl
  // Description:
  // - Creates a removable-link control with the supplied initial history.
  // Parameters:
  // - historyMessages (List<ChatMessage>): initial messages forwarded to the deletion-capable parent.
  // Returns:
  // - _RemovableLinkChatControl; initially permits history requests.
  _RemovableLinkChatControl({required super.historyMessages});

  // Function Name: requestHistory
  // Description:
  // - Throws ApiRequestException with status 404 for a removed link; otherwise delegates all paging arguments to the parent fake.
  // Parameters:
  // - linkId (int): link identifier forwarded to the parent.
  // - beforeMessageId (int?): optional older-page cursor.
  // - limit (int): requested page size, defaulting to 50.
  // Returns:
  // - Future<List<ChatMessage>>; inherited history or an access-denied error after removal.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async {
    if (linkRemoved) {
      throw ApiRequestException('Link was not found.', statusCode: 404);
    }
    return super.requestHistory(
      linkId: linkId,
      beforeMessageId: beforeMessageId,
      limit: limit,
    );
  }
}

// 함수이름: _deletionMessage
// 함수역할:
// - 발신자와 현재 시각 기준 경과 시간을 지정하여 삭제 가능 여부 검사용 메시지를 생성한다.
// 매개변수:
// - id (int): 메시지 ID와 본문의 구분자이며 기본값은 1이다.
// - sender (String): 발신자 해시이며 기본값은 patient-a이다.
// - hours (int): 생성 시각을 현재 UTC보다 앞당길 시간 수이며 기본값은 1이다.
// 반환값:
// - ChatMessage; 연동 17의 지정 발신자·나이 메시지.
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

// 함수이름: _historyShareMessage
// 함수역할:
// - 오늘에서 지정 일수 이전에 끝나는 7일 이력 공유와 큰 집계 수를 만들어 공유 카드 표시를 검사한다.
// 매개변수:
// - sender (String): 카드 발신자이며 기본값은 patient-a이다.
// - endDaysAgo (int): 오늘보다 공유 종료일을 앞당길 일수이며 기본값은 0이다.
// - separate (bool): 정기·필요시 분리 집계를 추가할지 여부이며 false이면 구형 합계만 제공한다.
// 반환값:
// - ChatMessage; 고정 ID·생성 시각과 상대 날짜 범위를 가진 공유 메시지.
ChatMessage _historyShareMessage({
  String sender = 'patient-a',
  int endDaysAgo = 0,
  bool separate = false,
}) {
  final end = MedicationHistoryDates.today(
    DateTime.now(),
  ).subtract(Duration(days: endDaysAgo));
  return ChatMessage.fromJson({
    'message_id': 71,
    'link_id': 17,
    'sender_hash': sender,
    'client_message_id': 'history-71',
    'body': 'Shared records',
    'message_kind': 'medication_history_share',
    'created_at': '2026-10-21T01:15:00Z',
    'context': {
      'history_context': {
        'start_date': MedicationHistoryDates.format(
          end.subtract(const Duration(days: 6)),
        ),
        'end_date': MedicationHistoryDates.format(end),
        'taken_count': 123456,
        'skipped_count': 2345,
        'unrecorded_count': 6789,
        if (separate) ...{
          'scheduled_taken_count': 123455,
          'scheduled_skipped_count': 2345,
          'scheduled_unrecorded_count': 6789,
          'as_needed_taken_count': 1,
        },
      },
    },
  });
}

// 함수이름: main
// 함수역할:
// - 채팅의 첨부·공유·복약 기록·삭제·읽음·연결 복구 및 늦은 응답에 대한 화면 경계 테스트를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  for (final patient in [false, true]) {
    for (final confirming in [false, true]) {
      // 함수이름: 열린 공유 흐름에 연동 해제를 반영한다: $patient $confirming
      // 함수역할:
      // - 환자·보호자의 공유 메뉴 또는 장소 확인창을 연 뒤 이력 조회가 403으로 끝나면, 열린 흐름에서도 공유 동작을 막고 메시지를 보내지 않는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('열린 공유 흐름에 연동 해제를 반영한다: $patient $confirming', (
        tester,
      ) async {
        final control = _RetryChatControl(failFirstSend: false);
        final realtime = _FakeRealtimeService();
        addTearDown(control.dispose);
        addTearDown(realtime.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: patient ? 'patient-a' : 'caregiver-a',
              patientHash: 'patient-a',
              control: control,
              realtimeService: realtime,
              careSelectorBuilder: (_) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      NearbyCareSelection(
                        phoneVerified: false,
                        place: NearbyCarePlace.fromJson({
                          'pharmacy_id': 'test-place',
                          'name': '시험 약국',
                          'address': '서울',
                          'latitude': 37.55,
                          'longitude': 126.92,
                        }),
                      ),
                    ),
                    child: const Text('장소 선택'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gate = Completer<List<ChatMessage>>();
        control.historyGate = gate;
        final previousRequests = control.historyRequests;
        realtime._states.add(LinkedChatConnectionState.connected);
        await tester.pump();
        expect(control.historyRequests, greaterThan(previousRequests));
        await tester.tap(find.byKey(const ValueKey('chatActions')));
        await tester.pumpAndSettle();
        if (confirming) {
          await tester.tap(find.byKey(const ValueKey('chat-action-3')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('장소 선택'));
          await tester.pumpAndSettle();
        }
        gate.completeError(ApiRequestException('Link ended', statusCode: 403));
        await tester.pumpAndSettle();
        if (confirming) {
          await tester.tap(find.byKey(const ValueKey('confirmCareShare')));
          await tester.pumpAndSettle();
        } else {
          for (final index in [0, 2, 3, 4, if (!patient) 1]) {
            expect(
              tester
                  .widget<ListTile>(find.byKey(ValueKey('chat-action-$index')))
                  .enabled,
              isFalse,
            );
          }
        }
        expect(control.sendAttempts, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final fails in [false, true]) {
    // 함수이름: 가려진 채팅의 늦은 약 상세조회가 화면을 열지 않는다: $fails
    // 함수역할:
    // - 다른 화면에 가려진 채팅의 늦은 약 상세 성공·오류는 화면을 열지 않으며, 채팅 복귀 후 새 요청은 정상적으로 상세 화면을 여는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('가려진 채팅의 늦은 약 상세조회가 화면을 열지 않는다: $fails', (tester) async {
      final control = _RetryChatControl(failFirstSend: false);
      final realtime = _FakeRealtimeService();
      addTearDown(control.dispose);
      addTearDown(realtime.dispose);
      await tester.pumpWidget(
        MaterialApp(
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
      await _selectDoseSlots(tester, ['morning']);
      final response = Completer<MedicationDetail>();
      control.detailGate = response;
      await tester.tap(find.text('테스트정'));
      await tester.pump();
      expect(control.detailRequests, 1);
      final navigator = Navigator.of(tester.element(find.byType(LinkedChatUI)));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('다른 화면')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (fails) {
        response.completeError(StateError('late detail failure'));
      } else {
        response.complete(
          const MedicationDetail(
            itemName: '테스트정',
            efficacy: '',
            usageMethod: '',
            warning: '',
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('다른 화면'), findsOneWidget);
      expect(find.text('약 상세정보'), findsNothing);
      expect(tester.takeException(), isNull);
      navigator.pop();
      await tester.pumpAndSettle();
      control.detailGate = null;
      await tester.tap(find.text('테스트정'));
      await tester.pumpAndSettle();
      expect(control.detailRequests, 2);
      expect(find.text('약 상세정보'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final caregiver in [false, true]) {
    // 함수이름: + 메뉴에서 현재 대화로 기록 공유 후 돌아온다: $caregiver
    // 함수역할:
    // - 환자·보호자가 현재 대화에 한정한 읽기 전용 이력 내보내기에서 명시적으로 공유하면 한 번만 전송하고, 공유 카드를 표시하며 작성 중인 초안을 유지하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('+ 메뉴에서 현재 대화로 기록 공유 후 돌아온다: $caregiver', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sender = caregiver ? 'caregiver-a' : 'patient-a';
      final messages = <ChatMessage>[];
      final control = _RetryChatControl(
        failFirstSend: false,
        historyMessages: messages,
      );
      final realtime = _FakeRealtimeService();
      final posts = <Map<String, dynamic>>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: MedBuddyTheme.light(),
              home: LinkedChatUI(
                linkId: 17,
                currentUserHash: sender,
                patientHash: 'patient-a',
                control: control,
                realtimeService: realtime,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '작성 중인 메시지');
          await tester.pump();
          await tester.tap(find.byKey(const Key('chatActions')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('chat-action-4')));
          await tester.pumpAndSettle();
          final screen = tester.widget<MedicationHistoryUI>(
            find.byType(MedicationHistoryUI),
          );
          expect(screen.patientHash, 'patient-a');
          expect(screen.currentUserHash, sender);
          expect(screen.chatLinkId, 17);
          expect(screen.readOnly, isTrue);
          expect(screen.initiallyShowExport, isTrue);
          expect(posts, isEmpty);
          await tester.tap(find.byKey(const Key('history-share-chat')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('history-share-recipient-17')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('history-share-recipient-18')),
            findsNothing,
          );
          expect(posts, isEmpty);
          await tester.tap(find.byKey(const Key('history-chat-send')));
          await tester.pumpAndSettle();
          expect(posts, hasLength(1));
          expect(posts.single['message_kind'], 'medication_history_share');
          expect(posts.single.containsKey('patient_hash'), isFalse);
          expect(posts.single.containsKey('history_context'), isFalse);
          expect(find.byType(MedicationHistoryUI), findsNothing);
          expect(
            find.byKey(const Key('chat-medication-history-card')),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '작성 중인 메시지',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/link/list')) {
            return historyTestResponse({
              'data': [
                for (final id in [17, 18])
                  {
                    'link_id': id,
                    'patient_hash': 'patient-a',
                    'caregiver_hash': 'caregiver-a',
                    'link_status': true,
                    'patient_alias': '환자',
                    'caregiver_alias': '가족',
                  },
              ],
            });
          }
          if (request.method == 'GET') {
            expect(request.url.queryParameters['patient_hash'], 'patient-a');
            return historyTestResponse(
              historyTestBody(
                start: request.url.queryParameters['start_date']!,
                end: request.url.queryParameters['end_date']!,
                items: [],
              ),
            );
          }
          expect(request.url.path, endsWith('/links/17/messages'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          posts.add(body);
          final result = {
            'message_id': 99,
            'link_id': 17,
            'sender_hash': sender,
            'client_message_id': body['client_message_id'],
            'body': body['body'],
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'message_kind': 'medication_history_share',
            'context': {
              'history_context': {
                'start_date': body['history_start_date'],
                'end_date': body['history_end_date'],
                'taken_count': 0,
                'skipped_count': 0,
                'unrecorded_count': 0,
              },
            },
          };
          messages.add(ChatMessage.fromJson(result));
          return historyTestResponse({'success': true, 'data': result});
        }),
      );
      await realtime.dispose();
      control.dispose();
    });
  }

  for (final cancelSearch in [false, true]) {
    // 함수이름: 저장 약 없는 검색 첨부 취소는 초안을 바꾸지 않는다: $cancelSearch
    // 함수역할:
    // - 저장 약이 없는 상태에서 검색 자체 또는 검색 결과 첨부를 취소하면 선택 약이 남지 않고 초안과 전송 횟수가 바뀌지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('저장 약 없는 검색 첨부 취소는 초안을 바꾸지 않는다: $cancelSearch', (tester) async {
      final control = _NoMedicationChatControl();
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          theme: MedBuddyTheme.light(),
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
      await tester.enterText(find.byType(TextField), '작성 중');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-action-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-search-medication')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(MedicationSearchUI))).pop(
        cancelSearch
            ? null
            : const MedicationDetail(
                itemSeq: '202600001',
                itemName: '취소할 검색정',
                efficacy: '',
                usageMethod: '',
                warning: '',
              ),
      );
      await tester.pumpAndSettle();
      if (cancelSearch) {
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('scheduleMedicationSelectionConfirm')),
              )
              .onPressed,
          isNull,
        );
      } else {
        expect(find.text('취소할 검색정'), findsOneWidget);
      }
      Navigator.of(tester.element(find.byType(CheckScheduleUI))).pop();
      await tester.pumpAndSettle();
      expect(find.text('취소할 검색정'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '작성 중',
      );
      expect(control.sendAttempts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await realtime.dispose();
      control.dispose();
    });
  }

  for (final hasSaved in [false, true]) {
    // 함수이름: 검색약은 저장 약과 분리해 첨부하고 복용 기록 없이 보낸다: $hasSaved
    // 함수역할:
    // - 검색 약 참조를 저장 약 ID와 구분해 첨부하고 복용 답장은 노출하지 않으며, 실패 후 같은 요청 ID로 시간대 없는 일반 메시지를 재전송하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('검색약은 저장 약과 분리해 첨부하고 복용 기록 없이 보낸다: $hasSaved', (tester) async {
      final control = hasSaved
          ? _RetryChatControl(failFirstSend: false)
          : _NoMedicationChatControl();
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          theme: MedBuddyTheme.light(),
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
      await tester.tap(find.byKey(const Key('chatActions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-action-4')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-action-0')));
      await tester.pumpAndSettle();
      if (hasSaved) {
        await tester.tap(
          find.byKey(const Key('scheduleMedicationSelectionOption_morning_91')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('chat-search-medication')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MedicationSearchUI>(find.byType(MedicationSearchUI))
            .selectionMode,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(MedicationSearchUI))).pop(
        const MedicationDetail(
          itemSeq: '202600001',
          itemName: '미등록 검색정',
          efficacy: '',
          usageMethod: '',
          warning: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('미등록 검색정'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('scheduleMedicationSelectionConfirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('미등록 검색정'), findsOneWidget);
      expect(find.text('복용했어요'), findsNothing);
      await tester.enterText(find.byType(TextField), '이 약에 대해 궁금해요.');
      await tester.pump();
      control.failSends = true;
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await tester.pumpAndSettle();
      expect(find.text('미등록 검색정'), findsOneWidget);
      control.failSends = false;
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await tester.pumpAndSettle();
      expect(control.clientMessageIds[0], control.clientMessageIds[1]);
      expect(control.referenceGroups.last.single.itemSeq, '202600001');
      expect(control.medicationIdGroups.last, hasSaved ? [91] : isEmpty);
      expect(control.slotKeys.last, isNull);
      expect(control.messageKinds.last, ChatMessageKind.text);
      expect(find.text('미등록 검색정'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await realtime.dispose();
      control.dispose();
    });
  }
  for (final (hospital, language, status) in [
    (false, 'ko', 'before_open'),
    (false, 'en', 'closing_soon'),
    (true, 'ko', 'closed'),
    (true, 'en', 'open'),
    (true, 'en', 'closed'),
  ]) {
    // 함수이름: shared place compact status and exact detail navigation $hospital/$language/$status
    // 함수역할:
    // - 병원·약국 공유 카드의 언어별 영업 상태, 전체 주소와 버튼 정렬을 확인하고, 현재 영업 여부를 추정하지 않은 동일 장소로 이동하되 삭제 후에는 이전 콜백도 차단하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets(
      'shared place compact status and exact detail navigation $hospital/$language/$status',
      (tester) async {
        const name = '이름이 긴 테스트 병원 약국';
        const address = '서울특별시 마포구 테스트로 152, 테스트빌딩 본관 4층 (상세 주소를 생략하지 않습니다)';
        final hour = switch (status) {
          'closed' => '20:00',
          'before_open' => '08:00',
          'closing_soon' => '18:45',
          _ => '13:00',
        };
        final placeJson = <String, dynamic>{
          if (hospital)
            'hospital_id': 'place-123'
          else
            'pharmacy_id': 'place-123',
          'name': name,
          'address': address,
          'telephone': '02-000-0000',
          'latitude': 37.55,
          'longitude': 126.92,
          'schedule_date': '2026-10-28',
          'operating_snapshot': {
            'status': status,
            'as_of': '2026-10-27T$hour:00+09:00',
            'opens_at': '2026-10-27T09:00:00+09:00',
            'closes_at': '2026-10-27T19:00:00+09:00',
          },
        };
        final control = _RetryChatControl(
          historyMessages: [
            ChatMessage(
              messageId: 1,
              linkId: 17,
              senderHash: 'caregiver-a',
              clientMessageId: 'place-share-1',
              body: 'Shared place',
              createdAt: DateTime.utc(2026, 10, 27, 4),
              hospitalContext: hospital
                  ? ChatHospitalContext.fromJson(placeJson)
                  : null,
              pharmacyContext: hospital
                  ? null
                  : ChatPharmacyContext.fromJson(placeJson),
              messageKind: hospital
                  ? ChatMessageKind.hospitalShare
                  : ChatMessageKind.pharmacyShare,
            ),
          ],
        );
        final realtime = _FakeRealtimeService();
        NearbyCarePlace? opened;
        bool? hospitalOpened;
        await tester.binding.setSurfaceSize(const Size(360, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              userSetting: UserSetting(language: language),
              control: control,
              realtimeService: realtime,
              careDetailsBuilder: (place, hospitals) {
                opened = place;
                hospitalOpened = hospitals;
                return const Scaffold(body: Text('Exact shared place'));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(switch (status) {
            'closed' => language == 'ko' ? '19:00 영업 종료' : 'Closed at 19:00',
            'before_open' => '영업 전 · 09:00 시작',
            'closing_soon' => 'Closing soon · Closes 19:00',
            _ => 'Open · Closes 19:00',
          }),
          findsOneWidget,
        );
        final addressText = tester.widget<Text>(find.text(address));
        final panel =
            tester
                    .widget<Container>(
                      find.byKey(const Key('chat-place-summary-panel')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(panel.color, MedBuddyColors.chatContentSurface);
        expect(
          panel.border,
          Border.all(color: MedBuddyColors.chatContentBorder),
        );
        final title = language == 'ko'
            ? (hospital ? '병원 정보' : '약국 정보')
            : (hospital ? 'Hospital information' : 'Pharmacy information');
        expect(find.text(title), findsOneWidget);
        expect(tester.widget<Text>(find.text(title)).style!.fontSize, 17);
        expect(
          tester.widget<Text>(find.text('Shared place')).style!.fontWeight,
          FontWeight.w600,
        );
        expect(addressText.maxLines, isNull);
        expect(addressText.overflow, isNot(TextOverflow.ellipsis));
        expect(find.textContaining('정보 확인:'), findsNothing);
        expect(find.textContaining('예약이 확정'), findsNothing);
        expect(find.text('정보 보기'), findsNothing);
        expect(find.text('Details'), findsNothing);
        final map = tester.getRect(
          find.byKey(const ValueKey('chat-place-preview-37.55-126.92')),
        );
        final call = tester.getRect(
          find.widgetWithText(OutlinedButton, language == 'ko' ? '전화' : 'Call'),
        );
        final directions = tester.getRect(
          find.widgetWithText(
            OutlinedButton,
            language == 'ko' ? '길찾기' : 'Directions',
          ),
        );
        expect(call.width, closeTo(directions.width, 0.1));
        expect(call.left, closeTo(map.left, 2));
        expect(directions.right, closeTo(map.right, 2));
        expect(
          find.descendant(
            of: find.byKey(const Key('chat-place-details')),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
        );
        final callback = tester
            .widget<OutlinedButton>(find.byKey(const Key('chat-place-details')))
            .onPressed!;
        await tester.tap(find.byKey(const Key('chat-place-details')));
        await tester.pumpAndSettle();
        expect(opened!.placeId, 'place-123');
        expect(opened!.address, address);
        expect(opened!.isOpenNow, isNull);
        expect(opened!.todayCloseTime, isNull);
        expect(hospitalOpened, hospital);
        Navigator.of(tester.element(find.text('Exact shared place'))).pop();
        await tester.pumpAndSettle();
        realtime._events.add({
          'type': 'chat_messages_deleted',
          'link_id': 17,
          'message_ids': [1],
          'scope': 'everyone',
        });
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(find.text('Exact shared place'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      },
    );
  }

  for (final language in ['ko', 'en']) {
    // 함수이름: 같은 날 여러 메시지는 하나의 현지 날짜로 묶음 $language
    // 함수역할:
    // - 현지 자정을 경계로 메시지 세 건을 날짜 구분선 두 개로 묶고, 같은 날의 구분선과 요일을 언어에 맞춰 한 번만 표시하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('같은 날 여러 메시지는 하나의 현지 날짜로 묶음 $language', (tester) async {
      // 함수이름: message
      // 함수역할:
      // - 날짜 구분선 검사용 환자 메시지를 만들면서 입력 시각을 UTC 저장 형식으로 변환한다.
      // 매개변수:
      // - id (int): 메시지 ID 및 본문·클라이언트 ID의 구분자.
      // - time (DateTime): 현지 날짜 묶음을 확인할 생성 시각.
      // 반환값:
      // - ChatMessage; 지정 시각을 UTC로 담은 연동 17의 메시지.
      ChatMessage message(int id, DateTime time) => ChatMessage(
        messageId: id,
        linkId: 17,
        senderHash: 'patient-a',
        clientMessageId: 'date-$id',
        body: 'Date message $id',
        createdAt: time.toUtc(),
      );
      final control = _RetryChatControl(
        historyMessages: [
          message(1, DateTime(2026, 10, 29, 23, 59)),
          message(2, DateTime(2026, 10, 30)),
          message(3, DateTime(2026, 10, 30, 10)),
        ],
      );
      final realtime = _FakeRealtimeService();
      await tester.binding.setSurfaceSize(const Size(500, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            userSetting: UserSetting(language: language),
            control: control,
            realtimeService: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatDateDivider), findsNWidgets(2));
      final first = find.byKey(const Key('chat-date-2026-10-29'));
      final second = find.byKey(const Key('chat-date-2026-10-30'));
      expect(
        tester
            .getCenter(find.descendant(of: second, matching: find.byType(Text)))
            .dx,
        closeTo(tester.getCenter(second).dx, 0.5),
      );
      expect(
        tester.getRect(first).bottom,
        lessThan(tester.getRect(second).top),
      );
      expect(
        find.text(
          language == 'ko' ? '2026년 10월 30일 금요일' : '2026-10-30 · Friday',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    });

    for (final mine in [true, false]) {
      // 함수이름: copy preserves message text $language/$mine
      // 함수역할:
      // - 본인·상대 메시지의 본문과 메뉴 서체를 확인하고 한국어·영어 복사 메뉴가 선택 모드 없이 원문을 클립보드로 전달하는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('copy preserves message text $language/$mine', (
        tester,
      ) async {
        final control = _RetryChatControl(
          historyMessages: [
            _deletionMessage(sender: mine ? 'patient-a' : 'caregiver-a'),
          ],
        );
        final realtime = _FakeRealtimeService();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              userSetting: UserSetting(language: language),
              control: control,
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = tester.widget<Text>(find.text('Message 1'));
        expect(body.style!.fontWeight, FontWeight.w600);
        expect(
          tester.widget<TextField>(find.byType(TextField)).style!.fontWeight,
          FontWeight.w600,
        );
        expect(
          find.text(language == 'ko' ? '약 정보' : 'Medication information'),
          findsNothing,
        );
        await tester.longPress(find.text('Message 1'));
        await tester.pumpAndSettle();
        expect(find.text(language == 'ko' ? '복사' : 'Copy'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.text(language == 'ko' ? '복사' : 'Copy'))
              .style,
          MedBuddyTextStyles.menuTitle,
        );
        await tester.tap(find.byKey(const Key('chat-copy-message')));
        await tester.pumpAndSettle();
        expect(copied, 'Message 1');
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      });

      // 함수이름: deleted bubble retains sender and disables copy $language/$mine
      // 함수역할:
      // - 삭제 메시지는 발신자별 색상·정렬과 기울임 안내를 유지하면서 본문과 복사 동작을 숨기고 선택 동작만 제공하는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets(
        'deleted bubble retains sender and disables copy $language/$mine',
        (tester) async {
          final control = _RetryChatControl(
            historyMessages: [
              _deletionMessage(
                sender: mine ? 'patient-a' : 'caregiver-a',
              ).copyWith(deletedForEveryone: true),
            ],
          );
          final realtime = _FakeRealtimeService();
          await tester.pumpWidget(
            MaterialApp(
              home: LinkedChatUI(
                linkId: 17,
                currentUserHash: 'patient-a',
                patientHash: 'patient-a',
                userSetting: UserSetting(language: language),
                control: control,
                realtimeService: realtime,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bubble = find.byKey(const ValueKey('chat-bubble-1'));
          final decoration =
              tester.widget<Container>(bubble).decoration! as BoxDecoration;
          expect(
            decoration.color,
            mine ? MedBuddyColors.chatOutgoing : Colors.white,
          );
          final alignment = tester.widget<Align>(
            find.ancestor(of: bubble, matching: find.byType(Align)).first,
          );
          expect(
            alignment.alignment,
            mine ? Alignment.centerRight : Alignment.centerLeft,
          );
          final deleted = find.text(
            language == 'ko' ? '삭제된 메시지입니다.' : 'This message was deleted.',
          );
          expect(
            tester.widget<Text>(deleted).style!.fontStyle,
            FontStyle.italic,
          );
          expect(find.text('Message 1'), findsNothing);
          await tester.longPress(deleted);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('chat-copy-message')), findsNothing);
          expect(find.byKey(const Key('chat-select-message')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await realtime.dispose();
          control.dispose();
        },
      );
    }
  }

  // 함수이름: copy menu rechecks a message deleted while open
  // 함수역할:
  // - 복사 메뉴를 연 뒤 전체 삭제 이벤트가 도착하면 메뉴를 눌러도 삭제된 본문을 클립보드로 보내지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('copy menu rechecks a message deleted while open', (
    tester,
  ) async {
    final control = _RetryChatControl(historyMessages: [_deletionMessage()]);
    final realtime = _FakeRealtimeService();
    var copies = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copies++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
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
    realtime._events.add({
      'type': 'chat_messages_deleted',
      'link_id': 17,
      'message_ids': [1],
      'scope': 'everyone',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-copy-message')));
    await tester.pumpAndSettle();
    expect(copies, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  for (final language in ['ko', 'en']) {
    for (final (mine, separate) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      // 함수이름: history card wraps large text $language/$mine/$separate
      // 함수역할:
      // - 좁은 큰 글씨 화면에서 언어·발신자·신구 집계 형식에 맞는 이력 요약과 비율을 표시하고, 공유 시각 중복·편집 제어 없이 카드가 배치되는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('history card wraps large text $language/$mine/$separate', (
        tester,
      ) async {
        final message = _historyShareMessage(
          sender: mine ? 'patient-a' : 'caregiver-a',
          separate: separate,
        );
        final control = _RetryChatControl(historyMessages: [message]);
        final realtime = _FakeRealtimeService();
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 1100),
                textScaler: TextScaler.linear(1.6),
              ),
              child: LinkedChatUI(
                linkId: 17,
                currentUserHash: 'patient-a',
                patientHash: 'patient-a',
                userSetting: UserSetting(language: language),
                control: control,
                realtimeService: realtime,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final english = language == 'en';
        expect(
          find.text(english ? 'Medication history' : '복약 기록'),
          findsOneWidget,
        );
        expect(find.text(english ? 'Taken' : '복용함'), findsOneWidget);
        expect(find.text(english ? 'Skipped' : '건너뜀'), findsOneWidget);
        expect(find.text(english ? 'Unrecorded' : '미기록'), findsOneWidget);
        expect(
          find.text('${english ? 'At sharing' : '공유 당시'}: 2026-10-21 10:15'),
          findsNothing,
        );
        final localTime = message.createdAt.toLocal();
        expect(
          find.text(
            UserSetting(
              language: language,
            ).formatTime(localTime.hour, localTime.minute),
          ),
          findsOneWidget,
        );
        expect(
          find.text(english ? 'View latest records' : '최신 기록 보기'),
          findsOneWidget,
        );
        final card = find.byKey(const Key('chat-medication-history-card'));
        final panel =
            tester
                    .widget<Container>(
                      find.byKey(const Key('chat-history-summary-panel')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(panel.color, MedBuddyColors.chatContentSurface);
        expect(
          panel.border,
          Border.all(color: MedBuddyColors.chatContentBorder),
        );
        expect(panel.color, isNot(MedBuddyColors.chatOutgoing));
        expect(panel.color, isNot(Colors.white));
        expect(find.byKey(const Key('history-rate-chart')), findsOneWidget);
        expect(
          find.text(separate ? '123455/132589' : '123456/132590'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history-count-3')),
          separate ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const Key('history-rate-toggle')), findsNothing);
        expect(
          find.descendant(of: card, matching: find.byType(Checkbox)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      });
    }
  }

  // 함수이름: an expired history share explains why it cannot be opened
  // 함수역할:
  // - 조회 보존 기간을 벗어난 공유 이력에는 만료 이유를 표시하고 최신 기록 버튼과 카드의 화면 이동을 모두 막는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('an expired history share explains why it cannot be opened', (
    tester,
  ) async {
    final control = _RetryChatControl(
      historyMessages: [_historyShareMessage(endDaysAgo: 94)],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          patientHash: 'patient-a',
          userSetting: UserSetting(language: 'ko'),
          control: control,
          realtimeService: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-history-expired')), findsOneWidget);
    expect(
      find.byKey(const Key('chat-history-unrecorded-notice')),
      findsNothing,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('chat-view-latest-history')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('chat-medication-history-card')));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationHistoryUI), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  // Function Name: a quick second tap on a history card opens one screen
  // Description:
  // - Checks that rapid repeated history-card taps push only one read-only screen, so one back navigation returns directly to chat even when the history request is denied.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a quick second tap on a history card opens one screen', (
    tester,
  ) async {
    final control = _RetryChatControl(
      historyMessages: [_historyShareMessage()],
    );
    final realtime = _FakeRealtimeService();
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              userSetting: UserSetting(language: 'ko'),
              control: control,
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-view-latest-history')));
        await tester.tap(
          find.byKey(const Key('chat-view-latest-history')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(MedicationHistoryUI), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MedicationHistoryUI), findsNothing);
      },
      () => MockClient(
        (request) async => http.Response('{"detail":"Access revoked"}', 403),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  for (final caregiver in [false, true]) {
    // 함수이름: history card opens read-only shared range caregiver=$caregiver
    // 함수역할:
    // - 환자·보호자가 공유 카드를 열면 해당 환자와 공유 날짜 범위만 한 번 조회하고, 역할에 맞는 언어의 읽기 전용 화면을 사용하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets(
      'history card opens read-only shared range caregiver=$caregiver',
      (tester) async {
        final message = _historyShareMessage();
        final history = message.historyContext!;
        final control = _RetryChatControl(historyMessages: [message]);
        final realtime = _FakeRealtimeService();
        final reads = <Uri>[];
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: LinkedChatUI(
                  linkId: 17,
                  currentUserHash: caregiver ? 'caregiver-a' : 'patient-a',
                  patientHash: 'patient-a',
                  userSetting: UserSetting(language: caregiver ? 'en' : 'ko'),
                  control: control,
                  realtimeService: realtime,
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              caregiver
                  ? find.byKey(const Key('chat-view-latest-history'))
                  : find.text('복약 기록'),
            );
            await tester.pumpAndSettle();
            final screen = tester.widget<MedicationHistoryUI>(
              find.byType(MedicationHistoryUI),
            );
            expect(screen.patientHash, 'patient-a');
            expect(screen.readOnly, isTrue);
            expect(screen.isEnglish, caregiver);
            expect(screen.sharedRange!.start, history.startDate);
            expect(screen.sharedRange!.end, history.endDate);
            expect(reads, hasLength(1));
            expect(reads.single.path, endsWith('/care/history'));
            expect(reads.single.queryParameters, {
              'patient_hash': 'patient-a',
              'start_date': MedicationHistoryDates.format(history.startDate),
              'end_date': MedicationHistoryDates.format(history.endDate),
            });
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            expect(request.method, 'GET');
            reads.add(request.url);
            return http.Response('{"detail":"Access revoked"}', 403);
          }),
        );
        await realtime.dispose();
        control.dispose();
      },
    );
  }

  // 함수이름: revoked history card blocks both current and stale callbacks
  // 함수역할:
  // - 연동 해제 후 이력 카드·버튼을 비활성화하고 해제 전에 저장한 콜백으로도 이력 화면을 열 수 없는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('revoked history card blocks both current and stale callbacks', (
    tester,
  ) async {
    final control = _RemovableLinkChatControl(
      historyMessages: [_historyShareMessage()],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final button = find.byKey(const Key('chat-view-latest-history'));
    final staleCallback = tester.widget<OutlinedButton>(button).onPressed!;
    control.linkRemoved = true;
    realtime._states.add(LinkedChatConnectionState.connected);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('chat-medication-history-card')),
          )
          .onTap,
      isNull,
    );
    staleCallback();
    await tester.pumpAndSettle();
    expect(find.byType(MedicationHistoryUI), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  for (final scope in ['me', 'everyone']) {
    // 함수이름: deleted history card cannot reopen from stale callback: $scope
    // 함수역할:
    // - 개인 또는 전체 삭제 이벤트로 공유 카드와 본문이 사라진 뒤 이전 콜백을 호출해도 이력 화면을 다시 열지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets(
      'deleted history card cannot reopen from stale callback: $scope',
      (tester) async {
        final control = _RetryChatControl(
          historyMessages: [_historyShareMessage()],
        );
        final realtime = _FakeRealtimeService();
        await tester.pumpWidget(
          MaterialApp(
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
        final staleCallback = tester
            .widget<OutlinedButton>(
              find.byKey(const Key('chat-view-latest-history')),
            )
            .onPressed!;
        realtime._events.add({
          'type': 'chat_messages_deleted',
          'link_id': 17,
          'message_ids': [71],
          'scope': scope,
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('chat-medication-history-card')),
          findsNothing,
        );
        expect(find.text('Shared records'), findsNothing);
        staleCallback();
        await tester.pumpAndSettle();
        expect(find.byType(MedicationHistoryUI), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      },
    );
  }

  // 함수이름: selection and replaced account block captured history navigation
  // 함수역할:
  // - 메시지 선택 모드와 계정 교체 후에는 이전 이력 열기 콜백을 호출해도 화면 이동이 발생하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'selection and replaced account block captured history navigation',
    (tester) async {
      final control = _RetryChatControl(
        historyMessages: [_historyShareMessage()],
      );
      final realtime = _FakeRealtimeService();
      final nextControl = _RetryChatControl();
      final nextRealtime = _FakeRealtimeService();
      // 함수이름: app
      // 함수역할:
      // - 동일한 연동·환자에 사용자와 요청·이벤트 대역을 교체한 채팅 트리를 만든다.
      // 매개변수:
      // - user (String): 현재 접속 계정 해시.
      // - chat (ManageLinkedChat): 해당 계정에서 사용할 요청 대역.
      // - stream (LinkedChatRealtimeService): 해당 계정에서 사용할 실시간 이벤트 대역.
      // 반환값:
      // - Widget; 계정 교체 검사용 MaterialApp.
      Widget app(
        String user,
        ManageLinkedChat chat,
        LinkedChatRealtimeService stream,
      ) => MaterialApp(
        home: LinkedChatUI(
          linkId: 17,
          currentUserHash: user,
          patientHash: 'patient-a',
          control: chat,
          realtimeService: stream,
        ),
      );
      await tester.pumpWidget(app('patient-a', control, realtime));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('chat-view-latest-history'));
      final staleCallback = tester.widget<OutlinedButton>(button).onPressed!;
      await tester.longPress(find.text('Shared records'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-select-message')));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      staleCallback();
      await tester.pumpAndSettle();
      expect(find.byType(MedicationHistoryUI), findsNothing);
      await tester.pumpWidget(app('caregiver-b', nextControl, nextRealtime));
      await tester.pumpAndSettle();
      staleCallback();
      await tester.pumpAndSettle();
      expect(find.byType(MedicationHistoryUI), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      await nextRealtime.dispose();
      control.dispose();
      nextControl.dispose();
    },
  );

  // 함수이름: malformed history card retains body without a navigation action
  // 함수역할:
  // - 날짜가 없고 집계 값도 잘못된 이력 공유 문맥은 본문만 표시하며 이력 이동 버튼이나 화면 예외를 만들지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'malformed history card retains body without a navigation action',
    (tester) async {
      final message = ChatMessage.fromJson({
        'message_id': 71,
        'link_id': 17,
        'sender_hash': 'patient-a',
        'client_message_id': 'invalid-history-71',
        'body': 'Shared records',
        'created_at': '2026-10-21T01:15:00Z',
        'message_kind': 'medication_history_share',
        'context': {
          'history_context': {'taken_count': 'invalid'},
        },
      });
      final control = _RetryChatControl(historyMessages: [message]);
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Shared records'), findsOneWidget);
      expect(find.byKey(const Key('chat-view-latest-history')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  // 함수이름: 입력만 바뀌면 메시지 목록을 다시 그리지 않는다
  // 함수역할:
  // - 입력 본문 변경 시 기존 채팅 세션·말풍선·목록을 다시 만들지 않고 전송 버튼 활성 상태만 올바르게 갱신하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('입력만 바뀌면 메시지 목록을 다시 그리지 않는다', (tester) async {
    final control = _RetryChatControl(
      historyMessages: [
        for (var id = 1; id <= 35; id++) _deletionMessage(id: id),
      ],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final existing = tester.allElements.toSet();
    expect(
      existing.where(
        (element) => element.widget.runtimeType.toString() == '_MessageBubble',
      ),
      isNotEmpty,
    );
    final rebuilt = <String>[];
    final previousCallback = debugOnRebuildDirtyWidget;
    addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (existing.contains(element)) {
        rebuilt.add(element.widget.runtimeType.toString());
      }
    };
    final input = tester.widget<TextField>(find.byType(TextField));
    input.controller!.text = 'test';
    input.onChanged!('test');
    await tester.pump();
    debugOnRebuildDirtyWidget = previousCallback;
    expect(rebuilt, isNot(contains('_LinkedChatSessionUI')));
    expect(rebuilt, isNot(contains('_MessageBubble')));
    expect(rebuilt, isNot(contains('ListView')));
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chatSendButton')))
          .onPressed,
      isNotNull,
    );
    input.controller!.clear();
    input.onChanged!('');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chatSendButton')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  // 함수이름: outgoing unread receipt clears on peer read and stays cleared
  // 함수역할:
  // - 상대 읽음 이벤트의 경계까지 본인 메시지의 미확인 표시를 제거하고, 재연결 이력이 이전 상태여도 표시를 되살리지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('outgoing unread receipt clears on peer read and stays cleared', (
    tester,
  ) async {
    final control = _RetryChatControl(
      historyMessages: [
        _deletionMessage(id: 1),
        _deletionMessage(id: 2),
        _deletionMessage(id: 3, sender: 'caregiver-a'),
      ],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-receipt-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-receipt-3')), findsNothing);
    realtime._events.add({
      'type': 'chat_read',
      'reader_hash': 'caregiver-a',
      'through_message_id': 1,
      'read_at': '2026-09-28T11:00:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsNothing);
    expect(find.byKey(const ValueKey('chat-unread-receipt-2')), findsOneWidget);
    realtime._states.add(LinkedChatConnectionState.connected);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-unread-receipt-1')), findsNothing);
    realtime._events.add({
      'type': 'chat_read',
      'reader_hash': 'caregiver-a',
      'through_message_id': 2,
      'read_at': '2026-09-28T11:01:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-unread-receipt-2')), findsNothing);
    expect(find.textContaining('· 읽음'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  // 함수이름: long variable-height history opens at latest and keeps unread boundary
  // 함수역할:
  // - 높이가 다른 긴 대화는 최신 메시지에서 열리고 화면 축소 후에도 위치를 유지하며, 과거 탐색 중 수신한 메시지는 최신 위치로 돌아온 뒤에만 읽음 처리하고 초안과 입장 경계를 보존하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'long variable-height history opens at latest and keeps unread boundary',
    (tester) async {
      final latestRequest = ValueNotifier<int>(0);
      addTearDown(latestRequest.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final control = _RetryChatControl(
        historyMessages: [
          for (var id = 1; id <= 50; id++)
            ChatMessage(
              messageId: id,
              linkId: 17,
              senderHash: 'caregiver-a',
              clientMessageId: 'long-$id',
              body: 'Message $id ${'긴 대화 내용 ' * (id % 9)}',
              createdAt: DateTime(2026, 9, 28, 10, id),
              readAt: id < 48 ? DateTime(2026, 9, 28, 11) : null,
            ),
        ],
      );
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            latestMessageRequest: latestRequest,
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            control: control,
            realtimeService: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(
        find.byKey(const Key('chat-message-list')),
      );
      expect(list.reverse, isTrue);
      expect(list.controller!.offset, 0);
      expect(
        find.byKey(const ValueKey('chat-message-50')).hitTestable(),
        findsOneWidget,
      );
      expect(control.markedReadIds, contains(50));
      await tester.binding.setSurfaceSize(const Size(360, 500));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-message-50')).hitTestable(),
        findsOneWidget,
      );
      list.controller!.jumpTo(300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-message-48')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-unread-divider')), findsOneWidget);
      expect(find.text('여기까지 읽음'), findsOneWidget);
      final unreadRect = tester.getRect(
        find.byKey(const Key('chat-unread-divider')),
      );
      final labelRect = tester.getRect(find.text('여기까지 읽음'));
      expect(labelRect.center.dx, closeTo(unreadRect.center.dx, 0.5));
      final divider = find.descendant(
        of: find.byKey(const Key('chat-unread-divider')),
        matching: find.byType(Divider),
      );
      expect(tester.getRect(divider).left, unreadRect.left);
      expect(tester.getRect(divider).right, unreadRect.right);
      // 과거 대화를 읽고 있을 때 받은 메시지는 최신 위치로 돌아오기 전에는 읽지 않는다.
      list.controller!.jumpTo(900);
      await tester.pumpAndSettle();
      realtime._events.add({
        'type': 'chat_message',
        'message': {
          'message_id': 51,
          'link_id': 17,
          'sender_hash': 'caregiver-a',
          'client_message_id': 'new-51',
          'body': 'New incoming',
          'created_at': '2026-09-28T12:00:00Z',
        },
      });
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(80));
      expect(control.markedReadIds, isNot(contains(51)));
      await tester.drag(
        find.byKey(const Key('chat-message-list')),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(find.text('New incoming').hitTestable(), findsOneWidget);
      expect(control.markedReadIds, contains(51));
      await tester.enterText(find.byType(TextField), '작성 중인 메시지');
      list.controller!.jumpTo(900);
      await tester.pumpAndSettle();
      latestRequest.value++;
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
      expect(find.text('New incoming').hitTestable(), findsOneWidget);
      expect(find.text('작성 중인 메시지'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  // 함수이름: older history retains the entry unread boundary
  // 함수역할:
  // - 입장 시 미확인 경계가 이전 페이지에 있어도 더 오래된 이력을 불러오면 원래 경계를 표시하고 더 불러오기 버튼을 제거하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('older history retains the entry unread boundary', (
    tester,
  ) async {
    final control = _RetryChatControl()
      ..unreadSummary = const ChatUnreadSummary(count: 60, firstMessageId: 1);
    control.historyPages = {
      null: [
        for (var i = 11; i <= 60; i++)
          _deletionMessage(id: i, sender: 'caregiver-a'),
      ],
      11: [
        for (var i = 1; i <= 10; i++)
          _deletionMessage(id: i, sender: 'caregiver-a'),
      ],
    };
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final list = tester.widget<ListView>(
      find.byKey(const Key('chat-message-list')),
    );
    for (
      var attempt = 0;
      attempt < 8 &&
          find.byKey(const Key('chat-load-older')).evaluate().isEmpty;
      attempt++
    ) {
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const Key('chat-load-older')));
    await tester.tap(find.byKey(const Key('chat-load-older')));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 8 &&
          find.byKey(const Key('chat-unread-divider')).evaluate().isEmpty;
      attempt++
    ) {
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(find.text('여기까지 읽음'), findsOneWidget);
    expect(control.historyBoundaries, contains(11));
    expect(find.byKey(const Key('chat-load-older')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  for (final hospitals in [false, true]) {
    for (final confirm in [false, true]) {
      // 함수이름: care share double dismissal keeps chat: hospital=$hospitals confirm=$confirm
      // 함수역할:
      // - 병원·약국 공유 확인창에서 확인 또는 취소를 연속 입력해도 채팅 경로와 초안을 보존하며, 확인한 경우에만 한 번 전송하는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets(
        'care share double dismissal keeps chat: hospital=$hospitals confirm=$confirm',
        (tester) async {
          final control = _RetryChatControl(failFirstSend: false);
          final realtime = _FakeRealtimeService();
          addTearDown(control.dispose);
          addTearDown(realtime.dispose);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('previous screen')),
            ),
          );
          unawaited(
            navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => LinkedChatUI(
                  linkId: 17,
                  currentUserHash: 'patient-a',
                  patientHash: 'patient-a',
                  peerName: '보호자 테스트',
                  control: control,
                  realtimeService: realtime,
                  careSelectorBuilder: (_) => Scaffold(
                    body: Builder(
                      builder: (context) => FilledButton(
                        key: const Key('pick-double-tap-care'),
                        onPressed: () => Navigator.pop(
                          context,
                          NearbyCareSelection(
                            phoneVerified: false,
                            place: NearbyCarePlace.fromJson({
                              if (hospitals)
                                'hospital_id': 'shared-place'
                              else
                                'pharmacy_id': 'shared-place',
                              'name': '시험 장소',
                              'address': '서울',
                              'latitude': 37.55,
                              'longitude': 126.92,
                            }),
                            scheduleDate: DateTime(2026, 10, 5),
                          ),
                        ),
                        child: const Text('선택'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '유지할 초안');
          await tester.tap(find.byKey(const ValueKey('chatActions')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey(hospitals ? 'chat-action-2' : 'chat-action-3')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pick-double-tap-care')));
          await tester.pumpAndSettle();
          final dismiss = confirm
              ? find.byKey(const ValueKey('confirmCareShare'))
              : find.text('취소');
          // 확인창이 닫히는 동안의 연속 입력도 채팅 화면을 닫으면 안 된다.
          await tester.tap(dismiss);
          await tester.tap(dismiss, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.byType(LinkedChatUI), findsOneWidget);
          expect(navigator.currentState!.canPop(), isTrue);
          expect(control.sendAttempts, confirm ? 1 : 0);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '유지할 초안',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  // 함수이름: care share rapid opening creates only one option sheet
  // 함수역할:
  // - 공유 메뉴를 빠르게 두 번 열어도 선택 시트는 하나만 생성되고 메시지는 전송되지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('care share rapid opening creates only one option sheet', (
    tester,
  ) async {
    final control = _RetryChatControl(failFirstSend: false);
    final realtime = _FakeRealtimeService();
    addTearDown(control.dispose);
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      MaterialApp(
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
    final selector = find.byKey(const ValueKey('chatActions'));
    await tester.tap(selector);
    await tester.tap(selector, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
    expect(control.sendAttempts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [
    (hospitals: true, phoneVerified: false),
    (hospitals: false, phoneVerified: false),
    (hospitals: false, phoneVerified: true),
  ]) {
    // 함수이름: care sharing confirms provider context and retries the same request: $mode
    // 함수역할:
    // - 병원·약국·전화 확인 약국의 공유 문맥을 확인 후 전송하고, 일반 메시지 실패가 끼어도 공유 재시도는 원래 요청 ID·장소·병원 날짜를 유지하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets(
      'care sharing confirms provider context and retries the same request: $mode',
      (tester) async {
        final control = _RetryChatControl();
        final realtime = _FakeRealtimeService();
        final selectedModes = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              peerName: '보호자 테스트',
              control: control,
              realtimeService: realtime,
              careSelectorBuilder: (hospitals) {
                selectedModes.add(hospitals);
                return Scaffold(
                  body: Builder(
                    builder: (context) => FilledButton(
                      key: const Key('pick-test-hospital'),
                      onPressed: () => Navigator.pop(
                        context,
                        NearbyCareSelection(
                          place: NearbyCarePlace.fromJson({
                            if (mode.hospitals)
                              'hospital_id': 'shared-place'
                            else
                              'pharmacy_id': 'shared-place',
                            'name': '공유병원',
                            'address': '서울',
                            'latitude': 37.55,
                            'longitude': 126.92,
                          }),
                          phoneVerified: mode.phoneVerified,
                          scheduleDate: DateTime(2026, 10, 5),
                        ),
                      ),
                      child: const Text('병원 선택'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final confirm in [false, true]) {
          await tester.tap(find.byKey(const ValueKey('chatActions')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              ValueKey(mode.hospitals ? 'chat-action-2' : 'chat-action-3'),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pick-test-hospital')));
          await tester.pumpAndSettle();
          expect(find.text('받는 사람: 보호자 테스트'), findsOneWidget);
          expect(
            find.text('진료 날짜: 2026년 10월 5일'),
            mode.hospitals ? findsOneWidget : findsNothing,
          );
          await tester.tap(
            confirm
                ? find.byKey(const ValueKey('confirmCareShare'))
                : find.text('취소'),
          );
          await tester.pumpAndSettle();
          expect(control.sendAttempts, confirm ? 1 : 0);
        }
        // 일반 메시지 실패가 끼어도 먼저 실패한 병원 공유 ID를 잃지 않는다.
        control.failSends = true;
        await tester.enterText(find.byType(TextField), '다른 메시지');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chatSendButton')));
        await tester.pumpAndSettle();
        control.failSends = false;
        await tester.tap(find.byKey(const ValueKey('retryCareShare')));
        await tester.pumpAndSettle();
        expect(selectedModes, [mode.hospitals, mode.hospitals]);
        final expectedKind = mode.hospitals
            ? ChatMessageKind.hospitalShare
            : mode.phoneVerified
            ? ChatMessageKind.pharmacyPhoneVerified
            : ChatMessageKind.pharmacyShare;
        expect(control.messageKinds, [
          expectedKind,
          ChatMessageKind.text,
          expectedKind,
        ]);
        expect(
          control.hospitalIds,
          mode.hospitals
              ? ['shared-place', null, 'shared-place']
              : [null, null, null],
        );
        expect(
          control.pharmacyIds,
          mode.hospitals
              ? [null, null, null]
              : ['shared-place', null, 'shared-place'],
        );
        expect(
          control.hospitalDates,
          mode.hospitals
              ? ['2026-10-05', null, '2026-10-05']
              : [null, null, null],
        );
        expect(control.clientMessageIds[0], control.clientMessageIds[2]);
        expect(control.clientMessageIds[0], isNot(control.clientMessageIds[1]));
        expect(find.byKey(const ValueKey('retryCareShare')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      },
    );
  }

  // Function Name: medication thumbnails decode at display size
  // Description:
  // - Checks that a medication thumbnail is displayed at 46 logical pixels and uses ResizeImage with a decode width scaled to the device pixel ratio.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('medication thumbnails decode at display size', (tester) async {
    const medication = ChatMedicationContext(
      medicationId: 91,
      medicationName: '테스트정',
      dosagePerTime: '1정',
      imageUrl: 'https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/test',
    );
    final control = _RetryChatControl(
      failFirstSend: false,
      historyMessages: [
        ChatMessage(
          messageId: 10,
          linkId: 17,
          senderHash: 'caregiver-a',
          clientMessageId: 'thumbnail_message_10',
          body: '이 약을 확인해주세요.',
          createdAt: DateTime.now().toUtc(),
          medicationContext: medication,
          medicationContexts: const [medication],
        ),
      ],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.width, 46);
    expect(
      image.image,
      isA<ResizeImage>().having(
        (resized) => resized.width,
        'width',
        (46 * tester.view.devicePixelRatio).round(),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  for (final kind in [
    ChatMessageKind.medicationShortage,
    ChatMessageKind.medicationDiscomfort,
  ]) {
    // 함수이름: $kind offers hospital search without automatic navigation
    // 함수역할:
    // - 약 부족·복용 불편 메시지는 병원 찾기를 제안하되 자동 이동하지 않고, 사용자가 누른 경우에만 병원 선택 화면을 열며 메시지를 추가 전송하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('$kind offers hospital search without automatic navigation', (
      tester,
    ) async {
      final control = _RetryChatControl(
        failFirstSend: false,
        historyMessages: [
          ChatMessage(
            messageId: 10,
            linkId: 17,
            senderHash: 'caregiver-a',
            clientMessageId: 'care_message_10',
            body: '테스트 복약 메시지',
            createdAt: DateTime.now().toUtc(),
            messageKind: kind,
            showSafetyGuidance: kind == ChatMessageKind.medicationDiscomfort,
            medicationContexts: const [
              ChatMedicationContext(medicationId: 91, medicationName: '테스트정'),
              ChatMedicationContext(medicationId: 92, medicationName: '저녁정'),
            ],
          ),
        ],
      );
      final realtime = _FakeRealtimeService();
      final modes = <bool>[];
      await tester.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            control: control,
            realtimeService: realtime,
            careSelectorBuilder: (hospital) {
              modes.add(hospital);
              return const Scaffold(body: Text('선택 화면'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(modes, isEmpty);
      expect(find.text('병원 찾기'), findsOneWidget);
      expect(
        find.text(
          kind == ChatMessageKind.medicationShortage ? '약 부족 알림' : '복용 불편 알림',
        ),
        findsOneWidget,
      );
      if (kind == ChatMessageKind.medicationShortage) {
        expect(find.text('약국 찾기'), findsOneWidget);
      }
      await tester.ensureVisible(find.text('병원 찾기'));
      await tester.tap(find.text('병원 찾기'));
      await tester.pumpAndSettle();
      expect(modes, [true]);
      expect(control.sendAttempts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    });
  }

  for (final mine in [true, false]) {
    for (final language in ['ko', 'en']) {
      // 함수이름: safety guidance separates hospital action $mine/$language
      // 함수역할:
      // - 본인·상대의 복용 불편 카드에서 한국어·영어 안전 안내와 병원 찾기 버튼 사이에 큰 글씨에서도 최소 12의 간격을 유지하는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('safety guidance separates hospital action $mine/$language', (
        tester,
      ) async {
        final control = _RetryChatControl(
          historyMessages: [
            ChatMessage(
              messageId: 12,
              linkId: 17,
              senderHash: mine ? 'patient-a' : 'caregiver-a',
              clientMessageId: 'discomfort-layout',
              body: 'Test discomfort',
              createdAt: DateTime.now().toUtc(),
              messageKind: ChatMessageKind.medicationDiscomfort,
              showSafetyGuidance: true,
            ),
          ],
        );
        final realtime = _FakeRealtimeService();
        await tester.binding.setSurfaceSize(const Size(360, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: LinkedChatUI(
                linkId: 17,
                currentUserHash: 'patient-a',
                patientHash: 'patient-a',
                userSetting: UserSetting(language: language),
                control: control,
                realtimeService: realtime,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final notice = find.byKey(
          const ValueKey('chatDiscomfortSafetyGuidance'),
        );
        expect(notice, findsOneWidget);
        expect(
          find.text(language == 'ko' ? '복용 불편 알림' : 'Medication discomfort'),
          findsOneWidget,
        );
        final button = find.widgetWithText(
          OutlinedButton,
          language == 'ko' ? '병원 찾기' : 'Find hospitals',
        );
        expect(
          tester.getRect(button).top - tester.getRect(notice).bottom,
          greaterThanOrEqualTo(12),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await realtime.dispose();
        control.dispose();
      });
    }
  }

  for (final language in ['ko', 'en']) {
    // 함수이름: hospital card fits narrow large-text chat in $language
    // 함수역할:
    // - 영업 스냅샷이 없는 병원 공유를 좁은 큰 글씨 화면에서 운영 확인 필요로 표시하고, 예약 확정 문구 없이 주소·상태·전화·길찾기를 배치하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('hospital card fits narrow large-text chat in $language', (
      tester,
    ) async {
      final control = _RetryChatControl(
        historyMessages: [
          ChatMessage(
            messageId: 11,
            linkId: 17,
            senderHash: 'caregiver-a',
            clientMessageId: 'hospital_message_11',
            body: 'Shared hospital',
            createdAt: DateTime.now().toUtc(),
            messageKind: ChatMessageKind.hospitalShare,
            hospitalContext: ChatHospitalContext(
              hospitalId: 'A123',
              name: '메드버디병원',
              address: '서울특별시 마포구',
              telephone: '02-000-0000',
              latitude: 37.55,
              longitude: 126.92,
              departments: const ['내과', '이비인후과'],
              scheduleDate: DateTime(2026, 10, 5),
              sourceUpdatedAt: DateTime.utc(2026, 9, 28, 1),
            ),
          ),
        ],
      );
      final realtime = _FakeRealtimeService();
      await tester.binding.setSurfaceSize(const Size(360, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 1000),
              textScaler: TextScaler.linear(1.6),
            ),
            child: LinkedChatUI(
              linkId: 17,
              currentUserHash: 'patient-a',
              patientHash: 'patient-a',
              userSetting: UserSetting(language: language),
              control: control,
              realtimeService: realtime,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final status = language == 'ko' ? '운영 확인 필요' : 'Hours unconfirmed';
      expect(find.text(status), findsOneWidget);
      expect(find.textContaining('정보 확인:'), findsNothing);
      expect(find.textContaining('예약이 확정'), findsNothing);
      // 공유된 병원 정보는 메시지 본문과 같은 크기로 읽힌다.
      for (final value in [status, '서울특별시 마포구']) {
        expect(tester.widget<Text>(find.text(value)).style!.fontSize, 15);
      }
      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      expect(find.byIcon(Icons.directions_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    });
  }
  // 함수이름: repeated reconnect attempts do not postpone fallback polling
  // 함수역할:
  // - 재연결 상태 이벤트를 5초마다 반복해도 보조 이력 조회 타이머가 계속 미뤄지지 않고 15초 안에 한 번 조회하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('repeated reconnect attempts do not postpone fallback polling', (
    tester,
  ) async {
    final control = _RetryChatControl();
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final initial = control.historyRequests;
    for (var attempt = 0; attempt < 3; attempt++) {
      realtime._states.add(LinkedChatConnectionState.reconnecting);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    }
    await tester.pumpAndSettle();
    expect(control.historyRequests, initial + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  // 함수이름: failed catch-up retries even after websocket connected
  // 함수역할:
  // - 소켓 연결 후 이력 보완 조회가 실패하면 보조 조회로 재시도하며, 성공한 뒤에는 추가 주기 조회를 중단하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('failed catch-up retries even after websocket connected', (
    tester,
  ) async {
    final control = _RetryChatControl();
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    control.failHistory = true;
    realtime._states.add(LinkedChatConnectionState.connected);
    await tester.pumpAndSettle();
    final failed = control.historyRequests;
    control.failHistory = false;
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(control.historyRequests, failed + 1);
    await tester.pump(const Duration(seconds: 36));
    expect(control.historyRequests, failed + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });
  // 함수이름: reconnection fills a gap larger than the recent history page
  // 함수역할:
  // - 재연결 시 기존 메시지와 최신 페이지 사이가 한 페이지보다 넓으면 최신 요청에 이어 커서 51의 이전 페이지까지 조회하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('reconnection fills a gap larger than the recent history page', (
    tester,
  ) async {
    final control = _RetryChatControl(
      historyMessages: [_deletionMessage(id: 1)],
    );
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    control.historyBoundaries.clear();
    control.historyPages = {
      null: [for (var i = 100; i >= 51; i--) _deletionMessage(id: i)],
      51: [for (var i = 50; i >= 1; i--) _deletionMessage(id: i)],
    };
    realtime._states.add(LinkedChatConnectionState.connected);
    await tester.pumpAndSettle();
    expect(control.historyBoundaries, [null, 51]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });
  // 함수이름: realtime polling stops while connected or backgrounded
  // 함수역할:
  // - 연결 중에는 주기 조회를 하지 않고 재연결 중에도 진행 중인 조회를 중복하지 않으며, 앱 일시정지 시 중단하고 복귀 후 한 번 보완하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('realtime polling stops while connected or backgrounded', (
    tester,
  ) async {
    final control = _RetryChatControl();
    final realtime = _FakeRealtimeService();
    await tester.pumpWidget(
      MaterialApp(
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
    final initial = control.historyRequests;
    await tester.pump(const Duration(seconds: 36));
    expect(control.historyRequests, initial);
    realtime._states.add(LinkedChatConnectionState.reconnecting);
    await tester.pump();
    control.historyGate = Completer<List<ChatMessage>>();
    await tester.pump(const Duration(seconds: 12));
    expect(control.historyRequests, initial + 1);
    await tester.pump(const Duration(seconds: 36));
    expect(control.historyRequests, initial + 1);
    control.historyGate!.complete([]);
    await tester.pumpAndSettle();
    control.historyGate = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 36));
    expect(control.historyRequests, initial + 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(control.historyRequests, greaterThan(initial + 1));
    final resumed = control.historyRequests;
    await tester.pump(const Duration(seconds: 36));
    expect(control.historyRequests, resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });
  // 아래 복용 확인 테스트는 운영과 같은 경로를 쓴다: main.dart처럼 실제 DoseSyncService와
  // 전송 대기열(DoseOutboxStore)을 ViewModel에 붙이고, 대기열에 저장된 요청으로 결과를 확인한다.

  // Function Name: selected evening dose goes straight to the offline queue
  // Description:
  // - Checks that an explicitly selected evening dose is persisted once in the offline queue with its date, link, and medication; no chat endpoint is called and the unselected morning remains incomplete.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('selected evening dose goes straight to the offline queue', (
    tester,
  ) async {
    final harness = await _attachChatDoseSync();
    final control = _TakenChatControl(multiSlotMedication: true);
    final realtime = _FakeRealtimeService();
    await _pumpPatientChat(
      tester,
      harness,
      control: control,
      realtime: realtime,
    );
    await _selectDoseSlots(tester, ['evening']);
    await _tapTaken(tester);
    expect(find.byType(BottomSheet), findsNothing);
    final operation = harness.queued.single;
    expect(operation['medication_ids'], [91]);
    expect(operation['slot_key'], 'evening');
    expect(operation['schedule_date'], '2026-09-21');
    expect(operation['link_id'], 17);
    expect(operation['completed'], isTrue);
    expect(operation['medication_names'], ['테스트정']);
    // The outbox is the only write path; neither chat endpoint sends a duplicate.
    expect(control.takenRequestIds, isEmpty);
    expect(control.sendAttempts, 0);
    // Offline persistence completes evening without changing the unselected morning.
    expect(await harness.pending(), hasLength(1));
    final projected = harness.service.schedules.single;
    expect(projected.isSlotCompleted('evening'), isTrue);
    expect(projected.isSlotCompleted('morning'), isFalse);
    expect(find.text('복용 기록 1건 전송 대기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeChat(tester, harness, control: control, realtime: realtime);
  });

  // Function Name: taken is queued once and updates the shared schedule
  // Description:
  // - Checks that rapid repeated taken replies queue only one morning dose, update the shared schedule without completing evening, and clear the recorded selection without a second prompt.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('taken is queued once and updates the shared schedule', (
    tester,
  ) async {
    final harness = await _attachChatDoseSync();
    final control = _TakenChatControl(multiSlotMedication: true);
    final realtime = _FakeRealtimeService();
    await _pumpPatientChat(
      tester,
      harness,
      control: control,
      realtime: realtime,
    );
    await _selectDoseSlots(tester, ['morning']);
    final taken = find.widgetWithText(ActionChip, '먹었어요');
    await tester.ensureVisible(taken);
    // Repeat the tap before a new frame can reflect the first write.
    await tester.tap(taken);
    await tester.tap(taken, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(harness.queued, hasLength(1));
    expect(harness.queued.single['slot_key'], 'morning');
    expect(harness.queued.single['medication_ids'], [91]);
    expect(control.takenRequestIds, isEmpty);
    expect(control.sendAttempts, 0);
    // The schedule screen observes the same updated shared schedule.
    final shared = harness.viewModel.todayMedicationScheduleList.single;
    expect(shared.isSlotCompleted('morning'), isTrue);
    expect(shared.isSlotCompleted('evening'), isFalse);
    // Clearing the saved selection prevents another submission of the same dose.
    expect(find.widgetWithText(ActionChip, '먹었어요'), findsNothing);
    expect(tester.takeException(), isNull);
    await _closeChat(tester, harness, control: control, realtime: realtime);
  });

  // 함수이름: without an outbox the chat endpoint records once and updates the shared schedule
  // 함수역할:
  // - 전송 대기열이 없으면 저장 대기 중 반복 입력도 채팅 복용 확인 API 한 번으로 제한하고, 선택 약만 기록한 응답을 공용 일정과 확인 메시지에 반영하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'without an outbox the chat endpoint records once and updates the shared schedule',
    (tester) async {
      final gate = Completer<void>();
      final control = _TakenChatControl(saveGate: gate);
      final realtime = _FakeRealtimeService();
      final viewModel = MedBuddyViewModel(
        patientHash: 'patient-a',
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
              realtimeService: realtime,
              initialMedicationContexts: const [
                ChatMedicationContext(
                  medicationId: 91,
                  medicationName: '테스트정',
                  dosagePerTime: '1정',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chatActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-action-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('scheduleMedicationSelectionOption_morning_91'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('scheduleMedicationSelectionConfirm')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ActionChip, '먹었어요'));
      await tester.tap(find.widgetWithText(ActionChip, '먹었어요'));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('선택하지 않은 약'), findsNothing);
      expect(control.takenRequestIds, hasLength(1));
      await tester.tap(find.widgetWithText(ActionChip, '먹었어요'));
      await tester.pump();
      expect(control.takenRequestIds, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(control.takenSlotKeys, ['morning']);
      expect(control.takenMedicationIds, [
        [91],
      ]);
      expect(control.sendAttempts, 0);
      expect(
        viewModel.todayMedicationScheduleList.single.isSlotCompleted('morning'),
        isTrue,
      );
      expect(find.text('아침 테스트정 복용을 기록했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  // Function Name: failed dose save keeps the selection and the retry queues it once at large text size
  // Description:
  // - Uses a rejecting database trigger to verify that failed local dose storage retains the selection and shows an error; retrying after recovery queues exactly one dose without chat API calls, even at large text size.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets(
    'failed dose save keeps the selection and the retry queues it once at large text size',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _attachChatDoseSync();
      final control = _TakenChatControl(multiSlotMedication: true);
      final realtime = _FakeRealtimeService();
      await _pumpPatientChat(
        tester,
        harness,
        control: control,
        realtime: realtime,
        mediaQuery: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.6),
        ),
      );
      await _selectDoseSlots(tester, ['morning']);
      // A database trigger reproduces a rejected write, such as a full disk.
      await harness.store.db.execute(
        'CREATE TRIGGER reject_insert BEFORE INSERT ON operations '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await _tapTaken(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(harness.queued, isEmpty);
      expect(
        find.text('복용 기록의 저장을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.'),
        findsOneWidget,
      );

      await harness.store.db.execute('DROP TRIGGER reject_insert');
      await _tapTaken(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(harness.queued, hasLength(1));
      expect(harness.queued.single['slot_key'], 'morning');
      expect(await harness.pending(), hasLength(1));
      expect(
        find.text('복용 기록의 저장을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.'),
        findsNothing,
      );
      expect(control.takenRequestIds, isEmpty);
      expect(control.sendAttempts, 0);
      await _closeChat(tester, harness, control: control, realtime: realtime);
    },
  );

  for (final mode in ['morning', 'evening', 'both', 'partial', 'changed']) {
    // 함수이름: selected dose slots are preserved without another prompt: $mode
    // 함수역할:
    // - 약 선택을 다시 열어도 정확한 시간대 선택을 유지하며, 일정 변경 시 저장을 막고 일부 저장 실패 후에는 미완료 시간대만 재시도해 중복 기록하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('selected dose slots are preserved without another prompt: $mode', (
      tester,
    ) async {
      final harness = await _attachChatDoseSync();
      final control = _TakenChatControl(multiSlotMedication: true);
      final realtime = _FakeRealtimeService();
      await _pumpPatientChat(
        tester,
        harness,
        control: control,
        realtime: realtime,
      );
      final slots = mode == 'both' || mode == 'partial'
          ? ['morning', 'evening']
          : [mode == 'evening' ? 'evening' : 'morning'];
      await _selectDoseSlots(tester, slots);

      // Reopening must restore the exact dose choices, not all slots of that drug.
      await tester.tap(find.byKey(const ValueKey('chatActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-action-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<KeepWordsText>(
              find.byKey(const Key('schedule-medication-selection-count')),
            )
            .data,
        '${slots.length}개 선택',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      if (mode == 'changed') {
        // 선택한 뒤 오늘 일정에서 아침 복용이 빠졌다(처방 변경이 다른 화면에서 반영된 경우).
        await harness.seedSchedules(const [
          MedicationSchedule(
            medicationID: '91',
            medicationName: '테스트정',
            dosage: '1정',
            intakeTime: '1회',
            medicationTime: 1,
            scheduleSlotKeys: ['evening'],
          ),
        ]);
      }
      if (mode == 'partial') {
        // 첫 시간대(아침)는 저장되고 두 번째(저녁) 쓰기만 거부된다.
        await harness.store.db.execute(
          'CREATE TRIGGER reject_second BEFORE INSERT ON operations '
          'WHEN (SELECT COUNT(*) FROM operations) >= 1 '
          "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
        );
      }
      await _tapTaken(tester);
      expect(find.text('복용한 시간대'), findsNothing);
      expect(find.text('기록하고 보내기'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      final queuedSlots = [
        for (final operation in harness.queued) operation['slot_key'],
      ];
      if (mode == 'changed') {
        expect(queuedSlots, isEmpty);
        expect(find.text('선택한 복약 일정이 변경되었습니다. 약을 다시 선택해주세요.'), findsOneWidget);
      } else if (mode == 'partial') {
        expect(queuedSlots, ['morning']);
        expect(
          find.text('복용 기록의 저장을 확인하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.'),
          findsOneWidget,
        );
      } else {
        expect(queuedSlots, slots);
      }
      for (final operation in harness.queued) {
        expect(operation['medication_ids'], [91]);
        expect(operation['schedule_date'], '2026-09-21');
        expect(operation['link_id'], 17);
      }
      if (mode == 'partial') {
        // The successful morning must not be stored again; only the evening is retried.
        await harness.store.db.execute('DROP TRIGGER reject_second');
        await _tapTaken(tester);
        expect(
          [for (final operation in harness.queued) operation['slot_key']],
          ['morning', 'evening'],
        );
        expect(await harness.pending(), hasLength(2));
        expect(find.widgetWithText(ActionChip, '먹었어요'), findsNothing);
      }
      expect(control.takenRequestIds, isEmpty);
      expect(control.sendAttempts, 0);
      expect(tester.takeException(), isNull);
      await _closeChat(tester, harness, control: control, realtime: realtime);
    });
  }

  // 함수이름: selected private deletion survives stale polling and preserves new messages
  // 함수역할:
  // - 삭제 확인 취소는 요청을 만들지 않고 개인 삭제는 선택한 메시지만 숨기며, 다른 메시지와 삭제 상태가 시간 경과 후에도 유지되는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // Function Name: tapping a message toggles its selection while selecting
  // Description:
  // - Checks that normal message taps do not enter selection mode, while taps in selection mode toggle only the targeted message checkbox.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('tapping a message toggles its selection while selecting', (
    tester,
  ) async {
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
    // Function Name: selected
    // Description:
    // - Reads the checkbox state of the specified message using the captured widget tester.
    // Parameters:
    // - id (int): message identifier embedded in the selection checkbox key.
    // Returns:
    // - bool; the non-null checked value of the matching Checkbox.
    bool selected(int id) => tester
        .widget<Checkbox>(find.byKey(ValueKey('selectChatMessage-$id')))
        .value!;

    await tester.tap(find.text('Message 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selectChatMessage-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('deleteChatMessages')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message 1'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(selected(1), isTrue);
    expect(selected(2), isFalse);
    await tester.tap(find.text('Message 1'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(selected(1), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await realtime.dispose();
    control.dispose();
  });

  // 함수이름: a chat whose link was removed replaces the composer with a notice
  // 함수역할:
  // - 재연결 이력 조회가 연동 해제로 404를 반환하면 기존 메시지는 유지하면서 입력창을 연동 해제 안내로 바꾸는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'a chat whose link was removed replaces the composer with a notice',
    (tester) async {
      final control = _RemovableLinkChatControl(
        historyMessages: [_deletionMessage()],
      );
      final realtime = _FakeRealtimeService();
      await tester.pumpWidget(
        MaterialApp(
          home: LinkedChatUI(
            linkId: 17,
            currentUserHash: 'patient-a',
            patientHash: 'patient-a',
            userSetting: const UserSetting(language: 'ko'),
            control: control,
            realtimeService: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chatSendButton')), findsOneWidget);
      expect(find.byKey(const Key('chat-link-unavailable')), findsNothing);

      // 연결 상태가 다시 알려지면 기록을 따라잡는 조회가 일어나고, 그 조회가 404로 거절된다.
      control.linkRemoved = true;
      realtime._states.add(LinkedChatConnectionState.connected);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-link-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('chatSendButton')), findsNothing);
      expect(find.text('연동 해제됨'), findsOneWidget);
      expect(find.text('Message 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await realtime.dispose();
      control.dispose();
    },
  );

  // 함수이름: shared deletion removes body and prevents delayed events restoring it
  // 함수역할:
  // - 전체 삭제한 메시지는 삭제 안내로 대체되고, 같은 ID의 늦은 실시간 메시지 이벤트가 원문을 복구하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
      await tester.tap(find.byKey(const Key('chat-select-message')));
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
    // 함수이름: old or incoming selection offers private deletion only: $sender
    // 함수역할:
    // - 25시간 지난 본인 메시지와 상대 메시지는 개인 삭제만 제안하며, 큰 글씨에서 삭제 요청이 실패하면 원문을 유지하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
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
        await tester.tap(find.byKey(const Key('chat-select-message')));
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

  // 함수이름: 안내는 자동으로 사라지고 약 선택 없이 일반 메시지를 보낸다
  // 함수역할:
  // - 초기 약 선택 안내는 4초 후 사라지고 입력은 계속 허용되며, 약을 선택하지 않아도 약 ID 없는 일반 메시지를 한 번 보낼 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

  // 함수이름: 큰 글씨에서도 메시지 실패 재시도는 같은 요청 식별자를 사용한다
  // 함수역할:
  // - 좁은 큰 글씨 화면에서 전송 실패 시 약 선택과 초안을 유지하고 같은 요청 ID로 재전송하며, 성공 메시지의 약을 눌러 상세 정보를 조회할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
    await tester.tap(find.byKey(const ValueKey('chatActions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-action-0')));
    await tester.pumpAndSettle();
    expect(find.text('대화할 약 선택'), findsOneWidget);
    expect(find.text('아침'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('scheduleMedicationSelectionOption_morning_91'),
      ),
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

  for (final language in ['ko', 'en']) {
    // Function Name: caregiver selects only requestable medication times: $language
    // Description:
    // - Checks that caregivers see only requestable medication times in either language and send a morning slot-check request with the localized prompt, not a generic progress view.
    // Parameters:
    // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    testWidgets(
      'caregiver selects only requestable medication times: $language',
      (tester) async {
        final isEnglish = language == 'en';
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
            ChatScheduleContext(
              slotKey: 'evening',
              alarmTime: '18:00',
              alarmEnabled: true,
              completedCount: 0,
              totalCount: 1,
              canRequestCheck: false,
              medications: [],
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
              userSetting: UserSetting(language: language),
              control: control,
              realtimeService: realtimeService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('chatActions')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ListTile>(find.byKey(const ValueKey('chat-action-1')))
              .enabled,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('chat-action-1')));
        await tester.pumpAndSettle();
        expect(
          find.text(isEnglish ? "Today's medication times" : '오늘의 복약 시간대'),
          findsOneWidget,
        );
        expect(
          find.text(
            isEnglish
                ? 'Choose a time to ask the patient to check their medication.'
                : '확인이 필요한 시간대를 선택해 환자에게 알려주세요.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            isEnglish
                ? 'Review progress for each medication time.'
                : '시간대별 약과 복용 진행률을 확인할 수 있습니다.',
          ),
          findsNothing,
        );
        expect(
          find.text(isEnglish ? 'Evening 18:00' : '저녁 18:00'),
          findsNothing,
        );
        expect(
          find.text(isEnglish ? 'Morning 08:00' : '아침 08:00'),
          findsOneWidget,
        );

        await tester.tap(find.text(isEnglish ? 'Morning 08:00' : '아침 08:00'));
        await tester.pumpAndSettle();

        expect(control.messageKinds, [ChatMessageKind.slotCheckRequest]);
        expect(control.slotKeys, ['morning']);
        expect(
          find.text(
            isEnglish
                ? 'Please check your morning medication.'
                : '아침 복약을 확인해주세요.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await realtimeService.dispose();
        control.dispose();
      },
    );
  }

  // 함수이름: 열린 기능 메뉴는 늦게 도착한 약 정보를 반영한다
  // 함수역할:
  // - 저장 약 조회가 늦어도 검색 진입은 계속 허용하고, 열린 기능 메뉴가 조회 완료 후 오래된 로딩·빈 목록 안내를 남기지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('열린 기능 메뉴는 늦게 도착한 약 정보를 반영한다', (tester) async {
    final control = _GatedMedicationChatControl();
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
    await tester.tap(find.byKey(const ValueKey('chatActions')));
    await tester.pumpAndSettle();
    final medication = find.byKey(const ValueKey('chat-action-0'));
    // 저장 약 조회와 별개인 약품 검색 진입은 계속 허용한다.
    expect(tester.widget<ListTile>(medication).enabled, isTrue);

    control.gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(medication).enabled, isTrue);
    expect(find.text('복용 중인 약이 없습니다'), findsNothing);
    expect(find.text('복용 중인 약을 불러오는 중입니다'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: 기능 메뉴는 복용 중인 약이 없어도 검색을 허용한다
  // 함수역할:
  // - 복용 중인 저장 약이 없어도 대화할 약 선택 메뉴를 비활성화하지 않고 약품 검색 화면에 진입할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('기능 메뉴는 복용 중인 약이 없어도 검색을 허용한다', (tester) async {
    final control = _NoMedicationChatControl();
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
    await tester.tap(find.byKey(const ValueKey('chatActions')));
    await tester.pumpAndSettle();
    final medication = tester.widget<ListTile>(
      find.byKey(const ValueKey('chat-action-0')),
    );
    expect(medication.enabled, isTrue);
    expect(find.text('대화할 약 선택'), findsOneWidget);
    expect(find.text('복용 중인 약이 없습니다'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat-action-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-search-medication')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  for (final language in ['ko', 'en']) {
    for (final scenario in [
      (user: 'patient-a', canRequest: false),
      (user: 'patient-a', canRequest: true),
      (user: 'caregiver-a', canRequest: false),
    ]) {
      // Function Name: 확인 요청 숨김 $language $scenario
      // Description:
      // - Checks that patients have no check-request action and caregivers without requestable times see a disabled action with an explanation; medication, hospital, and pharmacy actions remain available without sending messages.
      // Parameters:
      // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
      // Returns:
      // - Future<void>; completes after the asynchronous assertions.
      testWidgets('확인 요청 숨김 $language $scenario', (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final control = _RetryChatControl(
          failFirstSend: false,
          scheduleContexts: [
            ChatScheduleContext(
              slotKey: 'morning',
              alarmTime: '08:00',
              alarmEnabled: true,
              completedCount: 0,
              totalCount: 1,
              canRequestCheck: scenario.canRequest,
              medications: const [],
            ),
          ],
        );
        final realtimeService = _FakeRealtimeService();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 740),
                textScaler: TextScaler.linear(1.3),
              ),
              child: LinkedChatUI(
                linkId: 17,
                currentUserHash: scenario.user,
                patientHash: 'patient-a',
                userSetting: UserSetting(language: language),
                control: control,
                realtimeService: realtimeService,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final medication = find.byKey(const ValueKey('chatActions'));
        expect(tester.widget<IconButton>(medication).onPressed, isNotNull);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(TextField)).dx -
              tester.getTopRight(medication).dx,
          8,
        );
        await tester.tap(medication);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-action-0')), findsOneWidget);
        if (scenario.user == 'patient-a') {
          expect(find.byKey(const ValueKey('chat-action-1')), findsNothing);
        } else {
          expect(
            tester
                .widget<ListTile>(find.byKey(const ValueKey('chat-action-1')))
                .enabled,
            isFalse,
          );
          expect(
            find.text(
              language == 'en'
                  ? 'No medication times to check today'
                  : '오늘 확인을 요청할 시간대가 없습니다',
            ),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('chat-action-2')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-action-3')), findsOneWidget);
        expect(control.sendAttempts, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await realtimeService.dispose();
        control.dispose();
      });
    }
  }

  // 함수이름: 환자는 여러 약을 선택해 환자용 빠른 답장을 보낸다
  // 함수역할:
  // - 환자가 아침·저녁 약 두 건을 선택하면 환자용 빠른 답장을 제공하고, 복용 불가 답장은 두 약과 대표 약을 담은 시간대 없는 일반 메시지로 전송하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

    await tester.tap(find.byKey(const ValueKey('chatActions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-action-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('scheduleMedicationSelectionOption_morning_91'),
      ),
    );
    await tester.pumpAndSettle();
    final secondMedication = find.byKey(
      const ValueKey('scheduleMedicationSelectionOption_evening_92'),
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

    final takenReply = find.widgetWithText(ActionChip, '지금은 못 먹어요');
    await tester.ensureVisible(takenReply);
    await tester.tap(takenReply);
    await tester.pumpAndSettle();

    expect(control.primaryMedicationIds, [91]);
    expect(control.medicationIdGroups, [
      [91, 92],
    ]);
    expect(control.messageKinds, [ChatMessageKind.text]);
    expect(control.slotKeys, [null]);
    expect(find.text('테스트정, 저녁정 지금은 못 먹어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });

  // 함수이름: 보호자는 환자 문구 대신 보호자용 빠른 답장을 사용한다
  // 함수역할:
  // - 보호자에게 환자용 복용 응답 대신 질문형 빠른 답장을 제공하며, 선택 약과 환자 이름을 포함한 확인 질문을 전송하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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

    await tester.tap(find.byKey(const ValueKey('chatActions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-action-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('scheduleMedicationSelectionOption_morning_91'),
      ),
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

  for (final (currentUser, kind) in [
    ('patient-a', ChatMessageKind.slotCompletion),
    ('caregiver-a', ChatMessageKind.slotCompletion),
    ('patient-a', ChatMessageKind.slotCheckRequest),
  ]) {
    // 함수이름: $currentUser $kind: 채팅 카드에서 해당 일정으로 이동한다
    // 함수역할:
    // - 환자·보호자 모두 복약 확인 요청 카드는 일정 화면으로, 복용 완료 카드는 해당 환자·날짜의 읽기 전용 이력으로 이동하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('$currentUser $kind: 채팅 카드에서 해당 일정으로 이동한다', (tester) async {
      final day = MedicationHistoryDates.today(DateTime.now());
      final date =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final scheduleContext = ChatScheduleContext(
        scheduleDate: date,
        slotKey: 'evening',
        alarmTime: '18:00',
        alarmEnabled: true,
        completedCount: 0,
        totalCount: 1,
        canRequestCheck: false,
        medications: const [
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
            messageKind: kind,
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
              currentUserHash: currentUser,
              patientHash: 'patient-a',
              control: control,
              realtimeService: realtimeService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          kind == ChatMessageKind.slotCheckRequest ? '복약 확인 요청' : '복용 완료 알림',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('저녁 18:00'));
      await tester.pumpAndSettle();

      if (kind == ChatMessageKind.slotCheckRequest) {
        expect(find.byType(CheckScheduleUI), findsOneWidget);
      } else {
        expect(find.byType(MedicationHistoryUI), findsOneWidget);
        final scheduleScreen = tester.widget<MedicationHistoryUI>(
          find.byType(MedicationHistoryUI),
        );
        expect(scheduleScreen.readOnly, isTrue);
        expect(scheduleScreen.patientHash, 'patient-a');
        expect(scheduleScreen.sharedRange!.start.day, day.day);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await realtimeService.dispose();
      control.dispose();
    });
  }

  // Function Name: a schedule card older than the history does not open
  // Description:
  // - Checks that tapping a completion card dated 120 days ago does not open medication history or raise a widget exception.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('a schedule card older than the history does not open', (
    tester,
  ) async {
    final day = MedicationHistoryDates.today(
      DateTime.now(),
    ).subtract(const Duration(days: 120));
    final control = _RetryChatControl(
      failFirstSend: false,
      historyMessages: [
        ChatMessage(
          messageId: 71,
          linkId: 17,
          senderHash: 'patient-a',
          clientMessageId: 'schedule_message_002',
          body: '저녁 복약을 완료했어요.',
          createdAt: DateTime.utc(2026, 6, 24, 9),
          messageKind: ChatMessageKind.slotCompletion,
          scheduleContext: ChatScheduleContext(
            scheduleDate: MedicationHistoryDates.format(day),
            slotKey: 'evening',
            alarmTime: '18:00',
            alarmEnabled: true,
            completedCount: 1,
            totalCount: 1,
            canRequestCheck: false,
            medications: const [],
          ),
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
    await tester.tap(find.text('저녁 18:00'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationHistoryUI), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await realtimeService.dispose();
    control.dispose();
  });
}
