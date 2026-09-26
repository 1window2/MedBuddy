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
  // Function Name: ApiResponseParser._
  // Description: Prevents instances of the shared static HTTP-response decoding utility.
  // Parameters:
  // - None.
  // Returns:
  // - ApiResponseParser: the initialized instance.
  const ApiResponseParser._();

  // Function Name: decodeBody
  // Description: Decodes HTTP response bytes explicitly as UTF-8 so non-ASCII server messages are preserved.
  // Parameters:
  // - response (http.Response): HTTP response whose status and body are being decoded.
  // Returns:
  // - String: Decodes HTTP response bytes explicitly as UTF-8 so non-ASCII server messages are preserved.
  static String decodeBody(http.Response response) {
    return utf8.decode(response.bodyBytes);
  }

  // Function Name: decodeMap
  // Description: Decodes a JSON body and requires a string-keyed object, rejecting scalar and list payloads.
  // Parameters:
  // - responseBody (String): Server response body decoded as UTF-8.
  // Returns:
  // - Map<String, dynamic>: Decodes a JSON body and requires a string-keyed object, rejecting scalar and list payloads.
  static Map<String, dynamic> decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('Server response format was invalid.');
  }

  // Function Name: extractErrorDetail
  // Description: Extracts the FastAPI detail field when present and otherwise preserves the original response body, including malformed JSON errors.
  // Parameters:
  // - responseBody (String): Server response body decoded as UTF-8.
  // Returns:
  // - String: Extracts the FastAPI detail field when present and otherwise preserves the original response body, including malformed JSON errors.
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
