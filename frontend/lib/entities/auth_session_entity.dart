class AuthSession {
  final String userHash;
  final String? email;
  final bool emailVerified;
  final bool authenticated;

  const AuthSession({
    required this.userHash,
    required this.authenticated,
    this.email,
    this.emailVerified = false,
  });

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
