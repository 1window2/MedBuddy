import 'dart:typed_data';

import '../entities/pill_identification_entity.dart';
import 'identify_pill_control.dart';

// 파일명: identify_pill_batch_control.dart
// 역할: 여러 알약 사진 묶음을 단일 알약 식별 API로 제한 병렬 처리한다.

// 클래스명: PillImagePair
// 역할: 같은 알약의 앞면 필수 사진과 선택적 뒷면 사진을 한 요청 단위로 묶는다.
class PillImagePair {
  final Uint8List frontImage;
  final Uint8List? backImage;

  const PillImagePair({required this.frontImage, this.backImage});
}

// 클래스명: PillIdentificationBatchOutcome
// 역할: 입력 순서별 식별 결과 또는 개별 실패를 보존해 일부 실패가 전체를 막지 않게 한다.
class PillIdentificationBatchOutcome {
  final int index;
  final PillIdentificationResult? result;
  final Object? error;

  const PillIdentificationBatchOutcome._({
    required this.index,
    this.result,
    this.error,
  });

  const PillIdentificationBatchOutcome.succeeded({
    required int index,
    required PillIdentificationResult result,
  }) : this._(index: index, result: result);

  const PillIdentificationBatchOutcome.failed({
    required int index,
    required Object error,
  }) : this._(index: index, error: error);

  bool get isSuccess => result != null;
}

// 클래스명: IdentifyPillBatch
// 역할: 외부 AI 호출이 한꺼번에 몰리지 않도록 동시 요청 수를 제한하면서 여러 알약을 식별한다.
class IdentifyPillBatch {
  static const int maxBatchSize = 10;

  final IdentifyPill _singlePillControl;
  final int maxConcurrentRequests;

  IdentifyPillBatch({
    required IdentifyPill singlePillControl,
    this.maxConcurrentRequests = 2,
  }) : _singlePillControl = singlePillControl {
    if (maxConcurrentRequests < 1 || maxConcurrentRequests > maxBatchSize) {
      throw ArgumentError.value(
        maxConcurrentRequests,
        'maxConcurrentRequests',
        'must be between 1 and $maxBatchSize',
      );
    }
  }

  // 함수명: requestBatchIdentification
  // 역할: 입력 순서를 유지하면서 여러 알약 사진 묶음을 제한된 개수만큼 병렬 식별한다.
  Future<List<PillIdentificationBatchOutcome>> requestBatchIdentification(
    List<PillImagePair> imagePairs,
  ) async {
    if (imagePairs.isEmpty) {
      return const [];
    }
    if (imagePairs.length > maxBatchSize) {
      throw ArgumentError.value(
        imagePairs.length,
        'imagePairs.length',
        'must not exceed $maxBatchSize',
      );
    }

    final outcomes = List<PillIdentificationBatchOutcome?>.filled(
      imagePairs.length,
      null,
    );
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < imagePairs.length) {
        final index = nextIndex;
        nextIndex += 1;
        final pair = imagePairs[index];
        try {
          final result = await _singlePillControl.requestPillIdentification(
            frontImage: pair.frontImage,
            backImage: pair.backImage,
          );
          outcomes[index] = PillIdentificationBatchOutcome.succeeded(
            index: index,
            result: result,
          );
        } catch (error) {
          outcomes[index] = PillIdentificationBatchOutcome.failed(
            index: index,
            error: error,
          );
        }
      }
    }

    final workerCount = imagePairs.length < maxConcurrentRequests
        ? imagePairs.length
        : maxConcurrentRequests;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return List<PillIdentificationBatchOutcome>.unmodifiable(
      outcomes.cast<PillIdentificationBatchOutcome>(),
    );
  }
}
