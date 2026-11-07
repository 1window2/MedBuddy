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

// 함수이름: _prnEntry
// 함수역할:
// - 같은 약의 필요시 복용 이벤트를 서로 다른 UUID 슬롯으로 구성한다.
// 매개변수:
// - event (int): 12자리 숫자 부분에 사용할 이벤트 번호.
// - date (String): ISO 날짜; 기본값 2026-10-12.
// - status (String): taken·skipped·unrecorded 중 검증할 기록 상태.
// 반환값:
// - Map<String, dynamic>; 필요시 모드와 독립 슬롯을 가진 응답 항목.
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

// 함수이름: _snapshot
// 함수역할:
// - 공통 응답 fixture를 실제 스냅샷 파서에 통과시켜 날짜·슬롯 계약을 따르는 차트 입력을 만든다.
// 매개변수:
// - items (List<Map<String, dynamic>>): 합성 복약 항목; 기본값 빈 목록.
// - start (String): 포함되는 시작 ISO 날짜.
// - end (String): 포함되는 종료 ISO 날짜.
// 반환값:
// - MedicationHistorySnapshot; 응답에서 파싱한 조회 범위와 항목.
MedicationHistorySnapshot _snapshot({
  List<Map<String, dynamic>> items = const [],
  String start = '2026-10-12',
  String end = '2026-10-18',
}) => MedicationHistorySnapshot.fromJson(
  historyTestBody(start: start, end: end, items: items),
);

// 함수이름: _mixedSnapshot
// 함수역할:
// - 정기 4회 중 복용 2회와 필요시 복용 3회를 두 날짜에 배치하고 필요시 건너뜀·미기록도 포함한다.
// 매개변수:
// - 없음.
// 반환값:
// - MedicationHistorySnapshot; 정기 분모와 필요시 집계를 구분할 혼합 데이터.
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

// 함수이름: _segment
// 함수역할:
// - 날짜의 일과 상태를 합친 키로 주간 막대의 특정 부분을 찾는다.
// 매개변수:
// - day (int): 고정 주의 날짜 일 값 12~18.
// - status (String): taken·skipped·unrecorded·prn 막대 구분값.
// 반환값:
// - Finder; 해당 막대 부분의 키를 찾는 탐색기.
Finder _segment(int day, String status) =>
    find.byKey(ValueKey('history-week-$day-$status'));

// 함수이름: _day
// 함수역할:
// - ISO 날짜 키를 이용해 주간 차트의 날짜 선택 영역을 찾는다.
// 매개변수:
// - day (DateTime): 선택할 날짜.
// 반환값:
// - Finder; 해당 날짜 키를 찾는 탐색기.
Finder _day(DateTime day) => find.byKey(
  ValueKey('history-week-day-${MedicationHistoryDates.format(day)}'),
);

// 함수이름: _bar
// 함수역할:
// - 복용 막대의 상위 InkWell을 찾아 기록이 없어 높이가 0이어도 날짜 터치 영역을 선택한다.
// 매개변수:
// - day (DateTime): 찾을 날짜.
// 반환값:
// - Finder; 해당 일의 전체 막대 터치 영역.
Finder _bar(DateTime day) => find
    .ancestor(of: _segment(day.day, 'taken'), matching: find.byType(InkWell))
    .first;

// 함수이름: _weekChart
// 함수역할:
// - 고정 월요일부터의 주간 차트에 스냅샷과 선택·활성·언어 상태를 주입한다.
// 매개변수:
// - snapshot (MedicationHistorySnapshot): 표시할 조회 범위와 기록.
// - today (DateTime?): 선택 가능한 마지막 날짜; null이면 고정 일요일.
// - selected (DateTime?): 현재 선택 날짜; null이면 고정 월요일.
// - isEnglish (bool): 영어 표시 여부; 기본값 true.
// - enabled (bool): 날짜 선택 허용 여부; 기본값 true.
// - onDaySelected (ValueChanged<DateTime>?): 날짜 선택 처리; null이면 아무 작업도 하지 않는다.
// 반환값:
// - MedicationHistoryWeekChart; 테스트 설정을 반영한 차트 위젯.
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

// 함수이름: _pumpChart
// 함수역할:
// - 실제 테마·번역·여백을 사용해 지정 너비와 글자 배율로 차트를 표시하고 화면 크기 복원을 등록한다.
// 매개변수:
// - tester (WidgetTester): 화면 구성과 프레임 진행 도구.
// - child (Widget): 표시할 차트 또는 차트를 포함한 위젯.
// - width (double): 논리 화면 너비; 기본값 390.
// - textScale (double): 글자 배율; 기본값 1.
// - isEnglish (bool): 로캘의 영어 사용 여부; 기본값 true.
// 반환값:
// - Future<void>; 화면이 안정되면 완료한다.
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

// 함수이름: _expectUnclippedText
// 함수역할:
// - 차트 안 모든 RichText의 선택 상자가 렌더링 경계를 벗어나지 않는지 검사하여 Flex 오류 없이 생기는 잘림도 탐지한다.
// 매개변수:
// - tester (WidgetTester): 렌더링 객체와 예외 조회 도구.
// - chart (Finder): 글자 경계를 검사할 차트 범위.
// 반환값:
// - void; 0.5px 허용 오차를 넘는 잘림이나 렌더링 예외가 있으면 검증이 실패한다.
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

// Function Name: main
// Description:
// - Register bilingual chart aggregation, selection, accessibility, and compact-layout regressions.
// Parameters:
// - None.
// Returns:
// - void; the Flutter runner executes the registered tests.
void main() {
  for (final english in [false, true]) {
    // 함수이름: bordered chat summary keeps chart beside legend $english
    // 함수역할:
    // - 두 언어의 폭 240 채팅 요약에서 세 자리 수 범례가 차트 오른쪽에 유지되고 레이아웃 오류가 없는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
  for (final compact in [false, true]) {
    for (final count in [123, 123456]) {
      // Function Name: long ratio stays inside ring $compact/$count
      // Description:
      // - Keep every corner of long ratio text inside the ring for regular and compact layouts at 320px width and double text scale.
      // Parameters:
      // - tester (WidgetTester): pumps the widget tree and performs user gestures.
      // Returns:
      // - Future<void>; completes after the asynchronous assertions.
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

  // 함수이름: medication history charts
  // 함수역할:
  // - 두 언어의 집계·접근성·확대 배치와 날짜별 선택 가능 범위를 검사하는 테스트를 묶는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 그룹의 테스트를 등록한다.
  group('medication history charts', () {
    for (final english in [true, false]) {
      final language = english ? 'English' : 'Korean';

      // 함수이름: summary excludes PRN from the denominator in $language
      // 함수역할:
      // - 두 언어에서 필요시 복용을 정기 분모에서 제외해 50%와 상태별 건수를 표시하고 비율·분수 전환 및 접근성 안내를 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
        // 함수이름: ${prnOnly ? 'PRN-only' : 'empty'} summary has no percentage in $language
        // 함수역할:
        // - 빈 기록 또는 필요시만 있는 기록에 백분율을 만들지 않고 대시와 유효한 필요시 복용 건수만 표시하는지 두 언어로 검증한다.
        // 매개변수:
        // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
        // 반환값:
        // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
        // 함수이름: ${summary ? 'summary' : 'week'} fits width 320 text scale 2 in $language
        // 함수역할:
        // - 두 언어의 요약·주간 차트가 폭 320과 2배 글자에서 288px 내용 영역에 맞고 글자가 잘리지 않는지 검증한다.
        // 매개변수:
        // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
        // 반환값:
        // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: weekly PRN has a distinct color and counts only taken events
    // 함수역할:
    // - 필요시 복용을 별도 색으로 구분하고 taken 이벤트만 높이에 반영하며 정기 상태별 높이·색과 접근성 건수가 맞는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: empty week renders zero-height segments without division errors
    // 함수역할:
    // - 기록이 없는 주는 모든 막대 부분의 높이를 0으로 표시하고 나눗셈·렌더링 오류가 없는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: future records do not affect bars or the weekly scale
    // 함수역할:
    // - 오늘 이후의 정기·필요시 기록은 막대와 주간 최대 눈금에 영향을 주지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: each date label and bar selects its own day exactly once
    // 함수역할:
    // - 각 날짜의 라벨과 막대를 누를 때 해당 날짜를 한 번만 전달하고 선택 접근성 상태도 그 날짜에만 적용하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: disabled chart blocks both labels and bars for every day
    // 함수역할:
    // - 비활성 차트는 모든 날짜의 라벨·막대 콜백을 제거하여 탭해도 선택 기록을 만들지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: partial range enables only its inclusive dates
    // 함수역할:
    // - 부분 조회 범위의 시작·종료일을 포함한 날짜만 라벨·막대 선택을 허용하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
      // 함수이름: future ${label ? 'labels' : 'bars'} stay disabled even inside snapshot range
      // 함수역할:
      // - 주 전체가 조회 범위여도 오늘까지만 선택되고 미래 날짜의 라벨·막대는 선택되지 않는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면을 표시하고 입력·탭·렌더링 결과를 검사한다.
      // 반환값:
      // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
