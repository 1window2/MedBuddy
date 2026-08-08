import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum AuthenticationMode { disabled, firebase }

class AuthConfig {
  static const String _modeValue = String.fromEnvironment(
    'MEDBUDDY_AUTH_MODE',
    defaultValue: 'disabled',
  );

  static AuthenticationMode get mode => switch (_modeValue.toLowerCase()) {
    'disabled' => AuthenticationMode.disabled,
    'firebase' => AuthenticationMode.firebase,
    _ => throw StateError('Unsupported MEDBUDDY_AUTH_MODE: $_modeValue'),
  };

  static const String firebaseApiKey = String.fromEnvironment(
    'MEDBUDDY_FIREBASE_API_KEY',
  );
  static const String firebaseAppId = String.fromEnvironment(
    'MEDBUDDY_FIREBASE_APP_ID',
  );
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'MEDBUDDY_FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'MEDBUDDY_FIREBASE_PROJECT_ID',
  );
  static const String authEmulatorHost = String.fromEnvironment(
    'MEDBUDDY_FIREBASE_AUTH_EMULATOR_HOST',
  );
  static const int authEmulatorPort = int.fromEnvironment(
    'MEDBUDDY_FIREBASE_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  static const String localUserHash = String.fromEnvironment(
    'MEDBUDDY_LOCAL_USER_HASH',
  );

  static void validate() {
    if ((kReleaseMode || kProfileMode) && mode != AuthenticationMode.firebase) {
      throw StateError(
        'Release and profile builds require MEDBUDDY_AUTH_MODE=firebase.',
      );
    }
    if (mode != AuthenticationMode.firebase) {
      return;
    }
    if (firebaseApiKey.isEmpty ||
        firebaseAppId.isEmpty ||
        firebaseMessagingSenderId.isEmpty ||
        firebaseProjectId.isEmpty) {
      throw StateError('Firebase configuration is incomplete.');
    }
  }

  static FirebaseOptions get firebaseOptions {
    validate();
    return const FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
    );
  }
}
