// File Name: authentication_gate.dart
// Role: UI boundaries and helpers for root content selection during authentication startup and session changes.

import 'package:flutter/material.dart';

import '../entities/authentication_gate_state_entity.dart';
export '../entities/authentication_gate_state_entity.dart';

// Class Name: AuthenticationGate
// Role: Represents root content selected by initialization and sign-in state.
// Responsibilities:
// - Keeps MaterialApp and its Navigator stable during Firebase initialization.
// - Replaces the startup indicator without relying on MaterialApp.home updates.
// - Selects signed-out or signed-in content from verified session state.
// Attributes:
// - state (AuthenticationGateState): Observable secure-startup and authenticated-session state.
// - unauthenticatedChild (Widget): Root content shown while signed out.
// - authenticatedChild (Widget): Root content shown after authentication is confirmed.
class AuthenticationGate extends StatelessWidget {
  final AuthenticationGateState state;
  final Widget unauthenticatedChild;
  final Widget authenticatedChild;

  // Function Name: AuthenticationGate
  // Description: Initializes root content selected by initialization and sign-in state with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - state (AuthenticationGateState): Observable secure-startup and authenticated-session state.
  // - unauthenticatedChild (Widget): Root content shown while signed out.
  // - authenticatedChild (Widget): Root content shown after authentication is confirmed.
  // Returns: Initialized AuthenticationGate instance.
  const AuthenticationGate({
    super.key,
    required this.state,
    required this.unauthenticatedChild,
    required this.authenticatedChild,
  });

  // Function Name: build
  // Description: Renders root content selected by initialization and sign-in state from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for root content selected by initialization and sign-in state.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      // Function Name: build.builder callback
      // Description: Composes root content selected by initialization and sign-in state with Scaffold for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
      // Returns: Widget subtree for the described layout or fallback.
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
