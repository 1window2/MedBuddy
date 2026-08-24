// 파일명: app_language_control.dart
// 역할: 기기 전체에서 사용하는 MedBuddy 언어 설정을 관리한다.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: AppLanguageControl
// 역할: 인증 화면과 로그인 후 화면이 하나의 저장된 언어 설정을 사용하게 한다.
// 주요 책임:
// - 앱 시작을 지연하지 않고 마지막 언어 설정을 불러온다.
// - 한국어 또는 영어 선택값을 검증하고 기기에 저장한다.
// - 언어 변경 시 앱 루트에 알려 현재 화면을 다시 구성한다.
class AppLanguageControl extends ChangeNotifier with WidgetsBindingObserver {
  static const String preferenceKey = 'medbuddy_app_language';

  String _languageMode;
  int _selectionRevision = 0;

  AppLanguageControl({String initialLanguage = 'ko', bool loadPersisted = true})
    : _languageMode = normalizeLanguageMode(initialLanguage) {
    WidgetsBinding.instance.addObserver(this);
    if (loadPersisted) {
      unawaited(load());
    }
  }

  String get language => resolveLanguage(_languageMode);

  String get languageMode => _languageMode;

  bool get isEnglish => language == 'en';

  // 함수명: load
  // 역할:
  // - 기기에 저장된 앱 언어를 불러온다.
  // - 저장소를 읽는 동안 사용자가 새 언어를 선택했다면 해당 선택을 덮어쓰지 않는다.
  // 반환값:
  // - 저장된 언어 확인이 끝나면 완료된다.
  Future<void> load() async {
    final revision = _selectionRevision;
    final preferences = await SharedPreferences.getInstance();
    final storedLanguage = preferences.getString(preferenceKey);
    if (revision != _selectionRevision || storedLanguage == null) {
      return;
    }
    final normalizedMode = normalizeLanguageMode(storedLanguage);
    if (normalizedMode == _languageMode) {
      return;
    }
    _languageMode = normalizedMode;
    notifyListeners();
  }

  // 함수명: setLanguage
  // 역할:
  // - 앱 전체의 한국어 또는 영어 선택값을 변경하고 기기에 저장한다.
  // 매개변수:
  // - language: 변경할 앱 언어 코드
  // 반환값:
  // - 언어 저장이 끝나면 완료된다.
  Future<void> setLanguage(String language) async {
    return setLanguageMode(language);
  }

  // 함수명: setLanguageMode
  // 역할: 기기 설정 따르기, 한국어, 영어 중 선택한 언어 모드를 저장한다.
  Future<void> setLanguageMode(String languageMode) async {
    final normalizedMode = normalizeLanguageMode(languageMode);
    _selectionRevision += 1;
    if (_languageMode != normalizedMode) {
      _languageMode = normalizedMode;
      notifyListeners();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, normalizedMode);
  }

  Future<void> toggleLanguage() {
    return setLanguage(isEnglish ? 'ko' : 'en');
  }

  static String normalizeLanguage(String language) {
    return resolveLanguage(normalizeLanguageMode(language));
  }

  static String normalizeLanguageMode(String languageMode) {
    final normalized = languageMode.trim().toLowerCase();
    if (normalized == 'system' || normalized == 'en') {
      return normalized;
    }
    return 'ko';
  }

  // 함수명: resolveLanguage
  // 역할: 언어 모드를 현재 기기 언어에 맞는 실제 앱 언어 코드로 변환한다.
  static String resolveLanguage(String languageMode, {Locale? locale}) {
    final normalizedMode = normalizeLanguageMode(languageMode);
    if (normalizedMode != 'system') {
      return normalizedMode;
    }
    final deviceLocale =
        locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    return deviceLocale.languageCode.toLowerCase() == 'en' ? 'en' : 'ko';
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_languageMode == 'system') {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
