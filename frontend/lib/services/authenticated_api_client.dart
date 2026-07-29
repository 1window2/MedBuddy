import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_config.dart';

typedef IdTokenProvider = Future<String?> Function();
typedef UnauthorizedResponseHandler = Future<void> Function();

class AuthenticatedApiClient extends http.BaseClient {
  final http.Client _inner;
  final IdTokenProvider _tokenProvider;
  final UnauthorizedResponseHandler? _onUnauthorized;
  final Uri _trustedBaseUri;

  AuthenticatedApiClient({
    http.Client? inner,
    IdTokenProvider? tokenProvider,
    UnauthorizedResponseHandler? onUnauthorized,
    Uri? trustedBaseUri,
  }) : _inner = inner ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseIdToken,
       _onUnauthorized = onUnauthorized,
       _trustedBaseUri = trustedBaseUri ?? Uri.parse(ApiConfig.baseUrl);

  static Future<String?> _firebaseIdToken() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      return null;
    }
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_hasTrustedOrigin(request.url)) {
      throw StateError(
        'Authenticated API requests must target the configured MedBuddy backend.',
      );
    }
    final token = await _tokenProvider();
    if (token != null && token.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    request.headers.putIfAbsent('Accept', () => 'application/json');
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      await _onUnauthorized?.call();
    }
    return response;
  }

  bool _hasTrustedOrigin(Uri requestUri) {
    if (!requestUri.isScheme('http') && !requestUri.isScheme('https')) {
      return false;
    }
    if (!_trustedBaseUri.isScheme('http') &&
        !_trustedBaseUri.isScheme('https')) {
      return false;
    }
    return requestUri.origin == _trustedBaseUri.origin;
  }

  @override
  void close() {
    _inner.close();
  }
}
