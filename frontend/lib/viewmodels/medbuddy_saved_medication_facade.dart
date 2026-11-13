part of 'medbuddy_view_model.dart';

// File Name: medbuddy_saved_medication_facade.dart
// Role: Compatibility-only forwarding; saved-medication state belongs to its feature.

// Class Name: MedBuddySavedMedicationFacade
// Role: Keep existing callers compatible with the saved-medication feature owner.
// Responsibilities: Forward public saved-medication operations without duplicating feature state.
// Attributes: No extension-owned fields; _savedMedications belongs to the host MedBuddyViewModel.
extension MedBuddySavedMedicationFacade on MedBuddyViewModel {
  // 함수이름: changeMedicationRegimen
  // 함수역할: 저장 약의 적용일 기반 변경을 기존 일정·알림 갱신 경로와 함께 실행하도록 위임한다.
  // 매개변수: medicationId: 변경할 저장 약 ID; change: 재시도 시 유지할 변경 요청.
  // 반환값: 변경과 후속 갱신 결과 Future.
  Future<MedicationRegimenResult> changeMedicationRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) => _savedMedications.changeMedicationRegimen(medicationId, change);

  // Function Name: hasSavedMedicationLoadError
  // Description: Lets screens tell a failed saved-medication list request apart from an empty list.
  // Parameters: None. Returns: Whether the newest finished list request failed.
  bool get hasSavedMedicationLoadError => _savedMedications.hasLoadError;

  // Function Name: saveManualMedication
  // Description: Delegates user-entered medication registration.
  // Parameters: entry: User-confirmed medication data; refreshAfterSave: refresh policy.
  // Returns: Save outcome.
  Future<MedicationSaveResult> saveManualMedication(
    ManualMedicationEntry entry, {
    bool refreshAfterSave = true,
  }) => _savedMedications.saveManualMedication(
    entry,
    refreshAfterSave: refreshAfterSave,
  );

  // Function Name: refreshAfterMedicationSaves
  // Description: Delegates the single refresh after several saves made without one.
  // Parameters: None. Returns: Completes when the list, schedule and reminders are refreshed.
  Future<void> refreshAfterMedicationSaves() =>
      _savedMedications.refreshAfterMedicationSaves();

  // Function Name: saveIdentifiedPill
  // Description: Delegate a confirmed identification candidate and schedule to the save owner.
  // Parameters: candidate (PillIdentificationCandidate): confirmed medication; medicationSchedule (MedicationSchedule): reviewed doses; refreshAfterSave (bool): refresh after persistence.
  // Returns: Future<MedicationSaveResult>: save outcome.
  Future<MedicationSaveResult> saveIdentifiedPill(
    PillIdentificationCandidate candidate,
    MedicationSchedule medicationSchedule, {
    bool refreshAfterSave = true,
  }) => _savedMedications.saveIdentifiedPill(
    candidate,
    medicationSchedule,
    refreshAfterSave: refreshAfterSave,
  );

  // Function Name: saveIdentifiedPills
  // Description: Delegates ordered batch registration.
  // Parameters: requests: Confirmed candidates. Returns: Per-item results.
  Future<List<MedicationSaveResult>> saveIdentifiedPills(
    List<IdentifiedPillSaveRequest> requests,
  ) => _savedMedications.saveIdentifiedPills(requests);

  // Function Name: fetchSavedMedicationInfo
  // Description: Refreshes the feature-owned list.
  // Parameters: None. Returns: Request completion.
  Future<void> fetchSavedMedicationInfo() =>
      _savedMedications.fetchSavedMedicationInfo();

  // Function Name: requestDeleteSavedMedication
  // Description: Delegates single-item deletion.
  // Parameters: savedMedicationId: Selected medication. Returns: Deletion success.
  Future<bool> requestDeleteSavedMedication(int savedMedicationId) =>
      _savedMedications.requestDeleteSavedMedication(savedMedicationId);

  // Function Name: requestDeleteSavedMedications
  // Description: Delegates selected-item deletion.
  // Parameters: savedMedicationIds: Selected medications. Returns: Batch outcome.
  Future<SavedMedicationBatchDeleteResult> requestDeleteSavedMedications(
    Iterable<int> savedMedicationIds,
  ) => _savedMedications.requestDeleteSavedMedications(savedMedicationIds);
}
