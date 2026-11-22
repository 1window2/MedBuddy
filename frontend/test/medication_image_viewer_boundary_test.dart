import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:medbuddy_frontend/boundaries/medication_image_viewer_boundary.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

const _open = Key('open-viewer');
const _content = Key('medication-image-viewer-content');
const _title = Key('medication-image-viewer-title');
const _heading = Key('medication-image-viewer-heading');
const _photo = Key('medication-image-viewer-photo');
const _close = Key('medication-image-viewer-close');

void main() {
  testWidgets('viewer has a translucent backdrop and transparent surface', (
    tester,
  ) async {
    await _openViewer(tester, _createPhoto());
    final context = tester.element(find.byKey(_photo));
    final route = ModalRoute.of(context)!;
    expect(route.barrierColor!.a, inExclusiveRange(0, 1));
    final headingColor = tester.widget<ColoredBox>(find.byKey(_heading)).color;
    expect(headingColor.a, 1);
    expect(headingColor.computeLuminance(), lessThan(0.05));
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byKey(_content),
                  matching: find.byType(Material),
                )
                .first,
          )
          .type,
      MaterialType.transparency,
    );
    expect(tester.takeException(), isNull);
  });

  for (final point in const [
    Offset(195, 8),
    Offset(195, 836),
    Offset(4, 422),
    Offset(386, 422),
  ]) {
    testWidgets('backdrop tap at $point dismisses', (tester) async {
      bool? result;
      await _openViewer(
        tester,
        _createPhoto(),
        onClosed: (value) => result = value,
      );
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byKey(_photo), findsNothing);
      expect(result, isTrue);
    });
  }

  for (final leftSide in [true, false]) {
    testWidgets('blank portrait side dismisses, left=$leftSide', (
      tester,
    ) async {
      await _openViewer(
        tester,
        _createPhoto(width: 240, height: 1200),
        name: 'A long medication name wider than its portrait photograph',
      );
      final content = tester.getRect(find.byKey(_content));
      final photo = tester.getRect(find.byKey(_photo));
      expect(photo.width, lessThan(content.width));
      final point = Offset(
        leftSide
            ? (content.left + photo.left) / 2
            : (photo.right + content.right) / 2,
        photo.center.dy,
      );
      expect(content.contains(point), isTrue);
      expect(photo.contains(point), isFalse);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byKey(_photo), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('image and title taps do not dismiss', (tester) async {
    await _openViewer(tester, _createPhoto());
    await tester.tap(find.byKey(_photo));
    await tester.pumpAndSettle();
    expect(find.byKey(_photo), findsOneWidget);
    await tester.tap(find.byKey(_title));
    await tester.pumpAndSettle();
    expect(find.byKey(_photo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch zoom and pan stay in the viewer', (tester) async {
    await _openViewer(tester, _createPhoto());
    final center = tester.getCenter(find.byKey(_photo));
    final first = await tester.startGesture(
      center - const Offset(35, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(35, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveBy(const Offset(-35, 0));
    await tester.pump();
    await second.moveBy(const Offset(35, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final transform = find
        .descendant(of: find.byKey(_photo), matching: find.byType(Transform))
        .first;
    final zoomed = tester.widget<Transform>(transform).transform.clone();
    expect(zoomed.getMaxScaleOnAxis(), greaterThan(1));
    await tester.drag(find.byKey(_photo), const Offset(40, 25));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Transform>(transform).transform.storage,
      isNot(equals(zoomed.storage)),
    );
    expect(find.byKey(_photo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(960, 480), Size(480, 960), Size(640, 640)]) {
    testWidgets('title stays immediately above a centered $size photo', (
      tester,
    ) async {
      await _openViewer(
        tester,
        _createPhoto(width: size.width.toInt(), height: size.height.toInt()),
      );
      final title = tester.getRect(find.byKey(_title));
      final heading = tester.getRect(find.byKey(_heading));
      final close = tester.getRect(find.byKey(_close));
      final photo = tester.getRect(find.byKey(_photo));
      final content = tester.getRect(find.byKey(_content));
      expect(photo.top, closeTo(heading.bottom, 0.1));
      expect(title.right, lessThanOrEqualTo(close.left));
      expect(close.center.dy, closeTo(heading.center.dy, 0.1));
      expect(close.right, lessThanOrEqualTo(heading.right));
      expect(content.center.dx, closeTo(195, 0.1));
      expect(content.center.dy, closeTo(422, 0.1));
      expect(photo.size.aspectRatio, closeTo(size.aspectRatio, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    for (final viewport in const [Size(320, 520), Size(640, 320)]) {
      testWidgets('large $language title fits and scrolls at $viewport', (
        tester,
      ) async {
        final name = language == 'en'
            ? List.filled(8, 'Example extended release tablet 500 mg').join(' ')
            : List.filled(
                8,
                '\uC544\uC138\uD2B8\uC544\uBBF8\uB178\uD39C\uC815 500 mg',
              ).join(' ');
        await _openViewer(
          tester,
          _createPhoto(),
          name: name,
          language: language,
          viewport: viewport,
          textScale: 3.5,
        );
        final content = tester.getRect(find.byKey(_content));
        final photo = tester.getRect(find.byKey(_photo));
        final heading = tester.getRect(find.byKey(_heading));
        expect(content.left, greaterThanOrEqualTo(0));
        expect(content.right, lessThanOrEqualTo(viewport.width));
        expect(content.top, greaterThanOrEqualTo(64));
        expect(content.bottom, lessThanOrEqualTo(viewport.height - 64));
        expect(photo.height, greaterThan(50));
        expect(photo.top, closeTo(heading.bottom, 0.1));
        expect(find.byKey(_close).hitTestable(), findsOneWidget);
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(_title),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.drag(find.byKey(_title), const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(find.byKey(_photo), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(find.byKey(_photo), findsNothing);
      });
    }

    testWidgets('localized close button works for $language', (tester) async {
      await _openViewer(tester, _createPhoto(), language: language);
      expect(
        tester.widget<IconButton>(find.byKey(_close)).tooltip,
        language == 'en'
            ? 'Close enlarged image'
            : '\uD655\uB300 \uC0AC\uC9C4 \uB2EB\uAE30',
      );
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byKey(_photo), findsNothing);
    });
  }

  testWidgets('system back closes the viewer', (tester) async {
    await _openViewer(tester, _createPhoto());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_photo), findsNothing);
  });

  testWidgets('failed photo stays dismissible without leaking errors', (
    tester,
  ) async {
    final file = _createPhoto(corrupt: true);
    await _openViewer(tester, file, preload: false);
    // Let the already-mounted FileImage report its failure; resolving the same
    // failed stream a second time inside runAsync can wait for a fake frame.
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      if (find
          .byIcon(Icons.image_not_supported_outlined)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    await tester.tap(find.byKey(_photo));
    await tester.pumpAndSettle();
    expect(find.byKey(_photo), findsOneWidget);
    await tester.tapAt(const Offset(195, 836));
    await tester.pumpAndSettle();
    expect(find.byKey(_photo), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

File _createPhoto({int width = 960, int height = 480, bool corrupt = false}) {
  final directory = Directory.systemTemp.createTempSync('medbuddy-viewer-');
  final file = File('${directory.path}/photo.png');
  file.writeAsBytesSync(
    corrupt
        ? [0, 1, 2]
        : img.encodePng(img.Image(width: width, height: height)),
  );
  addTearDown(() {
    imageCache.evict(FileImage(file));
    if (file.existsSync()) file.deleteSync();
    if (directory.existsSync()) directory.deleteSync();
  });
  return file;
}

Future<void> _openViewer(
  WidgetTester tester,
  File photo, {
  String name = 'Example tablet 2.5 mg',
  String language = 'en',
  Size viewport = const Size(390, 844),
  double textScale = 1,
  bool preload = true,
  ValueChanged<bool>? onClosed,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: _open,
              onPressed: () async {
                final result = await MedicationImageViewer.show(
                  context,
                  medicationName: name,
                  localImagePath: photo.path,
                  language: language,
                );
                onClosed?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  if (preload) {
    await tester.runAsync(
      () => precacheImage(FileImage(photo), tester.element(find.byKey(_open))),
    );
  }
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
}
