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
// 속성:
// - _languageMode (String): system·ko·en 언어 선택 모드
class AppLanguageControl extends ChangeNotifier with WidgetsBindingObserver {
  static const String preferenceKey = 'medbuddy_app_language';

  String _languageMode;
  int _selectionRevision = 0;

  // 함수이름: AppLanguageControl
  // 함수역할: 초기 언어 모드를 정규화하고 기기 언어 변경을 관찰하며 필요하면 저장된 설정을 비동기로 복원한다.
  // 매개변수:
  // - initialLanguage (String): 저장값 복원 전 적용할 초기 언어 모드
  // - loadPersisted (bool): 시작 시 저장된 언어 선택을 읽을지 여부
  // 반환값:
  // - AppLanguageControl: 초기화된 인스턴스.
  AppLanguageControl({String initialLanguage = 'ko', bool loadPersisted = true})
    : _languageMode = normalizeLanguageMode(initialLanguage) {
    WidgetsBinding.instance.addObserver(this);
    if (loadPersisted) {
      unawaited(load());
    }
  }

  // 함수이름: language
  // 함수역할: 시스템 언어 모드를 현재 기기 설정에 적용한 실제 표시 언어 코드를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 시스템 언어 모드를 현재 기기 설정에 적용한 실제 표시 언어 코드를 제공한다.
  String get language => resolveLanguage(_languageMode);

  // 함수이름: languageMode
  // 함수역할: 시스템 따르기 여부를 보존한 사용자의 언어 선택 모드를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: system·ko·en 언어 선택 모드
  String get languageMode => _languageMode;

  // 함수이름: isEnglish
  // 함수역할: 실제 표시 언어가 영어인지 알려 언어별 화면 구성을 선택하게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 실제 표시 언어가 영어인지 알려 언어별 화면 구성을 선택하게 한다.
  bool get isEnglish => language == 'en';

  // 함수이름: load
  // 함수역할: 기기에 저장된 앱 언어를 불러온다. 저장소를 읽는 동안 사용자가 새 언어를 선택했다면 해당 선택을 덮어쓰지 않는다.
  // 매개변수:
  // - 없음.
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

  // 함수이름: setLanguage
  // 함수역할: 앱 전체의 한국어 또는 영어 선택값을 변경하고 기기에 저장한다.
  // 매개변수:
  // - language (String): 변경할 앱 언어 코드
  // 반환값:
  // - 언어 저장이 끝나면 완료된다.
  Future<void> setLanguage(String language) async {
    return setLanguageMode(language);
  }

  // 함수이름: setLanguageMode
  // 함수역할: 기기 설정 따르기, 한국어, 영어 중 선택한 언어 모드를 저장한다.
  // 매개변수:
  // - languageMode (String): system·ko·en 언어 선택 모드
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // Function Name: toggleLanguage
  // Description: Selects the opposite of the current display language and persists that explicit choice on the device.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> toggleLanguage() {
    return setLanguage(isEnglish ? 'ko' : 'en');
  }

  // 함수이름: normalizeLanguage
  // 함수역할: 선택 모드를 검증한 뒤 시스템 설정까지 해석한 ko 또는 en 코드를 구한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 선택 모드를 검증한 뒤 시스템 설정까지 해석한 ko 또는 en 코드를 구한다.
  static String normalizeLanguage(String language) {
    return resolveLanguage(normalizeLanguageMode(language));
  }

  // 함수이름: normalizeLanguageMode
  // 함수역할: 공백과 대소문자를 정리하고 system·en 이외의 선택값을 ko로 제한한다.
  // 매개변수:
  // - languageMode (String): system·ko·en 언어 선택 모드
  // 반환값:
  // - String: 공백과 대소문자를 정리하고 system·en 이외의 선택값을 ko로 제한한다.
  static String normalizeLanguageMode(String languageMode) {
    final normalized = languageMode.trim().toLowerCase();
    if (normalized == 'system' || normalized == 'en') {
      return normalized;
    }
    return 'ko';
  }

  // 함수이름: resolveLanguage
  // 함수역할: 언어 모드를 현재 기기 언어에 맞는 실제 앱 언어 코드로 변환한다.
  // 매개변수:
  // - languageMode (String): system·ko·en 언어 선택 모드
  // - locale (Locale?): 시스템 언어 해석에 사용할 기기 로케일
  // 반환값:
  // - String: 언어 모드를 현재 기기 언어에 맞는 실제 앱 언어 코드로 변환한다.
  static String resolveLanguage(String languageMode, {Locale? locale}) {
    final normalizedMode = normalizeLanguageMode(languageMode);
    if (normalizedMode != 'system') {
      return normalizedMode;
    }
    final deviceLocale =
        locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    return deviceLocale.languageCode.toLowerCase() == 'en' ? 'en' : 'ko';
  }

  // 함수이름: didChangeLocales
  // 함수역할: 시스템 언어를 따르는 경우에만 기기 언어 변경을 화면 구독자에게 알린다.
  // 매개변수:
  // - locales (List<Locale>?): 시스템 언어 해석에 사용할 기기 로케일
  // 반환값:
  // - 없음.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_languageMode == 'system') {
      notifyListeners();
    }
  }

  // 함수이름: dispose
  // 함수역할: 기기 언어 변경 관찰을 해제하고 ChangeNotifier 자원을 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
