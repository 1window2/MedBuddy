// File Name: app_language_control.dart
// Role: Owns the device-wide MedBuddy language preference.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: AppLanguageControl
// Role: Keeps authentication and signed-in settings on one persisted language.
// Responsibilities:
// - Load the last device-wide language without delaying application startup.
// - Validate and persist Korean or English selections.
// - Notify the application root so every active boundary can rebuild.
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

  // Function Name: load
  // Description:
  // - Loads the persisted device-wide language.
  // - Does not overwrite a newer selection made while storage was loading.
  // Returns:
  // - Completes after the stored preference has been considered.
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

  // Function Name: setLanguage
  // Description:
  // - Updates and persists the device-wide Korean or English selection.
  // Parameters:
  // - language: Requested ISO-style application language code.
  // Returns:
  // - Completes after persistence succeeds.
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
