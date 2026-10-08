// File Name: pill_identification_ui_boundary_test.dart
// Role: Regression coverage for pill-photo selection, candidate confirmation, schedule review, and
//   accessible results.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// Class Name: _FakeIdentifyPill
// Role: Pill-identification fixture with a valid PNG and one confirmable candidate.
// Responsibilities:
// - Supply the embedded PNG without opening camera or gallery UI.
// - Provide a confident candidate with front/back imprints while still requiring user confirmation.
class _FakeIdentifyPill extends IdentifyPill {
  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  // Function Name: _FakeIdentifyPill
  // Description:
  // - Initialize identification with an HTTP stub so UI tests cannot contact the server.
  // Parameters:
  // - None.
  // Returns:
  // - A fixed-image, fixed-candidate identification control.
  _FakeIdentifyPill()
    // Function Name: MockClient callback
    // Description:
    // - Complete the mocked HTTP request with status 500 and an empty JSON object without network access.
    // Parameters:
    // - _ (http.Request): Unused intercepted HTTP request.
    // Returns:
    // - Future<http.Response> with status 500.
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  // Function Name: requestPillImage
  // Description:
  // - Supply the embedded PNG without opening camera or gallery UI.
  // Parameters:
  // - source (ImageSource): Camera or gallery source requested by the caller. Accepted but not consumed
  //   by this fixture.
  // Returns:
  // - The valid PNG fixture bytes.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    return _png;
  }

  // Function Name: requestPillIdentification
  // Description:
  // - Provide a confident candidate with front/back imprints while still requiring user confirmation.
  // Parameters:
  // - frontImage (Uint8List): Front-side pill photo bytes. Accepted but not consumed by this fixture.
  // - backImage (Uint8List?): Optional reverse-side photo bytes. Accepted but not consumed by this
  //   fixture.
  // Returns:
  // - A single ranked candidate and its observed visual features.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    return const PillIdentificationResult(
      isConfident: true,
      requiresConfirmation: true,
      observedFeatures: PillVisualFeatures(
        shape: 'round',
        colors: ['yellow'],
        frontImprint: 'YH',
        backImprint: 'LT',
      ),
      candidates: [
        PillIdentificationCandidate(
          itemSeq: '200808877',
          itemName: '페라트라정2.5밀리그램(레트로졸)',
          manufacturer: '영풍제약',
          matchScore: 1.0,
          printFront: 'YH',
          printBack: 'LT',
        ),
      ],
    );
  }
}

// Class Name: _OversizedImageIdentifyPill
// Role: Image-selection stub that reproduces client-side image-size rejection.
// Responsibilities:
// - Reject photo selection with the typed oversized-image failure.
class _OversizedImageIdentifyPill extends _FakeIdentifyPill {
  // Function Name: requestPillImage
  // Description:
  // - Reject photo selection with the typed oversized-image failure.
  // Parameters:
  // - source (ImageSource): Camera or gallery source requested by the caller. Accepted but not consumed
  //   by this fixture.
  // Returns:
  // - A Future that throws PillIdentificationException for oversizedImage.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    throw const PillIdentificationException(
      PillIdentificationFailure.oversizedImage,
    );
  }
}

// Class Name: _LowConfidenceIdentifyPill
// Role: Identification fixture that adds a low-confidence image-quality warning.
// Responsibilities:
// - Reuse the normal candidate but mark the result uncertain and the pill too small in frame.
class _LowConfidenceIdentifyPill extends _FakeIdentifyPill {
  // Function Name: requestPillIdentification
  // Description:
  // - Reuse the normal candidate but mark the result uncertain and the pill too small in frame.
  // Parameters:
  // - frontImage (Uint8List): Front-side pill photo bytes.
  // - backImage (Uint8List?): Optional reverse-side photo bytes.
  // Returns:
  // - A low-confidence result retaining the candidate and quality issue.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    final result = await super.requestPillIdentification(
      frontImage: frontImage,
      backImage: backImage,
    );
    return PillIdentificationResult(
      isConfident: false,
      requiresConfirmation: true,
      observedFeatures: const PillVisualFeatures(
        shape: 'round',
        colors: ['yellow'],
        quality: 'usable',
        qualityIssues: ['pill is small in the frame'],
      ),
      candidates: result.candidates,
    );
  }
}

// Class Name: _EmptyIdentifyPill
// Role: Identification fixture for the accessible no-candidates state.
// Responsibilities:
// - Model a completed identification that found no matching pill candidates.
class _EmptyIdentifyPill extends _FakeIdentifyPill {
  // Function Name: requestPillIdentification
  // Description:
  // - Model a completed identification that found no matching pill candidates.
  // Parameters:
  // - frontImage (Uint8List): Front-side pill photo bytes. Accepted but not consumed by this fixture.
  // - backImage (Uint8List?): Optional reverse-side photo bytes. Accepted but not consumed by this
  //   fixture.
  // Returns:
  // - An unconfident result with an empty candidate list.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    return const PillIdentificationResult(
      isConfident: false,
      requiresConfirmation: true,
      observedFeatures: PillVisualFeatures(),
      candidates: [],
    );
  }
}

// Class Name: _DelayedReplacementIdentifyPill
// Role: Image picker that provides the first photo immediately and holds a replacement pending.
// Responsibilities:
// - Return the initial image normally, then wait for the test-controlled replacement result.
// Attributes:
// - _selectionCount (int): Selected-photo sequence used to vary or defer image bytes.
class _DelayedReplacementIdentifyPill extends _FakeIdentifyPill {
  final replacementImage = Completer<Uint8List?>();
  int _selectionCount = 0;

  // Function Name: requestPillImage
  // Description:
  // - Return the initial image normally, then wait for the test-controlled replacement result.
  // Parameters:
  // - source (ImageSource): Camera or gallery source requested by the caller.
  // Returns:
  // - The first PNG or the pending replacement-image Future.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) {
    _selectionCount += 1;
    if (_selectionCount == 1) {
      return super.requestPillImage(source);
    }
    return replacementImage.future;
  }
}

// 클래스명: _MultipleIdentifyPill
// 역할: 알약별로 다른 후보를 반환해 다중 식별 화면을 검증한다.
// 주요 책임:
// - 선택 횟수를 이미지 바이트에 덧붙여 실제로 서로 다른 사진을 재현한다.
// - 식별 요청마다 서로 다른 품목 번호와 약명을 가진 후보를 만든다.
// 속성:
// - _selectionCount (int): 이미지 바이트 구분 또는 지연에 사용하는 사진 선택 순번.
// - _requestCount (int): 서로 다른 알약 후보를 만드는 식별 요청 순번.
class _MultipleIdentifyPill extends _FakeIdentifyPill {
  int _selectionCount = 0;
  int _requestCount = 0;

  // 함수이름: requestPillImage
  // 함수역할:
  // - 선택 횟수를 이미지 바이트에 덧붙여 실제로 서로 다른 사진을 재현한다.
  // 매개변수:
  // - source (ImageSource): 호출자가 요청한 카메라 또는 갤러리 출처. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 선택 순번이 포함된 PNG 기반 바이트.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    _selectionCount += 1;
    // 테스트에서 서로 다른 사진을 선택한 상황을 실제 바이트 차이로 표현한다.
    return Uint8List.fromList([..._FakeIdentifyPill._png, _selectionCount]);
  }

  // 함수이름: requestPillIdentification
  // 함수역할:
  // - 식별 요청마다 서로 다른 품목 번호와 약명을 가진 후보를 만든다.
  // 매개변수:
  // - frontImage (Uint8List): 알약 앞면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // - backImage (Uint8List?): 선택적으로 전달한 알약 뒷면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 요청 순번으로 구별되는 알약 후보 한 건.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    _requestCount += 1;
    final pillNumber = _requestCount;
    return PillIdentificationResult(
      isConfident: true,
      requiresConfirmation: true,
      observedFeatures: const PillVisualFeatures(shape: 'round'),
      candidates: [
        PillIdentificationCandidate(
          itemSeq: 'multi-pill-$pillNumber',
          itemName: '다중 알약 $pillNumber',
          manufacturer: '제조사',
          matchScore: 0.9,
        ),
      ],
    );
  }
}

// Class Name: _OnePhotoMultipleIdentifyPill
// Role: Single-photo fixture containing two separately numbered pill observations.
// Responsibilities:
// - Return two bounded observations with distinct shapes, candidates, and confidence levels.
class _OnePhotoMultipleIdentifyPill extends _FakeIdentifyPill {
  // Function Name: requestMultiplePillIdentification
  // Description:
  // - Return two bounded observations with distinct shapes, candidates, and confidence levels.
  // Parameters:
  // - image (Uint8List): Configured image selection or image bytes under test. Accepted but not consumed
  //   by this fixture.
  // Returns:
  // - A two-observation result that still requires confirmation.
  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    return const MultiplePillIdentificationResult(
      requiresConfirmation: true,
      observations: [
        MultiplePillObservation(
          index: 1,
          boundingBox: PillBoundingBox(
            left: 0.1,
            top: 0.1,
            width: 0.3,
            height: 0.3,
          ),
          identification: PillIdentificationResult(
            isConfident: true,
            requiresConfirmation: true,
            observedFeatures: PillVisualFeatures(
              shape: 'round',
              colors: ['yellow'],
            ),
            candidates: [
              PillIdentificationCandidate(
                itemSeq: 'group-1',
                itemName: '첫 번째 알약',
                matchScore: 0.9,
              ),
            ],
          ),
        ),
        MultiplePillObservation(
          index: 2,
          boundingBox: PillBoundingBox(
            left: 0.6,
            top: 0.55,
            width: 0.25,
            height: 0.25,
          ),
          identification: PillIdentificationResult(
            isConfident: false,
            requiresConfirmation: true,
            observedFeatures: PillVisualFeatures(
              shape: 'oval',
              colors: ['white'],
            ),
            candidates: [
              PillIdentificationCandidate(
                itemSeq: 'group-2',
                itemName: '두 번째 알약',
                matchScore: 0.75,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 클래스명: _RefinementIdentifyPill
// 역할: 번호별 자르기·뒷면·실패·동점 확장을 외부 호출 없이 검증한다.
class _RefinementIdentifyPill extends _OnePhotoMultipleIdentifyPill {
  bool expandCandidates = false;
  bool incompleteCandidateList = false;
  bool failRefinement = false;
  bool cancelPicker = false;
  int refinementCalls = 0;
  PillBoundingBox? croppedRegion;
  Uint8List? submittedFront;
  Uint8List? submittedBack;
  final croppedBytes = Uint8List.fromList([..._FakeIdentifyPill._png, 42]);

  // 함수이름: requestPillImage
  // 함수역할: 사진 선택 취소 또는 고정 사진을 반환한다. 매개변수: source. 반환값: 사진 또는 null.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async =>
      cancelPicker ? null : _FakeIdentifyPill._png;

  // 함수이름: cropPillImage
  // 함수역할: 선택 번호의 영역과 원본 대신 보낼 사진을 기록한다. 매개변수: image, region. 반환값: 구분 가능한 사진.
  @override
  Future<Uint8List> cropPillImage(
    Uint8List image,
    PillBoundingBox region,
  ) async {
    croppedRegion = region;
    return croppedBytes;
  }

  // 함수이름: requestPillIdentification
  // 함수역할: 앞뒷면 대응과 실패 복구를 기록한다. 매개변수: frontImage, backImage. 반환값: 결과 또는 실패.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    refinementCalls++;
    submittedFront = frontImage;
    submittedBack = backImage;
    if (failRefinement) {
      throw const PillIdentificationException(
        PillIdentificationFailure.serviceUnavailable,
      );
    }
    return super.requestPillIdentification(
      frontImage: frontImage,
      backImage: backImage,
    );
  }

  // 함수이름: requestMultiplePillIdentification
  // 함수역할: 필요하면 첫 알약에 11개 동점 후보를 생성한다. 매개변수: image. 반환값: 두 알약의 결과.
  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    final result = await super.requestMultiplePillIdentification(image: image);
    if (!expandCandidates && !incompleteCandidateList) return result;
    final candidateCount = incompleteCandidateList
        ? PillIdentificationResult.maxCandidateCount
        : 11;
    return MultiplePillIdentificationResult(
      requiresConfirmation: true,
      observations: [
        MultiplePillObservation(
          index: 1,
          boundingBox: result.observations.first.boundingBox,
          identification: PillIdentificationResult(
            isConfident: false,
            requiresConfirmation: true,
            observedFeatures: const PillVisualFeatures(frontImprint: 'YH'),
            candidates: [
              for (var i = 0; i < candidateCount; i++)
                PillIdentificationCandidate(
                  itemSeq: '$i',
                  itemName: '동점 후보 $i',
                  matchScore: 1,
                ),
            ],
            hasMoreCandidates: incompleteCandidateList,
          ),
        ),
        result.observations.last,
      ],
    );
  }
}

// 함수이름: _openRefinementGroup
// 함수역할: 좁은 화면과 큰 글씨에서 다중 분석 결과를 연다. 매개변수: tester, control. 반환값: 렌더링 완료.
Future<void> _openRefinementGroup(
  WidgetTester tester,
  _RefinementIdentifyPill control,
) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: PillIdentificationUI(
        userSetting: const UserSetting(language: 'ko', fontSize: 20),
        control: control,
        captureMode: PillCaptureMode.singlePhoto,
      ),
    ),
  );
  await _tapVisible(
    tester,
    find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('카메라로 촬영'));
  await tester.pumpAndSettle();
}

// 클래스명: _DuplicateIdentifyPill
// 역할: 서로 다른 사진이 같은 품목으로 판정된 중복 검토 흐름을 재현한다.
// 주요 책임:
// - 선택 횟수별 바이트 차이를 만들어 서로 다른 사진의 동일 품목 판정을 검사한다.
// - 입력 사진이 달라도 동일 품목 후보를 반환해 선택적 중복 병합을 재현한다.
// 속성:
// - _selectionCount (int): 이미지 바이트 구분 또는 지연에 사용하는 사진 선택 순번.
class _DuplicateIdentifyPill extends _FakeIdentifyPill {
  int _selectionCount = 0;

  // 함수이름: requestPillImage
  // 함수역할:
  // - 선택 횟수별 바이트 차이를 만들어 서로 다른 사진의 동일 품목 판정을 검사한다.
  // 매개변수:
  // - source (ImageSource): 호출자가 요청한 카메라 또는 갤러리 출처. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 선택 순번이 포함된 PNG 기반 바이트.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    _selectionCount += 1;
    return Uint8List.fromList([..._FakeIdentifyPill._png, _selectionCount]);
  }

  // 함수이름: requestPillIdentification
  // 함수역할:
  // - 입력 사진이 달라도 동일 품목 후보를 반환해 선택적 중복 병합을 재현한다.
  // 매개변수:
  // - frontImage (Uint8List): 알약 앞면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // - backImage (Uint8List?): 선택적으로 전달한 알약 뒷면 사진 바이트. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - duplicate-pill 품목의 확인 필요 후보 한 건.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    return const PillIdentificationResult(
      isConfident: true,
      requiresConfirmation: true,
      observedFeatures: PillVisualFeatures(shape: 'round'),
      candidates: [
        PillIdentificationCandidate(
          itemSeq: 'duplicate-pill',
          itemName: '중복 알약',
          manufacturer: '제조사',
          matchScore: 0.9,
        ),
      ],
    );
  }
}

// 함수이름: _tapVisible
// 함수역할:
// - 큰 글씨로 화면 아래에 놓인 검사 대상을 먼저 스크롤한 뒤 탭한다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - finder (Finder): 화면에 보이게 한 뒤 누를 대상 위젯 탐색기.
// 반환값:
// - 대상 위젯의 탭 처리 완료.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

// 클래스명: _PhotoSourceIdentifyPill
// 역할: 각 입력칸의 카메라·갤러리 선택과 취소를 외부 앱 없이 재현한다.
class _PhotoSourceIdentifyPill extends _FakeIdentifyPill {
  bool cancelSelection = false;
  final List<ImageSource> sources = [];

  // 함수역할: 취소 상태에서는 사진을 변경하지 않는다. 매개변수: source. 반환값: 이미지 또는 null.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    sources.add(source);
    return cancelSelection ? null : _FakeIdentifyPill._png;
  }
}

// 클래스명: _NamedIdentifyPill
// 역할: 사진 선택 순서대로 지정한 약명을 후보로 돌려주어 저장 결과별 재시도 흐름을 재현한다.
// 주요 책임:
// - 선택 순번을 이미지 바이트에 덧붙여 어떤 사진의 식별 요청인지 구분한다.
// - 같은 이름을 두 번 주면 서로 다른 사진이 같은 품목으로 판정된다.
// 속성:
// - names (List<String>): 사진 선택 순서에 대응하는 후보 약명.
// - _selectionCount (int): 이미지 바이트 구분에 사용하는 사진 선택 순번.
class _NamedIdentifyPill extends _FakeIdentifyPill {
  final List<String> names;
  int _selectionCount = 0;

  // 함수이름: _NamedIdentifyPill
  // 함수역할: 사진 순서별 후보 약명을 보관한다. 매개변수: names. 반환값: 초기화된 대역.
  _NamedIdentifyPill(this.names);

  // 함수이름: requestPillImage
  // 함수역할: 선택 순번을 덧붙인 사진 바이트를 돌려준다. 매개변수: source. 반환값: 순번이 포함된 PNG 기반 바이트.
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    _selectionCount += 1;
    return Uint8List.fromList([..._FakeIdentifyPill._png, _selectionCount]);
  }

  // 함수이름: requestPillIdentification
  // 함수역할: 사진 순번에 대응하는 약명 하나를 후보로 돌려준다. 매개변수: frontImage, backImage. 반환값: 후보 한 건.
  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    final name = names[(frontImage.last - 1) % names.length];
    return PillIdentificationResult(
      isConfident: true,
      requiresConfirmation: true,
      observedFeatures: const PillVisualFeatures(shape: 'round'),
      candidates: [
        PillIdentificationCandidate(
          itemSeq: 'seq-$name',
          itemName: name,
          manufacturer: '제조사',
          matchScore: 0.9,
        ),
      ],
    );
  }
}

// 클래스명: _PartlyEmptyIdentifyPill
// 역할: 한 장 사진의 두 번째 알약만 후보가 없는 결과를 재현한다.
// 주요 책임:
// - 전체 사진 분석 호출 횟수를 세어 한 알약 재비교가 사진 전체를 다시 분석하지 않는지 확인하게 한다.
// 속성:
// - multipleCalls (int): 전체 사진 분석 요청 횟수.
class _PartlyEmptyIdentifyPill extends _RefinementIdentifyPill {
  int multipleCalls = 0;

  // 함수이름: requestMultiplePillIdentification
  // 함수역할: 첫 알약은 후보 한 건, 둘째 알약은 후보 없음으로 돌려준다. 매개변수: image. 반환값: 두 알약의 결과.
  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    multipleCalls += 1;
    final result = await super.requestMultiplePillIdentification(image: image);
    return MultiplePillIdentificationResult(
      requiresConfirmation: true,
      observations: [
        result.observations.first,
        MultiplePillObservation(
          index: 2,
          boundingBox: result.observations.last.boundingBox,
          identification: const PillIdentificationResult(
            isConfident: false,
            requiresConfirmation: true,
            observedFeatures: PillVisualFeatures(),
            candidates: [],
          ),
        ),
      ],
    );
  }
}

// 함수이름: _addPillPhoto
// 함수역할: 필요하면 알약 입력을 추가한 뒤 해당 위치의 앞면 사진을 카메라로 선택한다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - index (int): 0부터 시작하는 알약 입력 위치.
// 반환값:
// - 사진 선택 반영 완료.
Future<void> _addPillPhoto(WidgetTester tester, int index) async {
  if (index > 0) {
    await _tapVisible(
      tester,
      find.byKey(const Key('add-pill-photo-set-button')),
    );
    await tester.pumpAndSettle();
  }
  await _tapVisible(
    tester,
    find.byKey(
      Key(index == 0 ? 'pill-front-image-slot' : 'pill-front-image-slot-$index'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('카메라로 촬영'));
  await tester.pumpAndSettle();
}

// 함수이름: _setTallPillViewport
// 함수역할: 여러 알약 결과와 확인 버튼이 한 화면에 들어오도록 세로로 긴 화면을 설정한다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// 반환값:
// - 없음; 테스트 종료 시 화면 크기를 되돌린다.
void _setTallPillViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 함수이름: _confirmButton
// 함수역할: 선택 확인 버튼 위젯을 읽는다. 매개변수: tester. 반환값: 현재 OutlinedButton.
OutlinedButton _confirmButton(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.byKey(const Key('confirm-pill-candidate-button')),
  );
}

// 함수이름: _confirmButtonLabel
// 함수역할: 선택 확인 버튼에 표시된 문구를 읽는다. 매개변수: tester. 반환값: 버튼 문구.
String? _confirmButtonLabel(WidgetTester tester) {
  return tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const Key('confirm-pill-candidate-button')),
          matching: find.byType(Text),
        ),
      )
      .data;
}

// 함수이름: _reviewAndConfirm
// 함수역할: 앞선 결과 안내를 닫고 선택 확인을 누른 뒤, 중복 안내가 뜨면 지정한 방식을 골라 일정 검토를 확정한다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - duplicateChoiceKey (String?): 중복 안내에서 누를 버튼 키; 안내가 없어야 하면 null.
// 반환값:
// - 저장 콜백 완료와 화면 갱신 완료.
Future<void> _reviewAndConfirm(
  WidgetTester tester, {
  String? duplicateChoiceKey,
}) async {
  // 앞선 저장 결과 안내가 일정 검토 화면의 확인 버튼을 가리지 않게 먼저 닫는다.
  ScaffoldMessenger.of(
    tester.element(find.byType(PillIdentificationUI)),
  ).hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await _tapVisible(
    tester,
    find.byKey(const Key('confirm-pill-candidate-button')),
  );
  await tester.pumpAndSettle();
  if (duplicateChoiceKey == null) {
    expect(find.text('동일 약품 사진 확인'), findsNothing);
  } else {
    await tester.tap(find.byKey(Key(duplicateChoiceKey)));
    await tester.pumpAndSettle();
  }
  await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
  await tester.pumpAndSettle();
}

// Function Name: main
// Description:
// - Register regression cases for pill-photo selection, candidate confirmation, schedule review, and
//   accessible results.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  for (final language in ['ko', 'en']) {
    // 함수이름: 빈 알약 입력 추가 테스트
    // 함수역할: 사진 없이도 앞·뒷면 입력을 10개까지 추가하고 새 영역으로 이동하는지 확인한다.
    // 매개변수: tester는 위젯 테스트 제어기이다. 반환값: 큰 글씨·추가·삭제 검증 완료.
    testWidgets('추가 버튼은 빈 알약 입력을 바로 만든다 $language', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final control = _PhotoSourceIdentifyPill();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: PillIdentificationUI(
              userSetting: UserSetting(fontSize: 20, language: language),
              control: control,
            ),
          ),
        ),
      );
      final addButton = find.byKey(const Key('add-pill-photo-set-button'));
      for (var index = 1; index < 10; index += 1) {
        expect(tester.widget<OutlinedButton>(addButton).onPressed, isNotNull);
        await _tapVisible(tester, addButton);
        await tester.pumpAndSettle();
        final front = find.byKey(Key('pill-front-image-slot-$index'));
        expect(front, findsOneWidget);
        expect(find.byKey(Key('pill-back-image-slot-$index')), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(control.sources, isEmpty);
        if (language == 'ko') {
          expect(find.text('알약 ${index + 1}개 후보 찾기'), findsOneWidget);
        }
        expect(
          tester.getRect(front).overlaps(const Rect.fromLTWH(0, 0, 320, 640)),
          isTrue,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('identify-pill-button')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      }
      expect(tester.widget<OutlinedButton>(addButton).onPressed, isNull);
      expect(find.byKey(const Key('pill-front-image-slot-10')), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const Key('remove-pill-photo-set-9')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pill-front-image-slot-9')), findsNothing);
      expect(tester.widget<OutlinedButton>(addButton).onPressed, isNotNull);
    });
  }

  for (final gallery in [true, false]) {
    // 함수이름: 추가 알약의 사진 선택 테스트
    // 함수역할: 새 칸의 촬영 취소와 뒷면 선택은 다른 알약을 변경하지 않고 앞면이 있어야 분석된다.
    // 매개변수: tester는 위젯 테스트 제어기이다. 반환값: 개별 사진·필수 입력 검증 완료.
    testWidgets('추가 알약의 앞뒷면을 각각 선택한다 $gallery', (tester) async {
      final control = _PhotoSourceIdentifyPill();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PillIdentificationUI(
            userSetting: const UserSetting(),
            control: control,
          ),
        ),
      );
      await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('카메라로 촬영'));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const Key('add-pill-photo-set-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('알약 2 사진'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(control.sources, [ImageSource.camera]);
      final front = find.byKey(const Key('pill-front-image-slot-1'));
      final back = find.byKey(const Key('pill-back-image-slot-1'));
      expect(front, findsOneWidget);
      expect(back, findsOneWidget);
      control.cancelSelection = true;
      await _tapVisible(tester, front);
      await tester.pumpAndSettle();
      await tester.tap(find.text(gallery ? '갤러리에서 선택' : '카메라로 촬영'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('remove-pill-front-image-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('remove-pill-front-image-button-1')),
        findsNothing,
      );
      expect(front, findsOneWidget);
      control.cancelSelection = false;
      await _tapVisible(tester, back);
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리에서 선택'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('remove-pill-back-image-button-1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('identify-pill-button')))
            .onPressed,
        isNull,
      );
      await _tapVisible(tester, front);
      await tester.pumpAndSettle();
      await tester.tap(find.text('카메라로 촬영'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('remove-pill-front-image-button-1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('identify-pill-button')))
            .onPressed,
        isNotNull,
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('remove-pill-photo-set-1')),
      );
      await tester.pumpAndSettle();
      expect(front, findsNothing);
      expect(
        find.byKey(const Key('remove-pill-front-image-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 함수역할: 전체 사진 변경을 취소해도 기존 번호·후보와 저장 가능 상태를 유지한다.
  // 매개변수: tester. 반환값: 결과 보존 검증 완료.
  testWidgets('전체 사진 변경 취소는 후보 선택을 보존한다', (tester) async {
    final control = _RefinementIdentifyPill();
    addTearDown(control.dispose);
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await _tapVisible(tester, find.text('두 번째 알약'));
    await tester.pumpAndSettle();
    control.cancelPicker = true;
    await _tapVisible(
      tester,
      find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(find.text('두 번째 알약'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('confirm-pill-candidate-button')),
          )
          .onPressed,
      isNotNull,
    );
  });
  // 함수이름: 동점 확장 테스트
  // 함수역할: 숨겨진 6번째 후보를 펼치며 퍼센트가 확정처럼 표시되지 않는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('동점 후보 더 보기와 추가 확인 상태를 표시한다', (tester) async {
    final control = _RefinementIdentifyPill()..expandCandidates = true;
    await _openRefinementGroup(tester, control);
    expect(find.text('동점 후보 5'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.textContaining('추가 확인 필요'), findsWidgets);
    await _tapVisible(tester, find.byKey(const Key('more-pill-candidates-0')));
    await tester.pumpAndSettle();
    expect(find.text('동점 후보 5'), findsOneWidget);
    await _tapVisible(tester, find.text('동점 후보 5'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('응답 상한 밖 후보가 있으면 저장을 차단한다', (tester) async {
    final control = _RefinementIdentifyPill()..incompleteCandidateList = true;
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.text('동점 후보 0'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('두 번째 알약'));
    await tester.pumpAndSettle();

    expect(find.textContaining('표시된 목록 밖에도'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('confirm-pill-candidate-button')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 영역 재분석 테스트
  // 함수역할: 해당 영역 바이트만 분석하고 다른 알약의 선택을 보존한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('영역 재분석은 해당 알약만 갱신한다', (tester) async {
    final control = _RefinementIdentifyPill();
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.text('두 번째 알약'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('refine-pill-region-0')));
    await tester.pumpAndSettle();
    expect(control.croppedRegion?.left, 0.1);
    expect(control.submittedFront, control.croppedBytes);
    expect(control.submittedBack, isNull);
    expect(find.text('두 번째 알약'), findsOneWidget);
    await _tapVisible(tester, find.text('페라트라정2.5밀리그램(레트로졸)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('confirm-pill-candidate-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 뒷면 대응 테스트
  // 함수역할: 사용자가 선택한 번호의 앞면만 새 뒷면과 함께 전송한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('번호를 확인한 뒷면을 해당 알약에만 연결한다', (tester) async {
    final control = _RefinementIdentifyPill();
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.byKey(const Key('refine-pill-back-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('같은 알약을 뒤집어'), findsOneWidget);
    // 확인용 앞면 미리보기는 140dp 높이에 필요한 해상도까지만 디코딩한다.
    final frontPreview = tester.widget<Image>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Image),
      ),
    );
    expect(frontPreview.height, 140);
    expect(
      frontPreview.image,
      isA<ResizeImage>().having(
        // 함수이름: having 콜백
        // 함수역할: 디코딩 높이 제한을 꺼낸다. 매개변수: image. 반환값: 제한 높이.
        (image) => image.height,
        'height',
        (140 * tester.view.devicePixelRatio).round(),
      ),
    );
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(control.croppedRegion?.left, 0.6);
    expect(control.submittedFront, control.croppedBytes);
    expect(control.submittedBack, _FakeIdentifyPill._png);
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 재분석 취소·실패 테스트
  // 함수역할: 뒷면 선택 취소와 네트워크 실패가 기존 후보를 지우지 않게 한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('뒷면 취소와 재분석 실패는 기존 결과를 보존한다', (tester) async {
    final control = _RefinementIdentifyPill();
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.byKey(const Key('refine-pill-back-0')));
    await tester.pumpAndSettle();
    control.cancelPicker = true;
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(control.refinementCalls, 0);
    control.failRefinement = true;
    await _tapVisible(tester, find.byKey(const Key('refine-pill-region-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('기존 결과는 유지했습니다'), findsOneWidget);
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(find.text('두 번째 알약'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Verify that pills detected in one photo appear as separately numbered candidate groups.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('한 장의 사진에서 찾은 알약을 번호별 후보로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _OnePhotoMultipleIdentifyPill(),
          captureMode: PillCaptureMode.singlePhoto,
        ),
      ),
    );

    final groupButton = find.byKey(
      const Key('identify-multiple-pills-from-one-photo-button'),
    );
    await _tapVisible(tester, groupButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('multiple-pill-observation-preview')),
      findsOneWidget,
    );
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(find.text('두 번째 알약'), findsOneWidget);
    expect(find.textContaining('알약 1'), findsWidgets);
    expect(find.textContaining('알약 2'), findsWidgets);
    expect(find.text('알약 2개 후보 확인'), findsOneWidget);
    expect(find.byKey(const Key('add-pill-photo-set-button')), findsNothing);
    expect(find.byKey(const Key('pill-front-image-slot')), findsNothing);
    expect(find.text('여러 알약이 담긴 사진을 추가하세요'), findsNothing);
    expect(
      tester.widget(
        find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
      ),
      isA<TextButton>(),
    );
    expect(tester.takeException(), isNull);
  });

  for (final legacyEnabled in [null, false, true]) {
    for (final mode in PillCaptureMode.values) {
      // 함수이름: 촬영 방식별 기본 입력 테스트
      // 함수역할: 구형 실험실 설정과 무관하게 선택한 방식의 입력만 제공한다.
      // 매개변수: tester. 반환값: 두 방식의 버튼 분리 검증 완료.
      testWidgets('촬영 방식만 표시한다 $legacyEnabled $mode', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PillIdentificationUI(
              userSetting: UserSetting.fromJson({
                'language': 'ko',
                'multi_pill_identification_lab_enabled': ?legacyEnabled,
              }),
              captureMode: mode,
              control: _FakeIdentifyPill(),
            ),
          ),
        );
        final singlePhoto = mode == PillCaptureMode.singlePhoto;
        expect(
          find.byKey(const Key('pill-front-image-slot')),
          singlePhoto ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(
            const Key('identify-multiple-pills-from-one-photo-button'),
          ),
          singlePhoto ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('identify-pill-button')),
          singlePhoto ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const Key('add-multiple-pill-images-button')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('add-pill-photo-set-button')),
          singlePhoto ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('외부 AI'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 후보 알약은 사용자가 명시적으로 확정한 뒤에만 저장 검토로 넘어가는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('pill candidate flow requires explicit user confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _FakeIdentifyPill(),
        ),
      ),
    );

    expect(find.text('알약 하나씩 찾기'), findsOneWidget);
    expect(find.textContaining('외부 AI'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    expect(find.text('페라트라정2.5밀리그램(레트로졸)'), findsOneWidget);

    final candidateName = find.text('페라트라정2.5밀리그램(레트로졸)');
    await tester.ensureVisible(candidateName);
    await tester.pumpAndSettle();
    await tester.tap(candidateName);
    await tester.pump();
    final confirmButton = find.byKey(
      const Key('confirm-pill-candidate-button'),
    );
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('후보 선택 완료'), findsOneWidget);
    expect(find.textContaining('확정 결과가 아니므로'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 확정한 알약의 복약 일정을 저장 전에 검토하고 수정할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('confirmed pill schedule is reviewed before saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MedicationSchedule? savedSchedule;
    PillIdentificationCandidate? savedCandidate;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _FakeIdentifyPill(),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 확정 후보와 검토한 일정을 기록하고 약 저장 성공을 제공한다.
          // 매개변수:
          // - candidate (PillIdentificationCandidate): 사용자가 명시적으로 확정한 알약 후보.
          // - schedule (MedicationSchedule): 화면에서 전달하거나 수정한 복약 일정.
          // 반환값:
          // - saved 상태의 MedicationSaveResult.
          onSaveRequested: (candidate, schedule) async {
            savedCandidate = candidate;
            savedSchedule = schedule;
            return const MedicationSaveResult(
              status: MedicationSaveStatus.saved,
              message: 'saved',
            );
          },
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('페라트라정2.5밀리그램(레트로졸)'));
    await tester.pump();

    final confirmCandidate = find.byKey(
      const Key('confirm-pill-candidate-button'),
    );
    await tester.ensureVisible(confirmCandidate);
    await tester.tap(confirmCandidate);
    await tester.pumpAndSettle();

    expect(find.text('복약 정보 확인'), findsOneWidget);
    expect(find.textContaining('임시 기본값'), findsOneWidget);
    expect(savedSchedule, isNull);

    await tester.tap(find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(savedCandidate?.itemSeq, '200808877');
    expect(savedSchedule?.prescriptionDate, isNotNull);
    expect(savedSchedule?.dosage, '1정');
    expect(savedSchedule?.dailyFrequencyCount, 1);
    expect(savedSchedule?.medicationTime, 1);
    expect(find.text('복약 정보를 저장했습니다.'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 서로 다른 알약 사진을 합쳐 한 번에 검토하고 저장한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('서로 다른 알약 사진을 합쳐 한 번에 검토하고 저장한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<IdentifiedPillSaveRequest>? savedRequests;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _MultipleIdentifyPill(),
          // 함수이름: onBatchSaveRequested 콜백
          // 함수역할:
          // - 검토한 일괄 저장 요청을 기록하고 각 요청에 대응하는 성공 결과를 제공한다.
          // 매개변수:
          // - requests (List<IdentifiedPillSaveRequest>): 입력 순서대로 정리한 검토 완료 알약 저장 요청.
          // 반환값:
          // - 입력 개수와 순서를 유지한 저장 성공 결과 목록.
          onBatchSaveRequested: (requests) async {
            savedRequests = requests;
            return [
              for (var index = 0; index < requests.length; index += 1)
                const MedicationSaveResult(
                  status: MedicationSaveStatus.saved,
                  message: 'saved',
                ),
            ];
          },
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('add-pill-photo-set-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    expect(find.text('다중 알약 1'), findsOneWidget);
    expect(find.text('다중 알약 2'), findsOneWidget);

    await _tapVisible(tester, find.text('다중 알약 1'));
    await _tapVisible(tester, find.text('다중 알약 2'));
    await _tapVisible(
      tester,
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('복약 정보 확인'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(savedRequests, hasLength(2));
    expect(
      // 함수이름: map 콜백
      // 함수역할:
      // - 목록 검증에 사용할 선택 후보의 품목 코드를 추출한다.
      // 매개변수:
      // - request (IdentifiedPillSaveRequest): 후보 품목 식별자를 검사할 검토 완료 저장 요청.
      // 반환값:
      // - 요소의 candidate.itemSeq 값.
      savedRequests?.map((request) => request.candidate.itemSeq).toList(),
      ['multi-pill-1', 'multi-pill-2'],
    );
    expect(find.text('저장 2개, 기존 정보 0개, 실패 0개입니다.'), findsOneWidget);
  });

  // 함수이름: 저장한 알약 재제출 방지 테스트
  // 함수역할: 두 알약을 저장한 뒤 한 개를 더 추가해 확인하면 새 알약만 검토·저장 대상이 되는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장한 알약은 추가 알약을 확인할 때 다시 저장하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final savedBatches = <List<IdentifiedPillSaveRequest>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _MultipleIdentifyPill(),
          onBatchSaveRequested: (requests) async {
            savedBatches.add(requests);
            return [
              for (var index = 0; index < requests.length; index += 1)
                const MedicationSaveResult(
                  status: MedicationSaveStatus.saved,
                  message: 'saved',
                ),
            ];
          },
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('add-pill-photo-set-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('다중 알약 1'));
    await _tapVisible(tester, find.text('다중 알약 2'));
    await _tapVisible(
      tester,
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();
    expect(savedBatches.single, hasLength(2));
    // 저장 결과 안내가 사라진 뒤 다음 알약을 추가한다.
    ScaffoldMessenger.of(
      tester.element(find.byType(PillIdentificationUI)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const Key('add-pill-photo-set-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('다중 알약 3'));
    await _tapVisible(
      tester,
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(savedBatches, hasLength(2));
    expect(
      savedBatches.last.map((request) => request.candidate.itemSeq).toList(),
      ['multi-pill-3'],
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 같은 품목 사진은 알리고 같은 일정만 선택적으로 묶는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('같은 품목 사진은 알리고 같은 일정만 선택적으로 묶는다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<IdentifiedPillSaveRequest>? savedRequests;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _DuplicateIdentifyPill(),
          // 함수이름: onBatchSaveRequested 콜백
          // 함수역할:
          // - 검토한 일괄 저장 요청을 기록하고 각 요청에 대응하는 성공 결과를 제공한다.
          // 매개변수:
          // - requests (List<IdentifiedPillSaveRequest>): 입력 순서대로 정리한 검토 완료 알약 저장 요청.
          // 반환값:
          // - 입력 개수와 순서를 유지한 저장 성공 결과 목록.
          onBatchSaveRequested: (requests) async {
            savedRequests = requests;
            return [
              for (var index = 0; index < requests.length; index += 1)
                const MedicationSaveResult(
                  status: MedicationSaveStatus.saved,
                  message: 'saved',
                ),
            ];
          },
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const Key('add-pill-photo-set-button')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();

    final duplicateNames = find.text('중복 알약');
    expect(duplicateNames, findsNWidgets(2));
    await _tapVisible(tester, duplicateNames.at(0));
    await _tapVisible(tester, duplicateNames.at(1));
    await tester.pumpAndSettle();
    expect(find.text('동일 약품 사진 2장'), findsNWidgets(2));

    await _tapVisible(
      tester,
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('동일 약품 사진 확인'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-pill-merge-matching')));
    await tester.pumpAndSettle();

    expect(find.text('복약 정보 확인'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(savedRequests, hasLength(1));
    expect(find.textContaining('동일한 복약 일정 1개'), findsOneWidget);
    // 묶어 보낸 요청 하나가 저장되면 두 사진 모두 저장된 것으로 표시한다.
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(_confirmButton(tester).onPressed, isNull);
  });

  // 함수이름: 일부 실패 후 재확인 테스트
  // 함수역할: 병합 없이 A는 저장되고 B가 실패하면 다시 확인할 때 B만 보내는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장된 알약은 실패한 알약을 다시 확인할 때 보내지 않는다', (tester) async {
    _setTallPillViewport(tester);
    final sentBatches = <List<String>>[];
    var failB = true;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약', 'B약']),
          onBatchSaveRequested: (requests) async {
            sentBatches.add([
              for (final request in requests) request.candidate.itemName,
            ]);
            return [
              for (final request in requests)
                MedicationSaveResult(
                  status: failB && request.candidate.itemName == 'B약'
                      ? MedicationSaveStatus.failed
                      : MedicationSaveStatus.saved,
                  message: 'result',
                ),
            ];
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _addPillPhoto(tester, 1);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약'));
    await _tapVisible(tester, find.text('B약'));
    await tester.pumpAndSettle();

    await _reviewAndConfirm(tester);
    expect(sentBatches.single, ['A약', 'B약']);
    expect(find.text('저장 1개, 기존 정보 0개, 실패 1개입니다.'), findsOneWidget);
    // 실패한 B만 남았으므로 저장 완료로 표시하지 않고 한 건만 다시 확인한다.
    expect(_confirmButtonLabel(tester), '선택한 후보 확인');
    expect(_confirmButton(tester).onPressed, isNotNull);

    failB = false;
    await _reviewAndConfirm(tester);
    expect(sentBatches, hasLength(2));
    expect(sentBatches.last, ['B약']);
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(_confirmButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 병합과 실패가 겹친 저장 테스트
  // 함수역할: 같은 약 두 장을 묶어 저장하고 다른 약이 실패해도 저장된 두 장을 다시 보내지 않는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('묶어 저장한 사진은 다른 알약이 실패해도 다시 보내지 않는다', (tester) async {
    _setTallPillViewport(tester);
    final sentBatches = <List<String>>[];
    var failB = true;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약', 'A약', 'B약']),
          onBatchSaveRequested: (requests) async {
            sentBatches.add([
              for (final request in requests) request.candidate.itemName,
            ]);
            return [
              for (final request in requests)
                MedicationSaveResult(
                  status: failB && request.candidate.itemName == 'B약'
                      ? MedicationSaveStatus.failed
                      : MedicationSaveStatus.saved,
                  message: 'result',
                ),
            ];
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _addPillPhoto(tester, 1);
    await _addPillPhoto(tester, 2);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약').at(0));
    await _tapVisible(tester, find.text('A약').at(1));
    await _tapVisible(tester, find.text('B약'));
    await tester.pumpAndSettle();

    await _reviewAndConfirm(
      tester,
      duplicateChoiceKey: 'duplicate-pill-merge-matching',
    );
    expect(sentBatches.single, ['A약', 'B약']);
    expect(find.textContaining('동일한 복약 일정 1개'), findsOneWidget);
    expect(_confirmButtonLabel(tester), '선택한 후보 확인');

    // 남은 것은 B 한 장뿐이므로 중복 안내 없이 B만 다시 보낸다.
    failB = false;
    await _reviewAndConfirm(tester);
    expect(sentBatches, hasLength(2));
    expect(sentBatches.last, ['B약']);
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 묶은 요청 실패 테스트
  // 함수역할: 묶어 보낸 요청이 실패하면 그 두 장을 저장됨으로 표시하지 않고 저장된 다른 약만 제외하는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('묶어 보낸 요청이 실패하면 그 사진들만 다시 확인 대상으로 남는다', (tester) async {
    _setTallPillViewport(tester);
    final sentBatches = <List<String>>[];
    var failA = true;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약', 'A약', 'B약']),
          onBatchSaveRequested: (requests) async {
            sentBatches.add([
              for (final request in requests) request.candidate.itemName,
            ]);
            return [
              for (final request in requests)
                MedicationSaveResult(
                  status: failA && request.candidate.itemName == 'A약'
                      ? MedicationSaveStatus.failed
                      : MedicationSaveStatus.saved,
                  message: 'result',
                ),
            ];
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _addPillPhoto(tester, 1);
    await _addPillPhoto(tester, 2);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약').at(0));
    await _tapVisible(tester, find.text('A약').at(1));
    await _tapVisible(tester, find.text('B약'));
    await tester.pumpAndSettle();

    await _reviewAndConfirm(
      tester,
      duplicateChoiceKey: 'duplicate-pill-merge-matching',
    );
    expect(sentBatches.single, ['A약', 'B약']);
    // A 두 장은 저장되지 않았으므로 두 장 모두 다시 확인 대상이다.
    expect(_confirmButtonLabel(tester), '선택한 알약 2개 검토 후 저장');
    expect(find.text('저장 완료'), findsNothing);

    failA = false;
    await _reviewAndConfirm(
      tester,
      duplicateChoiceKey: 'duplicate-pill-merge-matching',
    );
    expect(sentBatches, hasLength(2));
    expect(sentBatches.last, ['A약']);
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 개별 저장 콜백 예외 테스트
  // 함수역할: 개별 저장 콜백이 두 번째 약에서 예외를 내도 먼저 저장된 약을 다시 보내지 않는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장 도중 예외가 나도 먼저 저장된 알약은 다시 보내지 않는다', (tester) async {
    _setTallPillViewport(tester);
    final sentNames = <String>[];
    var throwOnB = true;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약', 'B약']),
          onSaveRequested: (candidate, schedule) async {
            sentNames.add(candidate.itemName);
            if (throwOnB && candidate.itemName == 'B약') {
              throw StateError('save interrupted');
            }
            return const MedicationSaveResult(
              status: MedicationSaveStatus.saved,
              message: 'saved',
            );
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _addPillPhoto(tester, 1);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약'));
    await _tapVisible(tester, find.text('B약'));
    await tester.pumpAndSettle();

    await _reviewAndConfirm(tester);
    expect(sentNames, ['A약', 'B약']);
    expect(find.text('저장 1개, 기존 정보 0개, 실패 1개입니다.'), findsOneWidget);
    expect(_confirmButtonLabel(tester), '선택한 후보 확인');

    throwOnB = false;
    await _reviewAndConfirm(tester);
    expect(sentNames, ['A약', 'B약', 'B약']);
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 일괄 저장 콜백 예외 테스트
  // 함수역할: 일괄 저장 콜백이 예외를 내면 어떤 약도 저장됨으로 표시하지 않는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('일괄 저장이 예외로 끝나면 어떤 알약도 저장됨으로 표시하지 않는다', (tester) async {
    _setTallPillViewport(tester);
    var saveCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약', 'B약']),
          onBatchSaveRequested: (requests) async {
            saveCalls += 1;
            throw StateError('save interrupted');
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _addPillPhoto(tester, 1);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약'));
    await _tapVisible(tester, find.text('B약'));
    await tester.pumpAndSettle();

    await _reviewAndConfirm(tester);
    expect(saveCalls, 1);
    expect(find.text('저장 0개, 기존 정보 0개, 실패 2개입니다.'), findsOneWidget);
    expect(_confirmButtonLabel(tester), '선택한 알약 2개 검토 후 저장');
    expect(find.text('저장 완료'), findsNothing);
    expect(_confirmButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 저장 완료 후 같은 후보 재선택 테스트
  // 함수역할: 모두 저장한 뒤 같은 후보를 다시 눌러도 0개 저장 버튼이 생기지 않는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장을 마친 뒤 같은 후보를 다시 눌러도 저장 완료 상태를 유지한다', (tester) async {
    _setTallPillViewport(tester);
    var saveCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약']),
          onBatchSaveRequested: (requests) async {
            saveCalls += 1;
            return [
              for (var index = 0; index < requests.length; index += 1)
                const MedicationSaveResult(
                  status: MedicationSaveStatus.saved,
                  message: 'saved',
                ),
            ];
          },
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약'));
    await tester.pumpAndSettle();
    await _reviewAndConfirm(tester);
    expect(saveCalls, 1);
    expect(_confirmButtonLabel(tester), '저장 완료');

    await _tapVisible(tester, find.text('A약'));
    await tester.pumpAndSettle();

    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(find.textContaining('0개'), findsNothing);
    expect(_confirmButton(tester).onPressed, isNull);
    expect(saveCalls, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 저장 진행 표시 테스트
  // 함수역할: 저장 요청이 끝나기 전까지 확인 버튼에 진행 표시와 저장 중 문구가 보이는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('알약을 저장하는 동안 확인 버튼에 진행 상태를 표시한다', (tester) async {
    _setTallPillViewport(tester);
    final pendingSave = Completer<List<MedicationSaveResult>>();

    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: _NamedIdentifyPill(['A약']),
          onBatchSaveRequested: (requests) => pendingSave.future,
        ),
      ),
    );

    await _addPillPhoto(tester, 0);
    await _tapVisible(tester, find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('A약'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('pill-save-progress-indicator')),
      findsNothing,
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-review-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const Key('pill-save-progress-indicator')),
      findsOneWidget,
    );
    expect(_confirmButtonLabel(tester), '저장 중...');
    expect(_confirmButton(tester).onPressed, isNull);

    pendingSave.complete(const [
      MedicationSaveResult(status: MedicationSaveStatus.saved, message: 'ok'),
    ]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pill-save-progress-indicator')),
      findsNothing,
    );
    expect(_confirmButtonLabel(tester), '저장 완료');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 한 알약 재비교 테스트
  // 함수역할: 한 장 사진에서 후보가 없는 알약만 다시 비교하고 다른 알약의 선택을 유지하는지 검증한다.
  // 매개변수: tester: 위젯 렌더링과 사용자 입력을 수행하는 테스트 도구. 반환값: 비동기 검증 완료.
  testWidgets('한 장 사진에서 후보 없는 알약만 다시 비교한다', (tester) async {
    final control = _PartlyEmptyIdentifyPill();
    addTearDown(control.dispose);
    await _openRefinementGroup(tester, control);
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await tester.pumpAndSettle();
    expect(control.multipleCalls, 1);
    expect(find.byKey(const Key('pill-empty-results-1')), findsOneWidget);

    await _tapVisible(tester, find.text('이 알약 다시 비교'));
    await tester.pumpAndSettle();

    // 사진 전체를 다시 분석하지 않고 둘째 알약의 영역만 보낸다.
    expect(control.multipleCalls, 1);
    expect(control.refinementCalls, 1);
    expect(control.croppedRegion?.left, 0.6);
    expect(control.submittedFront, control.croppedBytes);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(find.byKey(const Key('pill-empty-results-1')), findsNothing);

    await _tapVisible(tester, find.text('페라트라정2.5밀리그램(레트로졸)'));
    await tester.pumpAndSettle();
    expect(_confirmButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 선택한 알약 사진이 크기 제한을 넘으면 실패 안내를 표시하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('pill photo selection surfaces oversized image failures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en'),
          control: _OversizedImageIdentifyPill(),
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(
      find.text('Each pill image must be 10 MB or smaller.'),
      findsOneWidget,
    );
    final identifyButton = tester.widget<FilledButton>(
      find.byKey(const Key('identify-pill-button')),
    );
    expect(identifyButton.onPressed, isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 앞면과 선택적 뒷면 사진을 서로 독립적으로 제거할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('front and optional back photos can be removed independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en'),
          control: _FakeIdentifyPill(),
        ),
      ),
    );

    for (final slotKey in const [
      Key('pill-front-image-slot'),
      Key('pill-back-image-slot'),
    ]) {
      await _tapVisible(tester, find.byKey(slotKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take Photo'));
      await tester.pumpAndSettle();
    }

    // Function Name: identifyButton
    // Description:
    // - Read the identification button after each image change to inspect whether it is enabled.
    // Parameters:
    // - None.
    // Returns:
    // - The current FilledButton identified by the stable test key.
    FilledButton identifyButton() => tester.widget<FilledButton>(
      find.byKey(const Key('identify-pill-button')),
    );

    expect(identifyButton().onPressed, isNotNull);
    expect(
      find.byKey(const Key('remove-pill-front-image-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('remove-pill-back-image-button')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('remove-pill-front-image-button'))),
      const Size(48, 48),
    );
    final frontRemoveButton = tester.widget<IconButton>(
      find.byKey(const Key('remove-pill-front-image-button')),
    );
    final backRemoveButton = tester.widget<IconButton>(
      find.byKey(const Key('remove-pill-back-image-button')),
    );
    expect(frontRemoveButton.tooltip, 'Remove Front photo');
    expect(backRemoveButton.tooltip, 'Remove Back photo');

    await tester.tap(find.byKey(const Key('remove-pill-back-image-button')));
    await tester.pump();

    expect(identifyButton().onPressed, isNotNull);
    expect(
      find.byKey(const Key('remove-pill-back-image-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('remove-pill-front-image-button')));
    await tester.pump();

    expect(identifyButton().onPressed, isNull);
    expect(
      find.byKey(const Key('remove-pill-front-image-button')),
      findsNothing,
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 신뢰도가 낮은 후보에는 서버의 확인 주의 문구를 표시하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('uncertain results surface the backend confidence warning', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en'),
          control: _LowConfidenceIdentifyPill(),
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pill-confidence-warning')), findsOneWidget);
    expect(find.textContaining('matches are uncertain'), findsOneWidget);
    final resultSemantics = tester
        .getSemantics(find.byKey(const Key('pill-candidate-results')))
        .getSemanticsData();
    expect(resultSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(resultSemantics.label, contains('Pill identification completed.'));
    semantics.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 후보가 없는 결과를 접근성 실시간 안내로 알리는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('empty results are announced as a live accessibility update', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en'),
          control: _EmptyIdentifyPill(),
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();

    final emptyResult = find.byKey(const Key('pill-empty-results'));
    expect(emptyResult, findsOneWidget);
    final resultSemantics = tester.getSemantics(emptyResult).getSemanticsData();
    expect(resultSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(resultSemantics.label, contains('0 possible matches'));
    semantics.dispose();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 대체 사진을 불러오는 동안 이전 후보의 확정 명령을 비활성화하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('replacement image loading disables stale candidate actions', (
    tester,
  ) async {
    final control = _DelayedReplacementIdentifyPill();
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en'),
          control: control,
        ),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    final candidateName = find.textContaining('페라트라');
    await tester.ensureVisible(candidateName);
    await tester.tap(candidateName);
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('confirm-pill-candidate-button')),
          )
          .onPressed,
      isNotNull,
    );

    final frontSlot = find.byKey(const Key('pill-front-image-slot'));
    await tester.ensureVisible(frontSlot);
    await tester.tap(frontSlot);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose From Gallery'));
    await tester.pump();

    final identifyButton = tester.widget<FilledButton>(
      find.byKey(const Key('identify-pill-button')),
    );
    final confirmButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('confirm-pill-candidate-button')),
    );
    expect(identifyButton.onPressed, isNull);
    expect(confirmButton.onPressed, isNull);
    expect(
      find.byKey(const Key('pill-image-loading-indicator')),
      findsOneWidget,
    );

    control.replacementImage.complete(_FakeIdentifyPill._png);
    await tester.pumpAndSettle();
    expect(find.textContaining('페라트라'), findsNothing);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: candidate results fit a compact viewport at large text size.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('candidate results fit a compact viewport at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        // Function Name: builder callback
        // Description:
        // - Apply text scale 1.3 to the existing child for accessibility layout checks.
        // Parameters:
        // - context (BuildContext): Widget context used for inherited settings or navigation.
        // - child (Widget?): Existing subtree whose media settings are overridden.
        // Returns:
        // - A MediaQuery wrapping the original child with the override.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'en', fontSize: 20),
          control: _FakeIdentifyPill(),
        ),
      ),
    );

    final frontSlot = find.byKey(const Key('pill-front-image-slot'));
    await tester.ensureVisible(frontSlot);
    await tester.tap(frontSlot);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    final identifyButton = find.byKey(const Key('identify-pill-button'));
    await tester.ensureVisible(identifyButton);
    await tester.tap(identifyButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
