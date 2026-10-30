// 결과 요약의 즉시 표시, 상단 고정, 접근성 및 화면 종료를 검증한다.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

const _statuses = {
  0: MedicationLookupStatus.verified,
  1: MedicationLookupStatus.verified,
  2: MedicationLookupStatus.candidates,
  3: MedicationLookupStatus.candidates,
  4: MedicationLookupStatus.candidates,
  5: MedicationLookupStatus.notFound,
  6: MedicationLookupStatus.notFound,
  7: MedicationLookupStatus.failed,
};

Widget _screen({
  bool english = false,
  double scale = 1,
  bool reduceMotion = false,
  Map<int, MedicationLookupStatus> statuses = _statuses,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: MedBuddyTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: PrescriptionAnalysisPreviewUI(
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    medicationScheduleList: List.generate(
      8,
      (index) => MedicationSchedule(
        medicationName: english
            ? 'Example medication ${index + 1}'
            : '시험약 ${index + 1}',
        dosage: '1정',
        intakeTime: '3회',
        medicationTime: 4,
        prescriptionDate: DateTime(2026, 1, 1),
        scheduleSlotKeys: ['morning', 'lunch', 'evening'],
      ),
    ),
    lookupStatuses: statuses,
    isMedicationLookupReview: true,
    verifiedScheduleIndexes: statuses.entries
        .where((entry) => entry.value == MedicationLookupStatus.verified)
        .map((entry) => entry.key)
        .toSet(),
    onBackRequested: () {},
    onAnalysisRequested: () {},
    onMedicationScheduleChanged: (_, _) {},
  ),
);

void main() {
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
    for (final viewport in [
      (Size(390, 844), 1.0),
      (Size(320, 568), 2.0),
      (Size(640, 360), 2.0),
    ]) {
      testWidgets(
        'summary appears immediately and stays pinned $english $viewport',
        (tester) async {
          tester.view.physicalSize = viewport.$1;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _screen(english: english, scale: viewport.$2),
          );
          final intro = find.byKey(const Key('lookup-summary-intro'));
          final pinned = find.byKey(const Key('lookup-summary-pinned'));
          expect(intro, findsNothing);
          final firstTop = tester.getTopLeft(pinned).dy;
          if (!english &&
              viewport.$2 == 1 &&
              Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/ocr_share_previews/summary-immediate.png',
              ),
            );
          }
          await tester.pump(const Duration(seconds: 3));
          expect(tester.getTopLeft(pinned).dy, firstTop);
          expect(intro, findsNothing);
          for (final entry in {
            MedicationLookupStatus.verified: 2,
            MedicationLookupStatus.candidates: 3,
            MedicationLookupStatus.notFound: 2,
            MedicationLookupStatus.failed: 1,
          }.entries) {
            expect(
              find.descendant(
                of: find.byKey(Key('lookup-summary-count-${entry.key.name}')),
                matching: find.text('${entry.value}'),
              ),
              findsOneWidget,
            );
          }
          if (!english &&
              viewport.$2 == 1 &&
              Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/ocr_share_previews/summary-pinned.png',
              ),
            );
          }
          final before = tester.getTopLeft(pinned);
          final titleBefore = tester.getTopLeft(
            find.byKey(const Key('prescription-review-title')),
          );
          final scroll = find
              .ancestor(
                of: find.byKey(const Key('ocr-medication-list')),
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await tester.drag(scroll, const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(pinned), before);
          final scrollRegion = find.byKey(
            const Key('prescription-review-scroll-region'),
          );
          expect(
            tester.getTopLeft(scrollRegion).dy -
                tester
                    .getBottomLeft(
                      find.byKey(const Key('lookup-summary-pinned-viewport')),
                    )
                    .dy,
            closeTo(10, .1),
          );
          expect(
            tester.getTopLeft(
              find.byKey(const Key('prescription-review-title')),
            ),
            titleBefore,
          );
          await tester.pumpWidget(
            _screen(
              english: english,
              scale: viewport.$2,
              statuses: {..._statuses, 7: MedicationLookupStatus.verified},
            ),
          );
          await tester.pumpAndSettle();
          expect(intro, findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const Key('lookup-summary-count-failed')),
              matching: find.text('0'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets('leaving immediately does not leave pending work', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion shows the pinned summary immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(reduceMotion: true));
    expect(find.byKey(const Key('lookup-summary-intro')), findsNothing);
    expect(find.byKey(const Key('lookup-summary-pinned')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
