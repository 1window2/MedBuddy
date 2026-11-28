import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

const _patient = 'registration-result-patient';
const _first = 'First selected medication';
const _second = 'Second selected medication';
const _firstId = '200000001';
const _secondId = '200000002';
const _chosenImage = 'https://nedrug.mfds.go.kr/chosen.jpg';
final _start = DateTime(2026, 11, 16);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('medbuddy-result-flow-');
    originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
  });

  tearDown(() async {
    await pumpEventQueue();
    PathProviderPlatform.instance = originalProvider;
    await directory.delete(recursive: true);
  });

  for (final source in [
    MedicationResultSource.manual,
    MedicationResultSource.pillPhoto,
  ]) {
    group(source.name, () {
      test(
        'handoff immediately enters results without lookup or persistence',
        () async {
          final flow = _Flow();
          expect(
            flow.model.medicationResultSource,
            MedicationResultSource.prescription,
          );
          expect(flow.show(source), isTrue);
          expect(
            flow.model.prescriptionFlowState,
            PrescriptionFlowState.resultReady,
          );
          expect(flow.model.medicationResultSource, source);
          expect(flow.model.analyzedMedicationList, hasLength(2));
          expect(flow.model.completedMedicationSaveIndexes, isEmpty);
          expect(flow.model.isMedicationSaving, isFalse);
          expect(flow.model.isAllMedicationSaving, isFalse);
          expect(flow.model.prescriptionChangeRadar, isNull);
          expect(flow.model.isPrescriptionChangeLoading, isFalse);
          expect(flow.requests, isEmpty);
          await pumpEventQueue();
          expect(flow.requests, isEmpty);
          expect(flow.overlapRequests, hasLength(1));
          expect(jsonDecode(flow.overlapRequests.single.body)['item_seqs'], [
            _firstId,
            _secondId,
          ]);
          expect(flow.rows, isEmpty);
          expect(await directory.list(recursive: true).toList(), isEmpty);
          final first = flow.model.analyzedMedicationList.first;
          expect(first.detail.itemSeq, _firstId);
          expect(first.detail.imageUrl, _chosenImage);
          expect(first.schedule.medicationName, _first);
          expect(first.schedule.dosage, '0.5mg');
          expect(first.schedule.prescriptionDate, _start);
          expect(first.schedule.medicationTime, 3);
          expect(first.schedule.scheduleSlotKeys, ['morning', 'evening']);
        },
      );

      test(
        'single save then bulk saves only pending rows in common state',
        () async {
          final flow = _Flow();
          flow.show(source);
          final first = flow.model.analyzedMedicationList.first;
          final gate = flow.pause('/save');
          final saving = flow.model.requestMedicationSave(first, 0);
          await gate.started.future;
          expect(flow.model.isMedicationSaving, isTrue);
          expect(flow.model.savingMedicationIndex, 0);
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
          expect(await flow.model.requestMedicationSave(first, 0), isFalse);
          expect(flow.show(source), isFalse);
          gate.release();
          expect(await saving, isTrue);
          expect(flow.model.completedMedicationSaveIndexes, {0});
          expect(flow.model.isMedicationSaving, isFalse);
          expect(flow.model.savingMedicationIndex, isNull);
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.model.completedMedicationSaveIndexes, {0, 1});
          expect(flow.model.isAllMedicationSaving, isFalse);
          expect(
            flow.model.prescriptionFlowState,
            PrescriptionFlowState.resultReady,
          );
          expect(flow.saveNames, [_first, _second]);
          expect(flow.model.savedMedicationInfoList, hasLength(2));
          expect(flow.model.todayMedicationScheduleList, hasLength(2));
          expect(flow.count('/list'), 2);
          expect(flow.count('/schedule/today'), 2);
          expect(flow.model.prescriptionChangeRadar, isNull);
          expect(await flow.model.requestMedicationSave(first, 0), isTrue);
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.saveNames, [_first, _second]);
          // 저장 뒤에도 성분 중복 확인은 다시 보내지 않는다.
          expect(flow.overlapRequests, hasLength(1));
          expect(flow.rows.first['dosage_per_time'], '0.5mg');
          expect(flow.rows.first['prescription_date'], '2026-11-16');
          expect(flow.rows.first['schedule_slot_keys'], ['morning', 'evening']);
          expect(flow.rows.last['schedule_slot_keys'], ['bedtime']);
          expect(flow.rows.map((row) => row['item_seq']), [
            _firstId,
            _secondId,
          ]);
        },
      );

      for (final failBoth in [false, true]) {
        test(
          'retry sends only pending rows after failure (all=$failBoth)',
          () async {
            final flow = _Flow();
            flow.show(source);
            flow.failedNames.add(_second);
            if (failBoth) flow.failedNames.add(_first);
            expect(
              await flow.model.requestAllAnalyzedMedicationSave(),
              isFalse,
            );
            expect(
              flow.model.completedMedicationSaveIndexes,
              failBoth ? isEmpty : {0},
            );
            expect(flow.rows, hasLength(failBoth ? 0 : 1));
            expect(flow.model.isMedicationSaving, isFalse);
            expect(flow.model.isAllMedicationSaving, isFalse);
            flow.failedNames.clear();
            expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
            expect(flow.model.completedMedicationSaveIndexes, {0, 1});
            expect(flow.rows, hasLength(2));
            expect(
              flow.saveNames,
              failBoth
                  ? [_first, _second, _first, _second]
                  : [_first, _second, _second],
            );
          },
        );
      }

      test(
        'lost save acknowledgement retries without duplicate persistence',
        () async {
          final flow = _Flow()..loseAcknowledgement = true;
          flow.show(source);
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
          expect(flow.model.completedMedicationSaveIndexes, {1});
          expect(flow.rows, hasLength(2));
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.saveNames, [_first, _second, _first]);
          expect(flow.rows, hasLength(2));
          expect(flow.model.completedMedicationSaveIndexes, {0, 1});
        },
      );

      test(
        'refresh failure does not make successful rows pending again',
        () async {
          final flow = _Flow()..failRefresh = true;
          flow.show(source);
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.model.completedMedicationSaveIndexes, {0, 1});
          expect(flow.model.hasSavedMedicationLoadError, isTrue);
          expect(flow.model.hasTodayScheduleLoadError, isTrue);
          flow.failRefresh = false;
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.saveNames, [_first, _second]);
          expect(flow.model.savedMedicationInfoList, hasLength(2));
          expect(flow.model.todayMedicationScheduleList, hasLength(2));
        },
      );

      test(
        'handoff snapshots caller-owned schedule slots as well as the list',
        () async {
          final flow = _Flow();
          final slots = ['morning', 'evening'];
          if (source == MedicationResultSource.manual) {
            final entries = [_manual(slots: slots)];
            expect(
              flow.model.showManualMedicationRegistrationResults(entries),
              isTrue,
            );
            entries.clear();
          } else {
            final requests = [_pill(slots: slots)];
            expect(
              flow.model.showPillMedicationRegistrationResults(requests),
              isTrue,
            );
            requests.clear();
          }
          slots
            ..clear()
            ..add('bedtime');
          expect(
            flow.model.analyzedMedicationList.single.schedule.scheduleSlotKeys,
            ['morning', 'evening'],
          );
          expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
          expect(flow.rows.single['schedule_slot_keys'], [
            'morning',
            'evening',
          ]);
          expect(flow.rows.single['item_seq'], _firstId);
        },
      );

      for (final ending in ['clear', 'dispose', 'account deletion']) {
        test(
          '$ending during lookup prevents every later save and refresh',
          () async {
            final flow = _Flow();
            flow.show(source, selectedManual: false);
            final lookupPath = source == MedicationResultSource.manual
                ? '/identify'
                : '/catalog/$_firstId';
            final gate = flow.pause(lookupPath);
            final saving = flow.model.requestAllAnalyzedMedicationSave();
            await gate.started.future;
            expect(flow.model.isAllMedicationSaving, isTrue);
            await flow.end(ending);
            final notificationCount = flow.notifications;
            final status = flow.model.statusMessage;
            gate.release();
            expect(await saving, isFalse);
            await pumpEventQueue();
            expect(flow.saveNames, isEmpty);
            expect(flow.count(lookupPath), 1);
            expect(flow.count('/list'), 0);
            expect(flow.count('/schedule/today'), 0);
            expect(flow.model.completedMedicationSaveIndexes, isEmpty);
            expect(flow.notifications, notificationCount);
            expect(flow.model.statusMessage, status);
            if (ending != 'dispose') {
              expect(
                flow.model.prescriptionFlowState,
                PrescriptionFlowState.idle,
              );
              expect(flow.model.analyzedMedicationList, isEmpty);
            }
          },
        );

        test(
          '$ending during save acknowledgement stops the rest of the batch',
          () async {
            final flow = _Flow();
            flow.show(source);
            final gate = flow.pause('/save');
            final saving = flow.model.requestAllAnalyzedMedicationSave();
            await gate.started.future;
            await flow.end(ending);
            if (ending == 'clear') {
              expect(flow.show(source), isTrue);
            }
            final notifications = flow.notifications;
            final status = flow.model.statusMessage;
            gate.release();
            expect(await saving, isFalse);
            await pumpEventQueue();
            expect(flow.saveNames, [_first]);
            expect(flow.count('/list'), 0);
            expect(flow.count('/schedule/today'), 0);
            expect(flow.model.completedMedicationSaveIndexes, isEmpty);
            expect(flow.notifications, notifications);
            expect(flow.model.statusMessage, status);
          },
        );
      }

      test(
        'cleared result cannot be saved by a stale single-save callback',
        () async {
          final flow = _Flow();
          flow.show(source);
          final oldResult = flow.model.analyzedMedicationList.first;
          flow.model.clearAnalysisResult();
          expect(await flow.model.requestMedicationSave(oldResult, 0), isFalse);
          expect(flow.requests, isEmpty);
          expect(flow.model.completedMedicationSaveIndexes, isEmpty);
        },
      );

      test('empty or conflicting handoffs cannot replace active results', () {
        final flow = _Flow();
        expect(flow.model.showManualMedicationRegistrationResults([]), isFalse);
        expect(flow.model.showPillMedicationRegistrationResults([]), isFalse);
        expect(flow.model.prescriptionFlowState, PrescriptionFlowState.idle);
        expect(flow.show(source), isTrue);
        expect(flow.show(source), isFalse);
        expect(flow.model.medicationResultSource, source);
        expect(flow.model.analyzedMedicationList, hasLength(2));
        flow.disposeModel();
        expect(flow.show(source), isFalse);
        expect(flow.requests, isEmpty);
      });
    });
  }

  test('manual chosen catalog identity is saved without name lookup', () async {
    final flow = _Flow();
    final selected = _catalog(_first, _firstId);
    expect(
      flow.model.showManualMedicationRegistrationResults([
        _manual(name: ' $_first ', catalog: selected),
      ]),
      isTrue,
    );
    final result = flow.model.analyzedMedicationList.single;
    expect(result.detail.itemSeq, _firstId);
    expect(result.detail.warning, 'warning for $_firstId');
    expect(await flow.model.requestMedicationSave(result, 0), isTrue);
    expect(flow.model.prescriptionStatusMessage, '복약 정보가 성공적으로 저장되었습니다.');
    expect(flow.count('/identify'), 0);
    final row = flow.rows.single;
    expect(row['item_seq'], _firstId);
    expect(row['item_name'], _first);
    expect(row['image_url'], _chosenImage);
    expect(row['efficacy'], 'efficacy for $_firstId');
    expect(row['warning_message'], 'warning for $_firstId');
    expect(row['use_method'], 'instructions for $_firstId');
  });

  test(
    'edited manual name does not display or save stale catalog identity',
    () async {
      final flow = _Flow()..lookupRows = [];
      flow.model.showManualMedicationRegistrationResults([
        _manual(name: 'Edited medication', catalog: _catalog(_first, _firstId)),
      ]);
      final result = flow.model.analyzedMedicationList.single;
      expect(result.detail.itemName, 'Edited medication');
      expect(result.detail.itemSeq, isEmpty);
      expect(result.detail.warning, isEmpty);
      expect(await flow.model.requestMedicationSave(result, 0), isTrue);
      expect(flow.count('/identify'), 1);
      expect(flow.rows.single['item_name'], 'Edited medication');
      expect(flow.rows.single['item_seq'], isEmpty);
      expect(flow.rows.single['warning_message'], isEmpty);
    },
  );

  test(
    'pill catalog lookup mismatch never replaces the chosen catalog product',
    () async {
      final flow = _Flow()
        ..lookupRows = [
          {
            'item_name': _first,
            'item_seq': '299999999',
            'efficacy': 'WRONG efficacy',
            'usage_method': 'WRONG instructions',
            'warning': 'WRONG warning',
            'image_url': 'https://nedrug.mfds.go.kr/wrong.jpg',
          },
        ];
      flow.model.showPillMedicationRegistrationResults([_pill()]);
      expect(flow.requests, isEmpty);
      final result = flow.model.analyzedMedicationList.single;
      expect(result.detail.itemSeq, _firstId);
      expect(result.detail.imageUrl, _chosenImage);
      expect(await flow.model.requestMedicationSave(result, 0), isTrue);
      expect(flow.count('/identify'), 0);
      expect(flow.count('/catalog/$_firstId'), 1);
      final row = flow.rows.single;
      expect(row['item_seq'], _firstId);
      expect(row['item_name'], _first);
      expect(row['image_url'], _chosenImage);
      expect(row['efficacy'], isEmpty);
      expect(row['use_method'], isEmpty);
      expect(row['warning_message'], isEmpty);
      expect(row['dosage_per_time'], '0.5mg');
      expect(row['schedule_slot_keys'], ['morning', 'evening']);
    },
  );

  group('manual result photo ownership', () {
    Future<File> photo(String name, {bool outsideCache = false}) async {
      final parent = outsideCache ? directory.path : '${directory.path}/cache';
      await Directory(parent).create(recursive: true);
      return File(
        '$parent/$name.png',
      ).writeAsBytes(image.encodePng(image.Image(width: 2, height: 2)));
    }

    test(
      'failed save keeps photo for retry; success stores it before cleanup',
      () async {
        final flow = _Flow();
        final picked = await photo('retry');
        flow.model.showManualMedicationRegistrationResults([
          _manual(localImagePath: picked.path),
        ]);
        expect(await picked.exists(), isTrue);
        expect(await flow.storedPhoto(), isEmpty);
        expect(flow.requests, isEmpty);
        flow.failedNames.add(_first);
        expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
        expect(await picked.exists(), isTrue);
        expect(await flow.storedPhoto(), isEmpty);
        expect(flow.model.completedMedicationSaveIndexes, isEmpty);
        flow.failedNames.clear();
        final gate = flow.pause('/save');
        final retry = flow.model.requestAllAnalyzedMedicationSave();
        await gate.started.future;
        expect(await picked.exists(), isTrue);
        gate.release();
        expect(await retry, isTrue);
        expect(flow.model.completedMedicationSaveIndexes, {0});
        expect(await picked.exists(), isFalse);
        final stored = await flow.storedPhoto();
        expect(stored, isNotEmpty);
        expect(image.decodeImage(await File(stored).readAsBytes()), isNotNull);
        expect(flow.rows.single.keys, isNot(contains('local_image_path')));
        expect(jsonEncode(flow.rows), isNot(contains(picked.path)));
        flow.model.clearAnalysisResult();
        await pumpEventQueue();
        expect(await File(stored).exists(), isTrue);
      },
    );

    test(
      'partial failure retains only the pending photo across a bulk retry',
      () async {
        final flow = _Flow()..failedNames.add(_second);
        final first = await photo('first');
        final second = await photo('second');
        flow.model.showManualMedicationRegistrationResults([
          _manual(localImagePath: first.path),
          _manual(name: _second, id: _secondId, localImagePath: second.path),
        ]);
        expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
        expect(flow.model.completedMedicationSaveIndexes, {0});
        expect(await first.exists(), isFalse);
        expect(await second.exists(), isTrue);
        final firstStored = await flow.storedPhoto();
        expect(firstStored, isNotEmpty);
        flow.failedNames.clear();
        expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
        expect(flow.saveNames, [_first, _second, _second]);
        expect(await second.exists(), isFalse);
        expect(await File(firstStored).exists(), isTrue);
        final secondStored = await flow.model.manualMedicationImageStore
            .findImagePath(patientHash: _patient, medicationId: 2);
        expect(secondStored, isNotEmpty);
        expect(await File(secondStored).exists(), isTrue);
        flow.model.clearAnalysisResult();
        await pumpEventQueue();
        expect(await File(firstStored).exists(), isTrue);
        expect(await File(secondStored).exists(), isTrue);
      },
    );

    for (final ending in ['clear', 'dispose', 'account deletion']) {
      test(
        '$ending deletes unsaved owned photos but keeps external originals',
        () async {
          final flow = _Flow();
          final picked = await photo('unsaved');
          final original = await photo('gallery', outsideCache: true);
          flow.model.showManualMedicationRegistrationResults([
            _manual(localImagePath: picked.path),
            _manual(name: _second, localImagePath: original.path),
          ]);
          expect(await picked.exists(), isTrue);
          await flow.end(ending);
          await _eventually(() async => !await picked.exists());
          expect(await original.exists(), isTrue);
          expect(flow.saveNames, isEmpty);
          expect(flow.count('/identify'), 0);
        },
      );
    }

    test(
      'exit during an in-flight failed save retains photo until request ends',
      () async {
        final flow = _Flow()..failedNames.add(_first);
        final picked = await photo('pending-failure');
        flow.model.showManualMedicationRegistrationResults([
          _manual(localImagePath: picked.path),
        ]);
        final gate = flow.pause('/save');
        final saving = flow.model.requestAllAnalyzedMedicationSave();
        await gate.started.future;
        flow.model.clearAnalysisResult();
        await pumpEventQueue();
        expect(await picked.exists(), isTrue);
        gate.release();
        expect(await saving, isFalse);
        await _eventually(() async => !await picked.exists());
        expect(await flow.storedPhoto(), isEmpty);
        expect(flow.count('/list'), 0);
        expect(flow.count('/schedule/today'), 0);
      },
    );

    test(
      'rejected handoff leaves incoming photo ownership with its caller',
      () async {
        final flow = _Flow();
        flow.show(MedicationResultSource.pillPhoto);
        final picked = await photo('rejected');
        expect(
          flow.model.showManualMedicationRegistrationResults([
            _manual(localImagePath: picked.path),
          ]),
          isFalse,
        );
        flow.model.clearAnalysisResult();
        await pumpEventQueue();
        expect(await picked.exists(), isTrue);
      },
    );
  });
}

MedicationDetail _catalog(String name, String id) => MedicationDetail(
  itemName: name,
  itemSeq: id,
  imageUrl: _chosenImage,
  efficacy: 'efficacy for $id',
  usageMethod: 'instructions for $id',
  warning: 'warning for $id',
);

ManualMedicationEntry _manual({
  String name = _first,
  String id = _firstId,
  List<String> slots = const ['morning', 'evening'],
  MedicationDetail? catalog,
  bool selected = true,
  String localImagePath = '',
}) => ManualMedicationEntry(
  medicationName: name,
  dosageAmount: '0.5',
  dosageUnit: 'mg',
  startDate: _start,
  endDate: _start.add(const Duration(days: 2)),
  scheduleSlotKeys: slots,
  catalogMedication: selected ? catalog ?? _catalog(name, id) : null,
  localImagePath: localImagePath,
);

IdentifiedPillSaveRequest _pill({
  String name = _first,
  String id = _firstId,
  List<String> slots = const ['morning', 'evening'],
}) => IdentifiedPillSaveRequest(
  candidate: PillIdentificationCandidate(
    itemSeq: id,
    itemName: name,
    imageUrl: _chosenImage,
  ),
  medicationSchedule: MedicationSchedule(
    medicationName: name,
    dosage: '0.5mg',
    intakeTime: '${slots.length}',
    medicationTime: 3,
    prescriptionDate: _start,
    scheduleSlotKeys: slots,
  ),
);

// Only HTTP and platform storage paths are replaced; the real save controls run.
class _Flow {
  late final MockClient client;
  late final MedBuddyViewModel model;
  final requests = <http.Request>[];
  // 결과 화면을 열 때 한 번 보내는 성분 중복 확인은 조회·저장 요청과 따로 센다.
  final overlapRequests = <http.Request>[];
  final rows = <Map<String, dynamic>>[];
  final saveNames = <String>[];
  final failedNames = <String>{};
  final gates = <String, _Gate>{};
  List<Map<String, dynamic>>? lookupRows;
  bool loseAcknowledgement = false;
  bool failRefresh = false;
  bool _disposed = false;
  int notifications = 0;

  _Flow() {
    client = MockClient(_respond);
    model = MedBuddyViewModel(
      patientHash: _patient,
      apiClient: client,
      notificationService: RecordingNotificationService(),
    );
    model.addListener(() => notifications++);
    addTearDown(() async {
      for (final gate in gates.values) {
        gate.release();
      }
      disposeModel();
      await pumpEventQueue();
      client.close();
    });
  }

  bool show(MedicationResultSource source, {bool selectedManual = true}) =>
      source == MedicationResultSource.manual
      ? model.showManualMedicationRegistrationResults([
          _manual(selected: selectedManual),
          _manual(
            name: _second,
            id: _secondId,
            slots: const ['bedtime'],
            selected: selectedManual,
          ),
        ])
      : model.showPillMedicationRegistrationResults([
          _pill(),
          _pill(name: _second, id: _secondId, slots: const ['bedtime']),
        ]);

  int count(String suffix) =>
      requests.where((request) => request.url.path.endsWith(suffix)).length;

  _Gate pause(String suffix) => gates[suffix] = _Gate();

  Future<void> end(String ending) async {
    switch (ending) {
      case 'clear':
        model.clearAnalysisResult();
      case 'dispose':
        disposeModel();
      case 'account deletion':
        await model.requestAccountDataDeletion();
      default:
        throw StateError('Unknown ending: $ending');
    }
  }

  void disposeModel() {
    if (_disposed) return;
    _disposed = true;
    model.dispose();
  }

  Future<String> storedPhoto() => model.manualMedicationImageStore
      .findImagePath(patientHash: _patient, medicationId: 1);

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/ingredient-overlap')) {
      overlapRequests.add(request);
      return _json({'success': true, 'items': []});
    }
    requests.add(request);
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/save')) {
      expect(body['patient_hash'], _patient);
      saveNames.add(body['item_name'] as String);
    }
    for (final entry in gates.entries) {
      if (path.endsWith(entry.key)) {
        entry.value.markStarted();
        await entry.value.released.future;
      }
    }
    if (path.contains('/catalog/')) {
      final id = request.url.pathSegments.last;
      expect(request.method, 'GET');
      return _json({
        'success': true,
        'data': lookupRows != null
            ? lookupRows!.firstOrNull
            : {
                'item_name': id == _firstId ? _first : _second,
                'item_seq': id,
                'efficacy': 'looked up efficacy',
                'usage_method': 'looked up instructions',
                'warning': 'looked up warning',
              },
      });
    }
    if (path.endsWith('/identify')) {
      final name = body['extracted_text'];
      return _json({
        'success': true,
        'data':
            lookupRows ??
            [
              {
                'item_name': name,
                'item_seq': name == _first ? _firstId : _secondId,
                'efficacy': 'looked up efficacy',
                'usage_method': 'looked up instructions',
                'warning': 'looked up warning',
              },
            ],
      });
    }
    if (path.endsWith('/save')) {
      final name = body['item_name'];
      if (failedNames.contains(name)) {
        return _json({'detail': 'temporary save failure'}, status: 503);
      }
      final existing = rows
          .where((row) => row['item_name'] == name)
          .firstOrNull;
      if (existing != null) {
        return _json({
          'success': false,
          'duplicate': true,
          'id': existing['id'],
        });
      }
      final row = {...body, 'id': rows.length + 1};
      rows.add(row);
      if (loseAcknowledgement) {
        loseAcknowledgement = false;
        throw const SocketException('Simulated lost save acknowledgement');
      }
      // The server's own message is English whatever the app language.
      return _json({
        'success': true,
        'id': row['id'],
        'message': "'$name' saved to pillbox.",
      });
    }
    if (path.endsWith('/list') || path.endsWith('/schedule/today')) {
      expect(request.url.queryParameters['patient_hash'], _patient);
      return _json({'success': !failRefresh, 'data': failRefresh ? [] : rows});
    }
    if (path.endsWith('/account-data') && request.method == 'DELETE') {
      rows.clear();
      return _json({'success': true});
    }
    throw StateError('Unexpected request: ${request.method} $path');
  }
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Gate {
  final started = Completer<void>();
  final released = Completer<void>();

  void markStarted() {
    if (!started.isCompleted) started.complete();
  }

  void release() {
    if (!released.isCompleted) released.complete();
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async => '$root/cache';

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
}

Future<void> _eventually(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Asynchronous photo cleanup did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
