// File Name: dose_home_widget_settings_test.dart
// Role: Checks size selection and pin routing through the real settings screen without device data.
import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Class Name: _SettingsWidgetPlatform
// Role: Publishes to an empty encrypted fixture while the method-channel mock records pin requests.
// Attributes: store: In-memory fixture; available: Platform capability.
class _SettingsWidgetPlatform extends DoseHomeWidgetPlatform {
  _SettingsWidgetPlatform(this.store);
  final DoseOutboxStore store;
  bool available = true;

  @override
  bool get supported => available;
  @override
  Future<DoseOutboxStore> openStore() async => store;
  @override
  Future<String?> readJournal() async => '[]';
  @override
  Future<void> saveState(String state) async {}
  @override
  Future<void> updateWidget() async {}
}

// Function Name: main
// Description: Exercises localized size selection, cancellation, pin defaults and unsupported-device visibility.
// Parameters: None. Returns: No value; all storage is disposable in-memory fixture data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('home_widget');
  const previewChannel = MethodChannel('com.medbuddy.app/settings');
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  late Database db;
  late _SettingsWidgetPlatform platform;
  late Completer<String> pinned;
  var pinSupported = true;
  var failPreviews = false;
  final previewCalls = <MethodCall>[];

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    platform = _SettingsWidgetPlatform(
      DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey()),
    );
    DoseHomeWidget.platform = platform;
    pinned = Completer<String>();
    pinSupported = true;
    failPreviews = false;
    previewCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(previewChannel, (call) async {
          previewCalls.add(call);
          if (failPreviews) throw PlatformException(code: 'preview_failed');
          return {'compact': image, 'expanded': image};
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isRequestPinWidgetSupported') return pinSupported;
          if (call.method == 'requestPinWidget') {
            pinned.complete(
              (call.arguments as Map)['qualifiedAndroidName'] as String,
            );
          }
          return true;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(previewChannel, null);
    DoseHomeWidget.resetForTest();
    await db.close();
  });

  // Function Name: pumpSettings
  // Description: Opens the home-widget section with localized labels and a no-write save callback.
  // Parameters: tester: UI driver; language: Display language; fontSize: App text size.
  // Returns: Completion after the initial section scroll settles.
  Future<void> pumpSettings(
    WidgetTester tester,
    String language, {
    int fontSize = 17,
  }) async {
    final auth = AuthenticationControl.development();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: UserSetting(
            language: language,
            languageMode: language,
            fontSize: fontSize,
          ),
          initialDestination: UserSettingDestination.homeWidget,
          authenticationControl: auth,
          onExtendedSettingSaveRequested: (_) async =>
              throw StateError('Pinning must not save account settings'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final add = find.byKey(const ValueKey('addDoseHomeWidget'));
  final selector = find.byKey(const ValueKey('doseHomeWidgetSizeSelector'));
  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 430.0]) {
      testWidgets(
        '4x3 pin selection fits $language at $width with large text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpSettings(tester, language, fontSize: 23);
          expect(selector, findsNothing);
          expect(
            find.text(language == 'en' ? 'Widget size' : '위젯 크기'),
            findsNothing,
          );
          await tester.ensureVisible(add);
          await tester.runAsync(() => tester.tap(add));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('dose-widget-preview-compact')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('dose-widget-preview-expanded')),
            findsOneWidget,
          );
          expect(previewCalls.single.arguments, {'language': language});
          expect(find.byType(RadioListTile<String>), findsNothing);
          expect(pinned.isCompleted, isFalse);
          await tester.runAsync(() async {
            await tester.ensureVisible(
              find.byKey(const ValueKey('doseHomeWidgetSize-expanded')),
            );
            await tester.tap(
              find.byKey(const ValueKey('doseHomeWidgetSize-expanded')),
            );
            await tester.pumpAndSettle();
            expect(
              await pinned.future.timeout(const Duration(seconds: 5)),
              DoseHomeWidget.expandedProvider,
            );
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('dismissed add picker does not pin; next choice can add 4x1', (
    tester,
  ) async {
    await pumpSettings(tester, 'en');
    await tester.ensureVisible(add);
    await tester.runAsync(() => tester.tap(add));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tapAt(const Offset(10, 10));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(pinned.isCompleted, isFalse);
    await tester.ensureVisible(add);
    await tester.runAsync(() => tester.tap(add));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(const ValueKey('doseHomeWidgetSize-compact')),
      );
      await tester.pumpAndSettle();
      expect(
        await pinned.future.timeout(const Duration(seconds: 5)),
        DoseHomeWidget.provider,
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported launcher keeps the existing manual-add guidance', (
    tester,
  ) async {
    pinSupported = false;
    await pumpSettings(tester, 'en');
    await tester.ensureVisible(add);
    await tester.runAsync(() => tester.tap(add));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(const ValueKey('doseHomeWidgetSize-compact')),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(
      find.text('Add MedBuddy from your home screen widget list.'),
      findsOneWidget,
    );
    expect(pinned.isCompleted, isFalse);
  });

  testWidgets('unsupported platform hides both size and add controls', (
    tester,
  ) async {
    platform.available = false;
    await pumpSettings(tester, 'en');
    expect(add, findsNothing);
    expect(selector, findsNothing);
  });

  testWidgets('preview failure can retry without pinning or writing settings', (
    tester,
  ) async {
    failPreviews = true;
    await pumpSettings(tester, 'ko');
    await tester.ensureVisible(add);
    await tester.runAsync(() => tester.tap(add));
    await tester.pumpAndSettle();
    final retry = find.byKey(const Key('retry-widget-previews'));
    await tester.ensureVisible(retry);
    expect(find.text('미리보기를 불러오지 못했습니다.'), findsOneWidget);
    expect(pinned.isCompleted, isFalse);
    failPreviews = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dose-widget-preview-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dose-widget-preview-expanded')),
      findsOneWidget,
    );
    expect(previewCalls, hasLength(2));
    expect(pinned.isCompleted, isFalse);
    expect(tester.takeException(), isNull);
  });
}
