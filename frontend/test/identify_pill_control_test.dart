import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';

void main() {
  test('requestPillIdentification parses ranked MFDS candidates', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/pill-identification/candidates');
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));
      return http.Response(
        jsonEncode({
          'success': true,
          'message': 'Candidates found.',
          'is_confident': true,
          'requires_confirmation': false,
          'observed_features': {
            'shape': 'round',
            'colors': ['yellow'],
            'front_imprint': 'YH',
            'back_imprint': 'LT',
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
      frontImage: XFile.fromData(Uint8List.fromList([1, 2, 3])),
      backImage: XFile.fromData(Uint8List.fromList([4, 5, 6])),
    );

    expect(result.isConfident, isTrue);
    expect(result.requiresConfirmation, isTrue);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.first.itemSeq, '200808877');
    expect(result.candidates.first.matchScore, 1.0);
  });

  test('requestPillIdentification rejects an oversized client image', () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => control.requestPillIdentification(
        frontImage: XFile.fromData(
          Uint8List(IdentifyPill.maxImageBytes + 1),
        ),
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

  test('requestPillIdentification maps invalid photos to a typed failure',
      () async {
    final control = IdentifyPill(
      baseUrl: 'http://localhost',
      client: MockClient((_) async => http.Response('{}', 422)),
    );

    expect(
      () => control.requestPillIdentification(
        frontImage: XFile.fromData(Uint8List.fromList([1, 2, 3])),
      ),
      throwsA(
        isA<PillIdentificationException>().having(
          (error) => error.failure,
          'failure',
          PillIdentificationFailure.invalidPhoto,
        ),
      ),
    );
  });
}
