import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_config.dart';

typedef IdTokenProvider = Future<String?> Function();
typedef AppCheckTokenProvider = Future<String?> Function();
typedef UnauthorizedResponseHandler = Future<void> Function();

class AppAttestationUnavailableException implements Exception {
  const AppAttestationUnavailableException();

  @override
  String toString() => 'Application attestation is temporarily unavailable.';
}

class AuthenticationUnavailableException implements Exception {
  const AuthenticationUnavailableException();

  @override
  String toString() => 'Authentication is temporarily unavailable.';
}

class ApiContractMismatchException implements Exception {
  const ApiContractMismatchException(this.serverVersion);

  final String serverVersion;

  @override
  String toString() => 'MedBuddy API contract is incompatible: $serverVersion';
}

class AuthenticatedApiClient extends http.BaseClient {
  static const Duration _authenticationTimeout = Duration(seconds: 10);
  static const Duration _appCheckTimeout = Duration(seconds: 10);
  final http.Client _inner;
  final IdTokenProvider _tokenProvider;
  final AppCheckTokenProvider _appCheckTokenProvider;
  final UnauthorizedResponseHandler? _onUnauthorized;
  final Uri _trustedBaseUri;

  AuthenticatedApiClient({
    http.Client? inner,
    IdTokenProvider? tokenProvider,
    AppCheckTokenProvider? appCheckTokenProvider,
    UnauthorizedResponseHandler? onUnauthorized,
    Uri? trustedBaseUri,
  }) : _inner = inner ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseIdToken,
       _appCheckTokenProvider = appCheckTokenProvider ?? _firebaseAppCheckToken,
       _onUnauthorized = onUnauthorized,
       _trustedBaseUri = trustedBaseUri ?? Uri.parse(ApiConfig.baseUrl);

  static Future<String?> _firebaseIdToken() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      return null;
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw const AuthenticationUnavailableException();
    }
    return token;
  }

  static Future<String?> _firebaseAppCheckToken() async {
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      return null;
    }
    final token = await FirebaseAppCheck.instance.getToken();
    if (token == null || token.trim().isEmpty) {
      throw const AppAttestationUnavailableException();
    }
    return token;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_hasTrustedOrigin(request.url)) {
      throw StateError(
        'Authenticated API requests must target the configured MedBuddy backend.',
      );
    }
    late final String? token;
    try {
      token = await _tokenProvider().timeout(_authenticationTimeout);
    } catch (_) {
      throw const AuthenticationUnavailableException();
    }
    if (AuthConfig.mode == AuthenticationMode.firebase &&
        (token == null || token.trim().isEmpty)) {
      throw const AuthenticationUnavailableException();
    }
    if (token != null && token.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    late final String? appCheckToken;
    try {
      appCheckToken = await _appCheckTokenProvider().timeout(_appCheckTimeout);
    } catch (_) {
      throw const AppAttestationUnavailableException();
    }
    if (AuthConfig.mode == AuthenticationMode.firebase &&
        (appCheckToken == null || appCheckToken.trim().isEmpty)) {
      throw const AppAttestationUnavailableException();
    }
    if (appCheckToken != null && appCheckToken.trim().isNotEmpty) {
      request.headers['X-Firebase-AppCheck'] = appCheckToken.trim();
    }
    request.headers.putIfAbsent('Accept', () => 'application/json');
    request.headers['X-MedBuddy-Api-Contract'] = ApiConfig.contractVersion;
    final response = await _inner.send(request);
    final serverContract =
        response.headers['x-medbuddy-api-contract']?.trim() ?? '';
    if (serverContract.isNotEmpty &&
        serverContract != ApiConfig.contractVersion) {
      await response.stream.drain<void>();
      throw ApiContractMismatchException(serverContract);
    }
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
