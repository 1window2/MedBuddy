// 파일명: notification_readiness_ui_boundary_test.dart
// 역할: 설정 안의 권한 상태·실패·명시적 테스트와 좁은 큰 글씨 화면을 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/notification_readiness_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

// 클래스명: _Control
// 역할: 권한 설정 화면에 상태·실패·지연을 주입하는 제어 대역이다.
// 주요 책임:
// - 플랫폼 호출 대신 요청 횟수와 언어를 기록하고 조회·표시·설정 이동의 완료를 제어한다.
// 속성:
// - state(NotificationReadinessSnapshot): 반환할 권한 상태.
// - sends / permissionRequests / settingsOpens / exactRequests / refreshes(int): 동작별 호출 횟수.
// - failSend / failRefresh / failSettings(bool): 작업별 실패 주입 설정.
// - sentLanguage(String?): 마지막 테스트 알림 언어.
// - sendGate / settingsGate(Completer<void>?): 표시·설정 이동의 선택적 대기 신호.
class _Control extends NotificationReadinessControl {
  // 함수이름: _Control
  // 함수역할:
  // - 알림·정확한 알람·시스템 설정 지원 여부를 상위 제어기에 주입한다.
  // 매개변수:
  // - supported(bool): 알림 자체를 지원하는지 여부.
  // - exact(bool): 정확한 알람 기능을 지원하는지 여부.
  // - settings(bool): 시스템 설정 이동 기능을 지원하는지 여부.
  // 반환값:
  // - _Control: 모든 권한이 켜진 초기 스냅샷을 가진 대역.
  _Control({bool supported = true, bool exact = true, bool settings = true})
    : super(
        notificationService: NotificationService.instance,
        supportsNotifications: supported,
        supportsExactAlarms: exact,
        supportsSystemSettings: settings,
      );
  NotificationReadinessSnapshot state = const NotificationReadinessSnapshot(
    notifications: true,
    medicationChannel: true,
    exactAlarms: true,
  );
  int sends = 0;
  int permissionRequests = 0;
  int settingsOpens = 0;
  int exactRequests = 0;
  int refreshes = 0;
  bool failSend = false;
  bool failRefresh = false;
  bool failSettings = false;
  String? sentLanguage;
  Completer<void>? sendGate;
  Completer<void>? settingsGate;

  // 함수이름: refresh
  // 함수역할:
  // - 조회 횟수를 늘린 뒤 현재 스냅샷을 돌려주거나 조회 실패를 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<NotificationReadinessSnapshot>: state 값; failRefresh이면 StateError.
  @override
  Future<NotificationReadinessSnapshot> refresh() async {
    refreshes++;
    if (failRefresh) throw StateError('unavailable');
    return state;
  }

  // 함수이름: sendTest
  // 함수역할:
  // - 표시 요청과 언어를 기록하고 선택적 대기를 거친 뒤 성공 또는 실패로 완료한다.
  // 매개변수:
  // - language(String): 테스트 알림에 사용할 표시 언어.
  // 반환값:
  // - Future<void>: 표시 대역 완료; failSend이면 StateError.
  @override
  Future<void> sendTest(String language) async {
    sends++;
    sentLanguage = language;
    if (sendGate != null) await sendGate!.future;
    if (failSend) throw StateError('unavailable');
  }

  // 함수이름: requestNotificationPermission
  // 함수역할:
  // - 직접 권한 요청 경로의 호출 횟수만 기록한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: state를 바꾸지 않는 성공 완료.
  @override
  Future<void> requestNotificationPermission() async {
    permissionRequests++;
  }

  // 함수이름: openSystemSettings
  // 함수역할:
  // - 일반 알림 설정 진입 횟수를 기록하고 선택적 지연·실패를 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 대기 해제 후 완료; failSettings이면 StateError.
  @override
  Future<void> openSystemSettings() async {
    settingsOpens++;
    if (settingsGate != null) await settingsGate!.future;
    if (failSettings) throw StateError('unavailable');
  }

  // 함수이름: openExactSettings
  // 함수역할:
  // - 정확한 시간 설정 진입 횟수를 기록하고 일반 설정과 같은 지연·실패 조건을 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 대기 해제 후 완료; failSettings이면 StateError.
  @override
  Future<void> openExactSettings() async {
    exactRequests++;
    if (settingsGate != null) await settingsGate!.future;
    if (failSettings) throw StateError('unavailable');
  }
}

// 함수이름: _open
// 함수역할:
// - 스크롤 가능한 설정 영역을 앱에 장착하고 첫 상태 조회와 화면 갱신을 기다린다.
// 매개변수:
// - tester(WidgetTester): 화면 장착 도구.
// - control(_Control): 상태와 플랫폼 동작을 제어할 대역.
// - english(bool): true이면 영어, false이면 한글 화면.
// 반환값:
// - Future<void>: 초기 화면 안정화 완료.
Future<void> _open(
  WidgetTester tester,
  _Control control, {
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: NotificationDeviceSettings(
            control: control,
            isEnglish: english,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: _tap
// 함수역할:
// - 지정 키의 설정 행이나 버튼을 노출한 뒤 누르고 상태 갱신을 기다린다.
// 매개변수:
// - tester(WidgetTester): 스크롤과 탭을 수행할 도구.
// - key(String): 누를 위젯의 ValueKey 값.
// 반환값:
// - Future<void>: 탭 뒤 화면 안정화 완료; 대기 중 작업은 호출 전에 해제해야 한다.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _sendKey = ValueKey('notificationSettingsSendTest');

// 함수이름: main
// 함수역할:
// - 권한 상태별 화면, 명시적 알림 전송, 앱 복귀와 큰 글씨 조작성을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 상태·동작·접근성 위젯 사례를 등록한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 추가 준비도·약 등록·채널 안내 없이 권한 스위치와 테스트 버튼을 표시하고 행 너비·간격을 맞추는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('약 등록 점검 없이 기존 설정 행과 테스트 버튼만 제공한다', (tester) async {
    await _open(tester, _Control());
    expect(find.text('알림 허용'), findsOneWidget);
    expect(find.text('정확한 시간에 알림'), findsOneWidget);
    expect(find.text('테스트 알림 보내기'), findsOneWidget);
    expect(find.textContaining('사용 준비'), findsNothing);
    expect(find.textContaining('약 등록'), findsNothing);
    expect(find.textContaining('알림 채널'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final phone = find.byKey(const ValueKey('deviceNotificationSettingsRow'));
    final exact = find.byKey(const ValueKey('deviceExactReminderSettingsRow'));
    expect(tester.widget<SwitchListTile>(phone).value, isTrue);
    expect(tester.widget<SwitchListTile>(exact).value, isTrue);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('허용됨'), findsNothing);
    expect(tester.getSize(phone).width, tester.getSize(exact).width);
    expect(tester.getTopLeft(exact).dy - tester.getBottomLeft(phone).dy, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 진입 때 플랫폼 동작을 하지 않고 명시적 한글 테스트 전송 뒤에는 수신 완료 대신 알림창 확인 안내를 표시하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('진입 시 권한을 요청하지 않고 테스트 요청을 실제 수신으로 단정하지 않는다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    expect(control.permissionRequests, 0);
    expect(control.exactRequests, 0);
    expect(control.settingsOpens, 0);
    expect(control.sends, 0);
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sends, 1);
    expect(control.sentLanguage, 'ko');
    expect(find.textContaining('휴대폰 알림창을 확인'), findsOneWidget);
    // 상시 설명은 제거하지만 전송 뒤 실제 수신 확인 안내는 유지한다.
    expect(
      find.byKey(const ValueKey('notificationSettingsTestLimitations')),
      findsNothing,
    );
    expect(find.textContaining('수신 완료'), findsNothing);
    expect(find.text('테스트 알림을 봤어요'), findsNothing);
  });

  for (final state in [
    const NotificationReadinessSnapshot(notifications: false),
    const NotificationReadinessSnapshot(
      notifications: true,
      medicationChannel: false,
    ),
    const NotificationReadinessSnapshot(notifications: true),
    const NotificationReadinessSnapshot(),
  ]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 차단·미확인 권한은 테스트 표시를 막고 설정만 열게 하며 채널 차단도 알림 스위치 꺼짐으로 반영하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets(
      '차단 또는 미확인 상태에서는 테스트를 막는다 ${state.notifications}/${state.medicationChannel}',
      (tester) async {
        final control = _Control()..state = state;
        await _open(tester, control);
        expect(
          tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
          isNull,
        );
        await _tap(tester, 'deviceNotificationSettingsRow');
        expect(control.settingsOpens, 1);
        expect(control.sends, 0);
        expect(control.permissionRequests, 0);
        if (state.notifications == true && state.medicationChannel == false) {
          expect(find.textContaining('복약 알림 꺼짐'), findsOneWidget);
          // 복약 알림이 오지 않으므로 스위치도 꺼짐으로 보인다.
          expect(
            tester
                .widget<SwitchListTile>(
                  find.byKey(const ValueKey('deviceNotificationSettingsRow')),
                )
                .value,
            isFalse,
          );
        }
      },
    );
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 정확한 알람 미허용에도 즉시 테스트를 허용하며 설정 이동·앱 복귀 후 새 허용 상태를 다시 읽어 스위치에 반영하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('정확한 시간 권한 없이도 즉시 테스트가 가능하고 복귀하면 다시 읽는다', (tester) async {
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        notifications: true,
        medicationChannel: true,
        exactAlarms: false,
      );
    await _open(tester, control);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNotNull,
    );
    await _tap(tester, 'deviceExactReminderSettingsRow');
    expect(control.exactRequests, 1);
    control.state = const NotificationReadinessSnapshot(
      notifications: true,
      medicationChannel: true,
      exactAlarms: true,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isTrue,
    );
    expect(control.refreshes, greaterThanOrEqualTo(3));
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 켜진 정확한 알람 행은 확인창 없이 설정을 열고 상태 변화가 없으면 켜짐을 유지하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('이미 허용된 권한도 설정을 열며 취소하면 켜진 상태를 유지한다', (tester) async {
    final control = _Control();
    await _open(tester, control);
    await _tap(tester, 'deviceExactReminderSettingsRow');
    expect(control.exactRequests, 1);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isTrue,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 설정 이동 대기 중 행을 잠그고 기존 값을 유지하며 중복 요청 없이 완료 뒤 실제 꺼짐 값을 반영하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('설정 이동 중 연타와 가짜 상태 변경을 막고 복귀 후 꺼짐을 반영한다', (tester) async {
    final control = _Control()..settingsGate = Completer<void>();
    await _open(tester, control);
    final phone = find.byKey(const ValueKey('deviceNotificationSettingsRow'));
    await tester.tap(phone);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(phone).value, isTrue);
    expect(tester.widget<SwitchListTile>(phone).onChanged, isNull);
    await tester.tap(phone);
    expect(control.settingsOpens, 1);
    control.state = const NotificationReadinessSnapshot(
      notifications: false,
      medicationChannel: true,
      exactAlarms: false,
    );
    control.settingsGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(phone).value, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
          )
          .value,
      isFalse,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 편집할 수 없는 정확한 알람 행을 숨기되 일반 알림이 허용된 테스트 버튼은 유지하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('별도 시간 권한이 없는 구형 Android에는 해당 스위치를 숨긴다', (tester) async {
    final control = _Control()
      ..state = const NotificationReadinessSnapshot(
        notifications: true,
        medicationChannel: true,
        exactAlarms: true,
        exactAlarmsEditable: false,
      );
    await _open(tester, control);
    expect(
      find.byKey(const ValueKey('deviceExactReminderSettingsRow')),
      findsNothing,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNotNull,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 지연 표시를 연속으로 눌러도 한 번만 요청하고 실패 뒤 재시도 성공 시 오류 안내를 지우는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('전송 중 연타를 막고 실패 후 재시도할 수 있다', (tester) async {
    final control = _Control()
      ..sendGate = Completer<void>()
      ..failSend = true;
    await _open(tester, control);
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    expect(control.sends, 1);
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('테스트 알림을 보내지 못했습니다'), findsOneWidget);
    control.failSend = false;
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sends, 2);
    expect(
      find.byKey(const ValueKey('notificationSettingsError')),
      findsNothing,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 표시 요청 중 위젯을 폐기한 뒤 완료해도 해제된 화면 갱신 예외가 없는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('전송 중 설정을 닫아도 완료 후 화면을 갱신하지 않는다', (tester) async {
    final control = _Control()..sendGate = Completer<void>();
    await _open(tester, control);
    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    control.sendGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 조회 실패는 두 행의 미확인 안내와 비활성 테스트로 나타나며 설정 이동 실패도 별도 오류로 표시하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('상태 조회 실패와 설정 이동 실패를 성공으로 표시하지 않는다', (tester) async {
    final control = _Control()
      ..failRefresh = true
      ..failSettings = true;
    await _open(tester, control);
    expect(find.text('상태를 확인하지 못했습니다.'), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNull,
    );
    await _tap(tester, 'deviceNotificationSettingsRow');
    expect(find.textContaining('설정을 열지 못했습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 모든 기능이 미지원이면 미지원 안내와 비활성 테스트 버튼을 표시하고 정확한 알람 행을 숨기는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('알림 미지원 환경은 미지원으로 표시한다', (tester) async {
    await _open(
      tester,
      _Control(supported: false, exact: false, settings: false),
    );
    expect(find.text('지원하지 않음'), findsOneWidget);
    expect(find.text('정확한 시간에 알림'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sendKey)).onPressed,
      isNull,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 정확한 알람·시스템 설정 미지원 환경에서 일반 알림 허용만으로 영어 테스트를 보내고 알림 행은 직접 권한 요청으로 연결하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('정확한 알림 권한이 없는 플랫폼에서는 채널 상태를 요구하지 않는다', (tester) async {
    final control = _Control(exact: false, settings: false)
      ..state = const NotificationReadinessSnapshot(notifications: true);
    await _open(tester, control, english: true);
    await _tap(tester, 'notificationSettingsSendTest');
    expect(control.sentLanguage, 'en');
    expect(find.text('On-time reminders'), findsNothing);
    await _tap(tester, 'deviceNotificationSettingsRow');
    expect(control.permissionRequests, 1);
  });

  for (final english in [false, true]) {
    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 폭 320·글씨 배율 2에서 한영 설정 행과 버튼을 스크롤해 누를 수 있고 높이 48 이상과 화면 오류 없음을 유지하는지 검증한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('320px 2배 글씨에서 설정과 버튼이 잘리지 않는다 english=$english', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, _Control(), english: english);
      for (final key in [
        'deviceNotificationSettingsRow',
        'deviceExactReminderSettingsRow',
        'notificationSettingsSendTest',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
