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
// 함수이름: controlWith
// 함수역할:
// - 고정 시계·메모리 필요시 대기 저장소를 사용해 기간 조회의 응답과 세션 교체를 제어한다.
// 매개변수:
// - client(http.Client): 기간별 응답을 제공할 가짜 클라이언트.
// - session(String? Function()?): 현재 세션 키 공급자; 생략하면 고정 세션.
// 반환값:
// - MedicationHistoryControl: 테스트 환자 조회기; 호출자가 dispose해야 한다.
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
// 함수이름: emptyResponse
// 함수역할:
// - 요청 시작·종료 날짜를 그대로 반영한 빈 이력 응답을 만든다.
// 매개변수:
// - request(http.Request): start_date/end_date 쿼리를 포함한 조회 요청.
// 반환값:
// - http.Response: 고정 약 목록과 빈 items를 가진 성공 응답; 날짜 쿼리 누락은 null 단언 실패.
http.Response emptyResponse(http.Request request) => historyTestResponse(
  historyTestBody(
    start: request.url.queryParameters['start_date']!,
    end: request.url.queryParameters['end_date']!,
    items: [],
  ),
);

// 함수이름: main
// 함수역할:
// - 정기/필요시 통계 분리와 90일 분할 조회의 실패·세션·중복 요청 경계를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록한 테스트는 프레임워크가 실행한다.
void main() {
  // 함수이름: 정기 통계 분모와 필요시 기록
  // 함수역할:
  // - 정기 세 상태는 분모 3·복용률 33%로 계산하고 완료된 필요시 기록만 별도 횟수에 더하며 필요시만 있으면 복용률을 계산하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: 90일 연속 구간 조회
  // 함수역할:
  // - 90일을 최신순 31·31·28일로 겹침 없이 조회하고 중간 결과를 노출하지 않으며 대기 중 중복 조회를 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
      final loading = control.load(range);
      await Future<void>.delayed(Duration.zero);
      expect(control.loading, isTrue);
      expect(control.snapshot, isNull);
      await expectLater(
        control.load(range),
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

  // 함수이름: 후속 구간 실패의 부분 결과 제거
  // 함수역할:
  // - 두 번째 구간의 통신 실패를 전달하고 스냅샷 없이 오류를 기록하며 busy를 해제하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
              ),
      throwsA(isA<http.ClientException>()),
    );
    expect(requests, 2);
    expect(control.snapshot, isNull);
    expect(control.error, isNotNull);
    expect(control.busy, isFalse);
  });

  // 함수이름: 구간 조회 중 세션 변경
  // 함수역할:
  // - 첫 응답 중 세션이 바뀌면 추가 요청을 중단하고 결과를 비운 채 세션 무효화 오류를 전달하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
              ),
      throwsA(isA<MedicationHistorySessionChanged>()),
    );
    expect(requests, 1);
    expect(control.snapshot, isNull);
    expect(control.sessionInvalidated, isTrue);
  });

  // 함수이름: 잘못된 기간의 통신 전 거부
  // 함수역할:
  // - 보존 범위 초과·미래·역순 날짜는 네트워크 요청 없이 FormatException으로 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
          control.load(range),
          throwsFormatException,
        );
      }
      expect(requests, 0);
    },
  );
}
