// File Name: test_viewport.dart
// Role: Shared widget-test helper that sets the logical screen size and restores it afterwards.
//
// Does not simulate: device pixel density (the ratio is fixed at 1, so the given size is the
//   logical size), safe-area insets, or the global MEDBUDDY_TEST_TEXT_SCALE hook in
//   flutter_test_config.dart, which this helper overrides for the current test when textScale
//   is given.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

// Function Name: setTestViewport
// Description:
// - Give the test view the requested logical size at a device pixel ratio of 1 and register the
//   resets as tear-downs, so the next test starts from the default surface.
// - Optionally set the platform text scale and register its reset as well.
// Parameters:
// - tester (WidgetTester): Tester whose view is resized.
// - size (Size): Logical width and height of the screen.
// - textScale (double?): Platform text-scale factor; left unchanged when null.
// Returns:
// - None. The call is synchronous; call sites that awaited a local copy drop the await.
void setTestViewport(WidgetTester tester, Size size, {double? textScale}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}
