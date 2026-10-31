// 파일명: medication_history_period_test.dart
// 역할: 기간 통계의 분모, 다중 구간 조회의 실패·권한·동시 요청 경계를 검증한다.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/widgets/medication_history_charts.dart';
import 'medication_history_fixtures.dart';
import 'support/fake_as_needed_pending_store.dart';

// 고정 한국 날짜를 사용하는 제어 객체로 실제 실행 날짜·지역과 무관하게 검사한다.
MedicationHistoryControl controlWith(
  http.Client client, {
  String? Function()? session,
}) => MedicationHistoryControl(
  patientHash: 'test-patient',
  client: client,
  pendingStore: FakeAsNeededPendingStore(),
  now: () => historyTestNow,
  sessionKeyProvider: session ?? () => 'test-session',
);

// 요청 범위를 그대로 돌려주는 빈 응답으로 실제 약·건강정보를 사용하지 않는다.
http.Response emptyResponse(http.Request request) => historyTestResponse(
  historyTestBody(
    start: request.url.queryParameters['start_date']!,
    end: request.url.queryParameters['end_date']!,
    items: [],
  ),
);

void main() {
  test(
    'PRN taken is independent of scheduled denominator and cancelled PRN',
    () {
      final entries = [
        historyTestEntry(status: 'taken'),
        historyTestEntry(status: 'skipped', id: 3),
        historyTestEntry(status: 'unrecorded', id: 4),
        historyTestEntry(
          status: 'taken',
          id: 5,
          mode: 'as_needed',
          slot: 'as_needed',
        ),
        historyTestEntry(
          status: 'unrecorded',
          id: 6,
          mode: 'as_needed',
          slot: 'as_needed',
        ),
      ].map(MedicationHistoryEntry.fromJson);
      final counts = MedicationHistoryChartCounts.fromEntries(entries);
      expect(counts.scheduled, 3);
      expect(counts.taken, 1);
      expect(counts.skipped, 1);
      expect(counts.unrecorded, 1);
      expect(counts.asNeeded, 1);
      expect(counts.total, 4);
      expect(counts.percent, 33);
      expect(
        MedicationHistoryChartCounts.fromEntries(
          entries.where((entry) => entry.isAsNeeded),
        ).percent,
        isNull,
      );
    },
  );

  test(
    '90 days load in bounded contiguous chunks, exposing only final snapshot',
    () async {
      final ranges = <MedicationHistoryRange>[];
      final second = Completer<http.Response>();
      http.Request? secondRequest;
      final control = controlWith(
        MockClient((request) async {
          ranges.add(
            MedicationHistoryRange(
              MedicationHistoryDates.parse(
                request.url.queryParameters['start_date'],
              ),
              MedicationHistoryDates.parse(
                request.url.queryParameters['end_date'],
              ),
            ),
          );
          if (ranges.length == 2) {
            secondRequest = request;
            return second.future;
          }
          return emptyResponse(request);
        }),
      );
      addTearDown(control.dispose);
      final range = MedicationHistoryRange(
        MedicationHistoryDates.earliest(control.today),
        control.today,
      );
      final loading = control.load(range, extended: true);
      await Future<void>.delayed(Duration.zero);
      expect(control.loading, isTrue);
      expect(control.snapshot, isNull);
      await expectLater(
        control.load(range, extended: true),
        throwsA(isA<MedicationHistoryBusy>()),
      );
      second.complete(emptyResponse(secondRequest!));
      await loading;
      expect(ranges.map((r) => r.days), [31, 31, 28]);
      expect(ranges.first.end, range.end);
      expect(ranges.last.start, range.start);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].end.add(const Duration(days: 1)), ranges[i - 1].start);
      }
      expect(control.snapshot!.range.label, range.label);
      expect(control.loading, isFalse);
    },
  );

  test('failed later chunk never leaves partial statistics', () async {
    var requests = 0;
    final control = controlWith(
      MockClient((request) async {
        if (++requests == 2) throw http.ClientException('offline');
        return emptyResponse(request);
      }),
    );
    addTearDown(control.dispose);
    await expectLater(
      control.load(
        MedicationHistoryRange(
          control.today.subtract(const Duration(days: 60)),
          control.today,
        ),
        extended: true,
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(requests, 2);
    expect(control.snapshot, isNull);
    expect(control.error, isNotNull);
    expect(control.busy, isFalse);
  });

  test('session changes stop chunk reads and clear all results', () async {
    String? session = 'first';
    var requests = 0;
    final control = controlWith(
      MockClient((request) async {
        requests++;
        session = 'second';
        return emptyResponse(request);
      }),
      session: () => session,
    );
    addTearDown(control.dispose);
    await expectLater(
      control.load(
        MedicationHistoryRange(
          control.today.subtract(const Duration(days: 60)),
          control.today,
        ),
        extended: true,
      ),
      throwsA(isA<MedicationHistorySessionChanged>()),
    );
    expect(requests, 1);
    expect(control.snapshot, isNull);
    expect(control.sessionInvalidated, isTrue);
  });

  test(
    'over-retention, future and reverse dates fail before network use',
    () async {
      var requests = 0;
      final control = controlWith(
        MockClient((request) async {
          requests++;
          return emptyResponse(request);
        }),
      );
      addTearDown(control.dispose);
      for (final range in [
        MedicationHistoryRange(
          control.today.subtract(const Duration(days: 90)),
          control.today,
        ),
        MedicationHistoryRange(
          control.today,
          control.today.add(const Duration(days: 1)),
        ),
        MedicationHistoryRange(
          control.today,
          control.today.subtract(const Duration(days: 1)),
        ),
      ]) {
        await expectLater(
          control.load(range, extended: true),
          throwsFormatException,
        );
      }
      expect(requests, 0);
    },
  );
}
