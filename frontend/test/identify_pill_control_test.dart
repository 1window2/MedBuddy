// File Name: identify_pill_control_test.dart
// Role: Regression coverage for pill-identification payload validation, typed failures, and upload
//   cancellation.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';

// Class Name: _AbortAwareClient
// Role: HTTP upload stub that completes only after the multipart abort signal.
// Responsibilities:
// - Wait for multipart cancellation, record it, and finish the fake upload with status 499.
// Attributes:
// - wasAborted (bool): Whether the HTTP abort signal was observed.
class _AbortAwareClient extends http.BaseClient {
  bool wasAborted = false;

  // Function Name: send
  // Description:
  // - Wait for multipart cancellation, record it, and finish the fake upload with status 499.
  // Parameters:
  // - request (http.BaseRequest): HTTP request intercepted instead of reaching the server.
  // Returns:
  // - An empty HTTP 499 stream after the abort trigger resolves.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortableRequest = request as http.AbortableMultipartRequest;
    await abortableRequest.abortTrigger;
    wasAborted = true;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 499);
  }
}

// Function Name: main
// Description:
// - Register regression cases for pill-identification payload validation, typed failures, and upload
//   cancellation.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: requestMultiplePillIdentification parses numbered observations.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestMultiplePillIdentification parses numbered observations',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the multiple-candidate POST route and return two numbered observations with valid bounds.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with separate observations and empty candidate lists.
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/pill-identification/multiple-candidates');
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Detected 2 pills.',
            'requires_confirmation': true,
            'observations': [
              {
                'index': 1,
                'bounding_box': {
                  'left': 0.1,
                  'top': 0.2,
                  'width': 0.3,
                  'height': 0.25,
                },
                'identification': {
                  'success': false,
                  'message': 'No matching pill candidates were found.',
                  'is_confident': false,
                  'requires_confirmation': true,
                  'observed_features': {
                    'shape': 'round',
                    'colors': ['white'],
                    'same_pill': true,
                    'side_consistency_confidence': 1.0,
                  },
                  'data': const [],
                },
              },
              {
                'index': 2,
                'bounding_box': {
                  'left': 0.6,
                  'top': 0.5,
                  'width': 0.2,
                  'height': 0.2,
                },
                'identification': {
                  'success': false,
                  'message': 'No matching pill candidates were found.',
                  'is_confident': false,
                  'requires_confirmation': true,
                  'observed_features': {
                    'shape': 'round',
                    'colors': ['yellow'],
                    'same_pill': true,
                    'side_consistency_confidence': 1.0,
                  },
                  'data': const [],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final control = IdentifyPill(baseUrl: 'http://localhost', client: client);

      final result = await control.requestMultiplePillIdentification(
        image: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.observations, hasLength(2));
      expect(result.observations.first.index, 1);
      expect(result.observations.first.boundingBox.left, 0.1);
      expect(result.observations.last.identification.observedFeatures.colors, [
        'yellow',
      ]);
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: multiple-pill parsing rejects non-contiguous indexes.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('multiple-pill parsing rejects non-contiguous indexes', () {
    expect(
      // Function Name: expect callback
      // Description:
      // - Parse observations starting at index two to exercise contiguous-index validation.
      // Parameters:
      // - None.
      // Returns:
      // - A parsing exception for the missing first index.
      () => MultiplePillIdentificationResult.fromJson({
        'success': true,
        'requires_confirmation': true,
        'observations': [
          {
            'index': 2,
            'bounding_box': {
              'left': 0.1,
              'top': 0.1,
              'width': 0.2,
              'height': 0.2,
            },
            'identification': {
              'success': false,
              'message': 'No candidates.',
              'is_confident': false,
              'requires_confirmation': true,
              'observed_features': {
                'same_pill': true,
                'side_consistency_confidence': 1.0,
              },
              'data': const [],
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification parses ranked MFDS candidates.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestPillIdentification parses ranked MFDS candidates', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert multipart upload routing and return a ranked MFDS candidate with shape, imprints, and
    //   confidence.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with a confirmable ranked candidate.
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/pill-identification/candidates');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      return http.Response(
        jsonEncode({
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': {
            'shape': 'round',
            'colors': ['yellow'],
            'front_imprint': 'YH',
            'back_imprint': 'LT',
            'same_pill': true,
            'side_consistency_confidence': 0.98,
          },
          'data': [
            {
              'item_seq': '200808877',
              'item_name': '페라트라정2.5밀리그램(레트로졸)',
              'entp_name': '영풍제약',
              'image_url': 'https://nedrug.mfds.go.kr/pill.jpg',
              'shape': '원형',
              'colors': ['노랑'],
              'print_front': 'YH',
              'print_back': 'LT',
              'match_score': 1.0,
              'matched_attributes': ['shape', 'color', 'imprint'],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = IdentifyPill(baseUrl: 'http://localhost', client: client);

    final result = await control.requestPillIdentification(
      frontImage: Uint8List.fromList([1, 2, 3]),
      backImage: Uint8List.fromList([4, 5, 6]),
    );

    expect(result.isConfident, isTrue);
    expect(result.requiresConfirmation, isTrue);
    expect(result.observedFeatures.samePill, isTrue);
    expect(result.observedFeatures.sideConsistencyConfidence, 0.98);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.first.itemSeq, '200808877');
    expect(result.candidates.first.matchScore, 1.0);
    expect(
      // Function Name: expect callback
      // Description:
      // - Attempt to replace an element of the result's immutable candidate list.
      // Parameters:
      // - None.
      // Returns:
      // - An UnsupportedError from the mutation attempt.
      () => result.candidates[0] = result.candidates[0],
      throwsUnsupportedError,
    );
    expect(
      // Function Name: expect callback
      // Description:
      // - Attempt to change the immutable observed-color list.
      // Parameters:
      // - None.
      // Returns:
      // - An UnsupportedError from the mutation attempt.
      () => result.observedFeatures.colors[0] = 'red',
      throwsUnsupportedError,
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification rejects an oversized client image.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestPillIdentification rejects an oversized client image', () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      // Function Name: MockClient callback
      // Description:
      // - Complete the mocked HTTP request with status 200 and an empty JSON object without network access.
      // Parameters:
      // - _ (http.Request): Unused intercepted HTTP request.
      // Returns:
      // - Future<http.Response> with status 200.
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      // Function Name: expect callback
      // Description:
      // - Submit image bytes exceeding the client upload limit by one byte.
      // Parameters:
      // - None.
      // Returns:
      // - A Future failing with the oversized-image identification error.
      () => control.requestPillIdentification(
        frontImage: Uint8List(IdentifyPill.maxImageBytes + 1),
      ),
      throwsA(
        isA<PillIdentificationException>().having(
          // Function Name: having callback
          // Description:
          // - Select the typed failure reason for a focused matcher assertion.
          // Parameters:
          // - error (Object): Typed exception inspected by the matcher.
          // Returns:
          // - The exception's failure value.
          (error) => error.failure,
          'failure',
          PillIdentificationFailure.oversizedImage,
        ),
      ),
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification maps invalid photos to a typed failure.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestPillIdentification maps invalid photos to a typed failure',
    () async {
      final control = IdentifyPill(
        baseUrl: 'http://localhost',
        // Function Name: MockClient callback
        // Description:
        // - Complete the mocked HTTP request with status 422 and an empty JSON object without network access.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - Future<http.Response> with status 422.
        client: MockClient((_) async => http.Response('{}', 422)),
      );

      expect(
        // Function Name: expect callback
        // Description:
        // - Submit a small image to the server-validation failure fixture.
        // Parameters:
        // - None.
        // Returns:
        // - A Future failing with the typed invalid-image error.
        () => control.requestPillIdentification(
          frontImage: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PillIdentificationException>().having(
            // Function Name: having callback
            // Description:
            // - Select the typed failure reason for a focused matcher assertion.
            // Parameters:
            // - error (Object): Typed exception inspected by the matcher.
            // Returns:
            // - The exception's failure value.
            (error) => error.failure,
            'failure',
            PillIdentificationFailure.invalidPhoto,
          ),
        ),
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification maps server errors to service unavailable.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestPillIdentification maps server errors to service unavailable',
    () async {
      final control = IdentifyPill(
        baseUrl: 'http://localhost',
        // Function Name: MockClient callback
        // Description:
        // - Complete the mocked HTTP request with status 500 and an empty JSON object without network access.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - Future<http.Response> with status 500.
        client: MockClient((_) async => http.Response('{}', 500)),
      );

      expect(
        // Function Name: expect callback
        // Description:
        // - Submit a small image to the server-error fixture.
        // Parameters:
        // - None.
        // Returns:
        // - A Future failing with the service-unavailable identification error.
        () => control.requestPillIdentification(
          frontImage: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PillIdentificationException>().having(
            // Function Name: having callback
            // Description:
            // - Select the typed failure reason for a focused matcher assertion.
            // Parameters:
            // - error (Object): Typed exception inspected by the matcher.
            // Returns:
            // - The exception's failure value.
            (error) => error.failure,
            'failure',
            PillIdentificationFailure.serviceUnavailable,
          ),
        ),
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 호출 제한 응답의 서버 재시도 대기시간을 알약 식별 오류에 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestPillIdentification preserves retry delay for rate limits',
    () async {
      final control = IdentifyPill(
        baseUrl: 'http://localhost',
        client: MockClient(
          // 함수이름: MockClient 콜백
          // 함수역할:
          // - 서버 호출 제한과 7초 재시도 헤더를 함께 제공한다.
          // 매개변수:
          // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
          // 반환값:
          // - Retry-After가 7인 HTTP 429 응답.
          (_) async => http.Response('{}', 429, headers: {'retry-after': '7'}),
        ),
      );

      await expectLater(
        control.requestPillIdentification(
          frontImage: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PillIdentificationException>()
              .having(
                // Function Name: having callback
                // Description:
                // - Select the typed failure reason for a focused matcher assertion.
                // Parameters:
                // - error (Object): Typed exception inspected by the matcher.
                // Returns:
                // - The exception's failure value.
                (error) => error.failure,
                'failure',
                PillIdentificationFailure.rateLimited,
              )
              .having(
                // 함수이름: having 콜백
                // 함수역할:
                // - 오류의 서버가 지정한 재시도 대기시간를 추출해 해당 필드를 검증한다.
                // 매개변수:
                // - error (Object): 매처가 검사할 유형화된 예외.
                // 반환값:
                // - 예외의 retryAfter 값.
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(seconds: 7),
              ),
        ),
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification rejects malformed success payloads.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestPillIdentification rejects malformed success payloads',
    () async {
      final validFeatures = <String, dynamic>{
        'same_pill': true,
        'side_consistency_confidence': 1.0,
      };
      final validCandidate = <String, dynamic>{
        'item_seq': '200808877',
        'item_name': 'Candidate',
        'match_score': 0.9,
      };
      final malformedPayloads = <Map<String, dynamic>>[
        {
          'success': 'yes',
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [validCandidate],
        },
        {
          'success': true,
          'message': '',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [validCandidate],
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': 'yes',
          'observed_features': validFeatures,
          'data': [validCandidate],
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': false,
          'observed_features': validFeatures,
          'data': [validCandidate],
        },
        {
          'success': false,
          'message': 'No candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': const [],
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': 'not-an-array',
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [
            for (var index = 0; index < 101; index++)
              {...validCandidate, 'item_seq': '$index'},
          ],
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [validCandidate],
          'has_more_candidates': true,
        },
        {
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [
            {
              'item_seq': '',
              'item_name': 'Missing identifier',
              'match_score': 0.9,
            },
          ],
        },
        {
          'success': false,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': [validCandidate],
        },
        {
          'success': true,
          'message': 'No candidates found.',
          'is_confident': false,
          'requires_confirmation': true,
          'observed_features': validFeatures,
          'data': const [],
        },
      ];

      for (final payload in malformedPayloads) {
        final control = IdentifyPill(
          baseUrl: 'http://localhost',
          client: MockClient(
            // Function Name: MockClient callback
            // Description:
            // - Wrap each malformed candidate payload in an otherwise successful JSON response.
            // Parameters:
            // - _ (http.Request): Unused intercepted HTTP request.
            // Returns:
            // - HTTP 200 containing the current invalid payload.
            (_) async => http.Response(
              jsonEncode(payload),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );

        await expectLater(
          control.requestPillIdentification(
            frontImage: Uint8List.fromList([1, 2, 3]),
          ),
          throwsA(
            isA<PillIdentificationException>().having(
              // Function Name: having callback
              // Description:
              // - Select the typed failure reason for a focused matcher assertion.
              // Parameters:
              // - error (Object): Typed exception inspected by the matcher.
              // Returns:
              // - The exception's failure value.
              (error) => error.failure,
              'failure',
              PillIdentificationFailure.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification accepts a valid empty result.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestPillIdentification accepts a valid empty result', () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: MockClient(
        // Function Name: MockClient callback
        // Description:
        // - Provide a valid no-match result that still satisfies the confirmation and visual-feature contract.
        // Parameters:
        // - _ (http.Request): Unused intercepted HTTP request.
        // Returns:
        // - HTTP 200 with no candidates and a no-match message.
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'message': 'No matching pill candidates were found.',
            'is_confident': false,
            'requires_confirmation': true,
            'observed_features': {
              'same_pill': true,
              'side_consistency_confidence': 1.0,
            },
            'data': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await control.requestPillIdentification(
      frontImage: Uint8List.fromList([1, 2, 3]),
    );

    expect(result.candidates, isEmpty);
    expect(result.isConfident, isFalse);
    expect(result.requiresConfirmation, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Verify that non-finite and invalid candidate scores normalize to zero instead of reaching the UI.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('candidate parsing rejects non-finite match scores', () {
    for (final rawScore in const ['NaN', 'Infinity', '-Infinity']) {
      final candidate = PillIdentificationCandidate.fromJson({
        'item_seq': 'item-$rawScore',
        'item_name': 'Candidate',
        'match_score': rawScore,
      });

      expect(candidate.matchScore, 0, reason: 'raw score: $rawScore');
    }
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestPillIdentification aborts the upload after timeout.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestPillIdentification aborts the upload after timeout', () async {
    final client = _AbortAwareClient();
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: client,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      control.requestPillIdentification(
        frontImage: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<PillIdentificationException>().having(
          // Function Name: having callback
          // Description:
          // - Select the typed failure reason for a focused matcher assertion.
          // Parameters:
          // - error (Object): Typed exception inspected by the matcher.
          // Returns:
          // - The exception's failure value.
          (error) => error.failure,
          'failure',
          PillIdentificationFailure.timedOut,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.wasAborted, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: dispose aborts an in-flight upload.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('dispose aborts an in-flight upload', () async {
    final client = _AbortAwareClient();
    final control = IdentifyPill(baseUrl: 'http://localhost', client: client);

    final request = control.requestPillIdentification(
      frontImage: Uint8List.fromList([1, 2, 3]),
    );
    control.dispose();

    await expectLater(request, throwsA(isA<PillIdentificationException>()));
    await Future<void>.delayed(Duration.zero);
    expect(client.wasAborted, isTrue);
  });
}
