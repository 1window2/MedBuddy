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
  static const Duration _requestTimeout = Duration(seconds: 5);

  final String baseUrl;
  final String userHash;
  final bool useRemotePersistence;
  final http.Client _client;
  final bool _ownsClient;

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
  // 함수역할: 사용자별 캐시를 먼저 읽고 원격 설정을 조회하되 기기 전용 실험실 설정은 유지하며 서버 실패 시 캐시로 대체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 사용자 설정
  // - 저장값이 없으면 기본값으로 채운 UserSetting
  Future<UserSetting> requestUserSetting() async {
    final cachedSetting = await _requestCachedUserSetting();
    if (!useRemotePersistence) {
      return cachedSetting;
    }

    try {
      final response = await _client
          .get(_buildUserSettingUri())
          .timeout(_requestTimeout);
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'User setting lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      // 실험실 설정은 기기 전용 값이므로 서버 응답에 덮어쓰이지 않게 합친다.
      final setting = _decodeUserSetting(responseBody).copyWith(
        nearbyPharmacyLabEnabled: cachedSetting.nearbyPharmacyLabEnabled,
        linkedMedicationChatLabEnabled:
            cachedSetting.linkedMedicationChatLabEnabled,
        multiPillIdentificationLabEnabled:
            cachedSetting.multiPillIdentificationLabEnabled,
      );
      await _cacheUserSetting(setting);
      return setting;
    } catch (error, stackTrace) {
      developer.log(
        'User setting lookup fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return cachedSetting;
    }
  }

  // 함수이름: saveUserSetting
  // 함수역할: 설정 화면에서 선택한 옵션을 실제 설정값으로 변환한 뒤 저장한다.
  // 매개변수:
  // - currentSetting (UserSetting): 현재 사용자 설정
  // - fontSizeOption (String): small, medium, large 중 선택된 글씨 크기 옵션
  // - readingSpeedOption (String): slow, medium, fast 중 선택된 읽기 속도 옵션
  // - language (String): ko 또는 en 언어 코드
  // - languageMode (String?): system·ko·en 언어 선택 모드
  // - timeFormat (String?): 12h 또는 24h 시각 표시 방식
  // - medicationNotificationsEnabled (bool?): 본인 복약 시간 알림 허용 여부
  // - caregiverNotificationsEnabled (bool?): 보호자 복약 상태 알림 허용 여부
  // - chatNotificationsEnabled (bool?): 가족 채팅 알림 허용 여부
  // - notificationDetailMode (String?): full 또는 type_only 알림 세부 표시 모드
  // - defaultMorningTime (String?): 새 아침 알림의 HH:mm 기본 시각
  // - defaultLunchTime (String?): 새 점심 알림의 HH:mm 기본 시각
  // - defaultEveningTime (String?): 새 저녁 알림의 HH:mm 기본 시각
  // - defaultBedtime (String?): 새 취침 전 알림의 HH:mm 기본 시각
  // 반환값:
  // - 저장 완료된 설정과 서버 동기화 여부
  Future<UserSettingSaveResult> saveUserSetting({
    required UserSetting currentSetting,
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
    String? languageMode,
    String? timeFormat,
    bool? medicationNotificationsEnabled,
    bool? caregiverNotificationsEnabled,
    bool? chatNotificationsEnabled,
    String? notificationDetailMode,
    String? defaultMorningTime,
    String? defaultLunchTime,
    String? defaultEveningTime,
    String? defaultBedtime,
  }) async {
    final nextSetting = currentSetting
        .copyWith(userHash: _normalizedUserHash)
        .updateUserSetting(
          fontSize: UserSetting.fontSizeFromOption(fontSizeOption),
          readingSpeed: UserSetting.readingSpeedFromOption(readingSpeedOption),
          language: language,
        )
        .copyWith(
          languageMode: languageMode,
          timeFormat: timeFormat,
          medicationNotificationsEnabled: medicationNotificationsEnabled,
          caregiverNotificationsEnabled: caregiverNotificationsEnabled,
          chatNotificationsEnabled: chatNotificationsEnabled,
          notificationDetailMode: notificationDetailMode,
          defaultMorningTime: defaultMorningTime,
          defaultLunchTime: defaultLunchTime,
          defaultEveningTime: defaultEveningTime,
          defaultBedtime: defaultBedtime,
        );

    await _cacheUserSetting(nextSetting);

    if (!useRemotePersistence) {
      return UserSettingSaveResult(
        setting: nextSetting,
        synchronizedWithServer: false,
      );
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

      // 서버에는 접근성 설정만 저장하고 실험실 설정은 기기 값을 유지한다.
      final savedSetting = _decodeUserSetting(responseBody).copyWith(
        nearbyPharmacyLabEnabled: nextSetting.nearbyPharmacyLabEnabled,
        linkedMedicationChatLabEnabled:
            nextSetting.linkedMedicationChatLabEnabled,
        multiPillIdentificationLabEnabled:
            nextSetting.multiPillIdentificationLabEnabled,
      );
      await _cacheUserSetting(savedSetting);
      return UserSettingSaveResult(
        setting: savedSetting,
        synchronizedWithServer: true,
      );
    } catch (error, stackTrace) {
      developer.log(
        'User setting save fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return UserSettingSaveResult(
        setting: nextSetting,
        synchronizedWithServer: false,
      );
    }
  }

  // 함수이름: saveNearbyPharmacyLabSetting
  // 함수역할: 근처 운영 약국 실험 기능의 노출 여부를 사용자별 기기에 저장한다. 베타 기능이 서버 설정 스키마에 영향을 주지 않도록 원격 전송은 하지 않는다.
  // 매개변수:
  // - currentSetting (UserSetting): 변경하지 않은 값을 보존할 현재 사용자 설정
  // - enabled (bool): 적용하거나 보존할 기능·알림 활성 상태
  // 반환값:
  // - 실험실 설정이 반영된 사용자 설정
  Future<UserSetting> saveNearbyPharmacyLabSetting({
    required UserSetting currentSetting,
    required bool enabled,
  }) async {
    final nextSetting = currentSetting.copyWith(
      userHash: _normalizedUserHash,
      nearbyPharmacyLabEnabled: enabled,
    );
    await _cacheUserSetting(nextSetting);
    return nextSetting;
  }

  // 함수이름: saveLinkedMedicationChatLabSetting
  // 함수역할: 복약 맥락 채팅의 노출 여부를 사용자별 기기에 저장한다. 실험 기능 값은 서버의 정식 사용자 설정 스키마로 전송하지 않는다.
  // 매개변수:
  // - currentSetting (UserSetting): 변경하지 않은 값을 보존할 현재 사용자 설정
  // - enabled (bool): 적용하거나 보존할 기능·알림 활성 상태
  // 반환값:
  // - 복약 맥락 채팅 설정이 반영된 사용자 설정
  Future<UserSetting> saveLinkedMedicationChatLabSetting({
    required UserSetting currentSetting,
    required bool enabled,
  }) async {
    final nextSetting = currentSetting.copyWith(
      userHash: _normalizedUserHash,
      linkedMedicationChatLabEnabled: enabled,
    );
    await _cacheUserSetting(nextSetting);
    return nextSetting;
  }

  // 함수이름: saveMultiPillIdentificationLabSetting
  // 함수역할: 여러 알약 사진을 한 번에 식별하는 실험 기능의 노출 여부를 기기에 저장한다. 검증 중인 기능이 서버의 정식 사용자 설정 스키마에 포함되지 않게 한다.
  // 매개변수:
  // - currentSetting (UserSetting): 변경하지 않은 값을 보존할 현재 사용자 설정
  // - enabled (bool): 적용하거나 보존할 기능·알림 활성 상태
  // 반환값:
  // - 다중 알약 식별 설정이 반영된 사용자 설정
  Future<UserSetting> saveMultiPillIdentificationLabSetting({
    required UserSetting currentSetting,
    required bool enabled,
  }) async {
    final nextSetting = currentSetting.copyWith(
      userHash: _normalizedUserHash,
      multiPillIdentificationLabEnabled: enabled,
    );
    await _cacheUserSetting(nextSetting);
    return nextSetting;
  }

  // 함수이름: _requestCachedUserSetting
  // 함수역할: 사용자별 저장값을 읽고 글씨·음성·언어의 구형 키와 기본값으로 누락을 보완하며 기기 전용 실험실 설정을 복원한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<UserSetting>: 사용자별 저장값을 읽고 글씨·음성·언어의 구형 키와 기본값으로 누락을 보완하며 기기 전용 실험실 설정을 복원한다.
  Future<UserSetting> _requestCachedUserSetting() async {
    final preferences = await SharedPreferences.getInstance();
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
      language:
          preferences.getString(_languageKey) ??
          preferences.getString(_legacyLanguageKey) ??
          fallbackSetting.language,
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
      defaultBedtime:
          preferences.getString(_defaultBedtimeKey) ??
          fallbackSetting.defaultBedtime,
      nearbyPharmacyLabEnabled:
          preferences.getBool(_nearbyPharmacyLabEnabledKey) ?? false,
      linkedMedicationChatLabEnabled:
          preferences.getBool(_linkedMedicationChatLabEnabledKey) ?? false,
      multiPillIdentificationLabEnabled:
          preferences.getBool(_multiPillIdentificationLabEnabledKey) ?? false,
    );
  }

  // 함수이름: _cacheUserSetting
  // 함수역할: 글씨·음성·언어·알림·기본 복약 시간과 실험실 선택값을 현재 사용자 전용 키로 기기에 저장한다.
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
    await preferences.setBool(
      _nearbyPharmacyLabEnabledKey,
      setting.nearbyPharmacyLabEnabled,
    );
    await preferences.setBool(
      _linkedMedicationChatLabEnabledKey,
      setting.linkedMedicationChatLabEnabled,
    );
    await preferences.setBool(
      _multiPillIdentificationLabEnabledKey,
      setting.multiPillIdentificationLabEnabled,
    );
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

  // 함수이름: _nearbyPharmacyLabEnabledKey
  // 함수역할: 근처 약국 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 근처 약국 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  String get _nearbyPharmacyLabEnabledKey =>
      'user_setting_${_normalizedUserHash}_nearby_pharmacy_lab_enabled';

  // 함수이름: _linkedMedicationChatLabEnabledKey
  // 함수역할: 복약 맥락 채팅 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 복약 맥락 채팅 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  String get _linkedMedicationChatLabEnabledKey =>
      'user_setting_${_normalizedUserHash}_linked_medication_chat_lab_enabled';

  // 함수이름: _multiPillIdentificationLabEnabledKey
  // 함수역할: 다중 알약 식별 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 다중 알약 식별 실험 기능 노출 여부를 저장할 사용자별 키를 만든다.
  String get _multiPillIdentificationLabEnabledKey =>
      'user_setting_${_normalizedUserHash}_multi_pill_identification_lab_enabled';

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
