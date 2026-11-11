// 파일명: data_use_info_ui_boundary_test.dart
// 역할: 데이터 이용 안내의 설정 내 위치·내용·복귀와 큰 글씨 스크롤을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/data_use_info_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/notification_readiness_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

// 함수이름: main
// 함수역할: 계정별 데이터 안내와 복약 설정의 기기 알림 배치를 검증하는 화면 사례를 등록한다.
// 매개변수: 없음.
// 반환값: 없음. 데이터 안내 테스트 등록.
void main() {
  // 함수이름: testWidgets: '설정에서 데이터 안내를 열고 뒤로 돌아올 수 있다'
  // 함수역할: 계정 설정에서 데이터 안내를 열고 펼침 내용을 읽은 뒤 돌아와 복약 알림 화면을 연다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 데이터 안내는 계정에만 있고 알림 기기 설정은 복약 화면에만 있으며 각 뒤로가기 후 이전 화면이 복원된다.
  testWidgets('설정에서 데이터 안내를 열고 뒤로 돌아올 수 있다', (tester) async {
    final auth = AuthenticationControl.development();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: auth,
          onExtendedSettingSaveRequested: (setting) async =>
              UserSettingSaveResult(
                setting: setting,
                synchronizedWithServer: false,
              ),
          previewSpeaker: (text, setting, {onComplete}) async {},
          readinessControl: NotificationReadinessControl(
            notificationService: NotificationService.instance,
            supportsNotifications: false,
            supportsExactAlarms: false,
            supportsSystemSettings: false,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('settingsDataUseMenu')), findsNothing);
    expect(find.byKey(const ValueKey('settingsReadinessMenu')), findsNothing);
    final account = find.byKey(const ValueKey('settingsAccountMenu'));
    await tester.ensureVisible(account);
    await tester.tap(account);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settingsDataUseMenu'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(DataUseInfoUI), findsOneWidget);
    expect(find.text('개인정보의 이용과 보관 방법을 확인합니다.'), findsOneWidget);
    expect(find.textContaining('완전히 익명화되는 것은 아닙니다'), findsNothing);
    await tester.tap(find.text('계정과 복약 정보'));
    await tester.pumpAndSettle();
    expect(find.textContaining('완전히 익명화되는 것은 아닙니다'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로').last);
    await tester.pumpAndSettle();
    expect(find.byType(DataUseInfoUI), findsNothing);
    expect(row, findsOneWidget);
    expect(find.byKey(const ValueKey('settingsReadinessMenu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settingsReadinessMenu')), findsNothing);
    expect(find.byKey(const ValueKey('settingsDataUseMenu')), findsNothing);
    expect(find.byType(NotificationDeviceSettings), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notificationSettingsSendTest')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationDeviceSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: '기기 알림은 복약 및 알림 안에만 표시하고 별도 화면을 열지 않는다'
  // 함수역할: 영어 설정에서 복약 및 알림으로 진입하고 뒤로간 뒤 추가 프레임을 진행한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 기기 알림과 시험 알림은 해당 구역에만 있고 별도 설정 검사 화면이나 늦은 재등장이 없으며 예외가 없다.
  testWidgets('기기 알림은 복약 및 알림 안에만 표시하고 별도 화면을 열지 않는다', (tester) async {
    final auth = AuthenticationControl.development();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(language: 'en'),
          authenticationControl: auth,
          readinessControl: NotificationReadinessControl(
            notificationService: NotificationService.instance,
            supportsNotifications: false,
            supportsExactAlarms: false,
            supportsSystemSettings: false,
          ),
          onExtendedSettingSaveRequested: (setting) async =>
              UserSettingSaveResult(
                setting: setting,
                synchronizedWithServer: false,
              ),
          previewSpeaker: (text, setting, {onComplete}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NotificationDeviceSettings), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NotificationDeviceSettings), findsOneWidget);
    expect(find.text('Setup check'), findsNothing);
    expect(find.text('Send test notification'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationDeviceSettings), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NotificationDeviceSettings), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
    // 함수이름: testWidgets: '데이터 안내 전체 내용을 320px 2배 글씨로 읽을 수 있다 english=$english'
    // 함수역할: 320×640·2배 글씨에서 한국어/영어 데이터 안내의 각 항목을 펼치고 마지막 주의사항까지 스크롤한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 실제 처리 범위·읽기 쉬운 텍스트 안내를 볼 수 있고 CSV나 공개 게시판 업로드를 허용하는 잘못된 설명이 없으며 레이아웃 예외가 없다.
    testWidgets('데이터 안내 전체 내용을 320px 2배 글씨로 읽을 수 있다 english=$english', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(home: DataUseInfoUI(isEnglish: english)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          english
              ? 'Review how your information is used and stored.'
              : '개인정보의 이용과 보관 방법을 확인합니다.',
        ),
        findsOneWidget,
      );
      final renderedTexts = <String>{};
      for (var i = 0; i < 90; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
        renderedTexts.addAll(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
        );
        expect(tester.takeException(), isNull);
      }
      expect(
        renderedTexts,
        contains(english ? 'Sharing medication records' : '복약 기록 공유'),
      );
      await tester.scrollUntilVisible(
        find.text(english ? 'Sharing medication records' : '복약 기록 공유'),
        -300,
      );
      await tester.tap(
        find.text(english ? 'Sharing medication records' : '복약 기록 공유'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(english ? 'readable text' : '읽기 쉬운 텍스트'),
        findsOneWidget,
      );
      expect(find.textContaining('CSV'), findsNothing);
      await tester.scrollUntilVisible(
        find.text(
          english ? 'Access and manage your information' : '내 정보 확인과 관리',
        ),
        300,
      );
      await tester.ensureVisible(find.text(english ? 'Access and manage your information' : '내 정보 확인과 관리'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          english ? 'Access and manage your information' : '내 정보 확인과 관리',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining(english ? 'Do not post prescriptions' : '공개 게시판에 처방전', skipOffstage: false),
        250,
      );
      expect(
        find.textContaining(
          english ? 'Do not post prescriptions' : '공개 게시판에 처방전',
        ),
        findsOneWidget,
      );
    });
  }

  // 함수이름: testWidgets: '운영자 메모 대신 실제 삭제 범위와 무료 AI 제한을 안내한다'
  // 함수역할: 외부 AI 주의와 계정 삭제 범위를 각각 펼쳐 실제 안내를 읽는다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 민감정보 전송 금지와 사본의 즉시 동시 삭제가 아님을 알리며 운영자 배포 메모는 노출하지 않는다.
  testWidgets('운영자 메모 대신 실제 삭제 범위와 무료 AI 제한을 안내한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DataUseInfoUI(isEnglish: false)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('외부 AI 이용 시 주의'), 300);
    await tester.tap(find.text('외부 AI 이용 시 주의'));
    await tester.pumpAndSettle();
    expect(find.textContaining('개인정보·민감정보를 전송해서는 안 됩니다'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('계정 삭제 범위'), 300);
    await tester.tap(find.text('계정 삭제 범위'));
    await tester.pumpAndSettle();
    expect(find.textContaining('모든 사본이 같은 순간에 삭제되는 것은 아닙니다'), findsOneWidget);
    expect(find.textContaining('운영자는 공개 배포 전에'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
