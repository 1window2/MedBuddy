// File Name: medication_image_url_entity_test.dart
// Role: Verifies that medication images are limited to trusted HTTPS sources.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_image_url_entity.dart';

void main() {
  test('accepts the trusted MFDS HTTPS medication image host', () {
    expect(
      safeMedicationImageUrl(
        'https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/12345',
      ),
      'https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/12345',
    );
  });

  test('rejects cleartext, local, credentialed, and untrusted image URLs', () {
    const rejectedUrls = [
      'http://nedrug.mfds.go.kr/image.png',
      'https://127.0.0.1/image.png',
      'https://192.168.45.7/image.png',
      'https://[::1]/image.png',
      'https://user:password@nedrug.mfds.go.kr/image.png',
      'https://nedrug.mfds.go.kr:8443/image.png',
      'https://tracker.example/image.png',
      'data:image/png;base64,abc',
    ];

    for (final url in rejectedUrls) {
      expect(safeMedicationImageUrl(url), isEmpty, reason: url);
    }
  });
}
