// 파일명: medication_history_charts_test.dart
// 역할: 복약 그래프의 정기·필요시 집계, 날짜 선택과 확대 글자 배치를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medication_history_charts.dart';

import 'medication_history_fixtures.dart';

final _monday = DateTime.utc(2026, 10, 12);
final _sunday = DateTime.utc(2026, 10, 18);

// 같은 약의 독립 필요시 이벤트를 실제 응답과 같은 UUID 슬롯으로 구분한다.
Map<String, dynamic> _prnEntry(
  int event, {
  String date = '2026-10-12',
  String status = 'taken',
}) => historyTestEntry(
  id: 2,
  name: '테스트 필요시약',
  date: date,
  mode: 'as_needed',
  slot:
      'as_needed:00000000-0000-4000-8000-${event.toString().padLeft(12, '0')}',
  status: status,
);

// 기존 응답 픽스처의 파서를 거쳐 날짜·슬롯 계약이 유효한 자료만 사용한다.
MedicationHistorySnapshot _snapshot({
  List<Map<String, dynamic>> items = const [],
  String start = '2026-10-12',
  String end = '2026-10-18',
}) => MedicationHistorySnapshot.fromJson(
  historyTestBody(start: start, end: end, items: items),
);

// 정기 4회 중 복용 2회와 필요시 복용 3회를 서로 다른 날짜에 배치한다.
MedicationHistorySnapshot _mixedSnapshot() => _snapshot(
  items: [
    historyTestEntry(date: '2026-10-12', status: 'taken'),
    historyTestEntry(date: '2026-10-12', slot: 'lunch', status: 'skipped'),
    historyTestEntry(date: '2026-10-12', slot: 'evening'),
    historyTestEntry(date: '2026-10-13', status: 'taken'),
    _prnEntry(1),
    _prnEntry(2),
    _prnEntry(3, date: '2026-10-13'),
    _prnEntry(4, status: 'skipped'),
    _prnEntry(5, status: 'unrecorded'),
  ],
);

Finder _segment(int day, String status) =>
    find.byKey(ValueKey('history-week-$day-$status'));

Finder _day(DateTime day) => find.byKey(
  ValueKey('history-week-day-${MedicationHistoryDates.format(day)}'),
);

// 기록이 없는 날도 높이 0인 막대 대신 전체 날짜 터치 영역을 누른다.
Finder _bar(DateTime day) => find
    .ancestor(of: _segment(day.day, 'taken'), matching: find.byType(InkWell))
    .first;

MedicationHistoryWeekChart _weekChart({
  required MedicationHistorySnapshot snapshot,
  DateTime? today,
  DateTime? selected,
  bool isEnglish = true,
  bool enabled = true,
  ValueChanged<DateTime>? onDaySelected,
}) => MedicationHistoryWeekChart(
  snapshot: snapshot,
  weekStart: _monday,
  today: today ?? _sunday,
  selected: selected ?? _monday,
  isEnglish: isEnglish,
  enabled: enabled,
  onDaySelected: onDaySelected ?? (_) {},
);

// 실제 화면과 같은 여백·테마·번역을 쓰되 서버나 상위 화면에는 의존하지 않는다.
Future<void> _pumpChart(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double textScale = 1,
  bool isEnglish = true,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      locale: Locale(isEnglish ? 'en' : 'ko'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ko')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// RenderFlex 오류가 없어도 좁은 날짜 셀에서 글자 자체가 잘릴 수 있어 경계를 검사한다.
void _expectUnclippedText(WidgetTester tester, Finder chart) {
  for (final element
      in find
          .descendant(of: chart, matching: find.byType(RichText))
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(-0.5), reason: text);
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: 'Text clipped horizontally: $text',
      );
      expect(box.top, greaterThanOrEqualTo(-0.5), reason: text);
      expect(
        box.bottom,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason: 'Text clipped vertically: $text',
      );
    }
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final english in [false, true]) {
    testWidgets('bordered chat summary keeps chart beside legend $english', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MedBuddyTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: MedicationHistoryChartsSummary.counts(
                  counts: const MedicationHistoryChartCounts(
                    taken: 123,
                    skipped: 123,
                    unrecorded: 123,
                    asNeeded: 123,
                  ),
                  isEnglish: english,
                ),
              ),
            ),
          ),
        ),
      );
      final chart = tester.getRect(find.byKey(const Key('history-rate-chart')));
      final count = tester.getRect(find.byKey(const Key('history-count-0')));
      expect(count.left, greaterThan(chart.right));
      expect(tester.takeException(), isNull);
    });
  }
  // 세 자리 이상 비율과 큰 글씨에서도 가운데 내용의 모든 모서리가 고리 안에 남는다.
  for (final compact in [false, true]) {
    for (final count in [123, 123456]) {
      testWidgets('long ratio stays inside ring $compact/$count', (
        tester,
      ) async {
        await _pumpChart(
          tester,
          MedicationHistoryChartsSummary.counts(
            counts: MedicationHistoryChartCounts(taken: count, unrecorded: 876),
            compact: compact,
            isEnglish: false,
          ),
          width: 320,
          textScale: 2,
          isEnglish: false,
        );
        final ring = tester.getRect(
          find.byKey(const Key('history-rate-chart')),
        );
        final content = tester.getRect(
          find.byKey(const Key('history-rate-content')),
        );
        for (final corner in [
          content.topLeft,
          content.topRight,
          content.bottomLeft,
          content.bottomRight,
        ]) {
          expect(
            (corner - ring.center).distance,
            lessThanOrEqualTo(ring.width / 2 - 16),
          );
        }
        expect(find.text('$count/${count + 876}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('medication history charts', () {
    for (final english in [true, false]) {
      final language = english ? 'English' : 'Korean';

      testWidgets('summary excludes PRN from the denominator in $language', (
        tester,
      ) async {
        await _pumpChart(
          tester,
          MedicationHistoryChartsSummary(
            snapshot: _mixedSnapshot(),
            isEnglish: english,
          ),
          isEnglish: english,
        );

        expect(find.text('50%'), findsOneWidget);
        expect(
          find.text(english ? '4 scheduled doses' : '정기 복용 4회 기준'),
          findsNothing,
        );
        for (final (index, value) in [2, 1, 1, 3].indexed) {
          expect(
            tester
                .widget<Text>(find.byKey(ValueKey('history-count-$index')))
                .data,
            '$value',
          );
        }
        for (final label
            in english
                ? ['Taken', 'Skipped', 'Unrecorded', 'As needed']
                : ['복용함', '건너뜀', '미기록', '필요시 복용']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(
          find.bySemanticsLabel(
            RegExp(
              english ? 'Scheduled dose record rate 50%' : '정기 복용 기록률 50%',
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('history-rate-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('2/4'), findsOneWidget);
        expect(find.text('50%'), findsNothing);
        await tester.tap(find.byKey(const Key('history-rate-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('50%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final prnOnly in [false, true]) {
        testWidgets(
          '${prnOnly ? 'PRN-only' : 'empty'} summary has no percentage in $language',
          (tester) async {
            await _pumpChart(
              tester,
              MedicationHistoryChartsSummary(
                snapshot: _snapshot(
                  items: prnOnly
                      ? [
                          _prnEntry(1),
                          _prnEntry(2),
                          _prnEntry(3, status: 'skipped'),
                          _prnEntry(4, status: 'unrecorded'),
                        ]
                      : [],
                ),
                isEnglish: english,
              ),
              isEnglish: english,
            );

            expect(
              tester
                  .widget<Text>(find.byKey(const Key('history-rate-value')))
                  .data,
              '-',
            );
            expect(find.text('0%'), findsNothing);
            expect(find.text('100%'), findsNothing);
            expect(
              find.text(english ? '0 scheduled doses' : '정기 복용 0회 기준'),
              findsNothing,
            );
            for (var index = 0; index < 4; index++) {
              expect(
                tester
                    .widget<Text>(find.byKey(ValueKey('history-count-$index')))
                    .data,
                index == 3 && prnOnly ? '2' : '0',
              );
            }
            expect(find.byKey(const Key('history-rate-chart')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }

      for (final summary in [true, false]) {
        testWidgets(
          '${summary ? 'summary' : 'week'} fits width 320 text scale 2 in $language',
          (tester) async {
            await _pumpChart(
              tester,
              summary
                  ? MedicationHistoryChartsSummary(
                      snapshot: _mixedSnapshot(),
                      isEnglish: english,
                    )
                  : _weekChart(snapshot: _mixedSnapshot(), isEnglish: english),
              width: 320,
              textScale: 2,
              isEnglish: english,
            );

            final chart = find.byType(
              summary
                  ? MedicationHistoryChartsSummary
                  : MedicationHistoryWeekChart,
            );
            expect(tester.getSize(chart).width, 288);
            expect(
              MediaQuery.textScalerOf(tester.element(chart)).scale(14),
              28,
            );
            _expectUnclippedText(tester, chart);
          },
        );
      }
    }

    testWidgets(
      'weekly PRN has a distinct color and counts only taken events',
      (tester) async {
        await _pumpChart(tester, _weekChart(snapshot: _mixedSnapshot()));

        final prnColor = tester.widget<Container>(_segment(12, 'prn')).color;
        expect(prnColor, isNotNull);
        final scheduledColors = [
          for (final status in ['taken', 'skipped', 'unrecorded'])
            tester.widget<Container>(_segment(12, status)).color,
        ];
        expect(scheduledColors, isNot(contains(prnColor)));
        expect(scheduledColors.toSet(), hasLength(3));
        // 최대 5회는 눈금 6에 맞추고, 필요시 취소·미기록은 막대 높이에 넣지 않는다.
        for (final status in ['taken', 'skipped', 'unrecorded']) {
          expect(
            tester.getSize(_segment(12, status)).height,
            closeTo(112 / 6, 0.01),
          );
        }
        expect(
          tester.getSize(_segment(12, 'prn')).height,
          closeTo(112 * 2 / 6, 0.01),
        );
        for (final status in ['taken', 'prn']) {
          expect(
            tester.getSize(_segment(13, status)).height,
            closeTo(112 / 6, 0.01),
          );
        }
        expect(tester.getSize(_segment(13, 'skipped')).height, 0);
        expect(tester.getSize(_segment(13, 'unrecorded')).height, 0);
        expect(
          find.bySemanticsLabel(
            '2026-10-12, taken 1, skipped 1, unrecorded 1, as needed 2',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'empty week renders zero-height segments without division errors',
      (tester) async {
        await _pumpChart(tester, _weekChart(snapshot: _snapshot()));
        for (var day = 12; day <= 18; day++) {
          for (final status in ['taken', 'skipped', 'unrecorded', 'prn']) {
            expect(tester.getSize(_segment(day, status)).height, 0);
          }
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('future records do not affect bars or the weekly scale', (
      tester,
    ) async {
      await _pumpChart(
        tester,
        _weekChart(
          snapshot: _snapshot(
            items: [
              historyTestEntry(date: '2026-10-12', status: 'taken'),
              for (final slot in ['morning', 'lunch', 'evening', 'bedtime'])
                historyTestEntry(
                  date: '2026-10-18',
                  slot: slot,
                  status: 'taken',
                ),
              _prnEntry(1, date: '2026-10-18'),
            ],
          ),
          today: DateTime.utc(2026, 10, 17),
        ),
      );
      expect(tester.getSize(_segment(12, 'taken')).height, closeTo(56, 0.01));
      for (final status in ['taken', 'skipped', 'unrecorded', 'prn']) {
        expect(tester.getSize(_segment(18, status)).height, 0);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('each date label and bar selects its own day exactly once', (
      tester,
    ) async {
      final selectedDays = <DateTime>[];
      var selected = _monday;
      await _pumpChart(
        tester,
        StatefulBuilder(
          builder: (context, setState) => _weekChart(
            snapshot: _mixedSnapshot(),
            selected: selected,
            onDaySelected: (day) {
              selectedDays.add(day);
              setState(() => selected = day);
            },
          ),
        ),
      );

      final expectedDays = <DateTime>[];
      for (var offset = 0; offset < 7; offset++) {
        final day = _monday.add(Duration(days: offset));
        for (final target in [_day(day), _bar(day)]) {
          await tester.tap(target);
          await tester.pumpAndSettle();
          expectedDays.add(day);
          expect(selectedDays, orderedEquals(expectedDays));
          for (var other = 0; other < 7; other++) {
            final candidate = _monday.add(Duration(days: other));
            final semantics = tester.widget<Semantics>(
              find
                  .ancestor(
                    of: _day(candidate),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Semantics &&
                          widget.properties.selected != null,
                    ),
                  )
                  .first,
            );
            expect(semantics.properties.selected, candidate == day);
          }
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled chart blocks both labels and bars for every day', (
      tester,
    ) async {
      final selectedDays = <DateTime>[];
      await _pumpChart(
        tester,
        _weekChart(
          snapshot: _mixedSnapshot(),
          enabled: false,
          onDaySelected: selectedDays.add,
        ),
      );
      for (var offset = 0; offset < 7; offset++) {
        final day = _monday.add(Duration(days: offset));
        for (final target in [_day(day), _bar(day)]) {
          expect(tester.widget<InkWell>(target).onTap, isNull);
          await tester.tap(target);
        }
      }
      expect(selectedDays, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('partial range enables only its inclusive dates', (
      tester,
    ) async {
      final selectedDays = <DateTime>[];
      await _pumpChart(
        tester,
        _weekChart(
          snapshot: _snapshot(start: '2026-10-14', end: '2026-10-16'),
          onDaySelected: selectedDays.add,
        ),
      );
      for (var offset = 0; offset < 7; offset++) {
        final day = _monday.add(Duration(days: offset));
        for (final target in [_day(day), _bar(day)]) {
          expect(
            tester.widget<InkWell>(target).onTap,
            day.day >= 14 && day.day <= 16 ? isNotNull : isNull,
          );
          await tester.tap(target);
        }
      }
      expect(selectedDays, [
        for (var day = 14; day <= 16; day++) ...[
          DateTime.utc(2026, 10, day),
          DateTime.utc(2026, 10, day),
        ],
      ]);
      expect(tester.takeException(), isNull);
    });

    for (final label in [true, false]) {
      testWidgets(
        'future ${label ? 'labels' : 'bars'} stay disabled even inside snapshot range',
        (tester) async {
          final selectedDays = <DateTime>[];
          final today = DateTime.utc(2026, 10, 14);
          await _pumpChart(
            tester,
            _weekChart(
              snapshot: _mixedSnapshot(),
              today: today,
              onDaySelected: selectedDays.add,
            ),
          );
          // 조회 범위가 주 전체여도 오늘 이후의 날짜를 선택해서는 안 된다.
          await tester.tap(label ? _day(today) : _bar(today));
          expect(selectedDays, [today]);
          selectedDays.clear();
          for (var day = 15; day <= 18; day++) {
            final date = DateTime.utc(2026, 10, day);
            await tester.tap(label ? _day(date) : _bar(date));
          }
          expect(selectedDays, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
