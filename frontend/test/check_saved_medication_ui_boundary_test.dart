// 파일명: check_saved_medication_ui_boundary_test.dart
// 역할: 저장 약의 필터·선택 삭제·등록 진입과 접근성 배치를 검증한다.

import 'dart:async';
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
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
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

// 함수이름: main
// 함수역할: 등록·정렬·선택 삭제와 작은 화면 접근성 회귀 검사를 등록한다.
// 매개변수: 없음. 반환값: 없음; 각 테스트가 기대 동작을 검증한다.
void main() {
  testWidgets('조회 조건은 현재 값 세 줄로 표시하고 취소하면 기존 조건을 유지한다', (tester) async {
    await _pumpFilterApp(tester);
    await tester.tap(find.byKey(const Key('saved-medication-filter-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('saved-medication-filter-row')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('saved-medication-sort-row')), findsOneWidget);
    expect(
      find.byKey(const Key('saved-medication-direction-row')),
      findsOneWidget,
    );
    await _openFilterRow(tester, 'filter');
    await tester.tap(
      find.byKey(const Key('saved-medication-filter-option-ended')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-filter-close')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 복용 중'), findsOneWidget);
    expect(find.text('진행약'), findsOneWidget);
    expect(find.text('종료약'), findsNothing);
  });

  // 함수역할: 검색어와 조회 상태를 모두 통과한 약만 전체 선택 삭제되는지 검증한다.
  testWidgets('검색한 약만 선택하며 검색어를 바꾸면 숨겨진 선택을 비운다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '약 1',
    );
    await tester.pumpAndSettle();
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    expect(find.text('1개 선택'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '약 2',
    );
    await tester.pumpAndSettle();
    expect(find.text('0개 선택'), findsOneWidget);
    await _toggleSavedAll(tester);
    await _deleteSavedSelection(tester);
    expect(model.deletedIds, [2]);
  });

  // 함수역할: 검색 결과 부재와 사진 없음이 삭제 동작으로 오해되지 않는지 확인한다.
  testWidgets('사진 없는 약은 이미지 없음 아이콘이며 빈 검색은 전체 보기로 복구한다', (tester) async {
    await _pumpSelectionApp(tester);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.textContaining('등록일자:'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '없는약',
    );
    await tester.pumpAndSettle();
    expect(find.text('검색한 약이 없습니다.'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.ensureVisible(
      find.byKey(const Key('saved-medication-show-all')),
    );
    await tester.tap(find.byKey(const Key('saved-medication-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('saved-medication-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  // 함수이름: 공통 제목 테스트
  // 함수역할: 루트 제목의 강조와 정렬 동작의 같은 행 배치를 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('루트 제목은 공통 헤더이며 선택 메뉴만 같은 행에 놓인다', (tester) async {
    await _pumpSelectionApp(tester);
    final header = tester.widget<MedBuddyPageHeader>(
      find.byType(MedBuddyPageHeader),
    );
    expect(header.prominent, isTrue);
    expect(header.onBackRequested, isNull);
    expect(tester.getTopLeft(find.text('저장된 복약 정보')).dx, 32);
    final title = tester.widget<Text>(find.text('저장된 복약 정보'));
    expect(title.style!.fontSize, 21);
    expect(title.style!.color, Colors.white);
    expect(
      (tester.getTopLeft(find.text('저장된 복약 정보')).dy -
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('saved-medication-select')),
                  )
                  .dy)
          .abs(),
      lessThan(1),
    );
    expect(find.text('약과 복용 기록을 확인합니다.'), findsOneWidget);
  });

  // 함수이름: 전체·일부 선택 테스트
  // 함수역할: 유효 ID만 전체 선택하고 일부 선택·전체 해제가 올바르게 표시되는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('전체 선택은 보이는 유효 ID만 포함하고 일부 선택과 해제를 표시한다', (tester) async {
    await _pumpSelectionApp(tester, invalidIds: true);
    await _startSavedSelection(tester);
    expect(find.text('복약 선택'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const Key('saved-medication-cancel-selection')))
          .right,
      lessThan(tester.getRect(find.text('복약 선택')).left),
    );
    expect(
      tester
          .widget<MedBuddyPageHeader>(find.byType(MedBuddyPageHeader))
          .actions,
      isEmpty,
    );
    expect(_allSelection(tester).value, isFalse);
    for (final id in ['null', '0', '-1']) {
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(ValueKey('saved-medication-checkbox-$id')),
            )
            .onChanged,
        isNull,
      );
    }
    await _toggleSavedAll(tester);
    expect(_allSelection(tester).value, isTrue);
    expect(find.text('2개 선택'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saved-medication-checkbox-1')));
    await tester.pumpAndSettle();
    expect(_allSelection(tester).value, isNull);
    expect(find.text('1개 선택'), findsOneWidget);
    await _toggleSavedAll(tester);
    expect(_allSelection(tester).value, isTrue);
    await _toggleSavedAll(tester);
    expect(_allSelection(tester).value, isFalse);
    expect(find.text('0개 선택'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('saved-medication-delete-selected')),
          )
          .onPressed,
      isNull,
    );
  });

  // 함수이름: 필터별 삭제 범위 테스트
  // 함수역할: 조건이 바뀔 때 선택을 비우고 최종 표시 조건 외의 약은 삭제하지 않는다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('필터 전환 뒤 전체 선택 삭제는 현재 표시 약으로 제한된다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('0개 선택'), findsOneWidget);
    await _toggleSavedAll(tester);
    expect(find.text('1개 선택'), findsOneWidget);
    await _chooseSavedFilter(tester, 'all');
    expect(find.text('0개 선택'), findsOneWidget);
    await _toggleSavedAll(tester);
    expect(find.text('4개 선택'), findsOneWidget);
    await _chooseSavedFilter(tester, 'active');
    expect(find.text('0개 선택'), findsOneWidget);
    await _toggleSavedAll(tester);
    await _deleteSavedSelection(tester);
    expect(model.deletedIds, unorderedEquals([1, 2]));
    expect(
      model.savedMedicationInfoList.map((item) => item.id),
      unorderedEquals([3, 4]),
    );
    expect(find.text('복약 선택'), findsNothing);
  });

  // 함수이름: 갱신 후 삭제 재검증 테스트
  // 함수역할: 확인 창을 연 뒤 숨겨진 약은 삭제 직전에도 제외한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('삭제 확인 중 목록이 바뀌면 보이지 않는 ID를 제외한다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    await model.replaceMedications([
      _selectionMedication(1),
      _selectionMedication(2, offsetDays: -30),
      _selectionMedication(3, offsetDays: -30),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('예'));
    await tester.pumpAndSettle();
    expect(model.deletedIds, [1]);
    expect(
      model.savedMedicationInfoList.map((item) => item.id),
      unorderedEquals([2, 3]),
    );
  });

  // 함수이름: 선택 삭제 부분 실패 테스트
  // 함수역할: 실제 ViewModel의 혼합 삭제 결과와 실패 항목 재선택을 검증한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('선택 일괄 삭제의 실패 항목은 선택을 유지한다', (tester) async {
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
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(
          home: CheckSavedMedicationUI(showCloseButton: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await _deleteSavedSelection(tester);
    expect(find.text('삭제 성공: 1개. 실패: 1개.'), findsOneWidget);
    expect(find.text('복약 선택'), findsOneWidget);
    expect(find.text('1개 선택'), findsOneWidget);
    expect(_allSelection(tester).value, isTrue);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('saved-medication-checkbox-2')),
          )
          .value,
      isTrue,
    );
  });

  // 함수이름: 삭제 중 조작 차단 테스트
  // 함수역할: 대기 중인 삭제는 선택·조건·뒤로가기와 중복 삭제를 막는다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('삭제 진행 중에는 조작과 화면 이탈을 막는다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    model.deleteGate = Completer<void>();
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예'));
    await tester.pumpAndSettle();
    expect(_allSelection(tester).onChanged, isNull);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('saved-medication-checkbox-1')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('saved-medication-filter-selector')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('saved-medication-cancel-selection')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('saved-medication-search')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('saved-medication-delete-selected')),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('복약 선택'), findsOneWidget);
    expect(model.deleteCalls, 2);
    model.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('복약 선택'), findsNothing);
  });

  // 함수이름: 선택 취소와 탐색 테스트
  // 함수역할: 닫기는 선택만 취소하고 시스템 뒤로가기도 선택을 먼저 닫은 뒤 화면을 나간다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('하위 화면의 선택 취소와 뒤로가기는 단계적으로 동작한다', (tester) async {
    await _pumpSelectionApp(tester, submenu: true);
    expect(
      tester
          .widget<MedBuddyPageHeader>(find.byType(MedBuddyPageHeader))
          .prominent,
      isFalse,
    );
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(
      find.byKey(const Key('saved-medication-cancel-selection')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckSavedMedicationUI), findsOneWidget);
    await _startSavedSelection(tester);
    expect(find.text('0개 선택'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CheckSavedMedicationUI), findsOneWidget);
    expect(find.text('복약 선택'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(CheckSavedMedicationUI), findsNothing);
    expect(find.text('목록 열기'), findsOneWidget);
  });

  // 함수이름: 빈 결과 복구 테스트
  // 함수역할: 전체 보기로 실제 목록을 표시하고 등록 버튼은 기존 작업 선택을 연다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('빈 복용 중 결과의 전체 보기와 등록 식별은 실제 동작한다', (tester) async {
    await _pumpFilterApp(tester, onlyEnded: true);
    await tester.tap(find.byKey(const Key('saved-medication-register')));
    await tester.pumpAndSettle();
    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);
    Navigator.of(tester.element(find.text('직접 등록'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(find.text('종료약'), findsOneWidget);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 선택 모드 큰 글씨 테스트
    // 함수역할: 작은 화면의 두 배 글씨에서도 날짜·개수·삭제 버튼을 끝까지 표시한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('선택과 날짜 정보는 큰 글씨에서도 잘리지 않는다: $language', (tester) async {
      await _pumpSelectionApp(
        tester,
        language: language,
        textScale: 2,
        small: true,
      );
      await _startSavedSelection(tester);
      await _toggleSavedAll(tester);
      expect(tester.takeException(), isNull);
      final footer = find.byKey(const Key('saved-medication-delete-selected'));
      expect(tester.getRect(footer).width, 280);
      expect(tester.getRect(footer).bottom, lessThanOrEqualTo(640));
      final date = find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data ?? '').startsWith(
                  language == 'ko' ? '복용기간:' : 'Medication period:',
                ),
          )
          .first;
      await tester.ensureVisible(date);
      await tester.pumpAndSettle();
      final dateText = tester.widget<Text>(date);
      expect(dateText.maxLines, isNull);
      expect(dateText.overflow, isNot(TextOverflow.ellipsis));
      expect(dateText.style!.color, MedBuddyColors.textMuted);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: 빈 화면 큰 글씨 테스트
    // 함수역할: 빈 결과의 두 버튼이 큰 글씨에서도 스크롤로 도달 가능한지 확인한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('빈 결과 동작은 큰 글씨에서도 도달할 수 있다: $language', (tester) async {
      await _pumpFilterApp(
        tester,
        onlyEnded: true,
        language: language,
        textScale: 2,
        small: true,
      );
      final register = find.byKey(const Key('saved-medication-register'));
      await tester.scrollUntilVisible(
        register,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('saved-medication-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(register).bottom, lessThanOrEqualTo(640));
      final all = find.byKey(const Key('saved-medication-show-all'));
      await tester.ensureVisible(all);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('종료약'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 빈 종료 결과 복구 테스트
  // 함수역할: 종료 결과가 비면 전체 보기로 복용 중인 약을 다시 표시한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('빈 종료 결과는 전체 보기로 복구하며 등록 동작을 중복하지 않는다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await model.replaceMedications([_selectionMedication(1)]);
    await tester.pumpAndSettle();
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('복용이 끝난 약이 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('saved-medication-register')), findsNothing);
    await tester.tap(find.byKey(const Key('saved-medication-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 완전히 빈 목록 접근성 테스트
    // 함수역할: 큰 글씨에서도 등록 버튼 전체가 보이고 화면 밖으로 넘치지 않는다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('완전히 빈 목록의 등록 버튼은 큰 글씨를 수용한다: $language', (tester) async {
      final model = await _pumpSelectionApp(
        tester,
        language: language,
        textScale: 2,
        small: true,
      );
      await model.replaceMedications([]);
      await tester.pumpAndSettle();
      final register = find.byKey(const Key('saved-medication-register'));
      await tester.scrollUntilVisible(
        register,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('saved-medication-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(register).bottom, lessThanOrEqualTo(640));
      expect(tester.getRect(register).left, 20);
      expect(tester.getRect(register).right, 300);
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    await _openFilterRow(tester, 'filter');
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
    await _applySavedFilter(tester);
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
    await tester.tap(find.byKey(const Key('saved-medication-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-medication-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-filter-close')));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);
    await _chooseSavedFilter(tester, 'active');
    expect(find.text('1개 선택'), findsOneWidget);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('0개 선택'), findsOneWidget);
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
      await tester.ensureVisible(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _openFilterRow(tester, 'filter');
      final all = find.byKey(const Key('saved-medication-filter-option-all'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      await _applySavedFilter(tester);
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

    expect(
      tester.getSize(find.byKey(const Key('saved-medication-register'))).height,
      lessThan(100),
    );
    await tester.tap(find.byKey(const Key('saved-medication-register')));
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

    await tester.tap(find.byKey(const Key('saved-medication-register')));
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

      await tester.tap(find.byKey(const Key('saved-medication-register')));
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
    await tester.scrollUntilVisible(
      imageButton,
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('saved-medication-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
      expect(find.text('등록일자순 · 최신순'), findsOneWidget);
      expect(find.text('등록일자순'), findsNothing);
      expect(find.text('복용날짜순'), findsNothing);
      expect(
        tester.getTopLeft(newestRegistration).dy,
        lessThan(tester.getTopLeft(newestMedicationDate).dy),
      );
      expect(
        find.byKey(const ValueKey('savedMedicationSortModeButton')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('savedMedicationSortDirectionButton')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      await tester.pumpAndSettle();
      await _openFilterRow(tester, 'sort');
      await tester.tap(
        find.byKey(const Key('saved-medication-sort-option-medicationDate')),
      );
      await _applySavedFilter(tester);

      expect(
        tester.getTopLeft(newestMedicationDate).dy,
        lessThan(tester.getTopLeft(newestRegistration).dy),
      );

      await tester.tap(
        find.byKey(const Key('saved-medication-filter-selector')),
      );
      await tester.pumpAndSettle();
      await _openFilterRow(tester, 'direction');
      final ascending = find.byKey(
        const Key('saved-medication-direction-option-ascending'),
      );
      await tester.ensureVisible(ascending);
      await tester.tap(ascending);
      await _applySavedFilter(tester);
      expect(find.text('복용날짜순 · 오래된순'), findsOneWidget);
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
  await _openFilterRow(tester, 'filter');
  await tester.tap(find.byKey(Key('saved-medication-filter-option-$mode')));
  await tester.pumpAndSettle();
  await _applySavedFilter(tester);
}

// 함수역할: 선택한 조회/정렬 조건을 확정한다. 매개변수: tester. 반환값: 적용 완료.
Future<void> _applySavedFilter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('saved-medication-filter-apply')));
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

// 클래스명: _SelectionTestControl
// 역할: 목록 조회와 개별 삭제만 대체해 기존 ViewModel의 일괄 삭제를 검증한다.
// 주요 책임: 삭제 ID를 기록하고 대기·목록 교체를 제어한다.
// 속성: medications는 응답 목록, deleteGate는 대기 신호, deletedIds는 실제 삭제 요청이다.
class _SelectionTestControl extends CheckSavedMedication {
  List<MedicationDetail> medications;
  final List<int> deletedIds = [];
  Completer<void>? deleteGate;

  // 함수이름: _SelectionTestControl
  // 함수역할: 외부 요청 없는 조회 목록을 받는다. 매개변수: medications. 반환값: 테스트 제어기.
  _SelectionTestControl(this.medications);

  // 함수이름: requestSavedMedicationInfo
  // 함수역할: 파싱을 거치지 않아 잘못된 ID도 UI에서 검증한다.
  // 매개변수: 없음. 반환값: 현재 약 목록.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async =>
      List<MedicationDetail>.from(medications);

  // 함수이름: requestDelete
  // 함수역할: 요청 ID를 기록하고 대기 신호 뒤 성공 처리한다.
  // 매개변수: savedMedicationId는 삭제 ID. 반환값: 성공 여부.
  @override
  Future<bool> requestDelete(int savedMedicationId) async {
    deletedIds.add(savedMedicationId);
    if (deleteGate != null) await deleteGate!.future;
    medications = medications
        // 함수역할: 삭제 대상만 제외한다. 매개변수: item. 반환값: 보존 여부.
        .where((item) => item.id != savedMedicationId)
        .toList();
    return true;
  }
}

// 클래스명: _SelectionTestViewModel
// 역할: 기존 ViewModel에 테스트 조회·삭제 제어기를 주입한다.
// 주요 책임: 실제 일괄 삭제와 상태 알림을 유지한다.
// 속성: control은 외부 요청 대신 동작하는 테스트 제어기이다.
class _SelectionTestViewModel extends MedBuddyViewModel {
  final _SelectionTestControl control;

  // 함수이름: _SelectionTestViewModel
  // 함수역할: 목록으로 테스트 제어기를 만든다. 매개변수: medications. 반환값: ViewModel.
  factory _SelectionTestViewModel(List<MedicationDetail> medications) =>
      _SelectionTestViewModel._(_SelectionTestControl(medications));

  // 함수이름: _SelectionTestViewModel._
  // 함수역할: 조회·설정·일정 요청을 기기 외부 접근 없이 구성한다.
  // 매개변수: control은 테스트 제어기. 반환값: ViewModel.
  _SelectionTestViewModel._(this.control)
    : super(
        checkSavedMedication: control,
        checkSchedule: CheckSchedule(
          baseUrl: 'http://medbuddy.test',
          client: MockClient(_mixedDeleteResponse),
        ),
        manageUserSetting: ManageUserSetting(useRemotePersistence: false),
        apiClient: MockClient(_emptySavedMedicationResponse),
      );

  // 함수이름: deletedIds
  // 함수역할: 실제 전달된 삭제 범위를 읽는다. 매개변수: 없음. 반환값: 삭제 ID 목록.
  List<int> get deletedIds => control.deletedIds;

  // 함수이름: deleteCalls
  // 함수역할: 중복 호출 여부를 검사한다. 매개변수: 없음. 반환값: 개별 삭제 요청 수.
  int get deleteCalls => control.deletedIds.length;

  // 함수이름: deleteGate
  // 함수역할: 대기 신호를 읽는다. 매개변수: 없음. 반환값: 선택적 완료 신호.
  Completer<void>? get deleteGate => control.deleteGate;

  // 함수이름: deleteGate
  // 함수역할: 삭제 요청의 완료 시점을 정한다. 매개변수: value는 완료 신호. 반환값: 없음.
  set deleteGate(Completer<void>? value) => control.deleteGate = value;

  // 함수이름: replaceMedications
  // 함수역할: 외부 데이터 갱신을 기존 조회 흐름으로 반영한다.
  // 매개변수: items는 새 목록. 반환값: 조회 완료.
  Future<void> replaceMedications(List<MedicationDetail> items) async {
    control.medications = items;
    await fetchSavedMedicationInfo();
  }
}

// 함수이름: _selectionMedication
// 함수역할: 현재 날짜 기준의 복용 중·종료·예정 약을 만든다.
// 매개변수: id는 저장 ID, offsetDays는 시작일 차이. 반환값: 14일 복용 약.
MedicationDetail _selectionMedication(int? id, {int offsetDays = 0}) =>
    MedicationDetail(
      id: id,
      itemName: '약 $id',
      efficacy: '',
      usageMethod: '',
      warning: '',
      createdDate: DateTime.now(),
      prescriptionDate: DateTime.now().add(Duration(days: offsetDays)),
      totalDays: '14',
    );

// 함수이름: _pumpSelectionApp
// 함수역할: 선택 회귀 검사를 위한 루트 또는 하위 화면을 준비한다.
// 매개변수: tester, invalidIds, submenu, language, textScale, small. 반환값: 제어 가능한 ViewModel.
Future<_SelectionTestViewModel> _pumpSelectionApp(
  WidgetTester tester, {
  bool invalidIds = false,
  bool submenu = false,
  String language = 'ko',
  double textScale = 1,
  bool small = false,
}) async {
  tester.view.physicalSize = small
      ? const Size(320, 640)
      : const Size(480, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final model = _SelectionTestViewModel([
    _selectionMedication(1),
    _selectionMedication(2),
    _selectionMedication(3, offsetDays: -30),
    _selectionMedication(4, offsetDays: 5),
    if (invalidIds) ...[
      _selectionMedication(null),
      _selectionMedication(0),
      _selectionMedication(-1),
    ],
  ]);
  addTearDown(model.dispose);
  await model.requestUserSettingSave(
    fontSizeOption: 'medium',
    readingSpeedOption: 'medium',
    language: language,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: model,
      child: MaterialApp(
        // 함수역할: 모든 경로에 같은 배율을 적용한다. 매개변수: context, child. 반환값: 접근성 화면.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: submenu
            ? Builder(
                // 함수역할: 돌아갈 부모 경로를 만든다. 매개변수: context. 반환값: 진입 버튼 화면.
                builder: (context) => Scaffold(
                  body: TextButton(
                    // 함수역할: 하위 복약 화면을 연다. 매개변수: 없음. 반환값: 이동 완료.
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        // 함수역할: 닫기 가능한 목록을 만든다. 매개변수: context. 반환값: 목록 화면.
                        builder: (context) => const CheckSavedMedicationUI(),
                      ),
                    ),
                    child: const Text('목록 열기'),
                  ),
                ),
              )
            : const CheckSavedMedicationUI(showCloseButton: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (submenu) {
    await tester.tap(find.text('목록 열기'));
    await tester.pumpAndSettle();
  }
  return model;
}

// 함수이름: _startSavedSelection
// 함수역할: 제목의 선택 명령을 실행한다. 매개변수: tester. 반환값: 전환 완료.
Future<void> _startSavedSelection(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('saved-medication-select')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('saved-medication-select')));
  await tester.pumpAndSettle();
}

// 함수이름: _allSelection
// 함수역할: 전체 선택 상태를 읽는다. 매개변수: tester. 반환값: 체크박스 행.
CheckboxListTile _allSelection(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(
      find.byKey(const Key('saved-medication-select-all')),
    );

// 함수이름: _toggleSavedAll
// 함수역할: 전체 선택 또는 해제를 실행한다. 매개변수: tester. 반환값: 갱신 완료.
Future<void> _toggleSavedAll(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('saved-medication-select-all')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('saved-medication-select-all')));
  await tester.pumpAndSettle();
}

// 함수이름: _deleteSavedSelection
// 함수역할: 하단 삭제 요청과 한국어 확인을 수행한다. 매개변수: tester. 반환값: 삭제 완료.
Future<void> _deleteSavedSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('예'));
  await tester.pumpAndSettle();
}

// 함수역할: 현재 값 행을 눌러 해당 조건의 선택창을 연다.
Future<void> _openFilterRow(WidgetTester tester, String row) async {
  final finder = find.byKey(ValueKey('saved-medication-$row-row'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
