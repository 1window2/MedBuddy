// 파일명: prescription_camera_guide_entity.dart
// 역할: 처방전 촬영 가이드의 거리 판정 결과를 표현한다.

// 열거형명: PrescriptionCameraGuideStatus
// 역할: 카메라에서 추정한 처방전의 거리와 정렬 상태를 구분한다.
enum PrescriptionCameraGuideStatus { searching, tooFar, aligned, tooClose }

// 클래스명: PrescriptionCameraGuideResult
// 역할: 처방전이 화면에서 차지하는 비율과 거리 판정 상태를 함께 보관한다.
// 주요 책임:
// - 촬영 화면이 표시할 거리 안내 상태를 전달한다.
// - 문서 후보의 화면 점유율을 분석 결과로 보존한다.
// 속성:
// - status: 현재 처방전 거리 및 정렬 상태
// - documentCoverage: 문서 후보가 전체 프레임에서 차지하는 비율
class PrescriptionCameraGuideResult {
  final PrescriptionCameraGuideStatus status;
  final double documentCoverage;

  const PrescriptionCameraGuideResult({
    required this.status,
    required this.documentCoverage,
  });

  static const PrescriptionCameraGuideResult searching =
      PrescriptionCameraGuideResult(
        status: PrescriptionCameraGuideStatus.searching,
        documentCoverage: 0,
      );
}
