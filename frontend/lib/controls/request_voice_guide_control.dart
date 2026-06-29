// 파일명: request_voice_guide_control.dart
// 역할: 음성 안내 기능을 위한 컨트롤 placeholder를 정의한다.

// 클래스명: RequestVoiceGuide
// 역할: 향후 복약 안내 문구를 음성으로 읽어주는 기능의 진입점을 보관한다.
// 주요 책임:
// - 후속 음성 안내 기능에서 사용할 컨트롤 이름과 메서드 계약을 유지한다.
// - 아직 구현되지 않은 기능 호출을 명확히 차단한다.
class RequestVoiceGuide {
  // 함수명: requestVoiceGuide
  // 함수역할:
  // - 음성 안내 기능이 아직 구현되지 않았음을 명시한다.
  // 반환값:
  // - 현재는 항상 UnsupportedError 발생
  void requestVoiceGuide() {
    throw UnsupportedError('음성 안내 기능은 아직 구현되지 않았습니다.');
  }
}
