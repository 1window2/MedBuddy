// File Name: api_config.dart
// Role: Defines backend endpoint construction, contract versioning, and development-only local URL exceptions.


import 'package:flutter/foundation.dart';

// 클래스명: ApiConfig
// 역할: 빌드에서 지정한 복약 API 주소와 계약 버전을 앱 전체에 제공한다.
// 주요 책임:
// - 같은 서버의 인증·약국·채팅 주소를 만들고 운영 HTTPS 및 제한된 로컬 개발 주소 정책을 검증한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
class ApiConfig {
  static const bool _localHttpRequested = bool.fromEnvironment(
    'MEDBUDDY_ALLOW_LOCAL_HTTP',
    defaultValue: true,
  );
  static const bool _allowLocalHttpForDevelopment =
      kDebugMode && _localHttpRequested;

  static const String contractVersion = String.fromEnvironment(
    'MEDBUDDY_API_CONTRACT_VERSION',
    defaultValue: 'medbuddy-api-v1',
  );

  static const String baseUrl = String.fromEnvironment(
    'MEDBUDDY_API_BASE_URL',
    defaultValue: 'https://api.medbuddy.pp.ua/api/v1/medication',
  );

  // 함수이름: authSessionUrl
  // 함수역할: 설정된 복약 API와 같은 서버의 인증 세션 handshake 주소를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 설정된 복약 API와 같은 서버의 인증 세션 handshake 주소를 제공한다.
  static String get authSessionUrl {
    return authUrl('/session');
  }

  // 함수이름: pushTokenUrl
  // 함수역할: 현재 사용자 푸시 토큰 등록·해제에 사용할 인증 API 주소를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 현재 사용자 푸시 토큰 등록·해제에 사용할 인증 API 주소를 제공한다.
  static String get pushTokenUrl {
    return authUrl('/push-token');
  }

  // 함수이름: pharmacyUrl
  // 함수역할: 복약 API와 같은 서버의 약국 API 주소를 조합한다.
  // 매개변수:
  // - path (String): /api/v1/pharmacy 뒤에 붙일 하위 경로
  // 반환값:
  // - 완성된 약국 API 주소
  static String pharmacyUrl(String path) {
    return _siblingApiUrl('pharmacy', path);
  }

  // 함수이름: chatUrl
  // 함수역할: 복약 API와 같은 서버의 환자·보호자 채팅 REST 주소를 조합한다.
  // 매개변수:
  // - path (String): 설정된 API 리소스 뒤에 붙일 하위 경로
  // 반환값:
  // - String: 복약 API와 같은 서버의 환자·보호자 채팅 REST 주소를 조합한다.
  static String chatUrl(String path) {
    return _siblingApiUrl('chat', path);
  }

  // 함수이름: chatWebSocketUrl
  // 함수역할: 채팅 REST 주소를 같은 서버의 보안 WebSocket 주소로 변환한다.
  // 매개변수:
  // - path (String): 설정된 API 리소스 뒤에 붙일 하위 경로
  // 반환값:
  // - String: 채팅 REST 주소를 같은 서버의 보안 WebSocket 주소로 변환한다.
  static String chatWebSocketUrl(String path) {
    final uri = Uri.parse(chatUrl(path));
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString();
  }

  // 함수이름: authUrl
  // 함수역할: 복약 API 기본 주소와 같은 서버의 인증 API 주소를 조합한다.
  // 매개변수:
  // - path (String): /api/v1/auth 뒤에 붙일 하위 경로
  // 반환값:
  // - 완성된 인증 API 주소
  static String authUrl(String path) {
    return _siblingApiUrl('auth', path);
  }

  // 함수이름: _siblingApiUrl
  // 함수역할: 설정된 복약 API와 같은 origin의 다른 v1 API 주소를 안전하게 만든다.
  // 매개변수:
  // - resource (String): 같은 origin의 auth·chat·pharmacy 등 리소스 이름
  // - path (String): 설정된 API 리소스 뒤에 붙일 하위 경로
  // 반환값:
  // - String: 설정된 복약 API와 같은 origin의 다른 v1 API 주소를 안전하게 만든다.
  static String _siblingApiUrl(String resource, String path) {
    const medicationPath = '/api/v1/medication';
    if (!baseUrl.endsWith(medicationPath)) {
      throw StateError('MEDBUDDY_API_BASE_URL has an unexpected path.');
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '${baseUrl.substring(0, baseUrl.length - medicationPath.length)}'
        '/api/v1/$resource$normalizedPath';
  }

  // Function Name: validate
  // Description: Applies the backend URL trust and contract-path policy to the configured base URL.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  static void validate() {
    validateUrl(baseUrl);
  }

  // 함수이름: validateUrl
  // 함수역할: API URL의 계약 경로와 네트워크 안전 조건을 검증한다. 개발 모드에서는 Android 에뮬레이터의 로컬 백엔드만 예외로 허용한다. 운영 빌드에서는 공인 HTTPS 호스트만 허용한다.
  // 매개변수:
  // - value (String): 검증할 API 기본 URL
  // - allowLocalHttp (bool): 로컬 개발용 HTTP 주소 허용 여부
  // 반환값:
  // - 없음. 조건을 충족하지 않으면 StateError를 발생시킨다.
  static void validateUrl(
    String value, {
    bool allowLocalHttp = _allowLocalHttpForDevelopment,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/api/v1/medication' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('MEDBUDDY_API_BASE_URL is invalid.');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw StateError('MEDBUDDY_API_BASE_URL must use HTTP or HTTPS.');
    }
    if (_isAllowedLocalDevelopmentUrl(uri, allowLocalHttp)) {
      return;
    }
    if (scheme != 'https' || (uri.hasPort && uri.port != 443)) {
      throw StateError('MedBuddy requires an HTTPS backend URL.');
    }
    if (_isPrivateOrLocalHost(uri.host)) {
      throw StateError('MedBuddy requires a public backend host.');
    }
  }

  // 함수이름: _isAllowedLocalDevelopmentUrl
  // 함수역할: 디버그 실행에서 사용하는 로컬 백엔드 주소만 좁게 허용한다. 다른 사설망 주소나 임의 포트는 허용하지 않는다.
  // 매개변수:
  // - uri (Uri): 검증하거나 외부 앱으로 열 대상 URI
  // - allowLocalHttp (bool): 제한된 로컬 개발 HTTP 예외 허용 여부
  // 반환값:
  // - bool: 디버그 실행에서 사용하는 로컬 백엔드 주소만 좁게 허용한다. 다른 사설망 주소나 임의 포트는 허용하지 않는다.
  static bool _isAllowedLocalDevelopmentUrl(Uri uri, bool allowLocalHttp) {
    if (!allowLocalHttp || uri.scheme.toLowerCase() != 'http') {
      return false;
    }

    final host = uri.host.toLowerCase();
    const allowedHosts = {'10.0.2.2', '127.0.0.1', 'localhost', '::1'};
    return allowedHosts.contains(host) && uri.hasPort && uri.port == 8000;
  }

  // Function Name: _isPrivateOrLocalHost
  // Description: Identifies local, private, reserved, documentation, multicast, and selected mapped-IPv4 host ranges that cannot serve as a public production backend.
  // Parameters:
  // - rawHost (String): Raw host name to check against the trust policy.
  // Returns:
  // - bool: Identifies local, private, reserved, documentation, multicast, and selected mapped-IPv4 host ranges that cannot serve as a public production backend.
  static bool _isPrivateOrLocalHost(String rawHost) {
    final host = rawHost.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return true;
    }

    final ipv4Parts = host.split('.');
    if (ipv4Parts.length == 4) {
      final octets = ipv4Parts.map(int.tryParse).toList(growable: false);
      if (octets.every(
        // Function Name: every callback
        // Description: Validates each parsed IPv4 octet against the inclusive 0-to-255 range.
        // Parameters:
        // - octet (int?): Optional parsed octet from the IPv4 address.
        // Returns:
        // - Whether the octet is present and within range.
        (octet) => octet != null && octet >= 0 && octet <= 255,
      )) {
        final first = octets[0]!;
        final second = octets[1]!;
        return first == 0 ||
            first == 10 ||
            first == 127 ||
            (first == 100 && second >= 64 && second <= 127) ||
            (first == 169 && second == 254) ||
            (first == 172 && second >= 16 && second <= 31) ||
            (first == 192 && (second == 0 || second == 168)) ||
            (first == 198 && (second == 18 || second == 19)) ||
            (first == 198 && second == 51 && octets[2] == 100) ||
            (first == 203 && second == 0 && octets[2] == 113) ||
            first >= 224;
      }
    }

    final compactIpv6 = host.replaceAll('[', '').replaceAll(']', '');
    return compactIpv6 == '::' ||
        compactIpv6 == '::1' ||
        compactIpv6.startsWith('fc') ||
        compactIpv6.startsWith('fd') ||
        RegExp(r'^fe[89ab]').hasMatch(compactIpv6) ||
        RegExp(r'^fe[c-f]').hasMatch(compactIpv6) ||
        compactIpv6.startsWith('ff') ||
        compactIpv6.startsWith('2001:db8:') ||
        compactIpv6.startsWith('::ffff:10.') ||
        compactIpv6.startsWith('::ffff:127.') ||
        compactIpv6.startsWith('::ffff:169.254.') ||
        RegExp(r'^::ffff:172\.(1[6-9]|2\d|3[01])\.').hasMatch(compactIpv6) ||
        compactIpv6.startsWith('::ffff:192.168.');
  }
}
