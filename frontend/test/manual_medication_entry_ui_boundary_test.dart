// 파일명: manual_medication_entry_ui_boundary_test.dart
// 역할: 복약정보 직접 등록 화면의 입력 검증, 사진 선택과 저장 흐름을 검증한다. 직접 등록 화면의 필수 입력 검증과 저장 요청 구성을 확인한다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// 클래스명: _PhotoPicker
// 역할: 실제 카메라·갤러리 없이 사진 선택값과 요청 옵션을 검증한다.
class _PhotoPicker extends ImagePicker {
  String? path;
  ImageSource? source;
  Object? failure;

  // 함수이름: pickImage
  // 함수역할: 사진 요청 옵션을 확인하고 준비된 경로 또는 취소를 반환한다. failure가 있으면 그 예외를 던진다.
  // 매개변수: source, maxWidth, maxHeight, imageQuality, preferredCameraDevice,
  // requestFullMetadata: 이미지 선택기의 원래 요청 옵션.
  // 반환값: 선택 사진 또는 null.
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    expect(imageQuality, 88);
    expect(maxWidth, 1800);
    expect(maxHeight, 1800);
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return path == null ? null : XFile(path!);
  }
}

// 클래스명: _TemporaryPathProvider
// 역할: 테스트 폴더를 앱 임시 폴더로 알려 임시 사본 삭제를 플랫폼 채널 없이 검증한다.
class _TemporaryPathProvider extends PathProviderPlatform {
  final String temporaryPath;

  // 함수이름: _TemporaryPathProvider
  // 함수역할: 앱 임시 폴더로 알릴 경로를 보관한다. 매개변수: temporaryPath. 반환값: 초기화된 대역.
  _TemporaryPathProvider(this.temporaryPath);

  // 함수이름: getTemporaryPath
  // 함수역할: 보관한 경로를 앱 임시 폴더로 돌려준다. 매개변수: 없음. 반환값: 임시 폴더 경로.
  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

// 클래스명: _PhotoSandbox
// 역할: 앱 임시 폴더와 사용자 사진 폴더 역할의 테스트 폴더, 그 안의 사진 파일을 준비한다.
class _PhotoSandbox {
  static final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  final Directory cache;
  final Directory gallery;

  // 함수이름: _PhotoSandbox._
  // 함수역할: 준비된 두 폴더를 보관한다. 매개변수: cache, gallery. 반환값: 초기화된 인스턴스.
  _PhotoSandbox._(this.cache, this.gallery);

  // 함수이름: _PhotoSandbox.create
  // 함수역할: 테스트 폴더를 만들고 경로 제공자를 바꾼 뒤 테스트 종료 시 되돌리도록 등록한다.
  // 매개변수: 없음. 반환값: 임시 폴더와 사진 폴더를 가진 인스턴스.
  factory _PhotoSandbox.create() {
    final root = Directory.systemTemp.createTempSync('manual-photo-cleanup-');
    final cache = Directory('${root.path}/cache')..createSync();
    final gallery = Directory('${root.path}/gallery')..createSync();
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(cache.path);
    addTearDown(() {
      PathProviderPlatform.instance = originalProvider;
      root.deleteSync(recursive: true);
    });
    return _PhotoSandbox._(cache, gallery);
  }

  // 함수이름: cachePhoto
  // 함수역할: 앱 임시 폴더에 선택기 사본 역할의 사진을 만든다. 매개변수: name. 반환값: 만든 파일.
  File cachePhoto(String name) =>
      File('${cache.path}/$name')..writeAsBytesSync(_png);

  // 함수이름: galleryPhoto
  // 함수역할: 앱 임시 폴더 밖에 사용자 원본 역할의 사진을 만든다. 매개변수: name. 반환값: 만든 파일.
  File galleryPhoto(String name) =>
      File('${gallery.path}/$name')..writeAsBytesSync(_png);
}

// 함수이름: _settleFileCleanup
// 함수역할: 기다리지 않고 시작된 임시 사본 삭제가 실제 파일 입출력을 마칠 시간을 준다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - file (File?): 삭제를 기다릴 파일. null이면 정해진 횟수만큼만 기다린다.
// 반환값:
// - 파일이 없어졌거나 대기 횟수를 모두 쓴 뒤 완료.
Future<void> _settleFileCleanup(WidgetTester tester, [File? file]) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if (file != null && !file.existsSync()) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

// 함수이름: _pickManualPhoto
// 함수역할: 사진 추가를 눌러 카메라 출처를 고르고 선택 결과가 화면에 반영되기를 기다린다.
// 매개변수: tester (WidgetTester): 위젯 테스트 제어기. 반환값: 선택 반영 완료.
Future<void> _pickManualPhoto(WidgetTester tester) async {
  final photo = find.byKey(const Key('manual-medication-photo'));
  await tester.ensureVisible(photo);
  await tester.pumpAndSettle();
  await tester.tap(photo);
  await tester.pumpAndSettle();
  await tester.tap(find.text('카메라로 촬영'));
  await tester.pumpAndSettle();
}

// 함수이름: _keepManualEntryOpen
// 함수역할: 화면 검증 중 저장 화면을 닫지 않는다.
// 매개변수: entry (ManualMedicationEntry): 저장 요청. 반환값: 고정 실패 결과.
Future<MedicationSaveResult> _keepManualEntryOpen(
  ManualMedicationEntry entry,
) async => const MedicationSaveResult(
  status: MedicationSaveStatus.failed,
  message: '테스트 저장 중단',
);

// 함수이름: main
// 함수역할:
// - 약 직접 등록 검증, 저장 데이터와 복용 단위 번역 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  for (final language in ['ko', 'en']) {
    // 함수이름: 필수 입력 순서·큰 글씨 테스트
    // 함수역할: 작은 화면에서 이름·복용량이 선택 사진보다 먼저 오고 안전 문구가 유지된다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('required fields precede compact photo at 2x in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          // 함수이름: builder 콜백
          // 함수역할: 글씨 배율을 두 배로 고정한다. 매개변수: context, child. 반환값: 접근성 화면.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ManualMedicationEntryUI(
            userSetting: UserSetting(language: language),
            onSaveRequested: _keepManualEntryOpen,
          ),
        ),
      );
      final name = find.byKey(const Key('manual-medication-name'));
      final dose = find.byKey(const Key('manual-medication-dosage'));
      final photo = find.byKey(const Key('manual-medication-photo'));
      expect(tester.getTopLeft(name).dy, lessThan(tester.getTopLeft(dose).dy));
      expect(
        tester.getBottomLeft(dose).dy,
        lessThan(tester.getTopLeft(photo).dy),
      );
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(photo).height, 48);
      expect(
        find.text(
          language == 'ko'
              ? '약 봉투나 복약 안내에 적힌 내용을 기준으로 입력해주세요. 확실하지 않은 내용은 임의로 입력하지 마세요.'
              : 'Use the medication label or instructions. Do not guess uncertain information.',
        ),
        findsOneWidget,
      );
      final title = tester.widget<Text>(
        find.text(language == 'ko' ? '약 직접 등록' : 'Add Medication'),
      );
      expect(title.style!.fontSize, 21);
      expect(title.style!.fontWeight, FontWeight.w700);
      await tester.ensureVisible(photo);
      await tester.pumpAndSettle();
      expect(photo.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('manual-medication-save')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // 함수이름: 사진 선택·취소·삭제 테스트
    // 함수역할: 공통 선택창의 번역·갤러리·카메라와 선택 후에만 나타나는 미리보기를 검증한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets(
      'photo expands only after selection and can be removed in $language',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'manual-photo-test-',
        );
        final file = File('${directory.path}/pill.png')
          ..writeAsBytesSync(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          );
        // 함수이름: 사진 정리 콜백
        // 함수역할: 테스트 전용 임시 사진만 제거한다. 매개변수: 없음. 반환값: 없음.
        addTearDown(() => directory.deleteSync(recursive: true));
        final picker = _PhotoPicker();
        await tester.pumpWidget(
          MaterialApp(
            home: ManualMedicationEntryUI(
              userSetting: UserSetting(language: language),
              imagePicker: picker,
              onSaveRequested: _keepManualEntryOpen,
            ),
          ),
        );
        final photo = find.byKey(const Key('manual-medication-photo'));
        await tester.ensureVisible(photo);
        await tester.tap(photo);
        await tester.pumpAndSettle();
        final cameraLabel = language == 'ko' ? '카메라로 촬영' : 'Take Photo';
        final galleryLabel = language == 'ko'
            ? '갤러리에서 선택'
            : 'Choose From Gallery';
        expect(find.text(cameraLabel), findsOneWidget);
        expect(find.text(galleryLabel), findsOneWidget);
        await tester.tap(find.text(galleryLabel));
        await tester.pumpAndSettle();
        expect(picker.source, ImageSource.gallery);
        expect(find.byType(Image), findsNothing);
        picker.path = file.path;
        await tester.tap(photo);
        await tester.pumpAndSettle();
        await tester.tap(find.text(cameraLabel));
        await tester.pumpAndSettle();
        expect(picker.source, ImageSource.camera);
        expect(find.byType(Image), findsOneWidget);
        final preview = tester.widget<Image>(find.byType(Image));
        expect(preview.height, 140);
        expect(preview.fit, BoxFit.contain);
        // 140dp 미리보기 높이에 화면 배율을 곱한 크기까지만 디코딩한다.
        expect(
          preview.image,
          isA<ResizeImage>().having(
            // 함수이름: having 콜백
            // 함수역할: 디코딩 높이 제한을 꺼낸다. 매개변수: image. 반환값: 제한 높이.
            (image) => image.height,
            'height',
            (140 * tester.view.devicePixelRatio).round(),
          ),
        );
        final remove = find.byKey(const Key('manual-medication-remove-photo'));
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        expect(remove, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 약 이름이 없으면 직접 등록 저장 요청을 보내지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('약 이름이 없으면 직접 등록 저장 요청을 보내지 않는다', (tester) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 직접 등록 저장 호출 횟수를 기록하고 저장 성공 결과를 제공한다.
          // 매개변수:
          // - entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - saved 상태의 MedicationSaveResult.
          onSaveRequested: (entry) async {
            requestCount += 1;
            return const MedicationSaveResult(
              status: MedicationSaveStatus.saved,
              message: '저장됨',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('manual-medication-save')));
    await tester.pump();

    expect(find.text('약 이름을 입력해주세요.'), findsOneWidget);
    expect(requestCount, 0);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 입력한 약 이름과 복용 정보를 기존 저장 요청 값으로 전달한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('입력한 약 이름과 복용 정보를 기존 저장 요청 값으로 전달한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ManualMedicationEntry? submittedEntry;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 사용자가 입력한 직접 등록 데이터를 보관하고 실패 결과로 화면을 유지한다.
          // 매개변수:
          // - entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값.
          // 반환값:
          // - failed 상태와 테스트 중단 메시지를 가진 저장 결과.
          onSaveRequested: (entry) async {
            submittedEntry = entry;
            return const MedicationSaveResult(
              status: MedicationSaveStatus.failed,
              message: '테스트 저장 중단',
            );
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '직접입력약',
    );
    await tester.enterText(
      find.byKey(const Key('manual-medication-dosage')),
      '0.5',
    );
    final eveningSlot = find.byKey(const Key('manual-medication-slot-evening'));
    await tester.ensureVisible(eveningSlot);
    await tester.pumpAndSettle();
    await tester.tap(eveningSlot);
    await tester.ensureVisible(find.byKey(const Key('manual-medication-save')));
    await tester.tap(find.byKey(const Key('manual-medication-save')));
    await tester.pumpAndSettle();

    expect(submittedEntry, isNotNull);
    expect(submittedEntry!.medicationName, '직접입력약');
    expect(submittedEntry!.dosageAmount, '0.5');
    expect(submittedEntry!.dosageUnit, '정');
    expect(
      submittedEntry!.scheduleSlotKeys,
      containsAll(['morning', 'evening']),
    );
    expect(find.text('테스트 저장 중단'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영어 설정은 단위 선택 문구만 번역하고 저장 값은 유지한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영어 설정은 단위 선택 문구만 번역하고 저장 값은 유지한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'en'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 단위 표시 번역 검사를 위한 직접 등록 저장 성공을 제공한다.
          // 매개변수:
          // - _ (ManualMedicationEntry): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
          // 반환값:
          // - saved 상태의 MedicationSaveResult.
          onSaveRequested: (_) async => const MedicationSaveResult(
            status: MedicationSaveStatus.saved,
            message: 'saved',
          ),
        ),
      ),
    );

    expect(find.text('Add Medication'), findsOneWidget);
    expect(find.text('Tablet'), findsOneWidget);
    expect(find.text('정'), findsNothing);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 사진 선택 실패 안내 테스트
    // 함수역할: 카메라 접근 거부처럼 선택기가 예외를 내면 처리되지 않은 오류 없이 안내를 표시하는지 검증한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('사진 선택기가 실패하면 오류 안내를 표시한다 $language', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = _PhotoPicker()
        ..failure = PlatformException(code: 'camera_access_denied');
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMedicationEntryUI(
            userSetting: UserSetting(language: language),
            imagePicker: picker,
            onSaveRequested: _keepManualEntryOpen,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('manual-medication-photo')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(language == 'ko' ? '카메라로 촬영' : 'Take Photo'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          language == 'ko'
              ? '사진을 불러오지 못했습니다. 카메라와 사진 접근 권한을 확인한 뒤 다시 시도해주세요.'
              : 'Could not load the photo. Check camera and photo access, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('manual-medication-photo')))
            .onPressed,
        isNotNull,
      );
    });
  }

  // 함수이름: 저장 콜백 예외 테스트
  // 함수역할: 저장 콜백이 예외로 끝나도 저장 중 상태에 머물지 않고 실패 안내 뒤 다시 저장할 수 있는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('저장 콜백이 예외로 끝나면 저장 중 상태를 해제하고 다시 저장할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할: 첫 요청은 예외로 끝내고 다음 요청은 실패 결과로 화면을 유지한다.
          // 매개변수: entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값.
          // 반환값: 두 번째 요청부터 failed 상태의 저장 결과.
          onSaveRequested: (entry) async {
            requestCount += 1;
            if (requestCount == 1) {
              throw StateError('refresh failed');
            }
            return _keepManualEntryOpen(entry);
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '직접입력약',
    );
    final save = find.byKey(const Key('manual-medication-save'));
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(requestCount, 1);
    expect(find.text('저장 중...'), findsNothing);
    expect(find.text('복약 정보를 저장하지 못했습니다.'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(requestCount, 2);
    expect(find.text('테스트 저장 중단'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 저장 중 재요청 차단 테스트
  // 함수역할: 저장 응답을 기다리는 동안과 저장 성공 뒤 화면이 닫히는 동안 저장 요청이 다시 나가지 않는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('저장 중이거나 저장을 마친 화면은 저장 요청을 다시 보내지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingSave = Completer<MedicationSaveResult>();
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할: 직접 등록 화면을 새 경로로 여는 버튼을 만든다. 매개변수: context. 반환값: 시작 화면.
          builder: (context) => Scaffold(
            body: TextButton(
              // 함수이름: onPressed 콜백
              // 함수역할: 직접 등록 화면을 연다. 매개변수: 없음. 반환값: 없음.
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  // 함수이름: builder 콜백
                  // 함수역할: 응답을 미룬 저장 콜백으로 직접 등록 화면을 만든다. 매개변수: _. 반환값: 직접 등록 화면.
                  builder: (_) => ManualMedicationEntryUI(
                    userSetting: const UserSetting(language: 'ko'),
                    // 함수이름: onSaveRequested 콜백
                    // 함수역할: 요청 횟수를 세고 테스트가 끝낼 때까지 응답을 미룬다.
                    // 매개변수: entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값.
                    // 반환값: 테스트가 완료시키는 저장 결과 Future.
                    onSaveRequested: (entry) {
                      requestCount += 1;
                      return pendingSave.future;
                    },
                  ),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '직접입력약',
    );
    final save = find.byKey(const Key('manual-medication-save'));
    await tester.tap(save);
    await tester.pump();
    expect(find.text('저장 중...'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(requestCount, 1);

    pendingSave.complete(
      const MedicationSaveResult(
        status: MedicationSaveStatus.saved,
        message: 'saved',
      ),
    );
    await tester.pump();
    // 닫히는 전환이 진행되는 동안에도 저장 버튼은 잠긴 채로 남는다.
    await tester.pump(const Duration(milliseconds: 50));
    expect(save, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.byType(ManualMedicationEntryUI), findsNothing);
    expect(find.text('복약 정보를 저장했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 임시 사본 정리 테스트
  // 함수역할: 사진을 바꾸거나 지우면 앱 임시 폴더의 이전 사본만 지우고 폴더 밖의 원본은 남기는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('사진을 바꾸거나 지우면 앱 임시 폴더의 사본만 지운다', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = _PhotoSandbox.create();
    final first = sandbox.cachePhoto('first.png');
    final second = sandbox.cachePhoto('second.png');
    final original = sandbox.galleryPhoto('original.png');
    final picker = _PhotoPicker();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          imagePicker: picker,
          onSaveRequested: _keepManualEntryOpen,
        ),
      ),
    );

    picker.path = first.path;
    await _pickManualPhoto(tester);
    await _settleFileCleanup(tester);
    expect(first.existsSync(), isTrue);

    // 다른 사진으로 바꾸면 이전 사본만 지운다.
    picker.path = second.path;
    await _pickManualPhoto(tester);
    await _settleFileCleanup(tester, first);
    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isTrue);

    // 같은 경로를 다시 받으면 지금 쓰는 사본을 지우지 않는다.
    await _pickManualPhoto(tester);
    await _settleFileCleanup(tester);
    expect(second.existsSync(), isTrue);

    final remove = find.byKey(const Key('manual-medication-remove-photo'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await _settleFileCleanup(tester, second);
    expect(second.existsSync(), isFalse);

    // 앱 임시 폴더 밖의 파일은 선택을 지워도 그대로 둔다.
    picker.path = original.path;
    await _pickManualPhoto(tester);
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await _settleFileCleanup(tester);
    expect(original.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 화면 종료 시 임시 사본 정리 테스트
  // 함수역할: 저장하지 않고 닫으면 바로, 저장 중에 닫으면 저장이 끝난 뒤에 임시 사본을 지우는지 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('화면을 닫으면 임시 사본을 지우되 저장 중이면 저장이 끝난 뒤 지운다', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = _PhotoSandbox.create();
    final abandoned = sandbox.cachePhoto('abandoned.png');
    final submitted = sandbox.cachePhoto('submitted.png');
    final picker = _PhotoPicker();
    final pendingSave = Completer<MedicationSaveResult>();
    final navigatorKey = GlobalKey<NavigatorState>();
    // 함수이름: openManualEntry
    // 함수역할: 직접 등록 화면을 새 경로로 연다. 매개변수: 없음. 반환값: 화면 전환 완료.
    Future<void> openManualEntry() async {
      unawaited(
        navigatorKey.currentState!.push<bool>(
          MaterialPageRoute(
            // 함수이름: builder 콜백
            // 함수역할: 응답을 미룬 저장 콜백으로 직접 등록 화면을 만든다. 매개변수: _. 반환값: 직접 등록 화면.
            builder: (_) => ManualMedicationEntryUI(
              userSetting: const UserSetting(language: 'ko'),
              imagePicker: picker,
              // 함수이름: onSaveRequested 콜백
              // 함수역할: 테스트가 끝낼 때까지 저장 응답을 미룬다. 매개변수: entry. 반환값: 저장 결과 Future.
              onSaveRequested: (entry) => pendingSave.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('시작')),
      ),
    );

    // 저장하지 않고 닫으면 선택했던 사본을 바로 지운다.
    await openManualEntry();
    picker.path = abandoned.path;
    await _pickManualPhoto(tester);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _settleFileCleanup(tester, abandoned);
    expect(abandoned.existsSync(), isFalse);

    // 저장 응답을 기다리는 중에 닫으면 저장 흐름이 사진을 읽을 수 있도록 남겨 둔다.
    await openManualEntry();
    picker.path = submitted.path;
    await _pickManualPhoto(tester);
    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '직접입력약',
    );
    await tester.tap(find.byKey(const Key('manual-medication-save')));
    await tester.pump();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _settleFileCleanup(tester);
    expect(find.byType(ManualMedicationEntryUI), findsNothing);
    expect(submitted.existsSync(), isTrue);

    pendingSave.complete(
      const MedicationSaveResult(
        status: MedicationSaveStatus.saved,
        message: 'saved',
      ),
    );
    await tester.pump();
    await _settleFileCleanup(tester, submitted);
    expect(submitted.existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
