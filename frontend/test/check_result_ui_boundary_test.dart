// 분석 결과의 2×2 표와 저장 동작을 실제 날짜·네트워크에 의존하지 않고 검증한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

AnalyzedMedication medication({bool asNeeded = false, bool missing = false}) =>
    AnalyzedMedication(
      schedule: MedicationSchedule(
        medicationName: asNeeded ? '시험용 필요시 약' : '시험용 긴 이름 약품 100밀리그램',
        dosage: '1정',
        intakeTime: '2회',
        medicationTime: 5,
        prescriptionDate: missing ? null : DateTime(2026, 1, 2),
        dosingMode: asNeeded ? 'as_needed' : 'scheduled',
        scheduleSlotKeys: const ['morning', 'evening'],
      ),
      detail: const MedicationDetail(
        itemName: '',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
    );

Widget screen({
  bool english = false,
  double scale = 1,
  List<AnalyzedMedication>? items,
  Set<int> saved = const {},
  int? saving,
  bool savingAll = false,
  Future<bool> Function(AnalyzedMedication, int)? save,
  Future<bool> Function()? saveAll,
  PrescriptionChangeRadar? radar,
  bool reduceMotion = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Platform.environment['MEDBUDDY_TEST_FONT'] == null
      ? MedBuddyTheme.light()
      : MedBuddyTheme.light().copyWith(
          textTheme: MedBuddyTheme.light().textTheme.apply(
            fontFamily: 'Noto Sans KR',
          ),
        ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: CheckResultUI(
    analyzedMedicationList: items ?? [medication(), medication(asNeeded: true)],
    prescriptionChangeRadar: radar,
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    statusMessageProvider: () => '시험 저장 결과',
    savingMedicationIndex: saving,
    completedMedicationSaveIndexes: saved,
    isAllMedicationSaving: savingAll,
    onCloseRequested: () {},
    onAllMedicationSaveRequested: saveAll ?? () async => true,
    onMedicationSaveRequested: save ?? (_, _) async => true,
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('result header grows for multiline names scale=$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      double previousHeight = 0;
      for (final lines in [1, 2, 4]) {
        final item = AnalyzedMedication(
          schedule: MedicationSchedule(
            medicationName: List.filled(lines, '시험약').join('\n'),
            dosage: '1정',
          ),
          detail: const MedicationDetail(
            itemName: '',
            efficacy: '',
            usageMethod: '',
            warning: '',
          ),
        );
        await tester.pumpWidget(
          screen(items: [item], scale: scale, reduceMotion: true),
        );
        await tester.pumpAndSettle();
        final header = tester.getRect(
          find.byKey(const Key('result-medication-header-0')),
        );
        final name = tester.getRect(
          find.byKey(const Key('result-medication-name-0')),
        );
        final save = tester.getRect(
          find.byKey(const Key('result-medication-save-0')),
        );
        final toggle = tester.getRect(
          find.byKey(const Key('result-medication-toggle-0')),
        );
        expect(name.top, greaterThanOrEqualTo(header.top));
        expect(name.bottom, lessThanOrEqualTo(header.bottom));
        expect(header.height, greaterThanOrEqualTo(previousHeight));
        if (lines == 4) expect(header.height, greaterThan(previousHeight));
        previousHeight = header.height;
        expect(save.center.dy, closeTo(toggle.center.dy, .1));
        expect(save.right, lessThanOrEqualTo(toggle.left));
        if (scale == 1) expect(save.center.dy, closeTo(header.center.dy, .1));
        expect(tester.takeException(), isNull);
      }
      if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../.dart_tool/result_previews/result-multiline-$scale.png',
          ),
        );
      }
    });
  }
  final resultScroll = find.descendant(
    of: find.byKey(const Key('analysis-result-list')),
    matching: find.byType(Scrollable),
  );
  Future<void> expand(WidgetTester tester, int index) async {
    final toggle = find.byKey(Key('result-medication-toggle-$index'));
    for (
      var attempt = 0;
      attempt < 30 && toggle.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(resultScroll, const Offset(0, -60));
      await tester.pumpAndSettle();
    }
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  testWidgets('summary is immediately visible and results are interactive', (
    tester,
  ) async {
    final items = List.generate(12, (_) => medication());
    await tester.pumpWidget(screen(items: items));
    final intro = find.byKey(const Key('analysis-summary-intro'));
    final pinned = find.byKey(const Key('analysis-summary-pinned'));
    expect(intro, findsNothing);
    expect(pinned, findsOneWidget);
    final toggle = find.byKey(const Key('result-medication-toggle-0'));
    await tester.tap(toggle);
    await tester.pump();
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
    final before = tester.getTopLeft(pinned);
    await tester.drag(resultScroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pinned), before);
    await tester.pumpWidget(screen(items: items, saved: {0}));
    await tester.pumpAndSettle();
    expect(intro, findsNothing);
  });

  testWidgets('compact result previews and rounded shared header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen());
    if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../.dart_tool/result_previews/result-immediate.png'),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('분석한 약과 복용 일정을 확인하고 저장합니다.'), findsOneWidget);
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
    expect(find.byKey(const Key('result-medication-summary-1')), findsNothing);
    if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../.dart_tool/result_previews/result-collapsed.png'),
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
    testWidgets(
      'landscape keeps results and save action usable english=$english',
      (tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(screen(english: english, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.getSize(resultScroll).height, greaterThan(40));
        expect(
          find.byKey(const Key('prescription-save-all')).hitTestable(),
          findsOneWidget,
        );
        await expand(tester, 0);
        expect(
          find.byKey(const Key('result-medication-summary-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('summary is immediate with either motion preference', (
    tester,
  ) async {
    await tester.pumpWidget(screen(reduceMotion: true));
    expect(find.byKey(const Key('analysis-summary-intro')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    expect(find.byKey(const Key('analysis-summary-intro')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded results retain their state across save rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await expand(tester, 0);
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('result-medication-summary-1')), findsNothing);
    await tester.pumpWidget(screen(saved: {0}));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('result-medication-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
  });

  testWidgets('comparison summary does not shift medication save indexes', (
    tester,
  ) async {
    int? savedIndex;
    await tester.pumpWidget(
      screen(
        radar: const PrescriptionChangeRadar(hasPreviousPrescription: false),
        save: (_, index) async {
          savedIndex = index;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    final save = find.descendant(
      of: find.byKey(const Key('result-medication-card-0')),
      matching: find.byIcon(Icons.save_outlined),
    );
    await tester.scrollUntilVisible(save, 100, scrollable: resultScroll);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(savedIndex, 0);
    expect(find.text('시험 저장 결과'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
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
    for (final large in [false, true]) {
      testWidgets('result table english=$english large=$large', (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 390, large ? 568 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(screen(english: english, scale: large ? 2 : 1));
        await tester.pumpAndSettle();

        expect(find.text(english ? 'Frequency' : '1일 횟수'), findsNothing);
        expect(
          find.byKey(const Key('result-medication-summary-0')),
          findsNothing,
        );
        await expand(tester, 0);
        await tester.scrollUntilVisible(
          find.byKey(const Key('result-medication-summary-0')),
          100,
          scrollable: resultScroll,
        );
        await tester.pumpAndSettle();
        final summary = tester.widget<Table>(
          find.byKey(const Key('result-medication-summary-0')),
        );
        final schedule = tester.widget<Table>(
          find.byKey(const Key('result-medication-schedule-0')),
        );
        expect(summary.children.single.children, hasLength(2));
        expect(schedule.children.single.children, hasLength(2));
        expect(find.text('2026-01-02'), findsWidgets);
        expect(
          find.text(english ? 'Morning, Evening' : '아침, 저녁'),
          findsOneWidget,
        );
        final name = tester.widget<Text>(find.text('시험용 긴 이름 약품 100밀리그램'));
        expect(name.maxLines, isNull);
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        final footer = find.byKey(const Key('prescription-save-all'));
        expect(footer.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../.dart_tool/result_previews/result-${english ? 'en' : 'ko'}-${large ? 'large' : 'normal'}.png',
            ),
          );
        }
        final prn = find.text(english ? 'As needed' : '필요시 복용');
        await expand(tester, 1);
        await tester.scrollUntilVisible(prn, 120, scrollable: resultScroll);
        await tester.pumpAndSettle();
        expect(prn.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(prn).bottom,
          lessThan(tester.getRect(footer).top),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'individual save keeps its index and saved rows cannot save again',
    (tester) async {
      final requests = <int>[];
      await tester.pumpWidget(
        screen(
          saved: {0},
          save: (item, index) async {
            requests.add(index);
            expect(item.schedule.isAsNeeded, isTrue);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      final first = find.descendant(
        of: find.byKey(const Key('result-medication-save-0')),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(first).onPressed, isNull);
      final second = find.byIcon(Icons.save_outlined);
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(requests, [1]);
      expect(find.text('복약 일정 저장 완료'), findsOneWidget);
    },
  );

  testWidgets(
    'saving disables all commands and failures leave retry available',
    (tester) async {
      await tester.pumpWidget(screen(saving: 0));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('prescription-save-all')),
            )
            .onPressed,
        isNull,
      );
      for (final icon in tester.widgetList<IconButton>(
        find.descendant(
          of: find.byKey(const Key('result-medication-save-0')),
          matching: find.byType(IconButton),
        ),
      )) {
        expect(icon.onPressed, isNull);
      }
      var attempts = 0;
      await tester.pumpWidget(
        screen(
          saveAll: () async {
            attempts++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prescription-save-all')));
      await tester.pumpAndSettle();
      expect(find.text('시험 저장 결과'), findsOneWidget);
      expect(find.text('복약 일정 저장 완료'), findsNothing);
      expect(attempts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('prescription-save-all')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'missing start dates stay unknown and non-daily cycles stay visible',
    (tester) async {
      final item = medication(missing: true);
      await tester.pumpWidget(
        screen(
          items: [
            AnalyzedMedication(
              schedule: item.schedule.copyWith(intakeTime: '격일'),
              detail: item.detail,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await expand(tester, 0);
      expect(find.text('정보 없음'), findsOneWidget);
      expect(find.textContaining('격일'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
