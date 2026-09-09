// 파일명: api_config_test.dart
// 역할: 공개 HTTPS API 주소와 신뢰 정책을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/api_config.dart';

// 함수이름: main
// 함수역할:
// - 신뢰 API 주소 정책과 REST/WebSocket 경로 구성 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 약국 API 경로가 설정된 서버 주소에서 약 API와 같은 수준으로 구성되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('pharmacyUrl builds a sibling API path on the configured origin', () {
    expect(
      ApiConfig.pharmacyUrl('/nearby'),
      'https://api.medbuddy.pp.ua/api/v1/pharmacy/nearby',
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 채팅 REST와 WebSocket 주소가 설정된 백엔드 주소를 공유하고 각각 HTTPS와 WSS를 사용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test(
    'chat URLs use the configured backend origin for REST and WebSocket',
    () {
      expect(
        ApiConfig.chatUrl('/links/17/messages'),
        'https://api.medbuddy.pp.ua/api/v1/chat/links/17/messages',
      );
      expect(
        ApiConfig.chatWebSocketUrl('/links/17/stream'),
        'wss://api.medbuddy.pp.ua/api/v1/chat/links/17/stream',
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 운영용 공개 HTTPS 약 API 주소가 신뢰 정책을 통과하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('validation accepts the production public HTTPS medication API', () {
    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - 공개 HTTPS 약 API 주소를 검증기에 넣어 정상 통과 조건을 실행한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 없음; 올바른 주소이므로 예외 없이 완료된다.
      () =>
          ApiConfig.validateUrl('https://api.medbuddy.pp.ua/api/v1/medication'),
      returnsNormally,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 로컬 개발 옵션이 켜지면 지정된 Android 에뮬레이터 HTTP 주소를 허용하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('validation accepts an Android emulator URL for local development', () {
    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - 개발 허용 옵션과 에뮬레이터의 지정 포트를 함께 전달한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 없음; 허용된 로컬 주소이므로 예외 없이 완료된다.
      () => ApiConfig.validateUrl(
        'http://10.0.2.2:8000/api/v1/medication',
        allowLocalHttp: true,
      ),
      returnsNormally,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 운영 정책에서 Android 에뮬레이터 HTTP 주소를 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('validation rejects an Android emulator URL for production policy', () {
    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - 개발 허용 옵션을 끈 상태에서 에뮬레이터 HTTP 주소를 검증한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 운영 정책 위반을 나타내는 StateError.
      () => ApiConfig.validateUrl(
        'http://10.0.2.2:8000/api/v1/medication',
        allowLocalHttp: false,
      ),
      throwsStateError,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 로컬 개발 정책도 지정된 에뮬레이터 주소와 포트 외의 HTTP 주소를 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('local development policy only accepts the configured local port', () {
    const rejectedUrls = [
      'http://10.0.2.2:9000/api/v1/medication',
      'http://192.168.1.10:8000/api/v1/medication',
      'http://api.medbuddy.pp.ua:8000/api/v1/medication',
    ];

    for (final url in rejectedUrls) {
      expect(
        // 함수이름: expect 콜백
        // 함수역할:
        // - 허용되지 않은 호스트·포트 조합을 개발 정책의 주소 검증에 전달한다.
        // 매개변수:
        // - 없음.
        // 반환값:
        // - 신뢰 범위 밖 주소에 대한 StateError.
        () => ApiConfig.validateUrl(url, allowLocalHttp: true),
        throwsStateError,
        reason: url,
      );
    }
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - FTP처럼 HTTP 계열이 아닌 API 주소를 거부하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('validation rejects non-HTTP API schemes', () {
    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - FTP 주소를 약 API 주소 검증에 전달해 프로토콜 제한을 실행한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 미지원 프로토콜에 대한 StateError.
      () => ApiConfig.validateUrl('ftp://api.medbuddy.pp.ua/api/v1/medication'),
      throwsStateError,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 로컬호스트, 사설·예약 IP와 평문 HTTP 주소가 운영 정책에서 거부되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test(
    'validation rejects localhost, private network, and clear-text endpoints',
    () {
      const rejectedUrls = [
        'https://localhost/api/v1/medication',
        'https://127.0.0.1/api/v1/medication',
        'https://10.0.2.2/api/v1/medication',
        'https://192.168.1.10/api/v1/medication',
        'https://198.51.100.4/api/v1/medication',
        'https://203.0.113.4/api/v1/medication',
        'https://[::1]/api/v1/medication',
        'https://[2001:db8::1]/api/v1/medication',
        'https://[ff02::1]/api/v1/medication',
        'http://api.medbuddy.pp.ua/api/v1/medication',
      ];

      for (final url in rejectedUrls) {
        expect(
          // 함수이름: expect 콜백
          // 함수역할:
          // - 각 로컬·사설·예약 IP 및 HTTP 주소에 운영용 신뢰 정책을 적용한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 신뢰할 수 없는 주소에 대한 StateError.
          () => ApiConfig.validateUrl(url, allowLocalHttp: false),
          throwsStateError,
          reason: url,
        );
      }
    },
  );
}
