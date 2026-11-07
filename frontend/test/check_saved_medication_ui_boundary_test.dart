// 파일명: check_saved_medication_ui_boundary_test.dart
// 역할: 저장 약의 필터·선택 삭제·등록 진입과 접근성 배치를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_saved_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_regimen_editor_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/calendar_days.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/widgets/medication_thumbnail.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _CancelledGalleryInputPrescription
// 역할: 갤러리에서 이미지를 고르지 않고 취소하는 처방 입력 대역.
// 주요 책임: 요청 횟수를 기록하고 선택·진행 콜백 없이 null을 반환한다.
// 속성: requestCount (int): 갤러리 선택 요청 횟수.
class _CancelledGalleryInputPrescription extends InputPrescription {
  int requestCount = 0;

  // 함수이름: requestPrescriptionImageFromGallery
  // 함수역할: 갤러리 호출 횟수만 늘려 사용자가 이미지 선택을 취소한 결과를 재현한다.
  // 매개변수: onImageSelected (PrescriptionImageSelectedCallback?): 호출하지 않는 선택 콜백; onProgress (PrescriptionRecognitionProgressCallback?): 호출하지 않는 인식 진행 콜백.
  // 반환값: Future<List<MedicationSchedule>?>: 항상 null이며 인식을 시작하지 않는다.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
    PrescriptionRecognitionProgressCallback? onProgress,
  }) async {
    requestCount += 1;
    return null;
  }
}

// 함수이름: main
// 함수역할: 등록·정렬·선택 삭제와 작은 화면 접근성 회귀 검사를 등록한다.
// 매개변수: 없음. 반환값: 없음; 각 테스트가 기대 동작을 검증한다.
void main() {
  // Function Name: testWidgets: '날짜별 접기 상태는 검색과 목록 갱신 뒤에도 서로 독립적이다'
  // Description: Collapse dated groups independently, search across a collapsed group, then clear the query and reverse the loaded items.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; search temporarily reveals matches, the saved collapse states survive refresh, and no deletion or widget exception occurs.
  testWidgets('날짜별 접기 상태는 검색과 목록 갱신 뒤에도 서로 독립적이다', (tester) async {
    final model = await _pumpSelectionApp(tester, initialFilter: 'all');
    final items = [
      _selectionMedication(1).copyWith(createdDate: DateTime(2026, 1, 2)),
      _selectionMedication(2).copyWith(createdDate: DateTime(2026, 1, 1)),
    ];
    await model.replaceMedications(items);
    await tester.pumpAndSettle();
    final first = find.byKey(const Key('saved-date-toggle-2026-01-02'));
    final second = find.byKey(const Key('saved-date-toggle-2026-01-01'));
    expect(find.text('약 1'), findsOneWidget);
    expect(find.text('약 2'), findsOneWidget);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsNothing);
    expect(find.text('약 2'), findsOneWidget);
    expect(
      find.descendant(of: first, matching: find.byIcon(Icons.arrow_drop_down)),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '약 2',
    );
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    // 검색 중에는 사용자가 접어 둔 묶음도 펼쳐 찾은 약 이름을 보인다.
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '1',
    );
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '약',
    );
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('saved-medication-search')),
      '',
    );
    await model.replaceMedications(items.reversed.toList());
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsNothing);
    expect(find.text('약 2'), findsOneWidget);
    await tester.tap(second);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
    expect(find.text('약 2'), findsNothing);
    expect(model.deletedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: '접힌 날짜도 선택 수를 표시하고 펼치면 선택을 유지한다'
  // 함수역할: 같은 날짜의 두 약 중 하나를 선택한 뒤 날짜 묶음을 접었다가 다시 펼친다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 접힌 머리글은 1개 선택을 표시하고 다시 펼쳐도 각 체크 상태가 유지되며 삭제하지 않는다.
  testWidgets('접힌 날짜도 선택 수를 표시하고 펼치면 선택을 유지한다', (tester) async {
    final model = await _pumpSelectionApp(tester, initialFilter: 'all');
    await model.replaceMedications([
      _selectionMedication(1).copyWith(createdDate: DateTime(2026, 1, 2)),
      _selectionMedication(2).copyWith(createdDate: DateTime(2026, 1, 2)),
    ]);
    await tester.pumpAndSettle();
    await _startSavedSelection(tester);
    await tester.tap(find.byKey(const Key('saved-medication-checkbox-1')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('saved-date-toggle-2026-01-02'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('saved-date-selected-2026-01-02')))
          .data,
      '1개 선택',
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('saved-medication-checkbox-1')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('saved-medication-checkbox-2')),
          )
          .value,
      isFalse,
    );
    expect(model.deletedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets: '중단과 교체 상태는 큰 글씨에서도 색과 상태명으로 구분한다 $language'
    // 함수역할: 한국어·영어의 작은 화면과 글자 배율 2에서 오늘·내일의 중단 및 처방 변경 상태를 순회한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 현재 중단·변경·예정 상태의 색, 변경 문구, 효력 날짜와 상태 배지가 맞고 화면 예외가 없다.
    testWidgets('중단과 교체 상태는 큰 글씨에서도 색과 상태명으로 구분한다 $language', (tester) async {
      final model = await _pumpSelectionApp(
        tester,
        initialFilter: 'all',
        small: true,
        textScale: 2,
        language: language,
      );
      final today = MedicationHistoryDates.today(DateTime.now());
      for (final scenario in [
        (replaced: false, future: false, color: MedBuddyColors.danger),
        (replaced: true, future: false, color: MedBuddyColors.infoBlue),
        (replaced: false, future: true, color: MedBuddyColors.reminderAccent),
        (replaced: true, future: true, color: MedBuddyColors.reminderAccent),
      ]) {
        await model.replaceMedications([
          _selectionMedication(1).copyWith(
            stoppedOn: today.add(Duration(days: scenario.future ? 1 : 0)),
            supersededById: scenario.replaced ? 2 : null,
          ),
        ]);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('saved-medication-status-1')),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('saved-medication-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final label = tester.widget<Text>(
          find.byKey(const Key('saved-medication-status-1')),
        );
        expect(label.style?.color, scenario.color);
        // 용량만 바꾼 수정도 다음 항목이 연결되므로 '교체'가 아닌 '변경'으로 표시한다.
        if (scenario.replaced) {
          expect(
            label.data,
            startsWith(
              language == 'en'
                  ? (scenario.future ? 'Change scheduled' : 'Changed')
                  : (scenario.future ? '처방 변경 예정' : '처방 변경'),
            ),
          );
        }
        expect(
          label.data,
          contains(
            MedicationHistoryDates.format(
              today.add(Duration(days: scenario.future ? 1 : 0)),
            ),
          ),
        );
        expect(
          find.byKey(const Key('saved-medication-status-badge-1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  // Function Name: testWidgets: '기본 복약함은 중단한 약의 정보와 중단일을 삭제 전까지 보여준다'
  // Description: Show a stopped medicine in the all/ended filters, open its detail, then confirm deletion after checking the record-loss warning and cancel-button order.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the active filter hides it, its stop date remains visible until deletion, and only ID 1 is removed.
  testWidgets('기본 복약함은 중단한 약의 정보와 중단일을 삭제 전까지 보여준다', (tester) async {
    final model = await _pumpSelectionApp(tester, initialFilter: 'all');
    final today = MedicationHistoryDates.today(DateTime.now());
    await model.replaceMedications([
      _selectionMedication(1).copyWith(stoppedOn: today),
      _selectionMedication(2),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(find.text('약 1'), findsOneWidget);
    expect(
      find.text('복용 중단 · ${MedicationHistoryDates.format(today)}'),
      findsOneWidget,
    );
    expect(model.deletedIds, isEmpty);
    await tester.tap(find.text('약 1'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _chooseSavedFilter(tester, 'active');
    expect(find.text('약 1'), findsNothing);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('약 1'), findsOneWidget);
    expect(find.text('약 2'), findsNothing);
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    // 삭제하면 복용 기록도 지워진다는 사실과 기록을 남기는 중단 방법을 알리고, 다른 대화상자와
    // 같이 취소를 왼쪽에 둔다.
    expect(find.textContaining('복용 기록도 함께 삭제'), findsOneWidget);
    expect(find.textContaining('처방에 따른 복용 중단'), findsOneWidget);
    expect(
      tester.getCenter(find.widgetWithText(OutlinedButton, '취소')).dx,
      lessThan(tester.getCenter(find.widgetWithText(OutlinedButton, '삭제')).dx),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '삭제'));
    await tester.pumpAndSettle();
    expect(model.deletedIds, [1]);
    expect(find.text('약 1'), findsNothing);
  });

  // 함수이름: testWidgets: '복용 중 필터에서 중단해도 결과 약을 전체 목록에 남긴다'
  // 함수역할: 복용 중 목록의 관리 메뉴에서 중단을 제출하고 확인한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 필터가 전체로 바뀌고 중단일·상태가 기록된 약이 삭제 없이 남는다.
  testWidgets('복용 중 필터에서 중단해도 결과 약을 전체 목록에 남긴다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await tester.tap(find.byKey(const Key('saved-medication-actions-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처방에 따른 복용 중단'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regimen-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regimen-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(find.text('약 1'), findsOneWidget);
    expect(find.byKey(const Key('saved-medication-status-1')), findsOneWidget);
    expect(model.deletedIds, isEmpty);
    expect(model.control.medications.first.stoppedOn, isNotNull);
  });

  // 함수이름: testWidgets: '미래 중단은 중단 예정으로 표시하고 종료 필터에서 제외한다'
  // 함수역할: 내일 중단할 약을 전체·복용 중·종료 필터에서 조회한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 내일의 중단 예정 문구를 표시하고 복용 중에는 포함하되 종료에서는 제외한다.
  testWidgets('미래 중단은 중단 예정으로 표시하고 종료 필터에서 제외한다', (tester) async {
    final model = await _pumpSelectionApp(tester, initialFilter: 'all');
    final tomorrow = MedicationHistoryDates.today(
      DateTime.now(),
    ).add(const Duration(days: 1));
    await model.replaceMedications([
      _selectionMedication(1).copyWith(stoppedOn: tomorrow),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text('복용 중단 예정 · ${MedicationHistoryDates.format(tomorrow)}'),
      findsOneWidget,
    );
    await _chooseSavedFilter(tester, 'active');
    expect(find.text('약 1'), findsOneWidget);
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('약 1'), findsNothing);
  });

  // Function Name: testWidgets: '마지막 복용일과 오늘 중단은 기기 날짜로 판단한다'
  // Description: Use device-midnight dates for a one-day course and a stop effective today, guarding the server-date regression in zones ahead of UTC such as Asia/Seoul.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; today's last dose is not ended, today's stop is effective rather than scheduled, and only the stopped item appears in the ended filter.
  testWidgets('마지막 복용일과 오늘 중단은 기기 날짜로 판단한다', (tester) async {
    final model = await _pumpSelectionApp(tester, initialFilter: 'all');
    final today = MedicationHistoryDates.today(DateTime.now());
    final localToday = DateTime(today.year, today.month, today.day);
    await model.replaceMedications([
      _selectionMedication(1).copyWith(
        prescriptionDate: localToday,
        createdDate: localToday,
        totalDays: '1',
      ),
      _selectionMedication(2).copyWith(stoppedOn: localToday),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('복용 종료 ·'), findsNothing);
    expect(find.textContaining('복용 중단 예정'), findsNothing);
    expect(
      find.text('복용 중단 · ${MedicationHistoryDates.format(today)}'),
      findsOneWidget,
    );
    await _chooseSavedFilter(tester, 'ended');
    expect(find.text('약 1'), findsNothing);
    expect(find.text('약 2'), findsOneWidget);
  });

  // 함수이름: testWidgets: '복약함 관리 메뉴에서 기록을 지우지 않는 변경 화면을 연다'
  // 함수역할: 약 관리 메뉴의 수정·중단·변경 항목을 차례로 열고 각각 뒤로 이동한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 각 동작이 처방 변경 편집 화면을 열고 뒤로 가면 복약함으로 복귀한다.
  testWidgets('복약함 관리 메뉴에서 기록을 지우지 않는 변경 화면을 연다', (tester) async {
    await _pumpSelectionApp(tester);
    await tester.tap(find.byKey(const Key('saved-medication-actions-1')));
    await tester.pumpAndSettle();
    expect(find.text('정보 수정'), findsOneWidget);
    expect(find.text('처방에 따른 복용 중단'), findsOneWidget);
    expect(find.text('새 처방으로 교체'), findsOneWidget);
    await tester.tap(find.text('정보 수정'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationRegimenEditorUI), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CheckSavedMedicationUI), findsOneWidget);
  });

  // 함수이름: testWidgets: '약 상세를 연속으로 눌러도 한 번 뒤로가면 목록으로 돌아온다'
  // 함수역할: 약 상세를 빠르게 두 번 누른 뒤 한 번 뒤로 이동하고 다시 연다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 상세 경로가 중복되지 않고 복약함 복귀 및 재진입이 가능하다.
  testWidgets('약 상세를 연속으로 눌러도 한 번 뒤로가면 목록으로 돌아온다', (tester) async {
    await _pumpSelectionApp(tester);
    final medication = find.text('약 1');
    await tester.tap(medication);
    // 전환 중 첫 화면 위로 들어오는 두 번째 탭은 무시되어야 한다.
    await tester.tap(medication, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsNothing);
    expect(find.byType(CheckSavedMedicationUI), findsOneWidget);

    await tester.tap(medication);
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: '조회 조건은 현재 값 세 줄로 표시하고 취소하면 기존 조건을 유지한다'
  // 함수역할: 현재 조회 조건·정렬·표시 설정이 있는 필터 창을 연 뒤 취소한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 현재 값 행이 표시되고 복용 중 필터와 기존 약 목록이 유지된다.
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

  // Function Name: testWidgets: '매일 복용하지 않는 약은 다음 복용일을 표시한다'
  // Description: Load daily and non-daily courses against the Korean calendar day and check tomorrow, today, and a four-week course.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; only non-daily rows show the next dose, tomorrow includes its weekday, and four weeks ends 27 days after the start.
  testWidgets('매일 복용하지 않는 약은 다음 복용일을 표시한다', (tester) async {
    await _pumpFilterApp(tester, nonDaily: true);
    // UTC 날짜가 한국 날짜와 다른 시간(한국 0~9시)에도 같은 기준일로 기대값을 만든다.
    final now = _koreaToday();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final tomorrowText =
        '${tomorrow.month.toString().padLeft(2, '0')}/'
        '${tomorrow.day.toString().padLeft(2, '0')} '
        '(${weekdays[tomorrow.weekday - 1]})';

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('saved-medication-next-dose-4')),
              matching: find.byType(Text),
            ),
          )
          .textSpan
          ?.toPlainText(),
      '다음 복용일: $tomorrowText',
    );
    expect(find.text('다음 복용일: 오늘'), findsOneWidget);
    // "4주"는 일정과 같은 규칙으로 28일로 읽는다.
    // Function Name: twoDigits
    // Description: Pad a calendar component for the expected course-date label.
    // Parameters: value (int): Month or day number.
    // Returns: String: Decimal digits padded on the left to at least two characters.
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    // Function Name: fullDate
    // Description: Compose a full calendar-date expectation without time-zone conversion.
    // Parameters: day (DateTime): Calendar date to display.
    // Returns: String: Year, two-digit month, and two-digit day joined by hyphens.
    String fullDate(DateTime day) =>
        '${day.year}-${twoDigits(day.month)}-${twoDigits(day.day)}';
    final end = DateTime(now.year, now.month, now.day + 27);
    final endText = end.year == now.year
        ? '${twoDigits(end.month)}-${twoDigits(end.day)}'
        : fullDate(end);
    expect(find.text('복용기간: ${fullDate(now)} ~ $endText'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('saved-medication-next-dose-1')),
      findsNothing,
    );
  });

  // 함수이름: testWidgets: '검색한 약만 선택하며 검색어를 바꾸면 숨겨진 선택을 비운다'
  // 함수역할: 검색 결과의 약을 선택한 후 검색어를 바꾸고 새로 보이는 약만 선택해 삭제한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 숨겨진 선택이 0개로 초기화되고 최종 삭제 ID는 2 하나다.
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

  // Function Name: testWidgets: '사진 없는 약은 약 아이콘 자리표시이며 빈 검색은 전체 보기로 복구한다'
  // Description: Render medicines without photos, search for an absent name, then recover through Show All.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; a medication placeholder replaces broken-image/close icons, registration dates stay hidden, and clearing the empty search restores the list.
  testWidgets('사진 없는 약은 약 아이콘 자리표시이며 빈 검색은 전체 보기로 복구한다', (tester) async {
    await _pumpSelectionApp(tester);
    expect(
      find.descendant(
        of: find.byType(MedicationThumbnail),
        matching: find.byIcon(Icons.medication_outlined),
      ),
      findsWidgets,
    );
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
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

  // Function Name: testWidgets: '복약함 제목은 뒤로가기가 있는 공통 헤더이다'
  // Description: Render the cabinet as a subordinate page and inspect its shared page header.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the header is not prominent, supplies a back callback, and shows the saved-medicine subtitle.
  testWidgets('복약함 제목은 뒤로가기가 있는 공통 헤더이다', (tester) async {
    await _pumpSelectionApp(tester);
    final header = tester.widget<MedBuddyPageHeader>(
      find.byType(MedBuddyPageHeader),
    );
    expect(header.prominent, isFalse);
    expect(header.onBackRequested, isNotNull);
    expect(find.text('저장한 약과 복용 기간을 확인합니다.'), findsOneWidget);
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

  // 함수이름: 선택 모드 행 누르기 테스트
  // 함수역할: 선택 모드에서 체크박스가 아닌 약 행을 눌러도 선택이 바뀌고 확인 창에 개수와 삭제·취소가 보이는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('선택 모드에서 약 행을 누르면 선택이 바뀌고 삭제 확인에 개수를 표시한다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    await _startSavedSelection(tester);
    expect(find.text('0개 선택'), findsOneWidget);
    await tester.tap(find.text('약 1'));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('saved-medication-checkbox-1')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('약 2'));
    await tester.pumpAndSettle();
    expect(find.text('2개 선택'), findsOneWidget);
    await tester.tap(find.text('약 2'));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.textContaining('선택한 약 1개를 삭제할까요?'), findsOneWidget);
    expect(_dialogButton('취소'), findsOneWidget);
    expect(find.text('아니오'), findsNothing);
    await tester.tap(_dialogButton('취소'));
    await tester.pumpAndSettle();
    expect(model.deletedIds, isEmpty);
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

  // Function Name: testWidgets: '삭제 확인 중 목록이 바뀌면 보이지 않는 ID를 제외한다'
  // Description: Open deletion confirmation for selected rows, then replace the list before confirming.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the deletion rechecks visibility and sends only the still-visible ID 1.
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
    await tester.tap(_dialogButton('삭제'));
    await tester.pumpAndSettle();
    expect(model.deletedIds, [1]);
    expect(
      model.savedMedicationInfoList.map((item) => item.id),
      unorderedEquals([2, 3]),
    );
  });

  // Function Name: testWidgets: '선택 일괄 삭제의 실패 항목은 선택을 유지한다'
  // Description: Use the real view model with one successful delete and one HTTP failure, then confirm a selected batch.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the mixed-result message reports one success and one failure, and the failed row remains selected for retry.
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
          home: CheckSavedMedicationUI(),
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

  // Function Name: testWidgets: '삭제 확인창이 열린 동안에는 삭제 중으로 표시하지 않는다'
  // Description: Hold deletion behind a completer after opening and then confirming the delete dialog.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the busy label is absent during confirmation, appears during the request, and clears after completion.
  testWidgets('삭제 확인창이 열린 동안에는 삭제 중으로 표시하지 않는다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    model.deleteGate = Completer<void>();
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('삭제 중...'), findsNothing);
    await tester.tap(_dialogButton('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('삭제 중...'), findsOneWidget);
    model.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('삭제 중...'), findsNothing);
  });

  // Function Name: testWidgets: '삭제 진행 중에는 조작과 화면 이탈을 막는다'
  // Description: Leave a two-item deletion pending while attempting selection, filtering, back navigation, and a repeated delete.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; controls are disabled, the route and selection mode stay active until completion, and exactly two item requests occur.
  testWidgets('삭제 진행 중에는 조작과 화면 이탈을 막는다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    model.deleteGate = Completer<void>();
    await _startSavedSelection(tester);
    await _toggleSavedAll(tester);
    await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('삭제'));
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
    expect(find.text('약봉투·처방전 등록'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);
    Navigator.of(tester.element(find.text('직접 등록'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-show-all')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건: 전체'), findsOneWidget);
    expect(find.text('종료약'), findsOneWidget);
  });

  for (final language in ['ko', 'en']) {
    // Function Name: testWidgets: '선택과 날짜 정보는 큰 글씨에서도 잘리지 않는다: $language'
    // Description: Use a 320-by-640 viewport and doubled text in each language, then enter selection mode.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; the delete footer stays 280 pixels wide within the viewport and the date remains untruncated in the muted text color without layout exceptions.
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
                (widget.data ?? widget.textSpan?.toPlainText() ?? '')
                    .startsWith(
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

  // Function Name: testWidgets: '첫 조회에 실패하면 빈 복약함 대신 오류와 다시 시도를 표시한다'
  // Description: Fail the initial load and a retry, then clear the injected error and retry again.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; failures show an error/retry rather than an empty cabinet or registration action, and recovery displays the medicines and removes the error.
  testWidgets('첫 조회에 실패하면 빈 복약함 대신 오류와 다시 시도를 표시한다', (tester) async {
    final model = await _pumpSelectionApp(
      tester,
      loadFailure: StateError('저장된 복약 정보 조회 실패 (500): boom'),
    );
    expect(find.text('저장된 복약정보가 없습니다.'), findsNothing);
    expect(find.byKey(const Key('saved-medication-register')), findsNothing);
    expect(find.text('저장된 복약 정보를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.byKey(const Key('saved-medication-select')), findsNothing);

    // 다시 시도도 실패하면 오류 상태를 유지한다.
    await tester.tap(find.byKey(const Key('saved-medication-retry')));
    await tester.pumpAndSettle();
    expect(find.text('저장된 복약 정보를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('저장된 복약정보가 없습니다.'), findsNothing);

    model.control.loadFailure = null;
    await tester.tap(find.byKey(const Key('saved-medication-retry')));
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
    expect(find.byKey(const Key('saved-medication-retry')), findsNothing);
    expect(find.text('저장된 복약 정보를 불러오지 못했습니다.'), findsNothing);
  });

  // Function Name: testWidgets: '표시 중인 목록은 새로 고침이 실패해도 유지한다'
  // Description: Load the cabinet successfully, inject a read error, and refresh the existing list.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the displayed medicine remains and no full-page retry action replaces the list.
  testWidgets('표시 중인 목록은 새로 고침이 실패해도 유지한다', (tester) async {
    final model = await _pumpSelectionApp(tester);
    model.control.loadFailure = StateError('저장된 복약 정보 조회 실패 (500): boom');
    await model.fetchSavedMedicationInfo();
    await tester.pumpAndSettle();
    expect(find.text('약 1'), findsOneWidget);
    expect(find.byKey(const Key('saved-medication-retry')), findsNothing);
  });

  for (final language in ['ko', 'en']) {
    // Function Name: testWidgets: '조회 실패 안내와 다시 시도는 큰 글씨를 수용한다: $language'
    // Description: Render an initial-load error in a 320-by-640 viewport with doubled text for each language.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; the localized failure and retry remain visible, the retry spans x=20 to x=300 within the viewport, and no layout exception occurs.
    testWidgets('조회 실패 안내와 다시 시도는 큰 글씨를 수용한다: $language', (tester) async {
      await _pumpSelectionApp(
        tester,
        language: language,
        textScale: 2,
        small: true,
        loadFailure: StateError('저장된 복약 정보 조회 실패 (500): boom'),
      );
      final retry = find.byKey(const Key('saved-medication-retry'));
      await tester.scrollUntilVisible(
        retry,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('saved-medication-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(retry).bottom, lessThanOrEqualTo(640));
      expect(tester.getRect(retry).left, 20);
      expect(tester.getRect(retry).right, 300);
      expect(
        find.text(
          language == 'en'
              ? 'Could not load saved medication information.'
              : '저장된 복약 정보를 불러오지 못했습니다.',
        ),
        findsOneWidget,
      );
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

  // 함수이름: testWidgets: '빈 저장 목록의 촬영 버튼은 세 가지 약 등록 방식을 제공한다'
  // 함수역할: 빈 목록의 등록 버튼을 열어 약봉투·처방전, 낱알약 식별, 직접 등록 선택지를 확인하고 낱알약 식별을 선택한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 선택 전에는 식별 화면이 없고 선택한 뒤에만 열린다.
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

    expect(find.text('약봉투·처방전 등록'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(find.byType(PillIdentificationUI), findsNothing);
    await tester.tap(find.text('알약 하나씩 찾기'));
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
  });

  // 함수이름: testWidgets: '빈 저장 목록에서 처방전 분석을 선택하면 이미지 출처를 고른다'
  // 함수역할: 빈 복약함에서 등록을 누른 후 약봉투·처방전 등록을 선택한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 카메라 촬영과 갤러리 선택 출처가 함께 표시된다.
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
    await tester.tap(find.text('약봉투·처방전 등록'));
    await tester.pumpAndSettle();

    expect(find.text('카메라로 촬영'), findsOneWidget);
    expect(find.text('갤러리에서 선택'), findsOneWidget);
  });

  // Function Name: testWidgets: 'embedded empty cabinet keeps the root route during gallery input'
  // Description: Mount the empty cabinet inside a root scaffold and cancel the gallery picker after choosing prescription registration.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; one gallery request occurs, the registration page remains open, and the original embedded root stays in the route tree.
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
              body: CheckSavedMedicationUI(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('saved-medication-register')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('약봉투·처방전 등록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리에서 선택'));
      await tester.pumpAndSettle();

      expect(inputPrescription.requestCount, 1);
      expect(
        find.byKey(const Key('medication-registration-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('embedded-cabinet-root'),
          skipOffstage: false,
        ),
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

  // 함수이름: testWidgets: '약 사진 팝업은 작은 화면과 큰 글자에서도 이미지 영역을 제한한다'
  // 함수역할: 작은 화면과 큰 글자 설정에서 저장 약의 사진 버튼을 눌러 확대 창을 연다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 이미지 대화상자와 뷰어가 생성되고 레이아웃 예외가 없다.
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
    await viewModel.saveUserSetting(
      viewModel.userSetting.updateUserSetting(
        fontSize: UserSetting.fontSizeFromOption('medium'),
        readingSpeed: UserSetting.readingSpeedFromOption('medium'),
        language: 'en',
      ),
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
    await tester.tap(_dialogButton('Delete'));
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

  // 함수이름: testWidgets: '영문 저장 목록은 작은 화면과 큰 글자에서도 넘치지 않는다'
  // 함수역할: 320 너비의 작은 화면에 큰 글자 배율과 영어를 적용해 날짜 정렬용 저장 약 목록을 표시한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; Medications 제목이 표시되고 렌더링 예외가 없다.
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
    await viewModel.saveUserSetting(
      viewModel.userSetting.updateUserSetting(
        fontSize: UserSetting.fontSizeFromOption('large'),
        readingSpeed: UserSetting.readingSpeedFromOption('medium'),
        language: 'en',
      ),
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

    expect(find.text('Medications'), findsOneWidget);
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

// 함수이름: _applySavedFilter
// 함수역할: 선택한 조회 조건을 적용하고 시트 종료와 목록 갱신을 기다린다.
// 매개변수: tester (WidgetTester): 조건 적용 버튼을 조작할 테스트 제어기.
// 반환값: Future<void>: 적용 후 화면 안정화 완료.
Future<void> _applySavedFilter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('saved-medication-filter-apply')));
  await tester.pumpAndSettle();
}

// Function Name: _koreaToday
// Description: Take the app's current Korean calendar day and reconstruct it at device-local midnight for date-only fixtures.
// Parameters: None.
// Returns: DateTime: Local midnight with the Korean day's year, month, and day.
DateTime _koreaToday() {
  final day = MedicationHistoryDates.today(DateTime.now());
  return DateTime(day.year, day.month, day.day);
}

// 함수이름: _pumpFilterApp
// 함수역할: 한국 날짜 기준의 진행·종료·예정 약을 제공하는 모의 서버와 화면을 만들고 지정한 조회 상태를 적용한다.
// 매개변수: tester (WidgetTester): 화면 제어기; onlyEnded (bool): 진행·예정 약 제외; nonDaily (bool): 격일·주 1회 약 추가; language (String): 표시 언어; textScale (double): 글자 배율; small (bool): 320x640 화면 사용; initialFilter (String): 초기 조회 조건, all이면 추가 선택 생략.
// 반환값: Future<void>: 목록 로딩과 초기 필터 적용 완료; 테스트 종료 시 화면 크기와 모델을 정리한다.
Future<void> _pumpFilterApp(
  WidgetTester tester, {
  bool onlyEnded = false,
  bool nonDaily = false,
  String language = 'ko',
  double textScale = 1,
  bool small = false,
  String initialFilter = 'active',
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
    // 앱은 기기 시간대와 무관하게 한국 날짜로 판단하므로 기준일도 한국 날짜로 만든다.
    final today = _koreaToday();
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
            'prescription_date': addCalendarDays(today, -30).toIso8601String(),
            'total_days': '7',
          },
          if (nonDaily) ...[
            {
              ..._savedMedicationJson(request, 4, '격일약'),
              'prescription_date': addCalendarDays(today, -1).toIso8601String(),
              'daily_frequency': '격일',
              'total_days': '14',
            },
            {
              ..._savedMedicationJson(request, 5, '주1회약'),
              'prescription_date': today.toIso8601String(),
              'daily_frequency': '주 1회',
              'total_days': '4주',
            },
          ],
          if (!onlyEnded)
            {
              ..._savedMedicationJson(request, 3, '예정약'),
              'prescription_date': addCalendarDays(today, 5).toIso8601String(),
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
  await viewModel.saveUserSetting(
    viewModel.userSetting.updateUserSetting(
      fontSize: UserSetting.fontSizeFromOption('large'),
      readingSpeed: UserSetting.readingSpeedFromOption('medium'),
      language: language,
    ),
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
  // 기존 필터별 회귀 검사는 상태를 명시적으로 선택해 시작한다.
  if (initialFilter != 'all') await _chooseSavedFilter(tester, initialFilter);
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
// 역할: 실제 ViewModel의 목록·선택 삭제·중단 흐름을 외부 통신 없이 제어한다.
// 주요 책임: 목록 복사 또는 조회 오류를 반환하고 삭제 대기·요청 ID·중단 효력일 갱신을 재현한다.
// 속성: medications: 응답 약 목록; deletedIds: 삭제 요청 기록; deleteGate: 삭제 완료 대기 신호; loadFailure: 주입할 조회 오류.
class _SelectionTestControl extends CheckSavedMedication {
  List<MedicationDetail> medications;
  final List<int> deletedIds = [];
  Completer<void>? deleteGate;
  // 값이 있으면 목록 조회가 이 오류로 실패한다.
  Object? loadFailure;

  // 함수이름: _SelectionTestControl
  // 함수역할: 외부 요청 없는 조회 목록을 받는다. 매개변수: medications. 반환값: 테스트 제어기.
  _SelectionTestControl(this.medications);

  // 함수이름: changeRegimen
  // 함수역할: 대상 약의 중단일을 요청 효력일로 바꾸고 고정 개정 번호로 처방 변경 성공을 재현한다.
  // 매개변수: medicationId (int): 변경할 약 ID; change (MedicationRegimenChange): 적용할 효력일을 담은 요청.
  // 반환값: Future<MedicationRegimenResult>: 요청 ID와 revision 1; 일치하는 약이 없어도 같은 성공 결과를 반환한다.
  @override
  Future<MedicationRegimenResult> changeRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) async {
    medications = [
      for (final medication in medications)
        if (medication.id == medicationId)
          medication.copyWith(
            stoppedOn: change.effectiveDate,
            regimenRevision: 1,
          )
        else
          medication,
    ];
    return MedicationRegimenResult(medicationId: medicationId, revision: 1);
  }

  // Function Name: requestSavedMedicationInfo
  // Description: Return an unparsed copy of the fixture list so invalid IDs reach UI validation, or throw the injected load failure.
  // Parameters: None.
  // Returns: Future<List<MedicationDetail>>: A new list containing the fixture items; fails with loadFailure when set.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    final failure = loadFailure;
    if (failure != null) throw failure;
    return List<MedicationDetail>.from(medications);
  }

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
MedicationDetail _selectionMedication(int? id, {int offsetDays = 0}) {
  final now = DateTime.now();
  return MedicationDetail(
    id: id,
    itemName: '약 $id',
    efficacy: '',
    usageMethod: '',
    warning: '',
    createdDate: now,
    prescriptionDate: addCalendarDays(now, offsetDays),
    totalDays: '14',
  );
}

// Function Name: _pumpSelectionApp
// Description: Mount a controllable selection fixture as a root or pushed route, with optional bad IDs, loading failure, and accessibility settings.
// Parameters: tester (WidgetTester): Test harness; invalidIds (bool): Include null/zero/negative IDs; submenu (bool): Push from a parent page; language (String): Locale; textScale (double): Text multiplier; small (bool): Use 320x640; loadFailure (Object?): Inject an initial read error; home (Widget?): Override the root host; initialFilter (String): Filter applied unless all, a load error, or a custom home prevents it.
// Returns: Future<_SelectionTestViewModel>: Mounted model for later list changes and deletion inspection; teardown restores viewport settings and disposes it.
Future<_SelectionTestViewModel> _pumpSelectionApp(
  WidgetTester tester, {
  bool invalidIds = false,
  bool submenu = false,
  String language = 'ko',
  double textScale = 1,
  bool small = false,
  Object? loadFailure,
  Widget? home,
  String initialFilter = 'active',
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
  model.control.loadFailure = loadFailure;
  await model.saveUserSetting(
    model.userSetting.updateUserSetting(
      fontSize: UserSetting.fontSizeFromOption('medium'),
      readingSpeed: UserSetting.readingSpeedFromOption('medium'),
      language: language,
    ),
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
            : home ?? const CheckSavedMedicationUI(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (submenu) {
    await tester.tap(find.text('목록 열기'));
    await tester.pumpAndSettle();
  }
  if (initialFilter != 'all' && loadFailure == null && home == null) {
    await _chooseSavedFilter(tester, initialFilter);
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

// Function Name: _dialogButton
// Description: Restrict a text finder to dialog descendants so similarly labeled page controls are not tapped.
// Parameters: label (String): Exact visible dialog text.
// Returns: Finder: Matching text descendants of Dialog widgets.
Finder _dialogButton(String label) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(label));

// Function Name: _deleteSavedSelection
// Description: Request deletion of the selected rows and accept the Korean confirmation dialog.
// Parameters: tester (WidgetTester): Harness with a mounted, selected cabinet.
// Returns: Future<void>: Both taps and ensuing frame settling complete.
Future<void> _deleteSavedSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('saved-medication-delete-selected')));
  await tester.pumpAndSettle();
  await tester.tap(_dialogButton('삭제'));
  await tester.pumpAndSettle();
}

// 함수이름: _openFilterRow
// 함수역할: 현재 값 행을 화면 안으로 스크롤한 뒤 눌러 조건 선택창을 연다.
// 매개변수: tester (WidgetTester): 화면 제어기; row (String): saved-medication-$row-row 키에 들어갈 조건 식별자.
// 반환값: Future<void>: 선택창의 화면 안정화 완료.
Future<void> _openFilterRow(WidgetTester tester, String row) async {
  final finder = find.byKey(ValueKey('saved-medication-$row-row'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
