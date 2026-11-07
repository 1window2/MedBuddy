// File Name: naver_map_sdk_gate.dart
// Role: Builds a Naver map only after the shared SDK initialization has finished.

import 'package:flutter/widgets.dart';

import '../services/naver_map_config.dart';

// Class Name: NaverMapSdkGate
// Role: Holds the map's place until the SDK started after the first frame is ready.
// Responsibilities:
// - Build the map at once when the SDK is already initialized.
// - Otherwise join the shared initialization and show the placeholder meanwhile.
// Attributes:
// - builder (WidgetBuilder): Builds the NaverMap widget.
// - placeholder (Widget): Shown while the SDK is still initializing.
class NaverMapSdkGate extends StatefulWidget {
  final WidgetBuilder builder;
  final Widget placeholder;

  // Function Name: NaverMapSdkGate
  // Description: Stores the map builder and the placeholder used during initialization.
  // Parameters:
  // - key (Key?): Flutter widget identity key.
  // - builder (WidgetBuilder): Builds the NaverMap widget.
  // - placeholder (Widget): Shown while the SDK is still initializing.
  // Returns:
  // - NaverMapSdkGate: the initialized instance.
  const NaverMapSdkGate({
    super.key,
    required this.builder,
    this.placeholder = const SizedBox.expand(),
  });

  @override
  State<NaverMapSdkGate> createState() => _NaverMapSdkGateState();
}

class _NaverMapSdkGateState extends State<NaverMapSdkGate> {
  late final Future<bool> _initialization = naverMapStartup.ensureInitialized();

  // Function Name: build
  // Description: Builds the map once the initialization attempt ends. A failed attempt was already reported, and the map is still built as before the SDK start moved off the launch path.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns:
  // - Widget: The map or the placeholder.
  @override
  Widget build(BuildContext context) {
    if (naverMapStartup.isReady) {
      return widget.builder(context);
    }
    return FutureBuilder<bool>(
      future: _initialization,
      builder: (context, snapshot) =>
          snapshot.connectionState == ConnectionState.done
          ? widget.builder(context)
          : widget.placeholder,
    );
  }
}
