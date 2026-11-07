// 파일명: as_needed_schedule_loading_test.dart
// 역할: 필요시 약 조회의 빈 결과·재조회·오류 상태에서 로딩과 실제 약 카드가 구분되는지 검증한다.

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

// 클래스명: _HistoryResponse
// 역할: 응답 시점과 필요시 약 포함 여부를 제어하는 이력 조회 대역이다.
// 주요 책임:
// - 요청의 조회 기간을 보존하고 빈 결과·약 한 건·503 오류 중 하나를 반환한다.
// 속성:
// - gate(Completer<void>?): 응답을 보류할 신호; null이면 기다리지 않는다.
// - hasMedication(bool): 성공 응답에 기록 가능한 필요시 약을 포함할지 여부.
// - fail(bool): 대기 해제 뒤 503을 반환할지 여부.
class _HistoryResponse {
  Completer<void>? gate;
  bool hasMedication = false;
  bool fail = false;

  // 함수이름: respond
  // 함수역할:
  // - 선택적 gate를 기다린 뒤 현재 플래그에 따라 조회 응답 또는 503 오류를 만든다.
  // 매개변수:
  // - request(http.Request): start_date와 end_date를 응답에 반영할 요청.
  // 반환값:
  // - Future<http.Response>: 빈 이력과 선택적 약 목록의 200 JSON 또는 실패용 503 응답.
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

// 함수이름: _control
// 함수역할:
// - 고정 계정·시각과 메모리 대기 저장소를 사용하여 조회 대역을 이력 제어기에 연결한다.
// 매개변수:
// - response(_HistoryResponse): 결과와 완료 시점을 제어하는 대역.
// 반환값:
// - MedicationHistoryControl: 테스트 종료 시 자동 폐기되는 제어기.
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

// 함수이름: _screen
// 함수역할:
// - 스크롤 화면 안에 필요시 복약 영역을 배치하고 비어 있을 때의 문구를 지정한다.
// 매개변수:
// - control(MedicationHistoryControl): 화면이 관찰하는 이력 제어기.
// - version(int): 같은 화면에서 재조회를 유도하는 새로고침 버전.
// 반환값:
// - Widget: 테스트에 장착할 MaterialApp; 이 함수 자체는 렌더링을 수행하지 않는다.
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

// 함수이름: _expectOnlyLoading
// 함수역할:
// - 초기 로딩만 표시되고 필요시 카드·알림 설정·빈 결과 안내가 모두 숨겨져 있는지 검증한다.
// 매개변수:
// - 없음; 현재 테스트 위젯 트리를 조회한다.
// 반환값:
// - 없음; 로딩 이외의 내용이 노출되면 테스트가 실패한다.
void _expectOnlyLoading() {
  expect(find.byKey(const Key('schedule-prn-initial-loading')), findsOneWidget);
  expect(find.byKey(const Key('schedule-as-needed')), findsNothing);
  expect(find.text('필요시 복용'), findsNothing);
  expect(find.byKey(const Key('prn-reminder')), findsNothing);
  expect(find.text('오늘 복용할 약이 없습니다'), findsNothing);
}

// 함수이름: main
// 함수역할:
// - 최초 조회·빈 캐시 재조회·실제 약 캐시 재조회에서 화면 상태 전이를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 환경설정 초기화와 위젯 테스트를 등록한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 필요시 알림 설정이 다른 사례에서 남지 않도록 환경설정 대역을 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 새 메모리 환경설정을 설치한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 최초 응답을 대기하는 동안 로딩만 보이고 빈 응답 완료 후에만 복용할 약 없음 안내가 나오는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
      // 함수이름: testWidgets 콜백
      // 함수역할:
      // - 빈 결과가 캐시된 화면을 재조회하거나 다시 열 때 로딩만 보이며, 완료 후 빈 결과·약 카드·오류 중 해당 상태 하나로 전환되는지 검증한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 실제 약이 있는 캐시는 재조회 중 초기 로딩으로 대체하지 않고 카드와 약 이름을 계속 표시하는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
