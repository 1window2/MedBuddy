// 파일명: pill_identification_ui_boundary_test.dart
// 역할: 낱알약 사진 선택, 일괄 식별, 검토와 저장 화면을 검증한다.

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

class _FakeIdentifyPill extends IdentifyPill {
  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  _FakeIdentifyPill()
    : super(client: MockClient((_) async => http.Response('{}', 500)));

  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    return _png;
  }

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

class _OversizedImageIdentifyPill extends _FakeIdentifyPill {
  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    throw const PillIdentificationException(
      PillIdentificationFailure.oversizedImage,
    );
  }
}

class _LowConfidenceIdentifyPill extends _FakeIdentifyPill {
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

class _EmptyIdentifyPill extends _FakeIdentifyPill {
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

class _DelayedReplacementIdentifyPill extends _FakeIdentifyPill {
  final replacementImage = Completer<Uint8List?>();
  int _selectionCount = 0;

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
class _MultipleIdentifyPill extends _FakeIdentifyPill {
  int _selectionCount = 0;
  int _requestCount = 0;

  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    _selectionCount += 1;
    // 테스트에서 서로 다른 사진을 선택한 상황을 실제 바이트 차이로 표현한다.
    return Uint8List.fromList([..._FakeIdentifyPill._png, _selectionCount]);
  }

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

// 클래스명: _DuplicateIdentifyPill
// 역할: 서로 다른 사진이 같은 품목으로 판정된 중복 검토 흐름을 재현한다.
class _DuplicateIdentifyPill extends _FakeIdentifyPill {
  int _selectionCount = 0;

  @override
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    _selectionCount += 1;
    return Uint8List.fromList([..._FakeIdentifyPill._png, _selectionCount]);
  }

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

// 함수명: _tapVisible
// 함수역할:
// - 큰 글씨로 화면 아래에 배치된 검사 대상을 먼저 스크롤한 뒤 누른다.
// 매개변수:
// - tester: 위젯 테스트 제어기
// - finder: 화면에서 누를 위젯 탐색기
// 반환값:
// - 탭 처리 완료 상태
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
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
      savedRequests?.map((request) => request.candidate.itemSeq).toList(),
      ['multi-pill-1', 'multi-pill-2'],
    );
    expect(find.text('저장 2개, 기존 정보 0개, 실패 0개입니다.'), findsOneWidget);
  });

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

  testWidgets('candidate results fit a compact viewport at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
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
