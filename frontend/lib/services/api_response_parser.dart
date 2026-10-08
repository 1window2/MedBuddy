import 'dart:convert';

import 'package:http/http.dart' as http;

// File Name: api_response_parser.dart
// Role: Provides shared HTTP response decoding helpers and the typed request failure for API controls.

// Class Name: ApiRequestException
// Role: Carries the status code or transport cause of a failed API request while remaining a StateError.
// Responsibilities:
// - Keep the message text controls already throw, so existing `on StateError` handlers and message checks still apply.
// - Let error presentation classify the failure by status code or cause instead of by message text.
// Attributes:
// - operation (String): Failure label of the request without a trailing period, such as "Schedule lookup failed".
// - statusCode (int?): HTTP status of a rejected response; null when no response was received.
// - detail (String): Server-provided error detail of a rejected response; empty otherwise.
// - cause (Object?): Original exception of a transport or decoding failure; null for a rejected response.
class ApiRequestException extends StateError {
  final String operation;
  final int? statusCode;
  final String detail;
  final Object? cause;

  // Function Name: ApiRequestException
  // Description: Builds the failure with the message "<operation> (<statusCode>): <detail>" when a status code is given and "<operation>." otherwise.
  // Parameters:
  // - operation (String): Failure label of the request without a trailing period.
  // - statusCode (int?): HTTP status of the rejected response, when one was received.
  // - detail (String): Server-provided error detail shown after the status code.
  // - cause (Object?): Original exception when the request failed before a usable response.
  // Returns:
  // - ApiRequestException: the initialized instance.
  ApiRequestException(
    this.operation, {
    this.statusCode,
    this.detail = '',
    this.cause,
  }) : super(
         statusCode == null
             ? '$operation.'
             : '$operation ($statusCode): $detail',
       );
}

// Class Name: ApiResponseParser
// Role: Centralizes JSON body decoding and FastAPI error detail extraction.
// Responsibilities:
// - Decode response bytes using UTF-8.
// - Convert JSON response bodies into Map<String, dynamic>.
// - Extract a server-provided error detail when an API request fails.
// - Build the typed failure for rejected responses and transport errors.
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

  // Function Name: httpFailure
  // Description: Builds the failure for a response with an unexpected status, keeping the "<operation> (<status>): <detail>" message; the caller throws it.
  // Parameters:
  // - operation (String): Failure label of the request without a trailing period.
  // - response (http.Response): Rejected response that supplies the status code.
  // - body (String): Response body already decoded as UTF-8, from which the error detail is extracted.
  // Returns:
  // - ApiRequestException: Failure carrying the status code and the server detail.
  static ApiRequestException httpFailure(
    String operation,
    http.Response response,
    String body,
  ) {
    return ApiRequestException(
      operation,
      statusCode: response.statusCode,
      detail: extractErrorDetail(body),
    );
  }

  // Function Name: transportFailure
  // Description: Builds the failure for a request that ended without a usable response, keeping the "<operation>." message and the original exception; the caller throws it.
  // Parameters:
  // - operation (String): Failure label of the request without a trailing period.
  // - cause (Object): Original timeout, connection, contract, authentication or decoding exception.
  // Returns:
  // - ApiRequestException: Failure carrying the original exception as its cause.
  static ApiRequestException transportFailure(String operation, Object cause) {
    return ApiRequestException(operation, cause: cause);
  }
}
