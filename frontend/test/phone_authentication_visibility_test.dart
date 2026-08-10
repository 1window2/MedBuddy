import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
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
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
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
