// 파일명: app_language_resolver.dart
// 역할: 저장된 언어 선택 모드를 실제 표시 언어로 해석하는 순수 규칙을 제공한다.

import 'package:flutter/widgets.dart';

// 기기에 저장하는 앱 언어 선택 모드의 SharedPreferences 키.
const String appLanguagePreferenceKey = 'medbuddy_app_language';

// 함수이름: normalizeAppLanguageMode
// 함수역할: 공백과 대소문자를 정리하고 system·en 이외의 선택값을 ko로 제한한다.
// 매개변수:
// - languageMode (String): system·ko·en 언어 선택 모드
// 반환값:
// - String: system, en 또는 ko.
String normalizeAppLanguageMode(String languageMode) {
  final normalized = languageMode.trim().toLowerCase();
  if (normalized == 'system' || normalized == 'en') {
    return normalized;
  }
  return 'ko';
}

// 함수이름: resolveAppLanguage
// 함수역할: 언어 모드를 현재 기기 언어에 맞는 실제 앱 언어 코드로 변환한다. 화면 없이 도는 백그라운드 작업도
//   언어 Control에 의존하지 않고 같은 규칙을 쓰도록 서비스 계층에 둔다.
// 매개변수:
// - languageMode (String): system·ko·en 언어 선택 모드
// - locale (Locale?): 시스템 언어 해석에 사용할 기기 로케일
// 반환값:
// - String: ko 또는 en.
String resolveAppLanguage(String languageMode, {Locale? locale}) {
  final normalizedMode = normalizeAppLanguageMode(languageMode);
  if (normalizedMode != 'system') {
    return normalizedMode;
  }
  final deviceLocale =
      locale ?? WidgetsBinding.instance.platformDispatcher.locale;
  return deviceLocale.languageCode.toLowerCase() == 'en' ? 'en' : 'ko';
}
