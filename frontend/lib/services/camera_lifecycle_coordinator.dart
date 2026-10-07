// File Name: camera_lifecycle_coordinator.dart
// Role: Serializes asynchronous camera lifecycle transitions.

// Function Name: CameraLifecycleTransition
// Description: Defines one asynchronous camera acquisition or release operation whose completion advances the serialized lifecycle queue.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef CameraLifecycleTransition = Future<void> Function();

// Class Name: CameraLifecycleCoordinator
// Role: Prevents camera open and release operations from overlapping.
// Responsibilities:
// - Runs camera lifecycle transitions in the order they were requested.
// - Keeps later transitions runnable when an earlier transition fails.
class CameraLifecycleCoordinator {
  Future<void> _tail = Future<void>.value();

  // Function Name: schedule
  // Description: Appends a camera lifecycle transition to the current serial queue. Returns the transition's own result while consuming its error on the queue tail.
  // Parameters:
  // - transition (CameraLifecycleTransition): Asynchronous camera open or release operation to run.
  // Returns:
  // - Completes with the scheduled transition or its original error.
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
