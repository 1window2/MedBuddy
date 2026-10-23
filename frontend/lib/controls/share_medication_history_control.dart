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

class ShareMedicationHistory {
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

  void _checkSession() {
    if (_disposed) throw const MedicationHistorySessionChanged();
    _ensureSession();
  }

  // 같은 계정이 여러 환자와 연결되어 있어도 현재 환자의 대화만 허용한다.
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

  String peerName(PatientCaregiverLink link) =>
      _list.peerName(link, isEnglish: isEnglish);

  // 응답이 유실된 동일 기간·상대의 재시도는 같은 식별자를 사용해 중복 전송을 막는다.
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

  void dispose() {
    _disposed = true;
    _recipients = const [];
    _pendingIds.clear();
    _list.dispose();
    _chat.dispose();
    if (_ownsClient) _client.close();
  }
}
