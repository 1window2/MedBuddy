// 파일명: share_medication_history_control.dart
// 역할: 환자와 로그인 세션 범위를 유지하며 복약 기록을 연결된 대화에 공유한다.
// 복약 기록의 환자 범위와 로그인 세션을 유지하며 채팅 공유 대상을 확인한다.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../entities/chat_message_entity.dart';
import '../entities/medication_history_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import 'manage_chat_list_control.dart';
import 'manage_linked_chat_control.dart';
import 'medication_history_control.dart';

// 클래스명: ShareMedicationHistory
// 역할: 현재 환자의 복약 기록을 검증된 연동 대화에 공유한다.
// 주요 책임: 환자·송신자·세션 범위를 확인하고 같은 기간 재시도의 요청 ID를 유지하며 응답을 검증한다.
// 속성: userHash/patientHash: 송신자·환자; isEnglish: 언어; _ensureSession/_now: 검사·시계; _client/_list/_chat: 통신 의존성; _recipients/_pendingIds: 검증 대상·재시도 ID; _sending/_disposed: 작업 상태.
class ShareMedicationHistory {
  // 함수이름: ShareMedicationHistory
  // 함수역할: 환자와 송신자 키를 검사하고 세션 검사로 감싼 채팅 조회·전송 의존성을 구성한다.
  // 매개변수: userHash/patientHash (String): 계정·환자; ensureSession: 실패 시 예외인 검사; isEnglish (bool): 언어; client (http.Client?): 외부 소유 연결; now: 선택 시계.
  // 반환값: 공유 컨트롤. 빈 식별자는 ArgumentError이며 직접 만든 HTTP 연결만 dispose 때 닫는다.
  ShareMedicationHistory({
    required this.userHash,
    required this.patientHash,
    required void Function() ensureSession,
    required this.isEnglish,
    http.Client? client,
    DateTime Function()? now,
  }) : _ensureSession = ensureSession,
       _ownsClient = client == null,
       _now = now ?? DateTime.now {
    if (userHash.trim().isEmpty || patientHash.trim().isEmpty) {
      throw ArgumentError('A sender and patient are required.');
    }
    _client =
        client ??
        AuthenticatedApiClient(
          tokenProvider: () async {
            _checkSession();
            if (AuthConfig.mode == AuthenticationMode.disabled) return null;
            final token = await FirebaseAuth.instance.currentUser?.getIdToken();
            _checkSession();
            return token;
          },
        );
    _list = ManageChatList(
      userHash: userHash,
      client: _client,
      isEnglish: isEnglish,
    );
    _chat = ManageLinkedChat(userHash: userHash, client: _client);
  }

  final String userHash;
  final String patientHash;
  final bool isEnglish;
  final void Function() _ensureSession;
  final DateTime Function() _now;
  final bool _ownsClient;
  late final http.Client _client;
  late final ManageChatList _list;
  late final ManageLinkedChat _chat;
  List<PatientCaregiverLink> _recipients = const [];
  final Map<String, String> _pendingIds = {};
  bool _sending = false;
  bool _disposed = false;

  // 함수이름: _checkSession
  // 함수역할: 종료 상태와 호출자가 제공한 세션 유효성을 확인한다.
  // 매개변수: 없음.
  // 반환값: 없음. 종료되면 MedicationHistorySessionChanged, 검사 실패는 원래 예외를 전파한다.
  void _checkSession() {
    if (_disposed) throw const MedicationHistorySessionChanged();
    _ensureSession();
  }

  // 같은 계정이 여러 환자와 연결되어 있어도 현재 환자의 대화만 허용한다.
  // 함수이름: loadRecipients
  // 함수역할: 채팅 목록을 새로 읽고 현재 환자·송신자가 속한 활성 연동만 공유 대상으로 확정한다.
  // 매개변수: 없음.
  // 반환값: 수정 불가능한 공유 대상 목록. 조회 실패·계정 변경은 예외이며 오래된 대상 목록은 먼저 비운다.
  Future<List<PatientCaregiverLink>> loadRecipients() async {
    _checkSession();
    _recipients = const [];
    await _list.refresh();
    _checkSession();
    if (_list.hasError) throw StateError('Could not verify chat recipients.');
    _recipients = _list.links
        .where(
          (link) =>
              link.patientHash == patientHash &&
              link.linkStatus &&
              link.linkId != null &&
              (link.patientHash == userHash || link.caregiverHash == userHash),
        )
        .toList(growable: false);
    return List.unmodifiable(_recipients);
  }

  // 함수이름: peerName
  // 함수역할: 공유 대화 상대의 이름을 현재 계정 관점과 표시 언어에 맞춰 조회한다.
  // 매개변수: link (PatientCaregiverLink): 표시할 연동 관계.
  // 반환값: 채팅 목록 컨트롤이 정한 상대 이름 또는 대체 문구.
  String peerName(PatientCaregiverLink link) =>
      _list.peerName(link, isEnglish: isEnglish);

  // 응답이 유실된 동일 기간·상대의 재시도는 같은 식별자를 사용해 중복 전송을 막는다.
  // 함수이름: send
  // 함수역할: 검증된 상대에게 기간별 기록 공유 메시지를 보내고 응답의 송신자·기간·요청 ID를 확인한다.
  // 매개변수: linkId (int): loadRecipients에서 확인한 대화; range (MedicationHistoryRange): 현재 시계 기준 유효한 기간.
  // 반환값: 검증된 ChatMessage. 실패 시 같은 대화·기간의 ID를 유지하며 동시 전송·세션 변경·응답 불일치는 예외로 알린다.
  Future<ChatMessage> send({
    required int linkId,
    required MedicationHistoryRange range,
  }) async {
    _checkSession();
    range.validate(_now());
    if (_sending) throw const MedicationHistoryBusy();
    if (!_recipients.any((link) => link.linkId == linkId)) {
      throw StateError('The recipient must belong to the selected patient.');
    }
    final key = '$linkId|${range.label}';
    final id = _pendingIds.putIfAbsent(
      key,
      MedicationHistoryControl.newOperationId,
    );
    _sending = true;
    try {
      final message = await _chat.sendMessage(
        linkId: linkId,
        clientMessageId: id,
        body: isEnglish ? 'I shared medication records.' : '복약 기록을 공유했어요.',
        messageKind: ChatMessageKind.medicationHistoryShare,
        historyStartDate: MedicationHistoryDates.format(range.start),
        historyEndDate: MedicationHistoryDates.format(range.end),
      );
      _checkSession();
      final shared = message.historyContext;
      if (message.linkId != linkId ||
          message.senderHash != userHash ||
          message.clientMessageId != id ||
          message.messageKind != ChatMessageKind.medicationHistoryShare ||
          shared == null ||
          shared.startDate != range.start ||
          shared.endDate != range.end) {
        throw const FormatException(
          'The shared record response did not match the request.',
        );
      }
      _pendingIds.remove(key);
      return message;
    } finally {
      _sending = false;
    }
  }

  // 함수이름: dispose
  // 함수역할: 후속 공유를 막고 대상·재시도 ID·하위 컨트롤을 정리한다.
  // 매개변수: 없음.
  // 반환값: 없음. 외부에서 주입한 HTTP 연결은 닫지 않는다.
  void dispose() {
    _disposed = true;
    _recipients = const [];
    _pendingIds.clear();
    _list.dispose();
    _chat.dispose();
    if (_ownsClient) _client.close();
  }
}
