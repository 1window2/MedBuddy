// 파일명: app_language_control.dart
// 역할: 기기 전체에서 사용하는 MedBuddy 언어 설정을 관리한다.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: AppLanguageControl
// 역할: 인증 화면과 로그인 후 화면이 하나의 저장된 언어 설정을 사용하게 한다.
// 주요 책임:
// - 앱 시작을 지연하지 않고 마지막 언어 설정을 불러온다.
// - 한국어 또는 영어 선택값을 검증하고 기기에 저장한다.
// - 언어 변경 시 앱 루트에 알려 현재 화면을 다시 구성한다.
class AppLanguageControl extends ChangeNotifier {
  static const String preferenceKey = 'medbuddy_app_language';

  String _language;
  int _selectionRevision = 0;

  AppLanguageControl({String initialLanguage = 'ko', bool loadPersisted = true})
    : _language = normalizeLanguage(initialLanguage) {
    if (loadPersisted) {
      unawaited(load());
    }
  }

  String get language => _language;

  bool get isEnglish => _language == 'en';

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
    final normalizedLanguage = normalizeLanguage(storedLanguage);
    if (normalizedLanguage == _language) {
      return;
    }
    _language = normalizedLanguage;
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
    final normalizedLanguage = normalizeLanguage(language);
    _selectionRevision += 1;
    if (_language != normalizedLanguage) {
      _language = normalizedLanguage;
      notifyListeners();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, normalizedLanguage);
  }

  Future<void> toggleLanguage() {
    return setLanguage(isEnglish ? 'ko' : 'en');
  }

  static String normalizeLanguage(String language) {
    return language.trim().toLowerCase() == 'en' ? 'en' : 'ko';
  }
}
