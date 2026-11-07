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
// Description:
// - Answer any otherwise unused fake transport call without reaching a server.
// Parameters:
// - request (http.Request): intercepted request; its contents are ignored.
// Returns:
// - Future<http.Response>; HTTP 200 with an empty JSON object.
Future<http.Response> _unused(http.Request request) async =>
    http.Response('{}', 200);

// Class Name: _Links
// Role: Configurable link-list source for chat-list polling.
// Responsibilities:
// - Return the configured ordering or simulate an offline lookup.
// Attributes:
// - result (List<PatientCaregiverLink>): links returned unchanged; the test controls their order.
// - fail (bool): when true, lookup throws StateError.
class _Links extends LinkPatientCaregiver {
  // Function Name: _Links
  // Description:
  // - Create a link-control fake backed by an inert mock client.
  // Parameters:
  // - None.
  // Returns:
  // - _Links; empty result list with failure disabled.
  _Links() : super(client: MockClient(_unused));

  List<PatientCaregiverLink> result = const [];
  bool fail = false;

  // Function Name: requestLinkScreen
  // Description:
  // - Return the current configured links, or throw StateError when the offline switch is set.
  // Parameters:
  // - None.
  // Returns:
  // - Future<List<PatientCaregiverLink>>; result without reordering or filtering.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    if (fail) throw StateError('offline');
    return result;
  }
}

// Class Name: _Previews
// Role: Supplies independent last-message times and unread counts for each chat.
// Responsibilities:
// - Generate deterministic previews without loading message history from a server.
// Attributes:
// - createdAt (Map<int, DateTime>): latest-message time keyed by link ID.
// - unread (Map<int, int>): unread count keyed by link ID, defaulting to zero.
class _Previews extends ManageLinkedChat {
  // Function Name: _Previews
  // Description:
  // - Create a preview provider scoped to the caregiver test account with an inert mock client.
  // Parameters:
  // - None.
  // Returns:
  // - _Previews; empty preview-time and unread-count maps.
  _Previews() : super(userHash: 'caregiver', client: MockClient(_unused));

  final Map<int, DateTime> createdAt = {};
  final Map<int, int> unread = {};

  // Function Name: requestHistory
  // Description:
  // - Return one synthetic latest message when the link has a configured time, otherwise return no history.
  // Parameters:
  // - linkId (int): link used to select the timestamp and construct message identifiers.
  // - beforeMessageId (int?), limit (int): accepted pagination inputs, ignored by this single-preview fake.
  // Returns:
  // - Future<List<ChatMessage>>; zero or one deterministic message.
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
  // Description:
  // - Read the configured unread count without requesting or changing message history.
  // Parameters:
  // - linkId (int): link whose unread count is requested.
  // Returns:
  // - Future<ChatUnreadSummary>; configured count or zero when absent.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async =>
      ChatUnreadSummary(count: unread[linkId] ?? 0);
}

// Class Name: _Labels
// Role: Label-store double that observes requested display languages.
// Responsibilities:
// - Record each language lookup and force the chat list to use fallback names.
// Attributes:
// - languages (List<bool>): isEnglish arguments in lookup order.
class _Labels extends ManageCaregiverPatientLocalState {
  final List<bool> languages = [];

  // Function Name: loadLabels
  // Description:
  // - Record the requested language and return no saved labels.
  // Parameters:
  // - caregiverHash (String), links (List<PatientCaregiverLink>): accepted lookup scope, unused by this fake.
  // - isEnglish (bool): language flag appended to languages, default false.
  // Returns:
  // - Future<Map<String, String>>; an empty label map.
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
// Description:
// - Build an active link from the test caregiver to a patient derived from its ID.
// Parameters:
// - id (int): link ID and suffix of the patient account.
// - alias (String?): optional server-side patient name; null and empty strings exercise fallback names.
// Returns:
// - PatientCaregiverLink; active caregiver-to-patient link.
PatientCaregiverLink _link(int id, {String? alias}) => PatientCaregiverLink(
  linkId: id,
  patientHash: 'patient-$id',
  caregiverHash: 'caregiver',
  patientAlias: alias,
  linkStatus: true,
);

// Function Name: main
// Description:
// - Register controlled chat-list polling tests for publication order, loading/error transitions, fallback labels, and borrowed authenticated clients.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // 함수이름: unresolved links remain unknown until a successful response
  // 함수역할: 최초 실패는 연동 없음으로 확정하지 않고, 정상 빈 응답 후의 실패는 마지막 확인 상태를 유지한다.
  // 매개변수: 없음. 반환값: 상태 전환 검증 완료 Future<void>.
  test('unresolved links remain unknown until a successful response', () async {
    final links = _Links()..fail = true;
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: _Previews(),
      localState: _Labels(),
    );
    addTearDown(control.dispose);
    expect(control.hasResolvedLinks, isFalse);

    await control.refresh();
    expect(control.hasError, isTrue);
    expect(control.hasResolvedLinks, isFalse);
    expect(control.links, isEmpty);

    links.fail = false;
    await control.refresh();
    expect(control.hasError, isFalse);
    expect(control.hasResolvedLinks, isTrue);
    expect(control.links, isEmpty);

    links.fail = true;
    await control.refresh();
    expect(control.hasError, isTrue);
    expect(control.hasResolvedLinks, isTrue);
    expect(control.links, isEmpty);
  });

  // 함수이름: restarting or switching accounts does not reuse resolved links
  // 함수역할: 기존 계정의 조회 결과가 재시작이나 다른 계정의 연동 확인 상태로 넘어가지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 각 계정의 초기화·실패 상태 검증 완료 Future<void>.
  test(
    'restarting or switching accounts does not reuse resolved links',
    () async {
      final links = _Links()..result = [_link(1)];
      final labels = _Labels();
      final original = ManageChatList(
        userHash: 'caregiver',
        linkControl: links,
        chatControl: _Previews(),
        localState: labels,
      );
      await original.refresh();
      expect(original.hasResolvedLinks, isTrue);
      expect(original.links, hasLength(1));
      original.dispose();

      links.fail = true;
      for (final owner in ['caregiver', 'another-account']) {
        final current = ManageChatList(
          userHash: owner,
          linkControl: links,
          chatControl: _Previews(),
          localState: labels,
        );
        addTearDown(current.dispose);
        await current.refresh();
        expect(current.hasResolvedLinks, isFalse);
        expect(current.hasError, isTrue);
        expect(current.links, isEmpty);
        expect(current.latestMessage(1), isNull);
      }
    },
  );

  // Function Name: record
  // Description:
  // - Attach a listener that records each published loading flag and ordered link-ID list.
  // Parameters:
  // - control (ManageChatList): observable list controller to monitor.
  // Returns:
  // - List<String>; live log with an L prefix while loading, followed by comma-separated link IDs.
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

  // Function Name: a poll publishes the sorted list once and stays silent when nothing changed
  // Description:
  // - Publish recency-sorted links once after initial loading, stay silent on unchanged polls, and notify once when either message recency or unread counts change.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
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

  // Function Name: background polls keep isLoading false; an explicit refresh shows it
  // Description:
  // - Show loading for the initial request and explicit refresh only; unchanged background polls neither set isLoading nor notify listeners.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'background polls keep isLoading false; an explicit refresh shows it',
    () async {
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
    },
  );

  // Function Name: a failing poll keeps the list and notifies only when the error state changes
  // Description:
  // - Keep the last links and previews through repeated lookup failures, notify only on error-state changes, then remove stale previews when recovery drops a link.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
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

  // Function Name: default patient names follow the display language
  // Description:
  // - Pass the current display language to label loading and use the requested language for fallback patient names when the server alias is empty.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
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
    expect(
      control.peerName(control.links.single, isEnglish: true),
      'Patient NT-7',
    );
  });

  // Function Name: default caregiver names show only the end of the account hash
  // Description:
  // - Fallback caregiver labels expose only the final four account-hash characters in Korean or English, not the full internal identifier.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test(
    'default caregiver names show only the end of the account hash',
    () async {
      final links = _Links()
        ..result = [
          PatientCaregiverLink(
            linkId: 9,
            patientHash: 'usr_patient0000e5b0',
            caregiverHash: 'usr_ad6f49ec1053a60874b9c485e73e1314',
            linkStatus: true,
          ),
        ];
      final control = ManageChatList(
        userHash: 'usr_patient0000e5b0',
        linkControl: links,
        chatControl: _Previews(),
        localState: _Labels(),
      );
      addTearDown(control.dispose);

      await control.refresh();
      expect(
        control.peerName(control.links.single, isEnglish: false),
        '보호자 1314',
      );
      expect(
        control.peerName(control.links.single, isEnglish: true),
        'Caregiver 1314',
      );
    },
  );

  // Function Name: default controls use the injected client and report a 401 to its handler
  // Description:
  // - Route both default link and preview controls through the injected authenticated client so each 401 reaches its handler, while disposal leaves that borrowed client usable.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  test('default controls use the injected client and report a 401 to its '
      'handler', () async {
    var unauthorized = 0;
    final paths = <String>[];
    var rejectLinks = false;
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/link/list')) {
          if (rejectLinks) {
            return jsonResponse({'detail': 'expired'}, status: 401);
          }
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
