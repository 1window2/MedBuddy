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
  int requestCount = 0;
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
    requestCount += 1;
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

// 클래스명: _RateLimitedOnceIdentifyPill
// 역할: 첫 요청만 호출 제한으로 실패시켜 자동 대기와 재시도 동작을 검증한다.
class _RateLimitedOnceIdentifyPill extends IdentifyPill {
  final Map<int, int> attemptsByImageId = <int, int>{};

  _RateLimitedOnceIdentifyPill()
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    final imageId = frontImage.first;
    final attempt = (attemptsByImageId[imageId] ?? 0) + 1;
    attemptsByImageId[imageId] = attempt;
    if (attempt == 1) {
      throw const PillIdentificationException(
        PillIdentificationFailure.rateLimited,
        retryAfter: Duration(seconds: 7),
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
          matchScore: 0.9,
        ),
      ],
    );
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

  test('호출 제한 응답은 서버 대기시간을 따른 뒤 실패 항목만 자동 재시도한다', () async {
    final singlePillControl = _RateLimitedOnceIdentifyPill();
    final waitedDurations = <Duration>[];
    final progressEvents = <PillIdentificationBatchProgress>[];
    final batchControl = IdentifyPillBatch(
      singlePillControl: singlePillControl,
      maxConcurrentRequests: 1,
      delay: (duration) async {
        waitedDurations.add(duration);
      },
    );

    final outcomes = await batchControl.requestBatchIdentification([
      PillImagePair(frontImage: Uint8List.fromList([1])),
    ], onProgress: progressEvents.add);

    expect(outcomes.single.isSuccess, isTrue);
    expect(singlePillControl.attemptsByImageId[1], 2);
    expect(waitedDurations, [const Duration(seconds: 7)]);
    expect(
      progressEvents.any((progress) => progress.isWaitingForRetry),
      isTrue,
    );
    expect(progressEvents.last.completedCount, 1);
    expect(progressEvents.last.retryingRequestCount, 0);
  });

  test('동일한 앞뒷면 사진은 한 번만 식별하고 모든 입력 위치에 결과를 복사한다', () async {
    final singlePillControl = _ControlledIdentifyPill();
    final batchControl = IdentifyPillBatch(
      singlePillControl: singlePillControl,
    );

    final outcomes = await batchControl.requestBatchIdentification([
      PillImagePair(
        frontImage: Uint8List.fromList([1, 2]),
        backImage: Uint8List.fromList([3, 4]),
      ),
      PillImagePair(
        frontImage: Uint8List.fromList([1, 2]),
        backImage: Uint8List.fromList([3, 4]),
      ),
      PillImagePair(frontImage: Uint8List.fromList([2, 3])),
    ]);

    expect(singlePillControl.requestCount, 2);
    expect(outcomes, hasLength(3));
    expect(outcomes.every((outcome) => outcome.isSuccess), isTrue);
    expect(
      outcomes[0].result?.candidates.single.itemSeq,
      outcomes[1].result?.candidates.single.itemSeq,
    );
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
