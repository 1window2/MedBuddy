// File Name: prescription_flow_entity.dart
// Role: Defines prescription recognition, preview, analysis, and progress states.

// Class Name: PrescriptionFlowState
// Role: Identifies prescription workflow screens and outcomes.
// Responsibilities: Coordinate recognition, preview, analysis, candidate review, failure and result transitions.
// Attributes: Enum values describe workflow stages rather than fractional processing progress.
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
// 역할: 처방전 인식과 약 정보 분석의 진행 단계를 구분한다.
// 주요 책임: 분석 작업 상태를 화면 진행 표시에 연결한다.
// 속성: prescriptionRecognition/medicationAnalysis: 처방전 인식·약 정보 분석 단계.
enum AnalysisProgressStep { prescriptionRecognition, medicationAnalysis }

// 클래스명: MedicationLookupStatus
// 역할: 처방전 약품별 조회 결과와 대기 상태를 구분한다.
// 주요 책임: 검색 결과 없음과 요청 실패를 다르게 표시하고 후보 확인 여부를 유지한다.
// 속성: verified: 확정; candidates: 후보 검토; notFound: 결과 없음; failed: 요청 실패; pending: 대기.
enum MedicationLookupStatus { verified, candidates, notFound, failed, pending }

// 클래스명: PrescriptionRecognitionStage
// 역할: 처방전 인식 처리의 실제 단계 경계를 나타낸다.
// 주요 책임: 문자 인식, 약품 구조화, 완료 상태로 단계별 진행 표시를 제공한다.
// 속성: recognizingText/structuringMedication/completed: 순서가 있는 처리 단계.
enum PrescriptionRecognitionStage {
  recognizingText,
  structuringMedication,
  completed;

  // 함수이름: progress
  // 함수역할: 단계 인덱스를 전체 단계 구간으로 나누어 진행 표시 값을 계산한다.
  // 매개변수: 없음.
  // 반환값: 현재 단계의 0, 0.5 또는 1; 엔진 내부의 실제 완료율은 아니다.
  double get progress => index / (values.length - 1);
}
