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

// 타입명: PillBatchDelay
// 역할: 호출 제한 대기 함수를 주입해 운영에서는 실제 대기하고 테스트에서는 즉시 검증한다.
typedef PillBatchDelay = Future<void> Function(Duration duration);

// 클래스명: PillIdentificationBatchProgress
// 역할: 전체 작업의 완료 수와 호출 제한 재시도 대기 상태를 화면에 전달한다.
class PillIdentificationBatchProgress {
  final int completedCount;
  final int totalCount;
  final int retryingRequestCount;
  final Duration? retryAfter;

  const PillIdentificationBatchProgress({
    required this.completedCount,
    required this.totalCount,
    required this.retryingRequestCount,
    this.retryAfter,
  });

  bool get isWaitingForRetry => retryingRequestCount > 0;
}

typedef PillIdentificationBatchProgressCallback =
    void Function(PillIdentificationBatchProgress progress);

// 클래스명: IdentifyPillBatch
// 역할: 외부 AI 호출이 한꺼번에 몰리지 않도록 동시 요청 수를 제한하면서 여러 알약을 식별한다.
class IdentifyPillBatch {
  static const int maxBatchSize = 10;
  static const int defaultMaxRateLimitRetries = 2;
  static const Duration _fallbackRetryDelay = Duration(seconds: 2);
  static const Duration _maximumRetryDelay = Duration(seconds: 60);

  final IdentifyPill _singlePillControl;
  final int maxConcurrentRequests;
  final int maxRateLimitRetries;
  final PillBatchDelay _delay;

  IdentifyPillBatch({
    required IdentifyPill singlePillControl,
    this.maxConcurrentRequests = 2,
    this.maxRateLimitRetries = defaultMaxRateLimitRetries,
    PillBatchDelay? delay,
  }) : _singlePillControl = singlePillControl,
       _delay = delay ?? Future<void>.delayed {
    if (maxConcurrentRequests < 1 || maxConcurrentRequests > maxBatchSize) {
      throw ArgumentError.value(
        maxConcurrentRequests,
        'maxConcurrentRequests',
        'must be between 1 and $maxBatchSize',
      );
    }
    if (maxRateLimitRetries < 0 || maxRateLimitRetries > 5) {
      throw ArgumentError.value(
        maxRateLimitRetries,
        'maxRateLimitRetries',
        'must be between 0 and 5',
      );
    }
  }

  // 함수명: requestBatchIdentification
  // 역할: 입력 순서를 유지하면서 여러 알약 사진 묶음을 제한된 개수만큼 병렬 식별한다.
  Future<List<PillIdentificationBatchOutcome>> requestBatchIdentification(
    List<PillImagePair> imagePairs, {
    PillIdentificationBatchProgressCallback? onProgress,
  }) async {
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
    final primaryIndexes = <int>[];
    final duplicateIndexes = <int, List<int>>{};
    for (var index = 0; index < imagePairs.length; index += 1) {
      int? matchingPrimary;
      for (final primaryIndex in primaryIndexes) {
        if (_samePair(imagePairs[index], imagePairs[primaryIndex])) {
          matchingPrimary = primaryIndex;
          break;
        }
      }
      if (matchingPrimary == null) {
        primaryIndexes.add(index);
        duplicateIndexes[index] = <int>[index];
      } else {
        duplicateIndexes[matchingPrimary]!.add(index);
      }
    }

    var nextIndex = 0;
    var completedCount = 0;
    var retryingRequestCount = 0;

    void reportProgress({Duration? retryAfter}) {
      onProgress?.call(
        PillIdentificationBatchProgress(
          completedCount: completedCount,
          totalCount: imagePairs.length,
          retryingRequestCount: retryingRequestCount,
          retryAfter: retryAfter,
        ),
      );
    }

    Future<PillIdentificationResult> requestWithRetry(
      PillImagePair pair,
    ) async {
      var retryCount = 0;
      while (true) {
        try {
          return await _singlePillControl.requestPillIdentification(
            frontImage: pair.frontImage,
            backImage: pair.backImage,
          );
        } on PillIdentificationException catch (error) {
          if (error.failure != PillIdentificationFailure.rateLimited ||
              retryCount >= maxRateLimitRetries) {
            rethrow;
          }
          retryCount += 1;
          final retryDelay = _boundedRetryDelay(
            error.retryAfter ?? _fallbackRetryDelay * retryCount,
          );
          retryingRequestCount += 1;
          reportProgress(retryAfter: retryDelay);
          try {
            await _delay(retryDelay);
          } finally {
            retryingRequestCount -= 1;
            reportProgress();
          }
        }
      }
    }

    Future<void> worker() async {
      while (nextIndex < primaryIndexes.length) {
        final primaryIndex = primaryIndexes[nextIndex];
        nextIndex += 1;
        final pair = imagePairs[primaryIndex];
        final matchingIndexes = duplicateIndexes[primaryIndex]!;
        try {
          final result = await requestWithRetry(pair);
          for (final index in matchingIndexes) {
            outcomes[index] = PillIdentificationBatchOutcome.succeeded(
              index: index,
              result: result,
            );
          }
        } catch (error) {
          for (final index in matchingIndexes) {
            outcomes[index] = PillIdentificationBatchOutcome.failed(
              index: index,
              error: error,
            );
          }
        }
        completedCount += matchingIndexes.length;
        reportProgress();
      }
    }

    reportProgress();
    final workerCount = primaryIndexes.length < maxConcurrentRequests
        ? primaryIndexes.length
        : maxConcurrentRequests;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return List<PillIdentificationBatchOutcome>.unmodifiable(
      outcomes.cast<PillIdentificationBatchOutcome>(),
    );
  }

  Duration _boundedRetryDelay(Duration requested) {
    if (requested <= Duration.zero) {
      return const Duration(seconds: 1);
    }
    if (requested > _maximumRetryDelay) {
      return _maximumRetryDelay;
    }
    return requested;
  }

  bool _samePair(PillImagePair first, PillImagePair second) {
    return _sameBytes(first.frontImage, second.frontImage) &&
        _sameNullableBytes(first.backImage, second.backImage);
  }

  bool _sameNullableBytes(Uint8List? first, Uint8List? second) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null) {
      return false;
    }
    return _sameBytes(first, second);
  }

  bool _sameBytes(Uint8List first, Uint8List second) {
    if (identical(first, second)) {
      return true;
    }
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}
