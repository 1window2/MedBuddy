import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'auth_config.dart';

class FirebaseRuntimeService {
  FirebaseRuntimeService._();

  static const Duration _initializationTimeout = Duration(seconds: 20);
  static Future<void>? _initializationFuture;

  static Future<void> initialize() async {
    final attempt = _initializationFuture ?? _startInitialization();
    await attempt.timeout(_initializationTimeout);
  }

  // Function Name: _startInitialization
  // Description:
  // - Starts native Firebase and App Check initialization once per isolate.
  // - Clears a failed native attempt while retaining an in-flight timed-out
  //   attempt, preventing overlapping native initialization calls on retry.
  // Returns:
  // - The shared native initialization attempt.
  static Future<void> _startInitialization() {
    final attempt = _initialize();
    _initializationFuture = attempt;
    unawaited(
      attempt.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_initializationFuture, attempt)) {
            _initializationFuture = null;
          }
        },
      ),
    );
    return attempt;
  }

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
    await FirebaseAppCheck.instance.activate(
      providerAndroid: _androidProvider(),
    );
  }

  static AndroidAppCheckProvider _androidProvider() {
    if (kReleaseMode || kProfileMode) {
      return const AndroidPlayIntegrityProvider();
    }
    return const AndroidDebugProvider();
  }
}
