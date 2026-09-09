// File Name: auth_session_entity.dart
// Role: Defines the backend-authenticated identity snapshot used by the sign-in gate.
// Class Name: AuthSession
// Role: Carries the MedBuddy user key and verified authentication attributes returned by the backend.
// Responsibilities:
// - Reject sessions without a user key and preserve optional email and verification state.
// Attributes:
// - userHash (String): Current user hash defining ownership, display, or persistence scope.
// - email (String?): Email used for sign-in, verification, or password reset.
// - emailVerified (bool): Whether the identity provider has verified the email.
// - authenticated (bool): Whether the backend confirmed an authenticated session.
class AuthSession {
  final String userHash;
  final String? email;
  final bool emailVerified;
  final bool authenticated;

  // Function Name: AuthSession
  // Description: Captures the backend user key, authenticated flag, and optional email verification state for the application gate.
  // Parameters:
  // - userHash (String): Current user hash defining ownership, display, or persistence scope.
  // - authenticated (bool): Whether the backend confirmed an authenticated session.
  // - email (String?): Email used for sign-in, verification, or password reset.
  // - emailVerified (bool): Whether the identity provider has verified the email.
  // Returns:
  // - AuthSession: the initialized instance.
  const AuthSession({
    required this.userHash,
    required this.authenticated,
    this.email,
    this.emailVerified = false,
  });

  // Function Name: AuthSession.fromJson
  // Description: Requires a nonblank backend user key, normalizes optional email text, and accepts authentication and email verification only as true booleans.
  // Parameters:
  // - json (Map<String, dynamic>): Backend response or stored JSON object for this model.
  // Returns:
  // - AuthSession: the decoded record after field validation and default handling.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userHash = (json['user_hash'] ?? '').toString().trim();
    if (userHash.isEmpty) {
      throw const FormatException('Authentication session has no user key.');
    }
    final email = (json['email'] ?? '').toString().trim();
    return AuthSession(
      userHash: userHash,
      authenticated: json['authenticated'] == true,
      email: email.isEmpty ? null : email,
      emailVerified: json['email_verified'] == true,
    );
  }
}
