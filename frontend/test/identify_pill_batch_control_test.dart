// 파일명: identify_pill_batch_control_test.dart
// 역할: 여러 낱알약 사진의 일괄 식별, 부분 실패와 결과 순서를 검증한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/identify_pill_batch_control.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';

// 클래스명: _ControlledIdentifyPill
// 역할: 완료 순서와 실패 대상을 제어해 다중 알약 제어기를 검증한다.
class _ControlledIdentifyPill extends IdentifyPill {
  final Set<int> failingImageIds;
  int activeRequestCount = 0;
  int maximumActiveRequestCount = 0;

  _ControlledIdentifyPill({this.failingImageIds = const <int>{}})
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    final imageId = frontImage.first;
    activeRequestCount += 1;
    if (activeRequestCount > maximumActiveRequestCount) {
      maximumActiveRequestCount = activeRequestCount;
    }
    try {
      // 입력 순서와 완료 순서를 의도적으로 다르게 만든다.
      await Future<void>.delayed(Duration(milliseconds: (5 - imageId) * 5));
      if (failingImageIds.contains(imageId)) {
        throw const PillIdentificationException(
          PillIdentificationFailure.serviceUnavailable,
        );
      }
      return PillIdentificationResult(
        isConfident: true,
        requiresConfirmation: true,
        observedFeatures: const PillVisualFeatures(),
        candidates: [
          PillIdentificationCandidate(
            itemSeq: 'pill-$imageId',
            itemName: '알약 $imageId',
            manufacturer: '제조사',
            matchScore: 0.9,
          ),
        ],
      );
    } finally {
      activeRequestCount -= 1;
    }
  }
}

void main() {
  test('다중 알약 식별은 입력 순서를 유지하고 동시 호출 수를 제한한다', () async {
    final singlePillControl = _ControlledIdentifyPill();
    final batchControl = IdentifyPillBatch(
      singlePillControl: singlePillControl,
      maxConcurrentRequests: 2,
    );

    final outcomes = await batchControl.requestBatchIdentification([
      PillImagePair(frontImage: Uint8List.fromList([1])),
      PillImagePair(frontImage: Uint8List.fromList([2])),
      PillImagePair(frontImage: Uint8List.fromList([3])),
      PillImagePair(frontImage: Uint8List.fromList([4])),
    ]);

    expect(
      outcomes
          .map((outcome) => outcome.result!.candidates.single.itemSeq)
          .toList(),
      ['pill-1', 'pill-2', 'pill-3', 'pill-4'],
    );
    expect(singlePillControl.maximumActiveRequestCount, 2);
  });

  test('일부 알약 식별이 실패해도 나머지 결과를 보존한다', () async {
    final batchControl = IdentifyPillBatch(
      singlePillControl: _ControlledIdentifyPill(failingImageIds: const {2}),
    );

    final outcomes = await batchControl.requestBatchIdentification([
      PillImagePair(frontImage: Uint8List.fromList([1])),
      PillImagePair(frontImage: Uint8List.fromList([2])),
      PillImagePair(frontImage: Uint8List.fromList([3])),
    ]);

    expect(outcomes[0].result?.candidates.single.itemSeq, 'pill-1');
    expect(outcomes[1].result, isNull);
    expect(outcomes[1].error, isA<PillIdentificationException>());
    expect(outcomes[2].result?.candidates.single.itemSeq, 'pill-3');
  });

  test('한 번에 등록할 수 있는 알약 수를 초과하면 요청하지 않는다', () async {
    final batchControl = IdentifyPillBatch(
      singlePillControl: _ControlledIdentifyPill(),
    );
    final imagePairs = List<PillImagePair>.generate(
      IdentifyPillBatch.maxBatchSize + 1,
      (index) => PillImagePair(frontImage: Uint8List.fromList([1])),
    );

    expect(
      () => batchControl.requestBatchIdentification(imagePairs),
      throwsArgumentError,
    );
  });
}
