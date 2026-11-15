// File Name: prescription_result_presentation_regression_test.dart
// Role: Guards result-card painting, centered save confirmation, and full-page failure backgrounds.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';

const _captureKey = Key('presentation-capture');
const _dialogKey = Key('prescription-save-completed-dialog');
const _dialogContentKey = Key('prescription-save-completed-content');
const _destinations = ['today', 'pillbox', 'home'];

// Function Name: _viewport
// Description: Sets logical test dimensions and restores them after the test.
// Parameters: tester: Widget driver; size: Logical viewport size.
// Returns: None.
void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Function Name: _app
// Description: Applies the real dialog theme and inherited accessibility settings above the navigator.
// Parameters: child: Page; scale: Text scale; padding: Simulated system safe areas.
// Returns: A capturable application without external services.
Widget _app(
  Widget child, {
  double scale = 1,
  EdgeInsets padding = EdgeInsets.zero,
}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    theme: MedBuddyTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: padding,
        viewPadding: padding,
      ),
      child: child!,
    ),
    home: child,
  ),
);

// Function Name: _ignore
// Description: Leaves navigation inert in painting-only fixtures.
// Parameters: None. Returns: None.
void _ignore() {}

// Function Name: _result
// Description: Builds one successfully savable medication and optional prescription comparison.
// Parameters: language: UI locale; radar: Include a collapsed comparison; onDestination: Records navigation.
// Returns: A result page with deterministic save outcomes.
Widget _result({
  String language = 'en',
  bool radar = false,
  ValueChanged<String>? onDestination,
}) => CheckResultUI(
  analyzedMedicationList: const [
    AnalyzedMedication(
      schedule: MedicationSchedule(
        medicationName: 'Test tablet',
        dosage: '1 tablet',
        medicationTime: 5,
      ),
      detail: MedicationDetail(
        itemName: '',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
    ),
  ],
  prescriptionChangeRadar: radar
      ? const PrescriptionChangeRadar(hasPreviousPrescription: false)
      : null,
  userSetting: UserSetting(language: language),
  statusMessageProvider: () => 'Saved',
  savingMedicationIndex: null,
  completedMedicationSaveIndexes: const {},
  isAllMedicationSaving: false,
  onCloseRequested: _ignore,
  onTodayScheduleRequested: () => onDestination?.call('today'),
  onSavedMedicationRequested: () => onDestination?.call('pillbox'),
  onHomeRequested: () => onDestination?.call('home'),
  onAllMedicationSaveRequested: () async => true,
  onMedicationSaveRequested: (_, _) async => true,
);

// Function Name: _expectCornerOutlines
// Description: Checks all four rounded border arcs after child fills have been painted.
// Parameters: tester: Widget driver; card: Result/radar container; radius: Existing corner radius; color: Outline color.
// Returns: Completed structural and raster checks; an obscured arc fails the test.
Future<void> _expectCornerOutlines(
  WidgetTester tester,
  Finder card, {
  required double radius,
  required Color color,
}) async {
  final container = tester.widget<Container>(card);
  final decoration = container.foregroundDecoration! as BoxDecoration;
  expect(container.clipBehavior, Clip.antiAlias);
  expect(container.padding, const EdgeInsets.all(1));
  expect(decoration.borderRadius, BorderRadius.circular(radius));
  expect(decoration.border, Border.all(color: color));
  final bounds = (container.margin! as EdgeInsets).deflateRect(
    tester.getRect(card),
  );
  final diagonal = (radius - .5) / math.sqrt(2);
  final samples = [
    Offset(bounds.left + radius - diagonal, bounds.top + radius - diagonal),
    Offset(bounds.right - radius + diagonal, bounds.top + radius - diagonal),
    Offset(bounds.left + radius - diagonal, bounds.bottom - radius + diagonal),
    Offset(bounds.right - radius + diagonal, bounds.bottom - radius + diagonal),
  ];
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  // Function Name: raster callback
  // Description: Samples a small antialiasing neighborhood around each border's centerline.
  // Parameters: None. Returns: Completion of image capture and pixel assertions.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final argb = color.toARGB32();
      final expected = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255];
      for (final point in samples) {
        var closest = 765;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = (point.dx * 3).round() + dx;
            final y = (point.dy * 3).round() + dy;
            expect(x, inInclusiveRange(0, image.width - 1));
            expect(y, inInclusiveRange(0, image.height - 1));
            final offset = (y * image.width + x) * 4;
            var difference = 0;
            for (var channel = 0; channel < 3; channel++) {
              difference +=
                  (bytes.getUint8(offset + channel) - expected[channel]).abs();
            }
            closest = math.min(closest, difference);
          }
        }
        expect(
          closest,
          lessThan(24),
          reason: 'Missing rounded outline at $point',
        );
      }
    } finally {
      image.dispose();
    }
  });
}

// Function Name: _expectBackground
// Description: Verifies page color at the top/bottom safe areas and below short content.
// Parameters: tester: Widget driver; size: Logical viewport size.
// Returns: Completed pixel checks with no saved screenshot artifacts.
Future<void> _expectBackground(WidgetTester tester, Size size) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  // Function Name: raster callback
  // Description: Reads viewport background pixels outside the white failure card.
  // Parameters: None. Returns: Completion of color assertions.
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (final point in [
        Offset(size.width / 2, 2),
        Offset(2, size.height - 40),
        Offset(size.width / 2, size.height - 2),
      ]) {
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final actual = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        expect(
          actual,
          MedBuddyColors.pageBackground,
          reason: 'Background at $point',
        );
      }
    } finally {
      image.dispose();
    }
  });
}

// Function Name: main
// Description: Registers focused presentation regressions without starting a device or backend.
// Parameters: None. Returns: None; Flutter executes the registered tests.
void main() {
  // Function Name: summary-gap test
  // Description: Keeps a natural 20dp separation between the green header and summary surface.
  // Parameters: tester: Widget driver. Returns: Completed layout assertions.
  testWidgets('analysis-complete surface has room below the page header', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(_result()));
    final summary = find
        .ancestor(
          of: find.text('Analysis Complete'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final headerBottom = tester
        .getBottomLeft(find.byType(MedBuddyPageHeader))
        .dy;
    expect(tester.getTopLeft(summary).dy - headerBottom, 20);
    expect(tester.takeException(), isNull);
  });

  // Function Name: rounded-outlines test
  // Description: Checks every corner in both expansion states without moving headers or changing widths.
  // Parameters: tester: Widget driver. Returns: Completed layout and raster assertions.
  testWidgets('radar and medication outlines survive expand and collapse', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 1200));
    await tester.pumpWidget(_app(_result(radar: true)));
    for (final entry in [
      (
        key: 'prescription-radar-card',
        toggle: 'prescription-radar-toggle',
        radius: 20.0,
        color: MedBuddyColors.successBorder,
      ),
      (
        key: 'result-medication-card-0',
        toggle: 'result-medication-toggle-0',
        radius: 8.0,
        color: MedBuddyColors.outline,
      ),
    ]) {
      final card = find.byKey(Key(entry.key));
      final collapsed = tester.getRect(card);
      for (final expanded in [false, true, false]) {
        if (expanded || tester.getRect(card).height != collapsed.height) {
          await tester.tap(find.byKey(Key(entry.toggle)));
          await tester.pumpAndSettle();
        }
        final current = tester.getRect(card);
        expect(current.topLeft, collapsed.topLeft);
        expect(current.width, collapsed.width);
        expect(
          current.height,
          expanded ? greaterThan(collapsed.height) : collapsed.height,
        );
        await _expectCornerOutlines(
          tester,
          card,
          radius: entry.radius,
          color: entry.color,
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    for (final config in [
      (size: const Size(390, 844), scale: 1.0),
      (size: const Size(320, 568), scale: 2.0),
      (size: const Size(640, 360), scale: 2.0),
    ]) {
      // Function Name: save-destination test
      // Description: Confirms centered themed content, icon/description order, scrolling and all three routes.
      // Parameters: tester: Widget driver. Returns: Completed responsive navigation assertions.
      testWidgets(
        'save dialog keeps destinations reachable $language $config',
        (tester) async {
          _viewport(tester, config.size);
          final requested = <String>[];
          await tester.pumpWidget(
            _app(
              _result(
                language: language,
                onDestination: (destination) {
                  expect(
                    Navigator.of(
                      tester.element(find.byType(CheckResultUI)),
                    ).canPop(),
                    isFalse,
                  );
                  requested.add(destination);
                },
              ),
              scale: config.scale,
            ),
          );
          for (final destination in _destinations) {
            await tester.tap(find.byKey(const Key('prescription-save-all')));
            await tester.pumpAndSettle();
            expect(find.byKey(_dialogKey), findsOneWidget);
            expect(find.byType(BottomSheet), findsNothing);
            final surface = tester.getRect(find.byKey(_dialogContentKey));
            expect(surface.center.dx, closeTo(config.size.width / 2, .1));
            expect(surface.center.dy, closeTo(config.size.height / 2, .1));
            expect(surface.left, greaterThanOrEqualTo(24));
            expect(surface.right, lessThanOrEqualTo(config.size.width - 24));
            expect(surface.top, greaterThanOrEqualTo(24));
            expect(surface.bottom, lessThanOrEqualTo(config.size.height - 24));
            final icon = tester.getRect(
              find.byKey(const Key('prescription-save-completed-icon')),
            );
            final description = tester.getRect(
              find.byKey(const Key('prescription-save-completed-description')),
            );
            expect(description.top - icon.bottom, 12);
            final action = find.byKey(
              Key('prescription-save-open-$destination'),
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            final label = find
                .descendant(of: action, matching: find.byType(Text))
                .first;
            final paragraph = tester.renderObject<RenderParagraph>(label);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.textScaler.scale(16), 16 * config.scale);
            expect(
              tester.getRect(label).left,
              greaterThanOrEqualTo(tester.getRect(action).left),
            );
            expect(
              tester.getRect(label).right,
              lessThanOrEqualTo(tester.getRect(action).right),
            );
            expect(
              tester.getRect(label).top,
              greaterThanOrEqualTo(tester.getRect(action).top),
            );
            expect(
              tester.getRect(label).bottom,
              lessThanOrEqualTo(tester.getRect(action).bottom),
            );
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(find.byKey(_dialogKey), findsNothing);
            expect(tester.takeException(), isNull);
          }
          expect(requested, _destinations);
        },
      );
    }
  }

  // Function Name: individual-save test
  // Description: Opens the same dialog when the last outstanding medication is saved individually.
  // Parameters: tester: Widget driver. Returns: Completed route assertions.
  testWidgets('last individual save opens the centered completion dialog', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(_result()));
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_dialogKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final step in [
    AnalysisProgressStep.prescriptionRecognition,
    AnalysisProgressStep.medicationAnalysis,
  ]) {
    for (final config in [
      (size: const Size(390, 1200), scale: 1.0),
      (size: const Size(320, 480), scale: 2.0),
    ]) {
      // Function Name: failure-background test
      // Description: Keeps both safe areas and unused space colored while the last recovery action remains scrollable.
      // Parameters: tester: Widget driver. Returns: Completed background and reachability assertions.
      testWidgets('failure background covers the viewport $step $config', (
        tester,
      ) async {
        _viewport(tester, config.size);
        var homes = 0;
        await tester.pumpWidget(
          _app(
            PrescriptionAnalysisFailureUI(
              message: '',
              userSetting: const UserSetting(language: 'en'),
              failureStep: step,
              onAnalysisRetryRequested:
                  step == AnalysisProgressStep.medicationAnalysis
                  ? _ignore
                  : null,
              onCameraRetryRequested: _ignore,
              onGalleryRetryRequested: _ignore,
              onHomeRequested: () => homes++,
            ),
            scale: config.scale,
            padding: const EdgeInsets.only(top: 24, bottom: 32),
          ),
        );
        expect(
          tester.getRect(find.byType(Scaffold)),
          Offset.zero & config.size,
        );
        await _expectBackground(tester, config.size);
        final home = find.text('Back to Home');
        await tester.ensureVisible(home);
        await tester.pumpAndSettle();
        expect(home.hitTestable(), findsOneWidget);
        final button = find
            .ancestor(of: home, matching: find.byType(OutlinedButton))
            .first;
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(config.size.height - 32),
        );
        await _expectBackground(tester, config.size);
        await tester.tap(home);
        expect(homes, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
