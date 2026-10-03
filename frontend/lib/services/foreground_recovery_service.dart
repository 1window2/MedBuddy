import 'dart:async';

/// Retries a read/reconciliation operation while its owning screen is active.
/// Never replays a medication mutation or launches concurrent requests.
class ForegroundRecoveryService {
  ForegroundRecoveryService(this.recover);

  final Future<bool> Function() recover;
  static const _delays = [5, 15, 30, 60, 120];
  Timer? _timer;
  bool _active = false;
  bool _running = false;
  bool _disposed = false;
  bool _resumePending = false;
  int _failures = 0;

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

  void stop() {
    _active = false;
    _resumePending = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _disposed = true;
  }

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
