// File Name: pill_identification_ui_boundary_test.dart
// Role: Regression coverage for pill-photo selection, candidate confirmation, schedule review, and
//   accessible results.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    if (!expandCandidates) return result;
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
              for (var i = 0; i < 11; i++)
                PillIdentificationCandidate(
                  itemSeq: '$i',
                  itemName: '동점 후보 $i',
                  matchScore: 1,
                ),
            ],
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

// Function Name: main
// Description:
// - Register regression cases for pill-photo selection, candidate confirmation, schedule review, and
//   accessible results.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
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
    expect(tester.takeException(), isNull);
  });

  for (final legacyEnabled in [null, false, true]) {
    // 함수이름: 기본 다중 알약 진입 테스트
    // 함수역할: 신규 설정과 이전 실험실 설정 유무에 관계없이 단일·다중 알약 입력을 제공한다.
    // 매개변수: tester: 위젯 도구. 반환값: 입력 명령 표시 검증 완료.
    testWidgets('다중 알약은 이전 설정과 무관하게 기본 제공된다 $legacyEnabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PillIdentificationUI(
            userSetting: UserSetting.fromJson({
              'language': 'ko',
              'multi_pill_identification_lab_enabled': ?legacyEnabled,
            }),
            control: _FakeIdentifyPill(),
          ),
        ),
      );

      expect(find.text('알약을 한 개 이상 촬영해주세요'), findsOneWidget);
      expect(find.byKey(const Key('pill-front-image-slot')), findsOneWidget);
      expect(
        find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('add-pill-photo-set-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('add-multiple-pill-images-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
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

    expect(find.text('알약 식별'), findsOneWidget);
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
    await tester.tap(find.text('Take a photo'));
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
      await tester.tap(find.text('Take a photo'));
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
    await tester.tap(find.text('Take a photo'));
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
    await tester.tap(find.text('Take a photo'));
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
    await tester.tap(find.text('Take a photo'));
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
    await tester.tap(find.text('Choose from gallery'));
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
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    final identifyButton = find.byKey(const Key('identify-pill-button'));
    await tester.ensureVisible(identifyButton);
    await tester.tap(identifyButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
