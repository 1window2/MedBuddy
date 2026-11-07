// 파일명: manage_user_setting_control.dart
// 역할: 사용자 설정의 로컬 영속화와 서버 동기화를 수행한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/patient_hash_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../services/user_setting_preference_keys.dart';

typedef _SettingState = ({
  UserSetting setting,
  String? pendingToken,
  String? intent,
  int revision,
});

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
  static final Map<String, Future<void>> _localWrites = {};

  // Function Name: lastLookupReachedServer
  // Description: Reports whether the latest settings lookup obtained a server copy rather than relying on cache.
  // Parameters: None.
  // Returns: True after a server-backed lookup; false before lookup or after cache fallback, preventing unintended remote overwrite.
  bool get lastLookupReachedServer => _lastLookupReachedServer;

  // Function Name: hasPendingSave
  // Description: Exposes whether locally saved preferences still await server synchronization.
  // Parameters: None.
  // Returns: The latest locally observed pending flag; durable account storage retains the marker across restarts.
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
    final initial = await _withPreferences(_readState);
    _lastLookupReachedServer = false;
    if (!useRemotePersistence) {
      _hasPendingSave = false;
      return initial.setting;
    }

    final pendingToken = initial.pendingToken;
    if (pendingToken != null) {
      // 오프라인에서 바꾼 설정이 다음 조회의 서버 사본에 덮이지 않도록 대기 중인 저장을 먼저 재시도한다.
      _hasPendingSave = true;
      final result = await _sendUserSetting(initial.setting, pendingToken);
      _lastLookupReachedServer = result.synchronizedWithServer;
      return result.setting;
    }
    final lookupIntent = initial.intent;

    try {
      final response = await _client
          .get(_buildUserSettingUri())
          .timeout(_requestTimeout);
      final responseBody = ApiResponseParser.requireOkBody(
        'User setting lookup failed',
        response,
      );

      final setting = _decodeUserSetting(responseBody);
      // 조회 중 다른 화면이나 작업이 오프라인 저장을 남겼다면 서버 사본으로 덮지 않는다.
      return await _withPreferences((preferences) async {
        final current = _readState(preferences);
        _hasPendingSave = current.pendingToken != null;
        final revision = _responseRevision(responseBody);
        if (_hasPendingSave ||
            current.intent != lookupIntent ||
            (revision != null && revision < current.revision)) {
          return current.setting;
        }
        final merged = setting.copyWith(
          medicationSearchMode: current.setting.medicationSearchMode,
        );
        await _writeState(preferences, (
          setting: merged,
          pendingToken: null,
          intent: current.intent,
          revision: revision ?? current.revision,
        ));
        _lastLookupReachedServer = true;
        return merged;
      });
    } catch (error, stackTrace) {
      developer.log(
        'User setting lookup fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return _withPreferences(
        (preferences) => _currentSaveResult(preferences).setting,
      );
    }
  }

  // 함수이름: saveUserSetting
  // 함수역할: 이미 완성된 설정 객체를 값 변환 없이 현재 사용자 범위로 기기에 저장하고 서버와 동기화한다. 설정 화면의 초안과 기기 언어 재동기화처럼 설정 전체를 가진 호출부가 사용한다.
  //   서버 반영 전까지 계정별 대기 표시를 남겨, 실패하면 다음 조회가 서버 사본 대신 이 저장을 다시 보낸다.
  // 매개변수:
  // - setting (UserSetting): 저장할 설정 전체. 사용자 해시는 이 컨트롤의 범위로 바꾼다.
  // 반환값:
  // - 저장 완료된 설정과 서버 동기화 여부
  Future<UserSettingSaveResult> saveUserSetting(UserSetting setting) async {
    final nextSetting = setting.copyWith(userHash: _normalizedUserHash);

    // 기기별 검색 모드만 바꾸면 서버 버전과 미전송 설정은 건드리지 않는다.
    final deviceOnly = await _withPreferences((preferences) async {
      final current = _readState(preferences);
      if (current.setting.medicationSearchMode ==
              nextSetting.medicationSearchMode ||
          !mapEquals(
            current.setting.toJson(includeDevicePreferences: false),
            nextSetting.toJson(includeDevicePreferences: false),
          )) {
        return null;
      }
      await _writeState(preferences, (
        setting: nextSetting,
        pendingToken: current.pendingToken,
        intent: current.intent,
        revision: current.revision,
      ));
      _hasPendingSave = current.pendingToken != null;
      return UserSettingSaveResult(
        setting: nextSetting,
        synchronizedWithServer: useRemotePersistence && !_hasPendingSave,
      );
    });
    if (deviceOnly != null) return deviceOnly;

    if (!useRemotePersistence) {
      await _withPreferences((preferences) async {
        final current = _readState(preferences);
        await _writeState(preferences, (
          setting: nextSetting,
          pendingToken: current.pendingToken,
          intent: current.intent,
          revision: current.revision,
        ));
      });
      return UserSettingSaveResult(
        setting: nextSetting,
        synchronizedWithServer: false,
      );
    }

    // 설정과 대기 표시를 한 스냅샷으로 저장한다. 중간 종료나 백그라운드 조회에서도
    // 새 표시와 옛 설정이 섞여 재전송되지 않게 한다.
    final token = _nextPendingToken();
    await _withPreferences((preferences) async {
      final current = _readState(preferences);
      await _writeState(preferences, (
        setting: nextSetting,
        pendingToken: token,
        intent: token,
        revision: current.revision,
      ));
      _hasPendingSave = true;
    });
    return _sendUserSetting(nextSetting, token);
  }

  // 함수이름: _sendUserSetting
  // 함수역할: 기기에 저장된 설정을 서버로 보내고, 성공하면 대기 표시가 그대로일 때만 서버 사본을 캐시하고 표시를 지운다.
  //   서버 버전 충돌은 최신 기기 저장만 재시도한다. 시간 초과된 옛 요청은 서버에서 거절되므로 최신 저장을 되돌리지 않는다.
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
      var expectedRevision = await _withPreferences(
        (preferences) => _readState(preferences).revision,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        final superseded = await _withPreferences(
          (preferences) => _readState(preferences).pendingToken == token
              ? null
              : _currentSaveResult(preferences),
        );
        if (superseded != null) return superseded;
        final response = await _client
            .put(
              _buildUserSettingUri(),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                ...setting.toJson(includeDevicePreferences: false),
                'expected_revision': expectedRevision,
              }),
            )
            .timeout(_requestTimeout);
        final responseBody = ApiResponseParser.decodeBody(response);
        if (response.statusCode == 409) {
          final detail = ApiResponseParser.decodeMap(responseBody)['detail'];
          if (detail is Map &&
              detail['code'] == 'settings_revision_conflict' &&
              detail['revision'] is int &&
              (detail['revision'] as int) >= 0) {
            expectedRevision = detail['revision'] as int;
            continue;
          }
        }

        if (response.statusCode != 200) {
          throw ApiResponseParser.httpFailure(
            'User setting save failed',
            response,
            responseBody,
          );
        }

        final savedSetting = _decodeUserSetting(responseBody);
        return await _withPreferences((preferences) async {
          final current = _readState(preferences);
          if (current.pendingToken == token) {
            final merged = savedSetting.copyWith(
              medicationSearchMode: current.setting.medicationSearchMode,
            );
            await _writeState(preferences, (
              setting: merged,
              pendingToken: null,
              intent: current.intent,
              revision: _responseRevision(responseBody) ?? current.revision,
            ));
            _hasPendingSave = false;
            return UserSettingSaveResult(
              setting: merged,
              synchronizedWithServer: true,
            );
          }
          return _currentSaveResult(preferences);
        });
      }
      throw StateError('User setting changed repeatedly while saving.');
    } catch (error, stackTrace) {
      developer.log(
        'User setting save fell back to local cache.',
        name: 'ManageUserSetting',
        error: error,
        stackTrace: stackTrace,
      );
      return _withPreferences(_currentSaveResult);
    }
  }

  // 함수이름: _currentSaveResult
  // 함수역할: 현재 저장소 상태로 결과를 다시 만들어 늦게 끝난 요청이 최신 저장 상태를 되돌리지 않게 한다.
  // 매개변수: preferences: 최신 계정 설정을 읽을 저장소.
  // 반환값: 현재 설정과 대기 토큰 유무에 따른 서버 동기화 결과.
  UserSettingSaveResult _currentSaveResult(SharedPreferences preferences) {
    final current = _readState(preferences);
    _hasPendingSave = current.pendingToken != null;
    return UserSettingSaveResult(
      setting: current.setting,
      synchronizedWithServer: !_hasPendingSave,
    );
  }

  // 함수이름: _responseRevision
  // 함수역할: 서버 응답에서 유효한 설정 리비전만 읽는다.
  // 매개변수: responseBody: JSON 응답 본문.
  // 반환값: 0 이상의 정수 리비전 또는 구형·잘못된 필드의 경우 null; JSON 디코딩 오류는 전파한다.
  int? _responseRevision(String responseBody) {
    final revision = ApiResponseParser.decodeMap(responseBody)['revision'];
    return revision is int && revision >= 0 ? revision : null;
  }

  // 함수이름: _withPreferences
  // 함수역할: 같은 isolate 안에서 계정별 저장소 검사와 쓰기를 직렬화한다.
  // 매개변수: action: 갱신한 SharedPreferences로 수행할 동기 또는 비동기 작업.
  // 반환값: 작업 결과 Future; 실패해도 후속 작업 잠금을 해제한다. 네트워크 대기는 호출자가 잠금 밖에서 수행한다.
  Future<T> _withPreferences<T>(
    FutureOr<T> Function(SharedPreferences) action,
  ) async {
    final owner = _normalizedUserHash;
    final previous = _localWrites[owner];
    final done = Completer<void>();
    _localWrites[owner] = done.future;
    try {
      if (previous != null) await previous;
      return await action(await _loadFreshPreferences());
    } finally {
      done.complete();
      if (identical(_localWrites[owner], done.future)) {
        _localWrites.remove(owner);
      }
    }
  }

  // Function Name: _readState
  // Description: Reads the account snapshot, falling back to legacy keys when absent or malformed.
  // Parameters: preferences: Account-keyed local storage.
  // Returns: Settings, pending intent and server revision; snapshot format/type failures preserve the legacy copy.
  _SettingState _readState(SharedPreferences preferences) {
    final snapshot = preferences.getString(
      _key(UserSettingPreference.snapshot),
    );
    if (snapshot != null) {
      try {
        final data = jsonDecode(snapshot) as Map<String, dynamic>;
        return (
          setting: UserSetting.fromJson(
            Map<String, dynamic>.from(data['setting'] as Map),
          ).copyWith(userHash: _normalizedUserHash),
          pendingToken: data['pending_sync'] as String?,
          intent: data['latest_intent'] as String?,
          revision: data['server_revision'] as int,
        );
      } on FormatException {
        // 읽을 수 없는 스냅샷은 마지막 호환 사본으로 복원한다.
      } on TypeError {
        // 구형 또는 손상된 스냅샷도 기존 계정별 값을 버리지 않는다.
      }
    }
    return (
      setting: _readCachedUserSetting(preferences),
      pendingToken: preferences.getString(
        _key(UserSettingPreference.pendingSync),
      ),
      intent: preferences.getString(_key(UserSettingPreference.latestIntent)),
      revision:
          preferences.getInt(_key(UserSettingPreference.serverRevision)) ?? 0,
    );
  }

  // 함수이름: _writeState
  // 함수역할: 설정·대기 토큰·리비전을 하나의 스냅샷으로 먼저 저장한 뒤 호환 키를 갱신한다.
  // 매개변수: preferences: 대상 저장소; state: 함께 저장할 계정 상태.
  // 반환값: 완료 Future; 스냅샷 저장 거절은 StateError, 이후 호환 키 기록 실패는 전파한다.
  Future<void> _writeState(
    SharedPreferences preferences,
    _SettingState state,
  ) async {
    final saved = await preferences.setString(
      _key(UserSettingPreference.snapshot),
      jsonEncode({
        'setting': state.setting.toJson(includeDevicePreferences: true),
        'pending_sync': state.pendingToken,
        'latest_intent': state.intent,
        'server_revision': state.revision,
      }),
    );
    if (!saved) throw StateError('User setting snapshot could not be saved.');
    if (state.pendingToken == null) {
      await preferences.remove(_key(UserSettingPreference.pendingSync));
    } else {
      await preferences.setString(
        _key(UserSettingPreference.pendingSync),
        state.pendingToken!,
      );
    }
    if (state.intent != null) {
      await preferences.setString(
        _key(UserSettingPreference.latestIntent),
        state.intent!,
      );
    }
    await preferences.setInt(
      _key(UserSettingPreference.serverRevision),
      state.revision,
    );
    await _cacheUserSetting(state.setting);
  }

  // Function Name: _loadFreshPreferences
  // Description: Obtains preferences and attempts to reload writes made by other isolates.
  // Parameters: None.
  // Returns: A preferences instance after the reload attempt; instance acquisition errors propagate.
  Future<SharedPreferences> _loadFreshPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await _reloadPreferences(preferences);
    return preferences;
  }

  // Function Name: _reloadPreferences
  // Description: Attempts a disk reload while retaining the in-memory copy on reload failure.
  // Parameters: preferences: Store instance to refresh.
  // Returns: Completion after success or a logged failure.
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

  // Function Name: _nextPendingToken
  // Description: Creates a per-save marker so an older completion cannot clear a newer pending intent.
  // Parameters: None.
  // Returns: A timestamp-and-sequence string; not a cryptographic identifier.
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
          preferences.getInt(_key(UserSettingPreference.fontSize)) ??
          preferences.getInt(_legacyFontSizeKey) ??
          fallbackSetting.fontSize,
      medicationSearchMode:
          preferences.getString(
            _key(UserSettingPreference.medicationSearchMode),
          ) ??
          fallbackSetting.medicationSearchMode,
      readingSpeed:
          preferences.getDouble(_key(UserSettingPreference.readingSpeed)) ??
          preferences.getDouble(_legacyReadingSpeedKey) ??
          fallbackSetting.readingSpeed,
      // 서버 응답과 같은 기준으로 ko·en만 남겨 캐시 값이 화면마다 다르게 판정되지 않게 한다.
      language: normalizeAppLanguage(
        preferences.getString(_key(UserSettingPreference.language)) ??
            preferences.getString(_legacyLanguageKey) ??
            fallbackSetting.language,
      ),
      languageMode:
          preferences.getString(_key(UserSettingPreference.languageMode)) ??
          preferences.getString(_key(UserSettingPreference.language)) ??
          fallbackSetting.languageMode,
      timeFormat:
          preferences.getString(_key(UserSettingPreference.timeFormat)) ??
          fallbackSetting.timeFormat,
      medicationNotificationsEnabled:
          preferences.getBool(
            _key(UserSettingPreference.medicationNotificationsEnabled),
          ) ??
          fallbackSetting.medicationNotificationsEnabled,
      caregiverNotificationsEnabled:
          preferences.getBool(
            _key(UserSettingPreference.caregiverNotificationsEnabled),
          ) ??
          fallbackSetting.caregiverNotificationsEnabled,
      chatNotificationsEnabled:
          preferences.getBool(
            _key(UserSettingPreference.chatNotificationsEnabled),
          ) ??
          fallbackSetting.chatNotificationsEnabled,
      notificationDetailMode:
          preferences.getString(
            _key(UserSettingPreference.notificationDetailMode),
          ) ??
          fallbackSetting.notificationDetailMode,
      defaultMorningTime:
          preferences.getString(
            _key(UserSettingPreference.defaultMorningTime),
          ) ??
          fallbackSetting.defaultMorningTime,
      defaultLunchTime:
          preferences.getString(_key(UserSettingPreference.defaultLunchTime)) ??
          fallbackSetting.defaultLunchTime,
      defaultEveningTime:
          preferences.getString(
            _key(UserSettingPreference.defaultEveningTime),
          ) ??
          fallbackSetting.defaultEveningTime,
      homeScheduleSource:
          preferences.getString(
                _key(UserSettingPreference.homeScheduleSource),
              ) ==
              'patients'
          ? 'patients'
          : 'self',
      defaultBedtime:
          preferences.getString(_key(UserSettingPreference.defaultBedtime)) ??
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
    await preferences.setString(
      _key(UserSettingPreference.medicationSearchMode),
      setting.medicationSearchMode,
    );
    await preferences.setInt(
      _key(UserSettingPreference.fontSize),
      setting.fontSize,
    );
    await preferences.setDouble(
      _key(UserSettingPreference.readingSpeed),
      setting.readingSpeed,
    );
    await preferences.setString(
      _key(UserSettingPreference.language),
      setting.language,
    );
    await preferences.setString(
      _key(UserSettingPreference.languageMode),
      setting.languageMode,
    );
    await preferences.setString(
      _key(UserSettingPreference.timeFormat),
      setting.timeFormat,
    );
    await preferences.setString(
      _key(UserSettingPreference.homeScheduleSource),
      setting.homeScheduleSource,
    );
    await preferences.setBool(
      _key(UserSettingPreference.medicationNotificationsEnabled),
      setting.medicationNotificationsEnabled,
    );
    await preferences.setBool(
      _key(UserSettingPreference.caregiverNotificationsEnabled),
      setting.caregiverNotificationsEnabled,
    );
    await preferences.setBool(
      _key(UserSettingPreference.chatNotificationsEnabled),
      setting.chatNotificationsEnabled,
    );
    await preferences.setString(
      _key(UserSettingPreference.notificationDetailMode),
      setting.notificationDetailMode,
    );
    await preferences.setString(
      _key(UserSettingPreference.defaultMorningTime),
      setting.defaultMorningTime,
    );
    await preferences.setString(
      _key(UserSettingPreference.defaultLunchTime),
      setting.defaultLunchTime,
    );
    await preferences.setString(
      _key(UserSettingPreference.defaultEveningTime),
      setting.defaultEveningTime,
    );
    await preferences.setString(
      _key(UserSettingPreference.defaultBedtime),
      setting.defaultBedtime,
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

  // Function Name: _key
  // Description: Builds the preference key within the normalized current account scope.
  // Parameters: preference: UserSettingPreference to address.
  // Returns: The account-specific persistence key.
  String _key(UserSettingPreference preference) =>
      preference.keyFor(_normalizedUserHash);

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
