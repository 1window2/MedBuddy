// 알림 진입에서도 연동별 역할·별칭을 복원하고 조회 실패 시 채팅을 열지 않는지 검증한다.
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

class _Links extends LinkPatientCaregiver {
  _Links() : super(client: MockClient((_) async => http.Response('{}', 200)));

  List<PatientCaregiverLink> result = const [];
  bool fail = false;
  int requests = 0;
  Completer<List<PatientCaregiverLink>>? pending;

  // 실제 환자 데이터나 네트워크 없이 지연·실패·재시도를 재현한다.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    requests++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return result;
  }
}

const _link = PatientCaregiverLink(
  linkId: 17,
  patientHash: 'patient-a',
  caregiverHash: 'caregiver-a',
  patientAlias: '환자 별칭',
  caregiverAlias: '보호자 별칭',
  linkStatus: true,
);

// 알림에는 연결 ID만 전달하고 화면이 직접 상대 정보와 역할을 확인하게 한다.
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

// 채팅의 실시간 연결까지 종료하고 테스트 환경의 네트워크 제한 타이머를 정리한다.
Future<void> _closeEntry(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['ko', 'en']) {
    for (final patient in [true, false]) {
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
      expect(find.textContaining('대화 상대를 확인하지 못했어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 세션 인증 클라이언트를 넘기면 연동 확인 요청이 그 클라이언트로 나가 401이 세션 처리기에 전달되고,
  // 빌린 클라이언트는 화면이 닫혀도 닫지 않는다.
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
