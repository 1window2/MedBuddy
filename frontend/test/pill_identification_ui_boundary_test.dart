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
  Future<XFile?> requestPillImage(ImageSource source) async {
    return XFile.fromData(_png, mimeType: 'image/png', name: 'pill.png');
  }

  @override
  Future<PillIdentificationResult> requestPillIdentification({
    required XFile frontImage,
    XFile? backImage,
  }) async {
    return const PillIdentificationResult(
      success: true,
      message: 'Candidates found.',
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
  Future<XFile?> requestPillImage(ImageSource source) async {
    return XFile.fromData(Uint8List(IdentifyPill.maxImageBytes + 1));
  }
}

void main() {
  testWidgets('pill candidate flow requires explicit user confirmation',
      (tester) async {
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
    final confirmButton =
        find.byKey(const Key('confirm-pill-candidate-button'));
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('후보 선택 완료'), findsOneWidget);
    expect(find.textContaining('확정 결과가 아니므로'), findsOneWidget);
  });

  testWidgets('pill photo preview rejects oversized images before allocation',
      (tester) async {
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
        find.text('Each pill image must be 10 MB or smaller.'), findsOneWidget);
    final identifyButton = tester.widget<FilledButton>(
      find.byKey(const Key('identify-pill-button')),
    );
    expect(identifyButton.onPressed, isNull);
  });
}
