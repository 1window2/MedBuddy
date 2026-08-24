// 파일명: naver_map_config.dart
// 역할: 빌드 시 주입한 네이버 지도 Client ID와 SDK 초기화를 관리한다.

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const naverMapClientId = String.fromEnvironment('MEDBUDDY_NAVER_MAP_CLIENT_ID');

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
