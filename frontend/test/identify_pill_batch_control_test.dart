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
// 주요 책임:
// - 이미지 첫 바이트에 따라 완료를 지연하고 활성 요청 수를 추적하며 지정 이미지에는 실패를 주입한다.
// 속성:
// - failingImageIds (Set<int>): 식별 실패 대상으로 삼을 이미지 첫 바이트 식별자 집합.
// - requestCount (int): 가로챈 제어기 요청 횟수.
// - activeRequestCount (int): 시작했지만 아직 해제·완료되지 않은 요청 수.
// - maximumActiveRequestCount (int): 동시에 활성화된 요청 수의 최대값.
class _ControlledIdentifyPill extends IdentifyPill {
  final Set<int> failingImageIds;
  int requestCount = 0;
  int activeRequestCount = 0;
  int maximumActiveRequestCount = 0;

  // 함수이름: _ControlledIdentifyPill
  // 함수역할:
  // - 실패시킬 이미지 식별자 집합을 보관하고 실제 서버 호출을 차단한다.
  // 매개변수:
  // - failingImageIds (Set<int>): 식별 실패 대상으로 삼을 이미지 첫 바이트 식별자 집합.
  // 반환값:
  // - 지연과 선택적 실패를 제어하는 알약 식별 대역.
  _ControlledIdentifyPill({this.failingImageIds = const <int>{}})
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 네트워크 없이 HTTP 500 상태와 빈 JSON 객체를 제공한다.
    // 매개변수:
    // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
    // 반환값:
    // - HTTP 500 응답 Future.
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  // 함수이름: requestPillIdentification
  // 함수역할:
  // - 이미지 첫 바이트에 따라 완료를 지연하고 활성 요청 수를 추적하며 지정 이미지에는 실패를 주입한다.
  // 매개변수:
  // - frontImage (Uint8List): 알약 앞면 사진 바이트.
  // - backImage (Uint8List?): 선택적으로 전달한 알약 뒷면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 이미지별 후보 한 건; 지정 실패 대상은 서비스 불가 예외.
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
// 주요 책임:
// - 각 이미지의 첫 시도는 7초 재시도 대기로 거절하고 다음 시도에 후보를 제공한다.
class _RateLimitedOnceIdentifyPill extends IdentifyPill {
  final Map<int, int> attemptsByImageId = <int, int>{};

  // 함수이름: _RateLimitedOnceIdentifyPill
  // 함수역할:
  // - 이미지별 시도 횟수를 추적할 재시도 대역을 로컬 HTTP 대역으로 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 첫 식별 시도만 호출 제한으로 실패하는 대역.
  _RateLimitedOnceIdentifyPill()
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 네트워크 없이 HTTP 500 상태와 빈 JSON 객체를 제공한다.
    // 매개변수:
    // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
    // 반환값:
    // - HTTP 500 응답 Future.
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  // 함수이름: requestPillIdentification
  // 함수역할:
  // - 각 이미지의 첫 시도는 7초 재시도 대기로 거절하고 다음 시도에 후보를 제공한다.
  // 매개변수:
  // - frontImage (Uint8List): 알약 앞면 사진 바이트.
  // - backImage (Uint8List?): 선택적으로 전달한 알약 뒷면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 재시도 성공 후보 또는 retryAfter가 7초인 호출 제한 예외.
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

// 함수이름: main
// 함수역할:
// - 알약 일괄 식별, 동시 실행 제한, 중복 제거와 재시도 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 다중 알약 식별은 입력 순서를 유지하고 동시 호출 수를 제한한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
          // 함수이름: map 콜백
          // 함수역할:
          // - 목록 검증에 사용할 식별된 품목 코드를 추출한다.
          // 매개변수:
          // - outcome (PillIdentificationBatchOutcome): 식별 결과 또는 성공 여부를 검사할 일괄 항목.
          // 반환값:
          // - 요소의 result!.candidates.single.itemSeq 값.
          .map((outcome) => outcome.result!.candidates.single.itemSeq)
          .toList(),
      ['pill-1', 'pill-2', 'pill-3', 'pill-4'],
    );
    expect(singlePillControl.maximumActiveRequestCount, 2);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 일부 알약 식별이 실패해도 나머지 결과를 보존한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 호출 제한 응답은 서버 대기시간을 따른 뒤 실패 항목만 자동 재시도한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('호출 제한 응답은 서버 대기시간을 따른 뒤 실패 항목만 자동 재시도한다', () async {
    final singlePillControl = _RateLimitedOnceIdentifyPill();
    final waitedDurations = <Duration>[];
    final progressEvents = <PillIdentificationBatchProgress>[];
    final batchControl = IdentifyPillBatch(
      singlePillControl: singlePillControl,
      maxConcurrentRequests: 1,
      // 함수이름: delay 콜백
      // 함수역할:
      // - 서버 지정 재시도 대기시간을 기록하되 실제 시간 대기는 생략한다.
      // 매개변수:
      // - duration (Duration): 알약 일괄 제어기가 요청한 재시도 대기시간.
      // 반환값:
      // - Future<void>; 요청 대기시간 기록 완료.
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
      // 함수이름: any 콜백
      // 함수역할:
      // - 목록 검증에 사용할 재시도 대기 상태를 추출한다.
      // 매개변수:
      // - progress (PillIdentificationBatchProgress): 재시도 상태를 검사할 일괄 식별 진행 정보.
      // 반환값:
      // - 요소의 isWaitingForRetry 값.
      progressEvents.any((progress) => progress.isWaitingForRetry),
      isTrue,
    );
    expect(progressEvents.last.completedCount, 1);
    expect(progressEvents.last.retryingRequestCount, 0);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 동일한 앞뒷면 사진은 한 번만 식별하고 모든 입력 위치에 결과를 복사한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
    // 함수이름: every 콜백
    // 함수역할:
    // - 목록 검증에 사용할 식별 성공 여부를 추출한다.
    // 매개변수:
    // - outcome (PillIdentificationBatchOutcome): 식별 결과 또는 성공 여부를 검사할 일괄 항목.
    // 반환값:
    // - 요소의 isSuccess 값.
    expect(outcomes.every((outcome) => outcome.isSuccess), isTrue);
    expect(
      outcomes[0].result?.candidates.single.itemSeq,
      outcomes[1].result?.candidates.single.itemSeq,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 한 번에 등록할 수 있는 알약 수를 초과하면 요청하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('한 번에 등록할 수 있는 알약 수를 초과하면 요청하지 않는다', () async {
    final batchControl = IdentifyPillBatch(
      singlePillControl: _ControlledIdentifyPill(),
    );
    final imagePairs = List<PillImagePair>.generate(
      IdentifyPillBatch.maxBatchSize + 1,
      // 함수이름: List<PillImagePair>.generate 콜백
      // 함수역할:
      // - 일괄 등록 한도를 넘길 동일한 작은 앞면 이미지 쌍을 만든다.
      // 매개변수:
      // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번. 이 대역에서는 직접 사용하지 않는다.
      // 반환값:
      // - 한 바이트 앞면 이미지를 가진 PillImagePair.
      (index) => PillImagePair(frontImage: Uint8List.fromList([1])),
    );

    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - 개수 제한을 초과한 사진 목록을 일괄 식별 진입점에 전달한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 입력 개수 검증에 실패하는 호출 결과.
      () => batchControl.requestBatchIdentification(imagePairs),
      throwsArgumentError,
    );
  });
}
