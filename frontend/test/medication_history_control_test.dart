// 파일명: medication_history_control_test.dart
// 역할: 인증·기간·동시 요청·세션 변경·재시도 계약을 검증한다.
import 'dart:async';
import 'support/fake_as_needed_pending_store.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

import 'medication_history_fixtures.dart';

final _range = MedicationHistoryRange(
  DateTime.utc(2026, 10, 11),
  DateTime.utc(2026, 10, 17),
);

// 함수역할: 고정 시각과 테스트 전송기를 제어 객체에 주입한다. 반환 객체는 호출자가 정리한다.
// 함수이름: _control
// 함수역할:
// - 고정 환자·시계·메모리 대기 저장소에 요청/세션 대역과 읽기 전용 정책을 주입한다.
// 매개변수:
// - client(http.Client): HTTP 응답과 실패를 제어할 클라이언트.
// - readOnly(bool): 쓰기 차단 여부; 기본 false.
// - session(String? Function()?): 현재 세션 키 공급자.
// - changes(Stream<String?>?): 세션 변경 이벤트.
// - timeout(Duration): 요청 제한 시간; 기본 25초.
// 반환값:
// - MedicationHistoryControl: 호출자가 dispose해야 하는 독립 조회기.
MedicationHistoryControl _control(
  http.Client client, {
  bool readOnly = false,
  String? Function()? session,
  Stream<String?>? changes,
  Duration timeout = const Duration(seconds: 25),
}) => MedicationHistoryControl(
  patientHash: 'scoped-patient',
  pendingStore: FakeAsNeededPendingStore(),
  client: client,
  now: () => historyTestNow,
  sessionKeyProvider: session ?? () => 'test-session',
  sessionChanges: changes,
  readOnly: readOnly,
  requestTimeout: timeout,
);

// 함수역할: 어제 예정된 복용을 오늘 실제 복용으로 정정할 테스트 의도를 만든다.
// 함수이름: _change
// 함수역할:
// - 버전 4의 어제 예정된 약을 현재보다 5분 전 실제 복용으로 정정할 의도를 만든다.
// 매개변수:
// - 없음.
// 반환값:
// - MedicationHistoryChange: 새 작업 UUID와 taken 상태를 가진 변경.
MedicationHistoryChange _change() => MedicationHistoryChange(
  entry: MedicationHistoryEntry.fromJson(historyTestEntry(revision: 4)),
  status: MedicationHistoryStatus.taken,
  actualTakenAt: historyTestNow.subtract(const Duration(minutes: 5)),
  operationId: MedicationHistoryControl.newOperationId(),
);

// 함수역할: 제어 객체의 요청과 실패 경계 회귀 테스트를 등록한다.
// 함수이름: main
// 함수역할:
// - 조회·내보내기·정정의 기간·인증·중복 작업·세션·실패 경계를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 프레임워크에서 테스트를 실행한다.
void main() {
  // 함수이름: 같은 기간의 갱신 중 표시 유지 검증
  // 함수역할: 이전 기록을 갱신 중에만 유지하고 응답 완료 후 새 기록으로 바꾸는지 확인한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료 Future<void>.
  test(
    'same-period refresh preserves data until the response arrives',
    () async {
      Completer<http.Response>? pending;
      final control = _control(
        MockClient(
          (_) async => pending == null
              ? historyTestResponse(historyTestBody())
              : pending.future,
        ),
      );
      addTearDown(control.dispose);
      await control.load(_range);
      final previous = control.snapshot;
      pending = Completer<http.Response>();
      final refresh = control.load(_range, preserveSnapshot: true);
      expect(control.snapshot, same(previous));
      expect(control.loading, isTrue);
      pending.complete(historyTestResponse(historyTestBody(items: [])));
      await refresh;
      expect(control.snapshot, isNot(same(previous)));
      expect(control.snapshot!.items, isEmpty);
      expect(control.loading, isFalse);
    },
  );

  // 함수이름: 다른 기간의 이전 표시 차단 검증
  // 함수역할: 유지 옵션을 켜도 이전 기간의 기록을 새 날짜 아래에 표시하지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료 Future<void>.
  test(
    'a different period clears data even with preservation enabled',
    () async {
      Completer<http.Response>? pending;
      final control = _control(
        MockClient(
          (_) async => pending == null
              ? historyTestResponse(historyTestBody())
              : pending.future,
        ),
      );
      addTearDown(control.dispose);
      await control.load(_range);
      pending = Completer<http.Response>();
      final refresh = control.load(
        MedicationHistoryRange(
          DateTime.utc(2026, 10, 17),
          DateTime.utc(2026, 10, 17),
        ),
        preserveSnapshot: true,
      );
      expect(control.snapshot, isNull);
      pending.complete(
        historyTestResponse(historyTestBody(start: '2026-10-17', items: [])),
      );
      await refresh;
      expect(control.snapshot!.range.days, 1);
    },
  );

  for (final status in [401, 403, 500]) {
    // 함수이름: 갱신 실패 시 이전 기록 제거 검증
    // 함수역할: 권한·서버 오류가 확인되면 환자·보호자 모두 이전 기록을 지우는지 확인한다.
    // 매개변수: 없음. 반환값: 비동기 검증 완료 Future<void>.
    for (final readOnly in [false, true]) {
      test('refresh failure $status clears data, readOnly=$readOnly', () async {
        var fail = false;
        final control = _control(
          MockClient(
            (_) async => fail
                ? historyTestResponse({'detail': 'Unavailable'}, status)
                : historyTestResponse(historyTestBody()),
          ),
          readOnly: readOnly,
        );
        addTearDown(control.dispose);
        await control.load(_range);
        fail = true;
        await expectLater(
          control.load(_range, preserveSnapshot: true),
          throwsA(isA<ApiRequestException>()),
        );
        expect(control.snapshot, isNull);
        expect(control.error, isNotNull);
        expect(control.loading, isFalse);
      });
    }
  }

  // 함수이름: 갱신 중 계정 변경 검증
  // 함수역할: 계정 변경 즉시 기존 기록을 지우고 늦은 응답도 다시 표시하지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료 Future<void>.
  test(
    'session change clears preserved data and rejects a late refresh',
    () async {
      final changes = StreamController<String?>.broadcast(sync: true);
      addTearDown(changes.close);
      Completer<http.Response>? pending;
      final control = _control(
        MockClient(
          (_) async => pending == null
              ? historyTestResponse(historyTestBody())
              : pending.future,
        ),
        changes: changes.stream,
      );
      addTearDown(control.dispose);
      await control.load(_range);
      pending = Completer<http.Response>();
      final refresh = control.load(_range, preserveSnapshot: true);
      final rejected = expectLater(
        refresh,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      changes.add('different-session');
      expect(control.snapshot, isNull);
      pending.complete(historyTestResponse(historyTestBody()));
      await rejected;
      expect(control.snapshot, isNull);
    },
  );

  // 함수이름: 내보내기와 현재 조회 분리
  // 함수역할:
  // - 하루 스냅샷을 로드한 뒤 7일 내보내기를 읽어도 현재 스냅샷·요청 기간의 객체를 유지하고 busy를 해제하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('export range preserves daily snapshot and requested range', () async {
    final control = _control(
      MockClient(
        (request) async => historyTestResponse(
          historyTestBody(
            start: request.url.queryParameters['start_date']!,
            end: request.url.queryParameters['end_date']!,
            items: [],
          ),
        ),
      ),
    );
    addTearDown(control.dispose);
    final day = MedicationHistoryRange(
      DateTime.utc(2026, 10, 17),
      DateTime.utc(2026, 10, 17),
    );
    await control.load(day);
    final daily = control.snapshot;
    final exported = await control.readRangeForExport(_range);
    expect(exported.range.days, 7);
    expect(control.snapshot, same(daily));
    expect(control.requestedRange, same(day));
    expect(control.busy, isFalse);
  });

  // 함수이름: 내보내기 범위의 통신 전 거부
  // 함수역할:
  // - 보존 기간 밖 내보내기 요청을 추가 통신 없이 거부하고 이미 로드한 스냅샷과 비실행 상태는 보존하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'export rejects oversized ranges before sending and preserves loaded data',
    () async {
      var requests = 0;
      final control = _control(
        MockClient((request) async {
          requests++;
          return historyTestResponse(historyTestBody());
        }),
      );
      addTearDown(control.dispose);
      await control.load(_range);
      final original = control.snapshot;
      // 다른 앱 공유는 보관 기간(최근 90일) 밖으로 나가면 요청 전에 거부한다.
      await expectLater(
        control.readRangeForExport(
          MedicationHistoryRange(
            DateTime.utc(2026, 7, 1),
            DateTime.utc(2026, 10, 17),
          ),
        ),
        throwsFormatException,
      );
      expect(requests, 1);
      expect(control.snapshot, same(original));
      expect(control.busy, isFalse);
    },
  );

  // Function Name: partitioned history export
  // Description:
  // - Reads a 90-day export in contiguous 31-day chunks, merges six rows in descending date order and deduplicates medication definitions.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test(
    'an export longer than 31 days is read in 31-day parts and merged',
    () async {
      final reads = <Uri>[];
      final control = _control(
        MockClient((request) async {
          reads.add(request.url);
          final start = request.url.queryParameters['start_date']!;
          final end = request.url.queryParameters['end_date']!;
          return historyTestResponse(
            historyTestBody(
              start: start,
              end: end,
              items: [
                historyTestEntry(date: end),
                historyTestEntry(date: start, slot: 'evening'),
              ],
            ),
          );
        }),
      );
      addTearDown(control.dispose);
      final range = MedicationHistoryRange(
        DateTime.utc(2026, 7, 20),
        DateTime.utc(2026, 10, 17),
      );
      final merged = await control.readRangeForExport(range);
      expect(
        reads.map(
          (uri) =>
              '${uri.queryParameters['start_date']}~${uri.queryParameters['end_date']}',
        ),
        [
          '2026-09-17~2026-10-17',
          '2026-08-17~2026-09-16',
          '2026-07-20~2026-08-16',
        ],
      );
      expect(merged.range.start, range.start);
      expect(merged.range.end, range.end);
      expect(merged.items, hasLength(6));
      expect(
        merged.items.map(
          (item) => MedicationHistoryDates.format(item.scheduleDate),
        ),
        [
          '2026-10-17',
          '2026-09-17',
          '2026-09-16',
          '2026-08-17',
          '2026-08-16',
          '2026-07-20',
        ],
      );
      expect(
        merged.medications.map((item) => item.id).toSet(),
        hasLength(merged.medications.length),
      );
      expect(control.busy, isFalse);
    },
  );

  // 함수이름: 내보내기 잠금과 세션 변경
  // 함수역할:
  // - 내보내기 응답 대기 중 조회·저장을 거부하고 계정 교체 뒤 결과를 폐기하며 세션 무효화와 잠금 해제를 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'export blocks competing work and discards results after a session change',
    () async {
      var session = 'original';
      final pending = Completer<http.Response>();
      final control = _control(
        MockClient((request) => pending.future),
        session: () => session,
      );
      addTearDown(control.dispose);
      final exporting = control.readRangeForExport(_range);
      await expectLater(
        control.load(_range),
        throwsA(isA<MedicationHistoryBusy>()),
      );
      await expectLater(
        control.save(_change()),
        throwsA(isA<MedicationHistoryBusy>()),
      );
      session = 'different';
      final rejected = expectLater(
        exporting,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      pending.complete(historyTestResponse(historyTestBody()));
      await rejected;
      expect(control.snapshot, isNull);
      expect(control.sessionInvalidated, isTrue);
      expect(control.busy, isFalse);
    },
  );

  // 인증 헤더와 대상 환자 범위가 조회에 빠지지 않음을 확인한다.
  // 함수이름: 조회 인증과 명시적 범위
  // 함수역할:
  // - 인증 헤더·환자 해시·시작/종료 달력 날짜를 정확한 이력 경로에 전송하고 정상 스냅샷을 오류 없이 반영하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'GET uses authenticated client and explicit patient and calendar dates',
    () async {
      final client = AuthenticatedApiClient(
        inner: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.url.path, '/api/v1/medication/care/history');
          expect(request.url.queryParameters, {
            'patient_hash': 'scoped-patient',
            'start_date': '2026-10-11',
            'end_date': '2026-10-17',
          });
          return historyTestResponse(historyTestBody());
        }),
        tokenProvider: () async => 'test-token',
        appCheckRequired: false,
      );
      final control = _control(client);
      addTearDown(() {
        control.dispose();
        client.close();
      });
      await control.load(_range);
      expect(control.snapshot!.items, hasLength(1));
      expect(control.loading, isFalse);
      expect(control.error, isNull);
    },
  );

  // 입력 상한은 네트워크 전송 전에 적용하고 잘못된 범위도 실패 상태로 노출한다.
  // 함수이름: 잘못된 조회 기간과 이전 자료
  // 함수역할:
  // - 이미 조회한 뒤 잘못된 범위를 요청하면 새 통신 없이 스냅샷을 비우고 FormatException을 오류 상태로 보존하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'invalid date range does not send or retain previous snapshot',
    () async {
      var requests = 0;
      final control = _control(
        MockClient((request) async {
          requests++;
          return historyTestResponse(historyTestBody());
        }),
      );
      addTearDown(control.dispose);
      await control.load(_range);
      await expectLater(
        control.load(
          MedicationHistoryRange(
            DateTime.utc(2026, 7, 1),
            DateTime.utc(2026, 10, 17),
          ),
        ),
        throwsFormatException,
      );
      expect(requests, 1);
      expect(control.snapshot, isNull);
      expect(control.error, isA<FormatException>());
    },
  );

  // 다른 기간의 성공 응답을 현재 조회 결과로 보여 주지 않는다.
  // 함수이름: 불일치 범위와 거짓 성공 응답
  // 함수역할:
  // - 요청과 다른 시작일 또는 success=false 응답은 성공 스냅샷으로 표시하지 않고 FormatException으로 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('mismatched and rejected response cannot become success', () async {
    for (final body in [
      historyTestBody(start: '2026-10-12'),
      {...historyTestBody(), 'success': false},
    ]) {
      final control = _control(
        MockClient((request) async => historyTestResponse(body)),
      );
      await expectLater(control.load(_range), throwsFormatException);
      expect(control.snapshot, isNull);
      control.dispose();
    }
  });

  // 쓰기는 실제 복용 시각과 예정일을 분리하고 충돌 검사용 버전을 보낸다.
  // 함수이름: 정정 요청의 버전과 실제 시각
  // 함수역할:
  // - PUT 경로는 원래 예정일을 유지하고 본문에 환자·기대 버전·작업 ID·별도 실제 UTC 복용 시각만 보내며 서버 기록 시각은 생략하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('PUT sends revision operation id and independent actual date', () async {
    final change = _change();
    final control = _control(
      MockClient((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url.path,
          '/api/v1/medication/care/history/1/2026-10-16/morning',
        );
        final body = jsonDecode(request.body) as Map;
        expect(body['patient_hash'], 'scoped-patient');
        expect(body['expected_revision'], 4);
        expect(body['operation_id'], change.operationId);
        expect(body['actual_taken_at'], '2026-10-17T05:55:00.000Z');
        expect(body.containsKey('recorded_at'), isFalse);
        return historyTestResponse({'success': true});
      }),
    );
    addTearDown(control.dispose);
    await control.save(change);
    expect(control.saving, isFalse);
  });

  // 읽기 전용 보호자 화면에서는 제어 계층에서도 쓰기를 거부한다.
  // 함수이름: 보호자 읽기 전용 쓰기 차단
  // 함수역할:
  // - 읽기 전용 제어기의 정정 요청은 HTTP 호출 없이 StateError로 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('caregiver and invalid times cannot send writes', () async {
    var requests = 0;
    final control = _control(
      MockClient((request) async {
        requests++;
        return historyTestResponse({'success': true});
      }),
      readOnly: true,
    );
    addTearDown(control.dispose);
    await expectLater(control.save(_change()), throwsStateError);
    expect(requests, 0);
  });

  // 진행 중인 조회가 중복 조회와 정정 요청을 함께 막는지 검사한다.
  // 함수이름: 진행 중 조회의 중복 작업 차단
  // 함수역할:
  // - 첫 조회가 대기 중이면 두 번째 조회와 정정을 MedicationHistoryBusy로 거부하고 최초 응답만 완료하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'concurrent fetch and write are rejected while request is active',
    () async {
      final pending = Completer<http.Response>();
      final control = _control(MockClient((request) => pending.future));
      addTearDown(control.dispose);
      final loading = control.load(_range);
      await expectLater(
        control.load(_range),
        throwsA(isA<MedicationHistoryBusy>()),
      );
      await expectLater(
        control.save(_change()),
        throwsA(isA<MedicationHistoryBusy>()),
      );
      pending.complete(historyTestResponse(historyTestBody()));
      await loading;
    },
  );

  // 로그아웃이나 계정 변경 뒤 도착한 이전 환자 응답은 폐기한다.
  // 함수이름: 지연 조회의 세션 경계
  // 함수역할:
  // - 세션 변경 뒤 도착한 이전 응답을 폐기하고 무효화된 제어기는 후속 정정도 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'session change discards delayed read and refuses later writes',
    () async {
      String? session = 'session-a';
      final pending = Completer<http.Response>();
      final control = _control(
        MockClient((request) => pending.future),
        session: () => session,
      );
      addTearDown(control.dispose);
      final loading = control.load(_range);
      session = 'session-b';
      final expectation = expectLater(
        loading,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      pending.complete(historyTestResponse(historyTestBody()));
      await expectation;
      expect(control.snapshot, isNull);
      expect(control.sessionInvalidated, isTrue);
      await expectLater(
        control.save(_change()),
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
    },
  );

  // 세션 변경 이벤트는 새 요청 없이도 화면에 있던 민감한 자료를 지운다.
  // 함수이름: 세션 이벤트의 지속 무효화
  // 함수역할:
  // - 로드 후 로그아웃 이벤트와 동일 키 복귀가 연속되어도 자료를 지우고 세션 무효화 상태를 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'session stream invalidates loaded data even if identity returns',
    () async {
      final changes = StreamController<String?>.broadcast(sync: true);
      final control = _control(
        MockClient((request) async => historyTestResponse(historyTestBody())),
        changes: changes.stream,
      );
      addTearDown(() async {
        control.dispose();
        await changes.close();
      });
      await control.load(_range);
      changes.add(null);
      changes.add('test-session');
      expect(control.snapshot, isNull);
      expect(control.sessionInvalidated, isTrue);
    },
  );

  // 응답 유실은 성공으로 취급하지 않고 같은 작업 식별자로 재시도할 수 있다.
  // 함수이름: 응답 유실 후 같은 작업 재시도
  // 함수역할:
  // - 첫 통신 오류 뒤 saving을 해제하고 같은 변경 객체로 재시도할 때 동일 operation_id를 보내는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('ambiguous failure keeps same explicit operation on retry', () async {
    final seen = <String>[];
    final control = _control(
      MockClient((request) async {
        seen.add((jsonDecode(request.body) as Map)['operation_id'] as String);
        if (seen.length == 1) throw http.ClientException('offline');
        return historyTestResponse({'success': true});
      }),
    );
    addTearDown(control.dispose);
    final change = _change();
    await expectLater(
      control.save(change),
      throwsA(isA<http.ClientException>()),
    );
    expect(control.saving, isFalse);
    await control.save(change);
    expect(seen, [change.operationId, change.operationId]);
  });

  // HTTP 오류와 거짓 성공 본문을 모두 보존하여 UI가 정정을 완료했다고 말하지 않게 한다.
  // 함수이름: 정정 실패 응답의 구분
  // 함수역할:
  // - 403·409·422·500은 상태 코드를 보존한 API 오류로 전달하고 success=false는 형식 오류로 거부하며 saving을 해제하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'save refuses conflict permission errors and false acknowledgements',
    () async {
      for (final status in [403, 409, 422, 500]) {
        final control = _control(
          MockClient(
            (request) async =>
                historyTestResponse({'detail': 'rejected'}, status),
          ),
        );
        await expectLater(
          control.save(_change()),
          throwsA(
            isA<ApiRequestException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(control.saving, isFalse);
        control.dispose();
      }
      final control = _control(
        MockClient((request) async => historyTestResponse({'success': false})),
      );
      addTearDown(control.dispose);
      await expectLater(control.save(_change()), throwsFormatException);
    },
  );

  // 제한 시간이 지난 조회는 로딩을 해제하고 이전 자료를 내보낼 수 없게 한다.
  // 함수이름: 조회 시간 제한
  // 함수역할:
  // - 응답이 제한 시간을 넘으면 TimeoutException을 전달하고 로딩과 스냅샷을 비우는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('timeout ends loading and exposes failure without stale data', () async {
    final pending = Completer<http.Response>();
    final control = _control(
      MockClient((request) => pending.future),
      timeout: const Duration(milliseconds: 5),
    );
    addTearDown(control.dispose);
    await expectLater(control.load(_range), throwsA(isA<TimeoutException>()));
    expect(control.loading, isFalse);
    expect(control.snapshot, isNull);
    pending.complete(historyTestResponse(historyTestBody()));
  });

  // 닫힌 화면에 늦게 도착한 쓰기 완료는 알림이나 성공 상태를 만들지 않는다.
  // 함수이름: 종료 후 늦은 쓰기 승인
  // 함수역할:
  // - 제어기를 종료한 뒤 성공 응답이 도착해도 저장 완료로 인정하지 않고 세션 변경 오류로 끝나는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('disposed control suppresses late write acknowledgement', () async {
    final pending = Completer<http.Response>();
    final control = _control(MockClient((request) => pending.future));
    final saving = control.save(_change());
    final expectation = expectLater(
      saving,
      throwsA(isA<MedicationHistorySessionChanged>()),
    );
    control.dispose();
    pending.complete(historyTestResponse({'success': true}));
    await expectation;
  });

  // 새 필요시 이벤트와 전송 작업은 충돌 가능성이 낮은 RFC 4122 UUID를 가진다.
  // 함수이름: 작업 UUID 형태와 표본 중복
  // 함수역할:
  // - 생성한 100개 ID가 서로 다르며 UUID 검사·버전 4·허용 variant를 충족하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('operation UUIDs have version and variant and do not collide', () {
    final ids = List.generate(
      100,
      (_) => MedicationHistoryControl.newOperationId(),
    );
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(MedicationHistoryChange.isUuid(id), isTrue);
      expect(id[14], '4');
      expect('89ab'.contains(id[19]), isTrue);
    }
  });
}
