// File Name: check_saved_medication_ui_boundary_test.dart
// Role: Regression coverage for saved-medication entry, grouped deletion, ordering, and accessible
//   layouts.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_saved_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _CancelledGalleryInputPrescription
// Role: Gallery-input stub that records selection attempts and simulates cancellation.
// Responsibilities:
// - Count gallery requests and model user cancellation without selecting an image.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _CancelledGalleryInputPrescription extends InputPrescription {
  int requestCount = 0;

  // Function Name: requestPrescriptionImageFromGallery
  // Description:
  // - Count gallery requests and model user cancellation without selecting an image.
  // Parameters:
  // - onImageSelected (PrescriptionImageSelectedCallback?): Callback announcing that an image has been
  //   selected. Accepted but not consumed by this fixture.
  // Returns:
  // - Null, indicating no prescription image was selected.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    requestCount += 1;
    return null;
  }
}

// Function Name: main
// Description:
// - Register regression cases for saved-medication entry, grouped deletion, ordering, and accessible
//   layouts.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: 조회 조건 전환 테스트
  // 함수역할: 기본 복용 중 상태와 종료·전체 선택에 따른 실제 목록을 확인한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('조회 조건은 복용 중으로 시작하고 종료와 전체를 선택한다', (tester) async {
    await _pumpFilterApp(tester);
    expect(find.text('조회 조건: 복용 중'), findsOneWidget);
    expect(find.text('복용 종료'), findsNothing);
    expect(find.text('진행약'), findsOneWidget);
    expect(find.text('종료약'), findsNothing);
    expect(find.text('예정약'), findsNothing);

    await tester.tap(find.byKey(const Key('saved-medication-filter-selector')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('saved-medication-filter-option-active')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('saved-medication-filter-option-ended')),
    );
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 복용 종료'), findsOneWidget);
    expect(find.text('진행약'), findsNothing);
    expect(find.text('종료약'), findsOneWidget);
    await _chooseSavedFilter(tester, 'all');
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(find.text('진행약'), findsOneWidget);
    expect(find.text('종료약'), findsOneWidget);
    expect(find.text('예정약'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 선택 삭제 유지 테스트
  // 함수역할: 취소·동일 조건은 선택 약을 유지하고 조건을 바꿀 때만 선택을 비우는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('조회 조건 취소는 선택 삭제 대상을 유지하고 변경은 초기화한다', (tester) async {
    await _pumpFilterApp(tester);
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1개 선택됨'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-medication-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-filter-close')));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택됨'), findsOneWidget);
    await _chooseSavedFilter(tester, 'active');
    expect(find.text('1개 선택됨'), findsOneWidget);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('0개 선택됨'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 빈 필터 결과 테스트
  // 함수역할: 복용 중인 약이 없어도 조회 조건을 바꾸어 종료된 약을 볼 수 있는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('복용 중 결과가 비어도 조회 조건에서 종료 약으로 전환한다', (tester) async {
    await _pumpFilterApp(tester, onlyEnded: true);
    expect(find.text('현재 복용 중인 약이 없습니다.'), findsOneWidget);
    expect(find.text('조회 조건: 복용 중'), findsOneWidget);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('종료약'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 조회 조건 접근성 테스트
    // 함수역할: 작은 화면과 두 배 글씨에서도 조건 버튼·선택 창이 넘치지 않는지 확인한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('조회 조건은 작은 화면과 큰 글씨에서 표시된다: $language', (tester) async {
      await _pumpFilterApp(
        tester,
        language: language,
        textScale: 2,
        small: true,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final all = find.byKey(const Key('saved-medication-filter-option-all'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'ko' ? '조회 조건: 전체' : 'Search filter: All'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 빈 저장 목록의 촬영 버튼은 세 가지 약 등록 방식을 제공한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('빈 저장 목록의 촬영 버튼은 세 가지 약 등록 방식을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_emptySavedMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('처방전 촬영하기'));
    await tester.pumpAndSettle();

    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(find.byType(PillIdentificationUI), findsNothing);
    await tester.tap(find.text('알약 하나씩 찾기'));
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 빈 저장 목록에서 처방전 분석을 선택하면 이미지 출처를 고른다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('빈 저장 목록에서 처방전 분석을 선택하면 이미지 출처를 고른다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_emptySavedMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('처방전 촬영하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처방전 분석'));
    await tester.pumpAndSettle();

    expect(find.text('카메라로 촬영'), findsOneWidget);
    expect(find.text('갤러리에서 선택'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: embedded empty cabinet keeps the root route during gallery input.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets(
    'embedded empty cabinet keeps the root route during gallery input',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final client = MockClient(_emptySavedMedicationResponse);
      final inputPrescription = _CancelledGalleryInputPrescription();
      final viewModel = MedBuddyViewModel(
        inputPrescription: inputPrescription,
        checkSavedMedication: CheckSavedMedication(
          baseUrl: 'http://medbuddy.test',
          client: client,
        ),
        apiClient: client,
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: viewModel,
          child: const MaterialApp(
            home: Scaffold(
              key: ValueKey('embedded-cabinet-root'),
              body: CheckSavedMedicationUI(showCloseButton: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('처방전 촬영하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('처방전 분석'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리에서 선택'));
      await tester.pumpAndSettle();

      expect(inputPrescription.requestCount, 1);
      expect(
        find.byKey(const ValueKey('embedded-cabinet-root')),
        findsOneWidget,
      );
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 환자 자신의 저장 약 목록에는 보호자 알림 설정을 표시하지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('patient saved list does not expose guardian alert control', (
    tester,
  ) async {
    final client = MockClient(_savedMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('알림 설정'), findsNothing);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 약 사진 팝업은 작은 화면과 큰 글자에서도 이미지 영역을 제한한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('약 사진 팝업은 작은 화면과 큰 글자에서도 이미지 영역을 제한한다', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_savedMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 기존 하위 화면에 2배 글씨를 적용해 접근성 배치를 검사한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
          // 반환값:
          // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const CheckSavedMedicationUI(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageButton = find.byKey(const ValueKey('savedMedicationImage-1'));
    await tester.ensureVisible(imageButton);
    await tester.pumpAndSettle();
    await tester.tap(imageButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('medication-image-dialog')), findsOneWidget);
    expect(find.byKey(const Key('medication-image-viewer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 묶음 삭제 일부만 성공한 경우 전체 성공 대신 혼합 결과를 안내하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('group delete reports mixed results instead of full success', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_mixedDeleteResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      checkSchedule: CheckSchedule(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);
    await viewModel.requestUserSettingSave(
      fontSizeOption: 'medium',
      readingSpeedOption: 'medium',
      language: 'en',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: CheckSavedMedicationUI()),
      ),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.text('Delete');
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(find.text('Deleted: 1. Failed: 1.'), findsOneWidget);
    expect(find.text('Deleted.'), findsNothing);
    expect(
      viewModel.savedMedicationInfoList
          // Function Name: map callback
          // Description:
          // - Extract the saved medication ID for the collection assertion.
          // Parameters:
          // - medication (MedicationDetail): Saved medication whose ID is inspected.
          // Returns:
          // - The element's id value.
          .map((medication) => medication.id)
          .toList(),
      [2],
    );
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 저장 약 목록이 등록일 기준과 복용일 기준 정렬을 전환하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets(
    'saved medication list switches between registration and medication dates',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({});
      final client = MockClient(_sortableMedicationResponse);
      final viewModel = MedBuddyViewModel(
        checkSavedMedication: CheckSavedMedication(
          baseUrl: 'http://medbuddy.test',
          client: client,
        ),
        manageUserSetting: ManageUserSetting(useRemotePersistence: false),
        apiClient: client,
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: viewModel,
          child: const MaterialApp(home: CheckSavedMedicationUI()),
        ),
      );
      await tester.pumpAndSettle();

      final newestRegistration = find.text('등록최신약');
      final newestMedicationDate = find.text('복용최신약');
      expect(find.byTooltip('정렬 기준 설정'), findsOneWidget);
      expect(find.text('등록일자순'), findsNothing);
      expect(find.text('복용날짜순'), findsNothing);
      expect(
        tester.getTopLeft(newestRegistration).dy,
        lessThan(tester.getTopLeft(newestMedicationDate).dy),
      );
      final closeCenter = tester.getCenter(
        find.byKey(const ValueKey('savedMedicationCloseButton')),
      );
      final sortModeCenter = tester.getCenter(
        find.byKey(const ValueKey('savedMedicationSortModeButton')),
      );
      final filterCenter = tester.getCenter(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      final sortDirectionCenter = tester.getCenter(
        find.byKey(const ValueKey('savedMedicationSortDirectionButton')),
      );
      expect((closeCenter.dy - sortModeCenter.dy).abs(), lessThan(1));
      expect((filterCenter.dy - sortDirectionCenter.dy).abs(), lessThan(1));

      await tester.tap(
        find.byKey(const ValueKey('savedMedicationSortModeButton')),
      );
      await tester.pumpAndSettle();
      expect(find.text('등록일자순'), findsOneWidget);
      expect(find.text('복용날짜순'), findsOneWidget);
      await tester.tap(find.text('복용날짜순'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(newestMedicationDate).dy,
        lessThan(tester.getTopLeft(newestRegistration).dy),
      );

      await tester.tap(
        find.byKey(const ValueKey('savedMedicationSortDirectionButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(
        tester.getTopLeft(newestRegistration).dy,
        lessThan(tester.getTopLeft(newestMedicationDate).dy),
      );
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영문 저장 목록은 작은 화면과 큰 글자에서도 넘치지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영문 저장 목록은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(_sortableMedicationResponse);
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: CheckSavedMedication(
        baseUrl: 'http://medbuddy.test',
        client: client,
      ),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
      apiClient: client,
    );
    addTearDown(viewModel.dispose);
    await viewModel.requestUserSettingSave(
      fontSizeOption: 'large',
      readingSpeedOption: 'medium',
      language: 'en',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
          // 반환값:
          // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const CheckSavedMedicationUI(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved Medication'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 함수이름: _chooseSavedFilter
// 함수역할: 조회 조건 시트에서 지정한 상태를 선택한다. 매개변수: tester, mode. 반환값: 화면 갱신 완료.
Future<void> _chooseSavedFilter(WidgetTester tester, String mode) async {
  await tester.tap(find.byKey(const Key('saved-medication-filter-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('saved-medication-filter-option-$mode')));
  await tester.pumpAndSettle();
}

// 함수이름: _pumpFilterApp
// 함수역할: 오늘 기준의 복용 중·종료·예정 약과 접근성 설정으로 필터 화면을 준비한다.
// 매개변수: tester, onlyEnded, language, textScale, small. 반환값: 화면 로딩 완료.
Future<void> _pumpFilterApp(
  WidgetTester tester, {
  bool onlyEnded = false,
  String language = 'ko',
  double textScale = 1,
  bool small = false,
}) async {
  tester.view.physicalSize = small
      ? const Size(320, 640)
      : const Size(480, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  // 함수역할: 위치나 실제 저장 정보에 접근하지 않고 복용 기간별 목록을 반환한다.
  final client = MockClient((request) async {
    final today = DateTime.now();
    return http.Response(
      jsonEncode({
        'success': true,
        'data': [
          if (!onlyEnded)
            {
              ..._savedMedicationJson(request, 1, '진행약'),
              'prescription_date': today.toIso8601String(),
              'total_days': '14',
            },
          {
            ..._savedMedicationJson(request, 2, '종료약'),
            'prescription_date': today
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'total_days': '7',
          },
          if (!onlyEnded)
            {
              ..._savedMedicationJson(request, 3, '예정약'),
              'prescription_date': today
                  .add(const Duration(days: 5))
                  .toIso8601String(),
              'total_days': '7',
            },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final viewModel = MedBuddyViewModel(
    checkSavedMedication: CheckSavedMedication(
      baseUrl: 'http://medbuddy.test',
      client: client,
    ),
    manageUserSetting: ManageUserSetting(useRemotePersistence: false),
    apiClient: client,
  );
  addTearDown(viewModel.dispose);
  await viewModel.requestUserSettingSave(
    fontSizeOption: 'large',
    readingSpeedOption: 'medium',
    language: language,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: viewModel,
      child: MaterialApp(
        // 함수역할: 시트에도 같은 접근성 글씨 배율을 적용한다.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CheckSavedMedicationUI(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: _emptySavedMedicationResponse
// 함수역할:
// - 저장 목록 GET에는 빈 성공 응답을, 그 외 경로에는 404를 제공한다.
// 매개변수:
// - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
// 반환값:
// - 빈 저장 목록의 HTTP 200 또는 미지원 경로의 404 응답.
Future<http.Response> _emptySavedMedicationResponse(
  http.Request request,
) async {
  if (request.method == 'GET' && request.url.path == '/list') {
    return http.Response(
      jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('Not found', 404);
}

// Function Name: _savedMedicationResponse
// Description:
// - Provide one saved medication scoped to the request patient, with an image and fixed dates.
// Parameters:
// - request (http.Request): HTTP request intercepted instead of reaching the server.
// Returns:
// - HTTP 200 containing the saved-tablet fixture.
Future<http.Response> _savedMedicationResponse(http.Request request) async {
  return http.Response(
    jsonEncode({
      'success': true,
      'data': [
        {
          'id': 1,
          'patient_hash':
              request.url.queryParameters['patient_hash'] ?? 'local_patient',
          'created_date': '2026-07-15',
          'prescription_date': '2026-07-15',
          'item_seq': '200000001',
          'item_name': 'test-tablet',
          'efficacy': 'effect',
          'use_method': 'usage',
          'warning_message': 'warning',
          'image_url': 'https://nedrug.mfds.go.kr/tablet.jpg',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

// Function Name: _mixedDeleteResponse
// Description:
// - Serve two saved tablets, fail deletion of the second, and return an empty refreshed schedule.
// Parameters:
// - request (http.Request): HTTP request intercepted instead of reaching the server.
// Returns:
// - HTTP 200 for supported reads/first deletion, 500 for the second deletion, or 404 otherwise.
Future<http.Response> _mixedDeleteResponse(http.Request request) async {
  if (request.method == 'GET' && request.url.path == '/list') {
    return http.Response(
      jsonEncode({
        'success': true,
        'data': [
          _savedMedicationJson(request, 1, 'tablet-one'),
          _savedMedicationJson(request, 2, 'tablet-two'),
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  if (request.method == 'DELETE') {
    final id = int.parse(request.url.pathSegments.last);
    return http.Response(
      jsonEncode({'success': id == 1}),
      id == 1 ? 200 : 500,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  if (request.method == 'GET' && request.url.path == '/schedule/today') {
    return http.Response(
      jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response('Not found', 404);
}

// 함수이름: _sortableMedicationResponse
// 함수역할:
// - 등록일과 복용일의 최신 순서가 서로 다른 두 약을 반환해 정렬 전환을 구별한다.
// 매개변수:
// - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
// 반환값:
// - 목록 GET의 두 약 응답 또는 미지원 경로의 HTTP 404.
Future<http.Response> _sortableMedicationResponse(http.Request request) async {
  if (request.method != 'GET' || request.url.path != '/list') {
    return http.Response('Not found', 404);
  }
  return http.Response(
    jsonEncode({
      'success': true,
      'data': [
        {
          ..._savedMedicationJson(request, 1, '등록최신약'),
          'created_date': '2026-07-22',
          'prescription_date': '2026-07-01',
        },
        {
          ..._savedMedicationJson(request, 2, '복용최신약'),
          'created_date': '2026-07-20',
          'prescription_date': '2026-07-21',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

// Function Name: _savedMedicationJson
// Description:
// - Build a saved-medication JSON fixture with request-scoped patient identity and a trusted image.
// Parameters:
// - request (http.Request): HTTP request intercepted instead of reaching the server.
// - id (int): Identifier of the medication, message, or notification fixture.
// - name (String): Display name of the saved-medication fixture.
// Returns:
// - The medication map for the supplied ID and name.
Map<String, dynamic> _savedMedicationJson(
  http.Request request,
  int id,
  String name,
) {
  return {
    'id': id,
    'patient_hash':
        request.url.queryParameters['patient_hash'] ?? 'local_patient',
    'created_date': '2026-07-15',
    'prescription_date': '2026-07-15',
    'item_seq': '20000000$id',
    'item_name': name,
    'efficacy': 'effect',
    'use_method': 'usage',
    'warning_message': 'warning',
    'image_url': 'https://nedrug.mfds.go.kr/tablet.jpg',
  };
}
