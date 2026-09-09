// File Name: link_patient_caregiver_ui_boundary_test.dart
// Role: Regression coverage for link-screen request races, patient registration, aliases, and
//   accessible dialogs.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _FakeLinkPatientCaregiver
// 역할: 연동 조회·코드 발급·등록의 완료 시점을 제어하고 별칭 변경과 폐기를 기록하는 대역.
// 주요 책임:
// - 입력 코드를 기록하고 연동 등록의 완료를 테스트가 결정하도록 대기시킨다.
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
  final List<(int, String)> aliasUpdates = [];
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

// 함수이름: main
// 함수역할:
// - 연동 화면 요청 경쟁, 환자 등록, 별칭과 접근성 대화상자 검증 사례와 테스트 대역을 등록한다.
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
  // - 기대 동작: 복약 대화는 실험 기능이 켜지면 노출되고 활성 약이 없을 때 이유를 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('복약 대화는 실험 기능이 켜지면 노출되고 활성 약이 없을 때 이유를 안내한다', (tester) async {
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
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

    final disabledLinkControl = _FakeLinkPatientCaregiver('caregiver-a');
    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          key: const ValueKey('chat-disabled-link-screen'),
          initialUserHash: 'caregiver-a',
          chatLabEnabled: true,
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
          chatLabEnabled: true,
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
            find.widgetWithIcon(IconButton, Icons.close).first,
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환자 코드를 검증하고 진행 중인 등록 요청을 중복 전송하지 않는다.
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
    expect(tester.takeException(), isNull);
  });

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
