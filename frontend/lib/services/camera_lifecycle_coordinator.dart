// File Name: camera_lifecycle_coordinator.dart
// Role: Serializes asynchronous camera lifecycle transitions.

// Function Name: CameraLifecycleTransition
// Description: Defines one asynchronous camera acquisition or release operation whose completion advances the serialized lifecycle queue.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef CameraLifecycleTransition = Future<void> Function();

// 클래스명: CameraLifecycleCoordinator
// 역할: 카메라 초기화·해제 전환을 순서대로 실행한다.
// 주요 책임: 앞선 실패를 호출자에게 전달하면서도 다음 전환이 계속 실행되도록 대기열을 유지한다.
// 속성: _tail (Future<void>): 성공·실패를 정리한 마지막 전환 완료 상태.
class CameraLifecycleCoordinator {
  Future<void> _tail = Future<void>.value();

  // 함수이름: schedule
  // 함수역할: 이전 전환이 끝난 뒤 새 전환을 실행하며 실패가 후속 전환을 막지 않도록 대기열 오류를 흡수한다.
  // 매개변수: transition (CameraLifecycleTransition): 순차 실행할 비동기 전환.
  // 반환값: Future<void>: 이번 전환 결과; 이번 오류는 호출자에게 그대로 전파된다.
  Future<void> schedule(CameraLifecycleTransition transition) {
    final result = _tail.then(/* Function Name: then callback
     * Description: Starts the queued camera transition after the preceding transition has settled.
     * Parameters:
     * - _ (void): Unused event value supplied by the enclosing callback contract.
     * Returns:
     * - The queued transition's result or completion future.
     */(_) => transition());
    _tail = result.then<void>(/* Function Name: then callback
     * Description: Marks a successful camera transition as a settled queue entry.
     * Parameters:
     * - _ (void): Unused event value supplied by the enclosing callback contract.
     * Returns:
     * - No return value.
     */(_) {}, onError: /* Function Name: onError callback
     * Description: Absorbs the queue-tail error so a failed transition does not block later transitions.
     * Parameters:
     * - _ (Object): Unused event value supplied by the enclosing callback contract.
     * - _ (StackTrace): Unused event value supplied by the enclosing callback contract.
     * Returns:
     * - No return value.
     */(Object _, StackTrace _) {});
    return result;
  }
}
