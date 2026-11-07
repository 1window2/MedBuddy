// File Name: foreground_recovery_service.dart
// Role: Retries read-only reconciliation while its owning screen remains active.
import 'dart:async';

// Class Name: ForegroundRecoveryService
// Role: Runs a single foreground recovery loop with bounded backoff.
// Responsibilities: Stop after success, pause on inactivity, and resume without overlapping requests.
// Attributes: recover (Future<bool> Function()) - safe read/reconciliation; _timer/_failures - retry state;
// - _active/_running/_disposed/_resumePending (bool): Lifetime and in-flight restart guards.
/// Retries a read/reconciliation operation while its owning screen is active.
/// Never replays a medication mutation or launches concurrent requests.
class ForegroundRecoveryService {
  // Function Name: ForegroundRecoveryService
  // Description: Retains a recovery operation without starting it.
  // Parameters: recover (Future<bool> Function()) - returns true when reconciled; false/errors request another retry.
  // Returns: An idle service; the callback must not replay medication mutations.
  ForegroundRecoveryService(this.recover);

  final Future<bool> Function() recover;
  static const _delays = [5, 15, 30, 60, 120];
  Timer? _timer;
  bool _active = false;
  bool _running = false;
  bool _disposed = false;
  bool _resumePending = false;
  int _failures = 0;

  // Function Name: start
  // Description: Starts immediately or requests a fresh run after an in-flight operation; repeated active/disposed starts are ignored.
  // Parameters: None.
  // Returns: Nothing; recovery runs asynchronously with backoff reset.
  void start() {
    if (_disposed || _active) return;
    _active = true;
    _failures = 0;
    if (_running) {
      _resumePending = true;
    } else {
      unawaited(_run());
    }
  }

  // Function Name: stop
  // Description: Cancels the next retry and disables further scheduling without cancelling an in-flight callback.
  // Parameters: None.
  // Returns: Nothing; start may reactivate the service later.
  void stop() {
    _active = false;
    _resumePending = false;
    _timer?.cancel();
    _timer = null;
  }

  // Function Name: dispose
  // Description: Stops retry scheduling permanently while allowing an already-running callback to settle.
  // Parameters: None.
  // Returns: Nothing; subsequent start calls have no effect.
  void dispose() {
    stop();
    _disposed = true;
  }

  // Function Name: _run
  // Description: Executes one non-overlapping recovery attempt, then stops on success or retries at 5/15/30/60/120 seconds.
  // Parameters: None.
  // Returns: Completion after choosing the next action; callback errors count as failures without escaping to the UI.
  Future<void> _run() async {
    if (!_active || _disposed || _running) return;
    _running = true;
    var succeeded = false;
    try {
      succeeded = await recover();
    } catch (_) {
      // The owning UI retains its normal error state; this is retry scheduling.
    } finally {
      _running = false;
    }
    if (!_active || _disposed) return;
    if (_resumePending) {
      _resumePending = false;
      unawaited(_run());
    } else if (!succeeded) {
      final index = _failures.clamp(0, _delays.length - 1);
      _failures++;
      _timer = Timer(Duration(seconds: _delays[index]), () {
        _timer = null;
        unawaited(_run());
      });
    } else {
      _active = false;
    }
  }
}
