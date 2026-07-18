import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('analysis failure offers camera and gallery retry actions',
      (tester) async {
    var cameraRetryCount = 0;
    var galleryRetryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en'),
          onCameraRetryRequested: () => cameraRetryCount += 1,
          onGalleryRetryRequested: () => galleryRetryCount += 1,
          onHomeRequested: () {},
        ),
      ),
    );

    final cameraRetryButton = find.text('Retake Photo');
    await tester.ensureVisible(cameraRetryButton);
    await tester.tap(cameraRetryButton);
    await tester.pump();

    final galleryRetryButton =
        find.byKey(const Key('prescription-gallery-retry-button'));
    await tester.ensureVisible(galleryRetryButton);
    await tester.tap(
      galleryRetryButton,
    );

    expect(cameraRetryCount, 1);
    expect(galleryRetryCount, 1);
  });

  testWidgets('analysis failure actions fit a compact large-text viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: PrescriptionAnalysisFailureUI(
          message: 'The request failed.',
          userSetting: const UserSetting(language: 'en', fontSize: 20),
          onCameraRetryRequested: () {},
          onGalleryRetryRequested: () {},
          onHomeRequested: () {},
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const Key('prescription-gallery-retry-button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
