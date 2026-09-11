// 파일명: chat_navigation_test.dart
// 역할: 대화 목록의 사용자 격리, 연동 상태 전환, 큰 글씨 탐색과 홈 2×2 배치를 검증한다.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/chat_list_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';

// 함수이름: _emptyResponse
// 함수역할: 실제 통신을 막는 응답을 제공한다. 매개변수: request: 요청. 반환값: 빈 성공 응답.
Future<http.Response> _emptyResponse(http.Request request) async =>
    http.Response('{}', 200);
// 함수이름: _noop
// 함수역할: 외부 동작 없는 콜백을 제공한다. 매개변수: 없음. 반환값: 없음.
void _noop() {}

// 클래스명: _Links
// 역할: 연동 응답·오류·지연을 제어한다. 속성: result, fail, pending, calls: 응답과 요청 상태.
class _Links extends LinkPatientCaregiver {
  List<PatientCaregiverLink> result = [];
  bool fail = false;
  int calls = 0;
  Completer<List<PatientCaregiverLink>>? pending;
  // 함수이름: _Links
  // 함수역할: 연동 조회 대역을 만든다. 매개변수: 없음. 반환값: 테스트 Control.
  _Links() : super(client: MockClient(_emptyResponse));
  // 함수이름: requestLinkScreen
  // 함수역할: 요청 횟수를 기록하고 응답·오류를 반환한다. 매개변수: 없음. 반환값: 연동 목록 Future.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    calls++;
    if (pending != null) {
      final request = pending!;
      pending = null;
      return request.future;
    }
    if (fail) throw StateError('offline');
    return result;
  }
}

// 클래스명: _History
// 역할: 최근 메시지 조회와 실패를 재현한다. 속성: messages, failed: 응답·실패 연동 ID.
class _History extends ManageLinkedChat {
  final Map<int, List<ChatMessage>> messages = {};
  int? failed;
  int calls = 0;
  // 함수이름: _History
  // 함수역할: 채팅 조회 대역을 만든다. 매개변수: 없음. 반환값: 테스트 Control.
  _History() : super(userHash: 'caregiver', client: MockClient(_emptyResponse));
  // 함수이름: requestHistory
  // 함수역할: 최근 한 메시지 요청을 검증하고 지정 이력을 제공한다.
  // 매개변수: linkId, beforeMessageId, limit: 연동·이력 기준·페이지 크기. 반환값: 지정 메시지 또는 실패.
  @override
  Future<List<ChatMessage>> requestHistory({
    required int linkId,
    int? beforeMessageId,
    int limit = 50,
  }) async {
    expect(limit, 1);
    calls++;
    if (linkId == failed) throw StateError('preview offline');
    return messages[linkId] ?? [];
  }
}

// 클래스명: _ViewModel
// 역할: 화면 테스트용 사용자 표시 설정을 고정한다. 속성: setting: 표시 설정.
class _ViewModel extends MedBuddyViewModel {
  UserSetting setting = const UserSetting();
  // 함수이름: _ViewModel
  // 함수역할: 지정 계정의 화면 모델을 만든다. 매개변수: hash: 계정. 반환값: 테스트 화면 모델.
  _ViewModel([String hash = 'caregiver'])
    : super(patientHash: hash, apiClient: MockClient(_emptyResponse));
  // 함수이름: userSetting
  // 함수역할: 테스트 설정을 제공한다. 매개변수: 없음. 반환값: 현재 설정.
  @override
  UserSetting get userSetting => setting;
}

// 함수이름: _link
// 함수역할: 다른 환자를 가진 연동을 만든다. 매개변수: id, caregiver, active: ID·보호자·활성 여부. 반환값: 연동.
PatientCaregiverLink _link(
  int id, {
  String caregiver = 'caregiver',
  bool active = true,
}) => PatientCaregiverLink(
  linkId: id,
  patientHash: 'patient-$id',
  caregiverHash: caregiver,
  patientAlias: 'Patient $id',
  linkStatus: active,
);
// 함수이름: _message
// 함수역할: 삭제·숨김·정렬 시각이 있는 메시지를 만든다. 매개변수: id, hidden, deleted: 연동·숨김·삭제. 반환값: 메시지.
ChatMessage _message(int id, {bool hidden = false, bool deleted = false}) =>
    ChatMessage(
      messageId: id,
      linkId: id,
      senderHash: 'patient-$id',
      clientMessageId: 'test-$id',
      body: 'Message $id',
      createdAt: DateTime(2026, 9, 9, 10, id),
      hiddenForMe: hidden,
      deletedForEveryone: deleted,
    );
// 함수이름: _viewport
// 함수역할: 화면 크기를 고정하고 종료 후 복구한다. 매개변수: tester, width: 도구·너비. 반환값: 없음.
void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 함수이름: main
// 함수역할: 대화 조회와 동적 탐색 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: 초기화 콜백
  // 함수역할: 테스트 기기 저장소를 비운다. 매개변수: 없음. 반환값: 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // 함수이름: 참여 범위 테스트
  // 함수역할: 유효 연동만 남기고 중복을 제거하며 두 역할의 이름을 구분한다. 매개변수: 없음. 반환값: 검증 완료.
  test(
    'filters active participants and resolves names for both roles',
    () async {
      final links = _Links()
        ..result = [
          _link(1),
          _link(2),
          _link(2),
          _link(3, active: false),
          _link(4, caregiver: 'other'),
          _link(0),
        ];
      final chat = _History();
      final control = ManageChatList(
        userHash: 'caregiver',
        linkControl: links,
        chatControl: chat,
      );
      addTearDown(control.dispose);
      await control.refresh();
      expect(control.links.length, 2);
      expect(
        control.peerName(control.links.first, isEnglish: true),
        'Patient 1',
      );
      expect(chat.calls, 0);
      final patient = ManageChatList(
        userHash: 'patient-1',
        linkControl: links,
        chatControl: chat,
      );
      addTearDown(patient.dispose);
      await patient.refresh();
      expect(patient.links.length, 1);
      expect(
        patient.peerName(patient.links.single, isEnglish: false),
        '보호자 caregiver',
      );
    },
  );
  // 함수이름: 미리보기 테스트
  // 함수역할: 최근 대화 정렬·숨김·개별 조회 실패·연동 삭제를 검증한다. 매개변수: 없음. 반환값: 검증 완료.
  test('previews sort by recency and discard hidden or failed data', () async {
    final links = _Links()..result = [_link(1), _link(2), _link(3)];
    final history = _History()
      ..messages.addAll({
        1: [_message(1)],
        2: [_message(2)],
        3: [_message(3, deleted: true)],
      });
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: history,
    );
    addTearDown(control.dispose);
    await control.refresh(includeMessages: true);
    expect(control.links.first.linkId, 3);
    history.messages[1] = [_message(1, hidden: true)];
    history.failed = 2;
    await control.refresh(includeMessages: true);
    expect(control.latestMessage(1), isNull);
    expect(control.latestMessage(2), isNull);
    expect(control.previewFailed(2), isTrue);
    links.result = [];
    await control.refresh();
    expect(control.links, isEmpty);
    expect(control.latestMessage(3), isNull);
  });
  // 함수이름: 재시도 테스트
  // 함수역할: 오프라인 때 목록을 유지하고 재시도 성공 시 오류를 해제한다. 매개변수: 없음. 반환값: 검증 완료.
  test('lookup errors preserve conversations and recover', () async {
    final links = _Links()..result = [_link(1)];
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: _History(),
    );
    addTearDown(control.dispose);
    await control.refresh();
    links.fail = true;
    await control.refresh();
    expect(control.hasError, isTrue);
    expect(control.links.length, 1);
    links.fail = false;
    links.result = [];
    await control.refresh();
    expect(control.hasError, isFalse);
    expect(control.links, isEmpty);
  });
  // 함수이름: 중복·종료 테스트
  // 함수역할: 조회 중 새 갱신을 합치고 폐기한 계정의 늦은 응답을 무시한다. 매개변수: 없음. 반환값: 검증 완료.
  test('queues refresh and ignores late disposed responses', () async {
    final pending = Completer<List<PatientCaregiverLink>>();
    final links = _Links()..pending = pending;
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: _History(),
    );
    final first = control.refresh();
    final second = control.refresh();
    expect(identical(first, second), isTrue);
    pending.complete([_link(1)]);
    await first;
    expect(links.calls, 2);
    expect(control.links, isEmpty);
    final late = Completer<List<PatientCaregiverLink>>();
    links.pending = late;
    final third = control.refresh();
    control.dispose();
    late.complete([_link(1)]);
    await third;
    expect(control.links, isEmpty);
  });
  // 함수이름: 동적 탭·수명주기 테스트
  // 함수역할: 연동 시 탭 표시, 여러 상대, 백그라운드 중지, 마지막 연동 해제 후 복귀와 표시 설정 변경 시 탭 유지를 검증한다.
  // 매개변수: tester: 위젯 도구. 반환값: 검증 완료.
  testWidgets(
    'chat follows links and lifecycle independently of display settings',
    (tester) async {
      _viewport(tester, 390);
      final links = _Links();
      final model = _ViewModel();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: model,
          child: MaterialApp(
            home: HomeScreen(
              chatListFactory:
                  // 함수이름: 목록 팩토리 콜백
                  // 함수역할: 계정별 테스트 목록을 만든다. 매개변수: hash: 계정. 반환값: Control.
                  (hash) => ManageChatList(
                    userHash: hash,
                    linkControl: links,
                    chatControl: _History(),
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bottomNavigation-chat')), findsNothing);
      expect(
        find.byKey(const ValueKey('homeNearbyPharmacyCard')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('homeMedicationReminderCard')),
        findsOneWidget,
      );
      links.result = [_link(1), _link(2)];
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bottomNavigation-chat')));
      await tester.pumpAndSettle();
      expect(find.text('Patient 1'), findsOneWidget);
      expect(find.text('Patient 2'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final calls = links.calls;
      await tester.pump(const Duration(seconds: 45));
      expect(links.calls, calls);
      links.result = [];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bottomNavigation-chat')), findsNothing);
      expect(find.byType(InputPrescriptionUI), findsOneWidget);
      links.result = [_link(1)];
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bottomNavigation-chat')));
      await tester.pumpAndSettle();
      model.setting = const UserSetting(fontSize: 20);
      model.updatesFor(MedBuddyFeature.userSetting).markChanged();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bottomNavigation-chat')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chatConversation-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  // 함수이름: 목록·선택 테스트
  // 함수역할: 삭제된 본문을 숨기고 선택한 환자의 기존 채팅으로 이동한다. 매개변수: tester: 도구. 반환값: 검증 완료.
  testWidgets('redacts deleted previews and opens the selected patient', (
    tester,
  ) async {
    final links = _Links()..result = [_link(1), _link(2)];
    final history = _History()..messages[2] = [_message(2, deleted: true)];
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: history,
    );
    addTearDown(control.dispose);
    await control.refresh(includeMessages: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatListUI(
          control: control,
          userSetting: const UserSetting(),
          onManageLinks: _noop,
        ),
      ),
    );
    expect(find.text('삭제된 메시지입니다'), findsOneWidget);
    expect(find.text('Message 2'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chatConversation-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final room = tester.widget<LinkedChatUI>(find.byType(LinkedChatUI));
    expect(room.linkId, 2);
    expect(room.patientHash, 'patient-2');
    expect(room.currentUserHash, 'caregiver');
    await tester.pumpWidget(const SizedBox.shrink());
    // 기존 실시간 연결의 네트워크 제한 시간을 소진해 테스트 타이머를 정리한다.
    await tester.pump(const Duration(seconds: 20));
  });
  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final language in ['ko', 'en']) {
        // 함수이름: 채팅 제목 일관성 테스트
        // 함수역할: 공통 제목 스타일과 확대 시 제목·도구 영역의 비겹침을 검증한다.
        // 매개변수: tester: 화면 테스트 도구. 반환값: 검증 완료.
        testWidgets('chat title fits $width $scale $language', (tester) async {
          _viewport(tester, width);
          final control = ManageChatList(
            userHash: 'caregiver',
            linkControl: _Links(),
            chatControl: _History(),
          );
          addTearDown(control.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 950),
                  textScaler: TextScaler.linear(scale),
                ),
                child: ChatListUI(
                  control: control,
                  userSetting: UserSetting(language: language),
                  onManageLinks: _noop,
                ),
              ),
            ),
          );
          final titleFinder = find.byKey(const ValueKey('chatListTitle'));
          final title = tester.widget<Text>(titleFinder);
          expect(title.data, language == 'en' ? 'Chat' : '채팅');
          expect(title.style?.fontSize, 28);
          expect(title.style?.fontWeight, FontWeight.w800);
          expect(title.style?.color, MedBuddyColors.textStrong);
          final titleRect = tester.getRect(titleFinder);
          final toolbarRect = tester.getRect(find.byType(AppBar));
          expect(titleRect.left, MedBuddySpacing.pageHorizontal);
          expect(titleRect.top, greaterThanOrEqualTo(toolbarRect.top));
          expect(titleRect.bottom, lessThanOrEqualTo(toolbarRect.bottom));
          for (final icon in [Icons.refresh, Icons.person_add_alt_1_outlined]) {
            final actionRect = tester.getRect(
              find.widgetWithIcon(IconButton, icon),
            );
            expect(titleRect.right, lessThanOrEqualTo(actionRect.left));
            expect(actionRect.bottom, lessThanOrEqualTo(toolbarRect.bottom));
          }
          expect(tester.takeException(), isNull);
        });
        // 함수이름: 다섯 탭 접근성 테스트
        // 함수역할: 다양한 화면·언어·배율에서 레이블·터치 영역을 검증한다. 매개변수: tester: 도구. 반환값: 검증 완료.
        testWidgets('five tabs fit $width $scale $language', (tester) async {
          _viewport(tester, width);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 950),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  bottomNavigationBar: MedBuddyBottomNavigationUI(
                    selectedDestination: MedBuddyDestination.chat,
                    language: language,
                    showChat: true,
                    // 함수이름: 선택 콜백
                    // 함수역할: 외부 동작 없는 선택 계약이다. 매개변수: destination: 목적지. 반환값: 없음.
                    onDestinationSelected: (destination) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final element
              in find
                  .descendant(
                    of: find.byType(MedBuddyBottomNavigationUI),
                    matching: find.byType(Text),
                  )
                  .evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.size.height, greaterThan(0));
          }
          for (final destination in MedBuddyDestination.values) {
            final rect = tester.getRect(
              find.byKey(ValueKey('bottomNavigation-${destination.name}')),
            );
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
        });
      }
    }
  }
  for (final scale in [1.0, 1.3, 2.0]) {
    for (final language in ['ko', 'en']) {
      // 함수이름: 알림·약국 2×2 배치 테스트
      // 함수역할: 알림은 두 번째, 약국은 네 번째 칸에 배치되고 각각의 진입 동작을 유지하는지 확인한다.
      // 매개변수: tester: 위젯 도구. 반환값: 검증 완료.
      testWidgets('reminders and pharmacy coexist in 2x2 $scale $language', (
        tester,
      ) async {
        _viewport(tester, 390);
        var opens = 0;
        var reminderOpens = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 950),
                textScaler: TextScaler.linear(scale),
              ),
              child: InputPrescriptionUI(
                statusMessage: '',
                userSetting: UserSetting(language: language),
                onPrescriptionScanRequested: _noop,
                onPrescriptionGalleryRequested: _noop,
                onTodayScheduleRequested: _noop,
                // 함수역할: 선택한 알약 촬영 방식을 받고 실제 탐색은 생략한다.
                // 매개변수: mode. 반환값: 없음.
                onPillIdentificationRequested: (mode) {},
                onUserSettingRequested: _noop,
                onHealthRecommendationRequested: _noop,
                // 함수이름: 알림 설정 진입 콜백
                // 함수역할: 선택 횟수를 센다. 매개변수: 없음. 반환값: 없음.
                onMedicationReminderRequested: () {
                  reminderOpens++;
                },
                // 함수이름: 약국 진입 콜백
                // 함수역할: 선택 횟수를 센다. 매개변수: 없음. 반환값: 없음.
                onNearbyPharmacyRequested: () {
                  opens++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pharmacy = find.byKey(const ValueKey('homeNearbyPharmacyCard'));
        final health = find.byKey(
          const ValueKey('homeHealthRecommendationCard'),
        );
        final scan = find.byKey(const ValueKey('homePrescriptionAnalysisCard'));
        final reminder = find.byKey(
          const ValueKey('homeMedicationReminderCard'),
        );
        expect(pharmacy, findsOneWidget);
        expect(reminder, findsOneWidget);
        expect(
          find.byKey(const ValueKey('homePillIdentificationCard')),
          findsNothing,
        );
        expect(tester.getTopLeft(scan).dy, tester.getTopLeft(reminder).dy);
        expect(tester.getTopLeft(health).dy, tester.getTopLeft(pharmacy).dy);
        expect(tester.getTopLeft(pharmacy).dx, tester.getTopLeft(reminder).dx);
        expect(tester.getSize(pharmacy).height, tester.getSize(health).height);
        await tester.ensureVisible(reminder);
        await tester.tap(reminder);
        expect(reminderOpens, 1);
        expect(opens, 0);
        await tester.ensureVisible(pharmacy);
        await tester.tap(pharmacy);
        expect(opens, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
