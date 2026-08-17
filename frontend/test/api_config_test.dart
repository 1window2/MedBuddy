// File Name: api_config_test.dart
// Role: Verifies development and release API endpoint trust rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/api_config.dart';

void main() {
  test('release validation accepts a public HTTPS medication API', () {
    expect(
      () => ApiConfig.validateUrl(
        'https://api.medbuddy.example/api/v1/medication',
        requirePublicHttps: true,
      ),
      returnsNormally,
    );
  });

  test(
    'release validation rejects localhost and private network endpoints',
    () {
      const rejectedUrls = [
        'https://localhost/api/v1/medication',
        'https://127.0.0.1/api/v1/medication',
        'https://10.0.2.2/api/v1/medication',
        'https://192.168.45.7/api/v1/medication',
        'https://198.51.100.4/api/v1/medication',
        'https://203.0.113.4/api/v1/medication',
        'https://[::1]/api/v1/medication',
        'https://[2001:db8::1]/api/v1/medication',
        'https://[ff02::1]/api/v1/medication',
        'http://api.medbuddy.example/api/v1/medication',
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

  test(
    'debug validation retains explicit emulator and trusted-LAN support',
    () {
      expect(
        () => ApiConfig.validateUrl(
          'http://10.0.2.2:8000/api/v1/medication',
          requirePublicHttps: false,
        ),
        returnsNormally,
      );
    },
  );
}
