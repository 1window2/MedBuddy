// File Name: naver_map_config.dart
// Role: Initializes the Naver map SDK only when a build-time client ID is configured.

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

// Function Name: initializeNaverMap
// Description: Skips unconfigured map support or initializes the SDK and reports authentication failures through Flutter's error boundary.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
Future<void> initializeNaverMap() async {
  if (!isNaverMapConfigured) {
    return;
  }
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
