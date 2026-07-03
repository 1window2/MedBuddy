import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// 파일명: manage_user_setting_control.dart
// 역할: 사용자 환경설정을 로컬 저장소에 저장하고 불러온다.

// 클래스명: ManageUserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 SharedPreferences에 영구 저장한다.
// 주요 책임:
// - 앱 실행 시 저장된 환경설정을 불러온다.
// - 설정 화면에서 선택한 값을 UserSetting으로 변환한다.
// - 앱을 재시작해도 설정이 유지되도록 로컬 저장소에 저장한다.
class ManageUserSetting {
  static const String _legacyFontSizeKey = 'user_setting_font_size';
  static const String _legacyReadingSpeedKey = 'user_setting_reading_speed';
  static const String _legacyLanguageKey = 'user_setting_language';
  static const Duration _requestTimeout = Duration(seconds: 5);

  final String baseUrl;
  final String userHash;
  final bool useRemotePersistence;
  final http.Client _client;
  final bool _ownsClient;

  ManageUserSetting({
    this.baseUrl = ApiConfig.baseUrl,
    this.userHash = PatientHash.defaultPatientHash,
    this.useRemotePersistence = true,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestUserSetting
  // 함수역할:
  // - 현재 메모리에 있는 사용자 설정을 반환한다.
  // 매개변수:
  // - currentSetting: ViewModel이 보관 중인 현재 설정
  // 반환값:
  // - 현재 사용자 설정
  UserSetting requestUserSetting(UserSetting currentSetting) {
    return currentSetting;
  }

  // 함수명: requestStoredUserSetting
  // 함수역할:
  // - SharedPreferences에 저장된 사용자 설정을 불러온다.
  // 반환값:
  // - 저장값이 없으면 기본값으로 채운 UserSetting
  Future<UserSetting> requestStoredUserSetting() async {
    if (!useRemotePersistence) {
      return _requestCachedUserSetting();
    }

    try {
      final response =
          await _client.get(_buildUserSettingUri()).timeout(_requestTimeout);
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'User setting lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final setting = _decodeUserSetting(responseBody);
      await _cacheUserSetting(setting);
      return setting;
    } catch (error, stackTrace) {
      developer.log(
        'User setting lookup fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return _requestCachedUserSetting();
    }
  }

  // 함수명: requestSettingSave
  // 함수역할:
  // - 설정 화면에서 선택한 옵션을 실제 설정값으로 변환한 뒤 저장한다.
  // 매개변수:
  // - currentSetting: 현재 사용자 설정
  // - fontSizeOption: small, medium, large 중 선택된 글씨 크기 옵션
  // - readingSpeedOption: slow, medium, fast 중 선택된 읽기 속도 옵션
  // - language: ko 또는 en 언어 코드
  // 반환값:
  // - 저장 완료된 새 UserSetting
  Future<UserSetting> requestSettingSave({
    required UserSetting currentSetting,
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) async {
    final nextSetting = currentSetting
        .copyWith(userHash: _normalizedUserHash)
        .changeFontSize(UserSetting.fontSizeFromOption(fontSizeOption))
        .changeReadingSpeed(
          UserSetting.readingSpeedFromOption(readingSpeedOption),
        )
        .changeLanguage(language);

    await _cacheUserSetting(nextSetting);

    if (!useRemotePersistence) {
      return nextSetting;
    }

    try {
      final response = await _client
          .put(
            _buildUserSettingUri(),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(nextSetting.toJson()),
          )
          .timeout(_requestTimeout);
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'User setting save failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final savedSetting = _decodeUserSetting(responseBody);
      await _cacheUserSetting(savedSetting);
      return savedSetting;
    } catch (error, stackTrace) {
      developer.log(
        'User setting save fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return nextSetting;
    }
  }

  Future<UserSetting> _requestCachedUserSetting() async {
    final preferences = await SharedPreferences.getInstance();
    final fallbackSetting = UserSetting(userHash: _normalizedUserHash);

    return UserSetting(
      userHash: fallbackSetting.userHash,
      fontSize: preferences.getInt(_fontSizeKey) ??
          preferences.getInt(_legacyFontSizeKey) ??
          fallbackSetting.fontSize,
      readingSpeed: preferences.getDouble(_readingSpeedKey) ??
          preferences.getDouble(_legacyReadingSpeedKey) ??
          fallbackSetting.readingSpeed,
      language: preferences.getString(_languageKey) ??
          preferences.getString(_legacyLanguageKey) ??
          fallbackSetting.language,
    );
  }

  Future<void> _cacheUserSetting(UserSetting setting) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_fontSizeKey, setting.fontSize);
    await preferences.setDouble(_readingSpeedKey, setting.readingSpeed);
    await preferences.setString(_languageKey, setting.language);
  }

  UserSetting _decodeUserSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return UserSetting.fromJson(Map<String, dynamic>.from(rawSetting));
    }
    throw StateError('Server response did not include user setting.');
  }

  Uri _buildUserSettingUri() {
    return Uri.parse('$baseUrl/settings/user').replace(
      queryParameters: {'user_hash': _normalizedUserHash},
    );
  }

  String get _normalizedUserHash => PatientHash.normalizePatientHash(userHash);

  String get _fontSizeKey => 'user_setting_${_normalizedUserHash}_font_size';

  String get _readingSpeedKey =>
      'user_setting_${_normalizedUserHash}_reading_speed';

  String get _languageKey => 'user_setting_${_normalizedUserHash}_language';

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
