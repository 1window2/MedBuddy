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

void main() {
  for (final source in ['llm_catalog_candidate', 'user_edit']) {
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
        find.text('처방전: ${source == 'user_edit' ? '애니코프' : '에니코프'}캡슐300mg'),
        findsOneWidget,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
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

  test(
    'explicit name edit supersedes OCR but multiple legacy results still require review',
    () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {'extracted_text': '사용자가수정한정100mg'});
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
