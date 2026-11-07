// File Name: caregiver_alert_action_control.dart
// Role: Executes account-scoped caregiver alert actions through authenticated APIs.
// Role: Execute caregiver-only actions through the existing authenticated APIs.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/chat_message_entity.dart';
import '../entities/medication_slot_label.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/auth_config.dart';
import 'manage_linked_chat_control.dart';

// Class Name: CaregiverAlertAction
// Role: Enumerates the caregiver actions supported by missed-dose alerts.
// Responsibilities: Distinguish server snoozing from a linked-chat request to check a dose.
// Attributes: snooze/requestCheck: Available action values.
enum CaregiverAlertAction { snooze, requestCheck }

// Class Name: CaregiverAlertActionControl
// Role: Executes missed-dose alert actions for the notified caregiver.
// Responsibilities: Check recipient ownership, deduplicate in-flight event/action pairs, and validate API responses.
// Attributes: userHash/baseUrl (String): Account/API scope; client (http.Client): Caller-owned transport; _running (Set<String>): In-flight keys.
class CaregiverAlertActionControl {
  final String userHash;
  final http.Client client;
  final String baseUrl;
  final Set<String> _running = {};

  // Function Name: CaregiverAlertActionControl
  // Description: Binds caregiver scope to an existing authenticated transport without making requests.
  // Parameters: userHash (String): Recipient account; client (http.Client): Caller-owned transport; baseUrl (String): API root.
  // Returns: An idle action control; it does not own or close the injected client.
  CaregiverAlertActionControl({required this.userHash, required this.client, this.baseUrl = ApiConfig.baseUrl});

  // Function Name: _uri
  // Description: Builds a caregiver endpoint and supplies the local user override only when authentication is explicitly disabled.
  // Parameters: path (String): Relative API endpoint.
  // Returns: URI under baseUrl; malformed URI input raises a parsing error.
  Uri _uri(String path) => Uri.parse('$baseUrl/$path').replace(
    queryParameters: AuthConfig.mode == AuthenticationMode.disabled ? {'user_hash': userHash} : null,
  );

  // Function Name: execute
  // Description: Snoozes a server alert or sends a deduplicated slot-check chat request, rejecting another account's alert and overlapping identical actions.
  // Parameters: context (CaregiverAlertContext): Validated alert; action (CaregiverAlertAction): Requested operation; language (String): Chat message locale.
  // Returns: Completion after server confirmation; ownership, duplicate, timeout, transport, and response failures propagate. In-flight markers are always released.
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
        final english = isEnglishLanguage(language);
        final slotLabel = medicationSlotLabelOrNull(context.slotKey, isEnglish: english, lowercase: true) ?? context.slotKey;
        final chat = ManageLinkedChat(userHash: userHash, client: client);
        await chat.sendMessage(
          linkId: context.linkId,
          clientMessageId: 'missed_chat_${context.sourceAlertId}',
          body: english ? 'Please check your $slotLabel medication schedule.' : '$slotLabel 복약 일정을 확인해 주세요.',
          messageKind: ChatMessageKind.slotCheckRequest, slotKey: context.slotKey,
          sourceAlertId: context.sourceAlertId,
        );
      }
    } finally {
      _running.remove(key);
    }
  }

  // Function Name: requestLocalDeliveries
  // Description: Loads local-mode deliveries and retains only valid alert contexts for this account.
  // Parameters: None.
  // Returns: Matching contexts, or an empty list outside authentication-disabled mode; HTTP/JSON/list-shape errors propagate.
  Future<List<CaregiverAlertContext>> requestLocalDeliveries() async {
    if (AuthConfig.mode != AuthenticationMode.disabled) return const [];
    final response = await client.get(_uri('caregiver-alerts/local-deliveries')).timeout(const Duration(seconds: 20));
    final data = _response(response)['data'];
    if (data is! List) throw StateError('Invalid caregiver delivery response.');
    return data.whereType<Map>().map((value) => CaregiverAlertContext.fromData(Map<String, dynamic>.from(value)))
        .whereType<CaregiverAlertContext>().where((value) => value.recipientHash == userHash).toList();
  }

  // Function Name: _response
  // Description: Requires a successful HTTP status and decodes UTF-8 JSON into an object.
  // Parameters: response (http.Response): Caregiver endpoint response.
  // Returns: Decoded map; non-2xx/non-object responses raise StateError and malformed encoding/JSON raises its decode error.
  Map<String, dynamic> _response(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Caregiver action failed (${response.statusCode}).');
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) throw StateError('Invalid action response.');
    return value;
  }
}
