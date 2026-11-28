// 파일명: photo_dose_recording_ui_boundary_test.dart
// 역할: 사진으로 복용 기록 화면의 흐름(본인 약 없음, 바로 확인, 질문, 겹치는 큐, 409, 두 번 누름)을 검증한다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/photo_dose_recording_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/identify_pill_control.dart';
import 'package:medbuddy_frontend/controls/photo_dose_control.dart';
import 'package:medbuddy_frontend/entities/photo_dose_plan_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/api_response_parser.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

http.Client _offline() => MockClient((_) async => http.Response('{}', 500));

// 클래스명: _FakeIdentify
// 역할: 정해 둔 알약 관찰을 돌려주는 알약 분석.
class _FakeIdentify extends IdentifyPill {
  final int pillCount;

  _FakeIdentify({this.pillCount = 1}) : super(client: _offline());

  @override
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    if (pillCount == 0) {
      // 서버는 알약이 없으면 422(사진 품질)로 답한다.
      throw const PillIdentificationException(
        PillIdentificationFailure.invalidPhoto,
      );
    }
    return _result();
  }

  MultiplePillIdentificationResult _result() =>
      MultiplePillIdentificationResult(
        requiresConfirmation: true,
        observations: [
          for (var i = 1; i <= pillCount; i++)
            MultiplePillObservation(
              index: i,
              boundingBox: const PillBoundingBox(
                left: 0.1,
                top: 0.1,
                width: 0.2,
                height: 0.2,
              ),
              identification: const PillIdentificationResult(
                isConfident: false,
                requiresConfirmation: true,
                observedFeatures: PillVisualFeatures(
                  shape: 'round',
                  colors: ['white'],
                ),
                candidates: [
                  PillIdentificationCandidate(
                    itemSeq: '200110001',
                    itemName: 'A',
                  ),
                ],
              ),
            ),
        ],
      );

  @override
  Future<Uint8List> cropPillImage(
    Uint8List image,
    PillBoundingBox region,
  ) async => _png;
}

// 클래스명: _FakeControl
// 역할: 차례로 정해 둔 계획을 돌려주고 기록 요청을 센다.
class _FakeControl extends PhotoDoseControl {
  final List<Map<String, dynamic>> plans;
  Object? confirmError;
  int planCalls = 0;
  int confirmCalls = 0;
  List<PhotoDoseAnswer> lastAnswers = const [];

  _FakeControl(this.plans)
    : super(baseUrl: 'https://api.test', client: _offline());

  @override
  Future<PhotoDosePlan> plan({
    required List<Map<String, dynamic>> pills,
    List<PhotoDoseAnswer> answers = const [],
    String? planToken,
  }) async {
    lastAnswers = answers;
    final index = planCalls < plans.length ? planCalls : plans.length - 1;
    planCalls++;
    return PhotoDosePlan.fromJson(plans[index]);
  }

  @override
  Future<PhotoDoseRecordResult> confirm({
    required List<Map<String, dynamic>> pills,
    required List<PhotoDoseAnswer> answers,
    required PhotoDosePlan plan,
    required String operationId,
  }) async {
    confirmCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (confirmError != null) throw confirmError!;
    return PhotoDoseRecordResult(
      operationId: operationId,
      takenAt: DateTime(2026, 11, 27, 8, 20),
      scheduleDate: '2026-11-27',
      todaySchedule: const [],
    );
  }
}

Map<String, dynamic> _medication(int id, String name) => {
  'id': id,
  'name': name,
  'dosage': '1정',
  'dosing_mode': 'scheduled',
  'slot_keys': ['morning'],
  'image_url': '',
};

Map<String, dynamic> _readyPlan() => {
  'success': true,
  'plan_token': 'MjAyNi0xMS0yN1QwODoyMDowMCswOTowMA.abcdef0123456789',
  'as_of': '2026-11-27T08:20:00+09:00',
  'pills': [
    {
      'index': 1,
      'status': 'matched',
      'medication_id': 7,
      'evidence': 'imprint',
      'options': [],
      'lookalike_ids': [],
    },
  ],
  'groups': [
    {
      'schedule_date': '2026-11-27',
      'slot_key': 'morning',
      'reminder_at': '2026-11-27T08:00:00+09:00',
      'timing': 'on_time',
      'medication_ids': [7],
      'missing_medication_ids': [],
    },
  ],
  'as_needed': [],
  'medications': [_medication(7, '노바스크정5밀리그램(암로디핀베실산염)')],
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
  'ready': true,
};

Map<String, dynamic> _questionPlan() => {
  ..._readyPlan(),
  'pills': [
    {
      'index': 1,
      'status': 'needs_choice',
      'medication_id': null,
      'options': [7],
      'lookalike_ids': [7],
    },
  ],
  'groups': [],
  'write': {
    'groups': [],
    'as_needed_medication_ids': [],
    'regimen_revisions': {},
  },
  'ready': false,
};

Future<_Harness> _pump(
  WidgetTester tester, {
  required _FakeControl control,
  bool hasOwnMedicines = true,
  bool overlap = false,
  int pillCount = 1,
}) async {
  final harness = _Harness();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PhotoDoseRecordingUI(
        userSetting: UserSetting(language: 'ko', fontSize: 20),
        hasOwnMedicines: hasOwnMedicines,
        onBeforePlan: () async => harness.flushes++,
        hasPendingOverlap: (_) => overlap,
        onRecorded: (result) async => harness.recorded.add(result),
        onRegisterRequested: () => harness.registerRequests++,
        identifyPill: _FakeIdentify(pillCount: pillCount),
        photoDoseControl: control,
        takePhoto: () async => _png,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  int flushes = 0;
  int registerRequests = 0;
  final List<PhotoDoseRecordResult> recorded = [];
}

Future<void> _tapConfirmAfterGuard(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 450)),
  );
  await tester.tap(find.byKey(const ValueKey('photoDoseConfirmButton')));
  await tester.pump();
}

void main() {
  testWidgets('without own medicines it explains and offers registration', (
    tester,
  ) async {
    final control = _FakeControl([_readyPlan()]);
    final harness = await _pump(
      tester,
      control: control,
      hasOwnMedicines: false,
    );
    expect(
      find.byKey(const ValueKey('photoDoseProblemnoMedicines')),
      findsOneWidget,
    );
    expect(control.planCalls, 0);
    await tester.tap(find.byKey(const ValueKey('photoDoseRegister')));
    await tester.pumpAndSettle();
    expect(harness.registerRequests, 1);
  });

  testWidgets('a matched photo goes straight to one confirm and records once', (
    tester,
  ) async {
    final control = _FakeControl([_readyPlan()]);
    final harness = await _pump(tester, control: control);
    expect(harness.flushes, 1);
    expect(find.byKey(const ValueKey('photoDoseConfirm')), findsOneWidget);
    expect(find.text('아침 약을 드시는 게 맞나요?'), findsOneWidget);
    expect(find.text('노바스크정5밀리그램'), findsOneWidget);
    expect(find.text('암로디핀베실산염'), findsOneWidget);
    expect(find.textContaining('오전 8:00'), findsOneWidget);

    await _tapConfirmAfterGuard(tester);
    // 기록 중에 다시 눌러도 요청은 하나다.
    await tester.tap(find.byKey(const ValueKey('photoDoseConfirmButton')));
    await tester.pumpAndSettle();
    expect(control.confirmCalls, 1);
    expect(harness.recorded, hasLength(1));
    expect(find.byKey(const ValueKey('photoDoseDone')), findsOneWidget);
    expect(find.text('복약을 완료했어요'), findsOneWidget);
    expect(find.text('아침 약 1개를 기록했어요'), findsOneWidget);
    expect(find.text('오전 8:20에 드셨어요'), findsOneWidget);
  });

  testWidgets('a tap right after the confirm screen appears is ignored', (
    tester,
  ) async {
    final control = _FakeControl([_readyPlan()]);
    await _pump(tester, control: control);
    await tester.tap(find.byKey(const ValueKey('photoDoseConfirmButton')));
    await tester.pumpAndSettle();
    expect(control.confirmCalls, 0);
    expect(find.byKey(const ValueKey('photoDoseConfirm')), findsOneWidget);
  });

  testWidgets('a look-alike question is answered and the plan is recomputed', (
    tester,
  ) async {
    final control = _FakeControl([_questionPlan(), _readyPlan()]);
    await _pump(tester, control: control);
    expect(find.text('이 약이 맞나요?'), findsOneWidget);
    expect(find.text('찍은 약'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photoDoseAnswerYes')));
    await tester.pumpAndSettle();
    expect(control.planCalls, 2);
    expect(control.lastAnswers.single.medicationId, 7);
    expect(find.byKey(const ValueKey('photoDoseConfirm')), findsOneWidget);
  });

  testWidgets('answering no records nothing and explains why', (tester) async {
    final nothing = {
      ..._questionPlan(),
      'pills': [
        {
          'index': 1,
          'status': 'skipped',
          'medication_id': null,
          'options': [],
          'lookalike_ids': [],
        },
      ],
    };
    final control = _FakeControl([_questionPlan(), nothing]);
    await _pump(tester, control: control);
    await tester.tap(find.byKey(const ValueKey('photoDoseAnswerNo')));
    await tester.pumpAndSettle();
    expect(control.lastAnswers.single.medicationId, isNull);
    expect(
      find.byKey(const ValueKey('photoDoseProblemnothingToRecord')),
      findsOneWidget,
    );
  });

  testWidgets('an unsent overlapping dose record blocks the confirm', (
    tester,
  ) async {
    final control = _FakeControl([_readyPlan()]);
    final harness = await _pump(tester, control: control, overlap: true);
    await _tapConfirmAfterGuard(tester);
    await tester.pumpAndSettle();
    expect(control.confirmCalls, 0);
    expect(harness.recorded, isEmpty);
    expect(
      find.byKey(const ValueKey('photoDoseProblempendingQueue')),
      findsOneWidget,
    );
  });

  testWidgets('a changed plan (409) asks for a new photo and records nothing', (
    tester,
  ) async {
    final control = _FakeControl([_readyPlan()])
      ..confirmError = ApiRequestException('x', statusCode: 409);
    final harness = await _pump(tester, control: control);
    await _tapConfirmAfterGuard(tester);
    await tester.pumpAndSettle();
    expect(harness.recorded, isEmpty);
    expect(
      find.byKey(const ValueKey('photoDoseProblemplanChanged')),
      findsOneWidget,
    );
    expect(find.text('다시 찍기'), findsOneWidget);
  });

  testWidgets('a connection failure retries the same confirm', (tester) async {
    final control = _FakeControl([_readyPlan()])
      ..confirmError = ApiRequestException('x');
    await _pump(tester, control: control);
    await _tapConfirmAfterGuard(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('photoDoseProblemconnection')),
      findsOneWidget,
    );
    control.confirmError = null;
    await tester.tap(find.byKey(const ValueKey('photoDoseRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photoDoseConfirm')), findsOneWidget);
    expect(control.planCalls, 1);
  });

  testWidgets('warnings are shown above the medicines', (tester) async {
    final plan = _readyPlan()
      ..['pills'] = [
        ...(_readyPlan()['pills'] as List),
        {
          'index': 2,
          'status': 'recently_taken',
          'medication_id': 8,
          'options': [],
          'lookalike_ids': [],
          'detail_at': '2026-11-27T08:10:00+09:00',
        },
      ]
      ..['medications'] = [
        _medication(7, '노바스크정5밀리그램(암로디핀베실산염)'),
        _medication(8, '아스피린프로텍트정100밀리그램'),
      ];
    final control = _FakeControl([plan]);
    await _pump(tester, control: control);
    expect(find.byKey(const ValueKey('photoDoseWarnings')), findsOneWidget);
    expect(find.text('아스피린프로텍트정100밀리그램은 오전 8:10에 이미 드셨어요.'), findsOneWidget);
    final warningTop = tester.getTopLeft(
      find.byKey(const ValueKey('photoDoseWarnings')),
    );
    final medicineTop = tester.getTopLeft(find.text('노바스크정5밀리그램'));
    expect(warningTop.dy, lessThan(medicineTop.dy));
  });

  testWidgets('a photo without pills asks for a new photo', (tester) async {
    final control = _FakeControl([_readyPlan()]);
    await _pump(tester, control: control, pillCount: 0);
    expect(
      find.byKey(const ValueKey('photoDoseProblemnoPills')),
      findsOneWidget,
    );
    expect(find.text('알약이 잘 보이지 않아요'), findsOneWidget);
    expect(control.planCalls, 0);
  });

  testWidgets('cancel closes without recording', (tester) async {
    final control = _FakeControl([_readyPlan()]);
    final harness = await _pump(tester, control: control);
    await tester.tap(find.byKey(const ValueKey('photoDoseCancel')));
    await tester.pumpAndSettle();
    expect(control.confirmCalls, 0);
    expect(harness.recorded, isEmpty);
    expect(find.byKey(const ValueKey('photoDoseConfirm')), findsNothing);
  });
}
