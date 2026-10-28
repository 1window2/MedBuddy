// File Name: prescription_flow_entity.dart
// Role: Defines prescription recognition, preview, analysis, and progress states.

// 클래스명: PrescriptionFlowState
// 역할: 처방전 입력부터 미리보기·약 분석·완료·오류까지의 화면 흐름 상태를 구분한다.
// 주요 책임:
// - ViewModel과 화면이 같은 상태값으로 작업 진행 및 화면 전환을 판단하게 한다.
// 비고:
// - 파일명: prescription_flow_entity.dart
enum PrescriptionFlowState {
  idle,
  recognizingPrescription,
  previewReady,
  analyzingMedication,
  medicationReviewRequired,
  analysisSucceeded,
  analysisFailed,
  resultReady,
}

// 클래스명: AnalysisProgressStep
// 역할: 약 분석 진행 표시에서 사용할 단계 값을 구분한다.
// 주요 책임:
// - 분석 작업의 현재 단계를 화면의 진행 표시와 연결한다.
enum AnalysisProgressStep { prescriptionRecognition, medicationAnalysis }

// 약별 조회 결과를 보관해 검색 결과 없음과 요청 실패를 구분한다.
enum MedicationLookupStatus { verified, candidates, notFound, failed, pending }

// 엔진 내부의 추정 백분율이 아니라 실제 완료된 인식 처리 단계이다.
enum PrescriptionRecognitionStage {
  recognizingText,
  structuringMedication,
  validatingResult,
  completed;

  double get progress => index / (values.length - 1);
}
