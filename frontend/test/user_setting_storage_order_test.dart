// 같은 isolate의 원격 컨트롤 간 저장 순서와 로컬 전용 조회의 스냅샷 우선순위를 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _owner = 'storage-owner-a';
const _on = UserSetting(userHash: _owner);
const _off = UserSetting(
  userHash: _owner,
  fontSize: 20,
  language: 'en',
  languageMode: 'en',
  medicationNotificationsEnabled: false,
  notificationDetailMode: 'type_only',
);
const _limit = Duration(seconds: 3);

String _key(String owner, String field) =>
    'flutter.user_setting_${owner}_$field';

class _WriteGate {
  final String key;
  final bool afterWrite;
  final entered = Completer<void>();
  final released = Completer<void>();
  bool claimed = false;

  _WriteGate(this.key, {this.afterWrite = false});

  void release() {
    if (!released.isCompleted) released.complete();
  }
}

// 실제 SharedPreferences의 캐시·reload는 유지하고 플랫폼의 쓰기 완료만 멈춘다.
class _GatedPreferences extends InMemorySharedPreferencesStore {
  _WriteGate? gate;

  _GatedPreferences(super.data) : super.withData();

  _WriteGate pause(String key, {bool afterWrite = false}) {
    final next = _WriteGate(key, afterWrite: afterWrite);
    gate = next;
    return next;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final current = gate;
    if (current == null || current.claimed || key != current.key) {
      return super.setValue(valueType, key, value);
    }
    current.claimed = true;
    if (current.afterWrite) await super.setValue(valueType, key, value);
    current.entered.complete();
    await current.released.future;
    if (current.afterWrite) return true;
    return super.setValue(valueType, key, value);
  }
}

http.Response _success(UserSetting setting, int revision) => http.Response(
  jsonEncode({'success': true, 'data': setting.toJson(), 'revision': revision}),
  200,
);

Future<Map<String, dynamic>> _snapshot(
  _GatedPreferences storage, {
  String owner = _owner,
}) async {
  final persisted = await storage.getAll();
  return jsonDecode(persisted[_key(owner, 'snapshot')]! as String)
      as Map<String, dynamic>;
}

Future<void> _expectPendingOff(_GatedPreferences storage) async {
  final state = await _snapshot(storage);
  expect(state['setting'], _off.toJson());
  expect(
    state['pending_sync'],
    isA<String>().having((value) => value.isNotEmpty, 'nonempty', isTrue),
  );
  expect(state['pending_sync'], state['latest_intent']);
  final persisted = await storage.getAll();
  expect(persisted[_key(_owner, 'pending_sync')], state['pending_sync']);
  expect(persisted[_key(_owner, 'medication_notifications_enabled')], isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previousPlatform;
  late _GatedPreferences storage;

  setUp(() {
    previousPlatform = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    storage = _GatedPreferences({
      _key(_owner, 'medication_notifications_enabled'): true,
      _key(_owner, 'server_revision'): 0,
    });
    SharedPreferencesStorePlatform.instance = storage;
  });

  tearDown(() {
    storage.gate?.release();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousPlatform;
  });

  test('pending publication cannot retry the previous payload', () async {
    final gate = storage.pause(_key(_owner, 'pending_sync'), afterWrite: true);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('offline', 503);
    });
    addTearDown(client.close);
    final writer = ManageUserSetting(userHash: _owner, client: client);
    final retry = ManageUserSetting(userHash: _owner, client: client);
    final saving = writer.saveUserSetting(_off);
    Future<UserSetting>? reading;
    try {
      await gate.entered.future.timeout(_limit);
      final staged = await _snapshot(storage);
      expect(staged['setting'], _off.toJson());
      expect(staged['pending_sync'], staged['latest_intent']);
      var retryFinished = false;
      reading = retry.requestUserSetting().then((setting) {
        retryFinished = true;
        return setting;
      });
      // 즉시 완료되는 플랫폼/HTTP 대역의 microtask를 소진해 잠금 대기를 확인한다.
      await Future<void>.delayed(Duration.zero);
      expect(retryFinished, isFalse);
      expect(requests, isEmpty);
    } finally {
      gate.release();
      await saving;
      if (reading != null) await reading;
    }
    expect((await saving).synchronizedWithServer, isFalse);
    expect((await reading).toJson(), _off.toJson());
    expect(requests, isNotEmpty);
    for (final request in requests) {
      expect(request.method, 'PUT');
      expect(
        (jsonDecode(request.body) as Map)['medication_notifications_enabled'],
        isFalse,
      );
    }
    await _expectPendingOff(storage);
    expect(writer.hasPendingSave, isTrue);
    expect(retry.hasPendingSave, isTrue);
  });

  for (final responseKind in ['ACK', 'GET']) {
    for (final pausedField in ['snapshot', 'font_size']) {
      test(
        'old $responseKind during $pausedField write preserves newer failed OFF',
        () async {
          final ready = Completer<_WriteGate>();
          var firstResponse = true;
          final client = MockClient((request) async {
            if (firstResponse) {
              firstResponse = false;
              expect(request.method, responseKind == 'ACK' ? 'PUT' : 'GET');
              ready.complete(storage.pause(_key(_owner, pausedField)));
              return _success(_on, responseKind == 'ACK' ? 1 : 0);
            }
            expect(request.method, 'PUT');
            return http.Response('offline', 503);
          });
          addTearDown(client.close);
          final older = ManageUserSetting(userHash: _owner, client: client);
          final newer = ManageUserSetting(userHash: _owner, client: client);
          final Future<Object> oldRequest = responseKind == 'ACK'
              ? older.saveUserSetting(_on)
              : older.requestUserSetting();
          Future<UserSettingSaveResult>? newRequest;
          _WriteGate? gate;
          try {
            gate = await ready.future.timeout(_limit);
            await gate.entered.future.timeout(_limit);
            var newerFinished = false;
            newRequest = newer.saveUserSetting(_off).then((result) {
              newerFinished = true;
              return result;
            });
            await Future<void>.delayed(Duration.zero);
            expect(newerFinished, isFalse);
          } finally {
            gate?.release();
            await oldRequest;
            if (newRequest != null) await newRequest;
          }
          final latest = await newRequest;
          expect(latest.synchronizedWithServer, isFalse);
          expect(latest.setting.toJson(), _off.toJson());
          expect(newer.hasPendingSave, isTrue);
          await _expectPendingOff(storage);
          expect(
            (await _snapshot(storage))['server_revision'],
            responseKind == 'ACK' ? 1 : 0,
          );
        },
      );
    }
  }

  test('an account waiting on storage does not lock another account', () async {
    const otherOwner = 'storage-owner-b';
    final gate = storage.pause(_key(_owner, 'snapshot'));
    final sentOwners = <String>[];
    final client = MockClient((request) async {
      final owner = request.url.queryParameters['user_hash']!;
      sentOwners.add(owner);
      if (owner == _owner) return http.Response('offline', 503);
      final setting = UserSetting.fromJson(
        jsonDecode(request.body) as Map<String, dynamic>,
      );
      return _success(setting, 1);
    });
    addTearDown(client.close);
    final waiting = ManageUserSetting(userHash: _owner, client: client);
    final independent = ManageUserSetting(userHash: otherOwner, client: client);
    final saving = waiting.saveUserSetting(_off);
    Future<UserSettingSaveResult>? otherSaving;
    try {
      await gate.entered.future.timeout(_limit);
      otherSaving = independent.saveUserSetting(
        _off.copyWith(userHash: otherOwner),
      );
      expect(
        (await otherSaving.timeout(_limit)).synchronizedWithServer,
        isTrue,
      );
      expect(sentOwners, [otherOwner]);
      final otherState = await _snapshot(storage, owner: otherOwner);
      expect(otherState['pending_sync'], isNull);
      expect(
        otherState['setting'],
        _off.copyWith(userHash: otherOwner).toJson(),
      );
    } finally {
      gate.release();
      await saving;
      if (otherSaving != null) await otherSaving;
    }
    await _expectPendingOff(storage);
  });

  test(
    'local-only readers trust the snapshot over partially mirrored fields',
    () async {
      final state = {
        'setting': _off.toJson(),
        'pending_sync': 'staged-off',
        'latest_intent': 'staged-off',
        'server_revision': 7,
      };
      await storage.setValue(
        'String',
        _key(_owner, 'snapshot'),
        jsonEncode(state),
      );
      await storage.setValue('Int', _key(_owner, 'font_size'), _on.fontSize);
      await storage.setValue('String', _key(_owner, 'language'), _on.language);
      await storage.setValue('String', _key(_owner, 'pending_sync'), 'old-on');
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('unexpected', 500);
      });
      addTearDown(client.close);
      final local = ManageUserSetting(
        userHash: _owner,
        client: client,
        useRemotePersistence: false,
      );
      expect((await local.requestUserSetting()).toJson(), _off.toJson());
      expect(requests, 0);
      expect(await _snapshot(storage), state);
    },
  );
}
