// File name: naver_map_config.dart
// Role: Owns the compile-time Naver Dynamic Map client identifier and SDK startup.

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const naverMapClientId = String.fromEnvironment(
  'MEDBUDDY_NAVER_MAP_CLIENT_ID',
);

bool get isNaverMapConfigured => naverMapClientId.trim().isNotEmpty;

Future<void> initializeNaverMap() async {
  if (!isNaverMapConfigured) {
    return;
  }
  await FlutterNaverMap().init(
    clientId: naverMapClientId,
    onAuthFailed: (exception) {
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
