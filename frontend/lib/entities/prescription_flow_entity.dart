// File Name: prescription_flow_entity.dart
// Role: State values for the prescription analysis flow.

enum PrescriptionFlowState {
  idle,
  recognizingPrescription,
  previewReady,
  analyzingMedication,
  analysisSucceeded,
  analysisFailed,
  resultReady,
}

enum AnalysisProgressStep {
  prescriptionRecognition,
  medicationAnalysis,
  scheduleGeneration,
}
