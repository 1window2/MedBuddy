import 'dart:async';

import 'package:http/http.dart' as http;

import 'authenticated_api_client.dart';

/// Status only: never retain response bodies, credentials, or user identifiers.
class BackendSessionHttpException implements Exception {
  const BackendSessionHttpException(this.statusCode);
  final int statusCode;
}

bool isTransientBackendSessionFailure(Object? error) {
  if (error is BackendSessionHttpException) {
    return const {408, 429, 500, 502, 503, 504}.contains(error.statusCode);
  }
  return error is TimeoutException ||
      error is http.ClientException ||
      error is AuthenticationUnavailableException ||
      error is AppAttestationUnavailableException;
}

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
