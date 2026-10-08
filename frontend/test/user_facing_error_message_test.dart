// File Name: user_facing_error_message_test.dart
// Role: Regression coverage for user-facing error guidance: typed API failures are classified
//   by status code or cause, and untyped errors keep the message-text rules.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';

const _expiredEn = 'Your sign-in has expired. Please sign in again.';
const _expiredKo = '로그인 정보가 만료되었습니다. 다시 로그인해주세요.';
const _delayedEn =
    'The response is taking longer than expected. Please try again shortly.';
const _delayedKo = '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
const _busyEn = 'There are many requests right now. Please try again shortly.';
const _busyKo = '현재 요청이 많습니다. 잠시 후 다시 시도해주세요.';
const _notFoundEn =
    'No matching medication was found. Review the OCR medication name.';
const _notFoundKo = '일치하는 약 정보를 찾지 못했습니다. OCR 약 이름을 확인해주세요.';
const _publicDataEn =
    'The public medication data service is temporarily unavailable.';
const _publicDataKo = '공공데이터 약품 정보 서비스가 일시적으로 응답하지 않습니다.';
const _serverEn =
    'The MedBuddy server is temporarily unavailable. Please try again shortly.';
const _serverKo = 'MedBuddy 서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해주세요.';
const _connectionEn = 'Check your internet connection and try again.';
const _connectionKo = '인터넷 연결을 확인한 뒤 다시 시도해주세요.';
const _updateEn =
    'This app version is not compatible with the server. Please update MedBuddy.';
const _updateKo = '현재 앱 버전이 서버와 호환되지 않습니다. MedBuddy를 업데이트해주세요.';
const _genericEn = 'Something went wrong. Please try again.';
const _genericKo = '요청을 처리하지 못했습니다. 다시 시도해주세요.';

// Function Name: _httpFailure
// Description:
// - Build the typed failure a control throws for a rejected response.
// Parameters:
// - operation (String): Failure label of the request.
// - statusCode (int): HTTP status of the rejected response.
// - detail (String): Server-provided error detail.
// Returns:
// - The typed failure with the status code and the detail.
ApiRequestException _httpFailure(
  String operation,
  int statusCode,
  String detail,
) {
  return ApiResponseParser.httpFailure(
    operation,
    http.Response('', statusCode),
    detail,
  );
}

// Function Name: _resolveBoth
// Description:
// - Resolve one error in English and in Korean.
// Parameters:
// - error (Object): Error to present.
// - context (UserFacingErrorContext): Task context that selects the wording.
// Returns:
// - The English and the Korean guidance.
(String, String) _resolveBoth(
  Object error, {
  UserFacingErrorContext context = UserFacingErrorContext.general,
}) {
  return (
    UserFacingErrorMessage.resolve(error, isEnglish: true, context: context),
    UserFacingErrorMessage.resolve(error, isEnglish: false, context: context),
  );
}

// Function Name: main
// Description:
// - Register regression cases for user-facing error guidance.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  group('typed failure with a status code', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: digits inside the server detail (a dose, a schedule id, an item code)
    //   are not read as a status code; the message is shown as the control built it.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('does not read numbers in the server detail as a status code', () {
      final doseConflict = _httpFailure(
        '복약 정보 저장 실패',
        409,
        '타이레놀정500밀리그람 is already saved.',
      );
      final scheduleRejected = _httpFailure(
        'Status update failed',
        422,
        'schedule 4290 is not active.',
      );
      final itemCodeRejected = _httpFailure(
        'Medication detail lookup failed',
        400,
        'item_seq 200404123 invalid',
      );
      final urlInDetail = _httpFailure(
        'Lookup failed',
        400,
        'see https://api.example.test:5030/x',
      );

      expect(_resolveBoth(doseConflict), (
        '복약 정보 저장 실패 (409): 타이레놀정500밀리그람 is already saved.',
        '복약 정보 저장 실패 (409): 타이레놀정500밀리그람 is already saved.',
      ));
      expect(_resolveBoth(scheduleRejected), (
        'Status update failed (422): schedule 4290 is not active.',
        'Status update failed (422): schedule 4290 is not active.',
      ));
      expect(
        _resolveBoth(
          itemCodeRejected,
          context: UserFacingErrorContext.medicationLookup,
        ),
        (
          'Medication detail lookup failed (400): item_seq 200404123 invalid',
          'Medication detail lookup failed (400): item_seq 200404123 invalid',
        ),
      );
      expect(_resolveBoth(urlInDetail).$1, urlInDetail.message);
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: the same texts thrown as a plain StateError are still classified by
    //   their digits, which is the behavior the typed failure replaces.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('the same texts as plain StateErrors keep the message-text rules', () {
      expect(
        _resolveBoth(
          StateError('복약 정보 저장 실패 (409): 타이레놀정500밀리그람 is already saved.'),
        ),
        (_serverEn, _serverKo),
      );
      expect(
        _resolveBoth(
          StateError('Status update failed (422): schedule 4290 is not active.'),
        ),
        (_busyEn, _busyKo),
      );
      expect(
        _resolveBoth(
          StateError(
            'Medication detail lookup failed (400): item_seq 200404123 invalid',
          ),
          context: UserFacingErrorContext.medicationLookup,
        ),
        (_notFoundEn, _notFoundKo),
      );
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: 401 and, until access-denied wording is approved, 403 give the
    //   sign-in guidance whatever the server detail says.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('401 and 403 give the sign-in guidance', () {
      expect(
        _resolveBoth(_httpFailure('Schedule lookup failed', 401, 'Unauthorized')),
        (_expiredEn, _expiredKo),
      );
      expect(
        _resolveBoth(
          _httpFailure(
            'Caregiver medication lookup failed',
            403,
            'An active patient-caregiver link is required.',
          ),
        ),
        (_expiredEn, _expiredKo),
      );
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: timeout, rate-limit and server statuses map to their guidance in both
    //   languages, and every status from 500 upward counts as a server failure.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('timeout, rate-limit and server statuses map to their guidance', () {
      for (final statusCode in [408, 504]) {
        expect(
          _resolveBoth(_httpFailure('분석 실패', statusCode, 'x')),
          (_delayedEn, _delayedKo),
          reason: '$statusCode',
        );
      }
      expect(
        _resolveBoth(_httpFailure('Status update failed', 429, 'x')),
        (_busyEn, _busyKo),
      );
      for (final statusCode in [500, 501, 502, 503, 599]) {
        expect(
          _resolveBoth(_httpFailure('Schedule lookup failed', statusCode, 'x')),
          (_serverEn, _serverKo),
          reason: '$statusCode',
        );
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: 404, 502 and 503 get the medication wording only in the medication
    //   lookup context; elsewhere 404 keeps the control message.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('the medication lookup context selects its own 404, 502 and 503 wording', () {
      const lookup = UserFacingErrorContext.medicationLookup;
      final notFound = _httpFailure('약품 정보 조회 실패', 404, 'no rows');

      expect(_resolveBoth(notFound, context: lookup), (_notFoundEn, _notFoundKo));
      expect(_resolveBoth(notFound), (notFound.message, notFound.message));
      for (final statusCode in [502, 503]) {
        expect(
          _resolveBoth(
            _httpFailure('약품 정보 조회 실패', statusCode, 'x'),
            context: lookup,
          ),
          (_publicDataEn, _publicDataKo),
          reason: '$statusCode',
        );
      }
      expect(
        _resolveBoth(_httpFailure('약품 정보 조회 실패', 500, 'x'), context: lookup),
        (_serverEn, _serverKo),
      );
      // Marker words in the detail are not classified either; only the status code is.
      expect(
        _resolveBoth(
          _httpFailure('약품 정보 조회 실패', 400, 'not found upstream'),
          context: lookup,
        ).$1,
        '약품 정보 조회 실패 (400): not found upstream',
      );
    });
  });

  group('typed failure with a cause', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: a wrapped transport exception gets the same guidance as the raw
    //   exception, in both languages, instead of the English catch-all sentence.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('unwraps the five transport exception types', () {
      final expectedByCause = <Object, (String, String)>{
        TimeoutException('slow'): (_delayedEn, _delayedKo),
        const SocketException('offline'): (_connectionEn, _connectionKo),
        http.ClientException('connection closed'): (_connectionEn, _connectionKo),
        const ApiContractMismatchException('medbuddy-api-v2'): (
          _updateEn,
          _updateKo,
        ),
        const AuthenticationUnavailableException(): (_genericEn, _genericKo),
      };
      for (final entry in expectedByCause.entries) {
        final wrapped = ApiResponseParser.transportFailure(
          'Schedule lookup failed',
          entry.key,
        );

        expect(wrapped.message, 'Schedule lookup failed.');
        expect(_resolveBoth(wrapped), entry.value, reason: '${entry.key}');
        expect(
          _resolveBoth(wrapped),
          _resolveBoth(entry.key),
          reason: 'wrapping must not change the guidance for ${entry.key}',
        );
      }
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: any other cause gives the generic localized guidance; digits in its
    //   text are not read as a status code.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('an unrecognized cause gives the generic guidance without text matching', () {
      final wrapped = ApiResponseParser.transportFailure(
        'Schedule lookup failed',
        const FormatException('Unexpected character', '<html>401 503</html>', 0),
      );

      expect(_resolveBoth(wrapped), (_genericEn, _genericKo));
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a StateError cause is presented as that error would be on its own,
    //   including a nested typed failure.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('a StateError cause is presented as that error', () {
      final plain = ApiResponseParser.transportFailure(
        'Schedule lookup failed',
        StateError('Schedule response could not be verified.'),
      );
      final nested = ApiResponseParser.transportFailure(
        'Outer request failed',
        _httpFailure('Inner request failed', 429, 'slow down'),
      );

      expect(
        _resolveBoth(plain).$2,
        'Schedule response could not be verified.',
      );
      expect(_resolveBoth(nested), (_busyEn, _busyKo));
    });
  });

  group('untyped errors', () {
    // Function Name: test callback
    // Description:
    // - Expected behavior: raw transport exceptions keep their guidance.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('raw transport exceptions keep their guidance', () {
      expect(_resolveBoth(TimeoutException('slow')), (_delayedEn, _delayedKo));
      expect(
        _resolveBoth(const SocketException('offline')),
        (_connectionEn, _connectionKo),
      );
      expect(
        _resolveBoth(http.ClientException('reset')),
        (_connectionEn, _connectionKo),
      );
      expect(
        _resolveBoth(const ApiContractMismatchException('medbuddy-api-v2')),
        (_updateEn, _updateKo),
      );
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a plain StateError is still classified by status digits and marker
    //   words in its text, in the same order as before.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('plain StateErrors keep the message-text classification', () {
      const lookup = UserFacingErrorContext.medicationLookup;

      expect(
        _resolveBoth(
          StateError(
            'Caregiver medication lookup failed (403): An active patient-caregiver link is required.',
          ),
        ),
        (_expiredEn, _expiredKo),
      );
      expect(_resolveBoth(StateError('Unauthorized')), (_expiredEn, _expiredKo));
      expect(
        _resolveBoth(StateError('분석 실패 (504): gateway')),
        (_delayedEn, _delayedKo),
      );
      expect(
        _resolveBoth(StateError('Too many requests')),
        (_busyEn, _busyKo),
      );
      expect(
        _resolveBoth(StateError('404 not found'), context: lookup),
        (_notFoundEn, _notFoundKo),
      );
      expect(
        _resolveBoth(StateError('약 정보를 찾지 못했습니다.'), context: lookup),
        (_notFoundEn, _notFoundKo),
      );
      expect(
        _resolveBoth(StateError('공공데이터 응답 오류'), context: lookup),
        (_publicDataEn, _publicDataKo),
      );
      expect(
        _resolveBoth(StateError('Lookup failed (503): x'), context: lookup),
        (_publicDataEn, _publicDataKo),
      );
      expect(
        _resolveBoth(StateError('Lookup failed (503): x')),
        (_serverEn, _serverKo),
      );
    });

    // Function Name: test callback
    // Description:
    // - Expected behavior: a StateError without a marker is shown verbatim, and any other
    //   unclassified error gives the generic guidance.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the test fails when an expectation does not hold.
    test('the verbatim StateError tail and the generic fallback are unchanged', () {
      expect(
        _resolveBoth(StateError('Schedule lookup failed.')),
        ('Schedule lookup failed.', 'Schedule lookup failed.'),
      );
      expect(
        _resolveBoth(StateError('약품 정보를 불러오지 못했습니다.')),
        ('약품 정보를 불러오지 못했습니다.', '약품 정보를 불러오지 못했습니다.'),
      );
      expect(_resolveBoth(StateError('')), (_genericEn, _genericKo));
      expect(
        _resolveBoth(const FormatException('bad payload')),
        (_genericEn, _genericKo),
      );
      expect(
        _resolveBoth(const AuthenticationUnavailableException()),
        (_genericEn, _genericKo),
      );
    });
  });
}
