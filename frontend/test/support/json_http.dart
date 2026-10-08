// File Name: json_http.dart
// Role: Shared builder for the JSON responses that MockClient handlers return in tests.
//
// Does not simulate: routing, request recording or request validation. A test still supplies its
//   own MockClient handler and asserts on the requests it collected.

import 'dart:convert';

import 'package:http/http.dart' as http;

// Function Name: jsonResponse
// Description:
// - Encode a value as a UTF-8 JSON response with the content type the backend sends, so Korean
//   text in a fixture is decoded the same way as a production response.
// Parameters:
// - body (Object?): JSON-encodable response payload.
// - status (int): HTTP status code; 200 when omitted.
// Returns:
// - http.Response: Response whose bytes are the UTF-8 JSON encoding of body.
http.Response jsonResponse(Object? body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
