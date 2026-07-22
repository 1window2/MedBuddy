// 파일명: prescription_flow_entity.dart
// 역할: 처방전 인식과 약물 정보 분석 흐름에서 사용하는 상태값을 정의한다.

enum PrescriptionFlowState {
  idle,
  recognizingPrescription,
  previewReady,
  analyzingMedication,
  analysisSucceeded,
  analysisFailed,
  resultReady,
}

enum AnalysisProgressStep { prescriptionRecognition, medicationAnalysis }
