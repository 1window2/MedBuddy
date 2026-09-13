// File Name: authentication_gate_test.dart
// Role: Regression coverage for authentication gate transitions from initialization to signed-in or
//   signed-out UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medbuddy_frontend/boundaries/authentication_gate.dart';

// Class Name: _FakeAuthenticationGateState
// Role: Mutable authentication state for exercising gate rebuilds without signing in.
// Responsibilities:
// - Expose whether the fake authentication initialization is still pending.
// - Expose whether the fake session is authenticated.
// - Replace both authentication flags and notify the gate to rebuild.
// Attributes:
// - _isInitializing (bool): Authentication gate initialization flag.
// - _isAuthenticated (bool): Authentication gate signed-in flag.
class _FakeAuthenticationGateState extends ChangeNotifier
    implements AuthenticationGateState {
  bool _isInitializing = true;
  bool _isAuthenticated = false;

  // Function Name: isInitializing
  // Description:
  // - Expose whether the fake authentication initialization is still pending.
  // Parameters:
  // - None.
  // Returns:
  // - The current initialization flag.
  @override
  bool get isInitializing => _isInitializing;

  // Function Name: isAuthenticated
  // Description:
  // - Expose whether the fake session is authenticated.
  // Parameters:
  // - None.
  // Returns:
  // - The current signed-in flag.
  @override
  bool get isAuthenticated => _isAuthenticated;

  // Function Name: update
  // Description:
  // - Replace both authentication flags and notify the gate to rebuild.
  // Parameters:
  // - isInitializing (bool): Whether authentication initialization is still pending.
  // - isAuthenticated (bool): Signed-in state to publish to the authentication gate.
  // Returns:
  // - No value; listeners observe the new gate state.
  void update({required bool isInitializing, required bool isAuthenticated}) {
    _isInitializing = isInitializing;
    _isAuthenticated = isAuthenticated;
    notifyListeners();
  }
}

// Function Name: main
// Description:
// - Register regression cases for authentication gate transitions from initialization to signed-in or
//   signed-out UI.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: replaces the startup spinner after authentication completes.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('replaces the startup spinner after authentication completes', (
    tester,
  ) async {
    final state = _FakeAuthenticationGateState();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationGate(
          state: state,
          unauthenticatedChild: const Text('signed out'),
          authenticatedChild: const Text('home'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('home'), findsNothing);

    state.update(isInitializing: false, isAuthenticated: true);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: shows authentication UI when initialization signs out.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('shows authentication UI when initialization signs out', (
    tester,
  ) async {
    final state = _FakeAuthenticationGateState();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticationGate(
          state: state,
          unauthenticatedChild: const Text('signed out'),
          authenticatedChild: const Text('home'),
        ),
      ),
    );

    state.update(isInitializing: false, isAuthenticated: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('signed out'), findsOneWidget);
  });
}
