// 파일명: check_result_control.dart
// 역할: 분석 결과 조회 기능을 위한 컨트롤 placeholder를 정의한다.

// 클래스명: CheckResult
// 역할: 향후 분석 결과를 별도 control에서 조회할 경우 사용할 진입점을 보관한다.
// 주요 책임:
// - 현재 ViewModel 중심으로 처리 중인 분석 결과 흐름과의 확장 지점을 유지한다.
// - 아직 분리 구현되지 않은 기능 호출을 명확히 차단한다.
class CheckResult {
  // 함수명: requestAnalysisResult
  // 함수역할:
  // - 분석 결과 조회 전용 control 기능이 아직 구현되지 않았음을 명시한다.
  // 반환값:
  // - 현재는 항상 UnsupportedError 발생
  void requestAnalysisResult() {
    throw UnsupportedError('분석 결과 조회 기능은 아직 별도 control로 구현되지 않았습니다.');
  }
}
