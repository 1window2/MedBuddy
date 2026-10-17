// 파일명: medication_history_ui_boundary_test.dart
// 역할: 기록 정정·권한·내보내기·작은 화면의 실제 위젯 흐름을 검증한다.
import 'dart:async';
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
}) async {
  final control = MedicationHistoryControl(
    patientHash: 'test-patient',
    readOnly: readOnly,
    client: MockClient(server.respond),
    now: () => historyTestNow,
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
      ),
    ),
  );
  await tester.pumpAndSettle();
  return control;
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
}) async {
  final control = MedicationHistoryControl(
    patientHash: 'test-patient',
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
    expect(find.byTooltip('About medication records'), findsOneWidget);
  });

  testWidgets(
    'status summary has compact spacing without shrinking info touch target',
    (tester) async {
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
      expect(morning.top - summary.bottom, closeTo(4, 0.01));
      final infoSize = tester.getSize(
        find.ancestor(
          of: find.byTooltip('복약 기록 안내'),
          matching: find.byType(IconButton),
        ),
      );
      expect(infoSize.width, greaterThanOrEqualTo(48));
      expect(infoSize.height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets(
    'record notice can be reopened without changing the selected day',
    (tester) async {
      final control = await _pumpHistory(tester, _HistoryServer());
      expect(find.textContaining('not proof of ingestion'), findsNothing);
      final original = control.snapshot;
      await tester.tap(find.byTooltip('About medication records'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not proof of ingestion'), findsOneWidget);
      expect(find.textContaining('Time zone: Korea'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not proof of ingestion'), findsNothing);
      expect(control.snapshot, same(original));
    },
  );

  testWidgets('record notice stays readable when requested with large text', (
    tester,
  ) async {
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
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('실제 복용을 증명'), findsNothing);
    final info = find.byTooltip('복약 기록 안내');
    for (
      var scroll = 0;
      scroll < 10 && info.hitTestable().evaluate().isEmpty;
      scroll++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(info.hitTestable(), findsOneWidget);
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.textContaining('실제 복용을 증명'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('실제 복용을 증명'), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Other page'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'daily arrows and calendar select one day within the history window',
    (tester) async {
      final server = _HistoryServer();
      server.items.add(historyTestEntry(name: 'Yesterday medication'));
      final control = await _pumpHistory(tester, server);
      expect(control.requestedRange!.days, 1);
      expect(control.requestedRange!.start, control.today);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-next-day')))
            .onPressed,
        isNull,
      );
      expect(find.text('Yesterday medication'), findsNothing);
      await tester.tap(find.byKey(const Key('history-previous-day')));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 16));
      expect(find.text('Yesterday medication'), findsOneWidget);
      expect(find.text('테스트 주간약'), findsNothing);
      await tester.tap(find.byKey(const Key('history-next-day')));
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, control.today);
      await tester.tap(find.byKey(const Key('history-select-date')));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.lastDate, DateTime(2026, 10, 17));
      expect(calendar.firstDate, DateTime(2026, 7, 20));
      Navigator.of(
        tester.element(find.byType(DatePickerDialog)),
      ).pop(DateTime(2026, 7, 20));
      await tester.pumpAndSettle();
      expect(control.requestedRange!.days, 1);
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
    'changing day clears old rows and blocks duplicate navigation while loading',
    (tester) async {
      final server = _HistoryServer();
      final control = await _pumpHistory(tester, server);
      final pending = Completer<http.Response>();
      server.pendingRead = pending;
      await tester.tap(find.byKey(const Key('history-previous-day')));
      await tester.pump();
      expect(find.text('테스트 주간약'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('history-next-day')))
            .onPressed,
        isNull,
      );
      pending.complete(
        historyTestResponse(
          historyTestBody(start: '2026-10-16', end: '2026-10-16'),
        ),
      );
      await tester.pumpAndSettle();
      expect(control.snapshot!.range.start, DateTime.utc(2026, 10, 16));
      expect(find.byKey(const Key('history-slot-morning')), findsOneWidget);
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
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
      await _chooseExportDate(tester, 'end', DateTime(2026, 10, 16));
      expect(find.textContaining('2026-10-11'), findsOneWidget);
      expect(find.text('2026-10-16'), findsOneWidget);
      expect(server.reads, hasLength(1));
      expect(control.snapshot, same(original));
      expect(control.requestedRange!.days, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-17 (Sat)'), findsOneWidget);
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
      expect(find.byTooltip('About medication records'), findsOneWidget);
      expect(find.byTooltip('Edit record'), findsNothing);
      expect(find.byKey(const Key('history-add-prn')), findsNothing);
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(server.writes, isEmpty);
    },
  );

  // 조회 실패에서 이전 자료나 성공 통계를 보여 주지 않고 재시도를 제공한다.
  testWidgets('offline read exposes retry and disables export', (tester) async {
    final server = _HistoryServer()..failRead = true;
    await _pumpHistory(tester, server);
    expect(find.byKey(const Key('history-load-error')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Export',
            ),
          )
          .onPressed,
      isNull,
    );
    server.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-load-error')), findsNothing);
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
    expect(find.text('1 doses today'), findsOneWidget);
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
    expect(find.text('1 doses today'), findsNWidgets(2));
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
    expect(find.text('1 doses today'), findsOneWidget);
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
    await tester.pump(const Duration(seconds: 4));
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
    expect(find.text('1 doses today'), findsOneWidget);
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
    await tester.tap(
      find.widgetWithText(RadioListTile<MedicationHistoryStatus>, 'Unrecorded'),
    );
    await _confirmSave(tester);
    await tester.pumpAndSettle();
    expect(server.paths.single, endsWith('/2/2026-10-17/$key'));
    expect(server.writes.single['expected_revision'], 3);
    expect(server.items, hasLength(1));
  });

  // 공유 전 동의가 필요하고 공유 완료와 전송 완료를 혼동하지 않는다.
  testWidgets(
    'CSV export asks privacy confirmation and calls native share safely',
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
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.textContaining('skip reasons'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
      expect(find.textContaining('not proof of ingestion'), findsNothing);
      expect(find.textContaining('Time zone: Korea'), findsNothing);
      expect(find.byType(DateRangePickerDialog), findsNothing);
      await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
      await tester.tap(find.text('Share CSV'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareCsv');
      final args = calls.single.arguments as Map;
      expect(args['filename'], 'medbuddy_history_2026-10-11_2026-10-17.csv');
      expect(args['content'], contains('테스트 주간약'));
      expect(args['content'], contains('2026-10-11 ~ 2026-10-17'));
      expect(
        args['content'],
        contains('Self-reported, not proof of ingestion'),
      );
      expect((args['content'] as String).startsWith('\uFEFF'), isFalse);
      expect(args['content'], isNot(contains('test-patient')));
      expect(find.textContaining('Check delivery'), findsOneWidget);
    },
  );

  testWidgets('export validates date order and inclusive 31-day limit', (
    tester,
  ) async {
    final server = _HistoryServer();
    await _pumpHistory(tester, server);
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await _chooseExportDate(tester, 'end', DateTime(2026, 10, 16));
    expect(find.text('End date cannot be before start date.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-export-share')))
          .onPressed,
      isNull,
    );
    await _chooseExportDate(tester, 'start', DateTime(2026, 9, 15));
    expect(
      find.text('Select up to 31 days within the last 90 days.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('history-export-share')))
          .onPressed,
      isNull,
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
    expect(server.reads, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('export read failure stays in dialog and permits retry', (
    tester,
  ) async {
    final server = _HistoryServer();
    final control = await _pumpHistory(tester, server);
    final original = control.snapshot;
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await _chooseExportDate(tester, 'start', DateTime(2026, 10, 11));
    server.failRead = true;
    await tester.tap(find.text('Share CSV'));
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
        await tester.tap(find.byTooltip('Export'));
        await tester.pumpAndSettle();
        server.pendingRead = Completer<http.Response>();
        await tester.tap(find.text('Share CSV'));
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
        await tester.tap(find.byTooltip(english ? 'Export' : '내보내기'));
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

  // 파일 공유 미지원 시 동의 없이 민감한 자료를 클립보드로 옮기지 않는다.
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
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share CSV'));
      await tester.pumpAndSettle();
      expect(
        find.text('File sharing is unavailable on this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Other apps may be able to read'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CSV text was copied'), findsNothing);
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
