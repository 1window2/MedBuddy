// File Name: saved_medication_state_test.dart
// Role: Guards isolated saved-medication state against stale reads, disposal, failed reads shown as empty and photo flicker.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/services/manual_medication_image_store.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

// Class Name: _PendingSaved
// Role: Deterministic list and deletion boundary.
// Responsibilities: Hold list responses until a test completes them.
class _PendingSaved extends CheckSavedMedication {
  final requests = <Completer<List<MedicationDetail>>>[];
  // Function Name: requestSavedMedicationInfo
  // Description: Enqueues a pending read. Parameters: None. Returns: Response future.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() {
    final request = Completer<List<MedicationDetail>>();
    requests.add(request);
    return request.future;
  }

  // Function Name: requestDelete
  // Description: Confirms deletion. Parameters: id: Selected ID. Returns: Success.
  @override
  Future<bool> requestDelete(int id) async => true;
}

// Class Name: _GatedImageStore
// Role: Device photo store whose lookups finish only when a test opens the gate.
// Responsibilities: Report scripted photo paths late, so the list state between a read and the photo lookup is observable.
// Attributes: paths maps saved IDs to stored photo paths; gate holds lookups until completed.
class _GatedImageStore extends ManualMedicationImageStore {
  final paths = <int, String>{};
  Completer<void> gate = Completer<void>();
  // Function Name: findImagePath
  // Description: Waits for the gate, then reports the scripted path. Parameters: patientHash, medicationId. Returns: Path or empty text.
  @override
  Future<String> findImagePath({
    required String patientHash,
    required int medicationId,
  }) async {
    await gate.future;
    return paths[medicationId] ?? '';
  }

  // Function Name: removeOrphanImages
  // Description: Skips device cleanup. Parameters: patientHash, activeMedicationIds. Returns: Completion.
  @override
  Future<void> removeOrphanImages({
    required String patientHash,
    required Set<int> activeMedicationIds,
  }) async {}
}

// Class Name: _Model
// Role: Avoids unrelated networking during deletion refresh.
class _Model extends MedBuddyViewModel {
  // Function Name: _Model
  // Description: Injects controlled reads and an optional photo store. Parameters: control, store. Returns: Test facade.
  _Model(_PendingSaved control, {ManualMedicationImageStore? store})
    : super(checkSavedMedication: control, manualMedicationImageStore: store);
  // Function Name: fetchTodayMedicationSchedule
  // Description: Skips unrelated networking. Parameters: None. Returns: Completion.
  @override
  Future<void> fetchTodayMedicationSchedule() async {}
}

// Function Name: main
// Description: Exercises list generation and lifetime boundaries.
// Parameters: None. Returns: None.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final medication = MedicationDetail(
    id: 7,
    itemName: 'Test',
    efficacy: '',
    usageMethod: '',
    warning: '',
  );
  // Function Name: newest read test
  // Description: An older success cannot replace newer data. Parameters: None. Returns: Completion.
  test('latest saved-medication list wins', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    addTearDown(model.dispose);
    final old = model.fetchSavedMedicationInfo();
    final latest = model.fetchSavedMedicationInfo();
    control.requests[1].complete([]);
    await latest;
    control.requests[0].complete([medication]);
    await old;
    expect(model.savedMedicationInfoList, isEmpty);
    expect(model.isSavedMedicationLoading, isFalse);
  });
  // Function Name: deletion race test
  // Description: A pending read cannot restore a confirmed deletion. Parameters: None. Returns: Completion.
  test('deletion invalidates earlier saved-medication reads', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    addTearDown(model.dispose);
    final old = model.fetchSavedMedicationInfo();
    expect(await model.requestDeleteSavedMedication(7), isTrue);
    control.requests.single.complete([medication]);
    await old;
    expect(model.savedMedicationInfoList, isEmpty);
  });
  // Function Name: disposal test
  // Description: Late reads cannot repopulate disposed state. Parameters: None. Returns: Completion.
  test('disposed saved-medication state ignores late reads', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    final old = model.fetchSavedMedicationInfo();
    model.dispose();
    control.requests.single.complete([medication]);
    await old;
    expect(model.savedMedicationInfoList, isEmpty);
  });
  // Function Name: failed read test
  // Description: A failed read is flagged instead of looking like an empty list, keeps the shown list, and the flag clears when a new read starts. Parameters: None. Returns: Completion.
  test('a failed saved-medication read is flagged and keeps the list', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    addTearDown(model.dispose);
    expect(model.hasSavedMedicationLoadError, isFalse);
    final first = model.fetchSavedMedicationInfo();
    control.requests[0].complete([medication]);
    await first;
    expect(model.hasSavedMedicationLoadError, isFalse);

    for (final failure in <Object>[
      StateError('저장된 복약 정보 조회 실패 (500): boom'),
      TimeoutException('no answer'),
    ]) {
      final failed = model.fetchSavedMedicationInfo();
      control.requests.last.completeError(failure);
      await failed;
      expect(model.hasSavedMedicationLoadError, isTrue);
      expect(model.isSavedMedicationLoading, isFalse);
      expect(model.savedMedicationInfoList.map((item) => item.id), [7]);
    }

    final retry = model.fetchSavedMedicationInfo();
    expect(model.hasSavedMedicationLoadError, isFalse);
    control.requests.last.complete([]);
    await retry;
    expect(model.hasSavedMedicationLoadError, isFalse);
    expect(model.savedMedicationInfoList, isEmpty);
  });
  // Function Name: first read failure test
  // Description: A failed first read leaves an empty list that is flagged as a failure. Parameters: None. Returns: Completion.
  test('a failed first read is not an empty saved-medication list', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    addTearDown(model.dispose);
    final first = model.fetchSavedMedicationInfo();
    control.requests.single.completeError(StateError('boom'));
    await first;
    expect(model.savedMedicationInfoList, isEmpty);
    expect(model.hasSavedMedicationLoadError, isTrue);
  });
  // Function Name: superseded failure test
  // Description: An older failure cannot flag a newer successful read. Parameters: None. Returns: Completion.
  test('a superseded failed read does not flag the newer list', () async {
    final control = _PendingSaved();
    final model = _Model(control);
    addTearDown(model.dispose);
    final old = model.fetchSavedMedicationInfo();
    final latest = model.fetchSavedMedicationInfo();
    control.requests[1].complete([medication]);
    await latest;
    control.requests[0].completeError(StateError('boom'));
    await old;
    expect(model.hasSavedMedicationLoadError, isFalse);
    expect(model.savedMedicationInfoList.map((item) => item.id), [7]);
  });
  // Function Name: photo path refresh test
  // Description: A refresh keeps known device photo paths attached in every published state, and a photo that left the device is cleared afterwards. Parameters: None. Returns: Completion.
  test('a refresh never publishes the list without known photo paths', () async {
    final control = _PendingSaved();
    final store = _GatedImageStore()..paths[7] = '/photos/7.jpg';
    final model = _Model(control, store: store);
    addTearDown(model.dispose);
    final first = model.fetchSavedMedicationInfo();
    control.requests[0].complete([medication]);
    await first;
    store.gate.complete();
    await pumpEventQueue();
    expect(model.savedMedicationInfoList.single.localImagePath, '/photos/7.jpg');

    final published = <String>[];
    // Function Name: saved-medication listener
    // Description: Records the photo path of every published list state. Parameters: None. Returns: None.
    void record() => published.addAll(
      model.savedMedicationInfoList.map((item) => item.localImagePath),
    );
    model.updatesFor(MedBuddyFeature.savedMedication).addListener(record);
    store.gate = Completer<void>();
    final refresh = model.fetchSavedMedicationInfo();
    control.requests[1].complete([medication]);
    await refresh;
    await pumpEventQueue();
    expect(model.savedMedicationInfoList.single.localImagePath, '/photos/7.jpg');
    store.gate.complete();
    await pumpEventQueue();
    expect(published, isNotEmpty);
    expect(published, everyElement('/photos/7.jpg'));

    store.paths.clear();
    final afterRemoval = model.fetchSavedMedicationInfo();
    control.requests[2].complete([medication]);
    await afterRemoval;
    await pumpEventQueue();
    expect(model.savedMedicationInfoList.single.localImagePath, isEmpty);
  });
}
