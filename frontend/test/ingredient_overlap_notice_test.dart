// 파일명: ingredient_overlap_notice_test.dart
// 역할: 성분 중복 확인의 요청 범위·응답 변환, 결과 출처별 거르기, 안내 문구, 결과 화면의 한 번 실행과 접힌 카드 표시를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_ingredient_overlap_control.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_prescription_change_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/ingredient_overlap_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

const _tylenol = '200000001';
const _gevorin = '200000002';
const _pancold = '200000003';

// Function Name: _overlap
// Description: Builds one overlap entry for wording and filtering tests.
// Parameters: seq/name: other medicine; source: its place; same: same product; ingredient: shared ingredient name.
// Returns: IngredientOverlap.
IngredientOverlap _overlap(
  String seq,
  String name, {
  IngredientOverlapSource source = IngredientOverlapSource.saved,
  bool same = false,
  String ingredient = '아세트아미노펜',
}) => IngredientOverlap(
  ingredientCode: 'M040702',
  ingredientName: ingredient,
  withItemSeq: seq,
  withItemName: name,
  source: source,
  sameProduct: same,
);

// Function Name: _entry
// Description: Builds one server overlap entry.
// Parameters: seq/name: other medicine; source: "saved" or "batch"; same: same product flag.
// Returns: JSON map.
Map<String, Object> _entry(
  String seq,
  String name, {
  String source = 'saved',
  bool same = false,
}) => {
  'ingredient_code': 'M040702',
  'ingredient_name': '아세트아미노펜',
  'with': {
    'item_seq': seq,
    'item_name': name,
    'source': source,
    'same_product': same,
  },
};

// Class Name: _FakeOverlapControl
// Role: Overlap control double that records requests and answers from a fixed map or fails.
// Responsibilities: Count calls, keep requested numbers, and optionally hold or fail the answer.
// Attributes: answer: overlaps by item_seq; error: failure to throw; calls: requested lists; gate: optional pending answer.
class _FakeOverlapControl extends CheckIngredientOverlap {
  final Map<String, List<IngredientOverlap>> answer;
  final Object? error;
  final List<List<String>> calls = [];
  Completer<void>? gate;

  // Function Name: _FakeOverlapControl
  // Description: Stores the answer or failure.
  // Parameters: answer: overlaps by item_seq; error: failure to throw.
  // Returns: _FakeOverlapControl.
  _FakeOverlapControl({this.answer = const {}, this.error})
    : super(client: MockClient((_) async => throw StateError('no HTTP')));

  // Function Name: requestIngredientOverlap
  // Description: Records the product numbers and answers or fails.
  // Parameters: itemSeqs: requested product numbers.
  // Returns: The fixed answer.
  @override
  Future<Map<String, List<IngredientOverlap>>> requestIngredientOverlap(
    Iterable<String> itemSeqs,
  ) async {
    calls.add(itemSeqs.toList());
    await gate?.future;
    if (error != null) throw error!;
    return answer;
  }
}

// Class Name: _FakeInputPrescription
// Role: OCR fixture that returns fixed recognized rows.
// Responsibilities: Simulate a selected prescription image without a gallery.
// Attributes: schedules: recognized rows.
class _FakeInputPrescription extends InputPrescription {
  final List<MedicationSchedule> schedules;

  // Function Name: _FakeInputPrescription
  // Description: Stores the recognized rows.
  // Parameters: schedules: rows returned for the selected image.
  // Returns: _FakeInputPrescription.
  _FakeInputPrescription(this.schedules);

  // Function Name: requestPrescriptionImageFromGallery
  // Description: Signals selection and returns the fixed rows.
  // Parameters: onImageSelected/onProgress: progress callbacks.
  // Returns: The fixed rows.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
    PrescriptionRecognitionProgressCallback? onProgress,
  }) async {
    onImageSelected?.call();
    return schedules;
  }
}

// Class Name: _FakeMedicationDetail
// Role: Catalog lookup double that gives each row a fixed product number.
// Responsibilities: Map recognized names to product numbers.
// Attributes: seqByName: product number by recognized name.
class _FakeMedicationDetail extends CheckMedicationDetail {
  final Map<String, String> seqByName;

  // Function Name: _FakeMedicationDetail
  // Description: Stores the product numbers.
  // Parameters: seqByName: product number by name.
  // Returns: _FakeMedicationDetail.
  _FakeMedicationDetail(this.seqByName);

  // Function Name: requestMedicationDetail
  // Description: Returns a detail with the configured product number.
  // Parameters: medicationSchedule: recognized row.
  // Returns: MedicationDetail.
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async => MedicationDetail(
    itemSeq: seqByName[medicationSchedule.medicationName] ?? '',
    itemName: medicationSchedule.medicationName,
    efficacy: 'effect',
    usageMethod: 'usage',
    warning: 'warning',
  );
}

// Class Name: _NoPreviousPrescription
// Role: Change-radar double without a previous prescription.
// Responsibilities: Keep the prescription result free of network work.
// Attributes: None.
class _NoPreviousPrescription extends CheckPrescriptionChange {
  // Function Name: _NoPreviousPrescription
  // Description: Uses an HTTP client that is never called.
  // Parameters: None.
  // Returns: _NoPreviousPrescription.
  _NoPreviousPrescription()
    : super(client: MockClient((_) async => throw StateError('no HTTP')));

  // Function Name: requestPrescriptionChange
  // Description: Answers without a previous prescription.
  // Parameters: medications: ignored.
  // Returns: Empty radar.
  @override
  Future<PrescriptionChangeRadar> requestPrescriptionChange(
    List<AnalyzedMedication> medications,
  ) async => const PrescriptionChangeRadar(hasPreviousPrescription: false);
}

// Function Name: _model
// Description: Builds a view model whose other network calls fail fast.
// Parameters: overlap: overlap control; input/detail: optional prescription fixtures.
// Returns: MedBuddyViewModel disposed after the test.
MedBuddyViewModel _model(
  CheckIngredientOverlap overlap, {
  InputPrescription? input,
  CheckMedicationDetail? detail,
}) {
  final model = MedBuddyViewModel(
    patientHash: 'overlap-patient',
    apiClient: MockClient(
      (request) async => http.Response('{"detail":"offline"}', 503),
    ),
    notificationService: RecordingNotificationService(),
    checkIngredientOverlap: overlap,
    checkPrescriptionChange: _NoPreviousPrescription(),
    inputPrescription: input,
    checkMedicationDetail: detail,
  );
  addTearDown(model.dispose);
  return model;
}

// Function Name: _pill
// Description: Builds one confirmed pill row.
// Parameters: seq/name: product.
// Returns: IdentifiedPillSaveRequest.
IdentifiedPillSaveRequest _pill(String seq, String name) =>
    IdentifiedPillSaveRequest(
      candidate: PillIdentificationCandidate(
        itemSeq: seq,
        itemName: name,
        imageUrl: '',
      ),
      medicationSchedule: MedicationSchedule(
        medicationName: name,
        dosage: '1정',
        medicationTime: 3,
        prescriptionDate: DateTime(2026, 11, 28),
        scheduleSlotKeys: const ['morning'],
      ),
    );

// Function Name: _resultScreen
// Description: Mounts the result screen with fixed rows and overlaps.
// Parameters: english: language; overlaps: notices by row.
// Returns: Widget.
Widget _resultScreen({
  bool english = false,
  Map<int, List<IngredientOverlap>> overlaps = const {},
}) => MaterialApp(
  theme: MedBuddyTheme.light(),
  home: CheckResultUI(
    source: MedicationResultSource.pillPhoto,
    analyzedMedicationList: [
      for (final name in ['게보린정', '파모티딘정'])
        AnalyzedMedication(
          schedule: MedicationSchedule(medicationName: name, dosage: '1정'),
          detail: MedicationDetail(
            itemName: name,
            efficacy: '',
            usageMethod: '',
            warning: '',
          ),
        ),
    ],
    ingredientOverlaps: overlaps,
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    statusMessageProvider: () => '',
    savingMedicationIndex: null,
    completedMedicationSaveIndexes: const {},
    isAllMedicationSaving: false,
    onCloseRequested: () {},
    onAllMedicationSaveRequested: () async => true,
    onMedicationSaveRequested: (_, _) async => true,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CheckIngredientOverlap', () {
    test(
      'sends only distinct numeric product numbers and decodes by item_seq',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final control = CheckIngredientOverlap(
          baseUrl: 'http://localhost',
          patientHash: 'patient-a',
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/ingredient-overlap');
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'success': true,
                'items': [
                  {
                    'item_seq': _gevorin,
                    'overlaps': [
                      _entry(_tylenol, '타이레놀정500'),
                      {'ingredient_code': 'M1', 'with': 'broken'},
                      _entry(_pancold, '판콜', source: 'unknown'),
                    ],
                  },
                  {'item_seq': _pancold, 'overlaps': []},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );

        final result = await control.requestIngredientOverlap([
          ' $_gevorin ',
          '',
          'ITEM-1',
          _gevorin,
          _pancold,
          '1' * 33,
        ]);

        expect(bodies.single, {
          'patient_hash': 'patient-a',
          'item_seqs': [_gevorin, _pancold],
        });
        expect(result.keys, [_gevorin, _pancold]);
        final overlap = result[_gevorin]!.single;
        expect(overlap.withItemSeq, _tylenol);
        expect(overlap.withItemName, '타이레놀정500');
        expect(overlap.ingredientName, '아세트아미노펜');
        expect(overlap.source, IngredientOverlapSource.saved);
        expect(overlap.sameProduct, isFalse);
        expect(result[_pancold], isEmpty);
      },
    );

    test(
      'skips HTTP without a valid number and caps the request at 50',
      () async {
        var calls = 0;
        final control = CheckIngredientOverlap(
          baseUrl: 'http://localhost',
          client: MockClient((_) async {
            calls++;
            return http.Response('{"success":true,"items":[]}', 200);
          }),
        );

        expect(
          await control.requestIngredientOverlap(['', ' ', 'A1']),
          isEmpty,
        );
        expect(calls, 0);
        expect(
          CheckIngredientOverlap.requestableItemSeqs([
            for (var index = 0; index < 60; index++) '${100 + index}',
          ]),
          hasLength(50),
        );
      },
    );

    test(
      'a server without the route answers no overlap; other failures propagate',
      () async {
        final missing = CheckIngredientOverlap(
          baseUrl: 'http://localhost',
          client: MockClient(
            (_) async => http.Response('{"detail":"Not Found"}', 404),
          ),
        );
        final failing = CheckIngredientOverlap(
          baseUrl: 'http://localhost',
          client: MockClient(
            (_) async => http.Response('{"detail":"failed"}', 500),
          ),
        );

        expect(await missing.requestIngredientOverlap([_tylenol]), isEmpty);
        await expectLater(
          failing.requestIngredientOverlap([_tylenol]),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('filterIngredientOverlapsForSource', () {
    final overlaps = [
      _overlap(_tylenol, '타이레놀정500', same: true),
      _overlap(_pancold, '판콜', source: IngredientOverlapSource.batch),
      _overlap('200000005', '타이레놀ER'),
    ];

    test('a prescription keeps only other saved products', () {
      expect(
        filterIngredientOverlapsForSource(
          overlaps,
          MedicationResultSource.prescription,
        ).map((overlap) => overlap.withItemName),
        ['타이레놀ER'],
      );
    });

    test(
      'an early prescription refill of a co-prescribed pair shows no notice',
      () {
        // 지난 처방의 A·B가 아직 복약 목록에 있고, 같은 성분인 A·B를 다시 처방받았다.
        final refill = [
          _overlap('200000005', '타이레놀ER'),
          _overlap('200000009', '다른처방약'),
        ];
        expect(
          filterIngredientOverlapsForSource(
            refill,
            MedicationResultSource.prescription,
            resultItemSeqs: {_tylenol, '200000005'},
          ).map((overlap) => overlap.withItemName),
          ['다른처방약'],
        );
        expect(
          filterIngredientOverlapsForSource(
            refill,
            MedicationResultSource.pillPhoto,
            resultItemSeqs: {_tylenol, '200000005'},
          ),
          refill,
        );
      },
    );

    test('pill and manual results keep same products and batch entries', () {
      for (final source in [
        MedicationResultSource.pillPhoto,
        MedicationResultSource.manual,
      ]) {
        expect(filterIngredientOverlapsForSource(overlaps, source), overlaps);
      }
    });
  });

  group('ingredientOverlapNoticeText', () {
    test('one other product in the list', () {
      expect(
        ingredientOverlapNoticeText([
          _overlap(_tylenol, '타이레놀정500'),
        ], isEnglish: false),
        '복약 목록의 ‘타이레놀정500’에도 같은 성분(아세트아미노펜)이 들어 있어요. '
        '함께 드셔도 되는지 약사나 의사에게 물어보세요.',
      );
      expect(
        ingredientOverlapNoticeText([
          _overlap(_tylenol, '타이레놀정500'),
        ], isEnglish: true),
        '‘타이레놀정500’ in your medication list also contains the same '
        'ingredient (아세트아미노펜). Ask a pharmacist or doctor whether you can '
        'take them together.',
      );
    });

    test('two products are listed and three or more are counted', () {
      final two = [_overlap('1', 'A'), _overlap('2', 'B')];
      final four = [
        ...two,
        _overlap('3', 'C', ingredient: '카페인무수물'),
        _overlap('3', 'C', ingredient: '아세트아미노펜'),
        _overlap('4', 'D'),
      ];

      expect(
        ingredientOverlapNoticeText(two, isEnglish: false),
        startsWith('복약 목록의 ‘A’, ‘B’에도 같은 성분(아세트아미노펜)이 들어 있어요.'),
      );
      expect(
        ingredientOverlapNoticeText(four, isEnglish: false),
        '복약 목록의 ‘A’, ‘B’ 외 2개에도 같은 성분(아세트아미노펜, 카페인무수물)이 들어 있어요. '
        '함께 드셔도 되는지 약사나 의사에게 물어보세요.',
      );
      expect(
        ingredientOverlapNoticeText(two, isEnglish: true),
        startsWith(
          '‘A’ and ‘B’ in your medication list also contain the same ingredient',
        ),
      );
      expect(
        ingredientOverlapNoticeText(four, isEnglish: true),
        startsWith(
          '‘A’, ‘B’ and 2 more in your medication list also contain the same '
          'ingredients (아세트아미노펜, 카페인무수물).',
        ),
      );
    });

    test('the same product already in the list', () {
      final same = [_overlap(_tylenol, '타이레놀정500', same: true)];

      expect(
        ingredientOverlapNoticeText(same, isEnglish: false),
        '이미 복약 목록에 같은 약(‘타이레놀정500’)이 있어요. 같은 약을 두 번 등록하는지 확인해 주세요.',
      );
      expect(
        ingredientOverlapNoticeText(same, isEnglish: true),
        'Your medication list already has the same medicine (‘타이레놀정500’). '
        'Check that you are not registering it twice.',
      );
    });

    test('a product on the same result screen', () {
      expect(
        ingredientOverlapNoticeText([
          _overlap(_pancold, '판콜', source: IngredientOverlapSource.batch),
        ], isEnglish: false),
        '이 결과 목록의 ‘판콜’에도 같은 성분(아세트아미노펜)이 들어 있어요. '
        '함께 드셔도 되는지 약사나 의사에게 물어보세요.',
      );
    });

    test('no overlap gives no text', () {
      expect(ingredientOverlapNoticeText(const [], isEnglish: false), isEmpty);
      expect(ingredientOverlapNoticeText(const [], isEnglish: true), isEmpty);
    });
  });

  group('result screen check', () {
    test(
      'runs once for pill results, keys by row and names batch rows as shown',
      () async {
        final control = _FakeOverlapControl(
          answer: {
            _gevorin: [
              _overlap(_tylenol, '타이레놀정500', same: true),
              _overlap(
                _pancold,
                '판콜에이내복액',
                source: IngredientOverlapSource.batch,
              ),
            ],
          },
        );
        final model = _model(control);

        expect(
          model.showPillMedicationRegistrationResults([
            _pill(_pancold, '판콜 사진 후보'),
            _pill(_gevorin, '게보린정'),
          ]),
          isTrue,
        );
        expect(model.ingredientOverlapsByMedicationIndex, isEmpty);
        await pumpEventQueue();

        expect(control.calls, [
          [_pancold, _gevorin],
        ]);
        expect(model.ingredientOverlapsByMedicationIndex.keys, [1]);
        expect(
          model.ingredientOverlapsByMedicationIndex[1]!.map(
            (overlap) => overlap.withItemName,
          ),
          ['타이레놀정500', '판콜 사진 후보'],
        );

        model.showMedicationAnalysisResult();
        await model.requestAllAnalyzedMedicationSave();
        await pumpEventQueue();
        expect(control.calls, hasLength(1));
      },
    );

    test('a prescription drops batch and same-product entries', () async {
      final control = _FakeOverlapControl(
        answer: {
          _gevorin: [
            _overlap(_gevorin, '게보린정', same: true),
            _overlap(_pancold, '판콜', source: IngredientOverlapSource.batch),
          ],
          _pancold: [
            _overlap(_tylenol, '타이레놀정500'),
            _overlap(_gevorin, '게보린', source: IngredientOverlapSource.batch),
          ],
        },
      );
      final model = _model(
        control,
        input: _FakeInputPrescription(const [
          MedicationSchedule(medicationName: 'gevorin'),
          MedicationSchedule(medicationName: 'pancold'),
          MedicationSchedule(medicationName: 'unlisted'),
        ]),
        detail: _FakeMedicationDetail({
          'gevorin': _gevorin,
          'pancold': _pancold,
        }),
      );

      await model.requestPrescriptionImageFromGallery();
      model.showMedicationAnalysisResult();
      await pumpEventQueue();

      expect(model.medicationResultSource, MedicationResultSource.prescription);
      expect(control.calls, [
        [_gevorin, _pancold, ''],
      ]);
      expect(model.ingredientOverlapsByMedicationIndex.keys, [1]);
      expect(
        model.ingredientOverlapsByMedicationIndex[1]!.single.withItemSeq,
        _tylenol,
      );
    });

    for (final failure in <String, Object>{
      'lookup failure': StateError('offline'),
      'timeout': TimeoutException('slow'),
    }.entries) {
      test('${failure.key} shows nothing', () async {
        final control = _FakeOverlapControl(error: failure.value);
        final model = _model(control);

        model.showPillMedicationRegistrationResults([_pill(_gevorin, '게보린정')]);
        await pumpEventQueue();

        expect(control.calls, hasLength(1));
        expect(model.ingredientOverlapsByMedicationIndex, isEmpty);
      });
    }

    test('a 404 from an older server shows nothing', () async {
      final control = CheckIngredientOverlap(
        baseUrl: 'http://localhost',
        client: MockClient(
          (_) async => http.Response('{"detail":"Not Found"}', 404),
        ),
      );
      final model = _model(control);

      model.showPillMedicationRegistrationResults([_pill(_gevorin, '게보린정')]);
      await pumpEventQueue();

      expect(model.ingredientOverlapsByMedicationIndex, isEmpty);
    });

    test('an answer after leaving the result screen is discarded', () async {
      final control = _FakeOverlapControl(
        answer: {
          _gevorin: [_overlap(_tylenol, '타이레놀정500')],
        },
      )..gate = Completer<void>();
      final model = _model(control);

      model.showPillMedicationRegistrationResults([_pill(_gevorin, '게보린정')]);
      model.clearAnalysisResult();
      control.gate!.complete();
      await pumpEventQueue();

      expect(model.ingredientOverlapsByMedicationIndex, isEmpty);
    });
  });

  group('CheckResultUI notice', () {
    testWidgets('shows under the header while the card is collapsed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _resultScreen(
          overlaps: {
            0: [_overlap(_tylenol, '타이레놀정500')],
          },
        ),
      );

      expect(
        find.byKey(const Key('result-medication-summary-0')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('result-medication-overlap-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('result-medication-overlap-1')),
        findsNothing,
      );
      expect(
        find.textContaining('복약 목록의 ‘타이레놀정500’에도 같은 성분(아세트아미노펜)이 들어 있어요.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('result-medication-toggle-0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('result-medication-summary-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('result-medication-overlap-0')),
        findsOneWidget,
      );
    });

    testWidgets('no overlap shows no notice and no "no overlap" text', (
      tester,
    ) async {
      await tester.pumpWidget(_resultScreen(english: true));

      expect(
        find.byKey(const Key('result-medication-overlap-0')),
        findsNothing,
      );
      expect(find.textContaining('same ingredient'), findsNothing);
      expect(find.textContaining('overlap'), findsNothing);
    });
  });
}
