// 파일명: api_config.dart
// 역할: 프론트엔드에서 사용할 백엔드 API 기본 주소를 관리한다.

// 클래스명: ApiConfig
// 역할: 빌드/실행 환경에서 전달된 API base URL을 앱 전체에 제공한다.
// 주요 책임:
// - Android 에뮬레이터 데모용 기본 주소를 제공한다.
// - MEDBUDDY_API_BASE_URL 값이 주어지면 해당 주소를 우선 사용한다.
import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'MEDBUDDY_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1/medication',
  );

  static String get authSessionUrl {
    return authUrl('/session');
  }

  static String get pushTokenUrl {
    return authUrl('/push-token');
  }

  // 함수명: authUrl
  // 역할:
  // - 복약 API 기본 주소와 같은 서버의 인증 API 주소를 조합한다.
  // 매개변수:
  // - path: /api/v1/auth 뒤에 붙일 하위 경로
  // 반환값:
  // - 완성된 인증 API 주소
  static String authUrl(String path) {
    const medicationPath = '/api/v1/medication';
    if (!baseUrl.endsWith(medicationPath)) {
      throw StateError('MEDBUDDY_API_BASE_URL has an unexpected path.');
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '${baseUrl.substring(0, baseUrl.length - medicationPath.length)}'
        '/api/v1/auth$normalizedPath';
  }

  static void validate() {
    validateUrl(baseUrl, requirePublicHttps: kReleaseMode || kProfileMode);
  }

  // 함수명: validateUrl
  // 역할:
  // - API URL의 계약 경로와 기본 네트워크 안전 조건을 검증한다.
  // - 릴리스 및 프로필 모드에서는 공인 HTTPS 호스트만 허용한다.
  // 매개변수:
  // - value: 검증할 API 기본 URL
  // - requirePublicHttps: 공인 HTTPS 엔드포인트를 강제할지 여부
  // 반환값:
  // - 없음. 조건을 충족하지 않으면 StateError를 발생시킨다.
  static void validateUrl(String value, {required bool requirePublicHttps}) {
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
    if (!requirePublicHttps) {
      return;
    }
    if (uri.scheme.toLowerCase() != 'https' ||
        (uri.hasPort && uri.port != 443)) {
      throw StateError(
        'Release and profile builds require an HTTPS backend URL.',
      );
    }
    if (_isPrivateOrLocalHost(uri.host)) {
      throw StateError(
        'Release and profile builds require a public backend host.',
      );
    }
  }

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
