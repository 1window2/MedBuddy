// File Name: link_patient_caregiver_ui_boundary_test.dart
// Role: Regression coverage for link-screen request races, patient registration, unlinking, follow-up
//   reload failures, the chat gate, aliases, and accessible dialogs.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _FakeLinkPatientCaregiver
// 역할: 연동 조회·코드 발급·등록의 완료 시점을 제어하고 별칭 변경과 폐기를 기록하는 대역.
// 주요 책임:
// - 입력 코드를 기록하고 연동 등록의 완료를 테스트가 결정하도록 대기시킨다.
// - 해제할 연결 식별자를 기록하고 연동 해제의 완료를 테스트가 결정하도록 대기시킨다.
// - 연결 식별자와 별칭 변경을 기록하고 현재 보호자 소유의 갱신 연결을 제공한다.
// 속성:
// - fakeUserHash (String): 가짜 연동 제어기에 배정할 사용자 식별자.
// - disposeCount (int): 사용자 변경 중 관찰한 폐기 호출 횟수.
class _FakeLinkPatientCaregiver extends LinkPatientCaregiver {
  final String fakeUserHash;
  final List<Completer<List<PatientCaregiverLink>>> linkRequests = [];
  final List<Completer<PatientLinkCode>> codeRequests = [];
  final List<Completer<PatientCaregiverLink>> registrationRequests = [];
  final List<String> registrationCodes = [];
  final List<Completer<PatientCaregiverLink>> unlinkRequests = [];
  final List<int> unlinkIds = [];
  final List<(int, String)> aliasUpdates = [];
  final List<(int, String)> caregiverAliasUpdates = [];
  bool failCaregiverAlias = false;
  int disposeCount = 0;

  // 함수이름: _FakeLinkPatientCaregiver
  // 함수역할:
  // - 테스트 사용자 범위와 실제 통신을 막는 HTTP 대역을 설정한다.
  // 매개변수:
  // - fakeUserHash (String): 가짜 연동 제어기에 배정할 사용자 식별자.
  // 반환값:
  // - 요청 완료를 직접 제어하는 연동 대역.
  _FakeLinkPatientCaregiver(this.fakeUserHash)
    : super(
        userHash: fakeUserHash,
        // Function Name: MockClient callback
        // Description:
        // - Complete the mocked HTTP request with status 500 and an empty JSON object without network access.
        // Parameters:
        // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
        //   consumed by this fixture.
        // Returns:
        // - Future<http.Response> with status 500.
        client: MockClient((http.Request request) async {
          return http.Response('{}', 500);
        }),
      );

  // Function Name: requestLinkScreen
  // Description:
  // - Queue a link-list request for explicit completion by the test.
  // Parameters:
  // - None.
  // Returns:
  // - The newly queued link-list Future.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() {
    final request = Completer<List<PatientCaregiverLink>>();
    linkRequests.add(request);
    return request.future;
  }

  // Function Name: generatePatientHash
  // Description:
  // - Queue invitation-code generation without completing it automatically.
  // Parameters:
  // - None.
  // Returns:
  // - The newly queued patient-code Future.
  @override
  Future<PatientLinkCode> generatePatientHash() {
    final request = Completer<PatientLinkCode>();
    codeRequests.add(request);
    return request.future;
  }

  // 함수이름: requestPatientCaregiverLink
  // 함수역할:
  // - 입력 코드를 기록하고 연동 등록의 완료를 테스트가 결정하도록 대기시킨다.
  // 매개변수:
  // - patientCode (String): 환자 연결을 위해 입력한 초대 코드.
  // 반환값:
  // - 새로 등록한 연동 요청의 Future.
  @override
  Future<PatientCaregiverLink> requestPatientCaregiverLink(String patientCode) {
    registrationCodes.add(patientCode);
    final request = Completer<PatientCaregiverLink>();
    registrationRequests.add(request);
    return request.future;
  }

  // 함수이름: requestUnlink
  // 함수역할:
  // - 해제할 연결 식별자를 기록하고 연동 해제의 완료를 테스트가 결정하도록 대기시킨다.
  // 매개변수:
  // - linkId (int): 해제할 환자·보호자 연결 식별자.
  // 반환값:
  // - 새로 등록한 해제 요청의 Future.
  @override
  Future<PatientCaregiverLink> requestUnlink(int linkId) {
    unlinkIds.add(linkId);
    final request = Completer<PatientCaregiverLink>();
    unlinkRequests.add(request);
    return request.future;
  }

  // 함수이름: savePatientAlias
  // 함수역할:
  // - 연결 식별자와 별칭 변경을 기록하고 현재 보호자 소유의 갱신 연결을 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자.
  // - patientAlias (String): 보호자가 지정한 연동 환자 표시 별칭.
  // 반환값:
  // - 지정 별칭이 반영된 활성 연결.
  @override
  Future<PatientCaregiverLink> savePatientAlias({
    required int linkId,
    required String patientAlias,
  }) async {
    aliasUpdates.add((linkId, patientAlias));
    return PatientCaregiverLink(
      linkId: linkId,
      patientHash: 'patient-a',
      caregiverHash: fakeUserHash,
      linkStatus: true,
      patientAlias: patientAlias,
    );
  }

  // 함수이름: saveCaregiverAlias
  // 함수역할: 환자가 저장한 보호자 별칭만 기록하거나 저장 실패를 재현한다.
  // 매개변수: linkId, caregiverAlias. 반환값: 갱신된 연결 또는 StateError.
  @override
  Future<PatientCaregiverLink> saveCaregiverAlias({
    required int linkId,
    required String caregiverAlias,
  }) async {
    caregiverAliasUpdates.add((linkId, caregiverAlias));
    if (failCaregiverAlias) throw StateError('Caregiver alias save failed.');
    return PatientCaregiverLink(
      linkId: linkId,
      patientHash: fakeUserHash,
      caregiverHash: 'caregiver-a',
      patientAlias: '어머니',
      caregiverAlias: caregiverAlias,
      linkStatus: true,
    );
  }

  // Function Name: dispose
  // Description:
  // - Record disposal so identity changes can be checked for duplicate cleanup.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the disposal counter increases.
  @override
  void dispose() {
    disposeCount += 1;
  }
}

// 클래스명: _FakeChatControl
// 역할: 연동 화면에서 채팅 진입 가능 여부를 결정할 활성 약 목록 대역.
// 주요 책임:
// - 선택한 연결의 채팅 진입 검사에 주입된 약 목록을 제공한다.
// 속성: medications (List<ChatMedicationContext>): 채팅 진입 검사에 반환할 약 목록.
class _FakeChatControl extends ManageLinkedChat {
  final List<ChatMedicationContext> medications;

  // 함수이름: _FakeChatControl
  // 함수역할:
  // - 채팅 가능 약 목록을 보관하고 고정 보호자 범위를 설정한다.
  // 매개변수:
  // - medications (List<ChatMedicationContext>): 가짜 제어기에 제공하는 약 관련 입력 목록.
  // 반환값:
  // - 지정 약 목록을 제공하는 채팅 제어 대역.
  _FakeChatControl(this.medications)
    : super(
        userHash: 'caregiver-a',
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 네트워크 없이 HTTP 500 상태와 빈 JSON 객체를 제공한다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - HTTP 500 응답 Future.
        client: MockClient((request) async => http.Response('{}', 500)),
      );

  // 함수이름: requestMedicationContexts
  // 함수역할:
  // - 선택한 연결의 채팅 진입 검사에 주입된 약 목록을 제공한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 생성자에 지정한 복약 문맥 목록.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => medications;
}

// 클래스명: _FailingChatControl
// 역할: 연동 화면의 채팅 진입 검사에서 약 목록 조회 실패를 재현하는 대역.
// 주요 책임:
// - 모든 연결의 약 목록 조회를 StateError로 실패시킨다.
// 속성: 추가 상태 없음; 부모 제어기에 고정 보호자와 통신 대역을 연결한다.
class _FailingChatControl extends ManageLinkedChat {
  // 함수이름: _FailingChatControl
  // 함수역할:
  // - 고정 보호자 범위와 실제 통신을 막는 HTTP 대역을 설정한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 약 목록 조회가 항상 실패하는 채팅 제어 대역.
  _FailingChatControl()
    : super(
        userHash: 'caregiver-a',
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 네트워크 없이 HTTP 500 상태와 빈 JSON 객체를 제공한다.
        // 매개변수:
        // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - HTTP 500 응답 Future.
        client: MockClient((request) async => http.Response('{}', 500)),
      );

  // 함수이름: requestMedicationContexts
  // 함수역할:
  // - 약 유무를 알 수 없는 조회 실패를 재현한다.
  // 매개변수:
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - StateError로 실패하는 Future.
  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => throw StateError('Medication context lookup failed.');
}

// 클래스명: _RouteRecorder
// 역할: 화면을 그리지 않고도 새 경로가 열렸는지 확인할 수 있게 push된 경로를 기록한다.
// 속성:
// - pushedRoutes (List<Route<dynamic>>): 관찰한 Navigator에 push된 경로.
// 주요 책임: Navigator의 경로 push를 순서대로 수집해 화면 이동 여부를 검증한다.
class _RouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  // 함수이름: didPush
  // 함수역할: push된 경로를 순서대로 기록한다.
  // 매개변수: route: 새로 열린 경로, previousRoute: 그 아래의 경로.
  // 반환값: 없음.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

const _caregiverLink = PatientCaregiverLink(
  linkId: 1,
  patientHash: 'patient-a',
  caregiverHash: 'caregiver-a',
  linkStatus: true,
);

const _activeMedication = ChatMedicationContext(
  medicationId: 91,
  medicationName: '테스트정',
  dosagePerTime: '1정',
);

// 함수이름: main
// 함수역할:
// - 연동 화면 요청 경쟁, 환자 등록·해제, 재조회 실패, 채팅 진입, 별칭과 접근성 대화상자 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 테스트 전에 메모리 설정 저장소를 비워 사용자 캐시를 격리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 설정 저장소가 빈 상태로 초기화된다.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 복약 대화는 기본으로 노출되고 활성 약이 없을 때 이유를 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('복약 대화는 기본으로 노출되고 활성 약이 없을 때 이유를 안내한다', (tester) async {
    _useLinkScreenViewport(tester);
    const link = PatientCaregiverLink(
      linkId: 1,
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
      linkStatus: true,
    );
    final hiddenLinkControl = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          key: const ValueKey('chat-hidden-link-screen'),
          initialUserHash: 'caregiver-a',
          // 함수이름: controlFactory 콜백
          // 함수역할:
          // - 캡처한 연동 제어기를 재사용해 테스트가 응답 시점을 제어하게 한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          controlFactory: (_) => hiddenLinkControl,
        ),
      ),
    );
    await tester.pump();
    hiddenLinkControl.linkRequests.single.complete(const [link]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    // 기본 목록은 일상 동작만 표시하고, 식별자와 연동 해제는 펼쳤을 때 노출한다.
    expect(find.text('patient-a'), findsNothing);
    expect(find.text('연동 해제'), findsNothing);
    await tester.tap(find.text('연동 관리'));
    await tester.pumpAndSettle();
    expect(find.text('patient-a'), findsOneWidget);
    expect(find.text('연동 해제'), findsOneWidget);
    await tester.tap(find.text('연동 관리'));
    await tester.pumpAndSettle();
    expect(find.text('patient-a'), findsNothing);

    final disabledLinkControl = _FakeLinkPatientCaregiver('caregiver-a');
    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          key: const ValueKey('chat-disabled-link-screen'),
          initialUserHash: 'caregiver-a',
          // 함수이름: controlFactory 콜백
          // 함수역할:
          // - 캡처한 연동 제어기를 재사용해 테스트가 응답 시점을 제어하게 한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          controlFactory: (_) => disabledLinkControl,
          // 함수이름: chatControlFactory 콜백
          // 함수역할:
          // - 지정한 활성 약 상태의 채팅 제어기 대역을 제공한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          chatControlFactory: (_) => _FakeChatControl(const []),
        ),
      ),
    );
    await tester.pump();
    disabledLinkControl.linkRequests.single.complete(const [link]);
    await tester.pumpAndSettle();

    final disabledChatButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chat_bubble_outline),
    );
    expect(disabledChatButton.onPressed, isNotNull);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chat_bubble_outline),
    );
    await tester.pump();
    expect(find.text('현재 복용 중인 약이 없어 채팅을 시작할 수 없습니다.'), findsOneWidget);

    final enabledLinkControl = _FakeLinkPatientCaregiver('caregiver-a');
    final chatControl = _FakeChatControl(const [
      ChatMedicationContext(
        medicationId: 91,
        medicationName: '테스트정',
        dosagePerTime: '1정',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          key: const ValueKey('chat-enabled-link-screen'),
          initialUserHash: 'caregiver-a',
          // 함수이름: controlFactory 콜백
          // 함수역할:
          // - 캡처한 연동 제어기를 재사용해 테스트가 응답 시점을 제어하게 한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          controlFactory: (_) => enabledLinkControl,
          // 함수이름: chatControlFactory 콜백
          // 함수역할:
          // - 지정한 활성 약 상태의 채팅 제어기 대역을 제공한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          chatControlFactory: (_) => chatControl,
        ),
      ),
    );
    await tester.pump();
    enabledLinkControl.linkRequests.single.complete(const [link]);
    await tester.pumpAndSettle();

    final chatButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chat_bubble_outline),
    );
    expect(chatButton.onPressed, isNotNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 약 목록 조회에 실패한 연동은 "복용 중인 약 없음"으로 막지 않고 채팅 화면을 연다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('약 목록 조회에 실패한 연동은 채팅을 막지 않는다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');
    final routes = _RouteRecorder();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // 함수이름: controlFactory 콜백
          // 함수역할:
          // - 캡처한 연동 제어기를 재사용해 테스트가 응답 시점을 제어하게 한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          controlFactory: (_) => control,
          // 함수이름: chatControlFactory 콜백
          // 함수역할:
          // - 약 목록 조회가 실패하는 채팅 제어기 대역을 제공한다.
          // 매개변수:
          // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
          // 반환값:
          // - 설정된 제어기 대역.
          chatControlFactory: (_) => _FailingChatControl(),
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [_caregiverLink]);
    await tester.pumpAndSettle();

    final chatButton = find.widgetWithIcon(
      IconButton,
      Icons.chat_bubble_outline,
    );
    expect(tester.widget<IconButton>(chatButton).tooltip, '복약 대화');
    expect(routes.pushedRoutes, hasLength(1));

    // 채팅 화면은 그리지 않고 경로가 열렸는지만 확인한다. 안내만 띄우는 경로는 push하지 않는다.
    await tester.tap(chatButton);
    expect(routes.pushedRoutes, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 조회와 코드 발급은 상위 화면에 연동 변경을 알리지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('조회와 코드 발급은 연동 변경을 알리지 않는다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('patient-a');
    var updates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'patient-a',
          controlFactory: (_) => control,
          onLinksChanged: () => updates++,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();
    expect(updates, 0);

    await tester.tap(find.text('환자 코드 생성'));
    await tester.pump();
    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'TEST1234',
        patientHash: 'patient-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const []);
    await tester.pumpAndSettle();

    expect(updates, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 만료된 환자 코드는 흐리게 표시하고 복사를 막으며, "새 코드 만들기"로 같은 발급 흐름을 다시 실행한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('만료된 환자 코드는 새 코드 만들기를 제공한다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('patient-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'patient-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 코드 생성'));
    await tester.pump();
    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'OLD12345',
        patientHash: 'patient-a',
        expiresAt: DateTime.utc(2000),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('코드가 만료되었어요. 새 코드를 만들어 주세요.'), findsOneWidget);
    expect(find.textContaining('남은 시간'), findsNothing);
    final code = tester.widget<Text>(
      find.byKey(const ValueKey('patientCodeValue')),
    );
    expect(code.style!.decoration, TextDecoration.lineThrough);
    await tester.tap(find.text('OLD12345'));
    await tester.pump();
    expect(find.text('코드를 복사했습니다.'), findsNothing);
    // 닫기 버튼은 최소 48dp 터치 영역을 가진다.
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(IconButton),
        ),
      ),
      const Size(48, 48),
    );

    await tester.tap(find.byKey(const ValueKey('patientCodeRegenerate')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(control.codeRequests, hasLength(2));
    control.codeRequests.last.complete(
      PatientLinkCode(
        code: 'NEW12345',
        patientHash: 'patient-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NEW12345'), findsOneWidget);
    expect(find.text('(코드를 누르면 복사됩니다)'), findsOneWidget);
    expect(find.byKey(const ValueKey('patientCodeRegenerate')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reloadFails in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 연동 해제가 성공하면 목록에서 바로 빼고 상위 화면에 알리며, 이어지는 재조회가 실패해도 해제 결과를 오류로 바꾸지 않는다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('연동 해제 결과를 반영한다 (재조회 실패: $reloadFails)', (tester) async {
      _useLinkScreenViewport(tester);
      SharedPreferences.setMockInitialValues({
        'caregiver_patient_label.caregiver-a.patient-a': '어머니',
      });
      final control = _FakeLinkPatientCaregiver('caregiver-a');
      var updates = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: LinkPatientCaregiverUI(
            initialUserHash: 'caregiver-a',
            controlFactory: (_) => control,
            chatControlFactory: (_) =>
                _FakeChatControl(const [_activeMedication]),
            onLinksChanged: () => updates++,
          ),
        ),
      );
      await tester.pump();
      control.linkRequests.single.complete(const [_caregiverLink]);
      await tester.pumpAndSettle();
      expect(find.text('어머니'), findsOneWidget);
      expect(updates, 0);

      await tester.tap(find.text('연동 관리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('연동 해제'));
      await tester.pumpAndSettle();
      expect(control.unlinkIds, isEmpty);
      await tester.tap(find.byKey(const Key('unlink-confirm')));
      await tester.pump();
      expect(control.unlinkIds, [1]);

      control.unlinkRequests.single.complete(
        _caregiverLink.copyWith(linkStatus: false),
      );
      // 재조회가 진행 중이라 진행 표시가 계속 움직이므로 정해진 횟수만 프레임을 진행한다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // 재조회 응답을 기다리지 않고 해제 결과를 먼저 반영하고 알린다.
      expect(updates, 1);
      expect(find.text('어머니'), findsNothing);
      expect(find.text('환자-보호자 연동을 해제했습니다.'), findsOneWidget);
      expect(control.linkRequests, hasLength(2));

      if (reloadFails) {
        control.linkRequests.last.completeError(
          StateError('Link lookup failed.'),
        );
      } else {
        control.linkRequests.last.complete(const []);
      }
      await tester.pumpAndSettle();

      expect(find.text('환자-보호자 연동을 해제했습니다.'), findsOneWidget);
      expect(find.text('Link lookup failed.'), findsNothing);
      expect(find.text('어머니'), findsNothing);
      expect(find.text('연동 관리'), findsNothing);
      expect(updates, 1);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('caregiver_patient_label.caregiver-a.patient-a'),
        isNull,
      );
      // 요청이 끝났으므로 다음 작업을 다시 받을 수 있다.
      expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 재조회가 실패해도 등록 성공을 안내하고 확인 후 등록된 환자를 보여준다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('등록 뒤 재조회가 실패해도 등록 성공으로 처리한다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');
    var updates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
          chatControlFactory: (_) =>
              _FakeChatControl(const [_activeMedication]),
          onLinksChanged: () => updates++,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 관리 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('patient-link-code')),
      'ABCD1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();
    control.registrationRequests.single.complete(_caregiverLink);
    await tester.pump();
    expect(updates, 1);
    expect(control.linkRequests, hasLength(2));

    control.linkRequests.last.completeError(StateError('Link lookup failed.'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient-link-code')), findsNothing);
    expect(control.registrationCodes, ['ABCD1234']);
    expect(find.byKey(const Key('patient-link-result-dialog')), findsOneWidget);
    expect(find.text('연동 완료'), findsOneWidget);
    expect(find.text('Link lookup failed.'), findsNothing);
    await tester.tap(find.byKey(const Key('patient-link-result-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('환자-보호자 연동을 등록했습니다.'), findsOneWidget);
    // 재조회 없이도 서버가 돌려준 연동이 목록에 보인다.
    expect(find.text('환자 NT-A'), findsOneWidget);
    expect(updates, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영어 화면의 보호자는 영어 기본 환자 이름을 보고, 그 이름이 별칭 입력란에 채워지거나 서버 별칭으로 저장되지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('English caregiver sees an English default patient name', (
    tester,
  ) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          userSetting: const UserSetting(language: 'en'),
          controlFactory: (_) => control,
          chatControlFactory: (_) =>
              _FakeChatControl(const [_activeMedication]),
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [_caregiverLink]);
    await tester.pumpAndSettle();

    expect(find.text('Patient NT-A'), findsOneWidget);
    expect(find.text('환자 NT-A'), findsNothing);

    await tester.tap(find.byTooltip('Edit patient display name'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(control.aliasUpdates, [(1, '')]);
    expect(find.text('Restored the default name.'), findsOneWidget);
    expect(find.text('Patient NT-A'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 보호자가 환자 별칭을 지우면 기본 이름으로 돌아갔다고 안내하고 목록에 기본 이름을 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보호자가 환자 표시 이름을 지우면 기본 이름으로 돌아간다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');
    var updates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
          chatControlFactory: (_) =>
              _FakeChatControl(const [_activeMedication]),
          onLinksChanged: () => updates++,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete([
      _caregiverLink.copyWith(patientAlias: '어머니'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('어머니'), findsOneWidget);
    updates = 0;

    await tester.tap(find.byTooltip('환자 표시 이름 수정'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '어머니',
    );
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(control.aliasUpdates, [(1, '')]);
    expect(find.text('기본 이름으로 변경했습니다.'), findsOneWidget);
    expect(find.text('환자 NT-A 표시 이름을 저장했습니다.'), findsNothing);
    expect(find.text('환자 NT-A'), findsOneWidget);
    expect(find.text('어머니'), findsNothing);
    expect(updates, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 연동 요청 진행 중에는 중복 명령을 비활성화하고 완료 후 다시 허용하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('link actions stay disabled while one request is in flight', (
    tester,
  ) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    expect(control.linkRequests, hasLength(1));

    const link = PatientCaregiverLink(
      linkId: 1,
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
      linkStatus: true,
    );
    control.linkRequests.single.complete(const [link]);
    await tester.pump();

    await tester.tap(find.text('연동 관리'));
    await tester.pumpAndSettle();
    final generateButton = find.byType(OutlinedButton).first;
    expect(tester.widget<OutlinedButton>(generateButton).onPressed, isNotNull);
    await tester.tap(generateButton);
    await tester.pump();

    expect(control.codeRequests, hasLength(1));
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.medication_outlined),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_back).first,
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(generateButton, warnIfMissed: false);
    await tester.pump();
    expect(control.codeRequests, hasLength(1));

    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'TEST1234',
        patientHash: 'caregiver-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST1234'), findsOneWidget);
    final warningText = find.text(
      '\uD574\uB2F9 \uCF54\uB4DC\uB97C \uBCF4\uD638\uC790 \uC678\n'
      '\uB2E4\uB978 \uC0AC\uB78C\uACFC \uACF5\uC720\uD558\uC9C0 \uB9C8\uC138\uC694!',
    );
    expect(warningText, findsOneWidget);
    expect(tester.widget<Text>(warningText).maxLines, 2);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const [link]);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    expect(control.disposeCount, 1);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 이전 사용자 조회가 늦게 끝나도 현재 사용자의 연동 상태를 덮어쓰지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('stale identity response cannot replace the current link state', (
    tester,
  ) async {
    _useLinkScreenViewport(tester);
    final oldControl = _FakeLinkPatientCaregiver('caregiver-old');
    final currentControl = _FakeLinkPatientCaregiver('caregiver-current');
    final createdHashes = <String>[];

    // Function Name: createControl
    // Description:
    // - Record requested identities and select the old or current link-control fixture.
    // Parameters:
    // - userHash (String): User identity used to select a scoped control.
    // Returns:
    // - The matching fake control; unexpected user hashes throw StateError.
    LinkPatientCaregiver createControl(String userHash) {
      createdHashes.add(userHash);
      return switch (userHash) {
        'caregiver-old' => oldControl,
        'caregiver-current' => currentControl,
        _ => throw StateError('Unexpected user hash: $userHash'),
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-old',
          controlFactory: createControl,
        ),
      ),
    );
    await tester.pump();
    expect(oldControl.linkRequests, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-current',
          controlFactory: createControl,
        ),
      ),
    );
    await tester.pump();

    expect(createdHashes, ['caregiver-old', 'caregiver-current']);
    expect(oldControl.disposeCount, 1);
    expect(currentControl.linkRequests, hasLength(1));

    currentControl.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 2,
        patientHash: 'patient-current',
        caregiverHash: 'caregiver-current',
        linkStatus: true,
      ),
    ]);
    await tester.pump();
    await tester.tap(find.text('연동 관리'));
    await tester.pumpAndSettle();
    expect(find.text('patient-current'), findsOneWidget);

    oldControl.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-stale',
        caregiverHash: 'caregiver-old',
        linkStatus: true,
      ),
    ]);
    await tester.pump();

    expect(find.text('patient-current'), findsOneWidget);
    expect(find.text('patient-stale'), findsNothing);
    expect(oldControl.disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(oldControl.disposeCount, 1);
    expect(currentControl.disposeCount, 1);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자 표시 이름 편집을 취소해도 화면이 유지된다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자 표시 이름 편집을 취소해도 화면이 유지된다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-a',
        caregiverHash: 'caregiver-a',
        linkStatus: true,
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('환자 표시 이름 수정'));
    await tester.pumpAndSettle();
    expect(find.text('환자 표시 이름'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(find.text('환자 표시 이름'), findsNothing);
    expect(find.text('환자 NT-A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자 표시 이름 저장 결과는 하단에 잠시 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자 표시 이름 저장 결과는 하단에 잠시 안내한다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-a',
        caregiverHash: 'caregiver-a',
        linkStatus: true,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('총 1개의 연동이 있습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('환자 표시 이름 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '어머니');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('총 1개의 연동이 있습니다.'), findsOneWidget);
    expect(find.text('어머니 표시 이름을 저장했습니다.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('어머니 표시 이름을 저장했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['save', 'cancel', 'clear', 'failure', 'switch']) {
    // 함수이름: 환자 보호자 별칭 편집 테스트
    // 함수역할: 저장·취소·해제·실패와 입력 중 계정 변경 시 화면 및 요청을 검증한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('patient caregiver alias $action', (tester) async {
      _useLinkScreenViewport(tester);
      final control = _FakeLinkPatientCaregiver('patient-a')
        ..failCaregiverAlias = action == 'failure';
      final other = _FakeLinkPatientCaregiver('patient-b');
      var updates = 0;
      // 함수이름: screen
      // 함수역할: 계정별 연결 제어기를 가진 동일 화면을 구성한다.
      // 매개변수: user. 반환값: 테스트 앱.
      Widget screen(String user) => MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: user,
          controlFactory: (hash) => hash == 'patient-a' ? control : other,
          onLinksChanged: () => updates++,
        ),
      );
      await tester.pumpWidget(screen('patient-a'));
      await tester.pump();
      control.linkRequests.single.complete(const [
        PatientCaregiverLink(
          linkId: 1,
          patientHash: 'patient-a',
          caregiverHash: 'caregiver-a',
          patientAlias: '어머니',
          caregiverAlias: '이전 이름',
          linkStatus: true,
        ),
      ]);
      await tester.pumpAndSettle();
      updates = 0;
      expect(find.byTooltip('환자 표시 이름 수정'), findsNothing);
      await tester.tap(find.byTooltip('보호자 표시 이름 수정'));
      await tester.pumpAndSettle();
      expect(find.text('보호자 표시 이름'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 20);
      await tester.enterText(
        find.byType(TextFormField),
        action == 'clear' ? '' : '우리 딸',
      );
      if (action == 'switch') {
        await tester.pumpWidget(screen('patient-b'));
        await tester.pump();
        other.linkRequests.single.complete([]);
        await tester.pumpAndSettle();
      }
      await tester.tap(
        action == 'cancel'
            ? find.widgetWithText(TextButton, '취소')
            : find.widgetWithText(FilledButton, '저장'),
      );
      await tester.pumpAndSettle();
      expect(control.aliasUpdates, isEmpty);
      expect(other.caregiverAliasUpdates, isEmpty);
      if (action == 'cancel' || action == 'switch') {
        expect(control.caregiverAliasUpdates, isEmpty);
      } else {
        expect(control.caregiverAliasUpdates, [
          (1, action == 'clear' ? '' : '우리 딸'),
        ]);
      }
      if (action == 'save') {
        expect(find.text('우리 딸'), findsOneWidget);
        expect(updates, 1);
      } else if (action == 'cancel' || action == 'failure') {
        expect(find.text('이전 이름'), findsOneWidget);
        expect(find.text('우리 딸'), findsNothing);
        expect(updates, 0);
      } else if (action == 'clear') {
        expect(find.text('이전 이름'), findsNothing);
        expect(find.text('기본 이름으로 변경했습니다.'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 코드를 검증하고 중복 제출·완료 확인으로 요청이나 화면 종료가 반복되지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자 코드를 검증하고 진행 중인 등록 요청을 중복 전송하지 않는다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 관리 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('patient-link-code')), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();

    expect(find.text('환자 코드는 영문과 숫자 8자리로 입력해 주세요.'), findsOneWidget);
    expect(control.registrationRequests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('patient-link-code')),
      'abcd1234',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('patient-link-code')))
          .controller
          ?.text,
      'ABCD1234',
    );

    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();
    expect(control.registrationCodes, ['ABCD1234']);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(control.registrationRequests, hasLength(1));

    const link = PatientCaregiverLink(
      linkId: 3,
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
      linkStatus: true,
    );
    control.registrationRequests.single.complete(link);
    await tester.pump();
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const [link]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient-link-code')), findsNothing);
    expect(find.byKey(const Key('patient-link-result-dialog')), findsOneWidget);
    expect(find.text('연동 완료'), findsOneWidget);
    // 같은 확인 콜백이 연속 호출되어도 아래 연동 화면은 닫히지 않는다.
    final acknowledge = tester
        .widget<FilledButton>(
          find.byKey(const Key('patient-link-result-confirm')),
        )
        .onPressed!;
    acknowledge();
    acknowledge();
    await tester.pumpAndSettle();
    expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(control.registrationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final isEnglish in [false, true]) {
    for (final succeeds in [false, true]) {
      // 함수이름: 등록 결과 접근성 테스트
      // 함수역할: 한·영 성공·실패 창이 작은 화면과 큰 글자에서 중앙에 표시되는지 확인한다.
      // 매개변수: tester (WidgetTester): 위젯 조작기. 반환값: 검증 완료 Future.
      testWidgets('등록 결과 중앙 안내 언어=$isEnglish 성공=$succeeds', (tester) async {
        tester.view.physicalSize = const Size(320, 520);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final control = _FakeLinkPatientCaregiver('caregiver-a');
        await tester.pumpWidget(
          _registrationTestApp(control, isEnglish: isEnglish, textScale: 2),
        );
        await tester.pump();
        control.linkRequests.single.complete([]);
        await tester.pumpAndSettle();
        await _submitPatientCode(tester, isEnglish: isEnglish);
        if (succeeds) {
          control.registrationRequests.single.complete(_caregiverLink);
          await tester.pump();
          control.linkRequests.last.complete([_caregiverLink]);
        } else {
          control.registrationRequests.single.completeError(
            TimeoutException('registration timeout'),
          );
        }
        await tester.pumpAndSettle();

        final result = find.byKey(const Key('patient-link-result-dialog'));
        expect(result, findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.descendant(
            of: result,
            matching: find.text(
              succeeds
                  ? (isEnglish ? 'Link complete' : '연동 완료')
                  : (isEnglish ? 'Unable to link' : '연동 실패'),
            ),
          ),
          findsOneWidget,
        );
        expect(tester.getCenter(find.byType(Dialog)).dx, closeTo(160, 1));
        expect(
          find.descendant(
            of: result,
            matching: find.byType(SingleChildScrollView),
          ),
          findsOneWidget,
        );
        final confirm = find.byKey(const Key('patient-link-result-confirm'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(result, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final failure in [
    ApiRequestException(
      'Patient registration failed',
      statusCode: 400,
      detail: 'Patient code is invalid',
    ),
    ApiRequestException(
      'Patient registration failed',
      statusCode: 409,
      detail: 'Patient code was already used',
    ),
    ApiRequestException(
      'Patient registration failed',
      statusCode: 400,
      detail: 'Cannot link to the same user',
    ),
    ApiRequestException('Patient registration failed', statusCode: 401),
    TimeoutException('registration timeout'),
  ]) {
    // 함수이름: 등록 실패 재시도 테스트
    // 함수역할: 코드·권한·통신 오류를 중앙에 안내하고 확인 후 같은 입력으로 재시도한다.
    // 매개변수: tester (WidgetTester): 위젯 조작기. 반환값: 검증 완료 Future.
    testWidgets('등록 실패는 원인을 안내하고 입력을 보존한다: $failure', (tester) async {
      _useLinkScreenViewport(tester);
      final control = _FakeLinkPatientCaregiver('caregiver-a');
      var updates = 0;
      // 함수이름: onLinksChanged
      // 함수역할: 등록 성공의 상위 알림 횟수를 기록한다.
      // 매개변수: 없음. 반환값: 없음.
      void onLinksChanged() => updates++;
      await tester.pumpWidget(
        _registrationTestApp(control, onLinksChanged: onLinksChanged),
      );
      await tester.pump();
      control.linkRequests.single.complete([]);
      await tester.pumpAndSettle();
      await _submitPatientCode(tester);
      control.registrationRequests.single.completeError(failure);
      await tester.pumpAndSettle();

      final result = find.byKey(const Key('patient-link-result-dialog'));
      expect(find.text('연동 실패'), findsOneWidget);
      expect(
        find.descendant(
          of: result,
          matching: find.text(
            UserFacingErrorMessage.resolve(failure, isEnglish: false),
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(updates, 0);
      expect(control.linkRequests, hasLength(1));
      await tester.tap(find.byKey(const Key('patient-link-result-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('patient-link-code')))
            .controller!
            .text,
        'ABCD1234',
      );
      await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
      await tester.pump();
      control.registrationRequests.last.complete(_caregiverLink);
      await tester.pump();
      control.linkRequests.last.complete([_caregiverLink]);
      await tester.pumpAndSettle();
      expect(result, findsOneWidget);
      expect(find.text('연동 완료'), findsOneWidget);
      expect(control.registrationCodes, ['ABCD1234', 'ABCD1234']);
      expect(updates, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final phase in [
    'pending-success',
    'pending-failure',
    'reload',
    'result',
  ]) {
    // 함수이름: 등록 계정 변경 테스트
    // 함수역할: 요청·재조회·결과 안내 중 계정 변경 시 이전 창과 응답이 새 계정에 영향을 주지 않는다.
    // 매개변수: tester (WidgetTester): 위젯 조작기. 반환값: 검증 완료 Future.
    testWidgets('계정 변경 후 이전 등록 결과를 무시한다: $phase', (tester) async {
      _useLinkScreenViewport(tester);
      final oldControl = _FakeLinkPatientCaregiver('caregiver-a');
      final currentControl = _FakeLinkPatientCaregiver('caregiver-b');
      var updates = 0;
      // 함수이름: onLinksChanged
      // 함수역할: 유효한 계정의 변경 알림 횟수를 기록한다.
      // 매개변수: 없음. 반환값: 없음.
      void onLinksChanged() => updates++;

      await tester.pumpWidget(
        _registrationTestApp(oldControl, onLinksChanged: onLinksChanged),
      );
      await tester.pump();
      oldControl.linkRequests.single.complete([]);
      await tester.pumpAndSettle();
      await _submitPatientCode(tester);
      if (phase == 'reload' || phase == 'result') {
        oldControl.registrationRequests.single.complete(_caregiverLink);
        await tester.pump();
        if (phase == 'result') {
          oldControl.linkRequests.last.complete([_caregiverLink]);
          await tester.pumpAndSettle();
          expect(find.text('연동 완료'), findsOneWidget);
        }
      }
      updates = 0;
      await tester.pumpWidget(
        _registrationTestApp(currentControl, onLinksChanged: onLinksChanged),
      );
      await tester.pump();
      currentControl.linkRequests.single.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await _submitPatientCode(tester);

      if (phase == 'pending-success') {
        oldControl.registrationRequests.single.complete(_caregiverLink);
      } else if (phase == 'pending-failure') {
        oldControl.registrationRequests.single.completeError(
          StateError('이전 계정의 오류입니다.'),
        );
      } else if (phase == 'reload') {
        oldControl.linkRequests.last.complete([_caregiverLink]);
      }
      await tester.pump();
      expect(find.byKey(const Key('patient-link-result-dialog')), findsNothing);
      expect(find.byKey(const Key('patient-link-code')), findsOneWidget);
      expect(find.text('이전 계정의 오류입니다.'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(updates, 0);
      expect(oldControl.disposeCount, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      currentControl.registrationRequests.single.completeError(
        StateError('현재 계정의 오류입니다.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('연동 실패'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('patient-link-result-dialog')),
          matching: find.text('현재 계정의 오류입니다.'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 등록 창 중복 열기 테스트
  // 함수역할: 같은 열기 콜백의 연속 실행으로 입력 창이나 결과 창이 겹치지 않는다.
  // 매개변수: tester (WidgetTester): 위젯 조작기. 반환값: 검증 완료 Future.
  testWidgets('연속 등록 창 열기는 하나의 결과 창만 만든다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');
    await tester.pumpWidget(_registrationTestApp(control));
    await tester.pump();
    control.linkRequests.single.complete([]);
    await tester.pumpAndSettle();
    final openButton = find.widgetWithText(OutlinedButton, '환자 관리 등록');
    final open = tester.widget<OutlinedButton>(openButton).onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('patient-link-code')),
      'ABCD1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();
    control.registrationRequests.single.complete(_caregiverLink);
    await tester.pump();
    control.linkRequests.last.complete([_caregiverLink]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('patient-link-result-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('patient-link-result-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final departure in [
    'dismiss',
    'dismiss-transition',
    'dispose',
    'owner-dispose',
  ]) {
    for (final succeeds in [true, false]) {
      // 함수이름: 종료된 등록 창 테스트
      // 함수역할: 창 취소·전체 종료·부모 종료 뒤 응답이 다른 화면에 결과를 표시하지 않는다.
      // 매개변수: tester (WidgetTester): 위젯 조작기. 반환값: 검증 완료 Future.
      testWidgets('종료된 등록 결과를 표시하지 않는다: $departure 성공=$succeeds', (
        tester,
      ) async {
        _useLinkScreenViewport(tester);
        final control = _FakeLinkPatientCaregiver('caregiver-a');
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _registrationTestApp(control, navigatorKey: navigatorKey),
        );
        await tester.pump();
        control.linkRequests.single.complete([]);
        await tester.pumpAndSettle();
        await _submitPatientCode(tester);
        if (departure.startsWith('dismiss')) {
          navigatorKey.currentState!.pop();
          if (departure == 'dismiss') {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        } else if (departure == 'dispose') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await tester.pumpWidget(
            MaterialApp(navigatorKey: navigatorKey, home: const Text('다른 화면')),
          );
          await tester.pump();
        }
        if (succeeds) {
          control.registrationRequests.single.complete(_caregiverLink);
          await tester.pump();
          if (departure.startsWith('dismiss')) {
            control.linkRequests.last.complete([_caregiverLink]);
          }
        } else {
          control.registrationRequests.single.completeError(
            StateError('종료 후 오류'),
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('patient-link-result-dialog')),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        if (departure.startsWith('dismiss')) {
          expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
        } else {
          expect(control.linkRequests, hasLength(1));
          expect(control.disposeCount, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자 등록 창은 작은 화면과 큰 글자에서도 넘치지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('환자 등록 창은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 1.4배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 관리 등록'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 연동 화면과 환자 코드 창은 작은 화면과 2배 글자에서도 스크롤된다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('연동 화면과 환자 코드 창은 작은 화면과 2배 글자에서도 스크롤된다', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final control = _FakeLinkPatientCaregiver('patient-a');

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
        home: LinkPatientCaregiverUI(
          initialUserHash: 'patient-a',
          // Function Name: controlFactory callback
          // Description:
          // - Reuse the captured link control so the test owns response timing.
          // Parameters:
          // - _ (String): Patient/user scope; the fixed fixture ignores it.
          // Returns:
          // - The configured control fixture.
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    // 역할 안내는 13pt 이상이며 큰 글씨에서도 줄임표로 잘리지 않는다.
    for (final role in ['약을 복용하는 환자', '복약을 확인하는 보호자']) {
      final roleText = find.text(role);
      expect(tester.widget<Text>(roleText).style!.fontSize, 13);
      expect(
        tester.renderObject<RenderParagraph>(roleText).didExceedMaxLines,
        isFalse,
      );
    }
    final generateButton = find.text('환자 코드 생성');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pump();
    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'TEST1234',
        patientHash: 'patient-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEST1234'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

// Function Name: _useLinkScreenViewport
// Description:
// - Use a 430 by 900 logical link-screen viewport and restore it after the test.
// Parameters:
// - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
// Returns:
// - No value; viewport overrides and cleanup hooks are installed.
void _useLinkScreenViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 함수이름: _registrationTestApp
// 함수역할: 등록 결과 테스트의 계정·언어·큰 글씨와 네트워크 대역을 구성한다.
// 매개변수: control: 계정 대역; isEnglish/textScale: 표시 설정; onLinksChanged: 변경 알림;
// - navigatorKey: 종료 동작에 사용할 탐색 키.
// 반환값: 외부 통신 없이 등록 흐름을 검증할 앱.
Widget _registrationTestApp(
  _FakeLinkPatientCaregiver control, {
  bool isEnglish = false,
  double textScale = 1,
  VoidCallback? onLinksChanged,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    // 함수이름: builder 콜백
    // 함수역할: 대화상자에도 테스트 글씨 배율을 적용한다.
    // 매개변수: context, child: 앱 하위 트리. 반환값: 글씨 배율이 설정된 화면.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LinkPatientCaregiverUI(
      initialUserHash: control.fakeUserHash,
      userSetting: UserSetting(language: isEnglish ? 'en' : 'ko'),
      // 함수이름: controlFactory 콜백
      // 함수역할: 완료 시점을 제어할 연동 대역을 제공한다.
      // 매개변수: _: 사용자 해시. 반환값: 지정 연동 대역.
      controlFactory: (_) => control,
      // 함수이름: chatControlFactory 콜백
      // 함수역할: 등록 후 조회의 외부 통신을 막는다.
      // 매개변수: _: 사용자 해시. 반환값: 빈 약 목록 대역.
      chatControlFactory: (_) => _FakeChatControl(const []),
      onLinksChanged: onLinksChanged,
    ),
  );
}

// 함수이름: _submitPatientCode
// 함수역할: 등록 창을 열고 유효한 코드를 제출하되 서버 응답은 대기시킨다.
// 매개변수: tester: 위젯 조작기; isEnglish: 영어 버튼 사용 여부.
// 반환값: 등록 요청 시작까지 완료되는 Future<void>.
Future<void> _submitPatientCode(
  WidgetTester tester, {
  bool isEnglish = false,
}) async {
  final open = find.text(isEnglish ? 'Register patient' : '환자 관리 등록');
  await tester.ensureVisible(open);
  await tester.pumpAndSettle();
  await tester.tap(open);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('patient-link-code')),
    'ABCD1234',
  );
  final submit = find.widgetWithText(
    FilledButton,
    isEnglish ? 'Register' : '등록하기',
  );
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pump();
}
