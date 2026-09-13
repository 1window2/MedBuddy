// 파일명: prescription_analysis_preview_ui_boundary_test.dart
// 역할: OCR 미리보기, 개인정보 마스킹, 복약 정보 표 수정과 분석 이동을 검증한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for OCR preview masking, correction limits, missing rows, and partial
//   review.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: OCR 영역을 표시하고 확대 화면에서 개인정보 처리를 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('OCR 영역을 표시하고 확대 화면에서 개인정보 처리를 안내한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    var analysisRequested = false;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'medbuddy-ocr-preview-test-',
    );
    final imageFile = File('${tempDirectory.path}/prescription.png');
    // 함수이름: addTearDown 콜백
    // 함수역할:
    // - 미리보기 이미지 캐시를 비우고 테스트 임시 이미지 폴더를 정리한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 임시 파일 정리 완료.
    addTearDown(() {
      imageCache.evict(FileImage(imageFile));
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
        'nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: [
            MedicationSchedule(
              medicationName: '테스트정',
              prescriptionDate: DateTime(2026, 8, 23),
              dosage: '1정',
              intakeTime: '2회',
              medicationTime: 3,
              scheduleSlotKeys: ['morning', 'evening'],
            ),
          ],
          recognizedTextRegions: const [
            RecognizedTextRegion(
              category: 'medication_row',
              text: '테스트정 1정 1일 2회',
              box2d: [100, 80, 260, 920],
            ),
            RecognizedTextRegion(
              category: 'sensitive_info',
              text: '',
              box2d: [20, 40, 80, 400],
            ),
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '일반 복약 안내 문구',
              box2d: [300, 80, 360, 920],
            ),
          ],
          previewImagePath: imageFile.path,
          userSetting: const UserSetting(),
          // 함수이름: onBackRequested 콜백
          // 함수역할:
          // - 뒤로가기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onBackRequested: () {},
          // 함수이름: onAnalysisRequested 콜백
          // 함수역할:
          // - 약 상세 분석 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onAnalysisRequested: () => analysisRequested = true,
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('ocr-region-0')), findsOneWidget);
    expect(find.byKey(const Key('ocr-sensitive-region-1')), findsOneWidget);
    expect(find.byKey(const Key('ocr-region-2')), findsNothing);
    expect(find.textContaining('개인정보 마스킹 영역'), findsOneWidget);
    expect(find.textContaining('인식 문구:'), findsNothing);
    expect(find.textContaining('서버 DB에는 저장하지 않습니다'), findsNothing);
    expect(find.byKey(const Key('ocr-image-canvas')), findsOneWidget);
    expect(find.byKey(const Key('ocr-medication-table')), findsOneWidget);
    expect(find.byKey(const Key('ocr-table-scroll-hint')), findsOneWidget);
    expect(find.text('약 이름'), findsOneWidget);
    expect(find.text('1회 투약량'), findsOneWidget);
    expect(find.text('1일 횟수'), findsOneWidget);
    expect(find.text('총 투약일'), findsOneWidget);
    expect(find.text('복용 시작일'), findsOneWidget);
    expect(find.text('실제 복약 시간대'), findsOneWidget);
    expect(
      find.byKey(const Key('prescription-analyze-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('ocr-preview-image')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('ocr-expanded-image-viewer')), findsOneWidget);
    expect(
      find.byKey(const Key('ocr-expanded-sensitive-region-1')),
      findsOneWidget,
    );
    expect(find.text('인식 영역 상세보기'), findsOneWidget);
    expect(find.textContaining('원본 이미지는 이 기기에만 남습니다'), findsOneWidget);
    final interactiveViewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('ocr-expanded-image-viewer')),
    );
    expect(interactiveViewer.maxScale, 5);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('ocr-expanded-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('ocr-expanded-image-viewer')), findsNothing);

    await tester.tap(find.byKey(const Key('prescription-analyze-button')));
    await tester.pumpAndSettle();
    expect(find.text('복약 정보 확인'), findsNothing);
    expect(analysisRequested, isTrue);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 수정된 약명과 큰 글씨에서도 OCR 미리보기 행이 넘치지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('corrected medication rows fit the preview at large text size', (
    tester,
  ) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ocr-medication-table')), findsOneWidget);
    expect(find.textContaining('+1'), findsNothing);
    expect(find.byKey(const Key('ocr-table-cell-4-name')), findsOneWidget);

    final tableScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('ocr-medication-table-scroll')),
    );
    expect(tableScroll.scrollDirection, Axis.horizontal);
    expect(tableScroll.controller?.offset, 0);
    await tester.drag(
      find.byKey(const Key('ocr-medication-table-scroll')),
      const Offset(-420, 0),
    );
    await tester.pumpAndSettle();
    expect(tableScroll.controller?.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 작은 화면에서도 미리보기 카드의 내용을 스크롤할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('preview card remains scrollable on a compact viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          );
        },
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final verticalScroll = find.byWidgetPredicate(
      // 함수이름: byWidgetPredicate 콜백
      // 함수역할:
      // - 세로 스크롤이 가능한 미리보기 영역만 찾도록 위젯 종류와 방향을 검사한다.
      // 매개변수:
      // - widget (Widget): 탐색 조건으로 검사할 후보 위젯.
      // 반환값:
      // - 세로 SingleChildScrollView이면 true.
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalScroll.first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 검토 필요 배지와 수정 버튼이 있는 네 행이 넘치지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('검토 필요 배지와 수정 버튼이 있는 네 행이 넘치지 않는다', (tester) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: List.generate(
            4,
            // 함수이름: generate 콜백
            // 함수역할:
            // - 미확인 표시와 순번별 긴 약명이 있는 OCR 행을 만들어 배지·수정 버튼 배치를 검사한다.
            // 매개변수:
            // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번.
            // 반환값:
            // - 검토 필요 상태의 MedicationSchedule.
            (index) => MedicationSchedule(
              medicationName: '검토가 필요한 긴 약 이름 ${index + 1}',
              intakeTime: '${index + 1}',
              nameCorrectionSource: 'unverified',
            ),
          ),
          userSetting: const UserSetting(),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('검토 필요'), findsNWidgets(4));
    expect(find.byKey(const Key('ocr-table-cell-3-name')), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: OCR 수정값을 콜백으로 전달한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('OCR 수정값을 콜백으로 전달한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    MedicationSchedule? updatedSchedule;
    var updatedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '에니코프캡슐',
              dosage: '1정',
              intakeTime: '1일 3회',
              medicationTime: 4,
              nameCorrectionSource: 'unverified',
            ),
          ],
          userSetting: const UserSetting(),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - 수정한 OCR 행의 위치와 새 일정을 기록한다.
          // 매개변수:
          // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번.
          // - schedule (MedicationSchedule): 화면에서 전달하거나 수정한 복약 일정.
          // 반환값:
          // - 없음; 수정 행 인덱스와 일정이 저장된다.
          onMedicationScheduleChanged: (index, schedule) {
            updatedIndex = index;
            updatedSchedule = schedule;
          },
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('ocr-table-cell-0-name')));
    await tester.pumpAndSettle();
    final nameCell = find.byKey(const Key('ocr-table-cell-0-name'));
    await tester.tapAt(tester.getTopLeft(nameCell) + const Offset(24, 18));
    await tester.pumpAndSettle();
    expect(find.text('OCR 인식 결과 수정'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ocr-edit-name')), '애니코프캡슐');
    await tester.enterText(find.byKey(const Key('ocr-edit-dosage')), '0.5정');
    await tester.enterText(
      find.byKey(const Key('ocr-edit-frequency')),
      '1일 2회',
    );
    await tester.enterText(find.byKey(const Key('ocr-edit-days')), '5');
    await tester.enterText(
      find.byKey(const Key('ocr-edit-prescription-date')),
      '2026-08-01',
    );
    for (final slotKey in const ['lunch', 'evening', 'bedtime']) {
      final slot = find.byKey(Key('ocr-edit-slot-$slotKey'));
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
    }
    final saveButton = find.byKey(const Key('ocr-edit-save'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(updatedIndex, 0);
    expect(updatedSchedule?.medicationName, '애니코프캡슐');
    expect(updatedSchedule?.dosage, '0.5정');
    expect(updatedSchedule?.intakeTime, '1일 2회');
    expect(updatedSchedule?.medicationTime, 5);
    expect(updatedSchedule?.prescriptionDate, DateTime(2026, 8, 1));
    expect(updatedSchedule?.scheduleSlotKeys, ['morning', 'bedtime']);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: OCR 수정 입력의 길이와 총 투약일 숫자를 제한한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('OCR 수정 입력의 길이와 총 투약일 숫자를 제한한다', (tester) async {
    await _setViewport(tester, const Size(320, 560));

    await tester.pumpWidget(
      MaterialApp(
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
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '테스트정',
              dosage: '1정',
              intakeTime: '1일 3회',
              medicationTime: 3,
            ),
          ],
          userSetting: const UserSetting(),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('ocr-table-cell-0-name')));
    await tester.pumpAndSettle();
    final nameCell = find.byKey(const Key('ocr-table-cell-0-name'));
    await tester.tapAt(tester.getTopLeft(nameCell) + const Offset(24, 18));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ocr-edit-dosage')),
      List.filled(50, '가').join(),
    );
    await tester.enterText(
      find.byKey(const Key('ocr-edit-frequency')),
      List.filled(50, '나').join(),
    );
    await tester.enterText(find.byKey(const Key('ocr-edit-days')), '12일345');
    await tester.pump();

    final dosageField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-dosage')),
    );
    final frequencyField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-frequency')),
    );
    final daysField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-days')),
    );
    expect(dosageField.controller?.text.length, 40);
    expect(frequencyField.controller?.text.length, 40);
    expect(daysField.controller?.text, '1234');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 직접 입력한 조제일자도 달력과 같은 허용 범위를 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('직접 입력한 조제일자도 달력과 같은 허용 범위를 검증한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    MedicationSchedule? updatedSchedule;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '테스트정',
              dosage: '1정',
              intakeTime: '1일 1회',
              medicationTime: 3,
            ),
          ],
          userSetting: const UserSetting(),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - 날짜 검증을 통과한 수정 일정을 기록한다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - schedule (MedicationSchedule): 화면에서 전달하거나 수정한 복약 일정.
          // 반환값:
          // - 없음; 수정 일정이 저장된다.
          onMedicationScheduleChanged: (_, schedule) {
            updatedSchedule = schedule;
          },
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('ocr-table-cell-0-date')));
    await tester.tap(find.byKey(const Key('ocr-table-cell-0-date')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ocr-edit-prescription-date')),
      '1999-12-31',
    );
    final saveButton = find.byKey(const Key('ocr-edit-save'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(updatedSchedule, isNull);
    expect(find.text('2000-01-01부터 오늘 기준 1년 이내 날짜를 입력해주세요.'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Verify that a medication omitted by OCR can be added directly to the review table.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('OCR에서 누락된 약을 표에 직접 추가한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    MedicationSchedule? addedSchedule;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: [
            MedicationSchedule(
              medicationName: '기존약',
              prescriptionDate: DateTime(2026, 8, 25),
              prescriptionBatchId: 'batch_20260825_alpha',
              dosage: '1정',
              intakeTime: '2회',
              medicationTime: 4,
              scheduleSlotKeys: const ['morning', 'evening'],
            ),
          ],
          userSetting: const UserSetting(),
          // Function Name: onBackRequested callback
          // Description:
          // - Keep back navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onBackRequested: () {},
          // Function Name: onAnalysisRequested callback
          // Description:
          // - Keep medication analysis available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onAnalysisRequested: () {},
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
          // 함수이름: onMedicationScheduleAdded 콜백
          // 함수역할:
          // - 사용자가 추가한 OCR 누락 약 일정을 기록한다.
          // 매개변수:
          // - schedule (MedicationSchedule): 화면에서 전달하거나 수정한 복약 일정.
          // 반환값:
          // - 추가된 일정; 호출자는 기록된 값으로 입력 내용을 검사한다.
          onMedicationScheduleAdded: (schedule) => addedSchedule = schedule,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    final addButton = find.byKey(const Key('ocr-add-medication-button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('누락된 약 추가'), findsWidgets);
    await tester.enterText(find.byKey(const Key('ocr-edit-name')), '수동추가약');
    await tester.enterText(find.byKey(const Key('ocr-edit-dosage')), '0.5정');
    await tester.enterText(find.byKey(const Key('ocr-edit-frequency')), '3회');
    final saveButton = find.byKey(const Key('ocr-edit-save'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(addedSchedule?.medicationName, '수동추가약');
    expect(addedSchedule?.dosage, '0.5정');
    expect(addedSchedule?.intakeTime, '3회');
    expect(addedSchedule?.medicationTime, 4);
    expect(addedSchedule?.prescriptionDate, DateTime(2026, 8, 25));
    expect(addedSchedule?.prescriptionBatchId, 'batch_20260825_alpha');
    expect(addedSchedule?.nameCorrectionSource, 'manual_add');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 조회 완료 약은 잠그고 미확인 약만 수정해 다시 조회한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('조회 완료 약은 잠그고 미확인 약만 수정해 다시 조회한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    var retryRequested = false;
    var continueRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(medicationName: '확인된약'),
            MedicationSchedule(medicationName: '미확인약'),
          ],
          userSetting: const UserSetting(),
          // 함수이름: onBackRequested 콜백
          // 함수역할:
          // - 뒤로가기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onBackRequested: () {},
          // 함수이름: onAnalysisRequested 콜백
          // 함수역할:
          // - 약 상세 분석 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onAnalysisRequested: () => retryRequested = true,
          // 함수이름: onMedicationScheduleChanged 콜백
          // 함수역할:
          // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
          // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onMedicationScheduleChanged: (_, _) {},
          verifiedScheduleIndexes: const {0},
          isMedicationLookupReview: true,
          // 함수이름: onVerifiedOnlyContinueRequested 콜백
          // 함수역할:
          // - 확인된 약만으로 계속 진행 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onVerifiedOnlyContinueRequested: () => continueRequested = true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.textContaining('공공데이터에서 확인하지 못했습니다'), findsOneWidget);
    expect(find.text('확인됨'), findsOneWidget);
    final verifiedName = tester.widget<Text>(find.text('확인된약'));
    expect(verifiedName.style?.decoration, TextDecoration.lineThrough);

    await tester.tap(find.byKey(const Key('ocr-table-cell-0-name')));
    await tester.pumpAndSettle();
    expect(find.text('OCR 인식 결과 수정'), findsNothing);

    await tester.tap(find.byKey(const Key('ocr-table-cell-1-name')));
    await tester.pumpAndSettle();
    expect(find.text('OCR 인식 결과 수정'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-edit-cancel')));
    await tester.pumpAndSettle();

    final retryButton = find.byKey(const Key('prescription-analyze-button'));
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pump();
    expect(retryRequested, isTrue);

    final continueButton = find.byKey(
      const Key('continue-with-verified-medications'),
    );
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('미확인 약을 제외할까요?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-verified-only-continue')));
    await tester.pumpAndSettle();
    expect(continueRequested, isTrue);
    expect(tester.takeException(), isNull);
  });
}

// Function Name: _setViewport
// Description:
// - Apply a logical viewport at unit pixel ratio and register restoration after the test.
// Parameters:
// - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
// - size (Size): Logical viewport dimensions used for layout checks.
// Returns:
// - Completion after setting the test viewport.
Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

// Function Name: _correctedSchedules
// Description:
// - Build five corrected OCR rows with retained original names and alternating dose frequencies.
// Parameters:
// - None.
// Returns:
// - A fixed-length list of corrected medication schedules.
List<MedicationSchedule> _correctedSchedules() {
  return List.generate(
    5,
    // Function Name: generate callback
    // Description:
    // - Build a corrected OCR row retaining its original name and alternating two/three-dose frequency.
    // Parameters:
    // - index (int): Zero-based row or generated fixture position.
    // Returns:
    // - The indexed corrected MedicationSchedule.
    (index) => MedicationSchedule(
      medicationName: 'Corrected medication name ${index + 1}',
      rawMedicationName: 'OCR medication ${index + 1}',
      nameCorrectionSource: 'local_catalog_prefix',
      intakeTime: '${index.isEven ? 3 : 2}회',
    ),
    growable: false,
  );
}
