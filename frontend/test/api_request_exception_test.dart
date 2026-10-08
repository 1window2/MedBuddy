// File Name: api_request_exception_test.dart
// Role: Regression coverage for the typed API request failure: message format, StateError
//   compatibility and the fields carried for error presentation.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/services/api_response_parser.dart';

// Function Name: _jsonResponse
// Description:
// - Build a UTF-8 JSON response the way the backend sends an error envelope.
// Parameters:
// - statusCode (int): HTTP status of the response.
// - body (Object): JSON-encodable response body.
// Returns:
// - The HTTP response with the encoded body bytes.
http.Response _jsonResponse(int statusCode, Object body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

// Function Name: main
// Description:
// - Register regression cases for the typed API request failure.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: httpFailure produces exactly the text controls build by hand today,
  //   "<operation> (<status>): <detail>", and carries the status code and the server detail.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('httpFailure keeps the hand-built status message byte for byte', () {
    final response = _jsonResponse(409, {'detail': '타이레놀정500밀리그람 is already saved.'});
    final responseBody = ApiResponseParser.decodeBody(response);
    final handBuilt = StateError(
      'Schedule lookup failed (${response.statusCode}): '
      '${ApiResponseParser.extractErrorDetail(responseBody)}',
    );

    final failure = ApiResponseParser.httpFailure(
      'Schedule lookup failed',
      response,
      responseBody,
    );

    expect(failure.message, handBuilt.message);
    expect(
      failure.message,
      'Schedule lookup failed (409): 타이레놀정500밀리그람 is already saved.',
    );
    expect(failure.toString(), handBuilt.toString());
    expect(failure.operation, 'Schedule lookup failed');
    expect(failure.statusCode, 409);
    expect(failure.detail, '타이레놀정500밀리그람 is already saved.');
    expect(failure.cause, isNull);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a body without a detail field, or one that is not JSON, is kept as the
  //   detail, exactly as extractErrorDetail returns it.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('httpFailure keeps a body without a JSON detail as the detail', () {
    final gateway = http.Response('Bad Gateway', 502);
    final gatewayFailure = ApiResponseParser.httpFailure(
      '분석 실패',
      gateway,
      ApiResponseParser.decodeBody(gateway),
    );
    final envelope = _jsonResponse(400, {'success': false});
    final envelopeFailure = ApiResponseParser.httpFailure(
      'Status update failed',
      envelope,
      ApiResponseParser.decodeBody(envelope),
    );

    expect(gatewayFailure.message, '분석 실패 (502): Bad Gateway');
    expect(gatewayFailure.detail, 'Bad Gateway');
    expect(
      envelopeFailure.message,
      'Status update failed (400): {"success":false}',
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: transportFailure produces exactly today's catch-all text,
  //   "<operation>.", and keeps the original exception instead of discarding it.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('transportFailure keeps the catch-all message and the cause', () {
    final cause = TimeoutException('slow');

    final failure = ApiResponseParser.transportFailure(
      'Schedule lookup failed',
      cause,
    );
    final koreanFailure = ApiResponseParser.transportFailure(
      '저장된 복약 정보를 불러오지 못했습니다',
      cause,
    );

    expect(failure.message, StateError('Schedule lookup failed.').message);
    expect(failure.toString(), 'Bad state: Schedule lookup failed.');
    expect(failure.operation, 'Schedule lookup failed');
    expect(failure.statusCode, isNull);
    expect(failure.detail, isEmpty);
    expect(failure.cause, same(cause));
    expect(koreanFailure.message, '저장된 복약 정보를 불러오지 못했습니다.');
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: the typed failure is still caught by `on StateError` and matched by
  //   StateError matchers, so existing handlers and tests keep working.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('the typed failure is still a StateError', () {
    final response = http.Response('{"detail":"gone"}', 404);
    final failure = ApiResponseParser.httpFailure(
      'History lookup failed',
      response,
      response.body,
    );
    Object? caught;
    try {
      throw failure;
    } on StateError catch (error) {
      caught = error;
    }

    expect(caught, same(failure));
    expect(() => throw failure, throwsStateError);
    expect(
      failure,
      isA<StateError>().having(
        // Function Name: having callback
        // Description:
        // - Select the exception message for a focused matcher assertion.
        // Parameters:
        // - error (StateError): Typed exception inspected by the matcher.
        // Returns:
        // - The exception's message value.
        (error) => error.message,
        'message',
        contains('404'),
      ),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: the constructor selects the message form by the presence of a status
  //   code and defaults the detail to empty.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('the constructor formats by the presence of a status code', () {
    expect(
      ApiRequestException('Unlink failed', statusCode: 500).message,
      'Unlink failed (500): ',
    );
    expect(
      ApiRequestException('Unlink failed', statusCode: 422, detail: 'x').message,
      'Unlink failed (422): x',
    );
    expect(ApiRequestException('Unlink failed').message, 'Unlink failed.');
  });
}
