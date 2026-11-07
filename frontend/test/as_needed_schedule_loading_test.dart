import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/widgets/as_needed_schedule_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_as_needed_pending_store.dart';

class _HistoryResponse {
  Completer<void>? gate;
  bool hasMedication = false;
  bool fail = false;

  Future<http.Response> respond(http.Request request) async {
    await gate?.future;
    if (fail) return http.Response('{}', 503);
    return http.Response(
      jsonEncode({
        'start_date': request.url.queryParameters['start_date'],
        'end_date': request.url.queryParameters['end_date'],
        'items': [],
        'medications': [
          if (hasMedication)
            {
              'id': 2,
              'item_name': 'Test PRN',
              'dosing_mode': 'as_needed',
              'can_record_as_needed': true,
              'dosage_per_time': '1 tablet',
            },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

MedicationHistoryControl _control(_HistoryResponse response) {
  final control = MedicationHistoryControl(
    patientHash: 'test-patient',
    pendingStore: FakeAsNeededPendingStore(),
    client: MockClient(response.respond),
    sessionKeyProvider: () => 'test-user',
    now: () => DateTime.utc(2026, 6, 1, 3),
  );
  addTearDown(control.dispose);
  return control;
}

Widget _screen(MedicationHistoryControl control, {int version = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            AsNeededScheduleSection(
              patientHash: 'test-patient',
              isEnglish: false,
              control: control,
              refreshVersion: version,
              emptyState: const Text('오늘 복용할 약이 없습니다'),
            ),
          ],
        ),
      ),
    );

void _expectOnlyLoading() {
  expect(find.byKey(const Key('schedule-prn-initial-loading')), findsOneWidget);
  expect(find.byKey(const Key('schedule-as-needed')), findsNothing);
  expect(find.text('필요시 복용'), findsNothing);
  expect(find.byKey(const Key('prn-reminder')), findsNothing);
  expect(find.text('오늘 복용할 약이 없습니다'), findsNothing);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('첫 빈 조회가 끝날 때까지 필요시 카드 대신 로딩만 표시한다', (tester) async {
    final response = _HistoryResponse()..gate = Completer<void>();
    final control = _control(response);
    await tester.pumpWidget(_screen(control));
    await tester.pump(const Duration(milliseconds: 100));
    _expectOnlyLoading();
    response.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
    expect(find.byKey(const Key('schedule-as-needed')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 빈 결과를 보관한 채 새로고침하거나 같은 세션으로 화면을 다시 여는 경로를 검증한다.
  for (final reopen in [false, true]) {
    for (final result in ['empty', 'medication', 'error']) {
      testWidgets('빈 조회 후 재조회 중 빈 카드를 표시하지 않는다: reopen=$reopen, $result', (
        tester,
      ) async {
        final response = _HistoryResponse();
        final control = _control(response);
        await tester.pumpWidget(_screen(control));
        await tester.pumpAndSettle();
        expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);

        if (reopen) await tester.pumpWidget(const SizedBox.shrink());
        response
          ..gate = Completer<void>()
          ..hasMedication = result == 'medication'
          ..fail = result == 'error';
        await tester.pumpWidget(_screen(control, version: 1));
        await tester.pump(const Duration(milliseconds: 100));
        expect(control.loading, isTrue);
        _expectOnlyLoading();

        response.gate!.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('schedule-prn-initial-loading')),
          findsNothing,
        );
        expect(
          find.text('오늘 복용할 약이 없습니다'),
          result == 'empty' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Test PRN'),
          result == 'medication' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('schedule-prn-error')),
          result == 'error' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('실제 필요시 약이 있으면 재조회 중에도 카드와 약 이름을 유지한다', (tester) async {
    final response = _HistoryResponse()..hasMedication = true;
    final control = _control(response);
    await tester.pumpWidget(_screen(control));
    await tester.pumpAndSettle();
    response.gate = Completer<void>();
    await tester.pumpWidget(_screen(control, version: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(control.loading, isTrue);
    expect(find.byKey(const Key('schedule-prn-initial-loading')), findsNothing);
    expect(find.byKey(const Key('schedule-as-needed')), findsOneWidget);
    expect(find.text('Test PRN'), findsOneWidget);
    response.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Test PRN'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
