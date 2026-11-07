// File Name: naver_map_config.dart
// Role: Initializes the Naver map SDK once, off the startup path, only when a build-time client ID is configured.

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const naverMapClientId = String.fromEnvironment('MEDBUDDY_NAVER_MAP_CLIENT_ID');

// Function Name: isNaverMapConfigured
// Description: Reports whether the build supplied a nonblank Naver map client ID.
// Parameters:
// - None.
// Returns:
// - bool: Whether the build supplied a nonblank Naver map client ID.
bool get isNaverMapConfigured => naverMapClientId.trim().isNotEmpty;

// Class Name: NaverMapStartup
// Role: Shares one Naver map SDK initialization between app startup and the map widgets.
// Responsibilities:
// - Start the SDK at most once at a time and let every caller await the same attempt.
// - Report a failed attempt and allow the next map screen to try again.
// Attributes:
// - _configured (bool): Whether this build has a Naver map client ID.
// - _initialize (Future<void> Function()): SDK initialization that loads the native map library.
// - _attempt (Future<bool>?): The running or successful initialization attempt.
// - isReady (bool): Whether the SDK finished initializing successfully.
class NaverMapStartup {
  final bool _configured;
  final Future<void> Function() _initialize;
  Future<bool>? _attempt;
  bool isReady = false;

  // Function Name: NaverMapStartup
  // Description: Stores the build configuration and the SDK initialization step.
  // Parameters:
  // - configured (bool): Whether this build has a Naver map client ID.
  // - initialize (Future<void> Function()): SDK initialization to run once.
  // Returns:
  // - NaverMapStartup: the initialized instance.
  NaverMapStartup({
    required bool configured,
    required Future<void> Function() initialize,
  }) : _configured = configured,
       _initialize = initialize;

  // Function Name: ensureInitialized
  // Description: Starts or joins the SDK initialization. A failure is reported and forgotten so a later map screen retries.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool>: Whether the SDK is ready; false when the build has no client ID or initialization failed.
  Future<bool> ensureInitialized() {
    if (!_configured) {
      return Future.value(false);
    }
    return _attempt ??= () async {
      try {
        await _initialize();
        isReady = true;
        return true;
      } catch (error, stackTrace) {
        _attempt = null;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'MedBuddy Naver Map',
            context: ErrorDescription('initializing Naver Map'),
          ),
        );
        return false;
      }
    }();
  }
}

// The native map library is about 24 MB, so loading it waits until a map is needed or the first frame is drawn.
final naverMapStartup = NaverMapStartup(
  configured: isNaverMapConfigured,
  initialize: _initializeNaverMapSdk,
);

// Function Name: _initializeNaverMapSdk
// Description: Initializes the SDK with the build client ID and reports authentication failures through Flutter's error boundary.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
Future<void> _initializeNaverMapSdk() async {
  await FlutterNaverMap().init(
    clientId: naverMapClientId,
    onAuthFailed: /* Function Name: onAuthFailed callback
     * Description: Reports Naver Map authentication failures with the SDK-specific Flutter error context.
     * Parameters:
     * - exception (NAuthFailedException): Authentication failure reported by the map SDK.
     * Returns:
     * - No return value.
     */(exception) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          library: 'MedBuddy Naver Map',
          context: ErrorDescription('authenticating the Naver map SDK'),
        ),
      );
    },
  );
}
