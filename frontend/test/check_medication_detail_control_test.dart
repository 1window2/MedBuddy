// File Name: check_medication_detail_control_test.dart
// Role: Regression coverage for how the medication detail lookup reports rejected responses and
//   requests that end without a usable response.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';

// Function Name: _lookup
// Description:
// - Runs one medication detail lookup against a client that answers with the given response.
// Parameters:
// - respond: Callback producing the scripted response or failure for the lookup request.
// Returns:
// - The lookup future, which completes with the detail or the reported failure.
Future<Object?> _lookup(Future<http.Response> Function() respond) {
  final client = MockClient((_) => respond());
  addTearDown(client.close);
  final control = CheckMedicationDetail(
    baseUrl: 'http://medbuddy.test',
    client: client,
  );
  return control.requestMedicationDetail(
    const MedicationSchedule(medicationName: '타이레놀정500밀리그람'),
  );
}

// Function Name: main
// Description:
// - Registers the failure-reporting cases of the medication detail lookup.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  const dedicatedMessages = <int, String>{
    401: '로그인 정보가 만료되었습니다. 다시 로그인해주세요.',
    404: '일치하는 약 정보를 찾지 못했습니다. OCR 약 이름을 확인해주세요.',
    504: '약품 정보 서버의 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.',
    429: '현재 약품 조회 요청이 많습니다. 잠시 후 다시 시도해주세요.',
    500: '공공데이터 약품 정보 서비스가 일시적으로 응답하지 않습니다.',
  };
  for (final entry in dedicatedMessages.entries) {
    // Function Name: test callback
    // Description:
    // - Expected behavior: statuses with dedicated guidance keep that guidance as the message.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes when the assertions pass.
    test('status ${entry.key} keeps its dedicated guidance', () async {
      await expectLater(
        _lookup(() async => http.Response('{"detail":"x"}', entry.key)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            entry.value,
          ),
        ),
      );
    });
  }

  // Function Name: test callback
  // Description:
  // - Expected behavior: a status without dedicated guidance keeps the existing message and
  //   carries the status code, so digits inside the server detail are not read as a status.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the assertions pass.
  test('another rejected status carries its status code', () async {
    await expectLater(
      _lookup(
        () async => http.Response(
          jsonEncode({'detail': '타이레놀정500밀리그람'}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      throwsA(
        isA<ApiRequestException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.message,
              'message',
              '약품 정보 조회 실패 (409): 타이레놀정500밀리그람',
            ),
      ),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a response that cannot be decoded keeps the existing message and the
  //   original failure as its cause.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the assertions pass.
  test('an undecodable response keeps the original failure', () async {
    await expectLater(
      _lookup(() async => http.Response('not json', 200)),
      throwsA(
        isA<ApiRequestException>()
            .having((error) => error.cause, 'cause', isA<FormatException>())
            .having(
              (error) => error.message,
              'message',
              '약품 정보를 불러오지 못했습니다.',
            ),
      ),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a busy account is still reported as a retryable lookup.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the assertions pass.
  test('a busy account remains a retryable lookup', () async {
    await expectLater(
      _lookup(
        () async => http.Response(
          '{"detail":"This account is busy. Retry the request shortly."}',
          503,
          headers: {'retry-after': '7'},
        ),
      ),
      throwsA(isA<MedicationLookupBusy>()),
    );
  });
}
