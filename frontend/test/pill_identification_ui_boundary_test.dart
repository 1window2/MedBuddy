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
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';
import 'package:medbuddy_frontend/widgets/medication_review_image_gallery.dart';

// Class Name: _FakeIdentifyPill
// Role: Pill-identification fixture with a valid PNG and one confirmable candidate.
// Responsibilities:
// - Supply the embedded PNG without opening camera or gallery UI.
// - Provide a confident candidate with front/back imprints while still requiring user confirmation.
// Attributes: _png (Uint8List): Embedded valid image returned by photo selection.
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
// Attributes: No additional state; inherits the fixed identification fixture.
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

// Class Name: _OnePhotoMultipleIdentifyPill
// Role: Single-photo fixture containing two separately numbered pill observations.
// Responsibilities:
// - Return two bounded observations with distinct shapes, candidates, and confidence levels.
// Attributes: No additional state; returns fixed numbered observations.
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

class _DelayedMultipleIdentifyPill extends _OnePhotoMultipleIdentifyPill {
  final analysis = Completer<MultiplePillIdentificationResult>();

  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) => analysis.future;

  void completeAnalysis() {
    analysis.complete(
      super.requestMultiplePillIdentification(image: _FakeIdentifyPill._png),
    );
  }
}

class _ImageCandidatesIdentifyPill extends _OnePhotoMultipleIdentifyPill {
  final String language;

  _ImageCandidatesIdentifyPill(this.language);

  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    final result = await super.requestMultiplePillIdentification(image: image);
    return MultiplePillIdentificationResult(
      requiresConfirmation: true,
      observations: [
        MultiplePillObservation(
          index: 1,
          boundingBox: result.observations.first.boundingBox,
          identification: PillIdentificationResult(
            isConfident: false,
            requiresConfirmation: true,
            observedFeatures: const PillVisualFeatures(),
            candidates: [
              for (var index = 0; index < 2; index++)
                PillIdentificationCandidate(
                  itemSeq: 'image-$index',
                  itemName: language == 'en'
                      ? 'Example tablet 2.5 mg'
                      : '예시정2.5밀리그램',
                  manufacturer: language == 'en' ? 'Example Pharma' : '예시제약',
                  imageUrl: 'https://nedrug.mfds.go.kr/pill-$index.png',
                  printFront: 'AB',
                  printBack: '25',
                  matchScore: 0.7,
                ),
            ],
          ),
        ),
        result.observations.last,
      ],
    );
  }
}

// 클래스명: _RefinementIdentifyPill
// 역할: 번호별 자르기·뒷면·실패·동점 확장을 외부 호출 없이 검증한다.
// 주요 책임: 선택·자르기·재식별 입력을 기록하고 취소·실패·후보 확장을 재현한다.
// 속성: expandCandidates, incompleteCandidateList, failRefinement, cancelPicker (bool): 응답 조건.
// - refinementCalls (int): 재식별 횟수; croppedRegion (PillBoundingBox?): 자른 범위.
// - submittedFront, submittedBack (Uint8List?): 최근 앞·뒷면 입력.
// - croppedBytes (Uint8List): 원본과 구분되는 자른 사진 바이트.
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
  IdentifyPill control, {
  String language = 'ko',
  double textScale = 1,
  Size physicalSize = const Size(320, 800),
  double devicePixelRatio = 1,
  bool Function(List<IdentifiedPillSaveRequest>)? onReviewRequested,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PillIdentificationUI(
        userSetting: UserSetting(language: language, fontSize: 20),
        control: control,
        onReviewRequested: onReviewRequested ?? (_) => true,
      ),
    ),
  );
  await _tapVisible(
    tester,
    find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(language == 'en' ? 'Take photo' : '카메라로 촬영'));
  await tester.pumpAndSettle();
}

// 클래스명: _DuplicateOnePhotoIdentifyPill
// 역할: 한 장의 사진에서 찾은 두 알약이 같은 품목으로 판정된 중복 검토 흐름을 재현한다.
// 주요 책임: 서로 다른 영역의 두 알약에 같은 품목 후보를 돌려줘 선택적 중복 병합을 재현한다.
// 속성: 없음.
class _DuplicateOnePhotoIdentifyPill extends _FakeIdentifyPill {
  // 함수이름: requestMultiplePillIdentification
  // 함수역할: 두 영역 모두 duplicate-pill 후보를 가진 결과를 돌려준다.
  // 매개변수: image (Uint8List): 촬영 사진. 이 대역에서는 사용하지 않는다.
  // 반환값: 두 알약 영역의 식별 결과.
  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    const identification = PillIdentificationResult(
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
          identification: identification,
        ),
        MultiplePillObservation(
          index: 2,
          boundingBox: PillBoundingBox(
            left: 0.6,
            top: 0.55,
            width: 0.25,
            height: 0.25,
          ),
          identification: identification,
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
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
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
      .widget<KeepWordsText>(
        find.descendant(
          of: find.byKey(const Key('confirm-pill-candidate-button')),
          matching: find.byType(KeepWordsText),
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
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'review stays fixed and photo controls share heading $language $scale',
        (tester) async {
          final control = _OnePhotoMultipleIdentifyPill();
          addTearDown(control.dispose);
          await _openRefinementGroup(
            tester,
            control,
            language: language,
            textScale: scale,
          );
          await tester.pump(const Duration(seconds: 6));
          await tester.pumpAndSettle();
          final footer = find.byKey(const Key('pill-review-footer'));
          final button = find.byKey(const Key('confirm-pill-candidate-button'));
          final initialBounds = tester.getRect(footer);
          expect(initialBounds.bottom, 800);
          expect(button.hitTestable(), findsOneWidget);
          expect(_confirmButton(tester).onPressed, isNull);
          expect(
            find.ancestor(
              of: footer,
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
          );
          final heading = find.byKey(const Key('pill-photo-heading'));
          final change = find.byKey(
            const Key('identify-multiple-pills-from-one-photo-button'),
          );
          expect(
            find.descendant(of: heading, matching: change),
            findsOneWidget,
          );
          expect(find.textContaining('사진에서 찾은 알약에 번호를 표시'), findsNothing);
          expect(
            find.textContaining('Detected pills are numbered'),
            findsNothing,
          );
          final frame = find.byKey(const Key('multiple-pill-photo-frame'));
          final firstGroup = find.byKey(const Key('pill-result-group-0'));
          expect(
            tester.getRect(change).right,
            closeTo(tester.getRect(frame).right, 0.01),
          );
          expect(
            tester.getRect(change).center.dy,
            closeTo(tester.getRect(heading).center.dy, 0.01),
          );
          expect(
            tester.getRect(frame).top - tester.getRect(heading).bottom,
            closeTo(8, 0.01),
          );
          expect(
            tester.getRect(firstGroup).top - tester.getRect(frame).bottom,
            16,
          );
          await _tapVisible(tester, find.text('첫 번째 알약'));
          await tester.pumpAndSettle();
          expect(_confirmButton(tester).onPressed, isNotNull);
          expect(_confirmButtonLabel(tester), contains('1'));
          expect(tester.getRect(footer).bottom, initialBounds.bottom);
          expect(button.hitTestable(), findsOneWidget);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(footer).bottom, initialBounds.bottom);
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final language in ['ko', 'en']) {
    testWidgets('multiple-photo entry reserves the uploaded frame $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final control = _OnePhotoMultipleIdentifyPill();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: PillIdentificationUI(
            userSetting: UserSetting(language: language),
            control: control,
            onReviewRequested: (_) => true,
          ),
        ),
      );
      final frame = find.byKey(const Key('multiple-pill-photo-frame'));
      final addPhoto = find.byKey(
        const Key('identify-multiple-pills-from-one-photo-button'),
      );
      final initialSize = tester.getSize(frame);
      expect(initialSize.width, 280);
      expect(initialSize.aspectRatio, closeTo(16 / 9, 0.001));
      expect(find.byKey(const Key('pill-front-image-slot')), findsNothing);
      expect(find.byKey(const Key('pill-result-group-0')), findsNothing);
      expect(
        find.textContaining(language == 'en' ? 'Pill 1' : '알약 1'),
        findsNothing,
      );
      expect(find.descendant(of: frame, matching: addPhoto), findsOneWidget);
      final icon = find.byIcon(Icons.add_photo_alternate_outlined);
      expect(
        tester.getCenter(icon).dx,
        closeTo(tester.getCenter(frame).dx, 0.1),
      );
      expect(tester.getSize(addPhoto), initialSize);
      await _tapVisible(tester, addPhoto);
      await tester.pumpAndSettle();
      await tester.tap(find.text(language == 'en' ? 'Take photo' : '카메라로 촬영'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(_FakeIdentifyPill._png),
          tester.element(frame),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(frame), initialSize);
      final imageBounds = tester.getRect(
        find.byKey(const Key('multiple-pill-preview-image')),
      );
      final overlayBounds = tester.getRect(
        find.byKey(const Key('multiple-pill-region-overlay')),
      );
      expect(imageBounds.size.aspectRatio, 1);
      expect(overlayBounds, imageBounds);
      expect(imageBounds.width, lessThan(initialSize.width));
      expect(imageBounds.height, closeTo(initialSize.height, 0.1));
      expect(_confirmButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    for (final compact in [false, true]) {
      testWidgets('candidate rows stay horizontal $language compact=$compact', (
        tester,
      ) async {
        final control = _ImageCandidatesIdentifyPill(language);
        addTearDown(control.dispose);
        // Local emulator profiles: 1080 x 2400 at 420 dpi (2.625 DPR).
        await _openRefinementGroup(
          tester,
          control,
          language: language,
          physicalSize: compact ? const Size(320, 800) : const Size(1080, 2400),
          devicePixelRatio: compact ? 1 : 2.625,
          textScale: compact ? 2 : 1,
        );
        final row = find.byKey(const Key('pill-candidate-row-image-0'));
        final thumbnail = find.byKey(const Key('pill-candidate-image-image-0'));
        final details = find.byKey(const Key('pill-candidate-details-image-0'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final imageBounds = tester.getRect(thumbnail);
        final detailsBounds = tester.getRect(details);
        final radio = find.descendant(
          of: row,
          matching: find.byIcon(Icons.radio_button_unchecked),
        );
        final radioBounds = tester.getRect(radio);
        expect(imageBounds.width, inInclusiveRange(72, 80));
        expect(imageBounds.height, imageBounds.width);
        expect(detailsBounds.left, greaterThan(imageBounds.right));
        expect(detailsBounds.top, closeTo(imageBounds.top, 0.1));
        expect(radioBounds.left, greaterThan(detailsBounds.right));
        expect(radioBounds.top, closeTo(imageBounds.top, 0.1));
        if (!compact) {
          expect(tester.getSize(row).height, lessThanOrEqualTo(100));
        }
        final group = find.byKey(const Key('pill-result-group-0'));
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const Key('pill-confidence-warning')),
          ),
          findsOneWidget,
        );
        expect(
          find.text(language == 'en' ? 'More evidence needed' : '추가 확인 필요'),
          findsNothing,
        );
        expect(
          find.text(language == 'en' ? 'Candidate for comparison' : '비교 후보'),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.textContaining('AB / 25')),
          findsOneWidget,
        );
        expect(_confirmButton(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('candidate image zoom does not change selection $language', (
      tester,
    ) async {
      final control = _ImageCandidatesIdentifyPill(language);
      addTearDown(control.dispose);
      await _openRefinementGroup(tester, control, language: language);
      final image = find.byKey(const Key('pill-candidate-image-image-0'));
      await _tapVisible(tester, image);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.maxScale, greaterThan(1));
      final close = find.byKey(const Key('medication-image-viewer-close'));
      expect(
        tester.widget<IconButton>(close).tooltip,
        language == 'en' ? 'Close enlarged image' : '확대 사진 닫기',
      );
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(_confirmButton(tester).onPressed, isNull);
      final details = find.byKey(const Key('pill-candidate-details-image-0'));
      await _tapVisible(
        tester,
        find.descendant(
          of: details,
          matching: find.text(
            language == 'en' ? 'Example tablet 2.5 mg' : '예시정2.5밀리그램',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selectedLabel = _confirmButtonLabel(tester);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(_confirmButton(tester).onPressed, isNotNull);
      await _tapVisible(tester, image);
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(_confirmButtonLabel(tester), selectedLabel);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(_confirmButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI disclosure hides at five seconds $language', (
      tester,
    ) async {
      final control = _FakeIdentifyPill();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PillIdentificationUI(
            userSetting: UserSetting(language: language),
            control: control,
            onReviewRequested: (_) => true,
          ),
        ),
      );
      final disclosure = find.byKey(const Key('pill-ai-disclosure'));
      expect(disclosure, findsOneWidget);
      expect(
        find.textContaining(language == 'en' ? 'external AI' : '외부 AI'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 4999));
      expect(disclosure, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(disclosure, findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(disclosure, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two detected pills hand off only the selected one $language', (
      tester,
    ) async {
      final control = _OnePhotoMultipleIdentifyPill();
      addTearDown(control.dispose);
      final savedBatches = <List<String>>[];
      await _openRefinementGroup(
        tester,
        control,
        language: language,
        onReviewRequested: (requests) {
          for (final request in requests) {
            expect(
              request.medicationSchedule.medicationName,
              request.candidate.itemName,
            );
          }
          savedBatches.add([
            for (final request in requests) request.candidate.itemSeq,
          ]);
          // 거절하면 화면이 남아 선택이 유지되는지 확인할 수 있다.
          return false;
        },
      );
      final zeroLabel = language == 'en' ? '0 pills selected' : '선택한 알약 0개';
      final oneLabel = language == 'en'
          ? 'Review and save 1 selected pill'
          : '선택한 알약 1개 검토 후 저장';
      expect(_confirmButtonLabel(tester), zeroLabel);
      expect(_confirmButton(tester).onPressed, isNull);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(const Key('pill-candidate-image-group-2')),
      );
      await tester.pumpAndSettle();
      expect(_confirmButton(tester).onPressed, isNull);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(
        find.textContaining(
          language == 'en' ? 'Only the pills you select' : '선택한 알약만 검토하고 저장',
        ),
        findsNothing,
      );

      await _tapVisible(tester, find.text('두 번째 알약'));
      await tester.pumpAndSettle();
      expect(_confirmButtonLabel(tester), oneLabel);
      expect(_confirmButton(tester).onPressed, isNotNull);
      final staleConfirm = _confirmButton(tester).onPressed!;
      await _tapVisible(tester, find.text('두 번째 알약'));
      await tester.pumpAndSettle();
      expect(_confirmButtonLabel(tester), zeroLabel);
      expect(_confirmButton(tester).onPressed, isNull);
      staleConfirm();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-review-confirm')), findsNothing);

      await _tapVisible(tester, find.text('두 번째 알약'));
      await _tapVisible(
        tester,
        find.byKey(const Key('confirm-pill-candidate-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-review-card-0')), findsOneWidget);
      expect(find.byKey(const Key('schedule-review-card-1')), findsNothing);
      final reviewList = find.byKey(const Key('schedule-review-list'));
      expect(
        find.descendant(of: reviewList, matching: find.text('두 번째 알약')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: reviewList, matching: find.text('첫 번째 알약')),
        findsNothing,
      );
      expect(savedBatches, isEmpty);
      final gallery = tester.widget<MedicationReviewImageGallery>(
        find.byType(MedicationReviewImageGallery),
      );
      expect(gallery.photos, hasLength(1));
      expect(
        gallery.photos.single.title,
        language == 'en' ? 'Pill photo' : '촬영한 알약 사진',
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('schedule-review-confirm')),
      );
      await tester.pumpAndSettle();
      expect(savedBatches, [
        ['group-2'],
      ]);
      expect(_confirmButtonLabel(tester), oneLabel);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pill groups fit narrow screens with large text $language', (
      tester,
    ) async {
      final control = _RefinementIdentifyPill()..expandCandidates = true;
      addTearDown(control.dispose);
      await _openRefinementGroup(
        tester,
        control,
        language: language,
        textScale: 2,
      );
      for (var index = 0; index < 2; index++) {
        final group = find.byKey(Key('pill-result-group-$index'));
        final decoration =
            tester.widget<Container>(group).decoration! as BoxDecoration;
        expect(decoration.borderRadius, MedBuddyRadii.card);
        expect(decoration.color, MedBuddyColors.surface);
        expect(decoration.border, isNotNull);
        for (final action in ['region', 'back']) {
          final button = find.byKey(Key('refine-pill-$action-$index'));
          expect(find.descendant(of: group, matching: button), findsOneWidget);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(button);
          expect(bounds.left, greaterThanOrEqualTo(20));
          expect(bounds.right, lessThanOrEqualTo(300));
        }
        expect(
          find.descendant(
            of: group,
            matching: find.text(index == 0 ? '동점 후보 0' : '두 번째 알약'),
          ),
          findsOneWidget,
        );
      }
      await _tapVisible(tester, find.text('두 번째 알약'));
      await tester.ensureVisible(
        find.byKey(const Key('confirm-pill-candidate-button')),
      );
      await tester.pumpAndSettle();
      expect(_confirmButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disposing before five seconds cancels the disclosure timer', (
    tester,
  ) async {
    final control = _FakeIdentifyPill();
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: control,
          onReviewRequested: (_) => true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    // Leaving the clock before expiry also checks for an uncancelled timer.
  });

  testWidgets('disclosure timeout does not finish or interrupt analysis', (
    tester,
  ) async {
    final control = _DelayedMultipleIdentifyPill();
    addTearDown(control.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PillIdentificationUI(
          userSetting: const UserSetting(language: 'ko'),
          control: control,
          onReviewRequested: (_) => true,
        ),
      ),
    );
    final photoButton = find.byKey(
      const Key('identify-multiple-pills-from-one-photo-button'),
    );
    await _tapVisible(tester, photoButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pump();
    expect(find.byKey(const Key('pill-ai-disclosure')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('pill-ai-disclosure')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.widget<FilledButton>(photoButton).onPressed, isNull);
    control.completeAnalysis();
    await tester.pumpAndSettle();
    expect(find.text('첫 번째 알약'), findsOneWidget);
    expect(find.text('두 번째 알약'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
    expect(find.byKey(const Key('pill-ai-disclosure')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('여러 알약 검토는 선택한 약만 결과 단계에 넘기고 바로 저장하지 않는다', (tester) async {
    final control = _PartlyEmptyIdentifyPill();
    addTearDown(control.dispose);
    List<IdentifiedPillSaveRequest>? reviewed;
    await _openRefinementGroup(
      tester,
      control,
      onReviewRequested: (requests) {
        reviewed = requests;
        return true;
      },
    );
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await _reviewAndConfirm(tester);
    expect(reviewed, hasLength(1));
    expect(reviewed!.single.candidate.itemSeq, 'group-1');
    expect(reviewed!.single.medicationSchedule.scheduleSlotKeys, ['morning']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('결과 단계가 거절하면 후보와 일정을 유지하고 다시 넘길 수 있다', (tester) async {
    final control = _OnePhotoMultipleIdentifyPill();
    addTearDown(control.dispose);
    var attempts = 0;
    await _openRefinementGroup(
      tester,
      control,
      onReviewRequested: (requests) {
        attempts++;
        expect(requests.single.candidate.itemSeq, 'group-1');
        return false;
      },
    );
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await _reviewAndConfirm(tester);
    expect(attempts, 1);
    expect(_confirmButton(tester).onPressed, isNotNull);
    await _reviewAndConfirm(tester);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unselected pill without candidates does not block review', (
    tester,
  ) async {
    final control = _PartlyEmptyIdentifyPill();
    addTearDown(control.dispose);
    final saved = <String>[];
    await _openRefinementGroup(
      tester,
      control,
      onReviewRequested: (requests) {
        saved.addAll(requests.map((request) => request.candidate.itemSeq));
        return true;
      },
    );
    expect(find.byKey(const Key('pill-empty-results-1')), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await _reviewAndConfirm(tester);
    expect(saved, ['group-1']);
    expect(control.refinementCalls, 0);
  });

  testWidgets('candidate bounds restrict only selected pills', (tester) async {
    final control = _RefinementIdentifyPill()..incompleteCandidateList = true;
    addTearDown(control.dispose);
    final saved = <String>[];
    await _openRefinementGroup(
      tester,
      control,
      onReviewRequested: (requests) {
        saved.addAll(requests.map((request) => request.candidate.itemSeq));
        return true;
      },
    );
    await _tapVisible(tester, find.text('두 번째 알약'));
    await tester.pumpAndSettle();
    final confirm = _confirmButton(tester).onPressed!;
    expect(_confirmButtonLabel(tester), '선택한 알약 1개 검토 후 저장');
    await _tapVisible(tester, find.text('동점 후보 0'));
    await tester.pumpAndSettle();
    expect(_confirmButton(tester).onPressed, isNull);
    expect(_confirmButtonLabel(tester), '선택한 알약 2개 검토 후 저장');
    confirm();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-review-confirm')), findsNothing);
    expect(saved, isEmpty);
    await _tapVisible(tester, find.text('동점 후보 0'));
    await _reviewAndConfirm(tester);
    expect(saved, ['group-2']);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets callback
  // 함수역할:
  // - 알약 후보 확인을 연속 호출해도 검토창 하나만 열리고 취소 시 저장하지 않으며 이후 재확인에서 한 번만 저장하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('후보 확인 연속 호출은 검토창 하나만 열고 취소 후 다시 열린다', (tester) async {
    final control = _OnePhotoMultipleIdentifyPill();
    addTearDown(control.dispose);
    var saves = 0;
    await _openRefinementGroup(
      tester,
      control,
      physicalSize: const Size(360, 3000),
      onReviewRequested: (_) {
        saves++;
        return true;
      },
    );
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await tester.pump();
    final confirm = _confirmButton(tester).onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    final review = find.byKey(const Key('schedule-review-confirm'));
    Navigator.of(tester.element(review)).pop();
    await tester.pumpAndSettle();
    expect(review, findsNothing);
    expect(saves, 0);
    expect(_confirmButton(tester).onPressed, isNotNull);
    await _reviewAndConfirm(tester);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 전체 사진 변경 취소 테스트
  // 함수역할:
  // - 알약 두 개를 선택한 뒤 새 전체 사진 선택을 취소해도 기존 후보와 확인 버튼이 유지되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 사진 선택과 후보 확인 상태를 조작하는 도구.
  // 반환값:
  // - Future<void>: 선택 상태 보존 검증 완료.
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
    expect(find.textContaining('추가 확인 필요'), findsNothing);
    expect(find.textContaining('불확실한 후보'), findsNWidgets(2));
    await _tapVisible(tester, find.byKey(const Key('more-pill-candidates-0')));
    await tester.pumpAndSettle();
    expect(find.text('동점 후보 5'), findsOneWidget);
    await _tapVisible(tester, find.text('동점 후보 5'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Select visible candidates from an incomplete result set; the UI must explain that more matches exist and keep confirmation disabled.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
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
          onReviewRequested: (_) => true,
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
    // 함수이름: 기본 입력 테스트
    // 함수역할: 구형 실험실 설정과 무관하게 한 장 사진 입력만 제공한다.
    // 매개변수: tester. 반환값: 입력 버튼 검증 완료.
    testWidgets('한 장 사진 입력만 표시한다 $legacyEnabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PillIdentificationUI(
            userSetting: UserSetting.fromJson({
              'language': 'ko',
              'multi_pill_identification_lab_enabled': ?legacyEnabled,
            }),
            control: _FakeIdentifyPill(),
            onReviewRequested: (_) => true,
          ),
        ),
      );
      expect(
        find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('add-multiple-pill-images-button')),
        findsNothing,
      );
      expect(find.textContaining('외부 AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 확정한 알약의 복약 일정을 저장 전에 검토하고 수정할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('confirmed pill schedule is reviewed before hand-off', (
    tester,
  ) async {
    MedicationSchedule? savedSchedule;
    PillIdentificationCandidate? savedCandidate;
    final control = _OnePhotoMultipleIdentifyPill();
    addTearDown(control.dispose);
    await _openRefinementGroup(
      tester,
      control,
      physicalSize: const Size(360, 800),
      onReviewRequested: (requests) {
        savedCandidate = requests.single.candidate;
        savedSchedule = requests.single.medicationSchedule;
        return true;
      },
    );
    await _tapVisible(tester, find.text('첫 번째 알약'));
    await tester.pump();

    final confirmCandidate = find.byKey(
      const Key('confirm-pill-candidate-button'),
    );
    await tester.ensureVisible(confirmCandidate);
    await tester.tap(confirmCandidate);
    await tester.pumpAndSettle();

    expect(find.text('복약 정보 확인'), findsOneWidget);
    expect(find.textContaining('임시 기본값'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    final gallery = tester.widget<MedicationReviewImageGallery>(
      find.byType(MedicationReviewImageGallery),
    );
    expect(gallery.photos, hasLength(1));
    expect(gallery.photos.single.title, '촬영한 알약 사진');
    expect(find.byKey(const Key('pill-review-photo-side-0')), findsOneWidget);
    expect(savedSchedule, isNull);

    await _tapVisible(tester, find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(savedCandidate?.itemSeq, 'group-1');
    expect(savedSchedule?.prescriptionDate, isNotNull);
    expect(savedSchedule?.dosage, '1정');
    expect(savedSchedule?.dailyFrequencyCount, 1);
    expect(savedSchedule?.medicationTime, 1);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 같은 품목 사진은 알리고 같은 일정만 선택적으로 묶는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('같은 품목 사진은 알리고 같은 일정만 선택적으로 묶는다', (tester) async {
    final control = _DuplicateOnePhotoIdentifyPill();
    addTearDown(control.dispose);
    List<IdentifiedPillSaveRequest>? savedRequests;
    await _openRefinementGroup(
      tester,
      control,
      physicalSize: const Size(360, 3000),
      onReviewRequested: (requests) {
        savedRequests = requests;
        return true;
      },
    );

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

    // 같은 일정인 두 알약은 하나의 요청으로 결과 단계에 넘긴다.
    expect(savedRequests, hasLength(1));
    expect(savedRequests!.single.candidate.itemSeq, 'duplicate-pill');
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
          onReviewRequested: (_) => true,
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('identify-multiple-pills-from-one-photo-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(
      find.text('Each pill image must be 10 MB or smaller.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('confirm-pill-candidate-button')),
      findsNothing,
    );
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
    final control = _PartlyEmptyIdentifyPill();
    addTearDown(control.dispose);
    await _openRefinementGroup(tester, control, language: 'en');

    final emptyResult = find.byKey(const Key('pill-empty-results-1'));
    expect(emptyResult, findsOneWidget);
    final resultSemantics = tester.getSemantics(emptyResult).getSemanticsData();
    expect(resultSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(resultSemantics.label, contains('0 possible matches'));
    semantics.dispose();
  });
}
