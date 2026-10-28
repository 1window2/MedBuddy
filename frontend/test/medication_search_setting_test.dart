// 파일명: medication_search_setting_test.dart
// 역할: 약품 검색 모드의 정규화와 계정별 기기 저장·서버 응답 병합을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/user_setting_preference_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('검색 모드는 모든 생성 경로에서 정규화하고 구형 값은 보통으로 복원한다', () {
    const cases = <String?, String>{
      null: 'balanced',
      '': 'balanced',
      'unknown': 'balanced',
      'accurate': 'balanced',
      ' Fast ': 'fast',
      ' BALANCED ': 'balanced',
      '\tTHOROUGH\n': 'thorough',
    };
    expect(const UserSetting().medicationSearchMode, 'balanced');
    expect(UserSetting.fromJson({}).medicationSearchMode, 'balanced');
    expect(
      UserSetting.fromJson({
        'medication_search_mode': 123,
      }).medicationSearchMode,
      'balanced',
    );
    for (final entry in cases.entries) {
      expect(normalizeMedicationSearchMode(entry.key), entry.value);
      for (final key in ['medication_search_mode', 'medicationSearchMode']) {
        expect(
          UserSetting.fromJson({key: entry.key}).medicationSearchMode,
          entry.value,
        );
      }
      if (entry.key != null) {
        final setting = UserSetting(medicationSearchMode: entry.key!);
        expect(setting.medicationSearchMode, entry.value);
        expect(
          setting.copyWith(fontSize: 20).medicationSearchMode,
          entry.value,
        );
        expect(
          const UserSetting()
              .copyWith(medicationSearchMode: entry.key)
              .medicationSearchMode,
          entry.value,
        );
      }
    }
    const retained = UserSetting(medicationSearchMode: 'fast');
    expect(
      retained.copyWith(medicationSearchMode: null).medicationSearchMode,
      'fast',
    );
  });

  test('기기 직렬화와 초안 비교에만 검색 모드를 포함한다', () {
    const balanced = UserSetting();
    const thorough = UserSetting(medicationSearchMode: ' THOROUGH ');
    final deviceJson = thorough.toJson(includeDevicePreferences: true);
    expect(deviceJson['medication_search_mode'], 'thorough');
    expect(UserSetting.fromJson(deviceJson).medicationSearchMode, 'thorough');
    expect(thorough.toJson(), isNot(contains('medication_search_mode')));
    expect(thorough.toJson(), balanced.toJson());
    expect(
      mapEquals(balanced.toJson(includeDevicePreferences: true), deviceJson),
      isFalse,
    );
    expect(
      mapEquals(
        const UserSetting(
          medicationSearchMode: 'invalid',
        ).toJson(includeDevicePreferences: true),
        balanced.toJson(includeDevicePreferences: true),
      ),
      isTrue,
    );
  });

  test('모드만 바꾸면 통신하지 않고 재시작 뒤 계정별로 복원한다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw StateError('offline');
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'owner', client: client);
    final saved = await control.saveUserSetting(
      const UserSetting(medicationSearchMode: ' FAST '),
    );
    expect(saved.setting.medicationSearchMode, 'fast');
    expect(calls, 0);
    expect(control.hasPendingSave, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        UserSettingPreference.medicationSearchMode.keyFor('owner'),
      ),
      'fast',
    );
    SharedPreferences.setMockInitialValues({
      for (final key in preferences.getKeys()) key: preferences.get(key)!,
    });
    for (final owner in ['owner', 'other']) {
      final restored = ManageUserSetting(
        userHash: owner,
        useRemotePersistence: false,
        client: client,
      );
      expect(
        (await restored.requestUserSetting()).medicationSearchMode,
        owner == 'owner' ? 'fast' : 'balanced',
      );
    }
  });

  test('기존 개별 키와 모드 없는 구형 스냅샷을 안전하게 읽는다', () async {
    final client = MockClient((_) async => http.Response('{}', 500));
    addTearDown(client.close);
    final control = ManageUserSetting(
      userHash: 'owner',
      useRemotePersistence: false,
      client: client,
    );
    for (final raw in [' THOROUGH ', 'invalid']) {
      SharedPreferences.setMockInitialValues({
        UserSettingPreference.medicationSearchMode.keyFor('owner'): raw,
      });
      expect(
        (await control.requestUserSetting()).medicationSearchMode,
        normalizeMedicationSearchMode(raw),
      );
    }
    SharedPreferences.setMockInitialValues({
      UserSettingPreference.snapshot.keyFor('owner'): jsonEncode({
        'setting': {'font_size': 20},
        'pending_sync': null,
        'latest_intent': null,
        'server_revision': 3,
      }),
    });
    final old = await control.requestUserSetting();
    expect(old.medicationSearchMode, 'balanced');
    expect(old.fontSize, 20);
  });

  test('늦은 서버 조회는 최신 기기 검색 모드를 덮어쓰지 않는다', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final client = MockClient((request) {
      expect(request.method, 'GET');
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'owner', client: client);
    final lookup = control.requestUserSetting();
    await started.future;
    await control.saveUserSetting(
      const UserSetting(medicationSearchMode: 'thorough'),
    );
    response.complete(
      http.Response(
        jsonEncode({
          'data': {'font_size': 20},
          'revision': 2,
        }),
        200,
      ),
    );
    final restored = await lookup;
    expect(restored.medicationSearchMode, 'thorough');
    expect(restored.fontSize, 20);
    final local = ManageUserSetting(
      userHash: 'owner',
      useRemotePersistence: false,
      client: client,
    );
    expect((await local.requestUserSetting()).medicationSearchMode, 'thorough');
  });

  test('원격 저장 중 모드 변경은 전송 표시를 보존하고 응답에 병합한다', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'PUT');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _expectNoDeviceMode(body);
      started.complete();
      await release.future;
      return http.Response(jsonEncode({'data': body, 'revision': 1}), 200);
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'owner', client: client);
    final save = control.saveUserSetting(
      const UserSetting(fontSize: 20, medicationSearchMode: 'fast'),
    );
    await started.future;
    final preferences = await SharedPreferences.getInstance();
    final snapshotKey = UserSettingPreference.snapshot.keyFor('owner');
    final before = jsonDecode(preferences.getString(snapshotKey)!);
    await control.saveUserSetting(
      const UserSetting(fontSize: 20, medicationSearchMode: 'thorough'),
    );
    final after = jsonDecode(preferences.getString(snapshotKey)!);
    for (final key in ['pending_sync', 'latest_intent', 'server_revision']) {
      expect(after[key], before[key]);
    }
    expect(calls, 1);
    expect(control.hasPendingSave, isTrue);
    release.complete();
    final saved = await save;
    expect(saved.setting.medicationSearchMode, 'thorough');
    expect(saved.synchronizedWithServer, isTrue);
    expect(control.hasPendingSave, isFalse);
    final local = ManageUserSetting(
      userHash: 'owner',
      useRemotePersistence: false,
      client: client,
    );
    expect((await local.requestUserSetting()).medicationSearchMode, 'thorough');
  });

  test('오프라인 저장 후 검색 모드를 바꿔도 재시작 재전송과 서버 조회에 보존한다', () async {
    var online = false;
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      if (!online) throw StateError('offline');
      final body = request.method == 'PUT'
          ? jsonDecode(request.body) as Map<String, dynamic>
          : const UserSetting(fontSize: 20).toJson();
      _expectNoDeviceMode(body);
      expect(body['font_size'], 20);
      return http.Response(jsonEncode({'data': body, 'revision': 1}), 200);
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'owner', client: client);
    final failed = await control.saveUserSetting(
      const UserSetting(fontSize: 20, medicationSearchMode: 'fast'),
    );
    expect(failed.synchronizedWithServer, isFalse);
    await control.saveUserSetting(
      failed.setting.copyWith(medicationSearchMode: 'thorough'),
    );
    expect(methods, ['PUT']);
    expect(control.hasPendingSave, isTrue);
    online = true;
    final restarted = ManageUserSetting(userHash: 'owner', client: client);
    expect(
      (await restarted.requestUserSetting()).medicationSearchMode,
      'thorough',
    );
    expect(restarted.hasPendingSave, isFalse);
    expect(
      (await restarted.requestUserSetting()).medicationSearchMode,
      'thorough',
    );
    expect(methods, ['PUT', 'PUT', 'GET']);
  });
}

// 함수역할: 사용자 설정 API에는 기기 전용 필드나 검색 요청 필드를 보내지 않는다.
void _expectNoDeviceMode(Map<String, dynamic> body) {
  for (final key in [
    'medication_search_mode',
    'medicationSearchMode',
    'search_mode',
  ]) {
    expect(body, isNot(contains(key)));
  }
}
