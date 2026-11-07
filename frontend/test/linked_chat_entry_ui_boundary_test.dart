// 파일명: linked_chat_entry_ui_boundary_test.dart
// 역할: 알림 진입에서도 연동별 역할·별칭을 복원하고 조회 실패 시 채팅을 열지 않는지 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

// 클래스명: _Links
// 역할: 알림으로 진입할 연동 목록의 지연·실패·재시도를 재현하는 대역.
// 주요 책임:
// - 요청 횟수를 기록하고 pending 응답, 실패, 즉시 결과 순서로 조회를 처리한다.
// 속성:
// - result (List<PatientCaregiverLink>): 즉시 반환할 연동 목록.
// - fail (bool): pending이 없을 때 오프라인 예외 발생 여부.
// - requests (int): 연동 조회 횟수.
// - pending (Completer<List<PatientCaregiverLink>>?): 테스트가 완료할 선택적 지연 응답.
class _Links extends LinkPatientCaregiver {
  // 함수이름: _Links
  // 함수역할:
  // - 외부 서버 없이 응답하는 MockClient로 연동 대역을 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - _Links; 빈 목록과 0회 요청, 실패·대기 응답이 없는 대역.
  _Links() : super(client: MockClient((_) async => http.Response('{}', 200)));

  List<PatientCaregiverLink> result = const [];
  bool fail = false;
  int requests = 0;
  Completer<List<PatientCaregiverLink>>? pending;

  // 함수이름: requestLinkScreen
  // 함수역할:
  // - 요청을 기록하고 pending이 있으면 기다리며, 없으면 fail에 따라 오류 또는 result를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<PatientCaregiverLink>>; 설정된 목록 또는 지연 응답으로 완료하고 실패 시 StateError를 던진다.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    requests++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return result;
  }
}

// 알림 진입 시 두 역할의 별칭을 복원할 활성 연동 기준값.
const _link = PatientCaregiverLink(
  linkId: 17,
  patientHash: 'patient-a',
  caregiverHash: 'caregiver-a',
  patientAlias: '환자 별칭',
  caregiverAlias: '보호자 별칭',
  linkStatus: true,
);

// 함수이름: _pumpEntry
// 함수역할:
// - 현재 계정의 연동 17 진입 화면을 표시하고 첫 조회 및 전환 프레임을 진행한다.
// 매개변수:
// - tester (WidgetTester): 화면 표시와 시간 진행 도구.
// - control (ManageChatList): 계정과 연동 조회를 제공하는 컨트롤.
// - language (String): 기본 ko인 전달 언어.
// 반환값:
// - Future<void>; 첫 프레임과 350ms를 진행한 뒤 완료하며 대기 중인 조회까지 기다리지는 않는다.
Future<void> _pumpEntry(
  WidgetTester tester,
  ManageChatList control, {
  String language = 'ko',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LinkedChatEntryUI(
        linkId: 17,
        currentUserHash: control.userHash,
        userSetting: UserSetting(language: language),
        control: control,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

// 함수이름: _closeEntry
// 함수역할:
// - 진입 화면을 제거한 뒤 20초를 진행하여 남은 작업이 해제된 화면 오류를 발생시키지 않는지 검사한다.
// 매개변수:
// - tester (WidgetTester): 화면 제거·시간 진행·예외 검사를 수행한다.
// 반환값:
// - Future<void>; 지연 작업 검증 후 완료하며 렌더링 예외가 있으면 실패한다.
Future<void> _closeEntry(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  expect(tester.takeException(), isNull);
}

// Function Name: main
// Description:
// - Register chat-entry tests for link-specific roles, pending and failed lookup, ended links, and authenticated-client ownership.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // 함수이름: setUp
  // 함수역할:
  // - 테스트마다 저장된 연동 이름·설정을 비워 이전 사례의 기기 상태가 섞이지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['ko', 'en']) {
    for (final patient in [true, false]) {
      // 함수이름: notification resolves patient=$patient in $language
      // 함수역할:
      // - 한국어·영어와 환자·보호자 역할별로 선택한 연동 17의 상대 이름과 환자 해시를 사용하고, 다른 연동에서 맡은 역할은 섞지 않는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('notification resolves patient=$patient in $language', (
        tester,
      ) async {
        final links = _Links()
          ..result = [
            // 같은 사람이 다른 연동에서는 보호자여도 선택한 연동의 역할만 사용한다.
            const PatientCaregiverLink(
              linkId: 18,
              patientHash: 'patient-b',
              caregiverHash: 'patient-a',
              linkStatus: true,
            ),
            _link,
          ];
        final control = ManageChatList(
          userHash: patient ? 'patient-a' : 'caregiver-a',
          linkControl: links,
        );
        addTearDown(links.dispose);
        addTearDown(control.dispose);
        await _pumpEntry(tester, control, language: language);
        final room = tester.widget<LinkedChatUI>(find.byType(LinkedChatUI));
        expect(room.linkId, 17);
        expect(room.patientHash, 'patient-a');
        expect(room.currentUserHash == room.patientHash, patient);
        expect(room.peerName, patient ? '보호자 별칭' : '환자 별칭');
        expect(room.userSetting.language, language);
        expect(links.requests, 1);
        await _closeEntry(tester);
      });
    }
  }

  // 함수이름: pending lookup never displays caregiver tools by default
  // 함수역할:
  // - 연동 조회 중에는 역할을 추측해 채팅이나 보호자 확인 도구를 표시하지 않고, 화면을 닫은 뒤 응답이 와도 다시 열지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('pending lookup never displays caregiver tools by default', (
    tester,
  ) async {
    final links = _Links()..pending = Completer<List<PatientCaregiverLink>>();
    final control = ManageChatList(userHash: 'patient-a', linkControl: links);
    addTearDown(links.dispose);
    addTearDown(control.dispose);
    await _pumpEntry(tester, control);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinkedChatUI), findsNothing);
    expect(find.text('복용하셨나요?'), findsNothing);
    // 조회 도중 뒤로 돌아간 뒤 응답이 와도 종료된 화면을 다시 열지 않는다.
    await tester.pumpWidget(const SizedBox.shrink());
    links.pending!.complete([_link]);
    await tester.pump();
    expect(find.byType(LinkedChatUI), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: lookup failure offers retry without guessing the role
  // 함수역할:
  // - 현재 조회가 실패하면 이전 캐시의 역할로 진입하지 않고 재시도를 제공하며, 조회 복구 후 올바른 환자 역할로 여는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('lookup failure offers retry without guessing the role', (
    tester,
  ) async {
    final links = _Links()..result = [_link];
    final control = ManageChatList(userHash: 'patient-a', linkControl: links);
    addTearDown(links.dispose);
    addTearDown(control.dispose);
    // 이전 캐시가 있어도 현재 조회가 실패하면 오래된 연동으로 진입하지 않는다.
    await control.refresh();
    links.fail = true;
    await _pumpEntry(tester, control);
    expect(find.byType(LinkedChatUI), findsNothing);
    expect(find.textContaining('대화 상대를 확인하지 못했어요'), findsOneWidget);
    links.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final room = tester.widget<LinkedChatUI>(find.byType(LinkedChatUI));
    expect(room.patientHash, room.currentUserHash);
    await _closeEntry(tester);
  });

  for (final scenario in ['missing', 'inactive', 'other-user', 'no-patient']) {
    // Function Name: invalid notification link is blocked: $scenario
    // Description:
    // - Missing, inactive, unrelated-user, and empty-patient links never open a conversation; successful lookup instead shows an ended-link notice and management action without retry.
    // Parameters:
    // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    testWidgets('invalid notification link is blocked: $scenario', (
      tester,
    ) async {
      final links = _Links()
        ..result = switch (scenario) {
          'missing' => [],
          'inactive' => [_link.copyWith(linkStatus: false)],
          'other-user' => [_link.copyWith(patientHash: 'someone-else')],
          _ => [_link.copyWith(patientHash: '')],
        };
      final control = ManageChatList(userHash: 'patient-a', linkControl: links);
      addTearDown(links.dispose);
      addTearDown(control.dispose);
      await _pumpEntry(tester, control);
      expect(find.byType(LinkedChatUI), findsNothing);
    // A successful lookup with no active link offers link management, not a retry.
      expect(find.textContaining('연동이 종료되었어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
      expect(find.text('연동 관리 열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: ended link offers close back to the previous screen in English
  // Description:
  // - An ended-link entry in English offers management and Close; closing removes the entry route and returns to the original screen.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('ended link offers close back to the previous screen in English', (
    tester,
  ) async {
    final links = _Links();
    final control = ManageChatList(userHash: 'patient-a', linkControl: links);
    addTearDown(links.dispose);
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
            // Function Name: start-screen builder
            // Description: Build the button that pushes the notification entry screen.
            // Parameters: context (BuildContext): navigator lookup scope.
            // Returns: Widget; the entry button.
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LinkedChatEntryUI(
                  linkId: 17,
                  currentUserHash: 'patient-a',
                  userSetting: const UserSetting(language: 'en'),
                  control: control,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('link has ended'), findsOneWidget);
    expect(find.text('Manage links'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(LinkedChatEntryUI), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  // Function Name: entry lookup uses the injected session client for a 401
  // Description:
  // - Send link lookup through the injected authenticated client, surface its 401 through the session handler, and keep that borrowed client usable after the entry closes.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
  testWidgets('entry lookup uses the injected session client for a 401', (
    tester,
  ) async {
    var unauthorized = 0;
    final paths = <String>[];
    final client = AuthenticatedApiClient(
      inner: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{"detail":"expired"}', 401);
      }),
      tokenProvider: () async => null,
      appCheckTokenProvider: () async => null,
      appCheckRequired: false,
      onUnauthorized: () async => unauthorized += 1,
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: LinkedChatEntryUI(
          linkId: 17,
          currentUserHash: 'patient-a',
          userSetting: const UserSetting(),
          apiClient: client,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(paths.single, endsWith('/link/list'));
    expect(unauthorized, 1);
    expect(find.byType(LinkedChatUI), findsNothing);
    expect(find.textContaining('대화 상대를 확인하지 못했어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final response = await client.get(
      Uri.parse('${ApiConfig.baseUrl}/link/list'),
    );
    expect(response.statusCode, 401);
    expect(tester.takeException(), isNull);
  });
}
