// File Name: medication_image_url_entity_test.dart
// Role: Verifies that medication images are limited to trusted HTTPS sources.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_image_url_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for trusted MFDS medication image URLs.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: accepts the trusted MFDS HTTPS medication image host.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('accepts the trusted MFDS HTTPS medication image host', () {
    expect(
      safeMedicationImageUrl(
        'https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/12345',
      ),
      'https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/12345',
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: rejects cleartext, local, credentialed, and untrusted image URLs.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('rejects cleartext, local, credentialed, and untrusted image URLs', () {
    const rejectedUrls = [
      'http://nedrug.mfds.go.kr/image.png',
      'https://127.0.0.1/image.png',
      'https://192.168.1.10/image.png',
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
