// File Name: user_setting_language_test.dart
// Role: Regression coverage for the shared English-language predicate and the language code
//   normalization of UserSetting.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// Function Name: main
// Description:
// - Register regression cases for the shared English-language predicate and the language code
//   normalization of UserSetting.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: any code starting with "en" is English regardless of case and padding;
  //   null, empty and other codes are not.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('isEnglishLanguage accepts every spelling of an English code', () {
    for (final language in ['en', 'EN', 'en-US', 'en_GB', ' en ', 'En-us']) {
      expect(isEnglishLanguage(language), isTrue, reason: language);
    }
    for (final language in <String?>[null, '', '  ', 'ko', 'KO', 'fr', 'ken']) {
      expect(isEnglishLanguage(language), isFalse, reason: '$language');
    }
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: every value collapses to the two supported codes, with Korean as the
  //   default for empty and unsupported values.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('normalizeAppLanguage returns only ko or en', () {
    expect(normalizeAppLanguage('EN'), 'en');
    expect(normalizeAppLanguage('en-US'), 'en');
    expect(normalizeAppLanguage(' en '), 'en');
    expect(normalizeAppLanguage('en'), 'en');
    expect(normalizeAppLanguage('ko'), 'ko');
    expect(normalizeAppLanguage(''), 'ko');
    expect(normalizeAppLanguage(null), 'ko');
    expect(normalizeAppLanguage('fr'), 'ko');
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: fromJson stores the normalized code, so the exact and the prefix checks
  //   used across the app agree, and toJson sends a code the server accepts.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('fromJson normalizes the stored language and round-trips it', () {
    const expectedLanguages = {
      'EN': 'en',
      'en-US': 'en',
      ' en ': 'en',
      'en': 'en',
      'ko': 'ko',
      '': 'ko',
      'fr': 'ko',
    };
    for (final entry in expectedLanguages.entries) {
      final setting = UserSetting.fromJson({'language': entry.key});

      expect(setting.language, entry.value, reason: '"${entry.key}"');
      expect(setting.isEnglish, entry.value == 'en', reason: '"${entry.key}"');
      expect(
        setting.language == 'en',
        isEnglishLanguage(entry.key),
        reason: 'exact and prefix checks must agree for "${entry.key}"',
      );
      expect(setting.toJson()['language'], entry.value);
      expect(
        UserSetting.fromJson(setting.toJson()).language,
        entry.value,
        reason: 'round trip of "${entry.key}"',
      );
    }
    expect(UserSetting.fromJson(const {}).language, 'ko');
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: a missing language mode follows the normalized language, while an
  //   explicit mode is preserved.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('fromJson derives a missing language mode from the normalized language', () {
    expect(UserSetting.fromJson(const {'language': 'EN'}).languageMode, 'en');
    expect(UserSetting.fromJson(const {'language': 'fr'}).languageMode, 'ko');
    expect(
      UserSetting.fromJson(const {
        'language': 'en-US',
        'language_mode': 'system',
      }).languageMode,
      'system',
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: copyWith and updateUserSetting normalize a new language and keep the
  //   current one when no language is given.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('copyWith and updateUserSetting store the normalized language', () {
    const setting = UserSetting();

    expect(setting.copyWith(language: 'EN-us').language, 'en');
    expect(setting.copyWith(language: 'fr').language, 'ko');
    expect(setting.copyWith(language: 'en').copyWith(fontSize: 20).language, 'en');
    expect(
      setting
          .updateUserSetting(fontSize: 16, readingSpeed: 1.0, language: ' EN ')
          .language,
      'en',
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: isEnglish and the 12-hour period label follow the shared predicate even
  //   for a directly constructed setting whose language was not normalized.
  // Parameters:
  // - None.
  // Returns:
  // - No value; the test fails when an expectation does not hold.
  test('isEnglish and the 12-hour period label use the shared predicate', () {
    const english = UserSetting(language: 'en-US', timeFormat: '12h');
    const korean = UserSetting(language: 'ko', timeFormat: '12h');

    expect(english.isEnglish, isTrue);
    expect(korean.isEnglish, isFalse);
    expect(english.formatTime(8, 5), 'AM 8:05');
    expect(english.formatTime(20, 5), 'PM 8:05');
    expect(korean.formatTime(8, 5), '오전 8:05');
    expect(korean.formatTime(20, 5), '오후 8:05');
  });
}
