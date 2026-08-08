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
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('MEDBUDDY_API_BASE_URL is invalid.');
    }
    if ((kReleaseMode || kProfileMode) && uri.scheme != 'https') {
      throw StateError(
        'Release and profile builds require an HTTPS backend URL.',
      );
    }
  }
}
