// File Name: saved_medication_batch_delete_result.dart
// Role: Immutable saved-medication deletion outcome shared by facade and feature.
// Class Name: SavedMedicationBatchDeleteResult
// Role: Summarizes successful and failed saved-medication deletions.
// Responsibilities:
// - Distinguish an empty selection, full success, and partial failure for the list UI.
// Attributes:
// - successCount (int): Number of successfully saved or deleted items.
// - failureCount (int): Number of failed items.
class SavedMedicationBatchDeleteResult {
  final int successCount;
  final int failureCount;

  // Function Name: SavedMedicationBatchDeleteResult
  // Description: Captures successful and failed deletion counts for an explicitly selected medication batch.
  // Parameters:
  // - successCount (int): Number of successfully saved or deleted items.
  // - failureCount (int): Number of failed items.
  // Returns:
  // - SavedMedicationBatchDeleteResult: the initialized instance.
  const SavedMedicationBatchDeleteResult({
    required this.successCount,
    required this.failureCount,
  });

  // Function Name: totalCount
  // Description: Computes the number of attempted medication deletions from success and failure counts.
  // Parameters:
  // - None.
  // Returns:
  // - int: Computes the number of attempted medication deletions from success and failure counts.
  int get totalCount => successCount + failureCount;
  // Function Name: allSucceeded
  // Description: Reports full success only when at least one medication was selected and no deletion failed.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Reports full success only when at least one medication was selected and no deletion failed.
  bool get allSucceeded => totalCount > 0 && failureCount == 0;
  // Function Name: hasFailures
  // Description: Reports whether any selected medication failed to delete.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether any selected medication failed to delete.
  bool get hasFailures => failureCount > 0;
}
