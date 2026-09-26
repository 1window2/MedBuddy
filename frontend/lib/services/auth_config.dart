// File Name: auth_config.dart
// Role: Reads build-time Firebase authentication settings and enforces secure release configuration.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// Class Name: AuthenticationMode
// Role: Selects explicit local development identity or Firebase-backed authentication.
// Responsibilities:
// - Keep disabled authentication distinguishable from the secure mode required by release and profile builds.
enum AuthenticationMode { disabled, firebase }

// Class Name: AuthConfig
// Role: Holds authentication, emulator, App Check, and Firebase build configuration.
// Responsibilities:
// - Reject unsupported modes or missing Firebase identifiers and expose validated FirebaseOptions.
// Attributes:
// - appCheckRequired (bool): Whether requests require App Check attestation.
class AuthConfig {
  static const String _modeValue = String.fromEnvironment(
    'MEDBUDDY_AUTH_MODE',
    defaultValue: 'disabled',
  );

  // Function Name: mode
  // Description: Parses the configured authentication mode case-insensitively and rejects values other than disabled or firebase.
  // Parameters:
  // - None.
  // Returns:
  // - AuthenticationMode: Parses the configured authentication mode case-insensitively and rejects values other than disabled or firebase.
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
  static const bool phoneAuthenticationEnabled = bool.fromEnvironment(
    'MEDBUDDY_PHONE_AUTH_ENABLED',
    defaultValue: false,
  );
  static const bool appCheckRequired = bool.fromEnvironment(
    'MEDBUDDY_FIREBASE_APP_CHECK_REQUIRED',
    defaultValue: true,
  );

  // Function Name: validate
  // Description: Requires Firebase mode for release and profile builds and checks the four required Firebase identifiers whenever secure authentication is enabled.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
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

  // Function Name: firebaseOptions
  // Description: Validates authentication configuration before constructing the Firebase application options from build-time values.
  // Parameters:
  // - None.
  // Returns:
  // - FirebaseOptions: Validates authentication configuration before constructing the Firebase application options from build-time values.
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
