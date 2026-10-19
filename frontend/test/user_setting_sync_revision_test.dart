// 설정 저장의 시간 초과, 응답 역전, 재시작 후 재전송을 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _on = UserSetting(userHash: 'user-a');
const _off = UserSetting(
  userHash: 'user-a',
  medicationNotificationsEnabled: false,
);

class _SettingsServer {
  UserSetting setting = _on;
  int revision = 0;
  final writes = <Map<String, dynamic>>[];

  http.Response read() => http.Response(
    jsonEncode({
      'success': true,
      'data': setting.toJson(),
      'revision': revision,
    }),
    200,
  );

  http.Response write(http.Request request) {
    final data = jsonDecode(request.body) as Map<String, dynamic>;
    writes.add(data);
    if (data['expected_revision'] != revision) {
      return http.Response(
        jsonEncode({
          'detail': {
            'code': 'settings_revision_conflict',
            'revision': revision,
          },
        }),
        409,
      );
    }
    setting = UserSetting.fromJson(data);
    revision++;
    return read();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('호환 키 저장 전에 종료되어도 스냅샷의 설정과 대기 표시를 함께 복원한다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_medication_notifications_enabled': true,
      'user_setting_user-a_pending_sync': 'older-token',
      'user_setting_user-a_snapshot': jsonEncode({
        'setting': _off.toJson(),
        'pending_sync': 'latest-token',
        'latest_intent': 'latest-token',
        'server_revision': 1,
      }),
    });
    final server = _SettingsServer()..revision = 1;
    final client = MockClient((request) async => server.write(request));
    addTearDown(client.close);
    final local = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );
    addTearDown(local.dispose);
    expect(
      (await local.requestUserSetting()).medicationNotificationsEnabled,
      isFalse,
    );
    final restarted = ManageUserSetting(userHash: 'user-a', client: client);
    expect(
      (await restarted.requestUserSetting()).medicationNotificationsEnabled,
      isFalse,
    );
    expect(server.writes, hasLength(1));
    expect(server.writes.single['expected_revision'], 1);
    expect(restarted.hasPendingSave, isFalse);
  });

  for (final snapshot in ['broken-json', '{"setting":[]}']) {
    test('손상된 스냅샷은 기존 계정별 설정을 보존한다: $snapshot', () async {
      SharedPreferences.setMockInitialValues({
        'user_setting_user-a_snapshot': snapshot,
        'user_setting_user-a_medication_notifications_enabled': false,
      });
      final local = ManageUserSetting(
        userHash: 'user-a',
        useRemotePersistence: false,
      );
      addTearDown(local.dispose);
      expect(
        (await local.requestUserSetting()).medicationNotificationsEnabled,
        isFalse,
      );
    });
  }

  test('시간 초과된 이전 저장이 최신 알림 끄기를 되돌리지 않는다', () async {
    final server = _SettingsServer();
    final started = Completer<void>();
    final release = Completer<void>();
    final oldFinished = Completer<void>();
    var first = true;
    final client = MockClient((request) async {
      if (request.method == 'GET') return server.read();
      if (first) {
        first = false;
        started.complete();
        await release.future;
        final response = server.write(request);
        oldFinished.complete();
        return response;
      }
      return server.write(request);
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'user-a', client: client);
    final earlier = control.saveUserSetting(_on);
    await started.future;
    expect((await earlier).synchronizedWithServer, isFalse);
    expect(
      (await control.saveUserSetting(_off)).synchronizedWithServer,
      isTrue,
    );
    release.complete();
    await oldFinished.future;
    expect(server.setting.medicationNotificationsEnabled, isFalse);
    expect(server.revision, 1);
    expect(
      (await control.requestUserSetting()).medicationNotificationsEnabled,
      isFalse,
    );
    expect(control.hasPendingSave, isFalse);
  });

  test('오래된 충돌 응답은 최신 버전으로 재시도하지 않는다', () async {
    final server = _SettingsServer();
    final started = Completer<void>();
    final release = Completer<void>();
    var first = true;
    final client = MockClient((request) async {
      if (first) {
        first = false;
        started.complete();
        await release.future;
      }
      return server.write(request);
    });
    addTearDown(client.close);
    final older = ManageUserSetting(userHash: 'user-a', client: client);
    final newer = ManageUserSetting(userHash: 'user-a', client: client);
    final earlier = older.saveUserSetting(_on);
    await started.future;
    await newer.saveUserSetting(_off);
    release.complete();
    final late = await earlier;
    expect(late.setting.medicationNotificationsEnabled, isFalse);
    expect(server.setting.medicationNotificationsEnabled, isFalse);
    expect(server.writes, hasLength(2));
    expect(older.hasPendingSave, isFalse);
  });

  test('서버에는 먼저 저장됐지만 늦게 온 성공 응답도 최신 기기 값을 보존한다', () async {
    final server = _SettingsServer();
    final started = Completer<void>();
    final release = Completer<void>();
    var first = true;
    final client = MockClient((request) async {
      final response = server.write(request);
      if (first) {
        first = false;
        started.complete();
        await release.future;
      }
      return response;
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'user-a', client: client);
    final earlier = control.saveUserSetting(_on);
    await started.future;
    final latest = await control.saveUserSetting(_off);
    expect(latest.synchronizedWithServer, isTrue);
    release.complete();
    expect((await earlier).setting.medicationNotificationsEnabled, isFalse);
    expect(server.writes.map((body) => body['expected_revision']), [0, 0, 1]);
    expect(server.revision, 2);
    expect(control.hasPendingSave, isFalse);
  });

  test('저장이 끝난 뒤 도착한 이전 조회가 최신 캐시를 덮지 않는다', () async {
    final server = _SettingsServer();
    final started = Completer<void>();
    final release = Completer<void>();
    final client = MockClient((request) async {
      if (request.method == 'PUT') return server.write(request);
      final response = server.read();
      started.complete();
      await release.future;
      return response;
    });
    addTearDown(client.close);
    final reader = ManageUserSetting(userHash: 'user-a', client: client);
    final writer = ManageUserSetting(userHash: 'user-a', client: client);
    final earlier = reader.requestUserSetting();
    await started.future;
    await writer.saveUserSetting(_off);
    release.complete();
    expect((await earlier).medicationNotificationsEnabled, isFalse);
    final local = ManageUserSetting(
      userHash: 'user-a',
      useRemotePersistence: false,
    );
    addTearDown(local.dispose);
    expect(
      (await local.requestUserSetting()).medicationNotificationsEnabled,
      isFalse,
    );
  });

  test('재시작 후 남은 최신 저장은 충돌 버전으로 다시 보내고 완료한다', () async {
    SharedPreferences.setMockInitialValues({
      'user_setting_user-a_pending_sync': 'saved-offline',
      'user_setting_user-a_server_revision': 1,
      'user_setting_user-a_medication_notifications_enabled': false,
    });
    final server = _SettingsServer()..revision = 3;
    final client = MockClient((request) async => server.write(request));
    addTearDown(client.close);
    final worker = ManageUserSetting(userHash: 'user-a', client: client);
    expect(
      (await worker.requestUserSetting()).medicationNotificationsEnabled,
      isFalse,
    );
    expect(server.writes.map((body) => body['expected_revision']), [1, 3]);
    expect(server.revision, 4);
    expect(worker.hasPendingSave, isFalse);
  });

  test('계속 충돌하면 재시도를 제한하고 기기 저장은 대기로 남긴다', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        jsonEncode({
          'detail': {
            'code': 'settings_revision_conflict',
            'revision': requests,
          },
        }),
        409,
      );
    });
    addTearDown(client.close);
    final control = ManageUserSetting(userHash: 'user-a', client: client);
    final result = await control.saveUserSetting(_off);
    expect(requests, 3);
    expect(result.synchronizedWithServer, isFalse);
    expect(result.setting.medicationNotificationsEnabled, isFalse);
    expect(control.hasPendingSave, isTrue);
  });
}
