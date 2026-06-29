// 파일명: api_config.dart
// 역할: 프론트엔드에서 사용할 백엔드 API 기본 주소를 관리한다.

// 클래스명: ApiConfig
// 역할: 빌드/실행 환경에서 전달된 API base URL을 앱 전체에 제공한다.
// 주요 책임:
// - Android 에뮬레이터 데모용 기본 주소를 제공한다.
// - MEDBUDDY_API_BASE_URL 값이 주어지면 해당 주소를 우선 사용한다.
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'MEDBUDDY_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1/medication',
  );
}
