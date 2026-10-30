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

const _candidate = MedicationDetail(
  itemName: '시험약 A',
  manufacturer: '시험 제약',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

void main() {
  testWidgets(
    'review details start open and candidate action survives folding',
    (tester) async {
      var candidateRequests = 0;
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

  testWidgets('analysis progress bar animates to completed count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
