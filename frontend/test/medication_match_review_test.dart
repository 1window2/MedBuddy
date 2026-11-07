// 파일명: medication_match_review_test.dart
// 역할: 불확실한 약 검색 후보의 명시적 선택과 처방 이름 보존·좁은 화면 표시를 검증한다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/medication_candidate_dialog.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

const candidate = MedicationDetail(
  itemName: '애니코프캡슐300밀리그램',
  manufacturer: '테스트 제약',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

// 함수이름: main
// 함수역할:
// - 조회 결과의 모호성 분기와 후보창 확인·취소·폭별 배치 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: 용량 접미사가 있는 시럽 후보
  // 함수역할:
  // - 원래 시럽 이름으로 조회해 확인 요구 예외를 받고 후보창에 원문을 유지하며 취소·선택만으로 확정되지 않고 확인 버튼에서만 반환되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('syrup volume suffix offers an explicit candidate selection', (
    tester,
  ) async {
    const original = '시네츄라시럽_(15mL)';
    const schedule = MedicationSchedule(medicationName: original);
    final client = MockClient((request) async {
      expect(jsonDecode(request.body)['extracted_text'], original);
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [],
          'requires_confirmation': true,
          'review_reason': 'ambiguous_product',
          'candidates': [
            {'item_name': '시네츄라시럽', 'manufacturer': '테스트 제약'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    MedicationMatchReview? review;
    await expectLater(
      CheckMedicationDetail(client: client).requestMedicationDetail(schedule),
      throwsA(
        isA<MedicationMatchReview>().having(
          (value) {
            review = value;
            return value.candidates.single.itemName;
          },
          'candidate',
          '시네츄라시럽',
        ),
      ),
    );
    MedicationDetail? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [schedule],
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
          isMedicationLookupReview: true,
          matchReviews: {0: review!},
          onCandidateConfirmed: (_, detail) => confirmed = detail,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final candidates = find.byKey(const Key('medication-candidates-0'));
    await tester.ensureVisible(candidates);
    await tester.tap(candidates);
    await tester.pumpAndSettle();
    expect(find.text('약 이름: $original'), findsOneWidget);
    expect(find.text('시네츄라시럽'), findsOneWidget);
    final confirm = find.byKey(const Key('confirm-medication-candidate'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    await tester.tap(candidates);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-candidate-0')));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(confirmed?.itemName, '시네츄라시럽');
    expect(tester.takeException(), isNull);
  });

  for (final source in ['llm_catalog_candidate', 'user_edit']) {
    // 함수이름: 보정 출처별 후보창 이름
    // 함수역할:
    // - 사용자 수정은 수정 이름, 자동 후보 보정은 OCR 원문을 보여 주며 취소 시 후보 확정 콜백을 실행하지 않는지 확인한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('candidate dialog preserves the intended name ($source)', (
      tester,
    ) async {
      MedicationDetail? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: PrescriptionAnalysisPreviewUI(
            medicationScheduleList: [
              MedicationSchedule(
                medicationName: '애니코프캡슐300mg',
                rawMedicationName: '에니코프캡슐300mg',
                nameCorrectionSource: source,
              ),
            ],
            userSetting: const UserSetting(),
            onBackRequested: () {},
            onAnalysisRequested: () {},
            onMedicationScheduleChanged: (_, _) {},
            isMedicationLookupReview: true,
            matchReviews: {
              0: MedicationMatchReview([candidate]),
            },
            onCandidateConfirmed: (_, detail) => confirmed = detail,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('medication-candidates-0'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('약 이름: ${source == 'user_edit' ? '애니코프' : '에니코프'}캡슐300mg'),
        findsOneWidget,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
  // 함수이름: 계정 잠금과 일반 503 구분
  // 함수역할:
  // - 동일 503이라도 계정 처리 중 응답은 MedicationLookupBusy, 일반 상류 장애는 StateError로 구분하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'account lock is retryable but other 503 failures are not retried blindly',
    () async {
      var detail = 'This account is busy. Retry the request shortly.';
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': detail}),
          503,
          headers: {'retry-after': '5'},
        ),
      );
      addTearDown(client.close);
      final control = CheckMedicationDetail(client: client);
      const schedule = MedicationSchedule(medicationName: 'test');
      await expectLater(
        control.requestMedicationDetail(schedule),
        throwsA(isA<MedicationLookupBusy>()),
      );
      detail = 'Upstream unavailable';
      await expectLater(
        control.requestMedicationDetail(schedule),
        throwsStateError,
      );
    },
  );
  // 함수이름: OCR 원문 전송과 후보 검토
  // 함수역할:
  // - 자동 이름 보정 후에도 original_text를 전송하며 확인 요구 응답을 자동 선택하지 않고 제조사를 보존한 검토 예외로 전달하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'review response is not automatically selected and OCR original is sent',
    () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['original_text'], '에니코프캡슐300mg');
        return http.Response(
          jsonEncode({
            'success': true,
            'requires_confirmation': true,
            'data': [],
            'candidates': [
              {'item_name': candidate.itemName, 'manufacturer': '테스트 제약'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final control = CheckMedicationDetail(client: client);
      await expectLater(
        control.requestMedicationDetail(
          const MedicationSchedule(
            medicationName: '애니코프캡슐300밀리그램',
            rawMedicationName: '에니코프캡슐300mg',
            nameCorrectionSource: 'local_catalog_ocr_vowel_variant',
          ),
        ),
        throwsA(
          isA<MedicationMatchReview>().having(
            (review) => review.candidates.single.manufacturer,
            'manufacturer',
            '테스트 제약',
          ),
        ),
      );
    },
  );

  // 함수이름: 명시적 수정 이름과 구형 다중 결과
  // 함수역할:
  // - 사용자가 수정한 이름과 검색 모드만 전송하고 구형 응답에 여러 약이 있으면 검토를 요구하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'explicit name edit supersedes OCR but multiple legacy results still require review',
    () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'extracted_text': '사용자가수정한정100mg',
          'search_mode': 'balanced',
        });
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {'item_name': 'first'},
              {'item_name': 'second'},
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await expectLater(
        CheckMedicationDetail(client: client).requestMedicationDetail(
          const MedicationSchedule(
            medicationName: '사용자가수정한정100mg',
            rawMedicationName: 'OCR정500mg',
            nameCorrectionSource: 'user_edit',
          ),
        ),
        throwsA(isA<MedicationMatchReview>()),
      );
    },
  );

  for (final width in [360.0, 800.0]) {
    // 함수이름: 화면 폭별 명시적 후보 확정
    // 함수역할:
    // - 두 화면 폭에서 선택 전 확인을 막고 제조사를 표시하며 선택 후에도 확인 버튼을 눌러야 같은 후보 객체를 반환하는지 확인한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('candidate selection is explicit and fits width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MedicationDetail? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<MedicationDetail>(
                    context: context,
                    builder: (_) => const MedicationCandidateDialog(
                      originalName: '에니코프캡슐300mg',
                      candidates: [candidate],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('confirm-medication-candidate'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(find.text('테스트 제약'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.byKey(const Key('medication-candidate-0')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, same(candidate));
      expect(tester.takeException(), isNull);
    });
  }
}
