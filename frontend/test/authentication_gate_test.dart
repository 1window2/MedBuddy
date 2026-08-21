import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medbuddy_frontend/boundaries/authentication_gate.dart';

class _FakeAuthenticationGateState extends ChangeNotifier
    implements AuthenticationGateState {
  bool _isInitializing = true;
  bool _isAuthenticated = false;

  @override
  bool get isInitializing => _isInitializing;

  @override
  bool get isAuthenticated => _isAuthenticated;

  void update({required bool isInitializing, required bool isAuthenticated}) {
    _isInitializing = isInitializing;
    _isAuthenticated = isAuthenticated;
    notifyListeners();
  }
}

void main() {
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
