// 파일명: manage_user_setting_control.dart
// 역할: 사용자 설정의 로컬 영속화와 서버 동기화를 수행한다.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 클래스명: ManageUserSetting
// 역할: 글씨 크기, 읽기 속도, 언어 설정을 SharedPreferences에 영구 저장한다.
// 주요 책임:
// - 앱 실행 시 저장된 환경설정을 불러온다.
// - 설정 화면에서 선택한 값을 UserSetting으로 변환한다.
// - 앱을 재시작해도 설정이 유지되도록 로컬 저장소에 저장한다.
// 속성:
// - _requestTimeout (Duration): 식별·분석 요청의 최대 대기시간
// - baseUrl (String): 복약 API 기본 주소
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - useRemotePersistence (bool): 기기 캐시 외에 서버 설정을 동기화할지 여부
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
class ManageUserSetting {
  static const String _legacyFontSizeKey = 'user_setting_font_size';
  static const String _legacyReadingSpeedKey = 'user_setting_reading_speed';
  static const String _legacyLanguageKey = 'user_setting_language';
  // 계정별 저장으로 바뀌기 전의 키. 계정 삭제 정리에서 이 이름만 정확히 지울 수 있게 공개한다.
  static const List<String> legacyUnscopedKeys = [
    _legacyFontSizeKey,
    _legacyReadingSpeedKey,
    _legacyLanguageKey,
  ];
  static const Duration _requestTimeout = Duration(seconds: 5);

  final String baseUrl;
  final String userHash;
  final bool useRemotePersistence;
  final http.Client _client;
  final bool _ownsClient;
  bool _lastLookupReachedServer = false;
  bool _hasPendingSave = false;
  static int _pendingTokenSequence = 0;

  // 함수이름: lastLookupReachedServer
  // 함수역할: 가장 최근 설정 조회가 서버 사본을 받았는지 알려 준다. 캐시만으로 채운 설정을 자동 저장해 서버의 더 새로운 값을 덮어쓰지 않게 하는 데 쓴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 최근 requestUserSetting이 서버 응답으로 끝났으면 true, 캐시로 대체했거나 아직 조회하지 않았으면 false.
  bool get lastLookupReachedServer => _lastLookupReachedServer;

  // 함수이름: hasPendingSave
  // 함수역할: 기기에 저장했지만 아직 서버에 반영하지 못한 설정이 남아 있는지 알려 준다. 표시는 계정별 저장소에 보관되어 앱 재시작과 백그라운드 작업에서도 유지된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 최근 조회·저장 뒤 서버 반영 대기 표시가 남아 있으면 true.
  bool get hasPendingSave => _hasPendingSave;

  // Function Name: ManageUserSetting
  // Description: Binds user-scoped preference persistence to the backend and HTTP client, with an explicit switch for local-only operation.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - userHash (String): Current user hash defining ownership, display, or persistence scope.
  // - useRemotePersistence (bool): Whether to synchronize settings with the server beyond the device cache.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - ManageUserSetting: the initialized instance.
  ManageUserSetting({
    this.baseUrl = ApiConfig.baseUrl,
    this.userHash = PatientHash.defaultPatientHash,
    this.useRemotePersistence = true,
    http.Client? client,
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: requestUserSetting
  // 함수역할: 사용자별 캐시를 먼저 읽고 원격 설정을 조회하며 서버 실패 시 캐시로 대체한다.
  //   서버에 아직 반영하지 못한 저장이 남아 있으면 서버 사본으로 캐시를 덮지 않고 그 저장을 먼저 다시 보낸다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 사용자 설정
  // - 저장값이 없으면 기본값으로 채운 UserSetting
  Future<UserSetting> requestUserSetting() async {
    final preferences = await _loadFreshPreferences();
    final cachedSetting = _readCachedUserSetting(preferences);
    _lastLookupReachedServer = false;
    if (!useRemotePersistence) {
      _hasPendingSave = false;
      return cachedSetting;
    }

    final pendingToken = preferences.getString(_pendingSyncKey);
    if (pendingToken != null) {
      // 오프라인에서 바꾼 설정이 다음 조회의 서버 사본에 덮이지 않도록 대기 중인 저장을 먼저 재시도한다.
      _hasPendingSave = true;
      final result = await _sendUserSetting(cachedSetting, pendingToken);
      _lastLookupReachedServer = result.synchronizedWithServer;
      return result.setting;
    }

    try {
      final response = await _client
          .get(_buildUserSettingUri())
          .timeout(_requestTimeout);
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw ApiResponseParser.httpFailure(
          'User setting lookup failed',
          response,
          responseBody,
        );
      }

      final setting = _decodeUserSetting(responseBody);
      // 조회 중 다른 화면이나 작업이 오프라인 저장을 남겼다면 서버 사본으로 덮지 않는다.
      await _reloadPreferences(preferences);
      if (preferences.getString(_pendingSyncKey) != null) {
        _hasPendingSave = true;
        return _readCachedUserSetting(preferences);
      }
      await _cacheUserSetting(setting);
      _hasPendingSave = false;
      _lastLookupReachedServer = true;
      return setting;
    } catch (error, stackTrace) {
      developer.log(
        'User setting lookup fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      _hasPendingSave = preferences.getString(_pendingSyncKey) != null;
      return cachedSetting;
    }
  }

  // 함수이름: saveUserSetting
  // 함수역할: 이미 완성된 설정 객체를 값 변환 없이 현재 사용자 범위로 기기에 저장하고 서버와 동기화한다. 설정 화면의 초안과 기기 언어 재동기화처럼 설정 전체를 가진 호출부가 사용한다.
  //   서버 반영 전까지 계정별 대기 표시를 남겨, 실패하면 다음 조회가 서버 사본 대신 이 저장을 다시 보낸다.
  // 매개변수:
  // - setting (UserSetting): 저장할 설정 전체. 사용자 해시는 이 컨트롤의 범위로 바꾼다.
  // 반환값:
  // - 저장 완료된 설정과 서버 동기화 여부
  Future<UserSettingSaveResult> saveUserSetting(
    UserSetting setting,
  ) async {
    final nextSetting = setting.copyWith(userHash: _normalizedUserHash);

    await _cacheUserSetting(nextSetting);

    if (!useRemotePersistence) {
      return UserSettingSaveResult(
        setting: nextSetting,
        synchronizedWithServer: false,
      );
    }

    final token = _nextPendingToken();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pendingSyncKey, token);
    _hasPendingSave = true;
    return _sendUserSetting(nextSetting, token);
  }

  // 함수이름: _sendUserSetting
  // 함수역할: 기기에 저장된 설정을 서버로 보내고, 성공하면 대기 표시가 그대로일 때만 서버 사본을 캐시하고 표시를 지운다.
  //   전송 중 더 새로운 기기 저장이 생겼으면 그 값을 보존하고, 표시가 이미 지워졌는데 캐시가 보낸 값과 다르면 다시 대기 표시를 남긴다.
  // 매개변수:
  // - setting (UserSetting): 서버에 보낼 설정 전체.
  // - token (String): 이 저장이 남긴 대기 표시 값.
  // 반환값:
  // - Future<UserSettingSaveResult>: 서버 반영 시 서버 사본과 true, 실패하거나 더 새로운 기기 저장이 있으면 기기 사본과 false.
  Future<UserSettingSaveResult> _sendUserSetting(
    UserSetting setting,
    String token,
  ) async {
    try {
      final response = await _client
          .put(
            _buildUserSettingUri(),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(setting.toJson()),
          )
          .timeout(_requestTimeout);
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw ApiResponseParser.httpFailure(
          'User setting save failed',
          response,
          responseBody,
        );
      }

      final savedSetting = _decodeUserSetting(responseBody);
      final preferences = await _loadFreshPreferences();
      final currentToken = preferences.getString(_pendingSyncKey);
      if (currentToken == token) {
        await _cacheUserSetting(savedSetting);
        await preferences.remove(_pendingSyncKey);
        _hasPendingSave = false;
        return UserSettingSaveResult(
          setting: savedSetting,
          synchronizedWithServer: true,
        );
      }
      final currentSetting = _readCachedUserSetting(preferences);
      if (currentToken == null &&
          jsonEncode(currentSetting.toJson()) != jsonEncode(setting.toJson())) {
        // 다른 저장이 먼저 끝난 뒤 이 오래된 값이 서버에 늦게 도착했다. 기기의 최신 값을 다시 보내게 한다.
        await preferences.setString(_pendingSyncKey, _nextPendingToken());
      }
      _hasPendingSave = preferences.getString(_pendingSyncKey) != null;
      return UserSettingSaveResult(
        setting: currentSetting,
        synchronizedWithServer: !_hasPendingSave,
      );
    } catch (error, stackTrace) {
      developer.log(
        'User setting save fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      _hasPendingSave = true;
      return UserSettingSaveResult(
        setting: setting,
        synchronizedWithServer: false,
      );
    }
  }

  // 함수이름: _loadFreshPreferences
  // 함수역할: 백그라운드 작업 등 다른 isolate가 쓴 값까지 보이도록 저장소를 다시 읽어 돌려준다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<SharedPreferences>: 최신 값으로 갱신을 시도한 저장소.
  Future<SharedPreferences> _loadFreshPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await _reloadPreferences(preferences);
    return preferences;
  }

  // 함수이름: _reloadPreferences
  // 함수역할: 저장소를 다시 읽고, 다시 읽기에 실패하면 메모리 사본을 그대로 쓴다.
  // 매개변수:
  // - preferences (SharedPreferences): 다시 읽을 저장소.
  // 반환값:
  // - Future<void>: 다시 읽기를 시도한 뒤 완료되는 Future.
  Future<void> _reloadPreferences(SharedPreferences preferences) async {
    try {
      await preferences.reload();
    } catch (error, stackTrace) {
      developer.log(
        'User setting preferences reload failed.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // 함수이름: _nextPendingToken
  // 함수역할: 저장마다 다른 서버 반영 대기 표시 값을 만든다. 늦게 끝난 전송이 더 새로운 저장의 표시를 지우지 않게 구분한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 시각과 일련번호로 만든 표시 값.
  static String _nextPendingToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_pendingTokenSequence++}';

  // 함수이름: _readCachedUserSetting
  // 함수역할: 사용자별 설정을 읽고 구형 접근성 키와 기본값으로 누락을 보완한다. 폐기된 실험실 키는 읽지 않는다.
  // 매개변수:
  // - preferences (SharedPreferences): 설정을 읽을 저장소.
  // 반환값:
  // - UserSetting: 현재 사용자 설정 또는 누락 값을 보완한 기본 설정.
  UserSetting _readCachedUserSetting(SharedPreferences preferences) {
    final fallbackSetting = UserSetting(userHash: _normalizedUserHash);

    return UserSetting(
      userHash: fallbackSetting.userHash,
      fontSize:
          preferences.getInt(_fontSizeKey) ??
          preferences.getInt(_legacyFontSizeKey) ??
          fallbackSetting.fontSize,
      readingSpeed:
          preferences.getDouble(_readingSpeedKey) ??
          preferences.getDouble(_legacyReadingSpeedKey) ??
          fallbackSetting.readingSpeed,
      // 서버 응답과 같은 기준으로 ko·en만 남겨 캐시 값이 화면마다 다르게 판정되지 않게 한다.
      language: normalizeAppLanguage(
        preferences.getString(_languageKey) ??
            preferences.getString(_legacyLanguageKey) ??
            fallbackSetting.language,
      ),
      languageMode:
          preferences.getString(_languageModeKey) ??
          preferences.getString(_languageKey) ??
          fallbackSetting.languageMode,
      timeFormat:
          preferences.getString(_timeFormatKey) ?? fallbackSetting.timeFormat,
      medicationNotificationsEnabled:
          preferences.getBool(_medicationNotificationsEnabledKey) ??
          fallbackSetting.medicationNotificationsEnabled,
      caregiverNotificationsEnabled:
          preferences.getBool(_caregiverNotificationsEnabledKey) ??
          fallbackSetting.caregiverNotificationsEnabled,
      chatNotificationsEnabled:
          preferences.getBool(_chatNotificationsEnabledKey) ??
          fallbackSetting.chatNotificationsEnabled,
      notificationDetailMode:
          preferences.getString(_notificationDetailModeKey) ??
          fallbackSetting.notificationDetailMode,
      defaultMorningTime:
          preferences.getString(_defaultMorningTimeKey) ??
          fallbackSetting.defaultMorningTime,
      defaultLunchTime:
          preferences.getString(_defaultLunchTimeKey) ??
          fallbackSetting.defaultLunchTime,
      defaultEveningTime:
          preferences.getString(_defaultEveningTimeKey) ??
          fallbackSetting.defaultEveningTime,
      homeScheduleSource:
          preferences.getString(_homeScheduleSourceKey) == 'patients'
          ? 'patients'
          : 'self',
      defaultBedtime:
          preferences.getString(_defaultBedtimeKey) ??
          fallbackSetting.defaultBedtime,
    );
  }

  // 함수이름: _cacheUserSetting
  // 함수역할: 글씨·음성·언어·알림·기본 복약 시간을 현재 사용자 전용 키로 기기에 저장한다.
  // 매개변수:
  // - setting (UserSetting): 복원·저장·적용할 사용자 환경 설정
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cacheUserSetting(UserSetting setting) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_fontSizeKey, setting.fontSize);
    await preferences.setDouble(_readingSpeedKey, setting.readingSpeed);
    await preferences.setString(_languageKey, setting.language);
    await preferences.setString(_languageModeKey, setting.languageMode);
    await preferences.setString(_timeFormatKey, setting.timeFormat);
    await preferences.setString(
      _homeScheduleSourceKey,
      setting.homeScheduleSource,
    );
    await preferences.setBool(
      _medicationNotificationsEnabledKey,
      setting.medicationNotificationsEnabled,
    );
    await preferences.setBool(
      _caregiverNotificationsEnabledKey,
      setting.caregiverNotificationsEnabled,
    );
    await preferences.setBool(
      _chatNotificationsEnabledKey,
      setting.chatNotificationsEnabled,
    );
    await preferences.setString(
      _notificationDetailModeKey,
      setting.notificationDetailMode,
    );
    await preferences.setString(
      _defaultMorningTimeKey,
      setting.defaultMorningTime,
    );
    await preferences.setString(_defaultLunchTimeKey, setting.defaultLunchTime);
    await preferences.setString(
      _defaultEveningTimeKey,
      setting.defaultEveningTime,
    );
    await preferences.setString(_defaultBedtimeKey, setting.defaultBedtime);
  }

  // Function Name: _decodeUserSetting
  // Description: Requires the response data map and decodes it into UserSetting, rejecting responses without settings.
  // Parameters:
  // - responseBody (String): Server response body decoded as UTF-8.
  // Returns:
  // - UserSetting: Requires the response data map and decodes it into UserSetting, rejecting responses without settings.
  UserSetting _decodeUserSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return UserSetting.fromJson(Map<String, dynamic>.from(rawSetting));
    }
    throw StateError('Server response did not include user setting.');
  }

  // Function Name: _buildUserSettingUri
  // Description: Builds the user-settings endpoint with the normalized current user hash.
  // Parameters:
  // - None.
  // Returns:
  // - Uri: Builds the user-settings endpoint with the normalized current user hash.
  Uri _buildUserSettingUri() {
    return Uri.parse(
      '$baseUrl/settings/user',
    ).replace(queryParameters: {'user_hash': _normalizedUserHash});
  }

  // Function Name: _normalizedUserHash
  // Description: Normalizes the current user hash before creating preference keys or scoped API requests.
  // Parameters:
  // - None.
  // Returns:
  // - String: Normalizes the current user hash before creating preference keys or scoped API requests.
  String get _normalizedUserHash => PatientHash.normalizePatientHash(userHash);

  // Function Name: _fontSizeKey
  // Description: Selects the user-scoped preference key for the base text size.
  // Parameters:
  // - None.
  // Returns:
  // - String: Selects the user-scoped preference key for the base text size.
  String get _fontSizeKey => 'user_setting_${_normalizedUserHash}_font_size';

  // Function Name: _readingSpeedKey
  // Description: Selects the user-scoped preference key for the TTS reading rate.
  // Parameters:
  // - None.
  // Returns:
  // - String: Selects the user-scoped preference key for the TTS reading rate.
  String get _readingSpeedKey =>
      'user_setting_${_normalizedUserHash}_reading_speed';

  // Function Name: _languageKey
  // Description: Selects the user-scoped preference key for the resolved display language.
  // Parameters:
  // - None.
  // Returns:
  // - String: Selects the user-scoped preference key for the resolved display language.
  String get _languageKey => 'user_setting_${_normalizedUserHash}_language';

  // 함수이름: _languageModeKey
  // 함수역할: 시스템 언어 따르기 선택을 보존할 사용자별 언어 모드 저장 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 시스템 언어 따르기 선택을 보존할 사용자별 언어 모드 저장 키를 만든다.
  String get _languageModeKey =>
      'user_setting_${_normalizedUserHash}_language_mode';

  // 함수이름: _pendingSyncKey
  // 함수역할: 기기에 저장했지만 서버에 반영하지 못한 설정이 있음을 표시하는 계정별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 서버 반영 대기 표시를 저장할 사용자별 키.
  String get _pendingSyncKey =>
      'user_setting_${_normalizedUserHash}_pending_sync';

  // 함수역할: 홈 일정 선택을 현재 계정에만 저장한다.
  String get _homeScheduleSourceKey =>
      'user_setting_${_normalizedUserHash}_home_schedule_source';

  // 함수이름: _timeFormatKey
  // 함수역할: 12시간·24시간 표시 방식을 보존할 사용자별 저장 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 12시간·24시간 표시 방식을 보존할 사용자별 저장 키를 만든다.
  String get _timeFormatKey =>
      'user_setting_${_normalizedUserHash}_time_format';

  // 함수이름: _medicationNotificationsEnabledKey
  // 함수역할: 환자 복약 알림 허용 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 환자 복약 알림 허용 여부를 저장할 사용자별 키를 만든다.
  String get _medicationNotificationsEnabledKey =>
      'user_setting_${_normalizedUserHash}_medication_notifications_enabled';

  // 함수이름: _caregiverNotificationsEnabledKey
  // 함수역할: 보호자 모니터링 알림 허용 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 보호자 모니터링 알림 허용 여부를 저장할 사용자별 키를 만든다.
  String get _caregiverNotificationsEnabledKey =>
      'user_setting_${_normalizedUserHash}_caregiver_notifications_enabled';

  // 함수이름: _chatNotificationsEnabledKey
  // 함수역할: 가족 채팅 알림 허용 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 가족 채팅 알림 허용 여부를 저장할 사용자별 키를 만든다.
  String get _chatNotificationsEnabledKey =>
      'user_setting_${_normalizedUserHash}_chat_notifications_enabled';

  // 함수이름: _notificationDetailModeKey
  // 함수역할: 잠금 화면의 민감정보 표시 모드를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 잠금 화면의 민감정보 표시 모드를 저장할 사용자별 키를 만든다.
  String get _notificationDetailModeKey =>
      'user_setting_${_normalizedUserHash}_notification_detail_mode';

  // 함수이름: _defaultMorningTimeKey
  // 함수역할: 새 아침 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 새 아침 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  String get _defaultMorningTimeKey =>
      'user_setting_${_normalizedUserHash}_default_morning_time';

  // 함수이름: _defaultLunchTimeKey
  // 함수역할: 새 점심 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 새 점심 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  String get _defaultLunchTimeKey =>
      'user_setting_${_normalizedUserHash}_default_lunch_time';

  // 함수이름: _defaultEveningTimeKey
  // 함수역할: 새 저녁 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 새 저녁 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  String get _defaultEveningTimeKey =>
      'user_setting_${_normalizedUserHash}_default_evening_time';

  // 함수이름: _defaultBedtimeKey
  // 함수역할: 새 취침 전 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 새 취침 전 복약 알림의 기본 시간을 저장할 사용자별 키를 만든다.
  String get _defaultBedtimeKey =>
      'user_setting_${_normalizedUserHash}_default_bedtime';

  // Function Name: dispose
  // Description: Closes the HTTP client only when this control created it; injected clients remain owned by the caller.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
