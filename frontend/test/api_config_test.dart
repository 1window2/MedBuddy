// File Name: api_config_test.dart
// Role: Verifies the public HTTPS API endpoint trust policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/api_config.dart';

void main() {
  test('validation accepts the production public HTTPS medication API', () {
    expect(
      () => ApiConfig.validateUrl(
        'https://api.medbuddy.pp.ua/api/v1/medication',
        requirePublicHttps: true,
      ),
      returnsNormally,
    );
  });

  test('validation accepts an Android emulator URL in debug policy', () {
    expect(
      () => ApiConfig.validateUrl(
        'http://10.0.2.2:8000/api/v1/medication',
        requirePublicHttps: false,
      ),
      returnsNormally,
    );
  });

  test('debug policy still rejects non-HTTP API schemes', () {
    expect(
      () => ApiConfig.validateUrl(
        'ftp://api.medbuddy.pp.ua/api/v1/medication',
        requirePublicHttps: false,
      ),
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
          () => ApiConfig.validateUrl(url, requirePublicHttps: true),
          throwsStateError,
          reason: url,
        );
      }
    },
  );
}
