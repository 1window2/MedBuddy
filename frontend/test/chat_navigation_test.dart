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
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_home_control.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/entities/caregiver_monitoring_snapshot_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:medbuddy_frontend/boundaries/feature_search_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_caregiver_medication_ui_boundary.dart';

// 함수이름: _emptyResponse
// 함수역할:
// - 외부 통신 없이 모든 요청에 빈 JSON 객체와 성공 상태를 응답한다.
// 매개변수:
// - request (http.Request): 수신한 요청이며 응답 내용에는 사용하지 않는다.
// 반환값:
// - Future<http.Response>; 상태 200과 본문 {}인 응답.
Future<http.Response> _emptyResponse(http.Request request) async =>
    http.Response('{}', 200);
// 함수이름: _noop
// 함수역할:
// - 화면에서 요구하는 동작 콜백을 부작용 없이 완료한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void _noop() {}

// 클래스명: _Links
// 역할: 연동 목록 조회의 성공·실패·지연을 재현하는 대역.
// 주요 책임:
// - 조회 횟수를 기록하고 한 번만 사용하는 지연 응답을 우선 처리한다.
// 속성:
// - result (List<PatientCaregiverLink>): 즉시 반환할 연동 목록.
// - fail (bool): 지연 응답이 없을 때 조회 오류를 발생시킬지 여부.
// - calls (int): 누적 조회 횟수.
// - pending (Completer<List<PatientCaregiverLink>>?): 다음 조회를 보류할 완료자.
class _Links extends LinkPatientCaregiver {
  List<PatientCaregiverLink> result = [];
  bool fail = false;
  int calls = 0;
  Completer<List<PatientCaregiverLink>>? pending;
  // 함수이름: _Links
  // 함수역할:
  // - 빈 JSON 응답 클라이언트를 사용하는 연동 조회 대역을 생성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - _Links; 실제 네트워크를 사용하지 않는 인스턴스.
  _Links() : super(client: MockClient(_emptyResponse));
  // 함수이름: requestLinkScreen
  // 함수역할:
  // - 조회 횟수를 늘리고 pending을 한 번 소비한다. 지연 응답이 없으면 fail에 따라 StateError를 던지거나 result를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<List<PatientCaregiverLink>>; 설정한 연동 목록 또는 보류 중인 결과.
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
// 역할: 대화 미리보기와 읽지 않은 메시지 수를 제공하는 대역.
// 주요 책임:
// - 연동별 응답과 실패를 설정하고 미리보기 조회 범위를 검사한다.
// 속성:
// - messages (Map<int, List<ChatMessage>>): 연동별 메시지 목록.
// - unreadCounts (Map<int, int>): 연동별 읽지 않은 메시지 수.
// - unreadFails (bool): 읽지 않은 메시지 수 조회의 실패 여부.
// - failed (int?): 미리보기 조회를 실패시킬 연동 ID.
// - calls (int): 미리보기 조회 횟수.
class _History extends ManageLinkedChat {
  final Map<int, List<ChatMessage>> messages = {};
  final unreadCounts = <int, int>{};
  bool unreadFails = false;
  // 함수이름: requestUnreadSummary
  // 함수역할:
  // - 연동별 읽지 않은 메시지 수를 반환하며 unreadFails가 켜져 있으면 StateError로 실패한다.
  // 매개변수:
  // - linkId (int): 조회할 연동 ID.
  // 반환값:
  // - Future<ChatUnreadSummary>; 설정한 수 또는 기본값 0을 담은 요약.
  @override
  Future<ChatUnreadSummary> requestUnreadSummary({required int linkId}) async {
    if (unreadFails) throw StateError('unread offline');
    return ChatUnreadSummary(count: unreadCounts[linkId] ?? 0);
  }

  int? failed;
  int calls = 0;
  // 함수이름: _History
  // 함수역할:
  // - caregiver 계정과 빈 응답 클라이언트로 대화 조회 대역을 생성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - _History; 메시지와 읽지 않은 수를 설정할 수 있는 대역.
  _History() : super(userHash: 'caregiver', client: MockClient(_emptyResponse));
  // 함수이름: requestHistory
  // 함수역할:
  // - 미리보기 요청이 한 건으로 제한되는지 검사하고 조회 횟수를 늘린다. 지정한 연동은 StateError로 실패한다.
  // 매개변수:
  // - linkId (int): 메시지를 조회할 연동 ID.
  // - beforeMessageId (int?): 이 대역에서는 사용하지 않는 이전 메시지 커서.
  // - limit (int): 기본값은 50이지만 이 테스트 대역은 1인 요청만 허용한다.
  // 반환값:
  // - Future<List<ChatMessage>>; 해당 연동의 설정된 메시지 또는 빈 목록.
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
// 역할: 홈 표시 설정과 본인 약 보유 여부를 제어하는 뷰 모델 대역.
// 주요 책임:
// - 조회 없이 테스트가 설정한 화면 상태를 제공한다.
// 속성:
// - setting (UserSetting): 화면에 노출할 사용자 설정.
// - hasOwnMedication (bool): 본인 약 한 건을 반환할지 여부.
class _ViewModel extends MedBuddyViewModel {
  UserSetting setting = const UserSetting();
  bool hasOwnMedication = false;
  // 함수이름: savedMedicationInfoList
  // 함수역할:
  // - 본인 약 보유 설정이 켜져 있으면 고정 약 한 건을, 아니면 부모의 저장 약 목록을 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<MedicationDetail>; 화면에서 조회하는 저장 약 목록.
  @override
  List<MedicationDetail> get savedMedicationInfoList => hasOwnMedication
      ? const [
          MedicationDetail(
            itemName: '본인약',
            efficacy: '',
            usageMethod: '',
            warning: '',
          ),
        ]
      : super.savedMedicationInfoList;
  // 함수이름: _ViewModel
  // 함수역할:
  // - 지정한 계정과 빈 응답 클라이언트를 사용하는 홈 화면 뷰 모델을 생성한다.
  // 매개변수:
  // - hash (String): 사용자 해시이며 기본값은 caregiver이다.
  // 반환값:
  // - _ViewModel; 사용자 설정을 직접 제어할 수 있는 인스턴스.
  _ViewModel([String hash = 'caregiver'])
    : super(patientHash: hash, apiClient: MockClient(_emptyResponse));
  // 함수이름: userSetting
  // 함수역할:
  // - 부모 저장소 대신 테스트에서 지정한 설정을 노출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - UserSetting; 현재 setting 값.
  @override
  UserSetting get userSetting => setting;
}

// 클래스명: _HomeMonitoring
// 역할: 환자별 홈 복약 요약 조회를 기록하는 대역.
// 주요 책임:
// - 전달받은 연동마다 알림 설정과 일정이 비어 있는 스냅샷을 만든다.
// 속성:
// - calls (int): 스냅샷 조회 횟수.
class _HomeMonitoring extends CheckCaregiverMedication {
  // Function Name: _HomeMonitoring
  // Description:
  // - Creates the home-monitoring fake for the caregiver account.
  // Parameters:
  // - None.
  // Returns:
  // - _HomeMonitoring; a counter-backed snapshot provider.
  _HomeMonitoring() : super(caregiverHash: 'caregiver');
  int calls = 0;
  // 함수이름: requestScheduleSnapshot
  // 함수역할:
  // - 호출 횟수를 늘리고 전달된 모든 연동을 빈 일정 스냅샷으로 변환한다. 연동 상태를 별도로 필터링하지 않는다.
  // 매개변수:
  // - links (List<PatientCaregiverLink>?): 스냅샷에 포함할 연동이며 null이면 빈 목록을 반환한다.
  // 반환값:
  // - Future<List<CaregiverMonitoringSnapshot>>; 입력 연동별 빈 일정 스냅샷.
  @override
  Future<List<CaregiverMonitoringSnapshot>> requestScheduleSnapshot({
    List<PatientCaregiverLink>? links,
  }) async {
    calls++;
    return [
      for (final link in links ?? <PatientCaregiverLink>[])
        CaregiverMonitoringSnapshot(
          link: link,
          notificationSettings: {},
          schedules: [],
        ),
    ];
  }
}

// 함수이름: _link
// 함수역할:
// - ID에서 환자 해시와 별칭을 만들고 보호자 및 활성 상태를 지정한 연동을 생성한다.
// 매개변수:
// - id (int): 연동 ID이자 환자 해시·별칭의 구분자.
// - caregiver (String): 보호자 해시이며 기본값은 caregiver이다.
// - active (bool): 활성 연동 여부이며 기본값은 true이다.
// 반환값:
// - PatientCaregiverLink; 목록 필터링과 상대 이름 표시용 연동.
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
// 함수역할:
// - ID를 메시지·연동 식별자와 발송 시각에 반영한 환자 메시지를 생성한다.
// 매개변수:
// - id (int): 메시지·연동 ID 및 발송 시각의 분 값.
// - hidden (bool): 미리보기 숨김 여부이며 기본값은 false이다.
// - deleted (bool): 삭제 상태 여부이며 기본값은 false이다.
// 반환값:
// - ChatMessage; 숨김·삭제 상태를 조절할 수 있는 미리보기 메시지.
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
// 함수역할:
// - 고정 높이 950과 픽셀 비율 1로 화면 크기를 설정하고 테스트 종료 시 원래 값을 복원한다.
// 매개변수:
// - tester (WidgetTester): 화면 설정과 종료 정리를 등록할 테스트 도구.
// - width (double): 테스트 화면 너비.
// 반환값:
// - void; 반환값 없음.
void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 함수이름: main
// 함수역할:
// - 홈 기능 검색, 연동 갱신, 대화 미리보기·배지 및 접근성 탐색 테스트를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - void; 반환값 없음.
void main() {
  // 홈의 두 일정 모드에서 실제 검색 진입과 기존 설정·등록·연동 경로를 검증한다.
  for (final source in ['self', 'patients']) {
    // 함수이름: 기능 찾기는 $source 홈에서도 동일한 안전한 이동을 제공한다
    // 함수역할:
    // - 본인·환자 모드에서 기능 검색으로 글씨 설정·약 추가·촬영·연동 관리·복약 일정에 진입하고, 뒤로 가기 시 검색어가 유지되는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증 후 완료한다.
    testWidgets('기능 찾기는 $source 홈에서도 동일한 안전한 이동을 제공한다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _viewport(tester, 390);
      final links = _Links();
      final model = _ViewModel()
        ..setting = UserSetting(homeScheduleSource: source);
      final api = _HomeMonitoring();
      final auth = AuthenticationControl.development();
      final language = AppLanguageControl(loadPersisted: false);
      addTearDown(model.dispose);
      addTearDown(api.dispose);
      addTearDown(auth.dispose);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MedBuddyViewModel>.value(value: model),
            ChangeNotifierProvider<AuthenticationControl>.value(value: auth),
            ChangeNotifierProvider<AppLanguageControl>.value(value: language),
          ],
          child: MaterialApp(
            theme: MedBuddyTheme.light(),
            home: HomeScreen(
              chatListFactory: (hash) => ManageChatList(
                userHash: hash,
                linkControl: links,
                chatControl: _History(),
              ),
              caregiverHomeFactory: (hash) =>
                  CheckCaregiverHome(userHash: hash, control: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('homeFeatureSearchButton'));
      expect(
        tester.getCenter(search).dx,
        lessThan(
          tester
              .getCenter(find.byKey(const ValueKey('homeNotificationsButton')))
              .dx,
        ),
      );
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '글씨 크게',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-fontSize')));
      await tester.pumpAndSettle();
      expect(find.byType(FeatureSearchUI), findsNothing);
      expect(find.byType(FeatureSearchUI, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fontSizeSelector')).hitTestable(),
        findsOneWidget,
      );
      expect(model.userSetting.fontSize, const UserSetting().fontSize);
      await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('featureSearchInput')))
            .controller!
            .text,
        '글씨 크게',
      );
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '약 추가',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-manualMedication')));
      await tester.pump();
      expect(find.byType(FeatureSearchUI, skipOffstage: false), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(ManualMedicationEntryUI), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FeatureSearchUI), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '처방전',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-prescription')));
      await tester.pumpAndSettle();
      expect(find.byType(FeatureSearchUI), findsOneWidget);
      expect(find.text('카메라로 촬영'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '알약 식별',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-pillIdentification')));
      await tester.pumpAndSettle();
      expect(find.byType(FeatureSearchUI), findsOneWidget);
      await tester.tap(find.text('알약 하나씩 찾기'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PillIdentificationUI>(find.byType(PillIdentificationUI))
            .captureMode,
        PillCaptureMode.individualPhotos,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '가족 채팅',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-chat')));
      await tester.pumpAndSettle();
      expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '오늘 먹을 약',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-schedule')));
      await tester.pumpAndSettle();
      expect(find.byType(FeatureSearchUI), findsNothing);
      expect(
        tester
            .widget<MedBuddyBottomNavigationUI>(
              find.byType(MedBuddyBottomNavigationUI),
            )
            .selectedDestination,
        MedBuddyDestination.schedule,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  // 함수이름: 기능 찾기의 환자 일정은 대기 중 다른 화면을 열면 그 위에 열지 않는다
  // 함수역할:
  // - 환자 일정 조회 중 검색 화면을 닫으면 늦은 응답이 다른 화면 위에 열리지 않고, 새 검색에서는 정상 진입하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('기능 찾기의 환자 일정은 대기 중 다른 화면을 열면 그 위에 열지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _viewport(tester, 390);
    final links = _Links()..result = [_link(1)];
    final model = _ViewModel();
    final api = _HomeMonitoring();
    final auth = AuthenticationControl.development();
    final language = AppLanguageControl(loadPersisted: false);
    addTearDown(model.dispose);
    addTearDown(api.dispose);
    addTearDown(auth.dispose);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MedBuddyViewModel>.value(value: model),
          ChangeNotifierProvider<AuthenticationControl>.value(value: auth),
          ChangeNotifierProvider<AppLanguageControl>.value(value: language),
        ],
        child: MaterialApp(
          theme: MedBuddyTheme.light(),
          home: HomeScreen(
            chatListFactory: (hash) => ManageChatList(
              userHash: hash,
              linkControl: links,
              chatControl: _History(),
            ),
            caregiverHomeFactory: (hash) =>
                CheckCaregiverHome(userHash: hash, control: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('homeFeatureSearchButton'));
    // Function Name: chooseCaregiverSchedule
    // Description:
    // - Opens feature search and selects caregiver schedules using the captured tester; pumps the selection without waiting for a deferred link lookup.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the search and selection frames.
    Future<void> chooseCaregiverSchedule() async {
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('featureSearchInput')),
        '환자 기록 확인',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('feature-caregiverSchedule')));
      await tester.pumpAndSettle();
    }

    final lookup = Completer<List<PatientCaregiverLink>>();
    links.pending = lookup;
    await chooseCaregiverSchedule();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    lookup.complete([_link(1)]);
    await tester.pumpAndSettle();
    expect(find.byType(CheckCaregiverMedicationUI), findsNothing);
    expect(find.byType(FeatureSearchUI), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await chooseCaregiverSchedule();
    expect(find.byType(CheckCaregiverMedicationUI), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  // 함수이름: late home source restoration refreshes linked patient schedules
  // 함수역할:
  // - 홈을 연 뒤 변경된 일정 표시 설정을 반영하며 환자 모드로 전환할 때마다 요약을 조회하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets(
    'late home source restoration refreshes linked patient schedules',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      _viewport(tester, 390);
      final links = _Links()..result = [_link(1)];
      final model = _ViewModel();
      final api = _HomeMonitoring();
      addTearDown(model.dispose);
      addTearDown(api.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: model,
          child: MaterialApp(
            home: HomeScreen(
              chatListFactory: (hash) => ManageChatList(
                userHash: hash,
                linkControl: links,
                chatControl: _History(),
              ),
              caregiverHomeFactory: (hash) =>
                  CheckCaregiverHome(userHash: hash, control: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      model.setting = const UserSetting(homeScheduleSource: 'patients');
      model.updatesFor(MedBuddyFeature.userSetting).markChanged();
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(find.byKey(const Key('caregiver-home-summary')), findsOneWidget);
      model.setting = const UserSetting(homeScheduleSource: 'self');
      model.updatesFor(MedBuddyFeature.userSetting).markChanged();
      await tester.pumpAndSettle();
      model.setting = const UserSetting(homeScheduleSource: 'patients');
      model.updatesFor(MedBuddyFeature.userSetting).markChanged();
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (source, ownMedication) in [
    ('self', false),
    ('self', true),
    ('patients', false),
    ('patients', true),
  ]) {
    // Function Name: 홈은 명시적 일정 선택을 따르고 연결 해제 시 안내한다: $source/$ownMedication
    // Description:
    // - Checks that home summaries follow the selected source, not ownership of medication; draft setting changes stay unsaved, returning home refreshes patient summaries, and removed links show the empty state.
    // Parameters:
    // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
    // Returns:
    // - Future<void>; completes after the asynchronous assertions.
    testWidgets('홈은 명시적 일정 선택을 따르고 연결 해제 시 안내한다: $source/$ownMedication', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      _viewport(tester, 390);
      final links = _Links()..result = [_link(1)];
      final model = _ViewModel()
        ..setting = UserSetting(homeScheduleSource: source)
        ..hasOwnMedication = ownMedication;
      final api = _HomeMonitoring();
      final authentication = AuthenticationControl.development();
      final language = AppLanguageControl(loadPersisted: false);
      addTearDown(model.dispose);
      addTearDown(api.dispose);
      addTearDown(authentication.dispose);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MedBuddyViewModel>.value(value: model),
            ChangeNotifierProvider<AuthenticationControl>.value(
              value: authentication,
            ),
            ChangeNotifierProvider<AppLanguageControl>.value(value: language),
          ],
          child: MaterialApp(
            home: HomeScreen(
              chatListFactory: (hash) => ManageChatList(
                userHash: hash,
                linkControl: links,
                chatControl: _History(),
              ),
              caregiverHomeFactory: (hash) =>
                  CheckCaregiverHome(userHash: hash, control: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('caregiver-home-summary')),
        source == 'self' ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const Key('homePrescriptionAnalysisCard')),
        findsOneWidget,
      );
      expect(api.calls, source == 'self' ? 0 : 1);
      expect(
        find.byKey(const Key('caregiver-home-source-hint')),
        source == 'self' ? findsOneWidget : findsNothing,
      );
      expect(model.userSetting.homeScheduleSource, source);
      if (source == 'self') {
        expect(find.text('홈 일정을 ‘연동된 환자’로 바꿔요.'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('caregiver-home-source-hint')),
        );
        await tester.tap(find.byKey(const Key('caregiver-home-source-hint')));
        await tester.pumpAndSettle();
        expect(find.byType(ManageUserSettingUI), findsOneWidget);
        expect(find.text('화면 및 음성'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')),
          findsNothing,
        );
        final sourceSelector = find.byKey(
          const ValueKey('homeScheduleSourceSelector'),
        );
        expect(sourceSelector, findsOneWidget);
        expect(
          find.descendant(of: sourceSelector, matching: find.text('내 일정')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ManageUserSettingUI>(find.byType(ManageUserSettingUI))
              .initialSetting
              .homeScheduleSource,
          'self',
        );
        // Only an explicit selection changes the draft; navigation never saves it.
        for (final (value, label) in [
          ('patients', '연동된 환자'),
          ('self', '내 일정'),
        ]) {
          await tester.ensureVisible(sourceSelector);
          await tester.tap(sourceSelector);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('homeScheduleSource-$value')));
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: sourceSelector, matching: find.text(label)),
            findsOneWidget,
          );
          expect(model.userSetting.homeScheduleSource, 'self');
        }
        await Navigator.of(
          tester.element(find.byType(ManageUserSettingUI)),
        ).maybePop();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')),
          findsOneWidget,
        );
        await Navigator.of(
          tester.element(find.byType(ManageUserSettingUI)),
        ).maybePop();
        await tester.pumpAndSettle();
        expect(model.userSetting.homeScheduleSource, 'self');
        expect(api.calls, 0);
      }
      if (source == 'patients') {
        expect(find.text('Patient 1'), findsOneWidget);
        expect(find.text('오늘 등록된 복약 일정이 없습니다.'), findsOneWidget);
        final previousCalls = api.calls;
        await tester.tap(find.byKey(const ValueKey('bottomNavigation-chat')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bottomNavigation-home')));
        await tester.pumpAndSettle();
        expect(api.calls, greaterThan(previousCalls));
        expect(find.text('Patient 1'), findsOneWidget);
      }
      links.result = [];
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('caregiver-home-source-hint')), findsNothing);
      expect(
        find.byKey(const Key('caregiver-home-summary')),
        source == 'self' ? findsNothing : findsOneWidget,
      );
      if (source == 'patients') {
        expect(find.text('연동된 환자가 없습니다.'), findsOneWidget);
        expect(find.byKey(const Key('caregiver-home-link')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp
  // 함수역할:
  // - 각 테스트 시작 전에 공유 환경설정을 비워 이전 테스트의 저장 상태를 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 반환값 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // Function Name: filters active participants and resolves names for both roles
  // Description:
  // - Filters inactive, duplicate, nonpositive, and unrelated links; resolves the caregiver-facing patient alias and patient-facing shortened caregiver name without fetching previews.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
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
        '보호자 IVER',
      );
    },
  );
  // 함수이름: previews sort by recency and discard hidden or failed data
  // 함수역할:
  // - 삭제·숨김 표시를 포함한 최신 메시지 순으로 미리보기를 정렬하고, 숨김·조회 실패·연동 삭제 후 이전 본문과 상태가 남지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
  // 함수이름: lookup errors preserve conversations and recover
  // 함수역할:
  // - 연동 조회가 실패하면 기존 목록과 오류를 유지하고, 재조회 성공 시 빈 목록과 정상 상태로 갱신하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
  // 함수이름: queues refresh and ignores late disposed responses
  // 함수역할:
  // - 진행 중인 갱신은 같은 Future를 공유하고 추가 갱신을 한 번 예약하며, dispose 이후 도착한 결과는 반영하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
  // 함수이름: chat follows links and lifecycle independently of display settings
  // 함수역할:
  // - 연동 유무에 따라 채팅 탭이 추가·제거되고 앱 일시정지 중 조회가 멈추며, 복귀와 글씨 설정 변경 후에도 올바른 대화 화면을 유지하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
        find.byKey(const ValueKey('homeUserSettingsCard')),
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
  // 함수이름: conversation badges refresh and clear without marking read
  // 함수역할:
  // - 큰 글씨 화면에서 읽지 않은 수를 3과 99+로 표시하되 원래 수 120은 유지하며, 0·조회 실패·연동 삭제 시 배지를 제거하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
  testWidgets('conversation badges refresh and clear without marking read', (
    tester,
  ) async {
    final links = _Links()..result = [_link(1), _link(2)];
    final history = _History()..unreadCounts.addAll({1: 3, 2: 120});
    final control = ManageChatList(
      userHash: 'caregiver',
      linkControl: links,
      chatControl: history,
    );
    addTearDown(control.dispose);
    await control.refresh(includeMessages: true);
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ChatListUI(
            control: control,
            userSetting: const UserSetting(),
            onManageLinks: _noop,
          ),
        ),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(control.unreadCount(2), 120);
    history.unreadCounts[1] = 0;
    await control.refresh(includeMessages: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('chatUnread-1')), findsNothing);
    history.unreadFails = true;
    await control.refresh(includeMessages: true);
    await tester.pump();
    expect(control.unreadCount(2), isNull);
    expect(find.byKey(const ValueKey('chatUnread-2')), findsNothing);
    history.unreadFails = false;
    links.result = [_link(1)];
    await control.refresh(includeMessages: true);
    expect(control.unreadCount(2), isNull);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: redacts deleted previews and opens the selected patient
  // 함수역할:
  // - 삭제된 본문 대신 안내 문구와 지정된 목록 간격·서체를 표시하고, 선택한 환자와 연동으로 채팅을 열어 해당 경로만 관찰하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
  // 반환값:
  // - Future<void>; 비동기 검증 후 완료한다.
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
    final chatRoutes = LinkedChatRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [chatRoutes],
        home: ChatListUI(
          control: control,
          userSetting: const UserSetting(),
          onManageLinks: _noop,
        ),
      ),
    );
    expect(find.text('삭제된 메시지입니다'), findsOneWidget);
    expect(find.text('Message 2'), findsNothing);
    final header = tester.getRect(find.byType(MedBuddyPageHeader));
    final firstConversation = find.byType(ListTile).first;
    final conversation = tester.getRect(firstConversation);
    expect(conversation.top - header.bottom, closeTo(20, 0.01));
    final tile = tester.widget<ListTile>(firstConversation);
    expect(
      tile.contentPadding,
      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    );
    final frame = tester.widget<Material>(
      find.byKey(const ValueKey('chatConversationFrame-1')),
    );
    expect(
      (frame.shape! as RoundedRectangleBorder).borderRadius,
      MedBuddyRadii.largeCard,
    );
    final titleStyle = (tile.title! as Text).style!;
    final previewStyle = ((tile.subtitle! as Padding).child! as Text).style!;
    expect(titleStyle.fontSize, 17);
    expect(titleStyle.fontWeight, FontWeight.w700);
    expect(previewStyle.fontSize, 13);
    expect(previewStyle.fontWeight, FontWeight.w600);
    expect(previewStyle.color, MedBuddyColors.textMuted);
    await tester.tap(find.byKey(const ValueKey('chatConversation-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final room = tester.widget<LinkedChatUI>(find.byType(LinkedChatUI));
    expect(room.linkId, 2);
    expect(room.patientHash, 'patient-2');
    expect(room.currentUserHash, 'caregiver');
    // 채팅 알림이 같은 대화를 다시 쌓지 않도록 목록에서 연 대화도 같은 경로 이름으로 추적된다.
    expect(chatRoutes.isOpen(2), isTrue);
    expect(chatRoutes.isOpen(1), isFalse);
    expect(
      ModalRoute.of(tester.element(find.byType(LinkedChatUI)))?.settings.name,
      linkedChatRouteName(2),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    // 기존 실시간 연결의 네트워크 제한 시간을 소진해 테스트 타이머를 정리한다.
    await tester.pump(const Duration(seconds: 20));
  });
  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final language in ['ko', 'en']) {
        // Function Name: chat title fits $width $scale $language
        // Description:
        // - Checks localized chat headers across screen widths and text scales: title styling and insets stay fixed, while the text remains inside the header without colliding with action icons.
        // Parameters:
        // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
        // Returns:
        // - Future<void>; completes after the asynchronous assertions.
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
          expect(
            find.text(
              language == 'en' ? 'Message your family.' : '가족과 메시지를 주고받습니다.',
            ),
            findsOneWidget,
          );
          expect(title.style?.fontSize, 21);
          expect(title.style?.fontWeight, FontWeight.w700);
          expect(title.style?.color, Colors.white);
          final titleRect = tester.getRect(titleFinder);
          final toolbarRect = tester.getRect(find.byType(MedBuddyPageHeader));
          expect(titleRect.left, MedBuddySpacing.pageHorizontal + 12);
          expect(titleRect.top, greaterThanOrEqualTo(toolbarRect.top));
          expect(titleRect.bottom, lessThanOrEqualTo(toolbarRect.bottom));
          for (final icon in [Icons.refresh, Icons.person_add_alt_1_outlined]) {
            final actionRect = tester.getRect(
              find.widgetWithIcon(IconButton, icon),
            );
            expect(titleRect.overlaps(actionRect), isFalse);
            expect(actionRect.bottom, lessThanOrEqualTo(toolbarRect.bottom));
          }
          expect(tester.takeException(), isNull);
        });
        // Function Name: five tabs fit $width $scale $language
        // Description:
        // - Checks all five navigation destinations across widths, languages, and text scales: labels remain readable on one line and each target retains at least 48-by-48 logical pixels.
        // Parameters:
        // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
        // Returns:
        // - Future<void>; completes after the asynchronous assertions.
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
              // Function Name: onDestinationSelected callback
              // Description: Accept a destination without navigating during the layout check.
              // Parameters: destination (MedBuddyDestination): selected destination, unused here.
              // Returns: void; no side effects.
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
          // Navigation labels remain at least 13 logical pixels high in font size.
            expect(
              (element.widget as Text).style!.fontSize,
              greaterThanOrEqualTo(13),
            );
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
      // 함수이름: settings and pharmacy coexist in 2x2 $scale $language
      // 함수역할:
      // - 화면 크기·글씨·언어가 달라도 처방전·건강 및 약국·설정 항목의 두 열 정렬을 유지하고, 설정과 약국 선택이 각각 해당 콜백만 호출하는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·상태·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증 후 완료한다.
      testWidgets('settings and pharmacy coexist in 2x2 $scale $language', (
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
                userSetting: UserSetting(language: language),
                onTodayScheduleRequested: _noop,
                // 함수이름: onPillIdentificationRequested 콜백
                // 함수역할: 촬영 요청을 받아도 배치 검사 중에는 화면을 이동하지 않는다.
                // 매개변수: mode (PillCaptureMode): 선택한 촬영 방식이며 여기서는 사용하지 않는다.
                // 반환값: void; 부작용 없음.
                onPillIdentificationRequested: (mode) {},
                // 함수이름: onUserSettingRequested 콜백
                // 함수역할: 설정 항목이 선택된 횟수를 기록한다.
                // 매개변수: 없음.
                // 반환값: void; reminderOpens를 증가시킨다.
                onUserSettingRequested: () {
                  reminderOpens++;
                },
                onHealthRecommendationRequested: _noop,
                // 함수이름: onNearbyPharmacyRequested 콜백
                // 함수역할: 약국 항목이 선택된 횟수를 기록한다.
                // 매개변수: 없음.
                // 반환값: void; opens를 증가시킨다.
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
        final reminder = find.byKey(const ValueKey('homeUserSettingsCard'));
        expect(pharmacy, findsOneWidget);
        expect(reminder, findsOneWidget);
        expect(
          find.byKey(const ValueKey('homePillIdentificationCard')),
          findsNothing,
        );
        expect(tester.getTopLeft(scan).dy, tester.getTopLeft(health).dy);
        expect(tester.getTopLeft(reminder).dy, tester.getTopLeft(pharmacy).dy);
        expect(tester.getTopLeft(pharmacy).dx, tester.getTopLeft(scan).dx);
        expect(tester.getTopLeft(reminder).dx, tester.getTopLeft(health).dx);
        expect(
          tester.getSize(pharmacy).height,
          tester.getSize(reminder).height,
        );
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
