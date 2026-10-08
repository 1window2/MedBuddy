// File Name: manage_chat_list_control_test.dart
// Role: Characterizes what the chat-list control publishes per poll: order, notify count,
//   loading flag, label language and the HTTP client its default controls use.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_caregiver_patient_local_state_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/caregiver_patient_local_state_service.dart';

import 'support/json_http.dart';

// Function Name: _unused
// Description: Answers requests of fakes that override every operation the tests reach.
// Parameters: request - intercepted request (unused). Returns: An empty 200 response.
Future<http.Response> _unused(http.Request request) async =>
    http.Response('{}', 200);

// Class Name: _Links
// Role: Link lookup fake returning the links a test sets, in server (link ID) order.
// Responsibilities: Fail on demand so the kept-list behavior can be observed.
// Attributes: result - links of the next lookup; fail - whether the next lookup throws.
class _Links extends LinkPatientCaregiver {
  // Function Name: _Links
  // Description: Creates the fake without a reachable server.
  // Parameters: None. Returns: The link fake.
  _Links() : super(client: MockClient(_unused));

  List<PatientCaregiverLink> result = const [];
  bool fail = false;

  // Function Name: requestLinkScreen
  // Description: Returns the configured links or fails like an offline lookup.
  // Parameters: None. Returns: The links; throws StateError when fail is set.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    if (fail) throw StateError('offline');
    return result;
  }
}

// Class Name: _Previews
// Role: Chat fake returning one latest message and an unread count per link.
// Attributes: createdAt - latest message time per link; unread - unread count per link.
class _Previews extends ManageLinkedChat {
  // Function Name: _Previews
  // Description: Creates the fake for the caregiver account used by the tests.
  // Parameters: None. Returns: The preview fake.
  _Previews() : super(userHash: 'caregiver', client: MockClient(_unused));

  final Map<int, DateTime> createdAt = {};
  final Map<int, int> unread = {};

  // Function Name: requestHistory
  // Description: Returns the configured latest message of the link, if any.
  // Parameters: linkId - conversation; beforeMessageId, limit - unused paging inputs.
  // Returns: Zero or one message.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async => [
    if (createdAt[linkId] case final time?)
      ChatMessage(
        messageId: linkId,
        linkId: linkId,
        senderHash: 'patient-$linkId',
        clientMessageId: 'preview_$linkId',
        body: 'message $linkId',
        createdAt: time,
      ),
  ];

  // Function Name: requestUnreadSummary
  // Description: Returns the configured unread count of the link.
  // Parameters: linkId - conversation. Returns: The unread summary, zero by default.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async =>
      ChatUnreadSummary(count: unread[linkId] ?? 0);
}

// Class Name: _Labels
// Role: Label-store fake that records the language the control asked for.
// Attributes: languages - isEnglish value of each loadLabels call, oldest first.
class _Labels extends ManageCaregiverPatientLocalState {
  final List<bool> languages = [];

  // Function Name: loadLabels
  // Description: Records the requested language and returns no stored label.
  // Parameters: caregiverHash, links - unused scope; isEnglish - requested fallback language.
  // Returns: An empty label map.
  @override
  Future<Map<String, String>> loadLabels({
    required String caregiverHash,
    required List<PatientCaregiverLink> links,
    bool isEnglish = false,
  }) async {
    languages.add(isEnglish);
    return const {};
  }
}

// Function Name: _link
// Description: Builds an active link between the test caregiver and patient-<id>.
// Parameters: id - link ID; alias - server-side patient alias, if any.
// Returns: The link.
PatientCaregiverLink _link(int id, {String? alias}) => PatientCaregiverLink(
  linkId: id,
  patientHash: 'patient-$id',
  caregiverHash: 'caregiver',
  patientAlias: alias,
  linkStatus: true,
);

// Function Name: main
// Description: Registers the chat-list control tests; no network, storage or timers are used.
// Parameters: None. Returns: None.
void main() {
  // Each notify is logged as "<L when loading><link IDs in published order>".
  List<String> record(ManageChatList control) {
    final seen = <String>[];
    control.addListener(() {
      seen.add(
        '${control.isLoading ? 'L' : ''}'
        '${control.links.map((link) => link.linkId).join(',')}',
      );
    });
    return seen;
  }

  // G1: the server order (link ID) must never be published before the recency order.
  test('a poll publishes the sorted list once and stays silent when nothing '
      'changed', () async {
    final links = _Links()..result = [_link(1), _link(2)];
    final previews = _Previews()
      ..createdAt[1] = DateTime.utc(2026, 1, 1)
      ..createdAt[2] = DateTime.utc(2026, 1, 2);
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: previews,
      localState: _Labels(),
    );
    addTearDown(control.dispose);
    final seen = record(control);

    await control.refresh(includeMessages: true);
    expect(seen, ['L', '2,1']);

    for (var poll = 0; poll < 3; poll++) {
      seen.clear();
      await control.refresh(includeMessages: true);
      expect(seen, isEmpty, reason: 'poll $poll');
      expect(control.isLoading, isFalse);
    }

    previews.createdAt[1] = DateTime.utc(2026, 1, 3);
    await control.refresh(includeMessages: true);
    expect(seen, ['1,2']);

    seen.clear();
    previews.unread[2] = 4;
    await control.refresh(includeMessages: true);
    expect(seen, ['1,2']);
    expect(control.unreadCount(2), 4);
  });

  // G1: only the first load and an explicit refresh show the progress bar.
  test('background polls keep isLoading false; an explicit refresh shows it', () async {
    final links = _Links()..result = [_link(1)];
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: _Previews(),
      localState: _Labels(),
    );
    addTearDown(control.dispose);
    final seen = record(control);

    final first = control.refresh();
    expect(control.isLoading, isTrue);
    await first;
    expect(seen, ['L', '1']);

    seen.clear();
    final poll = control.refresh();
    expect(control.isLoading, isFalse);
    await poll;
    expect(seen, isEmpty);

    final requested = control.refresh(showLoading: true);
    expect(control.isLoading, isTrue);
    await requested;
    expect(seen, ['L1', '1']);
  });

  // G1: a failed poll keeps the last list and reports the error state change once.
  test('a failing poll keeps the list and notifies only when the error state '
      'changes', () async {
    final links = _Links()..result = [_link(1), _link(2)];
    final previews = _Previews()..createdAt[2] = DateTime.utc(2026, 1, 2);
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: previews,
      localState: _Labels(),
    );
    addTearDown(control.dispose);
    await control.refresh(includeMessages: true);
    final seen = record(control);

    links.fail = true;
    await control.refresh(includeMessages: true);
    await control.refresh(includeMessages: true);
    expect(seen, ['2,1']);
    expect(control.hasError, isTrue);
    expect(control.latestMessage(2), isNotNull);

    links
      ..fail = false
      ..result = [_link(1)];
    await control.refresh(includeMessages: true);
    expect(seen, ['2,1', '1']);
    expect(control.hasError, isFalse);
    // The preview of the removed link leaves together with the link.
    expect(control.latestMessage(2), isNull);
  });

  // F3/G8: label lookups use the language the creator set on the control; the fallback for a
  // cleared server alias uses the language the caller asks peerName for.
  test('default patient names follow the display language', () async {
    final links = _Links()..result = [_link(7, alias: '')];
    final labels = _Labels();
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: _Previews(),
      localState: labels,
    );
    addTearDown(control.dispose);

    await control.refresh();
    expect(labels.languages, [false]);
    expect(
      control.peerName(control.links.single, isEnglish: false),
      CaregiverPatientLocalStateService.fallbackLabel('patient-7'),
    );

    control.isEnglish = true;
    await control.refresh();
    expect(labels.languages, [false, true]);
    expect(
      control.peerName(control.links.single, isEnglish: true),
      CaregiverPatientLocalStateService.fallbackLabel(
        'patient-7',
        isEnglish: true,
      ),
    );
    expect(control.peerName(control.links.single, isEnglish: true), 'Patient NT-7');
  });

  // G2: both default controls must send through the injected session client, so a 401 on
  // the link list or on a preview reaches the session's unauthorized handler.
  test('default controls use the injected client and report a 401 to its '
      'handler', () async {
    var unauthorized = 0;
    final paths = <String>[];
    var rejectLinks = false;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/link/list')) {
          if (rejectLinks) return jsonResponse({'detail': 'expired'}, status: 401);
          return jsonResponse({
            'data': [
              {
                'link_id': 3,
                'patient_hash': 'patient-3',
                'caregiver_hash': 'caregiver',
                'link_status': true,
              },
            ],
          });
        }
        return http.Response(jsonEncode({'detail': 'expired'}), 401);
      }),
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      appCheckRequired: false,
      onUnauthorized: () async => unauthorized += 1,
    );
    addTearDown(client.close);
    final control = ManageChatList(
      userHash: 'caregiver',
      client: client,
      localState: _Labels(),
    );

    await control.refresh(includeMessages: true);
    expect(control.links.single.linkId, 3);
    expect(paths, [
      endsWith('/medication/link/list'),
      endsWith('/chat/links/3/messages'),
      endsWith('/chat/links/3/unread-count'),
    ]);
    // History and unread-count were rejected: one handler call each.
    expect(unauthorized, 2);
    expect(control.previewFailed(3), isTrue);

    rejectLinks = true;
    await control.refresh();
    expect(unauthorized, 3);
    expect(control.hasError, isTrue);

    // The borrowed client stays usable after the control is disposed.
    control.dispose();
    final response = await client.get(
      Uri.parse('${ApiConfig.baseUrl}/link/list'),
    );
    expect(response.statusCode, 401);
  });
}
