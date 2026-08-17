// File Name: camera_lifecycle_coordinator.dart
// Role: Serializes asynchronous camera lifecycle transitions.

typedef CameraLifecycleTransition = Future<void> Function();

// Class Name: CameraLifecycleCoordinator
// Role: Prevents camera open and release operations from overlapping.
// Responsibilities:
// - Runs camera lifecycle transitions in the order they were requested.
// - Keeps later transitions runnable when an earlier transition fails.
class CameraLifecycleCoordinator {
  Future<void> _tail = Future<void>.value();

  // Function Name: schedule
  // Description:
  // - Appends a camera lifecycle transition to the current serial queue.
  // - Returns the transition's own result while consuming its error on the queue tail.
  // Parameters:
  // - transition: Asynchronous camera open or release operation to run.
  // Returns:
  // - Completes with the scheduled transition or its original error.
  Future<void> schedule(CameraLifecycleTransition transition) {
    final result = _tail.then((_) => transition());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
