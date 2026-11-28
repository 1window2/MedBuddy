// 파일명: photo_dose_control_test.dart
// 역할: 사진으로 복용 기록의 요청 값 만들기, 계획·기록 응답 읽기, HTTP 요청 형식을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/photo_dose_control.dart';
import 'package:medbuddy_frontend/entities/photo_dose_plan_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';

Map<String, dynamic> planJson({
  List<Map<String, dynamic>>? pills,
  List<Map<String, dynamic>>? groups,
  List<Map<String, dynamic>>? asNeeded,
  bool ready = true,
}) => {
  'success': true,
  'plan_token': 'MjAyNi0xMS0yN1QwODoyMDowMCswOTowMA.abcdef0123456789',
  'as_of': '2026-11-27T08:20:00+09:00',
  'pills':
      pills ??
      [
        {
          'index': 1,
          'status': 'matched',
          'medication_id': 7,
          'evidence': 'imprint',
          'options': [],
          'lookalike_ids': [],
          'detail_at': null,
        },
      ],
  'groups':
      groups ??
      [
        {
          'schedule_date': '2026-11-27',
          'slot_key': 'morning',
          'reminder_at': '2026-11-27T08:00:00+09:00',
          'timing': 'on_time',
          'medication_ids': [7],
          'missing_medication_ids': [8],
        },
      ],
  'as_needed': asNeeded ?? [],
  'ignored_answer_indexes': [],
  'medications': [
    {
      'id': 7,
      'name': '노바스크정5밀리그램(암로디핀베실산염)',
      'dosage': '1정',
      'dosing_mode': 'scheduled',
      'slot_keys': ['morning'],
      'image_url': '',
      'slot': {'schedule_date': '2026-11-27', 'slot_key': 'morning'},
    },
    {
      'id': 8,
      'name': '크레스토정10밀리그램',
      'dosage': '1정',
      'dosing_mode': 'scheduled',
      'slot_keys': ['morning'],
      'image_url': '',
      'slot': null,
    },
  ],
  'write': {
    'groups': [
      {
        'schedule_date': '2026-11-27',
        'slot_key': 'morning',
        'medication_ids': [7],
      },
    ],
    'as_needed_medication_ids': [],
    'regimen_revisions': {'7': 0},
  },
  'ready': ready,
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('pill json keeps candidates, imprint matches and safe labels only', () {
    final result = PillIdentificationResult(
      isConfident: false,
      requiresConfirmation: true,
      observedFeatures: const PillVisualFeatures(
        shape: 'round',
        colors: ['white', 'White<x>', 'white'],
        frontImprint: 'N',
        backImprint: 'V5',
      ),
      candidates: const [
        PillIdentificationCandidate(
          itemSeq: '200110001',
          itemName: 'A',
          matchedAttributes: ['shape', 'imprint'],
        ),
        PillIdentificationCandidate(itemSeq: 'bad seq!', itemName: 'B'),
        PillIdentificationCandidate(itemSeq: '200110002', itemName: 'C'),
      ],
    );
    final json = photoDosePillJson(3, result);
    expect(json['index'], 3);
    expect(json['item_seqs'], ['200110001', '200110002']);
    expect(json['imprint_item_seqs'], ['200110001']);
    expect(json['has_imprint'], isTrue);
    expect(json['shape'], 'round');
    expect(json['colors'], ['white']);
  });

  test('one imprint character is not a visible imprint', () {
    final result = PillIdentificationResult(
      isConfident: false,
      requiresConfirmation: true,
      observedFeatures: const PillVisualFeatures(
        shape: 'Oval?',
        frontImprint: '-',
        backImprint: 'A',
      ),
      candidates: const [],
    );
    final json = photoDosePillJson(1, result);
    expect(json['has_imprint'], isFalse);
    expect(json['shape'], 'unknown');
  });

  test('plan parses groups, warnings and the server wall-clock time', () {
    final plan = PhotoDosePlan.fromJson(
      planJson(
        pills: [
          {
            'index': 1,
            'status': 'matched',
            'medication_id': 7,
            'evidence': 'look',
            'options': [],
            'lookalike_ids': [],
          },
          {
            'index': 2,
            'status': 'recently_taken',
            'medication_id': 8,
            'options': [],
            'lookalike_ids': [],
            'detail_at': '2026-11-27T08:10:00+09:00',
          },
          {
            'index': 3,
            'status': 'needs_choice',
            'medication_id': null,
            'options': [7, 8],
            'lookalike_ids': [7],
          },
        ],
      ),
    );
    expect(plan.groups.single.reminderAt, DateTime(2026, 11, 27, 8));
    expect(plan.asOf, DateTime(2026, 11, 27, 8, 20));
    expect(plan.pills.first.foundByLook, isTrue);
    expect(plan.warnings.single.detailAt, DateTime(2026, 11, 27, 8, 10));
    expect(plan.questions.single.options, [7, 8]);
    expect(plan.medications[7]!.slotKeys, ['morning']);
    expect(plan.groups.single.missingMedicationIds, [8]);
    expect(plan.medicationCount, 1);
    expect(plan.hasWrite, isTrue);
  });

  test('plan without a token or with an unknown status is rejected', () {
    expect(
      () => PhotoDosePlan.fromJson({...planJson(), 'plan_token': ''}),
      throwsFormatException,
    );
    expect(
      () => PhotoDosePlan.fromJson(
        planJson(
          pills: [
            {'index': 1, 'status': 'surprise'},
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('plan and confirm post the documented bodies', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/plan')) {
        return _json(planJson());
      }
      return _json({
        'success': true,
        'operation_id': 'op',
        'taken_at': '2026-11-27T08:20:00+09:00',
        'schedule_date': '2026-11-27',
        'data': [],
      });
    });
    final control = PhotoDoseControl(
      baseUrl: 'https://api.test/v1',
      client: client,
    );
    final pills = [
      {
        'index': 1,
        'item_seqs': ['200110001'],
      },
    ];
    final plan = await control.plan(pills: pills);
    final again = await control.plan(
      pills: pills,
      answers: const [PhotoDoseAnswer(1, null)],
      planToken: plan.planToken,
    );
    final recorded = await control.confirm(
      pills: pills,
      answers: const [PhotoDoseAnswer(1, 7)],
      plan: again,
      operationId: 'a6f2c3c1-0d3b-4c39-9d3c-3d7c1a2b4e5f',
    );
    expect(requests.map((r) => r.url.path), [
      '/v1/schedule/photo-intake/plan',
      '/v1/schedule/photo-intake/plan',
      '/v1/schedule/photo-intake/confirm',
    ]);
    final first = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(first.containsKey('plan_token'), isFalse);
    final second = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(second['plan_token'], plan.planToken);
    expect(second['answers'], [
      {'index': 1, 'medication_id': null},
    ]);
    final third = jsonDecode(requests[2].body) as Map<String, dynamic>;
    expect(third['operation_id'], 'a6f2c3c1-0d3b-4c39-9d3c-3d7c1a2b4e5f');
    expect(third['expected'], planJson()['write']);
    expect(recorded.scheduleDate, '2026-11-27');
    expect(recorded.takenAt, DateTime(2026, 11, 27, 8, 20));
  });

  test('a 409 from the server surfaces as an ApiRequestException', () async {
    final control = PhotoDoseControl(
      baseUrl: 'https://api.test/v1',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'expired'}), 409),
      ),
    );
    await expectLater(
      control.plan(
        pills: [
          {'index': 1},
        ],
      ),
      throwsA(
        isA<ApiRequestException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });
}
