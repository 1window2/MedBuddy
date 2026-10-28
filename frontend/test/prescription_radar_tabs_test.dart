import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_change_radar_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

PrescriptionChangeRadar radar({int changedCount = 5, bool unknown = false}) =>
    PrescriptionChangeRadar(
      hasPreviousPrescription: true,
      previousPrescriptionDate: DateTime(2026, 7, 29),
      currentPrescriptionDate: DateTime(2026, 8, 3),
      summary: const PrescriptionChangeSummary(
        addedCount: 2,
        scheduleChangedCount: 5,
        missingCount: 9,
      ),
      changes: [
        for (var i = 0; i < changedCount; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.scheduleChanged,
            itemName: '변경 시험약 ${i + 1}',
            changedFields: const ['dosage_per_time', 'daily_frequency'],
            previous: const PrescriptionScheduleSnapshot(
              dosagePerTime: '1',
              dailyFrequency: '4',
            ),
            current: const PrescriptionScheduleSnapshot(
              dosagePerTime: '1정',
              dailyFrequency: '2회',
            ),
          ),
        for (var i = 0; i < 2; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.added,
            itemName: '새로 확인한 긴 이름의 시험약 ${i + 1} (시험 성분)',
          ),
        for (var i = 0; i < 9; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.missing,
            itemName: '이전 처방 시험약 ${i + 1}',
          ),
        if (unknown)
          const PrescriptionMedicationChange(
            type: PrescriptionChangeType.unknown,
            itemName: '분류 확인 시험약',
          ),
      ],
    );

Widget screen({
  String language = 'ko',
  double scale = 1,
  PrescriptionChangeRadar? data,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: MedBuddyTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrescriptionChangeRadarUI(
            radar: data ?? radar(),
            userSetting: UserSetting(language: language),
          ),
        ),
      ),
    ),
  ),
);

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

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

  for (final language in ['ko', 'en']) {
    for (final large in [false, true]) {
      testWidgets(
        'tabs page three medications and open one detail $language $large',
        (tester) async {
          tester.view.physicalSize = large
              ? const Size(320, 568)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final data = radar();
          await tester.pumpWidget(
            screen(language: language, scale: large ? 2 : 1, data: data),
          );
          expect(find.text('변경 시험약 1'), findsNothing);
          await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
          expect(find.text('변경 시험약 1'), findsOneWidget);
          expect(find.text('변경 시험약 3'), findsOneWidget);
          expect(find.text('변경 시험약 4'), findsNothing);
          expect(find.byKey(const Key('radar-change-detail')), findsNothing);
          if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true' &&
              !large) {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, 1000),
            );
            await tester.pumpAndSettle();
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/result_previews/radar-tabs-$language.png',
              ),
            );
          }
          await tap(tester, find.text('변경 시험약 1'));
          expect(find.byKey(const Key('radar-change-detail')), findsOneWidget);
          expect(find.text('1정'), findsOneWidget);
          expect(find.text('4'), findsOneWidget);
          await tap(tester, find.text('변경 시험약 2'));
          expect(find.byKey(const Key('radar-change-detail')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('radar-change-0')),
              matching: find.byType(Table),
            ),
            findsNothing,
          );
          await tap(tester, find.byKey(const Key('radar-next-page')));
          expect(find.text('변경 시험약 1'), findsNothing);
          expect(find.text('변경 시험약 5'), findsOneWidget);
          expect(find.byKey(const Key('radar-change-detail')), findsNothing);
          expect(
            tester
                .widget<IconButton>(find.byKey(const Key('radar-next-page')))
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(
            screen(language: language, scale: large ? 2 : 1, data: data),
          );
          expect(find.text('변경 시험약 5'), findsOneWidget);
          await tap(tester, find.byKey(const Key('radar-tab-added')));
          expect(find.text('새로 확인한 긴 이름의 시험약 1 (시험 성분)'), findsOneWidget);
          expect(find.byKey(const Key('radar-next-page')), findsNothing);
          await tap(tester, find.byKey(const Key('radar-tab-missing')));
          expect(find.text('이전 처방 시험약 1'), findsOneWidget);
          await tap(tester, find.byKey(const Key('radar-next-page')));
          await tap(tester, find.byKey(const Key('radar-next-page')));
          expect(find.text('이전 처방 시험약 9'), findsOneWidget);
          expect(
            find.text(
              language == 'ko'
                  ? '이번 처방에서 확인되지 않음'
                  : 'Not found in this prescription',
            ),
            findsOneWidget,
          );
          await tap(tester, find.byKey(const Key('radar-previous-page')));
          expect(find.text('이전 처방 시험약 4'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty category and refreshed shorter results remain usable', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
    await tap(tester, find.byKey(const Key('radar-next-page')));
    await tester.pumpWidget(screen(data: radar(changedCount: 1)));
    await tester.pumpAndSettle();
    expect(find.text('변경 시험약 1'), findsOneWidget);
    expect(find.byKey(const Key('radar-next-page')), findsNothing);
    await tester.pumpWidget(screen(data: radar(changedCount: 0)));
    await tester.pumpAndSettle();
    expect(find.text('이 분류에 해당하는 약이 없습니다.'), findsOneWidget);
    await tap(tester, find.byKey(const Key('radar-tab-added')));
    expect(find.text('새로 확인한 긴 이름의 시험약 1 (시험 성분)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown change type is not lost when summary counts are absent',
    (tester) async {
      await tester.pumpWidget(
        screen(
          data: const PrescriptionChangeRadar(
            hasPreviousPrescription: true,
            changes: [
              PrescriptionMedicationChange(
                type: PrescriptionChangeType.unknown,
                itemName: '분류 확인 시험약',
              ),
            ],
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
      await tap(tester, find.byKey(const Key('radar-tab-unknown')));
      expect(find.text('분류 확인 시험약'), findsOneWidget);
      expect(find.text('기타'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
