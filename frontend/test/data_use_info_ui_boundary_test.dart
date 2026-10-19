// 파일명: data_use_info_ui_boundary_test.dart
// 역할: 데이터 안내의 실제 처리 설명, 설정 연결과 큰 글씨 탐색을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/data_use_info_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/notification_readiness_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

void main() {
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
            loadHasMedication: () async => true,
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
    expect(find.byKey(const ValueKey('settingsReadinessMenu')), findsOneWidget);
    expect(find.byKey(const ValueKey('settingsDataUseMenu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settingsReadinessMenu')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReadinessUI), findsOneWidget);
    expect(find.text('약 등록과 알림 수신 상태를 점검합니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settingsReadinessMenu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('설정에서 점검을 선택했을 때만 열고 뒤로가기 뒤 다시 열지 않는다', (tester) async {
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
            loadHasMedication: () async => true,
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
    expect(find.byType(NotificationReadinessUI), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settingsReadinessMenu')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReadinessUI), findsOneWidget);
    expect(find.text('Setup check'), findsOneWidget);
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReadinessUI), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NotificationReadinessUI), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
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
      for (var i = 0; i < 90; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(
        find.textContaining(
          english ? 'Do not post prescriptions' : '공개 게시판에 처방전',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('운영자 메모 대신 실제 삭제 범위와 무료 AI 제한을 안내한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DataUseInfoUI(isEnglish: false)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('외부 AI 이용 시 주의'), 300);
    expect(find.textContaining('개인정보·민감정보를 전송해서는 안 됩니다'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('계정 삭제 범위'), 300);
    expect(find.textContaining('모든 사본이 같은 순간에 삭제되는 것은 아닙니다'), findsOneWidget);
    expect(find.textContaining('운영자는 공개 배포 전에'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
