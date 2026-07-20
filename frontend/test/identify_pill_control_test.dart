import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';

class _AbortAwareClient extends http.BaseClient {
  bool wasAborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortableRequest = request as http.AbortableMultipartRequest;
    await abortableRequest.abortTrigger;
    wasAborted = true;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 499);
  }
}

void main() {
  test('requestPillIdentification parses ranked MFDS candidates', () async {
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
              'image_url': 'https://example.test/pill.jpg',
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
      () => result.candidates[0] = result.candidates[0],
      throwsUnsupportedError,
    );
    expect(
      () => result.observedFeatures.colors[0] = 'red',
      throwsUnsupportedError,
    );
  });

  test('requestPillIdentification rejects an oversized client image', () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => control.requestPillIdentification(
        frontImage: Uint8List(IdentifyPill.maxImageBytes + 1),
      ),
      throwsA(
        isA<PillIdentificationException>().having(
          (error) => error.failure,
          'failure',
          PillIdentificationFailure.oversizedImage,
        ),
      ),
    );
  });

  test(
    'requestPillIdentification maps invalid photos to a typed failure',
    () async {
      final control = IdentifyPill(
        baseUrl: 'http://localhost',
        client: MockClient((_) async => http.Response('{}', 422)),
      );

      expect(
        () => control.requestPillIdentification(
          frontImage: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PillIdentificationException>().having(
            (error) => error.failure,
            'failure',
            PillIdentificationFailure.invalidPhoto,
          ),
        ),
      );
    },
  );

  test(
    'requestPillIdentification maps server errors to service unavailable',
    () async {
      final control = IdentifyPill(
        baseUrl: 'http://localhost',
        client: MockClient((_) async => http.Response('{}', 500)),
      );

      expect(
        () => control.requestPillIdentification(
          frontImage: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PillIdentificationException>().having(
            (error) => error.failure,
            'failure',
            PillIdentificationFailure.serviceUnavailable,
          ),
        ),
      );
    },
  );

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
              (error) => error.failure,
              'failure',
              PillIdentificationFailure.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test('requestPillIdentification accepts a valid empty result', () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: MockClient(
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
          (error) => error.failure,
          'failure',
          PillIdentificationFailure.timedOut,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.wasAborted, isTrue);
  });

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
