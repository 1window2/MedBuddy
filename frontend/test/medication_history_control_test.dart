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
MedicationHistoryChange _change() => MedicationHistoryChange(
  entry: MedicationHistoryEntry.fromJson(historyTestEntry(revision: 4)),
  status: MedicationHistoryStatus.taken,
  actualTakenAt: historyTestNow.subtract(const Duration(minutes: 5)),
  operationId: MedicationHistoryControl.newOperationId(),
);

// 함수역할: 제어 객체의 요청과 실패 경계 회귀 테스트를 등록한다.
void main() {
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
      // CSV는 보관 기간(최근 90일) 밖으로 나가면 요청 전에 거부한다.
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

  test('a CSV longer than 31 days is read in 31-day parts and merged', () async {
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
      merged.items.map((item) => MedicationHistoryDates.format(item.scheduleDate)),
      [
        '2026-10-17',
        '2026-09-17',
        '2026-09-16',
        '2026-08-17',
        '2026-08-16',
        '2026-07-20',
      ],
    );
    expect(merged.medications.map((item) => item.id).toSet(), hasLength(
      merged.medications.length,
    ));
    expect(control.busy, isFalse);
  });

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
            DateTime.utc(2026, 9, 1),
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

  // 중복 탭, 조회 중 수정, 수정 중 조회를 하나의 요청 잠금으로 막는다.
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
