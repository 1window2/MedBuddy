part of 'medbuddy_view_model.dart';

// File Name: medbuddy_saved_medication_facade.dart
// Role: Compatibility-only forwarding; saved-medication state belongs to its feature.

// Class Name: MedBuddySavedMedicationFacade
// Role: Keeps existing screen and prescription call sites stable.
// Responsibilities: Forward operations without accessing feature-private state.
extension MedBuddySavedMedicationFacade on MedBuddyViewModel {
  // Function Name: saveMedicationInfo
  // Description: Delegates a medication and optional schedule to the feature.
  // Parameters: Medication, schedule, local image and refresh policy.
  // Returns: Save outcome.
  Future<MedicationSaveResult> saveMedicationInfo(
    MedicationDetail medicationInfo, {
    MedicationSchedule? medicationSchedule,
    String localImagePath = '',
    bool refreshAfterSave = true,
  }) => _savedMedications.saveMedicationInfo(
    medicationInfo,
    medicationSchedule: medicationSchedule,
    localImagePath: localImagePath,
    refreshAfterSave: refreshAfterSave,
  );

  // Function Name: saveManualMedication
  // Description: Delegates user-entered medication registration.
  // Parameters: entry: User-confirmed medication data. Returns: Save outcome.
  Future<MedicationSaveResult> saveManualMedication(
    ManualMedicationEntry entry,
  ) => _savedMedications.saveManualMedication(entry);

  // Function Name: saveIdentifiedPill
  // Description: Delegates a confirmed identification candidate and schedule.
  // Parameters: Candidate, schedule and refresh policy. Returns: Save outcome.
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
