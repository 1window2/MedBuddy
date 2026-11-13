// 파일명: app_language_resolver.dart
// 역할: 저장된 언어 선택 모드를 실제 표시 언어로 해석하는 순수 규칙을 제공한다.

import 'package:flutter/widgets.dart';

// 기기에 저장하는 앱 언어 선택 모드의 SharedPreferences 키.
const String appLanguagePreferenceKey = 'medbuddy_app_language';

// Function Name: normalizeAppLanguageMode
// Description: Normalize case and whitespace, accepting system/en and defaulting all other modes to ko.
// Parameters: languageMode (String): stored or requested selection.
// Returns: String: system, en or ko.
String normalizeAppLanguageMode(String languageMode) {
  final normalized = languageMode.trim().toLowerCase();
  if (normalized == 'system' || normalized == 'en') {
    return normalized;
  }
  return 'ko';
}

// Function Name: resolveAppLanguage
// Description: Resolve system mode from the supplied or platform locale; support English explicitly and use Korean otherwise.
// Parameters: languageMode (String): requested selection; locale (Locale?): device-locale override.
// Returns: String: en or ko.
String resolveAppLanguage(String languageMode, {Locale? locale}) {
  final normalizedMode = normalizeAppLanguageMode(languageMode);
  if (normalizedMode != 'system') {
    return normalizedMode;
  }
  final deviceLocale =
      locale ?? WidgetsBinding.instance.platformDispatcher.locale;
  return deviceLocale.languageCode.toLowerCase() == 'en' ? 'en' : 'ko';
}
