// 파일명: medication_search_setting_test.dart
// 역할: 약 검색 모드의 정규화·기기 전용 저장·계정 격리와 원격 요청 중 병합을 검증한다.
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

// 함수이름: main
// 함수역할: 검색 모드의 생성·직렬화·복원과 원격 조회/저장 경합 회귀 테스트를 등록한다.
// 매개변수: 없음.
// 반환값: 없음. 테스트 바인딩과 사례를 준비한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp
  // 함수역할: 각 사례 전에 모의 기기 설정을 비워 이전 계정·전송 상태가 남지 않게 한다.
  // 매개변수: 없음.
  // 반환값: 없음. 빈 SharedPreferences 저장소.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: test: '검색 모드는 모든 생성 경로에서 정규화하고 구형 값은 보통으로 복원한다'
  // 함수역할: null·잘못된 값·구형 accurate와 공백/대소문자가 섞인 모드를 생성자·JSON·copyWith 경로로 넣는다.
  // 매개변수: 없음.
  // 반환값: 없음. 잘못된 값은 balanced, 유효한 값은 정규화되며 null 복사는 기존 fast를 유지한다.
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

  // 함수이름: test: '기기 직렬화와 초안 비교에만 검색 모드를 포함한다'
  // 함수역할: thorough 설정의 기기 포함 JSON과 서버용 JSON 및 잘못된 모드의 초안 비교를 대조한다.
  // 매개변수: 없음.
  // 반환값: 없음. 모드는 기기 JSON에만 포함되고 잘못된 모드는 balanced와 동일하게 비교된다.
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

  // 함수이름: test: '모드만 바꾸면 통신하지 않고 재시작 뒤 계정별로 복원한다'
  // 함수역할: 통신하면 실패하는 클라이언트로 모드만 저장한 뒤 기기 저장소를 재생성하고 두 계정으로 읽는다.
  // 매개변수: 없음.
  // 반환값: 비동기 검증 완료. 통신·보류 저장 없이 owner만 fast를 복원하고 other는 balanced이다.
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

  // 함수이름: test: '기존 개별 키와 모드 없는 구형 스냅샷을 안전하게 읽는다'
  // 함수역할: 공백이 섞인 개별 키·잘못된 키 값과 모드 필드 없는 구형 스냅샷을 읽는다.
  // 매개변수: 없음.
  // 반환값: 비동기 검증 완료. 모드는 정규화/기본 복원되고 기존 글씨 크기 20은 유지된다.
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

  // 함수이름: test: '늦은 서버 조회는 최신 기기 검색 모드를 덮어쓰지 않는다'
  // 함수역할: GET 응답을 지연한 사이 모드를 thorough로 저장하고 글씨 크기 20의 서버 응답을 완료한다.
  // 매개변수: 없음.
  // 반환값: 비동기 검증 완료. 서버 글씨 크기와 최신 기기 모드가 병합되고 재조회에도 thorough가 유지된다.
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

  // 함수이름: test: '원격 저장 중 모드 변경은 전송 표시를 보존하고 응답에 병합한다'
  // 함수역할: PUT을 대기시킨 동안 fast를 thorough로 바꾸고 전송 메타데이터와 응답 후 복원을 확인한다.
  // 매개변수: 없음.
  // 반환값: 비동기 검증 완료. PUT은 한 번이며 보류 정보는 보존되고 완료 후 thorough와 동기화 성공 상태가 남는다.
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

  // 함수이름: test: '오프라인 저장 후 검색 모드를 바꿔도 재시작 재전송과 서버 조회에 보존한다'
  // 함수역할: 오프라인 PUT 실패 뒤 모드를 변경하고 온라인 재시작으로 보류 저장 재전송과 후속 GET을 수행한다.
  // 매개변수: 없음.
  // 반환값: 비동기 검증 완료. PUT·PUT·GET 순서에서도 서버 본문에 모드가 없고 thorough가 유지된다.
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

// 함수이름: _expectNoDeviceMode
// 함수역할: 서버 사용자 설정 본문에 기기 검색 모드와 검색 요청 전용 필드가 섞이지 않았는지 단언한다.
// 매개변수: body (Map<String, dynamic>): 검사할 요청/응답 설정 본문.
// 반환값: 없음. 세 검색 모드 키가 하나라도 있으면 테스트 실패.
void _expectNoDeviceMode(Map<String, dynamic> body) {
  for (final key in [
    'medication_search_mode',
    'medicationSearchMode',
    'search_mode',
  ]) {
    expect(body, isNot(contains(key)));
  }
}
