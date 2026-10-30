import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_wordmark.dart';

void main() {
  setUpAll(() async {
    final font = Platform.environment['MEDBUDDY_TEST_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in ['Roboto', 'Arial', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  for (final width in [150.0, 220.0]) {
    testWidgets('wordmark fits $width without cropping either brand part', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: MedBuddyColors.pageBackground,
            body: Center(
              child: RepaintBoundary(
                key: const Key('brand-preview'),
                child: ColoredBox(
                  color: MedBuddyColors.pageBackground,
                  child: SizedBox(
                    width: width,
                    child: const MedBuddyWordmark(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('MedBuddy'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.getSize(find.byType(MedBuddyWordmark)).width, width);
      final tagline = find.byKey(const Key('brand-tagline'));
      final wordmark = find.byKey(const Key('brand-wordmark-image'));
      expect(find.text('SMART MEDICATION CARE'), findsOneWidget);
      expect(
        tester.getTopLeft(tagline).dx,
        closeTo(tester.getTopLeft(wordmark).dx, .1),
      );
      expect(
        tester.getTopRight(tagline).dx,
        closeTo(tester.getTopRight(wordmark).dx, .1),
      );
      expect(
        tester.getTopLeft(tagline).dy,
        greaterThan(tester.getBottomLeft(wordmark).dy),
      );
      expect(tester.takeException(), isNull);
      if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
        await expectLater(
          find.byKey(const Key('brand-preview')),
          matchesGoldenFile('../.dart_tool/result_previews/brand-$width.png'),
        );
      }
    });
  }
}
