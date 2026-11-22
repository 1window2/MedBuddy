// 파일명: manual_medication_review_handoff_test.dart
// 역할: 직접 등록의 검토 인계, 사진 소유권과 기존 저장 경로를 독립적으로 검증한다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_search_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _saved = MedicationSaveResult(
  status: MedicationSaveStatus.saved,
  message: '',
);
const _catalogMedication = MedicationDetail(
  itemSeq: 'review-catalog-id',
  itemName: 'Catalog medication',
  manufacturer: 'Catalog manufacturer',
  efficacy: 'Catalog efficacy',
  usageMethod: 'Catalog usage',
  warning: 'Catalog warning',
);

class _PhotoPicker extends ImagePicker {
  String? path;
  Completer<XFile?>? pending;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => pending != null
      ? await pending!.future
      : path == null
      ? null
      : XFile(path!);
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;
  int lookups = 0;

  @override
  Future<String?> getTemporaryPath() async {
    lookups++;
    return path;
  }
}

class _Photos {
  _Photos() {
    final original = PathProviderPlatform.instance;
    provider = _TemporaryPathProvider(directory.path);
    PathProviderPlatform.instance = provider;
    addTearDown(() async {
      PathProviderPlatform.instance = original;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      // Windows에서 이미지 디코더의 파일 해제가 늦어질 수 있다.
      for (var attempt = 0; ; attempt++) {
        try {
          await directory.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt >= 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }

  final directory = Directory.systemTemp.createTempSync('manual-review-');
  late final _TemporaryPathProvider provider;

  File create(String name) => File('${directory.path}/$name.png')
    ..writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
}

Finder _field(String suffix, [int index = 0]) =>
    find.byKey(Key('manual-medication-$suffix')).at(index);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(
  WidgetTester tester,
  String suffix,
  String value, [
  int index = 0,
]) async {
  await tester.ensureVisible(_field(suffix, index));
  await tester.enterText(_field(suffix, index), value);
  await tester.pumpAndSettle();
}

Future<void> _pickPhoto(WidgetTester tester, [int index = 0]) async {
  await _tap(tester, _field('photo', index));
  await _tap(tester, find.text('카메라로 촬영'));
  await _settlePhotoIO(tester);
}

// 실제 파일 삭제가 가상 프레임 시계와 별개로 완료될 때까지 기다린다.
Future<void> _waitForDeletion(WidgetTester tester, File photo) async {
  final elapsed = Stopwatch()..start();
  while (photo.existsSync() && elapsed.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(photo.existsSync(), isFalse);
}

Future<void> _settlePhotoIO(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<GlobalKey<NavigatorState>> _mount(
  WidgetTester tester, {
  bool Function(List<ManualMedicationEntry>)? review,
  Future<MedicationSaveResult> Function(ManualMedicationEntry)? save,
  Future<void> Function()? refresh,
  ImagePicker? picker,
  String language = 'ko',
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var unexpectedSaves = 0;
  var unexpectedRefreshes = 0;
  addTearDown(() {
    expect(unexpectedSaves, 0, reason: 'Review must not persist entries');
    expect(
      unexpectedRefreshes,
      0,
      reason: 'Review must not refresh saved data',
    );
  });
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: Text('Origin')),
    ),
  );
  unawaited(
    navigator.currentState!.push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualMedicationEntryUI(
          userSetting: UserSetting(language: language),
          imagePicker: picker,
          onReviewRequested: review,
          onSaveRequested:
              save ??
              (_) async {
                unexpectedSaves++;
                return _saved;
              },
          onSavesFinished:
              refresh ??
              () async {
                unexpectedRefreshes++;
              },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  testWidgets('validates every pending form before one batch review', (
    tester,
  ) async {
    final requests = <List<ManualMedicationEntry>>[];
    await _mount(
      tester,
      review: (entries) {
        requests.add(entries);
        return false;
      },
    );
    await _enter(tester, 'dosage', '0');
    await _tap(tester, _field('add'));
    await _tap(tester, _field('dose-days-custom', 1));
    await _enter(tester, 'interval', '0');
    await _tap(tester, _field('slot-morning', 1));
    await _tap(tester, _field('save'));

    expect(requests, isEmpty);
    expect(find.text('약 이름을 입력해주세요.'), findsNWidgets(2));
    expect(find.text('0보다 큰 올바른 복용량을 입력해주세요.'), findsOneWidget);
    expect(find.text('1~90 사이의 일수를 입력해주세요.'), findsOneWidget);
    expect(find.text('복용 시간대를 한 개 이상 선택해주세요.'), findsOneWidget);

    await _enter(tester, 'name', 'First');
    await _enter(tester, 'dosage', '1');
    await _enter(tester, 'name', 'Second', 1);
    await _enter(tester, 'interval', '3');
    await _tap(tester, _field('slot-evening', 1));
    await _tap(tester, _field('save'));
    expect(requests, hasLength(1));
    expect(requests.single.map((entry) => entry.medicationName), [
      'First',
      'Second',
    ]);
    expect(find.byType(ManualMedicationEntryUI), findsOneWidget);
    expect(find.text('복약 정보를 저장했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review snapshots all catalog, schedule and photo fields', (
    tester,
  ) async {
    final photos = _Photos();
    final first = photos.create('first');
    final second = photos.create('second');
    final picker = _PhotoPicker()..path = first.path;
    List<ManualMedicationEntry>? reviewed;
    final navigator = await _mount(
      tester,
      picker: picker,
      review: (entries) {
        reviewed = entries;
        return true;
      },
    );
    await _tap(tester, _field('search'));
    expect(find.byType(MedicationSearchUI), findsOneWidget);
    navigator.currentState!.pop(_catalogMedication);
    await tester.pumpAndSettle();
    await _enter(tester, 'dosage', '0.5');
    await _tap(tester, _field('unit'));
    await _tap(tester, find.text('캡슐').last);
    await _pickPhoto(tester);

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1);
    final end = DateTime(now.year, now.month, now.day + 8);
    await _tap(tester, _field('start-date'));
    navigator.currentState!.pop(start);
    await tester.pumpAndSettle();
    await _tap(tester, _field('end-date'));
    navigator.currentState!.pop(end);
    await tester.pumpAndSettle();
    await _tap(tester, _field('dose-days-custom'));
    await _enter(tester, 'interval', '3');
    await _tap(tester, _field('slot-morning'));
    await _tap(tester, _field('slot-lunch'));
    await _tap(tester, _field('slot-bedtime'));

    await _tap(tester, _field('add'));
    await _enter(tester, 'name', '  Second medication  ', 1);
    await _enter(tester, 'dosage', '2', 1);
    picker.path = second.path;
    await _pickPhoto(tester, 1);
    await _tap(tester, _field('dose-days-custom', 1));
    await _enter(tester, 'interval', '0', 1);
    await _tap(tester, _field('as-needed', 1));
    final removePhoto = tester
        .widget<IconButton>(_field('remove-photo'))
        .onPressed!;
    await tester.tap(_field('save'));
    await tester.pump();
    removePhoto();
    await tester.pump();

    expect(reviewed, hasLength(2));
    final scheduled = reviewed![0];
    expect(scheduled.catalogMedication, same(_catalogMedication));
    expect(scheduled.medicationName, _catalogMedication.itemName);
    expect(scheduled.dosageAmount, '0.5');
    expect(scheduled.dosageUnit, '캡슐');
    expect(scheduled.startDate, start);
    expect(scheduled.endDate, end);
    expect(scheduled.scheduleSlotKeys, ['lunch', 'bedtime']);
    expect(scheduled.doseDays, '3일마다');
    expect(scheduled.dosingMode, 'scheduled');
    expect(scheduled.localImagePath, first.path);
    final asNeeded = reviewed![1];
    expect(asNeeded.catalogMedication, isNull);
    expect(asNeeded.medicationName, 'Second medication');
    expect(asNeeded.dosageAmount, '2');
    expect(asNeeded.dosageUnit, '정');
    expect(asNeeded.dosingMode, 'as_needed');
    expect(asNeeded.doseDays, isEmpty);
    expect(asNeeded.toMedicationSchedule().scheduleSlotKeys, isEmpty);
    expect(asNeeded.localImagePath, second.path);
    expect(() => reviewed!.clear(), throwsUnsupportedError);
    expect(tester.widget<TextFormField>(_field('name')).enabled, isFalse);
    expect(tester.widget<IconButton>(_field('remove-photo')).onPressed, isNull);

    // 인계가 성공해도 이 화면 자체는 저장하거나 경로를 닫지 않는다.
    expect(find.byType(ManualMedicationEntryUI), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await _settlePhotoIO(tester);
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
    expect(photos.provider.lookups, 0);
    expect(find.text('Origin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('review copy and double-tap lock use $language at large text', (
      tester,
    ) async {
      var calls = 0;
      late VoidCallback request;
      final navigator = await _mount(
        tester,
        language: language,
        width: 320,
        textScale: 2,
        review: (_) {
          calls++;
          request();
          return true;
        },
      );
      expect(
        find.text(language == 'ko' ? '복약 정보 확인' : 'Review medications'),
        findsOneWidget,
      );
      await _enter(tester, 'name', 'Review only');
      request = tester.widget<FilledButton>(_field('save')).onPressed!;
      await tester.tap(_field('save'));
      await tester.tap(_field('save'));
      await tester.pump();
      request();
      await tester.pump();
      expect(calls, 1);
      expect(
        find.text(language == 'ko' ? '확인 중...' : 'Reviewing...'),
        findsOneWidget,
      );
      expect(
        find.text(language == 'ko' ? '저장 중...' : 'Saving...'),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(_field('save')).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_field('add')).onPressed, isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      request();
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Origin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final throws in [false, true]) {
    testWidgets('rejected review restores editing and photo cleanup: $throws', (
      tester,
    ) async {
      final photos = _Photos();
      final first = photos.create('first');
      final second = photos.create('second');
      final replacement = photos.create('replacement');
      final picker = _PhotoPicker()..path = first.path;
      final requests = <List<ManualMedicationEntry>>[];
      final navigator = await _mount(
        tester,
        picker: picker,
        review: (entries) {
          requests.add(entries);
          if (throws) throw StateError('Review unavailable');
          return false;
        },
      );
      await _enter(tester, 'name', 'First');
      await _pickPhoto(tester);
      await _tap(tester, _field('add'));
      await _enter(tester, 'name', 'Second', 1);
      picker.path = second.path;
      await _pickPhoto(tester, 1);
      await _tap(tester, _field('save'));
      expect(requests, hasLength(1));
      expect(tester.widget<FilledButton>(_field('save')).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(_field('add')).onPressed, isNotNull);
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);
      expect(photos.provider.lookups, 0);

      await _enter(tester, 'name', 'Edited first');
      await _tap(tester, _field('slot-evening'));
      await _tap(tester, _field('remove-photo'));
      await _waitForDeletion(tester, first);
      picker.path = replacement.path;
      await _pickPhoto(tester);
      await _tap(tester, _field('save'));
      expect(requests, hasLength(2));
      expect(requests[0][0].medicationName, 'First');
      expect(requests[0][0].scheduleSlotKeys, ['morning']);
      expect(requests[0][0].localImagePath, first.path);
      expect(requests[1][0].medicationName, 'Edited first');
      expect(requests[1][0].scheduleSlotKeys, ['morning', 'evening']);
      expect(requests[1][0].localImagePath, replacement.path);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await _waitForDeletion(tester, replacement);
      await _waitForDeletion(tester, second);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retry after rejection can hand off and parent owns navigation', (
    tester,
  ) async {
    final photos = _Photos();
    final photo = photos.create('accepted');
    final picker = _PhotoPicker()..path = photo.path;
    var calls = 0;
    late GlobalKey<NavigatorState> navigator;
    navigator = await _mount(
      tester,
      picker: picker,
      review: (_) {
        if (++calls == 1) return false;
        unawaited(
          navigator.currentState!.pushReplacement<void, bool>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Shared result')),
            ),
          ),
        );
        return true;
      },
    );
    await _enter(tester, 'name', 'Review medication');
    await _pickPhoto(tester);
    await _tap(tester, _field('save'));
    expect(calls, 1);
    final request = tester.widget<FilledButton>(_field('save')).onPressed!;
    request();
    request();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    request();
    await tester.pumpAndSettle();
    await _settlePhotoIO(tester);
    expect(calls, 2);
    expect(find.byType(ManualMedicationEntryUI), findsNothing);
    expect(find.text('Shared result'), findsOneWidget);
    expect(photo.existsSync(), isTrue);
    expect(photos.provider.lookups, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Origin'), findsOneWidget);
    expect(photo.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back before review blocks stale callbacks and deletes photo', (
    tester,
  ) async {
    final photos = _Photos();
    final photo = photos.create('abandoned');
    var calls = 0;
    final navigator = await _mount(
      tester,
      picker: _PhotoPicker()..path = photo.path,
      review: (_) {
        calls++;
        return true;
      },
    );
    await _enter(tester, 'name', 'Abandoned medication');
    await _pickPhoto(tester);
    final request = tester.widget<FilledButton>(_field('save')).onPressed!;
    navigator.currentState!.pop();
    request();
    await tester.pumpAndSettle();
    request();
    await _waitForDeletion(tester, photo);
    expect(calls, 0);
    expect(find.text('Origin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets(
      'closing inside a rejected callback still cleans photos: $throws',
      (tester) async {
        final photos = _Photos();
        final photo = photos.create('rejected-on-close');
        late GlobalKey<NavigatorState> navigator;
        var calls = 0;
        navigator = await _mount(
          tester,
          picker: _PhotoPicker()..path = photo.path,
          review: (_) {
            calls++;
            navigator.currentState!.pop();
            if (throws) throw StateError('Review unavailable');
            return false;
          },
        );
        await _enter(tester, 'name', 'Rejected medication');
        await _pickPhoto(tester);
        final request = tester.widget<FilledButton>(_field('save')).onPressed!;
        request();
        request();
        await tester.pumpAndSettle();
        await _waitForDeletion(tester, photo);
        expect(calls, 1);
        expect(find.text('Origin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('review is blocked by another route or pending photo picker', (
    tester,
  ) async {
    final picker = _PhotoPicker()..pending = Completer<XFile?>();
    var calls = 0;
    final navigator = await _mount(
      tester,
      picker: picker,
      review: (_) {
        calls++;
        return false;
      },
    );
    await _enter(tester, 'name', 'Not ready');
    final request = tester.widget<FilledButton>(_field('save')).onPressed!;
    await _tap(tester, _field('search'));
    request();
    await tester.pump();
    expect(calls, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await _pickPhoto(tester);
    expect(tester.widget<FilledButton>(_field('save')).onPressed, isNull);
    request();
    await tester.pump();
    expect(calls, 0);
    picker.pending!.complete(null);
    await tester.pumpAndSettle();
    await _tap(tester, _field('save'));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'without review callback batch save, refresh and cleanup remain',
    (tester) async {
      final photos = _Photos();
      final photo = photos.create('saved');
      final events = <String>[];
      final entries = <ManualMedicationEntry>[];
      await _mount(
        tester,
        picker: _PhotoPicker()..path = photo.path,
        save: (entry) async {
          entries.add(entry);
          events.add(entry.medicationName);
          return _saved;
        },
        refresh: () async => events.add('refresh'),
      );
      expect(find.text('복약 정보 저장'), findsOneWidget);
      await _enter(tester, 'name', 'First');
      await _enter(tester, 'dosage', '0.5');
      await _tap(tester, _field('dose-days-격일'));
      await _pickPhoto(tester);
      await _tap(tester, _field('add'));
      expect(find.text('전체 복약 정보 저장'), findsOneWidget);
      await _enter(tester, 'name', 'Second', 1);
      final request = tester.widget<FilledButton>(_field('save')).onPressed!;
      request();
      request();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(events, ['First', 'Second', 'refresh']);
      expect(entries[0].localImagePath, photo.path);
      expect(entries[0].dosageAmount, '0.5');
      expect(entries[0].doseDays, '격일');
      expect(entries[0].scheduleSlotKeys, ['morning']);
      expect(entries[1].localImagePath, isEmpty);
      expect(find.byType(ManualMedicationEntryUI), findsNothing);
      expect(find.text('Origin'), findsOneWidget);
      await _waitForDeletion(tester, photo);
      expect(tester.takeException(), isNull);
    },
  );
}
