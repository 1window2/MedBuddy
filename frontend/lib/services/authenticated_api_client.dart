// 파일명: authenticated_api_client.dart
// 역할: API 계약, Firebase 인증과 App Check 헤더를 일관되게 적용한다.

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
    request.headers.addAll(await buildAuthenticationHeaders(request.url));
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

  // 함수명: buildAuthenticationHeaders
  // 역할:
  // - REST와 WebSocket이 동일한 Firebase 및 API 계약 헤더를 사용하도록 한다.
  // - 설정된 MedBuddy 서버가 아닌 주소에는 인증 정보를 절대 제공하지 않는다.
  Future<Map<String, String>> buildAuthenticationHeaders(Uri requestUri) async {
    if (!_hasTrustedOrigin(requestUri)) {
      throw StateError(
        'Authenticated API requests must target the configured MedBuddy backend.',
      );
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-MedBuddy-Api-Contract': ApiConfig.contractVersion,
    };
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
      headers['Authorization'] = 'Bearer ${token.trim()}';
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
      headers['X-Firebase-AppCheck'] = appCheckToken.trim();
    }
    return headers;
  }

  bool _hasTrustedOrigin(Uri requestUri) {
    final requestScheme = requestUri.scheme.toLowerCase();
    if (!const {'http', 'https', 'ws', 'wss'}.contains(requestScheme)) {
      return false;
    }
    if (!_trustedBaseUri.isScheme('http') &&
        !_trustedBaseUri.isScheme('https')) {
      return false;
    }
    final normalizedRequestUri = requestUri.replace(
      scheme: switch (requestScheme) {
        'ws' => 'http',
        'wss' => 'https',
        _ => requestScheme,
      },
    );
    return normalizedRequestUri.origin == _trustedBaseUri.origin;
  }

  @override
  void close() {
    _inner.close();
  }
}
