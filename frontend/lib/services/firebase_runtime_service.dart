import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'auth_config.dart';

class FirebaseRuntimeService {
  FirebaseRuntimeService._();

  static Future<void>? _initializationFuture;

  static Future<void> initialize() {
    return _initializationFuture ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
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
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  static AndroidAppCheckProvider _androidProvider() {
    if (kReleaseMode || kProfileMode) {
      return const AndroidPlayIntegrityProvider();
    }
    return const AndroidDebugProvider();
  }
}
