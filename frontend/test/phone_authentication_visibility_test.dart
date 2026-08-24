import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// File Name: phone_authentication_visibility_test.dart
// Role: Verifies that billing-dependent SMS authentication stays unavailable
// in the default Spark-compatible beta build.

void main() {
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
