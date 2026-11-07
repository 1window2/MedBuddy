// 파일명: prescription_medication_cards_test.dart
// 역할: 처방전 카드의 후보 버튼 위치·세로 배치·큰 글씨와 원문 숨김을 검증한다.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_progress_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 테스트 자료: _candidate
// 역할: 두 검토 카드가 공유하는 약품 후보로, 확정 여부와 후보 창 취소를 검사한다.

const _candidate = MedicationDetail(
  itemName: '시험약 A',
  manufacturer: '시험 제약',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

// 함수이름: main
// 함수역할: 처방 검토 카드의 접기·후보 선택·조회 상태·접근성과 분석 진행 애니메이션 검증을 등록한다.
// 매개변수: 없음.
// 반환값: void: 공통 글꼴 준비와 각 테스트를 등록한다.
void main() {
  // 함수이름: testWidgets: 'review details start open and candidate action survives folding'
  // 함수역할: 후보 검토 카드가 열린 상태에서 시작해 접은 채 후보 창을 취소하고 용량이 바뀐 화면으로 갱신한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 후보 버튼은 접혀도 동작하고 확정 콜백은 호출되지 않으며 접힘이 유지된 뒤 펼치면 변경 용량 2정이 보인다.
  testWidgets(
    'review details start open and candidate action survives folding',
    (tester) async {
      var candidateRequests = 0;
      // 함수이름: preview
      // 함수역할: 같은 약 카드와 후보 목록을 유지하면서 용량만 바꿀 수 있는 검토 화면을 만든다.
      // 매개변수: updated (bool): true이면 용량 2정, 아니면 1정.
      // 반환값: Widget: 후보 확정 횟수를 기록하는 MaterialApp.
      Widget preview({bool updated = false}) => MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          userSetting: const UserSetting(),
          medicationScheduleList: [
            MedicationSchedule(
              medicationName: '시험약 A',
              dosage: updated ? '2정' : '1정',
            ),
          ],
          isMedicationLookupReview: true,
          matchReviews: {
            0: MedicationMatchReview([_candidate]),
          },
          onCandidateConfirmed: (_, _) => candidateRequests++,
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
        ),
      );
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      final table = find.byKey(const Key('ocr-medication-summary-0'));
      final toggle = find.byKey(const Key('ocr-medication-toggle-0'));
      expect(table, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(table, findsNothing);
      final candidates = find.byKey(const Key('medication-candidates-0'));
      expect(candidates.hitTestable(), findsOneWidget);
      await tester.tap(candidates);
      await tester.pumpAndSettle();
      expect(find.text('약 이름: 시험약 A'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(candidateRequests, 0);
      await tester.pumpWidget(preview(updated: true));
      await tester.pumpAndSettle();
      expect(table, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(table, findsOneWidget);
      expect(find.text('2정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: setUpAll
  // 함수역할: 환경 변수로 지정한 글꼴을 여러 테스트 글꼴 이름으로 등록하고 Material 아이콘 글꼴을 준비한다.
  // 매개변수: 없음; MEDBUDDY_TEST_FONT 환경 변수의 파일 경로를 읽는다.
  // 반환값: Future<void>: 변수가 없으면 즉시 종료하며 파일·에셋 읽기나 글꼴 로딩 실패는 테스트 준비 오류로 전파한다.
  setUpAll(() async {
    final font = Platform.environment['MEDBUDDY_TEST_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in ['Roboto', 'Noto Sans KR', 'Arial', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final english in [false, true]) {
    // 함수이름: testWidgets: '필요시 복용은 2x2 표의 시간대 칸에 표시한다 english=$english'
    // 함수역할: 한국어·영어에서 필요시 복용 약 하나를 검토 표에 표시한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 시간대 칸에 필요시 문구가 있고 별도 횟수 칸·비매일 복용 배지는 없으며 렌더링 예외가 없다.
    testWidgets('필요시 복용은 2x2 표의 시간대 칸에 표시한다 english=$english', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionAnalysisPreviewUI(
            userSetting: UserSetting(language: english ? 'en' : 'ko'),
            medicationScheduleList: const [
              MedicationSchedule(
                medicationName: '시험용 필요시 약',
                dosage: '1정',
                dosingMode: 'as_needed',
              ),
            ],
            onBackRequested: () {},
            onAnalysisRequested: () {},
            onMedicationScheduleChanged: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final slots = find.byKey(const Key('ocr-table-cell-0-slots'));
      expect(
        find.descendant(
          of: slots,
          matching: find.text(english ? 'As needed' : '필요시 복용'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ocr-table-cell-0-frequency')), findsNothing);
      expect(find.byKey(const Key('ocr-table-not-daily-0')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    for (final large in [false, true]) {
      // 함수이름: testWidgets: 'lookup statuses and two digit numbers fit english=$english large=$large'
      // 함수역할: 한국어·영어와 보통·큰 글씨 조합으로 12개 약에 조회 상태별 문구·색·배경을 배치한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 반환값 없음; 이력 없는 행은 흰 배경이며 상태 배지가 없고 각 상태 배지는 카드 폭 안에 들어가며 마지막 번호 12가 잘 표시된다.
      testWidgets(
        'lookup statuses and two digit numbers fit english=$english large=$large',
        (tester) async {
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final statuses = MedicationLookupStatus.values;
          final labels = english
              ? [
                  'Medicine found',
                  'Check candidates',
                  'No match found',
                  'Lookup failed',
                  'Lookup needed',
                ]
              : ['약품 확인됨', '후보 확인 필요', '약품을 찾지 못함', '조회 실패', '다시 조회 필요'];
          final colors = [
            MedBuddyColors.primaryDark,
            MedBuddyColors.reminderAccent,
            MedBuddyColors.textMuted,
            MedBuddyColors.danger,
            MedBuddyColors.infoBlue,
          ];
          final backgrounds = [
            MedBuddyColors.successSurface,
            MedBuddyColors.warningSurface,
            MedBuddyColors.surfaceSubtle,
            MedBuddyColors.dangerSurface,
            MedBuddyColors.lavenderSurface,
          ];
          await tester.pumpWidget(
            MaterialApp(
              theme: MedBuddyTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: PrescriptionAnalysisPreviewUI(
                userSetting: UserSetting(language: english ? 'en' : 'ko'),
                medicationScheduleList: List.generate(
                  12,
                  (index) => MedicationSchedule(
                    medicationName: english
                        ? 'Test medicine $index 100 mg'
                        : '시험약 $index 100밀리그램',
                    dosage: '1정',
                    prescriptionDate: DateTime(2026, 1, 1),
                  ),
                ),
                isMedicationLookupReview: true,
                lookupStatuses: {
                  for (var i = 0; i < statuses.length; i++) i + 1: statuses[i],
                },
                onBackRequested: () {},
                onAnalysisRequested: () {},
                onMedicationScheduleChanged: (_, _) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          // 조회 이력이 없는 행을 검색 실패나 결과 없음으로 단정하지 않는다.
          expect(find.byKey(const Key('ocr-lookup-status-0')), findsNothing);
          expect(
            tester
                .widget<Material>(
                  find.byKey(const Key('ocr-medication-card-0')),
                )
                .color,
            Colors.white,
          );
          for (var i = 0; i < statuses.length; i++) {
            final badge = find.byKey(Key('ocr-lookup-status-${i + 1}'));
            final text = find.descendant(
              of: badge,
              matching: find.text(labels[i]),
            );
            expect(text, findsOneWidget);
            expect(tester.widget<Text>(text).style?.color, colors[i]);
            expect(
              tester
                  .widget<Material>(
                    find.byKey(Key('ocr-medication-card-${i + 1}')),
                  )
                  .color,
              backgrounds[i],
            );
            final rect = tester.getRect(badge);
            final header = tester.getRect(
              find.byKey(Key('ocr-medication-card-${i + 1}')),
            );
            expect(rect.left, greaterThanOrEqualTo(header.left));
            expect(rect.right, lessThanOrEqualTo(header.right));
          }
          final number = find.byKey(const Key('ocr-medication-number-11'));
          await tester.ensureVisible(number);
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(number).data, '12');
          expect(tester.takeException(), isNull);
        },
      );

      // 함수이름: testWidgets: 'vertical medication cards and inline candidates english=$english large=$large'
      // 함수역할: 긴 약명과 보정 원문, 미확정·확정 후보를 가진 두 카드를 언어·글자 크기별로 렌더링하고 후보 창을 취소한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 반환값 없음; 번호·편집·접기·상태 정렬과 2열 정보 표가 화면 안에 맞고 원문·확정 약 후보 버튼은 숨겨지며 취소는 후보를 확정하지 않는다. 선택적 미리보기 환경에서는 골든도 비교한다.
      testWidgets(
        'vertical medication cards and inline candidates english=$english large=$large',
        (tester) async {
          final size = Size(large ? 320 : 390, 844);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          MedicationDetail? chosen;
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: MedBuddyTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: PrescriptionAnalysisPreviewUI(
                userSetting: UserSetting(language: english ? 'en' : 'ko'),
                medicationScheduleList: [
                  MedicationSchedule(
                    medicationName: english
                        ? 'Example medication with a long name 100 mg'
                        : '시험용 긴 이름 약품 100밀리그램',
                    rawMedicationName: 'OCR-RAW-NOT-DISPLAYED',
                    nameCorrectionSource: 'llm_catalog_candidate',
                    dosage: '1정',
                    intakeTime: '3회',
                    medicationTime: 5,
                    prescriptionDate: DateTime(2026, 10, 20),
                    scheduleSlotKeys: ['morning', 'lunch', 'evening'],
                  ),
                  const MedicationSchedule(
                    medicationName: '시험약 B',
                    dosage: '1정',
                  ),
                ],
                isMedicationLookupReview: true,
                verifiedScheduleIndexes: const {1},
                lookupStatuses: const {
                  0: MedicationLookupStatus.candidates,
                  1: MedicationLookupStatus.verified,
                },
                matchReviews: {
                  0: MedicationMatchReview([_candidate]),
                  1: MedicationMatchReview([_candidate]),
                },
                onCandidateConfirmed: (index, detail) {
                  expect(index, 0);
                  chosen = detail;
                },
                onBackRequested: () {},
                onAnalysisRequested: () {},
                onMedicationScheduleChanged: (_, _) {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final cards = find.byKey(const Key('ocr-medication-list'));
          expect(
            find.descendant(of: cards, matching: find.byType(Table)),
            findsNWidgets(4),
          );
          expect(find.text(english ? 'Review' : '검토 필요'), findsNothing);
          expect(find.text(english ? 'Corrected' : '보정'), findsNothing);
          expect(
            find.descendant(
              of: cards,
              matching: find.text(english ? 'Check candidates' : '후보 확인 필요'),
            ),
            findsOneWidget,
          );
          for (var index = 0; index < 2; index++) {
            final number = find.byKey(Key('ocr-medication-number-$index'));
            expect(tester.widget<Text>(number).data, '${index + 1}');
            final pencil = find.descendant(
              of: find.byKey(Key('ocr-medication-edit-$index')),
              matching: find.byIcon(Icons.edit_outlined),
            );
            final toggle = find.byKey(Key('ocr-medication-toggle-$index'));
            final badge = find.byKey(Key('ocr-lookup-status-$index'));
            expect(
              tester.getCenter(pencil).dy,
              closeTo(tester.getCenter(toggle).dy, .1),
            );
            expect(
              tester.getCenter(badge).dy,
              closeTo(tester.getCenter(toggle).dy, .1),
            );
            expect(
              tester.getRect(number).right,
              lessThan(tester.getRect(pencil).left),
            );
            final name = find.byKey(Key('ocr-medication-name-$index'));
            expect(
              tester.getRect(number).right,
              lessThan(tester.getRect(name).left),
            );
            expect(
              tester.getRect(number).top,
              closeTo(tester.getRect(name).top + 2, .1),
            );
          }
          expect(
            find.descendant(
              of: cards,
              matching: find.text(english ? 'Medicine found' : '약품 확인됨'),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('OCR-RAW-NOT-DISPLAYED'), findsNothing);
          expect(
            find.byKey(const Key('medication-candidates-1')),
            findsNothing,
          );
          final button = find.byKey(const Key('medication-candidates-0'));
          expect(
            find.descendant(
              of: find.byKey(const Key('ocr-medication-card-0')),
              matching: button,
            ),
            findsOneWidget,
          );
          expect(
            tester.getRect(button).bottom,
            lessThan(
              tester
                  .getRect(find.byKey(const Key('ocr-table-cell-0-dosage')))
                  .top,
            ),
          );
          expect(
            tester.widget<Text>(find.text('시험약 B')).style?.decoration,
            isNull,
          );
          for (final field in ['name', 'dosage', 'days', 'date', 'slots']) {
            final finder = find.byKey(Key('ocr-table-cell-0-$field'));
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          if (!large) {
            // 함수이름: fieldRect
            // 함수역할: 첫 번째 약의 지정 정보 칸을 찾아 정렬 검증용 화면 좌표를 읽는다.
            // 매개변수: name (String): ocr-table-cell-0 키에 붙일 필드 이름.
            // 반환값: Rect: 해당 위젯의 경계; 찾기 조건이 단일 위젯을 가리키지 않으면 테스트가 실패한다.
            Rect fieldRect(String name) =>
                tester.getRect(find.byKey(Key('ocr-table-cell-0-$name')));
            expect(fieldRect('dosage').center.dy, fieldRect('days').center.dy);
            expect(fieldRect('date').center.dy, fieldRect('slots').center.dy);
            expect(
              fieldRect('date').top - fieldRect('dosage').top,
              lessThan(english ? 150 : 100),
            );
            final name = find.text(
              english
                  ? 'Example medication with a long name 100 mg'
                  : '시험용 긴 이름 약품 100밀리그램',
            );
            expect(name, findsOneWidget);
            expect(
              fieldRect('dosage').width,
              closeTo(fieldRect('days').width, .01),
            );
            expect(fieldRect('date').width, fieldRect('slots').width);
            final dosage = find.descendant(
              of: find.byKey(const Key('ocr-table-cell-0-dosage')),
              matching: find.byType(Text),
            );
            for (final value in tester.widgetList<Text>(dosage)) {
              expect(value.textAlign, TextAlign.center);
            }
          }
          expect(
            find.byKey(const Key('ocr-table-cell-0-frequency')),
            findsNothing,
          );
          for (final table in tester.widgetList<Table>(
            find.descendant(of: cards, matching: find.byType(Table)),
          )) {
            expect(table.children.single.children, hasLength(2));
          }
          final continueButton = find.byKey(
            const Key('prescription-analyze-button'),
          );
          final continueLabel = find.descendant(
            of: continueButton,
            matching: find.byType(Text),
          );
          expect(
            tester.getRect(continueLabel).height,
            lessThanOrEqualTo(tester.getRect(continueButton).height),
          );
          if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/ocr_share_previews/cards-${english ? 'en' : 'ko'}-${large ? 'large' : 'normal'}.png',
              ),
            );
          }
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text(
                english ? 'Confirm the medication' : '약품 후보 확인',
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text(english ? 'Cancel' : '취소'));
          await tester.pumpAndSettle();
          expect(chosen, isNull);
          expect(tester.takeException(), isNull);
        },
      );

      // 함수이름: testWidgets: 'OCR editor spacing english=$english large=$large'
      // 함수역할: 언어·글자 크기별로 OCR 편집창을 열고 필드 간격을 검사한 뒤 키보드 하단 여백을 적용한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 반환값 없음; 지정 필드 사이 간격이 15 이상이고 복용일 칸까지 스크롤할 수 있으며 예외 없이 취소한다. 미리보기 옵션을 켜면 골든도 비교한다.
      testWidgets('OCR editor spacing english=$english large=$large', (
        tester,
      ) async {
        tester.view.physicalSize = Size(large ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: MedBuddyTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: PrescriptionAnalysisPreviewUI(
              userSetting: UserSetting(language: english ? 'en' : 'ko'),
              medicationScheduleList: [
                MedicationSchedule(
                  medicationName: '시험약',
                  dosage: '1정',
                  intakeTime: '2회',
                  medicationTime: 4,
                  prescriptionDate: DateTime(2026, 10, 20),
                  scheduleSlotKeys: ['morning', 'evening'],
                ),
              ],
              onBackRequested: () {},
              onAnalysisRequested: () {},
              onMedicationScheduleChanged: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ocr-table-cell-0-name')));
        await tester.pumpAndSettle();
        for (final pair in [
          ('name', 'prescription-date'),
          ('prescription-date', 'dosage'),
          ('frequency', 'days'),
        ]) {
          final before = tester.getRect(find.byKey(Key('ocr-edit-${pair.$1}')));
          final after = tester.getRect(find.byKey(Key('ocr-edit-${pair.$2}')));
          expect(after.top - before.bottom, greaterThanOrEqualTo(15));
        }
        if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../.dart_tool/ocr_share_previews/editor-${english ? 'en' : 'ko'}-${large ? 'large' : 'normal'}.png',
            ),
          );
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('ocr-edit-days')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('ocr-edit-cancel')));
        await tester.pumpAndSettle();
      });
    }
  }

  // 함수이름: testWidgets: 'analysis progress bar animates to completed count'
  // 함수역할: 총 5개 중 완료 수를 1에서 3으로 바꾸며 진행 막대의 전환 시간을 나눠 진행한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 처음 0.2, 전환 중 0.2와 0.6 사이, 완료 후 0.6이며 미리보기 옵션을 켜면 골든도 비교한다.
  testWidgets('analysis progress bar animates to completed count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 함수이름: screen
    // 함수역할: 총 분석 수는 5로 고정하고 완료 수만 주입한 약 분석 진행 화면을 만든다.
    // 매개변수: count (int): 완료한 약 개수.
    // 반환값: Widget: 진행 비율 애니메이션을 관찰할 MaterialApp.
    Widget screen(int count) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MedBuddyTheme.light(),
      home: PrescriptionAnalysisProgressUI(
        activeStep: AnalysisProgressStep.medicationAnalysis,
        userSetting: const UserSetting(),
        totalMedicationCount: 5,
        completedMedicationCount: count,
        onBackRequested: () {},
      ),
    );
    await tester.pumpWidget(screen(1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .2,
    );
    await tester.pumpWidget(screen(3));
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      allOf(greaterThan(.2), lessThan(.6)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .6,
    );
    if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../.dart_tool/ocr_share_previews/progress-ko.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
