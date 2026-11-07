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

// 클래스명: _TestPhotoStore
// 역할: 사진 요청에 사용한 환자·약 식별자를 기록하고 실제 앱 자산 경로를 돌려주는 저장소 대역이다.
// 주요 책임: 필요시 약의 계정별 사진 조회와 기존 사진 보기 연결을 검증한다.
// 속성: patient(String?)·medication(int?): 마지막 조회의 환자와 약 식별자.
class _TestPhotoStore extends ManualMedicationImageStore {
  String? patient;
  int? medication;
  // 함수이름: findImagePath
  // 함수역할: 조회 인자를 보관하고 시험에 사용할 로고 파일의 절대 경로를 반환한다.
  // 매개변수: patientHash(String)·medicationId(int): 사진을 요청한 환자와 약.
  // 반환값: Future<String>: 로컬 앱 자산 경로이며 파일 존재 여부는 검사하지 않는다.
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
// 역할: 기록 조회·정정·필요시 복용 요청을 메모리에서 처리하는 HTTP 대역이다.
// 주요 책임: 기간 필터와 기록 버전을 반영하고 지연·통신 실패·충돌·잘못된 응답을 선택적으로 재현한다.
// 속성: items·writes(List<Map<String,dynamic>>): 기록·쓰기 내역; paths(List<String>)·reads(List<Uri>): 요청 이력; failRead/prnEligible/extraPrn/failFirstWrite/malformedFirstWrite(bool): 시나리오; failWriteNumber/rejectWrite(int?): 실패 순번·HTTP 상태; pendingWrite/pendingRead(Completer<http.Response>?): 지연 응답.
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

  // 함수이름: respond
  // 함수역할: GET은 날짜 구간의 기록을 반환하고 쓰기는 상태·실제 복용 시각·사유와 버전을 반영한다. 설정된 지연·거절·통신 실패를 우선 적용한다.
  // 매개변수: request(http.Request): 시험용 조회 또는 기록 변경 요청.
  // 반환값: Future<http.Response>: 구성한 JSON 응답; 통신 실패 플래그에서는 ClientException을 발생시킨다.
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

// Function Name: _pumpHistory
// Description: Mounts history with the real theme/localizations and an isolated HTTP/store double; optionally selects today's visible details and registers controller cleanup.
// Parameters: tester (WidgetTester), server (_HistoryServer): Harness and responses; readOnly/isEnglish/openToday/initiallyShowExport/isActive (bool): View modes; textScale (double): Text scaling; onChanged (FutureOr<void> Function()?): Save callback; sessionChanges (Stream<String?>?): Session events; now (DateTime Function()?): Clock; recordChanges (Listenable?): External changes.
// Returns: Future<MedicationHistoryControl>: Mounted controller; failed widget lookup or settling fails the test.
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
  Listenable? recordChanges,
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
        recordChanges: recordChanges,
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

// 함수이름: _revealHistory
// 함수역할: 목록 상단으로 돌아간 뒤 대상이 실제로 눌리는 위치까지 스크롤한다.
// 매개변수: tester(WidgetTester): 위젯 실행기; target(Finder): 표시할 기록 화면 요소.
// 반환값: Future<void>: 스크롤 완료; 대상이 없거나 스크롤 제한을 넘으면 테스트가 실패한다.
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

// 함수이름: _openEditor
// 함수역할: 기록 수정 버튼이 눌리는 위치까지 최대 20회 스크롤한 뒤 편집창을 연다.
// 매개변수: tester(WidgetTester): 위젯 실행기; isEnglish(bool): 수정 버튼 도구 설명 언어.
// 반환값: Future<void>: 편집창 표시 완료; 수정 버튼이 정확히 하나가 아니면 실패한다.
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

// 함수이름: _confirmSave
// 함수역할: 기록 저장 버튼과 확인창의 Save를 차례로 누르고 첫 프레임까지만 진행한다.
// 매개변수: tester(WidgetTester): 영어 기록 편집창이 열린 실행기.
// 반환값: Future<void>: 저장 요청 시작; 네트워크 응답 완료는 호출자가 추가로 기다린다.
Future<void> _confirmSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('history-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pump();
}

// 함수이름: _chooseExportDate
// 함수역할: 공유 시작일 또는 종료일의 달력을 열어 지정 날짜나 취소 결과로 닫는다.
// 매개변수: tester(WidgetTester): 실행기; endpoint(String): start 또는 end; date(DateTime?): 선택 날짜, null이면 취소.
// 반환값: Future<void>: 날짜 선택 결과가 반영된 공유창.
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

// 함수이름: _pumpAsNeeded
// 함수역할: 필요시 복용 섹션을 실제 테마·번역과 시험용 저장소에 연결하여 표시하고 제어기 해제를 등록한다.
// 매개변수: tester(WidgetTester)·server(_HistoryServer): 실행기·응답 대역; readOnly/isEnglish(bool): 표시 모드; textScale/leadingHeight(double): 글자 배율·앞쪽 높이; sessionChanges(Stream<String?>?)·now(DateTime Function()?): 세션·시각 대역; requestTimeout(Duration): 요청 제한; imageStore(ManualMedicationImageStore)·pendingStore(FakeAsNeededPendingStore?): 사진·대기 기록 저장소.
// 반환값: Future<MedicationHistoryControl>: 표시한 섹션의 제어기; 비동기 정착 실패는 테스트로 전달한다.
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

// Function Name: main
// Description: Registers history editing, period selection, export, PRN recovery and read-only/session-boundary widget regressions with isolated responses.
// Parameters: None; individual callbacks receive the test runner's WidgetTester.
// Returns: void; registers tests and fixtures without running them synchronously.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할: 모든 기간 탭에서 일별 상세가 처음부터 펼쳐지고 사용자가 다시 접고 펼칠 수 있는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 시작일·종료일 변경이 별도 조회 버튼 없이 적용되며 사용자 지정 기간에 임의 구간 막대그래프가 나타나지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 달력이 시작일 이후의 종료일만 허용하고 탭별 접힘 상태가 서로 영향을 주지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 날짜 선택 취소는 재조회하지 않으며 자동 기간 조회 실패 후 재시도가 가능한지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // Function Name: testWidgets callback
    // Description: Checks that resume events reload history only when the parameterized active flag makes that view visible.
    // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
    // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 탭 위에 열린 일정 화면에서 기록하면 탭은 다시 만들어지지 않으므로 저장 신호로 다시 읽는다.
  for (final active in [true, false]) {
    // Function Name: testWidgets callback
    // Description: Checks that external record-change events trigger reads only for the parameterized visible history state.
    // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
    // Returns: Future<void>; a failed expectation or widget interaction fails the case.
    testWidgets('a dose saved elsewhere reloads only a visible history: $active', (
      tester,
    ) async {
      final saved = ValueNotifier(0);
      addTearDown(saved.dispose);
      final server = _HistoryServer();
      await _pumpHistory(
        tester,
        server,
        openToday: false,
        isActive: active,
        recordChanges: saved,
      );
      final reads = server.reads.length;
      saved.value++;
      await tester.pumpAndSettle();
      expect(server.reads.length, active ? reads + 1 : reads);
    });
  }

  // Function Name: testWidgets callback
  // Description: Completes an in-flight read after an external dose event and requires a subsequent read so the saved dose is not lost.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
  testWidgets('a dose saved during a read is read after it', (tester) async {
    final saved = ValueNotifier(0);
    addTearDown(saved.dispose);
    final server = _HistoryServer();
    await _pumpHistory(tester, server, openToday: false, recordChanges: saved);
    final pending = Completer<http.Response>();
    server.pendingRead = pending;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final reads = server.reads.length;
    saved.value++;
    await tester.pump();
    expect(server.reads.length, reads);
    server.pendingRead = null;
    pending.complete(
      historyTestResponse(
        historyTestBody(start: '2026-10-11', end: '2026-10-17', items: []),
      ),
    );
    await tester.pumpAndSettle();
    expect(server.reads.length, reads + 1);
  });

  // Function Name: testWidgets callback
  // Description: Signals an external dose change while editing and verifies that refresh waits until the editor closes.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
  testWidgets('a dose saved while the editor is open is read after it closes', (
    tester,
  ) async {
    final saved = ValueNotifier(0);
    addTearDown(saved.dispose);
    final server = _HistoryServer();
    await _pumpHistory(tester, server, recordChanges: saved);
    await _openEditor(tester);
    final reads = server.reads.length;
    saved.value++;
    await tester.pumpAndSettle();
    expect(server.reads.length, reads);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(server.reads.length, greaterThan(reads));
    final afterClose = server.reads.length;
    await tester.pumpAndSettle();
    expect(server.reads.length, afterClose);
  });

  // Function Name: testWidgets callback
  // Description: Advances the injected clock to a new week and verifies that resuming follows today's period.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // Function Name: testWidgets callback
  // Description: Delays the post-save reload and checks that visible saving progress bridges the write and refresh stages.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 날짜별 기록 조회가 대기 중이어도 뒤로가기로 이력 화면을 닫고 늦은 응답이 새 화면에 영향을 주지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 채팅에서 연 기록 화면이 다시 빌드되어도 같은 세션을 유지하고 정상적으로 조회·종료하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Leaves the schedule after a PRN save and verifies that its undo still updates only the saved record through the retained action.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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
      // 함수이름: testWidgets 콜백
      // 함수역할: 환자·보호자 및 한국어·영어 조합에서 필요시 약의 복용량이 누락되지 않는지 검증한다.
      // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
      // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 공유 바로가기 진입 시 확인창을 한 번만 열고 취소하면 실제 전송 없이 닫히는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 조회 실패나 읽기 전용 진입에서는 공유 바로가기 확인창이 자동으로 열리지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
  // 함수이름: setUp 콜백
  // 함수역할: 각 사례가 이전 설정의 영향을 받지 않도록 메모리 환경설정을 빈 값으로 초기화한다.
  // 매개변수: 없음.
  // 반환값: void: 초기화 완료.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 함수이름: testWidgets 콜백
  // 함수역할: 처음 진입하거나 다시 열어도 기록 안내창이 자동으로 나타나지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 일별 상태 요약의 여백·중앙 정렬과 시간대 카드의 내부 테두리를 확인하고 제거된 정보 버튼이 없는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 원그래프 클릭이 기록률·건수 표시만 전환하고 조회·선택 날짜·실제 기록은 바꾸지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 큰 글씨에서 원그래프의 비율·건수 전환을 수행해 레이아웃 예외가 없는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 이전·다음 화살표와 달력으로 허용된 이력 구간 안의 날짜를 선택하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 기간 변경 조회 중 이전 날짜의 행을 지우고 중복 날짜 이동을 차단하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 기록 카드를 일정의 시간대 순서로 정렬하고 필요시 기록은 별도 분류에 유지하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 여러 날의 내보내기 기간을 선택해도 현재 보고 있는 일별 상세 날짜는 유지되는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 보호자 이력은 읽기 전용으로 표시하고 수정·새 기록 추가는 숨기되 공유 진입은 유지하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 조회 통신 실패 시 재시도를 제공하고 조회 성공 전에는 공유를 막는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 지난 일정의 정정에서 실제 복용일을 오늘로 선택해도 원래 예정일은 바뀌지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 미래 복용 시각 오류가 난 뒤 상태를 건너뜀으로 바꾸면 해당 시각 오류가 해제되는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 미래 시각 오류는 날짜나 시간의 실제 변경으로 해제되지만 달력 취소만으로는 사라지지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 한국어·영어의 건너뜀 안내가 기존 알림 설정을 변경하지 않는다는 점을 표시하는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 건너뜀 사유를 저장하기 전에 확인을 거치고 현재 기록 버전을 함께 보내는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 쓰기 통신 실패를 성공으로 표시하지 않고 재시도에 동일한 변경 의도를 사용하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 잘못된 저장 승인 응답 뒤에는 확인한 입력을 잠가 동일 요청만 재시도하도록 하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 저장 응답 대기 중 중복 제출과 편집창 종료를 막는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 버전 충돌에서는 동일 요청을 무조건 재전송하지 않고 닫기·최신 기록 조회를 제공하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 기록 조회 화면에서 새 필요시 복용을 추가하는 동작을 제공하지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
  testWidgets('history never offers new dose recording', (tester) async {
    await _pumpHistory(tester, _HistoryServer());
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-add-prn')), findsNothing);
    expect(find.byTooltip('Edit record'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할: 같은 날 필요시 약을 두 번 기록할 때 각각 다른 시간대 UUID를 사용하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 현재 기록할 수 없는 필요시 약에는 새 복용 기록 동작이 나타나지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
  testWidgets('ineligible PRN cannot create a new dose', (tester) async {
    await _pumpAsNeeded(tester, _HistoryServer()..prnEligible = false);
    expect(find.byKey(const Key('schedule-prn-take-2')), findsNothing);
    expect(find.text('No medication today'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할: 필요시 약 사진을 환자·약 식별자로 조회하고 클릭 시 기존 사진 보기 화면으로 연결하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 필요시 복용 직후 되돌리기는 방금 생성한 기록만 미기록으로 정정하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 같은 약의 새 기록을 되돌려도 먼저 입력한 복용 기록은 유지되는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Retries an unconfirmed prior-day PRN operation and requires a separate explicit tap before recording another dose for today.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 대기 기록 저장소가 실패해도 필요시 약 목록은 유지하고 오류를 알리는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Fails a PRN undo request and verifies that the feedback directs the user to correct the existing history record.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 추가 필요시 복용 확인창에 오늘의 마지막 복용 시각과 경과 시간을 표시하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 마지막 필요시 복용 후 1분 미만인 경우 경과 시간을 방금 전으로 표시하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Cancels the additional-dose confirmation and requires the existing count and write history to stay unchanged.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 일괄 체크에서 아직 먹지 않은 약을 먼저 기록하고 추가 복용이 필요한 약은 확인창을 거치는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Injects partial bulk-save failure and verifies that retry submits only the remaining intent without duplicating successful doses.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // Function Name: testWidgets callback
  // Description: Returns a definite server rejection and verifies that it releases the global pending lock instead of blocking every check.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 기록 상태는 조작 불가능한 체크 아이콘 없이 왼쪽 정렬된 문자로 표시되는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 필요시 약 행에 사진과 원형 체크를 표시하고 예전 복용했어요 텍스트 버튼은 제거됐는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Saves a PRN dose after scrolling and verifies that rebuilding its count does not jump the card to a different scroll position.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 필요시 목록 조회 실패를 약 없음으로 표시하지 않고 새로고침을 제공하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 저장 응답을 잃은 필요시 기록은 재시도에도 같은 이벤트·작업 식별자를 사용하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 필요시 복용 연속 클릭과 응답 대기 중 클릭으로 중복 기록이 생성되지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: testWidgets callback
  // Description: Reopens the schedule with shared pending storage and confirms that an uncertain PRN operation keeps its identity rather than becoming a second dose.
  // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
  // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 읽기 전용 필요시 섹션에서는 새 복용을 기록할 수 없는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 세션이 바뀌면 열린 필요시 상세를 숨기고 이전 계정의 저장 동작을 차단하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 추가 복용 확인창이 열린 사이 날짜가 바뀌면 전날 기준 기록을 차단하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 한국어·영어 큰 글씨에서 필요시 목록과 추가 복용 확인창이 넘치지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // Function Name: group callback
  // Description: Groups monthly-calendar selection, allowed history windows, export defaults, semantics and responsive-layout regressions.
  // Parameters: None; nested widget tests receive their own WidgetTester.
  // Returns: void; registers the month-specific cases and local fixture helpers.
  group('month calendar', () {
    // 함수이름: monthServer
    // 함수역할: 월별 상태·필요시 표시를 검증할 여러 날짜의 복용·미기록 항목을 구성한다.
    // 매개변수: 없음.
    // 반환값: _HistoryServer: 정기 기록과 필요시 복용 한 건을 가진 독립 메모리 대역.
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

    // Function Name: day
    // Description: Locates the monthly cell by its complete date key without relying on duplicate day-number text.
    // Parameters: date (String): YYYY-MM-DD date suffix used by the calendar key.
    // Returns: Finder: Matching calendar cell; does not assert that it exists.
    Finder day(String date) => find.byKey(ValueKey('history-month-day-$date'));

    // 함수이름: openMonth
    // 함수역할: 이력 화면의 자동 오늘 선택을 생략하고 월간 탭이 보이도록 스크롤한 뒤 선택한다.
    // 매개변수: tester(WidgetTester)·server(_HistoryServer): 실행기·응답 대역; textScale(double)·isEnglish(bool): 글자 배율·언어.
    // 반환값: Future<void>: 월간 조회와 화면 정착 완료.
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

    // Function Name: testWidgets callback
    // Description: Invokes a calendar cell through its accessibility tap action and requires the selected-day details to update.
    // Parameters: tester (WidgetTester): Drives the isolated widget tree and test clock.
    // Returns: Future<void>; a failed expectation or widget interaction fails the case.
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

    // 함수이름: testWidgets 콜백
    // 함수역할: 월간 탭에서 한 달 구간을 조회하고 막대그래프 대신 건수 달력을 유지하는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 이미 읽은 월의 날짜를 선택할 때 전체 기간을 재조회하지 않고 인라인 상세를 여는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 이전 달 탐색이 허용된 90일 이력 구간을 넘어가지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 월간 조회 실패 시 오래된 집계를 숨기고 재시도 뒤 새 자료를 표시하는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 월간 화면에서 공유를 열면 현재 보이는 달을 초기 내보내기 기간으로 사용하는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 월간 범례가 정기 상태와 필요시 분류를 한 줄 중앙 정렬로 표시하는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

    // 함수이름: testWidgets 콜백
    // 함수역할: 좁은 화면과 큰 한국어 글씨에서도 월간 달력에 레이아웃 예외가 없는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 복용률의 분모·분자는 정기 일정만 집계하고 필요시 복용은 별도 항목으로 표시하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 기존 필요시 기록의 시각·상태를 수정해도 원래 시간대 이벤트 식별자는 유지되는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 텍스트 공유는 확인창을 거친 뒤 네이티브 공유를 호출하고 공개되는 항목을 확인할 수 있는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 외부 공유의 날짜 순서를 검증하고 최대 90일 범위를 허용하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 공유 자료 조회 실패 후 대화상자를 유지하여 재시도할 수 있는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 자료 조회 중 공유 취소 또는 세션 변경이 발생하면 늦은 응답으로 전송하지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
    // 함수이름: testWidgets 콜백
    // 함수역할: 좁은 화면에서 한국어·영어 큰 글씨로 공유 시작일·종료일을 표시해도 넘치지 않는지 검증한다.
    // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
    // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 공유 크기 제한을 넘으면 내용을 임의로 잘라 전송하지 않고 확인창에서 오류를 표시하는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 네이티브 공유 미지원 시 복사 대안을 별도로 확인받고 취소하면 클립보드를 변경하지 않는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 세션 변경 시 열린 기록 편집창의 민감 내용을 숨기고 저장을 막는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할: 좁은 화면과 큰 글씨에서 기록 목록·편집창을 조작해도 레이아웃 예외가 없는지 검증한다.
  // 매개변수: tester(WidgetTester): 격리된 화면과 시험 시계를 조작하는 실행기.
  // 반환값: Future<void>; 기대 결과나 위젯 조작이 어긋나면 테스트가 실패한다.
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
