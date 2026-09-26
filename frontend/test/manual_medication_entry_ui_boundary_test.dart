// 파일명: manual_medication_entry_ui_boundary_test.dart
// 역할: 복약정보 직접 등록 화면의 입력 검증, 사진 선택과 저장 흐름을 검증한다. 직접 등록 화면의 필수 입력 검증과 저장 요청 구성을 확인한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 클래스명: _PhotoPicker
// 역할: 실제 카메라·갤러리 없이 사진 선택값과 요청 옵션을 검증한다.
class _PhotoPicker extends ImagePicker {
  String? path;
  ImageSource? source;

  // 함수이름: pickImage
  // 함수역할: 사진 요청 옵션을 확인하고 준비된 경로 또는 취소를 반환한다.
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
    return path == null ? null : XFile(path!);
  }
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
      expect(title.style!.fontWeight, FontWeight.w800);
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
}
