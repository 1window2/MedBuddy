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

    await tester.tap(find.byKey(const Key('pill-front-image-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카메라로 촬영'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('identify-pill-button')));
    await tester.pumpAndSettle();
    expect(find.text('페라트라정2.5밀리그램(레트로졸)'), findsOneWidget);

    await tester.tap(find.text('페라트라정2.5밀리그램(레트로졸)'));
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

    await tester.tap(find.byKey(const Key('pill-front-image-slot')));
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
      await tester.tap(find.byKey(slotKey));
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

    await tester.tap(find.byKey(const Key('pill-front-image-slot')));
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

    await tester.tap(find.byKey(const Key('pill-front-image-slot')));
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

    await tester.tap(find.byKey(const Key('pill-front-image-slot')));
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
