// 파일명: api_config_test.dart
// 역할: 공개 HTTPS API 주소와 신뢰 정책을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/api_config.dart';

void main() {
  test('pharmacyUrl builds a sibling API path on the configured origin', () {
    expect(
      ApiConfig.pharmacyUrl('/nearby'),
      'https://api.medbuddy.pp.ua/api/v1/pharmacy/nearby',
    );
  });

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

  test('validation accepts the production public HTTPS medication API', () {
    expect(
      () =>
          ApiConfig.validateUrl('https://api.medbuddy.pp.ua/api/v1/medication'),
      returnsNormally,
    );
  });

  test('validation accepts an Android emulator URL for local development', () {
    expect(
      () => ApiConfig.validateUrl(
        'http://10.0.2.2:8000/api/v1/medication',
        allowLocalHttp: true,
      ),
      returnsNormally,
    );
  });

  test('validation rejects an Android emulator URL for production policy', () {
    expect(
      () => ApiConfig.validateUrl(
        'http://10.0.2.2:8000/api/v1/medication',
        allowLocalHttp: false,
      ),
      throwsStateError,
    );
  });

  test('local development policy only accepts the configured local port', () {
    const rejectedUrls = [
      'http://10.0.2.2:9000/api/v1/medication',
      'http://192.168.1.10:8000/api/v1/medication',
      'http://api.medbuddy.pp.ua:8000/api/v1/medication',
    ];

    for (final url in rejectedUrls) {
      expect(
        () => ApiConfig.validateUrl(url, allowLocalHttp: true),
        throwsStateError,
        reason: url,
      );
    }
  });

  test('validation rejects non-HTTP API schemes', () {
    expect(
      () => ApiConfig.validateUrl('ftp://api.medbuddy.pp.ua/api/v1/medication'),
      throwsStateError,
    );
  });

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
          () => ApiConfig.validateUrl(url, allowLocalHttp: false),
          throwsStateError,
          reason: url,
        );
      }
    },
  );
}
