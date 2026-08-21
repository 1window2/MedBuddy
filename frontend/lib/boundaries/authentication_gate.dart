// File Name: authentication_gate.dart
// Role: Keeps authentication-state transitions inside the active root route.

import 'package:flutter/material.dart';

import '../entities/authentication_gate_state_entity.dart';
export '../entities/authentication_gate_state_entity.dart';

// Class Name: AuthenticationGate
// Role: Switches the active root-route content as authentication changes.
// Responsibilities:
// - Keeps MaterialApp and its Navigator stable during Firebase initialization.
// - Replaces the startup indicator without relying on MaterialApp.home updates.
// - Selects signed-out or signed-in content from verified session state.
class AuthenticationGate extends StatelessWidget {
  final AuthenticationGateState state;
  final Widget unauthenticatedChild;
  final Widget authenticatedChild;

  const AuthenticationGate({
    super.key,
    required this.state,
    required this.unauthenticatedChild,
    required this.authenticatedChild,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (state.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!state.isAuthenticated) {
          return unauthenticatedChild;
        }
        return authenticatedChild;
      },
    );
  }
}
