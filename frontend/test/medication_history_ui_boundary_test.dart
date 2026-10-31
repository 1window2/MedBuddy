// 파일명: medication_history_ui_boundary_test.dart
// 역할: 기록 정정·권한·내보내기·작은 화면의 실제 위젯 흐름을 검증한다.
import 'dart:async';
import 'support/fake_as_needed_pending_store.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/medication_history_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/as_needed_schedule_section.dart';
import 'package:medbuddy_frontend/widgets/medication_thumbnail.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';

import 'medication_history_fixtures.dart';

class _TestPhotoStore extends ManualMedicationImageStore {
  String? patient;
  int? medication;
  @override
  Future<String> findImagePath({
    required String patientHash,
    required int medicationId,
  }) async {
    patient = patientHash;
    medication = medicationId;
    return File('assets/app_icon/medbuddy_logo.png').absolute.path;
  }
}

// 클래스명: _HistoryServer
// 역할: 이력 조회·쓰기 결과만 메모리에 재현하고 전송 의도를 검사한다.
class _HistoryServer {
  final items = <Map<String, dynamic>>[historyTestEntry(date: '2026-10-17')];
  final writes = <Map<String, dynamic>>[];
  final paths = <String>[];
  final reads = <Uri>[];
  bool failRead = false;
  bool prnEligible = true;
  bool extraPrn = false;
  int? failWriteNumber;
  bool failFirstWrite = false;
  bool malformedFirstWrite = false;
  int? rejectWrite;
  Completer<http.Response>? pendingWrite;
  Completer<http.Response>? pendingRead;

  // 함수역할: 요청 기간을 반영하고 PUT의 상태 변경을 응답에 적용한다. 실패는 선택적으로 주입한다.
  Future<http.Response> respond(http.Request request) async {
    if (request.method == 'GET') {
      reads.add(request.url);
      if (failRead) throw http.ClientException('offline');
      if (pendingRead != null) return pendingRead!.future;
      final start = request.url.queryParameters['start_date']!;
      final end = request.url.queryParameters['end_date']!;
      final body = historyTestBody(
        start: start,
        end: end,
        items: items
            .where(
              (entry) =>
                  (entry['schedule_date'] as String).compareTo(start) >= 0 &&
                  (entry['schedule_date'] as String).compareTo(end) <= 0,
            )
            .toList(),
      );
      if (extraPrn) {
        (body['medications'] as List).add({
          'id': 3,
          'item_name': '두 번째 필요시약',
          'dosing_mode': 'as_needed',
          'dosage_per_time': '1정',
        });
      }
      for (final medication in body['medications'] as List) {
        medication['can_record_as_needed'] =
            prnEligible && medication['dosing_mode'] == 'as_needed';
      }
      return historyTestResponse(body);
    }
    final change = jsonDecode(request.body) as Map<String, dynamic>;
    writes.add(change);
    paths.add(request.url.path);
    if (pendingWrite != null) return pendingWrite!.future;
    if (rejectWrite != null) {
      return historyTestResponse({'detail': 'conflict'}, rejectWrite!);
    }
    if ((failFirstWrite && writes.length == 1) ||
        writes.length == failWriteNumber) {
      throw http.ClientException('connection reset');
    }
    final parts = request.url.pathSegments;
    final id = int.parse(parts[parts.length - 3]);
    final date = parts[parts.length - 2];
    final slot = parts.last;
    final position = items.indexWhere(
      (item) =>
          item['medication_id'] == id &&
          item['schedule_date'] == date &&
          item['slot_key'] == slot,
    );
    final entry = position >= 0
        ? items[position]
        : historyTestEntry(
            id: id,
            name: '테스트 필요시약',
            date: date,
            slot: slot,
            mode: 'as_needed',
          );
    entry.addAll({
      'status': change['status'],
      'actual_taken_at': change['actual_taken_at'],
      'reason': change['reason'],
      'revision': (entry['revision'] as int) + 1,
      'recorded_at': historyTestNow.toIso8601String(),
    });
    if (position < 0) items.add(entry);
    if (malformedFirstWrite && writes.length == 1) {
      return historyTestResponse({'success': 'true'});
    }
    return historyTestResponse({'success': true});
  }
}

// 함수역할: 실제 테마·번역을 적용하고 부모와 동일한 화면 생성자로 테스트한다.
Future<MedicationHistoryControl> _pumpHistory(
  WidgetTester tester,
  _HistoryServer server, {
  bool readOnly = false,
  bool isEnglish = true,
  double textScale = 1,
  FutureOr<void> Function()? onChanged,
  Stream<String?>? sessionChanges,
  bool openToday = true,
  bool initiallyShowExport = false,
  bool isActive = true,
  DateTime Function()? now,
}) async {
  final control = MedicationHistoryControl(
    patientHash: 'test-patient',
    pendingStore: FakeAsNeededPendingStore(),
    readOnly: readOnly,
    client: MockClient(server.respond),
    now: now ?? () => historyTestNow,
    sessionKeyProvider: () => 'test-user',
    sessionChanges: sessionChanges,
  );
  addTearDown(control.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ko')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MedicationHistoryUI(
        patientHash: 'test-patient',
        readOnly: readOnly,
        isEnglish: isEnglish,
        control: control,
        onChanged: onChanged,
        initiallyShowExport: initiallyShowExport,
        isActive: isActive,
      ),
    ),
  );
  await tester.pumpAndSettle();
  // 주간 통계에서 오늘을 선택해 기존 정정·권한 검증에 필요한 상세만 펼친다.
  if (openToday && !server.failRead) {
    final today = find.byKey(const ValueKey('history-week-day-2026-10-17'));
    await tester.scrollUntilVisible(
      today,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(today);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('history-date-navigation')),
    );
    await tester.pumpAndSettle();
  }
  return control;
}

// 화면 상단으로 돌아간 뒤 대상까지 스크롤하여 작은 화면에서도 실제 조작 경로를 사용한다.
Future<void> _revealHistory(WidgetTester tester, Finder target) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, 10000));
  await tester.pumpAndSettle();
  if (target.hitTestable().evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    target,
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

// 함수역할: 실제 스크롤 뒤 정정 버튼을 눌러 편집 대화상자를 연다.
Future<void> _openEditor(WidgetTester tester, {bool isEnglish = true}) async {
  final edit = find.byTooltip(isEnglish ? 'Edit record' : '기록 수정');
  for (
    var scroll = 0;
    scroll < 20 && edit.hitTestable().evaluate().isEmpty;
    scroll++
  ) {
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  expect(edit.hitTestable(), findsOneWidget);
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

// 함수역할: 기록 저장과 확인을 차례로 누르되 네트워크 완료는 호출자가 기다린다.
Future<void> _confirmSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('history-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pump();
}

// 공유 창의 두 날짜 입력을 각각 선택하고 달력의 반환값을 검증 흐름에 전달한다.
Future<void> _chooseExportDate(
  WidgetTester tester,
  String endpoint,
  DateTime? date,
) async {
  await tester.tap(find.byKey(Key('history-export-$endpoint')));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(date);
  await tester.pumpAndSettle();
}

Future<MedicationHistoryControl> _pumpAsNeeded(
  WidgetTester tester,
  _HistoryServer server, {
  bool readOnly = false,
  bool isEnglish = true,
  double textScale = 1,
  Stream<String?>? sessionChanges,
  DateTime Function()? now,
  Duration requestTimeout = const Duration(seconds: 25),
  double leadingHeight = 0,
  ManualMedicationImageStore imageStore = const ManualMedicationImageStore(),
  FakeAsNeededPendingStore? pendingStore,
}) async {
  final control = MedicationHistoryControl(
    patientHash: 'test-patient',
    pendingStore: pendingStore ?? FakeAsNeededPendingStore(),
    readOnly: readOnly,
    client: MockClient(server.respond),
    now: now ?? () => historyTestNow,
    requestTimeout: requestTimeout,
    sessionKeyProvider: () => 'test-user',
    sessionChanges: sessionChanges,
  );
  addTearDown(control.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ko')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          children: [
            if (leadingHeight > 0) SizedBox(height: leadingHeight),
            AsNeededScheduleSection(
              patientHash: 'test-patient',
              isEnglish: isEnglish,
              readOnly: readOnly,
              control: control,
              imageStore: imageStore,
              emptyState: const Text('No medication today'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return control;
}

// 함수역할: 보호자·수정·내보내기와 실패 경로의 UI 회귀 테스트를 등록한다.
void main() {
  // 모든 기간에서 상세는 처음부터 열리고 사용자가 접은 상태는 탭별로 유지된다.
  testWidgets(
    'daily details start open in every period and remain collapsible',
    (tester) async {
      await _pumpHistory(tester, _HistoryServer(), openToday: false);
      for (final period in ['week', 'month', 'custom']) {
        await _revealHistory(tester, find.byKey(Key('history-tab-$period')));
        await tester.tap(find.byKey(Key('history-tab-$period')));
        await tester.pumpAndSettle();
        await _revealHistory(
          tester,
          find.byKey(const Key('history-toggle-details')),
        );
        expect(
          find.byKey(const Key('history-date-navigation')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('history-toggle-details')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-date-navigation')), findsNothing);
      }
      await _revealHistory(tester, find.byKey(const Key('history-tab-week')));
      await tester.tap(find.byKey(const Key('history-tab-week')));
      await tester.pumpAndSettle();
      await _revealHistory(
        tester,
        find.byKey(const Key('history-toggle-details')),
      );
      expect(find.byKey(const Key('history-date-navigation')), findsNothing);
    },
  );

  // 날짜를 확정하면 바로 집계를 바꾸며 중복 기간 표시나 조회 버튼은 두지 않는다.
  testWidgets(
    'custom period automatically applies dates and has no binned chart',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server, openToday: false);
      expect(find.byKey(const Key('history-week-chart')), findsOneWidget);
      await tester.tap(find.byKey(const Key('history-tab-custom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-toggle-chart')), findsNothing);
      expect(find.byKey(const Key('history-week-chart')), findsNothing);
      expect(find.byKey(const Key('history-date-navigation')), findsOneWidget);
      expect(control.snapshot!.range.days, 7);
      expect(find.byKey(const Key('history-apply-range')), findsNothing);
      expect(find.byKey(const Key('history-applied-range')), findsNothing);
      await tester.tap(find.byKey(const Key('history-range-start')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 8, 1));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 8, 1));
      expect(control.snapshot!.range.end, DateTime.utc(2026, 10, 17));
      expect(control.snapshot!.range.days, 78);
      expect(
        server.reads
            .skip(server.reads.length - 3)
            .map(
              (uri) => MedicationHistoryRange(
                MedicationHistoryDates.parse(uri.queryParameters['start_date']),
                MedicationHistoryDates.parse(uri.queryParameters['end_date']),
              ).days,
            ),
        [31, 31, 16],
      );
      await _revealHistory(
        tester,
        find.byKey(const Key('history-select-date')),
      );
      await tester.tap(find.byKey(const Key('history-select-date')));
      await tester.pumpAndSettle();
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(2026, 8, 1));
      expect(picker.lastDate, DateTime(2026, 10, 17));
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 8, 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-previous-day')))
            .onPressed,
        isNull,
      );
      expect(server.writes, isEmpty);
    },
  );

  testWidgets(
    'custom picker prevents reversed ranges and folds are independent by tab',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server, openToday: false);
      await _revealHistory(
        tester,
        find.byKey(const Key('history-toggle-chart')),
      );
      await tester.tap(find.byKey(const Key('history-toggle-chart')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-week-chart')), findsNothing);
      await _revealHistory(tester, find.byKey(const Key('history-tab-custom')));
      await tester.tap(find.byKey(const Key('history-tab-custom')));
      await tester.pumpAndSettle();
      final range = control.snapshot!.range.label;
      final readCount = server.reads.length;
      await tester.tap(find.byKey(const Key('history-range-end')));
      await tester.pumpAndSettle();
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.firstDate, DateTime(2026, 10, 11));
      expect(picker.lastDate, DateTime(2026, 10, 17));
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 10, 1));
      await tester.pumpAndSettle();
      expect(server.reads.length, readCount);
      expect(control.snapshot!.range.label, range);
      await tester.tap(find.byKey(const Key('history-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-week-chart')), findsNothing);
      await tester.tap(find.byKey(const Key('history-tab-custom')));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.label, range);
      expect(find.byKey(const Key('history-apply-range')), findsNothing);
      expect(find.byKey(const Key('history-date-navigation')), findsOneWidget);
    },
  );

  // 취소·동일 날짜는 요청하지 않고 종료일 변경은 한 번만 조회한다. 실패해도 이전 기간 자료를 남기지 않는다.
  testWidgets(
    'automatic range loading ignores cancellation and supports retry',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server, openToday: false);
      await tester.tap(find.byKey(const Key('history-tab-custom')));
      await tester.pumpAndSettle();
      final before = server.reads.length;
      for (final result in <DateTime?>[null, DateTime(2026, 10, 17)]) {
        await tester.tap(find.byKey(const Key('history-range-end')));
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(result);
        await tester.pumpAndSettle();
        expect(server.reads.length, before);
      }
      server.failRead = true;
      await tester.tap(find.byKey(const Key('history-range-end')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 10, 15));
      await tester.pumpAndSettle();
      expect(server.reads.length, before + 1);
      expect(find.byKey(const Key('history-load-error')), findsOneWidget);
      expect(find.byKey(const Key('history-rate-value')), findsNothing);
      server.failRead = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.end, DateTime.utc(2026, 10, 15));
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 11));
      expect(server.reads.length, before + 2);
    },
  );

  // 하루 기록을 불러오는 동안 뒤로가기를 누르면 무시하지 않고 화면을 닫는다(느린 연결에서 최대 25초).
  // 탭으로 유지되는 숨겨진 기록 화면은 앱 복귀마다 서버를 다시 읽지 않는다.
  for (final active in [true, false]) {
    testWidgets('resume reloads only a visible history: $active', (
      tester,
    ) async {
      final server = _HistoryServer();
      await _pumpHistory(
        tester,
        server,
        openToday: false,
        isActive: active,
      );
      final reads = server.reads.length;
      expect(reads, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(server.reads.length, active ? greaterThan(reads) : reads);
    });
  }

  // 탭을 켜 둔 채 주가 바뀌면 지난주 대신 오늘이 속한 주를 다시 읽는다.
  testWidgets('resume after a new week moves the period to today', (
    tester,
  ) async {
    var now = historyTestNow;
    final server = _HistoryServer();
    await _pumpHistory(tester, server, openToday: false, now: () => now);
    final monday = find.byKey(const ValueKey('history-week-day-2026-10-19'));
    expect(monday, findsNothing);
    now = historyTestNow.add(const Duration(days: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(monday, findsOneWidget);
    expect(server.reads.last.queryParameters['start_date'], '2026-10-19');
  });

  // 저장 뒤 다른 화면을 갱신하는 동안에도 빈 화면 대신 진행을 표시한다.
  testWidgets('a saved edit shows progress until the reload starts', (
    tester,
  ) async {
    final refresh = Completer<void>();
    final server = _HistoryServer();
    await _pumpHistory(tester, server, onChanged: () => refresh.future);
    await _openEditor(tester);
    await _confirmSave(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    refresh.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('back while a day loads closes the history', (tester) async {
    final server = _HistoryServer();
    final control = MedicationHistoryControl(
      patientHash: 'test-patient',
      pendingStore: FakeAsNeededPendingStore(),
      client: MockClient(server.respond),
      now: () => historyTestNow,
      sessionKeyProvider: () => 'test-user',
    );
    addTearDown(control.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ko')],
        home: const Scaffold(body: Text('home-root')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MedicationHistoryUI(
            patientHash: 'test-patient',
            isEnglish: true,
            control: control,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final today = find.byKey(const ValueKey('history-week-day-2026-10-17'));
    await tester.scrollUntilVisible(
      today,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(today), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(today);
    await tester.pumpAndSettle();
    server.pendingRead = Completer<http.Response>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(control.busy, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MedicationHistoryUI), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    server.pendingRead!.complete(
      historyTestResponse(
        historyTestBody(start: '2026-10-12', end: '2026-10-17', items: []),
      ),
    );
    await tester.pumpAndSettle();
  });

  // 채팅 카드로 연 기간 화면은 앱이 다시 그려져도(토큰 갱신·언어 변경) 같은 기간이면 다시 시작하지 않는다.
  testWidgets('a rebuilt chat-shared history keeps its session', (
    tester,
  ) async {
    var reads = 0;
    final history = MedicationHistoryControl(
      patientHash: 'test-patient',
      readOnly: true,
      client: MockClient((request) async {
        reads++;
        return historyTestResponse(
          historyTestBody(
            start: request.url.queryParameters['start_date']!,
            end: request.url.queryParameters['end_date']!,
            items: [historyTestEntry(date: '2026-10-17')],
          ),
        );
      }),
      now: () => historyTestNow,
      sessionKeyProvider: () => 'test-user',
    );
    addTearDown(history.dispose);
    late StateSetter rebuildRoot;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuildRoot = setState;
          return MaterialApp(
            navigatorKey: navigator,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('en'), Locale('ko')],
            home: const Scaffold(body: Text('home')),
          );
        },
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          // 채팅 카드처럼 다시 그릴 때마다 새 기간 객체를 만든다.
          builder: (_) => MedicationHistoryUI(
            patientHash: 'test-patient',
            readOnly: true,
            isEnglish: true,
            control: history,
            sharedRange: MedicationHistoryRange(
              DateTime.utc(2026, 10, 16),
              DateTime.utc(2026, 10, 17),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    rebuildRoot(() {});
    await tester.pumpAndSettle();
    expect(history.sessionInvalidated, isFalse);
    expect(reads, 1);
  });

  // 실행 취소 안내는 일정 화면을 떠난 뒤에도 남으므로, 그때 눌러도 실제로 되돌려야 한다.
  testWidgets('the as-needed undo still works after leaving the schedule', (
    tester,
  ) async {
    final server = _HistoryServer();
    final control = MedicationHistoryControl(
      patientHash: 'test-patient',
      pendingStore: FakeAsNeededPendingStore(),
      client: MockClient(server.respond),
      now: () => historyTestNow,
      sessionKeyProvider: () => 'test-user',
    );
    addTearDown(control.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: MedBuddyTheme.light(),
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ListView(
              children: [
                AsNeededScheduleSection(
                  patientHash: 'test-patient',
                  isEnglish: true,
                  control: control,
                  emptyState: const Text('No medication today'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prn-undo-record')), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prn-undo-record')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(server.writes, hasLength(2));
    expect(server.writes.last['status'], 'unrecorded');
    expect(find.text('Dose record undone.'), findsOneWidget);
  });
  for (final readOnly in [false, true]) {
    for (final isEnglish in [false, true]) {
      testWidgets('필요시 복용량 번역: 보호자=$readOnly 영어=$isEnglish', (tester) async {
        final server = _HistoryServer();
        final control = await _pumpAsNeeded(
          tester,
          server,
          readOnly: readOnly,
          isEnglish: isEnglish,
        );
        expect(find.text(isEnglish ? '1 tablet' : '1정'), findsOneWidget);
        expect(find.text(isEnglish ? '1정' : '1 tablet'), findsNothing);
        expect(find.text('테스트 필요시약'), findsOneWidget);
        expect(control.snapshot!.medications.last.dosage, '1정');
        expect(server.writes, isEmpty);
      });
    }
  }

  // 검색 바로가기는 최초 성공 조회 뒤 확인창만 열고 실제 전송·기록 변경을 하지 않는다.
  testWidgets('공유 바로가기는 확인창만 한 번 열고 취소할 수 있다', (tester) async {
    final server = _HistoryServer();
    await _pumpHistory(
      tester,
      server,
      openToday: false,
      initiallyShowExport: true,
    );
    expect(find.byKey(const Key('history-export-start')), findsOneWidget);
    expect(server.writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-export-start')), findsNothing);
    expect(server.writes, isEmpty);
  });

  for (final readOnly in [false, true]) {
    testWidgets('공유 바로가기는 조회 실패 또는 읽기 전용이면 자동으로 열지 않는다: $readOnly', (
      tester,
    ) async {
      final server = _HistoryServer()..failRead = !readOnly;
      await _pumpHistory(
        tester,
        server,
        openToday: false,
        readOnly: readOnly,
        initiallyShowExport: true,
      );
      expect(find.byKey(const Key('history-export-start')), findsNothing);
      expect(server.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('record notice never opens automatically on entry or reopening', (
    tester,
  ) async {
    await _pumpHistory(tester, _HistoryServer());
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('not proof of ingestion'), findsNothing);
    expect(find.textContaining('Time zone: Korea'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'medication_history_notice_seen_v1',
      ),
      isNull,
    );
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Time zone: Korea'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHistory(tester, _HistoryServer(), readOnly: true);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('not proof of ingestion'), findsNothing);
    expect(find.byTooltip('About medication records'), findsNothing);
  });

  testWidgets('status summary has compact spacing without an info control', (
    tester,
  ) async {
    await _pumpHistory(tester, _HistoryServer(), isEnglish: false);
    final date = tester.getRect(
      find.byKey(const Key('history-date-navigation')),
    );
    final summary = tester.getRect(
      find.byKey(const Key('history-status-summary')),
    );
    final morning = tester.getRect(
      find.byKey(const Key('history-slot-morning')),
    );
    expect(summary.top - date.bottom, closeTo(4, 0.01));
    expect(morning.top - summary.bottom, closeTo(8, 0.01));
    final entry = find
        .descendant(
          of: find.byKey(const Key('history-slot-morning')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.key.toString().contains('history-entry-'),
          ),
        )
        .first;
    expect(tester.getSize(entry).height, lessThanOrEqualTo(68));
    final section = tester.getRect(
      find.byKey(const Key('history-section-details')),
    );
    expect(morning.left - section.left, closeTo(17, 0.01));
    expect(section.right - morning.right, closeTo(17, 0.01));
    final card = tester.widget<Container>(
      find.byKey(const Key('history-slot-morning')),
    );
    expect(
      (card.decoration! as BoxDecoration).borderRadius,
      MedBuddyRadii.card,
    );
    expect(
      tester
          .widget<Wrap>(find.byKey(const Key('history-status-summary')))
          .alignment,
      WrapAlignment.center,
    );
    expect(find.byTooltip('복약 기록 안내'), findsNothing);
  });

  // 안내 팝업 대신 그래프 표시만 바뀌며 조회 자료와 선택한 날짜는 유지된다.
  testWidgets(
    'summary toggles count without changing history or selected day',
    (tester) async {
      final control = await _pumpHistory(tester, _HistoryServer());
      final snapshot = control.snapshot;
      final day = control.requestedRange;
      await _revealHistory(
        tester,
        find.byKey(const Key('history-rate-toggle')),
      );
      await tester.tap(find.byKey(const Key('history-rate-toggle')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('history-rate-value'))).data,
        contains('/'),
      );
      expect(control.snapshot, same(snapshot));
      expect(find.byType(AlertDialog), findsNothing);
      expect(control.requestedRange, same(day));
      expect(find.byKey(const Key('history-section-summary')), findsOneWidget);
      expect(find.byKey(const Key('history-section-dates')), findsOneWidget);
      expect(find.text('2026-10-12 ~ 2026-10-18'), findsOneWidget);
      await _revealHistory(
        tester,
        find.byKey(const Key('history-section-details')),
      );
      expect(find.byKey(const Key('history-section-details')), findsOneWidget);
    },
  );

  testWidgets('large text ratio toggle has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpHistory(
      tester,
      _HistoryServer(),
      isEnglish: false,
      textScale: 2,
    );
    await _revealHistory(tester, find.byKey(const Key('history-rate-toggle')));
    await tester.tap(find.byKey(const Key('history-rate-toggle')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('복약 기록 안내'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'daily arrows and calendar select one day within the history window',
    (tester) async {
      final server = _HistoryServer();
      server.items.add(historyTestEntry(name: 'Yesterday medication'));
      final control = await _pumpHistory(tester, server);
      expect(control.requestedRange!.days, 6);
      expect(control.requestedRange!.start, DateTime.utc(2026, 10, 12));
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-next-day')))
            .onPressed,
        isNull,
      );
      expect(find.text('Yesterday medication'), findsNothing);
      await tester.tap(find.byKey(const Key('history-previous-day')));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 12));
      expect(find.text('Yesterday medication'), findsOneWidget);
      expect(find.text('테스트 주간약'), findsNothing);
      await tester.tap(find.byKey(const Key('history-next-day')));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 12));
      await tester.tap(find.byKey(const Key('history-select-date')));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.lastDate, DateTime(2026, 10, 17));
      expect(calendar.firstDate, DateTime(2026, 10, 12));
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 10, 12));
      await tester.pumpAndSettle();
      expect(control.requestedRange!.days, 6);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-previous-day')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('No scheduled doses or records on this date.'),
        findsOneWidget,
      );
      expect(server.writes, isEmpty);
    },
  );

  testWidgets(
    'changing period clears rows and blocks duplicate navigation while loading',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server);
      final pending = Completer<http.Response>();
      server.pendingRead = pending;
      final previous = find.byKey(const Key('history-previous-week'));
      await _revealHistory(tester, previous);
      await tester.tap(previous);
      await tester.pump();
      expect(find.text('테스트 주간약'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-next-week')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('history-rate-value')), findsNothing);
      pending.complete(
        historyTestResponse(
          historyTestBody(start: '2026-10-05', end: '2026-10-11', items: []),
        ),
      );
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 5));
      expect(control.snapshot!.items, isEmpty);
    },
  );

  testWidgets(
    'slot cards follow the schedule order and keep PRN events separate',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = _HistoryServer();
      server.items
        ..clear()
        ..addAll([
          historyTestEntry(id: 1, date: '2026-10-17', slot: 'evening'),
          historyTestEntry(id: 1, date: '2026-10-17', slot: 'morning'),
          historyTestEntry(id: 1, date: '2026-10-17', slot: 'lunch'),
          historyTestEntry(
            id: 2,
            date: '2026-10-17',
            mode: 'as_needed',
            slot: 'as_needed:12345678-1234-4234-8234-123456789012',
          ),
        ]);
      await _pumpHistory(tester, server, readOnly: true);
      final slots = ['morning', 'lunch', 'evening', 'as_needed'];
      for (var index = 0; index < slots.length - 1; index++) {
        expect(
          tester.getTopLeft(find.byKey(Key('history-slot-${slots[index]}'))).dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(Key('history-slot-${slots[index + 1]}')))
                .dy,
          ),
        );
      }
      expect(find.byTooltip('Edit record'), findsNothing);
    },
  );

  testWidgets(
    'export can select several days without changing the visible day',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server);
      final original = control.snapshot;
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
      await _chooseExportDate(tester, 'end', DateTime(2026, 10, 16));
      expect(find.textContaining('2026-10-11'), findsOneWidget);
      expect(find.text('2026-10-16'), findsOneWidget);
      // 달력의 한 달 조회와 오늘 조회 뒤로는 날짜를 골라도 다시 읽지 않는다.
      expect(server.reads, hasLength(1));
      expect(control.snapshot, same(original));
      expect(control.requestedRange!.days, 6);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _revealHistory(
        tester,
        find.byKey(const Key('history-select-date')),
      );
      expect(find.text('2026-10-17'), findsOneWidget);
      expect(server.writes, isEmpty);
    },
  );

  // 보호자는 이력을 볼 수 있지만 정정이나 필요시 복용 생성 명령을 받지 않는다.
  testWidgets(
    'caregiver history is read only with explicit self-report label',
    (tester) async {
      final server = _HistoryServer();
      await _pumpHistory(tester, server, readOnly: true);
      expect(find.text('Patient records · Read only'), findsOneWidget);
      expect(find.textContaining('not proof of ingestion'), findsNothing);
      expect(find.byTooltip('About medication records'), findsNothing);
      expect(find.byTooltip('Edit record'), findsNothing);
      expect(find.byKey(const Key('history-add-prn')), findsNothing);
      expect(find.byTooltip('Share'), findsOneWidget);
      expect(server.writes, isEmpty);
    },
  );

  // 조회 실패에서 이전 자료나 성공 통계를 보여 주지 않고 재시도를 제공한다.
  testWidgets('offline read exposes retry and disables export', (tester) async {
    final server = _HistoryServer()..failRead = true;
    await _pumpHistory(tester, server);
    expect(find.byKey(const Key('history-load-error')), findsOneWidget);
    final errorBottom = tester
        .getBottomLeft(find.byKey(const Key('history-load-error')))
        .dy;
    final retryTop = tester
        .getTopLeft(find.widgetWithText(OutlinedButton, 'Retry'))
        .dy;
    expect(retryTop - errorBottom, greaterThanOrEqualTo(12));
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Share',
            ),
          )
          .onPressed,
      isNull,
    );
    server.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-load-error')), findsNothing);
    await _revealHistory(tester, find.text('테스트 주간약'));
    expect(find.text('테스트 주간약'), findsOneWidget);
  });

  // 예정일이 어제인 약도 실제 날짜를 오늘로 선택해 기록할 수 있다.
  testWidgets(
    'late dose can select today as actual date without moving scheduled day',
    (tester) async {
      final server = _HistoryServer();
      server.items.single['schedule_date'] = '2026-10-16';
      var changes = 0;
      await _pumpHistory(tester, server, onChanged: () => changes++);
      await tester.tap(find.byKey(const Key('history-previous-day')));
      await tester.pumpAndSettle();
      await _openEditor(tester);
      await tester.tap(
        find.widgetWithText(RadioListTile<MedicationHistoryStatus>, 'Taken'),
      );
      await tester.pumpAndSettle();
      final dateButton = find.widgetWithText(OutlinedButton, '2026-10-16');
      await tester.ensureVisible(dateButton);
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('17'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _confirmSave(tester);
      await tester.pumpAndSettle();
      expect(server.paths.single, endsWith('/1/2026-10-16/morning'));
      expect(
        server.writes.single['actual_taken_at'],
        '2026-10-17T06:00:00.000Z',
      );
      expect(changes, 1);
      expect(find.text('The record was saved.'), findsOneWidget);
      expect(
        find.textContaining('Actual taken: 2026-10-17 15:00'),
        findsOneWidget,
      );
    },
  );

  // 미래 복용 시각 검증에 실패한 뒤 건너뜀을 선택하면 관련 없는 오류가 남지 않는다.
  testWidgets('future taken time error clears when status changes to skipped', (
    tester,
  ) async {
    final server = _HistoryServer();
    server.items
      ..clear()
      ..add({
        ...historyTestEntry(date: '2026-10-17', status: 'taken'),
        'actual_taken_at': '2026-10-17T14:11:00Z',
      });
    await _pumpHistory(tester, server);
    await _openEditor(tester);
    await tester.tap(find.byKey(const Key('history-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-save-error')), findsOneWidget);
    expect(server.writes, isEmpty);
    await tester.tap(
      find.widgetWithText(RadioListTile<MedicationHistoryStatus>, 'Skipped'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-save-error')), findsNothing);
    await _confirmSave(tester);
    await tester.pumpAndSettle();
    expect(server.writes.single['status'], 'skipped');
    expect(server.writes.single['actual_taken_at'], isNull);
  });

  // 실제 날짜 또는 시각을 수정하면 오래된 검증 안내를 지우되 선택 취소에는 유지한다.
  for (final changeDate in [true, false]) {
    testWidgets(
      'future error clears on ${changeDate ? 'date' : 'time'} edit but not cancellation',
      (tester) async {
        final server = _HistoryServer();
        server.items
          ..clear()
          ..add({
            ...historyTestEntry(date: '2026-10-17', status: 'taken'),
            'actual_taken_at': '2026-10-17T14:11:00Z',
          });
        await _pumpHistory(tester, server);
        await _openEditor(tester);
        await tester.tap(find.byKey(const Key('history-save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-save-error')), findsOneWidget);
        final button = find.widgetWithText(
          OutlinedButton,
          changeDate ? '2026-10-17' : '23:11',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final picker = changeDate
            ? find.byType(DatePickerDialog)
            : find.byType(TimePickerDialog);
        Navigator.of(tester.element(picker)).pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-save-error')), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        Navigator.of(tester.element(picker)).pop(
          changeDate
              ? DateTime(2026, 10, 16)
              : const TimeOfDay(hour: 14, minute: 11),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-save-error')), findsNothing);
        expect(server.writes, isEmpty);
      },
    );
  }

  // 건너뜀을 선택할 때만 복용 미완료와 알림 유지 정책을 한국어·영어로 안내한다.
  for (final english in [false, true]) {
    testWidgets(
      'skipped notice explains unchanged alerts in ${english ? 'English' : 'Korean'}',
      (tester) async {
        await _pumpHistory(tester, _HistoryServer(), isEnglish: english);
        await _openEditor(tester, isEnglish: english);
        expect(find.byKey(const Key('history-skipped-notice')), findsNothing);
        await tester.tap(
          find.widgetWithText(
            RadioListTile<MedicationHistoryStatus>,
            english ? 'Skipped' : '건너뜀',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            english
                ? 'Skipped doses are not marked as taken. Existing dose reminders and missed-dose alerts remain active.'
                : '건너뛴 기록은 복용 완료로 처리되지 않으며 기존 복약·미복약 알림은 유지됩니다.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.widgetWithText(
            RadioListTile<MedicationHistoryStatus>,
            english ? 'Taken' : '복용함',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-skipped-notice')), findsNothing);
      },
    );
  }

  // 건너뜀 이유는 명시적으로 확인한 뒤 저장되며 실제 복용 시각은 보내지 않는다.
  testWidgets(
    'skipped reason requires confirmation and is saved with revision',
    (tester) async {
      final server = _HistoryServer();
      await _pumpHistory(tester, server);
      await _openEditor(tester);
      await tester.tap(
        find.widgetWithText(RadioListTile<MedicationHistoryStatus>, 'Skipped'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('history-skip-reason')),
        'Left the medicine at home',
      );
      await tester.tap(find.byKey(const Key('history-save')));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
      expect(find.text('Save this record?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(server.writes.single['status'], 'skipped');
      expect(server.writes.single['reason'], 'Left the medicine at home');
      expect(server.writes.single['actual_taken_at'], isNull);
      expect(server.writes.single['expected_revision'], 0);
    },
  );

  // 실패 뒤 같은 기록 재시도는 추가 이벤트나 새 작업 ID를 만들지 않는다.
  testWidgets(
    'write failure never shows success and retries identical intent',
    (tester) async {
      final server = _HistoryServer()..failFirstWrite = true;
      var changes = 0;
      await _pumpHistory(tester, server, onChanged: () => changes++);
      await _openEditor(tester);
      await _confirmSave(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-save-error')), findsOneWidget);
      expect(find.text('The record was saved.'), findsNothing);
      expect(changes, 0);
      await tester.tap(find.text('Retry record'));
      await tester.pumpAndSettle();
      expect(server.writes, hasLength(2));
      expect(server.writes[0], server.writes[1]);
      expect(changes, 1);
    },
  );

  // 잘못된 성공 응답도 전송 유실처럼 취급해 확인한 내용과 작업 ID를 유지한다.
  testWidgets(
    'malformed acknowledgement keeps confirmed fields locked for retry',
    (tester) async {
      final server = _HistoryServer()..malformedFirstWrite = true;
      await _pumpHistory(tester, server);
      await _openEditor(tester);
      await _confirmSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('The record was saved.'), findsNothing);
      expect(find.text('Retry record'), findsOneWidget);
      expect(
        tester
            .widget<RadioListTile<MedicationHistoryStatus>>(
              find.widgetWithText(
                RadioListTile<MedicationHistoryStatus>,
                'Taken',
              ),
            )
            .enabled,
        isFalse,
      );
      tester
          .widget<RadioGroup<MedicationHistoryStatus>>(
            find.byType(RadioGroup<MedicationHistoryStatus>),
          )
          .onChanged(MedicationHistoryStatus.skipped);
      await tester.pump();
      expect(find.byKey(const Key('history-save-error')), findsOneWidget);
      await tester.tap(find.text('Retry record'));
      await tester.pumpAndSettle();
      expect(server.writes[0], server.writes[1]);
    },
  );

  // 전송 도중 버튼을 다시 누르거나 편집창을 닫아 중복 저장하지 못하게 한다.
  testWidgets('pending write disables duplicate submit and close', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final server = _HistoryServer()..pendingWrite = pending;
    await _pumpHistory(tester, server);
    await _openEditor(tester);
    await _confirmSave(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .onPressed,
      isNull,
    );
    expect(server.writes, hasLength(1));
    pending.complete(historyTestResponse({'success': true}));
    await tester.pumpAndSettle();
    expect(find.text('The record was saved.'), findsOneWidget);
  });

  // 버전 충돌 후 재시도로 타 기기의 정정을 덮어쓰지 않는다.
  testWidgets(
    'revision conflict offers close and refresh instead of blind retry',
    (tester) async {
      final server = _HistoryServer()..rejectWrite = 409;
      await _pumpHistory(tester, server);
      await _openEditor(tester);
      await _confirmSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('Close and refresh'), findsOneWidget);
      expect(find.byKey(const Key('history-save')), findsNothing);
      expect(find.text('The record was saved.'), findsNothing);
      tester
          .widget<RadioGroup<MedicationHistoryStatus>>(
            find.byType(RadioGroup<MedicationHistoryStatus>),
          )
          .onChanged(MedicationHistoryStatus.skipped);
      await tester.pump();
      expect(find.byKey(const Key('history-save-error')), findsOneWidget);
      expect(
        find.textContaining('The record changed on another device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close and refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Edit medication record'), findsNothing);
    },
  );

  testWidgets('history never offers new dose recording', (tester) async {
    await _pumpHistory(tester, _HistoryServer());
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-add-prn')), findsNothing);
    expect(find.byTooltip('Edit record'), findsOneWidget);
  });

  // 일정에서 한 날짜의 필요시 복용을 두 번 체크하면 두 개의 고유 이벤트가 된다.
  testWidgets('two as-needed doses use different slot UUIDs on the same day', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    for (var count = 0; count < 2; count++) {
      ScaffoldMessenger.of(
        tester.element(find.byType(ListView)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('schedule-prn-take-2')),
        200,
      );
      await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<MedicationHistoryStatus>), findsNothing);
      if (count > 0) {
        expect(find.textContaining('instead of 1'), findsOneWidget);
        await tester.tap(find.byKey(const Key('prn-confirm-additional')));
        await tester.pumpAndSettle();
      } else {
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          server.writes,
          hasLength(1),
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join('|'),
        );
      }
    }
    expect(server.paths, hasLength(2));
    expect(server.paths[0], isNot(server.paths[1]));
    expect(
      server.paths.every((path) => path.contains('/2/2026-10-17/as_needed:')),
      isTrue,
    );
    expect(
      server.items.where((item) => item['medication_id'] == 2),
      hasLength(2),
    );
    expect(find.text('2 doses today'), findsOneWidget);
  });

  testWidgets('ineligible PRN cannot create a new dose', (tester) async {
    await _pumpAsNeeded(tester, _HistoryServer()..prnEligible = false);
    expect(find.byKey(const Key('schedule-prn-take-2')), findsNothing);
    expect(find.text('No medication today'), findsOneWidget);
  });

  testWidgets(
    'PRN uses patient-scoped local photo and opens existing image viewer',
    (tester) async {
      final store = _TestPhotoStore();
      await _pumpAsNeeded(tester, _HistoryServer(), imageStore: store);
      final photo = tester.widget<MedicationThumbnail>(
        find.byKey(const Key('schedule-prn-thumbnail-2')),
      );
      expect(store.patient, 'test-patient');
      expect(store.medication, 2);
      expect(
        photo.localImagePath,
        File('assets/app_icon/medbuddy_logo.png').absolute.path,
      );
      await tester.tap(find.byKey(const Key('schedule-prn-thumbnail-2')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
    },
  );

  testWidgets('undo right after a PRN dose marks only that record unrecorded', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.text('1 dose today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prn-undo-record')));
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(2));
    expect(server.paths[1], server.paths[0]);
    expect(server.writes[1]['status'], 'unrecorded');
    expect(server.writes[1]['expected_revision'], 1);
    expect(server.writes[1]['actual_taken_at'], isNull);
    expect(
      server.writes[1]['operation_id'],
      isNot(server.writes[0]['operation_id']),
    );
    expect(find.text('Dose record undone.'), findsOneWidget);
    expect(find.text('1 dose today'), findsNothing);
    // 되돌린 뒤 다시 누르면 추가 복용 확인 없이 첫 복용으로 기록한다.
    ScaffoldMessenger.of(
      tester.element(find.byType(ListView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(server.writes, hasLength(3));
    expect(server.paths[2], isNot(server.paths[0]));
  });

  testWidgets('undo leaves an earlier dose of the same day as it was', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(ListView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prn-confirm-additional')));
    await tester.pumpAndSettle();
    expect(find.text('2 doses today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prn-undo-record')));
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(3));
    expect(server.paths[2], server.paths[1]);
    expect(server.writes[2]['status'], 'unrecorded');
    expect(find.text('1 dose today'), findsOneWidget);
  });

  // 재시작 전에 확인하지 못한 어제 기록을 이어 보내면, 오늘 목록에서 되돌릴 수 없는 실행 취소 대신
  // 오늘 복용은 다시 누르라고 안내한다.
  testWidgets('resending an earlier day\'s PRN dose asks for a new tap today', (
    tester,
  ) async {
    final server = _HistoryServer();
    final store = FakeAsNeededPendingStore()
      ..batches['test-patient'] = [
        MedicationHistoryChange(
          entry: MedicationHistoryEntry(
            medicationId: 2,
            itemName: '테스트 필요시약',
            scheduleDate: DateTime.utc(2026, 10, 16),
            slotKey: 'as_needed:12345678-1234-4234-8234-123456789012',
            status: MedicationHistoryStatus.unrecorded,
            revision: 0,
            dosingMode: 'as_needed',
          ),
          status: MedicationHistoryStatus.taken,
          operationId: '22345678-1234-4234-8234-123456789012',
          actualTakenAt: DateTime.utc(2026, 10, 16, 3),
        ),
      ];
    await _pumpAsNeeded(tester, server, pendingStore: store);
    await tester.scrollUntilVisible(
      find.byKey(const Key('schedule-prn-take-2')),
      200,
    );
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(server.paths.single, contains('/2/2026-10-16/as_needed:'));
    expect(find.byKey(const Key('prn-earlier-record-sent')), findsOneWidget);
    expect(find.byKey(const Key('prn-undo-record')), findsNothing);
    expect(store.batches['test-patient'], isEmpty);
  });

  // 기기 저장소를 열지 못해도 필요시 목록과 횟수는 보이고, 중복될 수 있는 새 기록만 막는다.
  testWidgets('PRN list stays visible when the pending store fails', (
    tester,
  ) async {
    final server = _HistoryServer();
    final store = FakeAsNeededPendingStore()..failRead = true;
    await _pumpAsNeeded(tester, server, pendingStore: store);
    await tester.scrollUntilVisible(
      find.byKey(const Key('schedule-prn-take-2')),
      200,
    );
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(server.writes, isEmpty);
    expect(
      find.textContaining('Device storage could not be opened'),
      findsOneWidget,
    );
    store.failRead = false;
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(1));
  });

  testWidgets('a failed PRN undo explains where to correct the record', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    server.failWriteNumber = 2;
    await tester.tap(find.byKey(const Key('prn-undo-record')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be undone'), findsOneWidget);
    expect(find.text('Dose record undone.'), findsNothing);
    expect(find.text('1 dose today'), findsOneWidget);
  });

  // 복용 간격이 정해진 약을 다시 먹기 전에 오늘 마지막 복용 시각과 지난 시간을 함께 보여 준다.
  testWidgets('another PRN dose shows when the last one was taken', (
    tester,
  ) async {
    final server = _HistoryServer();
    server.items.add({
      ...historyTestEntry(
        id: 2,
        name: '테스트 필요시약',
        date: '2026-10-17',
        slot: 'as_needed:12345678-1234-4234-8234-123456789012',
        mode: 'as_needed',
        status: 'taken',
        revision: 1,
      ),
      'actual_taken_at': '2026-10-17T03:30:00Z',
      'recorded_at': '2026-10-17T03:31:00Z',
    });
    await _pumpAsNeeded(tester, server);
    await tester.scrollUntilVisible(
      find.byKey(const Key('schedule-prn-take-2')),
      200,
    );
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('instead of 1'), findsOneWidget);
    // 12:30(한국 시간)에 먹었고 지금은 15:00이다.
    expect(
      find.textContaining('Last dose at 12:30 (2 h 30 min ago)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.writes, isEmpty);
  });

  testWidgets('a PRN dose taken under a minute ago reads just now', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    await tester.scrollUntilVisible(
      find.byKey(const Key('schedule-prn-take-2')),
      200,
    );
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(ListView)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Last dose at 15:00 (just now)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('repeat dose cancellation does not change the count', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('instead of 1'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(1));
    expect(find.text('1 dose today'), findsOneWidget);
  });

  testWidgets(
    'bulk checks unchecked medicines before confirming additional doses',
    (tester) async {
      final server = _HistoryServer()..extraPrn = true;
      await _pumpAsNeeded(tester, server);
      await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('schedule-entire-slot-toggle-as_needed')),
      );
      await tester.pumpAndSettle();
      expect(server.writes, hasLength(2));
      expect(server.paths.last, contains('/3/'));
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(
        find.byKey(const Key('schedule-entire-slot-toggle-as_needed')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('instead of 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prn-confirm-additional')));
      await tester.pumpAndSettle();
      expect(server.writes, hasLength(4));
      expect(find.text('2 doses today'), findsNWidgets(2));
    },
  );

  testWidgets('partially saved bulk retries only remaining intent', (
    tester,
  ) async {
    final server = _HistoryServer()
      ..extraPrn = true
      ..failWriteNumber = 2;
    await _pumpAsNeeded(tester, server);
    await tester.tap(
      find.byKey(const Key('schedule-entire-slot-toggle-as_needed')),
    );
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(2));
    expect(find.byKey(const Key('prn-save-error')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('schedule-entire-slot-toggle-as_needed')),
    );
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(3));
    expect(server.paths[1], server.paths[2]);
    expect(server.writes[1], server.writes[2]);
    expect(find.text('1 dose today'), findsNWidgets(2));
  });

  testWidgets('confirmed server rejection does not leave all checks blocked', (
    tester,
  ) async {
    final server = _HistoryServer()..rejectWrite = 422;
    final control = await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(control.pendingAsNeededChanges, isEmpty);
    server.rejectWrite = null;
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.text('1 dose today'), findsOneWidget);
  });

  testWidgets(
    'history status is text aligned with record details without check icons',
    (tester) async {
      await _pumpHistory(tester, _HistoryServer());
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.text('Unrecorded'), findsOneWidget);
    },
  );

  testWidgets(
    'PRN rows include medication thumbnail and no taken text button',
    (tester) async {
      await _pumpAsNeeded(tester, _HistoryServer());
      expect(find.byKey(const Key('schedule-prn-thumbnail-2')), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Taken'), findsNothing);
      await tester.tap(find.byKey(const Key('prn-reminder')));
      await tester.pumpAndSettle();
      expect(find.text('As-needed check reminder'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    },
  );

  testWidgets('saving a PRN dose keeps the scrolled card in place', (
    tester,
  ) async {
    await _pumpAsNeeded(tester, _HistoryServer(), leadingHeight: 900);
    await tester.scrollUntilVisible(
      find.byKey(const Key('schedule-prn-take-2')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, closeTo(before, 2));
    // 실행 취소가 있는 저장 알림은 일반 복용과 같이 5초 동안 보인다.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('schedule-prn-take-2')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('PRN loading failure offers refresh not an empty schedule', (
    tester,
  ) async {
    final server = _HistoryServer()..failRead = true;
    await _pumpAsNeeded(tester, server);
    expect(find.byKey(const Key('schedule-prn-error')), findsOneWidget);
    expect(find.text('No medication today'), findsNothing);
    server.failRead = false;
    await tester.tap(find.byTooltip('Refresh as-needed medication'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-prn-take-2')), findsOneWidget);
  });

  testWidgets('PRN retry preserves event and operation after lost response', (
    tester,
  ) async {
    final server = _HistoryServer()..failFirstWrite = true;
    var now = historyTestNow;
    await _pumpAsNeeded(tester, server, now: () => now);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prn-save-error')), findsOneWidget);
    now = now.add(const Duration(days: 1));
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(server.paths.toSet(), hasLength(1));
    expect(server.writes[0], server.writes[1]);
    expect(
      server.items.where((item) => item['medication_id'] == 2),
      hasLength(1),
    );
  });

  testWidgets('PRN double tap and pending save cannot duplicate a dose', (
    tester,
  ) async {
    final server = _HistoryServer()..pendingWrite = Completer<http.Response>();
    await _pumpAsNeeded(tester, server);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.tap(
      find.byKey(const Key('schedule-prn-take-2')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsNothing);
    expect(server.writes, hasLength(1));
    server.pendingWrite!.complete(historyTestResponse({'success': true}));
    await tester.pumpAndSettle();
  });

  testWidgets('uncertain PRN survives closing and reopening the schedule', (
    tester,
  ) async {
    final lateResponse = Completer<http.Response>();
    final server = _HistoryServer()..pendingWrite = lateResponse;
    final control = await _pumpAsNeeded(
      tester,
      server,
      requestTimeout: const Duration(milliseconds: 100),
    );
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prn-save-error')), findsOneWidget);
    expect(control.pendingAsNeededChange, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              AsNeededScheduleSection(
                patientHash: 'test-patient',
                isEnglish: true,
                control: control,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    server.pendingWrite = null;
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    lateResponse.complete(historyTestResponse({'success': true}));
    await tester.pumpAndSettle();
    expect(server.writes, hasLength(2));
    expect(server.writes[0], server.writes[1]);
    expect(server.paths.toSet(), hasLength(1));
    expect(control.pendingAsNeededChange, isNull);
    expect(find.text('1 dose today'), findsOneWidget);
  });

  testWidgets('read-only PRN section cannot record', (tester) async {
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server, readOnly: true);
    expect(find.text('As-needed medication'), findsOneWidget);
    expect(find.text('Patient-reported doses'), findsOneWidget);
    expect(find.text('테스트 필요시약'), findsOneWidget);
    expect(find.text('0 doses today'), findsOneWidget);
    expect(find.byKey(const Key('schedule-prn-thumbnail-2')), findsOneWidget);
    expect(find.byKey(const Key('schedule-prn-take-2')), findsNothing);
    expect(find.byKey(const Key('prn-reminder')), findsNothing);
    expect(
      find.byKey(const Key('schedule-entire-slot-toggle-as_needed')),
      findsNothing,
    );
    expect(server.writes, isEmpty);
  });

  testWidgets('session switch hides open PRN details and prevents save', (
    tester,
  ) async {
    final changes = StreamController<String?>.broadcast();
    addTearDown(changes.close);
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server, sessionChanges: changes.stream);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    changes.add('another-user');
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prn-confirm-additional')))
          .onPressed,
      isNull,
    );
    expect(server.writes, hasLength(1));
  });

  testWidgets('day change while PRN confirmation is open blocks stale date', (
    tester,
  ) async {
    var now = historyTestNow;
    final server = _HistoryServer();
    await _pumpAsNeeded(tester, server, now: () => now);
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
    await tester.pumpAndSettle();
    now = now.add(const Duration(days: 1));
    await tester.tap(find.byKey(const Key('prn-confirm-additional')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prn-save-error')), findsOneWidget);
    expect(server.writes, hasLength(1));
    expect(server.reads.last.queryParameters['start_date'], '2026-10-18');
  });

  for (final english in [false, true]) {
    testWidgets(
      'PRN section and confirmation fit large text english=$english',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpAsNeeded(
          tester,
          _HistoryServer(),
          isEnglish: english,
          textScale: 2,
        );
        await tester.ensureVisible(
          find.byKey(const Key('schedule-prn-take-2')),
        );
        await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('schedule-prn-take-2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 기존 필요시 이벤트 정정은 새 복용을 만들지 않고 원래 키와 버전을 사용한다.
  // 한 달 달력: 날짜별 정기 복용 기록 수·색, 필요시 표시, 날짜 진입과 복귀, 조회 가능 기간.
  group('month calendar', () {
    _HistoryServer monthServer() {
      final server = _HistoryServer();
      server.items
        ..clear()
        ..addAll([
          historyTestEntry(date: '2026-10-16', status: 'taken', revision: 1),
          historyTestEntry(date: '2026-10-16', slot: 'evening'),
          historyTestEntry(date: '2026-10-15', status: 'taken', revision: 1),
          historyTestEntry(date: '2026-10-14'),
          historyTestEntry(
            id: 2,
            name: '테스트 필요시약',
            date: '2026-10-14',
            slot: 'as_needed:12345678-1234-4234-8234-123456789012',
            mode: 'as_needed',
            status: 'taken',
            revision: 1,
          ),
        ]);
      return server;
    }

    Finder day(String date) => find.byKey(ValueKey('history-month-day-$date'));

    Future<void> openMonth(
      WidgetTester tester,
      _HistoryServer server, {
      double textScale = 1,
      bool isEnglish = true,
    }) async {
      await _pumpHistory(
        tester,
        server,
        openToday: false,
        textScale: textScale,
        isEnglish: isEnglish,
      );
      await _revealHistory(tester, find.byKey(const Key('history-tab-month')));
      await tester.tap(find.byKey(const Key('history-tab-month')));
      await tester.pumpAndSettle();
    }

    // 달력 칸은 하위 의미 정보를 제외하므로 화면 낭독기의 누르기가 날짜를 골라야 한다.
    testWidgets('a calendar day exposes its tap to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openMonth(tester, monthServer());
      await _revealHistory(tester, day('2026-10-16'));
      final cell = tester
          .widgetList<Semantics>(
            find.ancestor(of: day('2026-10-16'), matching: find.byType(Semantics)),
          )
          .firstWhere((widget) => widget.properties.label?.contains('16') ?? false);
      expect(cell.properties.onTap, isNotNull);
      handle.dispose();
    });

    testWidgets('monthly tab reads the month and retains count calendar', (
      tester,
    ) async {
      final server = monthServer();
      await openMonth(tester, server);
      await _revealHistory(tester, day('2026-10-16'));
      expect(find.byKey(const Key('history-month-calendar')), findsOneWidget);
      expect(server.reads, hasLength(2));
      expect(server.reads.last.queryParameters['start_date'], '2026-10-01');
      expect(server.reads.last.queryParameters['end_date'], '2026-10-17');
      expect(
        find.descendant(of: day('2026-10-16'), matching: find.text('1/2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: day('2026-10-15'), matching: find.text('1/1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: day('2026-10-14'), matching: find.text('0/1')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Day 14, 0 of 1 recorded as taken, as-needed 1$'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<InkWell>(day('2026-10-18')).onTap, isNull);
      expect(
        tester
            .getRect(
              find.descendant(of: day('2026-10-16'), matching: find.text('16')),
            )
            .top,
        tester
            .getRect(
              find.descendant(of: day('2026-10-17'), matching: find.text('17')),
            )
            .top,
      );
    });
    testWidgets(
      'day selection opens inline details without refetching the period',
      (tester) async {
        final server = monthServer();
        await openMonth(tester, server);
        await _revealHistory(
          tester,
          find.byKey(const Key('history-toggle-details')),
        );
        expect(
          find.byKey(const Key('history-date-navigation')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('history-toggle-details')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-date-navigation')), findsNothing);
        await _revealHistory(tester, day('2026-10-16'));
        await tester.tap(day('2026-10-16'));
        await tester.pumpAndSettle();
        await _revealHistory(
          tester,
          find.byKey(const Key('history-select-date')),
        );
        expect(find.text('2026-10-16'), findsOneWidget);
        expect(server.reads, hasLength(2));
        await _revealHistory(
          tester,
          find.byKey(const Key('history-toggle-details')),
        );
        await tester.tap(find.byKey(const Key('history-toggle-details')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-date-navigation')), findsNothing);
        await _revealHistory(
          tester,
          find.byKey(const Key('history-toggle-chart')),
        );
        await tester.tap(find.byKey(const Key('history-toggle-chart')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-month-calendar')), findsNothing);
      },
    );
    testWidgets('earlier months stop at the 90-day history window', (
      tester,
    ) async {
      final server = monthServer();
      await openMonth(tester, server);
      for (final title in ['2026.09', '2026.08', '2026.07']) {
        await tester.tap(find.byKey(const Key('history-previous-month')));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
      }
      expect(server.reads.last.queryParameters['start_date'], '2026-07-20');
      expect(server.reads.last.queryParameters['end_date'], '2026-07-31');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-previous-month')))
            .onPressed,
        isNull,
      );
      await _revealHistory(tester, day('2026-07-20'));
      expect(tester.widget<InkWell>(day('2026-07-19')).onTap, isNull);
      expect(tester.widget<InkWell>(day('2026-07-20')).onTap, isNotNull);
      await _revealHistory(tester, find.byKey(const Key('history-next-month')));
      await tester.tap(find.byKey(const Key('history-next-month')));
      await tester.pumpAndSettle();
      expect(find.text('2026.08'), findsOneWidget);
    });
    testWidgets('a failed month read offers a retry with no stale chart', (
      tester,
    ) async {
      final server = monthServer()..failRead = true;
      await openMonth(tester, server);
      expect(find.byKey(const Key('history-load-error')), findsOneWidget);
      expect(find.byKey(const Key('history-rate-value')), findsNothing);
      server.failRead = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await _revealHistory(tester, day('2026-10-16'));
      expect(
        find.descendant(of: day('2026-10-16'), matching: find.text('1/2')),
        findsOneWidget,
      );
    });
    testWidgets('export from month starts with the visible month', (
      tester,
    ) async {
      await openMonth(tester, monthServer());
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-10-01'), findsWidgets);
      expect(find.text('2026-10-17'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
    // 짧은 범례는 기본 배율에서 한 줄 안에 모두 들어간다.
    testWidgets('month legend shows all categories in one compact row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openMonth(tester, monthServer(), isEnglish: false);
      final legend = find.byKey(const Key('history-month-legend'));
      await _revealHistory(tester, legend);
      final bounds = tester.getRect(legend);
      final labels = ['모두 기록', '일부 기록', '미기록', '필요시'];
      final items = find.descendant(
        of: legend,
        matching: find.byWidgetPredicate(
          (widget) => widget is Row && widget.mainAxisSize == MainAxisSize.min,
        ),
      );
      expect(items, findsNWidgets(4));
      expect(
        (tester.getRect(items.first).left + tester.getRect(items.last).right) /
            2,
        closeTo(bounds.center.dx, 0.5),
      );
      final rectangles = [
        for (final label in labels)
          tester.getRect(
            find.descendant(of: legend, matching: find.text(label)),
          ),
      ];
      for (final rect in rectangles) {
        expect(rect.top, closeTo(rectangles.first.top, 0.01));
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.right, lessThanOrEqualTo(bounds.right));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('month fits narrow screens at large Korean text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openMonth(tester, monthServer(), textScale: 2, isEnglish: false);
      await _revealHistory(
        tester,
        find.byKey(const Key('history-month-legend')),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('record summary counts scheduled doses only, not PRN doses', (
    tester,
  ) async {
    final server = _HistoryServer();
    server.items
      ..clear()
      ..addAll([
        historyTestEntry(date: '2026-10-17'),
        historyTestEntry(
          id: 2,
          name: '테스트 필요시약',
          date: '2026-10-17',
          slot: 'as_needed:12345678-1234-4234-8234-123456789012',
          mode: 'as_needed',
          status: 'taken',
          revision: 1,
        ),
      ]);
    await _pumpHistory(tester, server);
    // 필요시 기록은 별도 집계하며 정기 복용률의 분모에는 포함하지 않는다.
    await _revealHistory(tester, find.byKey(const Key('history-rate-value')));
    expect(
      tester.widget<Text>(find.byKey(const Key('history-rate-value'))).data,
      '0%',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('history-count-3'))).data,
      '1',
    );
    await _revealHistory(
      tester,
      find.byKey(const Key('history-status-summary')),
    );
    final summary = find.byKey(const Key('history-status-summary'));
    expect(
      find.descendant(of: summary, matching: find.text('Taken 0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('As needed 1')),
      findsOneWidget,
    );
    expect(tester.widget<Wrap>(summary).alignment, WrapAlignment.center);
  });

  testWidgets('editing an existing PRN event preserves its original slot key', (
    tester,
  ) async {
    const key = 'as_needed:12345678-1234-4234-8234-123456789012';
    final server = _HistoryServer();
    server.items
      ..clear()
      ..add(
        historyTestEntry(
          id: 2,
          name: '테스트 필요시약',
          date: '2026-10-17',
          slot: key,
          mode: 'as_needed',
          status: 'taken',
          revision: 3,
        ),
      );
    await _pumpHistory(tester, server);
    await _openEditor(tester);
    // 필요시 복용에는 건너뛸 예정 복용이 없으므로 취소와 복용만 고를 수 있다.
    expect(
      find.byType(RadioListTile<MedicationHistoryStatus>),
      findsNWidgets(2),
    );
    expect(
      find.widgetWithText(RadioListTile<MedicationHistoryStatus>, 'Skipped'),
      findsNothing,
    );
    await tester.tap(
      find.widgetWithText(
        RadioListTile<MedicationHistoryStatus>,
        'Cancel record (recorded by mistake)',
      ),
    );
    await _confirmSave(tester);
    await tester.pumpAndSettle();
    expect(server.writes.single['status'], 'unrecorded');
    expect(server.paths.single, endsWith('/2/2026-10-17/$key'));
    expect(server.writes.single['expected_revision'], 3);
    expect(server.items, hasLength(1));
  });

  // 공유 전 동의가 필요하고 공유 완료와 전송 완료를 혼동하지 않는다.
  testWidgets(
    'Text sharing asks privacy confirmation and calls native share safely',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.medbuddy/data_export'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.medbuddy/data_export'),
          null,
        ),
      );
      await _pumpHistory(tester, _HistoryServer());
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.textContaining('skip reasons'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
      expect(find.textContaining('not proof of ingestion'), findsNothing);
      expect(find.textContaining('Time zone: Korea'), findsNothing);
      expect(find.byType(DateRangePickerDialog), findsNothing);
      await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
      await tester.tap(find.text('Share via other apps'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareText');
      final args = calls.single.arguments as Map;
      expect(args.containsKey('filename'), isFalse);
      expect(args['subject'], 'MedBuddy medication history');
      expect(args['content'], contains('테스트 주간약'));
      expect(args['content'], contains('2026-10-11 ~ 2026-10-17'));
      expect(
        args['content'],
        contains('Self-reported records are not proof of ingestion'),
      );
      expect((args['content'] as String).startsWith('\uFEFF'), isFalse);
      expect(args['content'], isNot(contains('test-patient')));
      expect(find.textContaining('Check delivery'), findsOneWidget);
    },
  );

  testWidgets(
    'export validates date order and allows up to 90 days for external sharing',
    (tester) async {
      final server = _HistoryServer();
      await _pumpHistory(tester, server);
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await _chooseExportDate(tester, 'start', DateTime(2026, 10, 17));
      await _chooseExportDate(tester, 'end', DateTime(2026, 10, 16));
      expect(
        find.text('End date cannot be before start date.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-export-share')))
            .onPressed,
        isNull,
      );
      // 다른 앱 공유는 31일씩 나눠 읽으므로 31일을 넘는 기간도 고를 수 있다.
      await _chooseExportDate(tester, 'start', DateTime(2026, 7, 20));
      expect(find.byKey(const Key('history-export-error')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-export-share')))
            .onPressed,
        isNotNull,
      );
      await _chooseExportDate(tester, 'start', DateTime(2026, 9, 16));
      expect(find.byKey(const Key('history-export-error')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-export-share')))
            .onPressed,
        isNotNull,
      );
      await _chooseExportDate(tester, 'end', null);
      expect(find.text('2026-10-16'), findsOneWidget);
      // 달력의 한 달 조회와 오늘 조회 뒤로는 날짜를 골라도 다시 읽지 않는다.
      expect(server.reads, hasLength(1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('export read failure stays in dialog and permits retry', (
    tester,
  ) async {
    final server = _HistoryServer();
    final control = await _pumpHistory(tester, server);
    final original = control.snapshot;
    await _revealHistory(tester, find.byTooltip('Share'));
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
    server.failRead = true;
    await tester.tap(find.text('Share via other apps'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load the export records. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('2026-10-11'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-export-share')))
          .onPressed,
      isNotNull,
    );
    expect(control.snapshot, same(original));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  for (final cancel in [true, false]) {
    testWidgets(
      'pending export ${cancel ? 'cancellation' : 'session change'} prevents late sharing',
      (tester) async {
        final shares = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.medbuddy/data_export'),
          (call) async {
            shares.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('com.medbuddy/data_export'),
            null,
          ),
        );
        final changes = StreamController<String?>.broadcast(sync: true);
        addTearDown(changes.close);
        final server = _HistoryServer();
        await _pumpHistory(tester, server, sessionChanges: changes.stream);
        await _revealHistory(tester, find.byTooltip('Share'));
        await tester.tap(find.byTooltip('Share'));
        await tester.pumpAndSettle();
        server.pendingRead = Completer<http.Response>();
        await tester.tap(find.text('Share via other apps'));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('history-export-share')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('history-export-start')),
              )
              .onPressed,
          isNull,
        );
        if (cancel) {
          await tester.tap(find.text('Cancel'));
          await tester.pump();
        } else {
          changes.add(null);
          await tester.pump();
          expect(find.text('Session changed'), findsOneWidget);
        }
        server.pendingRead!.complete(
          historyTestResponse(
            historyTestBody(
              start: '2026-10-17',
              end: '2026-10-17',
              items: server.items,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(shares, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final english in [true, false]) {
    testWidgets(
      'export date fields fit a narrow screen with large ${english ? 'English' : 'Korean'} text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpHistory(
          tester,
          _HistoryServer(),
          textScale: 2,
          isEnglish: english,
        );
        await _revealHistory(tester, find.byTooltip(english ? 'Share' : '공유'));
        await tester.tap(find.byTooltip(english ? 'Share' : '공유'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final start = tester.getRect(
          find.byKey(const Key('history-export-start')),
        );
        final end = tester.getRect(find.byKey(const Key('history-export-end')));
        expect(start.bottom, lessThan(end.top));
        await tester.tap(find.text(english ? 'Cancel' : '취소'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'oversized text stays in the dialog without truncating or sharing',
    (tester) async {
      final shares = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.medbuddy/data_export'),
        (call) async {
          shares.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.medbuddy/data_export'),
          null,
        ),
      );
      final server = _HistoryServer();
      await _pumpHistory(tester, server);
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      server.items.single['item_name'] = List.filled(100001, 'x').join();
      await tester.tap(find.byKey(const Key('history-export-share')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Too many records to share at once. Select a shorter period.',
        ),
        findsOneWidget,
      );
      expect(shares, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('history-export-share')))
            .onPressed,
        isNotNull,
      );
    },
  );

  // 텍스트 공유 미지원 시 동의 없이 민감한 자료를 클립보드로 옮기지 않는다.
  testWidgets(
    'unsupported sharing asks before clipboard fallback and permits cancellation',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.medbuddy/data_export'),
        (call) async => throw MissingPluginException(),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.medbuddy/data_export'),
          null,
        ),
      );
      await _pumpHistory(tester, _HistoryServer());
      await _revealHistory(tester, find.byTooltip('Share'));
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share via other apps'));
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing is unavailable on this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Other apps may be able to read'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Medication records were copied'),
        findsNothing,
      );
    },
  );

  // 정정 도중 계정이 바뀌면 대화상자에도 이전 약 이름이나 메모가 남지 않는다.
  testWidgets('session change hides sensitive open editor and blocks saving', (
    tester,
  ) async {
    final changes = StreamController<String?>.broadcast(sync: true);
    addTearDown(changes.close);
    await _pumpHistory(
      tester,
      _HistoryServer(),
      sessionChanges: changes.stream,
    );
    await _openEditor(tester);
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(find.text('테스트 주간약'), findsNothing);
    expect(find.byKey(const Key('history-save')), findsNothing);
  });

  // 작은 기기와 2배 글씨에서도 목록·날짜 선택·정정 내용을 스크롤할 수 있다.
  testWidgets(
    'narrow screen and large text have no overflow in history or editor',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpHistory(tester, _HistoryServer(), textScale: 2);
      await _revealHistory(tester, find.text('Daily medication records.'));
      expect(find.text('Daily medication records.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _openEditor(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
