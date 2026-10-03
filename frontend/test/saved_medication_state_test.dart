// File Name: saved_medication_state_test.dart
// Role: Guards isolated saved-medication state against stale reads and disposal.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
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

// Class Name: _Model
// Role: Avoids unrelated networking during deletion refresh.
class _Model extends MedBuddyViewModel {
  // Function Name: _Model
  // Description: Injects controlled reads. Parameters: control. Returns: Test facade.
  _Model(_PendingSaved control) : super(checkSavedMedication: control);
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
}
