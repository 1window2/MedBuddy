// File Name: firebase_runtime_service.dart
// Role: Shares bounded Firebase and App Check initialization across application entry points.
import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'auth_config.dart';

// Class Name: FirebaseRuntimeService
// Role: Coordinates one native Firebase initialization attempt per isolate.
// Responsibilities:
// - Reuse in-flight work, clear failed attempts for retries, validate an existing app's identity, and select the build-appropriate App Check provider.
class FirebaseRuntimeService {
  // Function Name: FirebaseRuntimeService._
  // Description: Restricts Firebase and App Check initialization to the shared static initialization future.
  // Parameters:
  // - None.
  // Returns:
  // - FirebaseRuntimeService: the initialized instance.
  FirebaseRuntimeService._();

  static const Duration _initializationTimeout = Duration(seconds: 20);
  static Future<void>? _initializationFuture;

  // Function Name: initialize
  // Description: Awaits the shared native Firebase and App Check attempt with a 20-second caller timeout without starting overlapping initialization.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  static Future<void> initialize() async {
    final attempt = _initializationFuture ?? _startInitialization();
    await attempt.timeout(_initializationTimeout);
  }

  // Function Name: _startInitialization
  // Description: Starts native Firebase and App Check initialization once per isolate. Clears a failed native attempt while retaining an in-flight timed-out attempt, preventing overlapping native initialization calls on retry.
  // Parameters:
  // - None.
  // Returns:
  // - The shared native initialization attempt.
  static Future<void> _startInitialization() {
    final attempt = _initialize();
    _initializationFuture = attempt;
    unawaited(
      attempt.then<void>(
        // Function Name: then callback
        // Description: Converts successful Firebase initialization into the shared completion-only future.
        // Parameters:
        // - _ (void): Unused event value supplied by the enclosing callback contract.
        // Returns:
        // - No return value.
        (_) {},
        onError: /* Function Name: onError callback
         * Description: Releases the cached initialization attempt only if it is still the failed attempt, allowing a later retry.
         * Parameters:
         * - _ (Object): Unused event value supplied by the enclosing callback contract.
         * - _ (StackTrace): Unused event value supplied by the enclosing callback contract.
         * Returns:
         * - No return value.
         */(Object _, StackTrace _) {
          if (identical(_initializationFuture, attempt)) {
            _initializationFuture = null;
          }
        },
      ),
    );
    return attempt;
  }

  // Function Name: _initialize
  // Description: Creates Firebase when absent or validates the existing app identifiers, then activates Android App Check when required.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  static Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: AuthConfig.firebaseOptions);
    } else {
      final configured = AuthConfig.firebaseOptions;
      final existing = Firebase.app().options;
      if (existing.appId != configured.appId ||
          existing.projectId != configured.projectId ||
          existing.messagingSenderId != configured.messagingSenderId) {
        throw StateError(
          'The initialized Firebase application does not match MedBuddy configuration.',
        );
      }
    }
    if (AuthConfig.appCheckRequired) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: _androidProvider(),
      );
    }
  }

  // Function Name: _androidProvider
  // Description: Selects Play Integrity for release and profile builds and the debug App Check provider for development.
  // Parameters:
  // - None.
  // Returns:
  // - AndroidAppCheckProvider: Selects Play Integrity for release and profile builds and the debug App Check provider for development.
  static AndroidAppCheckProvider _androidProvider() {
    if (kReleaseMode || kProfileMode) {
      return const AndroidPlayIntegrityProvider();
    }
    return const AndroidDebugProvider();
  }
}
