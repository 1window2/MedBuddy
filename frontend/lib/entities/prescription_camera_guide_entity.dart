// 파일명: prescription_camera_guide_entity.dart
// 역할: 처방전 촬영 가이드의 거리 판정 결과를 표현한다.

// 클래스명: PrescriptionCameraGuideStatus
// 역할: 문서 미탐색·너무 멂·정렬됨·너무 가까움 촬영 상태를 구분한다.
// 주요 책임:
// - 카메라 안내 화면이 문서 점유율에 맞는 거리 조정 안내를 선택하게 한다.
enum PrescriptionCameraGuideStatus { searching, tooFar, aligned, tooClose }

// 클래스명: PrescriptionCameraGuideResult
// 역할: 처방전이 화면에서 차지하는 비율과 거리 판정 상태를 함께 보관한다.
// 주요 책임:
// - 촬영 화면이 표시할 거리 안내 상태를 전달한다.
// - 문서 후보의 화면 점유율을 분석 결과로 보존한다.
// 속성:
// - status (PrescriptionCameraGuideStatus): 현재 처방전 거리 및 정렬 상태
// - documentCoverage (double): 문서 후보가 전체 프레임에서 차지하는 비율
class PrescriptionCameraGuideResult {
  final PrescriptionCameraGuideStatus status;
  final double documentCoverage;

  // 함수이름: PrescriptionCameraGuideResult
  // 함수역할: 문서 후보의 화면 점유율과 거리·정렬 판정 상태를 하나의 프레임 분석 결과로 묶는다.
  // 매개변수:
  // - status (PrescriptionCameraGuideStatus): 사진 속 처방전의 거리·검출 판정 상태
  // - documentCoverage (double): 프레임에서 문서 후보가 차지하는 비율
  // 반환값:
  // - PrescriptionCameraGuideResult: 초기화된 인스턴스.
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
