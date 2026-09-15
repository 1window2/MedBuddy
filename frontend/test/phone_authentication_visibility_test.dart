// File Name: phone_authentication_visibility_test.dart
// Role: Verifies that billing-dependent SMS authentication stays unavailable in the default
//   Spark-compatible beta build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';


// 함수이름: main
// 함수역할:
// - 베타 기본 전화 인증 비노출과 진입 차단 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: phone sign-in is hidden in the default beta build.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('phone sign-in is hidden in the default beta build', (
    tester,
  ) async {
    final control = AuthenticationControl.development();
    addTearDown(control.dispose);

    await tester.pumpWidget(
      MaterialApp(home: AuthenticationUI(control: control)),
    );

    expect(find.text('Continue with phone'), findsNothing);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('회원가입 없이 계속하기'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: authentication globe toggles Korean and English globally.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('authentication globe toggles Korean and English globally', (
    tester,
  ) async {
    final control = AuthenticationControl.development();
    final languageControl = AppLanguageControl(loadPersisted: false);
    addTearDown(control.dispose);
    addTearDown(languageControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationUI(
          control: control,
          languageControl: languageControl,
        ),
      ),
    );

    expect(find.text('로그인'), findsNWidgets(2));
    expect(find.text('회원가입 없이 계속하기'), findsOneWidget);

    await tester.tap(find.byKey(const Key('authentication-language-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(languageControl.language, 'en');
  });
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기본 베타 빌드에서는 SMS 다중 인증 설정을 표시하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('SMS MFA settings are hidden in the default beta build', (
    tester,
  ) async {
    final control = AuthenticationControl.development();
    addTearDown(control.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: control,
          onSettingSaveRequested:
              // Function Name: onSettingSaveRequested callback
              // Description:
              // - Acknowledge the configured local-only or synchronized settings save without persistence.
              // Parameters:
              // - fontSizeOption (String): Selected application text-size option. Accepted but not consumed by this
              //   fixture.
              // - readingSpeedOption (String): Selected voice-reading speed option. Accepted but not consumed by
              //   this fixture.
              // - language (String): Language code used for labels or notification content. Accepted but not
              //   consumed by this fixture.
              // Returns:
              // - A settings result marked synchronized.
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => UserSettingSaveResult(
                setting: const UserSetting(),
                synchronizedWithServer: true,
              ),
        ),
      ),
    );

    final accountMenu = find.byKey(const ValueKey('settingsAccountMenu'));
    await tester.ensureVisible(accountMenu);
    await tester.pumpAndSettle();
    await tester.tap(accountMenu);
    await tester.pumpAndSettle();

    expect(find.text('SMS two-step verification'), findsNothing);
    expect(find.text('Enable SMS MFA'), findsNothing);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: phone authentication entry points fail closed by default.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('phone authentication entry points fail closed by default', () async {
    final control = AuthenticationControl.development();
    addTearDown(control.dispose);

    await control.startPhoneSignIn('+821012345678');

    expect(control.canEnrollSmsMfa, isFalse);
    expect(
      control.errorMessage,
      'Phone authentication is unavailable in this beta build.',
    );
  });
}
