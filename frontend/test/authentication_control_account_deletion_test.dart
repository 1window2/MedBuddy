// File Name: authentication_control_account_deletion_test.dart
// Role: Verifies fail-closed local teardown after server-managed deletion.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'account deletion clears the local session before provider failure',
    () async {
      final control = AuthenticationControl.development();
      var providerSignOutCalled = false;

      await expectLater(
        control.finishAccountDeletionForTest(() async {
          providerSignOutCalled = true;
          throw Exception('provider unavailable');
        }),
        throwsStateError,
      );

      expect(providerSignOutCalled, isTrue);
      expect(control.session, isNull);
      expect(control.isAuthenticated, isFalse);
      expect(control.errorMessage, isNotEmpty);
      control.dispose();
    },
  );

  test('account deletion remains signed out after provider success', () async {
    final control = AuthenticationControl.development();

    await control.finishAccountDeletionForTest(() async {});

    expect(control.session, isNull);
    expect(control.isAuthenticated, isFalse);
    expect(control.errorMessage, isNull);
    control.dispose();
  });

  test(
    'sign out completes authenticated cleanup before provider sign out',
    () async {
      final control = AuthenticationControl.development();
      final events = <String>[];
      control.setBeforeSignOut(() async {
        events.add('cleanup');
      });

      await control.signOutForTest(() async {
        events.add('provider-sign-out');
      });

      expect(events, <String>['cleanup', 'provider-sign-out']);
      control.dispose();
    },
  );

  test(
    'sign out keeps provider session when authenticated cleanup fails',
    () async {
      final control = AuthenticationControl.development();
      var providerSignOutCalled = false;
      control.setBeforeSignOut(() async {
        throw StateError('push token unregister failed');
      });

      await expectLater(
        control.signOutForTest(() async {
          providerSignOutCalled = true;
        }),
        throwsStateError,
      );

      expect(providerSignOutCalled, isFalse);
      control.dispose();
    },
  );
}
