// File Name: backend_session_failure.dart
// Role: Classifies session-establishment failures for safe retries and privacy-preserving diagnostics.
import 'dart:async';

import 'package:http/http.dart' as http;

import 'authenticated_api_client.dart';

// Class Name: BackendSessionHttpException
// Role: Represents a backend session rejection without retaining response content.
// Responsibilities: Expose only the HTTP status needed for retry and diagnostic classification.
// Attributes: statusCode (int) - HTTP response status, stored without validation.
/// Status only: never retain response bodies, credentials, or user identifiers.
class BackendSessionHttpException implements Exception {
  // Function Name: BackendSessionHttpException
  // Description: Captures a failed session response's status without its body or identity data.
  // Parameters: statusCode (int) - received HTTP status.
  // Returns: A status-only exception.
  const BackendSessionHttpException(this.statusCode);
  final int statusCode;
}

// Function Name: isTransientBackendSessionFailure
// Description: Selects transport/token failures and the explicit retryable HTTP status set.
// Parameters: error (Object?) - session-establishment failure or null.
// Returns: True for 408/429/500/502/503/504, timeout, HTTP transport, or unavailable identity/attestation; otherwise false.
bool isTransientBackendSessionFailure(Object? error) {
  if (error is BackendSessionHttpException) {
    return const {408, 429, 500, 502, 503, 504}.contains(error.statusCode);
  }
  return error is TimeoutException ||
      error is http.ClientException ||
      error is AuthenticationUnavailableException ||
      error is AppAttestationUnavailableException;
}

// Function Name: backendSessionFailureCode
// Description: Maps failures to fixed diagnostic labels without serializing potentially sensitive exception messages.
// Parameters: error (Object) - failed session operation's exception.
// Returns: HTTP status label or recognized failure category; unknown types produce unexpected.
String backendSessionFailureCode(Object error) {
  if (error is BackendSessionHttpException) return 'http_${error.statusCode}';
  if (error is TimeoutException) return 'timeout';
  if (error is http.ClientException) return 'transport';
  if (error is AuthenticationUnavailableException) return 'identity_unavailable';
  if (error is AppAttestationUnavailableException) return 'attestation_unavailable';
  if (error is ApiContractMismatchException) return 'contract_mismatch';
  if (error is FormatException) return 'invalid_payload';
  return 'unexpected';
}
