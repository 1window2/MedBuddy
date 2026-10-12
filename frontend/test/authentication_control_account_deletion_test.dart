// File Name: authentication_control_account_deletion_test.dart
// Role: Verifies fail-closed local teardown after server-managed deletion.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';

// Function Name: main
// Description:
// - Register regression cases for account deletion, authenticated cleanup, and provider sign-out
//   ordering.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 로컬 데모의 로그아웃은 공급자 호출·정리·상태 알림 없이 같은 세션을 유지한다.
  test('disabled-auth sign out preserves the demo without cleanup', () async {
    final control = AuthenticationControl.development();
    addTearDown(control.dispose);
    final session = control.session;
    var cleanups = 0;
    var changes = 0;
    control.setBeforeSignOut(() async {
      cleanups++;
      throw StateError('Cleanup must not run in the local demo.');
    });
    control.addListener(() => changes++);

    await control.signOut();
    await control.signOut();

    expect(cleanups, 0);
    expect(changes, 0);
    expect(control.session, same(session));
    expect(control.isAuthenticated, isTrue);
    expect(control.isBusy, isFalse);
    expect(control.errorMessage, isNull);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: account deletion clears the local session before provider failure.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'account deletion clears the local session before provider failure',
    () async {
      final control = AuthenticationControl.development();
      var providerSignOutCalled = false;

      await expectLater(
        // Function Name: finishAccountDeletionForTest callback
        // Description:
        // - Record provider sign-out and fail it after server-managed account deletion.
        // Parameters:
        // - None.
        // Returns:
        // - A failed Future with the simulated provider exception.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: account deletion remains signed out after provider success.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('account deletion remains signed out after provider success', () async {
    final control = AuthenticationControl.development();

    // Function Name: finishAccountDeletionForTest callback
    // Description:
    // - Complete provider sign-out successfully without contacting a provider.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes immediately.
    await control.finishAccountDeletionForTest(() async {});

    expect(control.session, isNull);
    expect(control.isAuthenticated, isFalse);
    expect(control.errorMessage, isNull);
    control.dispose();
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: sign out completes authenticated cleanup before provider sign out.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'sign out completes authenticated cleanup before provider sign out',
    () async {
      final control = AuthenticationControl.development();
      final events = <String>[];
      // Function Name: setBeforeSignOut callback
      // Description:
      // - Append authenticated cleanup to the event log before provider sign-out.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completion after recording cleanup.
      control.setBeforeSignOut(() async {
        events.add('cleanup');
      });

      // Function Name: signOutForTest callback
      // Description:
      // - Append provider sign-out to the event log to verify cleanup ordering.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completion after recording provider sign-out.
      await control.signOutForTest(() async {
        events.add('provider-sign-out');
      });

      expect(events, <String>['cleanup', 'provider-sign-out']);
      // The shared sign-out body also publishes the empty session.
      expect(control.session, isNull);
      expect(control.isAuthenticated, isFalse);
      expect(control.errorMessage, isNull);
      control.dispose();
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: sign out keeps provider session when authenticated cleanup fails.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'sign out keeps provider session when authenticated cleanup fails',
    () async {
      final control = AuthenticationControl.development();
      var providerSignOutCalled = false;
      // Function Name: setBeforeSignOut callback
      // Description:
      // - Fail authenticated push-token cleanup before the provider session is released.
      // Parameters:
      // - None.
      // Returns:
      // - A Future that throws StateError for unregister failure.
      control.setBeforeSignOut(() async {
        throw StateError('push token unregister failed');
      });

      await expectLater(
        // Function Name: signOutForTest callback
        // Description:
        // - Record whether provider sign-out ran after a failed cleanup attempt.
        // Parameters:
        // - None.
        // Returns:
        // - Future<void>; completion after setting the invocation flag.
        control.signOutForTest(() async {
          providerSignOutCalled = true;
        }),
        throwsStateError,
      );

      expect(providerSignOutCalled, isFalse);
      expect(control.isAuthenticated, isTrue);
      control.dispose();
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: expired session runs cleanup before forced provider sign out.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'expired session runs cleanup before forced provider sign out',
    () async {
      final control = AuthenticationControl.development();
      final events = <String>[];
      // Function Name: setBeforeSignOut callback
      // Description:
      // - Record cleanup and reject it as already unauthorized during forced session invalidation.
      // Parameters:
      // - None.
      // Returns:
      // - A Future that fails with the simulated unauthorized-cleanup error.
      control.setBeforeSignOut(() async {
        events.add('cleanup');
        throw StateError('server token is already unauthorized');
      });

      // Function Name: invalidateUnauthorizedSessionForTest callback
      // Description:
      // - Append provider sign-out to the event log to verify cleanup ordering.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completion after recording provider sign-out.
      await control.invalidateUnauthorizedSessionForTest(() async {
        events.add('provider-sign-out');
      });

      expect(events, <String>['cleanup', 'provider-sign-out']);
      expect(control.session, isNull);
      expect(control.isAuthenticated, isFalse);
      expect(control.errorMessage, contains('expired'));
      control.dispose();
    },
  );
}
