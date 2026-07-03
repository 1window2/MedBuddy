import 'dart:convert';

import 'package:http/http.dart' as http;

// File Name: api_response_parser.dart
// Role: Provides shared HTTP response decoding helpers for API controls.

// Class Name: ApiResponseParser
// Role: Centralizes JSON body decoding and FastAPI error detail extraction.
// Responsibilities:
// - Decode response bytes using UTF-8.
// - Convert JSON response bodies into Map<String, dynamic>.
// - Extract a server-provided error detail when an API request fails.
class ApiResponseParser {
  const ApiResponseParser._();

  static String decodeBody(http.Response response) {
    return utf8.decode(response.bodyBytes);
  }

  static Map<String, dynamic> decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('Server response format was invalid.');
  }

  static String extractErrorDetail(String responseBody) {
    try {
      final decodedError = decodeMap(responseBody);
      if (decodedError['detail'] != null) {
        return decodedError['detail'].toString();
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
  }
}
