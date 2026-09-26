// Role: Execute caregiver-only actions through the existing authenticated APIs.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/chat_message_entity.dart';
import '../services/api_config.dart';
import '../services/auth_config.dart';
import 'manage_linked_chat_control.dart';

enum CaregiverAlertAction { snooze, requestCheck }

class CaregiverAlertActionControl {
  final String userHash;
  final http.Client client;
  final String baseUrl;
  final Set<String> _running = {};

  CaregiverAlertActionControl({required this.userHash, required this.client, this.baseUrl = ApiConfig.baseUrl});

  Uri _uri(String path) => Uri.parse('$baseUrl/$path').replace(
    queryParameters: AuthConfig.mode == AuthenticationMode.disabled ? {'user_hash': userHash} : null,
  );

  Future<void> execute(CaregiverAlertContext context, CaregiverAlertAction action, {String language = 'ko'}) async {
    if (context.recipientHash != userHash) throw StateError('This notification belongs to another account.');
    final key = '${context.eventId}:${action.name}';
    if (!_running.add(key)) throw StateError('This action is already running.');
    try {
      if (action == CaregiverAlertAction.snooze) {
        final response = await client.post(_uri('caregiver-alerts/${context.alertId}/snooze')).timeout(const Duration(seconds: 20));
        final body = _response(response);
        if (body['success'] != true || body['data'] is! Map) throw StateError('Snooze was not confirmed.');
      } else {
        final labels = language == 'en'
            ? const {'morning': 'morning', 'lunch': 'lunch', 'evening': 'evening', 'bedtime': 'bedtime'}
            : const {'morning': '아침', 'lunch': '점심', 'evening': '저녁', 'bedtime': '취침 전'};
        final chat = ManageLinkedChat(userHash: userHash, client: client);
        await chat.sendMessage(
          linkId: context.linkId,
          clientMessageId: 'missed_chat_${context.sourceAlertId}',
          body: language == 'en' ? 'Please check your ${labels[context.slotKey]} medication schedule.' : '${labels[context.slotKey]} 복약 일정을 확인해 주세요.',
          messageKind: ChatMessageKind.slotCheckRequest, slotKey: context.slotKey,
          sourceAlertId: context.sourceAlertId,
        );
      }
    } finally {
      _running.remove(key);
    }
  }

  Future<List<CaregiverAlertContext>> requestLocalDeliveries() async {
    if (AuthConfig.mode != AuthenticationMode.disabled) return const [];
    final response = await client.get(_uri('caregiver-alerts/local-deliveries')).timeout(const Duration(seconds: 20));
    final data = _response(response)['data'];
    if (data is! List) throw StateError('Invalid caregiver delivery response.');
    return data.whereType<Map>().map((value) => CaregiverAlertContext.fromData(Map<String, dynamic>.from(value)))
        .whereType<CaregiverAlertContext>().where((value) => value.recipientHash == userHash).toList();
  }

  Map<String, dynamic> _response(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Caregiver action failed (${response.statusCode}).');
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) throw StateError('Invalid action response.');
    return value;
  }
}
