// File Name: backend_session_failure_test.dart
// Role: Checks session-recovery eligibility and redacted diagnostics for backend failures.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/backend_session_failure.dart';

// Function Name: main
// Description:
// - Register error-classification cases without making network requests.
// Parameters:
// - None.
// Returns:
// - No value; the framework runs the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Separate retryable timeout, transport, attestation and transient HTTP failures from permanent HTTP, contract and configuration failures.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('only temporary session failures are eligible for automatic recovery', () {
    for (final status in [408, 429, 500, 502, 503, 504]) {
      expect(isTransientBackendSessionFailure(BackendSessionHttpException(status)), isTrue);
    }
    for (final status in [400, 401, 403, 404, 409, 422]) {
      expect(isTransientBackendSessionFailure(BackendSessionHttpException(status)), isFalse);
    }
    for (final error in [
      TimeoutException('private details'),
      http.ClientException('private endpoint'),
      const AuthenticationUnavailableException(),
      const AppAttestationUnavailableException(),
    ]) {
      expect(isTransientBackendSessionFailure(error), isTrue);
    }
    for (final error in [
      null,
      const ApiContractMismatchException('private contract'),
      const FormatException('private response'),
      StateError('configuration'),
    ]) {
      expect(isTransientBackendSessionFailure(error), isFalse);
    }
  });

  // Function Name: test callback
  // Description:
  // - Map representative failures containing private details to stable diagnostic codes, retaining only the HTTP status where applicable.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('release diagnostics never include raw errors or response contents', () {
    expect(backendSessionFailureCode(http.ClientException('secret token')), 'transport');
    expect(backendSessionFailureCode(TimeoutException('private URL')), 'timeout');
    expect(backendSessionFailureCode(const BackendSessionHttpException(503)), 'http_503');
    expect(backendSessionFailureCode(const FormatException('private payload')), 'invalid_payload');
    expect(backendSessionFailureCode(StateError('private details')), 'unexpected');
  });
}
