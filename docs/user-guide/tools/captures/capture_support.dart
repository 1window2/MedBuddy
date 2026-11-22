// File Name: capture_support.dart
// Role: Load explicit test fonts and capture unmodified widget geometry.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

final workspace = Platform.environment['GUIDE_WORKSPACE']!;
final captureOutput = Platform.environment['GUIDE_CAPTURE_OUTPUT']!;

// Function Name: captureTheme
// Description: Preserve product colors and geometry with test-only Korean glyphs.
// Parameters: None.
// Returns: ThemeData with Noto Sans KR text families.
ThemeData captureTheme() => MedBuddyTheme.light().copyWith(
  textTheme: MedBuddyTheme.light().textTheme.apply(fontFamily: 'Noto Sans KR'),
  primaryTextTheme: MedBuddyTheme.light().primaryTextTheme.apply(fontFamily: 'Noto Sans KR'),
);

// Function Name: captureFonts
// Description: Load external test fonts and create the configured capture directory.
// Parameters: None; paths come from GUIDE_CAPTURE_FONT and GUIDE_FLUTTER_SDK.
// Returns: Future<void>; missing files or font-loading errors fail the test.
Future<void> captureFonts() async {
  for (final entry in {
    'Roboto': 'NotoSansCJK-Regular.ttc',
    'Noto Sans KR': 'NotoSansCJK-Regular.ttc',
    'Ahem': 'NotoSansCJK-Regular.ttc',
    'Arial': 'NotoSansCJK-Regular.ttc',
  }.entries) {
    final loader = FontLoader(entry.key);
    loader.addFont(Future.value(ByteData.sublistView(File(Platform.environment['GUIDE_CAPTURE_FONT']!).readAsBytesSync())));
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File('${Platform.environment['GUIDE_FLUTTER_SDK']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
  Directory(captureOutput).createSync(recursive: true);
}

// Function Name: captureViewport
// Description: Set a stable viewport and restore its metrics after the test.
// Parameters: tester is the active WidgetTester.
// Returns: void; registers cleanup for the physical size and device pixel ratio.
void captureViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Function Name: captureScreen
// Description: Capture the product layer at 2x without simulated system chrome.
// Parameters: tester drives rendering; name is the PNG stem; settle waits for idle.
// Returns: Future<void>; writes a PNG and fails on a pending widget exception.
Future<void> captureScreen(WidgetTester tester, String name, {bool settle = true}) async {
  if (settle) await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.single.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$captureOutput/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}
