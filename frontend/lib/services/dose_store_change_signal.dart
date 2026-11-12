// File Name: dose_store_change_signal.dart
// Role: Tells the foreground app that another Flutter engine in the same process changed the shared dose store.

import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

// Class Name: DoseStoreChangeSignal
// Role: Process-wide notice from a background engine (dose upload job, reminder refresh) to the foreground dose sync.
// Responsibilities: Keep one listener registration under a fixed name, send it a notice from other engines, and skip the listener's own writes.
// Attributes: register/lookup/remove - named-port registry functions, defaulting to IsolateNameServer; _port - this instance's listener.
class DoseStoreChangeSignal {
  static const _portName = 'medbuddy_dose_store_changed';

  final bool Function(SendPort port, String name) register;
  final SendPort? Function(String name) lookup;
  final bool Function(String name) remove;
  ReceivePort? _port;

  // Function Name: DoseStoreChangeSignal
  // Description: Configures the registry without listening.
  // Parameters: register/lookup/remove - named-port registry functions, defaulting to IsolateNameServer.
  // Returns: A signal that only sends until listen is called.
  DoseStoreChangeSignal({
    this.register = IsolateNameServer.registerPortWithName,
    this.lookup = IsolateNameServer.lookupPortByName,
    this.remove = IsolateNameServer.removePortNameMapping,
  });

  // Function Name: listen
  // Description: Takes over the name and calls onChanged for every notice. A name left by an ended engine cannot
  //   receive anything, and only the signed-in foreground session listens, so the newest listener replaces it.
  // Parameters: onChanged (void Function()) - called in this isolate for each notice.
  // Returns: None; an earlier listener of this instance is closed first.
  void listen(void Function() onChanged) {
    close();
    final port = ReceivePort();
    remove(_portName);
    register(port.sendPort, _portName);
    port.listen((_) => onChanged());
    _port = port;
  }

  // Function Name: notify
  // Description: Tells the listener that the store changed, unless the listener is this instance (it already knows).
  // Parameters: None.
  // Returns: None; without a listener nothing is sent.
  void notify() {
    final target = lookup(_portName);
    if (target == null || target == _port?.sendPort) return;
    target.send(null);
  }

  // Function Name: close
  // Description: Stops listening and removes the name while it is still this instance's registration.
  // Parameters: None.
  // Returns: None.
  void close() {
    final port = _port;
    if (port == null) return;
    _port = null;
    if (lookup(_portName) == port.sendPort) remove(_portName);
    port.close();
  }
}
