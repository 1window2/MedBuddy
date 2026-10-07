// File Name: authenticated_api_client.dart
// Role: Applies backend-origin trust, API contract, Firebase identity, and App Check policy to HTTP requests.

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_config.dart';

// Function Name: IdTokenProvider
// Description: Supplies the current Firebase identity token asynchronously; null is permitted only when the client authentication policy allows it.
// Parameters:
// - None.
// Returns:
// - Future<String?>: Supplies the current Firebase identity token asynchronously; null is permitted only when the client authentication policy allows it.
typedef IdTokenProvider = Future<String?> Function();
// Function Name: AppCheckTokenProvider
// Description: Supplies an application-attestation token asynchronously for requests requiring Firebase App Check.
// Parameters:
// - None.
// Returns:
// - Future<String?>: Supplies an application-attestation token asynchronously for requests requiring Firebase App Check.
typedef AppCheckTokenProvider = Future<String?> Function();
// Function Name: UnauthorizedResponseHandler
// Description: Defines asynchronous session invalidation and cleanup triggered after the backend returns HTTP 401.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef UnauthorizedResponseHandler = Future<void> Function();

// Class Name: AppAttestationUnavailableException
// Role: Signals that a required App Check token cannot be obtained.
// Responsibilities:
// - Distinguish application-attestation failure from user authentication failure without exposing provider internals.
class AppAttestationUnavailableException implements Exception {
  // Function Name: AppAttestationUnavailableException
  // Description: Creates the fixed application-attestation failure used when token retrieval is unavailable or times out.
  // Parameters:
  // - None.
  // Returns:
  // - AppAttestationUnavailableException: the initialized instance.
  const AppAttestationUnavailableException();

  // Function Name: toString
  // Description: Provides the stable user-facing description of temporary application-attestation unavailability.
  // Parameters:
  // - None.
  // Returns:
  // - String: a diagnostic representation of this error or value.
  @override
  String toString() => 'Application attestation is temporarily unavailable.';
}

// Class Name: AuthenticationUnavailableException
// Role: Signals that the current Firebase identity cannot authorize a request.
// Responsibilities:
// - Distinguish missing or timed-out identity tokens from transport and attestation failures.
class AuthenticationUnavailableException implements Exception {
  // Function Name: AuthenticationUnavailableException
  // Description: Creates the fixed authentication failure used when a usable identity token is unavailable.
  // Parameters:
  // - None.
  // Returns:
  // - AuthenticationUnavailableException: the initialized instance.
  const AuthenticationUnavailableException();

  // Function Name: toString
  // Description: Provides the stable user-facing description of temporary authentication unavailability.
  // Parameters:
  // - None.
  // Returns:
  // - String: a diagnostic representation of this error or value.
  @override
  String toString() => 'Authentication is temporarily unavailable.';
}

// 클래스명: ApiContractMismatchException
// 역할: 서버가 반환한 API 계약 버전이 앱과 맞지 않음을 표현한다.
// 주요 책임:
// - 서버 버전을 보존하여 업데이트 안내와 버전 불일치 진단에 제공한다.
// 속성:
// - serverVersion (String): 응답 헤더에 기록된 서버 API 계약 버전
class ApiContractMismatchException implements Exception {
  // 함수이름: ApiContractMismatchException
  // 함수역할: 호환되지 않은 서버 계약 버전을 예외에 보존한다.
  // 매개변수:
  // - serverVersion (String): 응답 헤더에 기록된 서버 API 계약 버전
  // 반환값:
  // - ApiContractMismatchException: 초기화된 인스턴스.
  const ApiContractMismatchException(this.serverVersion);

  final String serverVersion;

  // 함수이름: toString
  // 함수역할: 앱과 호환되지 않는 서버 계약 버전을 포함한 진단 문자열을 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 오류 또는 값의 진단용 문자열 표현.
  @override
  String toString() => 'MedBuddy API contract is incompatible: $serverVersion';
}

// Class Name: AuthenticatedApiClient
// Role: Adds trusted-backend authentication and attestation headers to HTTP requests.
// Responsibilities:
// - Enforce same-origin token delivery, bound token retrieval, reject contract mismatches, and invoke session cleanup on HTTP 401.
// Attributes:
// - _inner (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
// - _tokenProvider (IdTokenProvider): Asynchronous provider of the current user's identity token.
// - _appCheckTokenProvider (AppCheckTokenProvider): Asynchronous provider of the current app-attestation token.
// - _appCheckRequired (bool): Whether requests require App Check attestation.
// - _onUnauthorized (UnauthorizedResponseHandler?): Session-cleanup callback after a server HTTP 401 response.
// - _trustedBaseUri (Uri): MedBuddy origin permitted to receive authentication headers.
class AuthenticatedApiClient extends http.BaseClient {
  static const Duration _authenticationTimeout = Duration(seconds: 10);
  static const Duration _appCheckTimeout = Duration(seconds: 10);
  final http.Client _inner;
  final IdTokenProvider _tokenProvider;
  final AppCheckTokenProvider _appCheckTokenProvider;
  final bool _appCheckRequired;
  final UnauthorizedResponseHandler? _onUnauthorized;
  final Uri _trustedBaseUri;

  // Function Name: AuthenticatedApiClient
  // Description: Wraps a transport client with injected or Firebase-backed token providers, App Check requirements, trusted origin, and optional unauthorized-session handling.
  // Parameters:
  // - inner (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // - tokenProvider (IdTokenProvider?): Asynchronous provider of the current user's identity token.
  // - appCheckTokenProvider (AppCheckTokenProvider?): Asynchronous provider of the current app-attestation token.
  // - appCheckRequired (bool?): Whether requests require App Check attestation.
  // - onUnauthorized (UnauthorizedResponseHandler?): Session-cleanup callback after a server HTTP 401 response.
  // - trustedBaseUri (Uri?): MedBuddy origin permitted to receive authentication headers.
  // Returns:
  // - AuthenticatedApiClient: the initialized instance.
  AuthenticatedApiClient({
    http.Client? inner,
    IdTokenProvider? tokenProvider,
    AppCheckTokenProvider? appCheckTokenProvider,
    bool? appCheckRequired,
    UnauthorizedResponseHandler? onUnauthorized,
    Uri? trustedBaseUri,
  }) : _inner = inner ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseIdToken,
       _appCheckTokenProvider = appCheckTokenProvider ?? _firebaseAppCheckToken,
       _appCheckRequired = appCheckRequired ?? AuthConfig.appCheckRequired,
       _onUnauthorized = onUnauthorized,
       _trustedBaseUri = trustedBaseUri ?? Uri.parse(ApiConfig.baseUrl);

  // Function Name: _firebaseIdToken
  // Description: Returns no token in explicit local mode; otherwise requires a nonblank current-user Firebase ID token.
  // Parameters:
  // - None.
  // Returns:
  // - Future<String?>: No token in explicit local mode; otherwise requires a nonblank current-user Firebase ID token.
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

  // Function Name: _firebaseAppCheckToken
  // Description: Returns no attestation in explicit local mode; otherwise requires a nonblank Firebase App Check token.
  // Parameters:
  // - None.
  // Returns:
  // - Future<String?>: No attestation in explicit local mode; otherwise requires a nonblank Firebase App Check token.
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

  // 함수이름: send
  // 함수역할: 신뢰 주소의 인증 헤더를 붙여 요청하고 서버 계약 불일치 응답은 소모 후 거부하며 401에는 세션 무효화 콜백을 실행한다.
  // 매개변수:
  // - request (http.BaseRequest): 인증·신뢰 범위 검증 후 전송할 HTTP 요청
  // 반환값:
  // - Future<http.StreamedResponse>: 신뢰 주소의 인증 헤더를 붙여 요청하고 서버 계약 불일치 응답은 소모 후 거부하며 401에는 세션 무효화 콜백을 실행한다.
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

  // Function Name: buildAuthenticationHeaders
  // Description: Builds shared REST and WebSocket contract, bearer, and App Check headers only for the configured backend origin, with bounded token retrieval and typed failures.
  // Parameters:
  // - requestUri (Uri): Destination URI that would receive authentication headers.
  // Returns:
  // - Future<Map<String, String>>: Builds shared REST and WebSocket contract, bearer, and App Check headers only for the configured backend origin, with bounded token retrieval and typed failures.
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
    if (_appCheckRequired) {
      late final String? appCheckToken;
      try {
        appCheckToken = await _appCheckTokenProvider().timeout(
          _appCheckTimeout,
        );
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
    }
    return headers;
  }

  // 함수이름: _hasTrustedOrigin
  // 함수역할: HTTP·HTTPS 및 대응 WebSocket 스킴만 허용하고 ws·wss를 HTTP 기준으로 정규화해 설정 서버와 origin이 같은지 확인한다.
  // 매개변수:
  // - requestUri (Uri): 인증 헤더를 제공할 대상 주소
  // 반환값:
  // - bool: HTTP·HTTPS 및 대응 WebSocket 스킴만 허용하고 ws·wss를 HTTP 기준으로 정규화해 설정 서버와 origin이 같은지 확인한다.
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

  // Function Name: close
  // Description: Closes the wrapped HTTP transport and its persistent connections.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  @override
  void close() {
    _inner.close();
  }
}
