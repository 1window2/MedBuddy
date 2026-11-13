// 파일명: user_setting_storage_order_test.dart
// 역할: 같은 isolate의 원격 컨트롤 간 저장 순서와 로컬 전용 조회의 스냅샷 우선순위를 검증한다.
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

// 함수이름: _key
// 함수역할:
// - 플랫폼 저장소의 flutter 접두사까지 포함한 계정별 설정 키를 만든다.
// 매개변수:
// - owner(String): 설정 소유 계정.
// - field(String): snapshot, pending_sync 등 설정 항목 이름.
// 반환값:
// - String: 다른 계정과 구분되는 SharedPreferences 플랫폼 키.
String _key(String owner, String field) =>
    'flutter.user_setting_${owner}_$field';

// 클래스명: _WriteGate
// 역할: 특정 환경설정 쓰기 한 번의 시작과 해제를 제어한다.
// 주요 책임:
// - 쓰기 전 또는 후 대기를 지정하고 종료 시 중복 해제를 허용한다.
// 속성:
// - key(String): 지연 대상 플랫폼 키.
// - afterWrite(bool): 실제 저장 후 완료만 지연할지 여부.
// - entered / released(Completer<void>): 진입 및 재개 신호.
// - claimed(bool): 대상 쓰기를 이미 한 번 가로챘는지 여부.
class _WriteGate {
  final String key;
  final bool afterWrite;
  final entered = Completer<void>();
  final released = Completer<void>();
  bool claimed = false;

  // 함수이름: _WriteGate
  // 함수역할:
  // - 대상 키와 지연 단계를 보관하고 아직 사용하지 않은 대기 신호를 만든다.
  // 매개변수:
  // - key(String): 지연할 저장 키.
  // - afterWrite(bool): true이면 실제 저장 뒤, false이면 저장 전에 대기한다.
  // 반환값:
  // - _WriteGate: 최초 일치 쓰기만 지연하는 제어 신호.
  _WriteGate(this.key, {this.afterWrite = false});

  // 함수이름: release
  // 함수역할:
  // - 아직 완료하지 않은 재개 신호를 완료해 대기 중 쓰기를 진행시킨다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 반복 호출은 추가 동작 없이 무시한다.
  void release() {
    if (!released.isCompleted) released.complete();
  }
}

// 실제 SharedPreferences의 캐시·reload는 유지하고 플랫폼의 쓰기 완료만 멈춘다.
// 클래스명: _GatedPreferences
// 역할: SharedPreferences 플랫폼 쓰기 한 번을 지연하는 메모리 저장소이다.
// 주요 책임:
// - 캐시·reload 동작은 유지하면서 특정 키의 쓰기 완료 시점을 분리한다.
// 속성:
// - gate(_WriteGate?): 다음 일치 쓰기에 적용할 선택적 지연 조건.
class _GatedPreferences extends InMemorySharedPreferencesStore {
  _WriteGate? gate;

  // 함수이름: _GatedPreferences
  // 함수역할:
  // - 초기 플랫폼 키와 값을 상위 메모리 저장소에 주입한다.
  // 매개변수:
  // - data(Map<String, Object>): 테스트 시작 시 존재할 환경설정 값.
  // 반환값:
  // - _GatedPreferences: 초기 지연 조건이 없는 저장소.
  _GatedPreferences(super.data) : super.withData();

  // 함수이름: pause
  // 함수역할:
  // - 다음 일치 쓰기를 가로챌 새 대기 조건으로 gate를 교체한다.
  // 매개변수:
  // - key(String): 지연 대상 플랫폼 키.
  // - afterWrite(bool): 실제 쓰기를 먼저 반영할지 여부.
  // 반환값:
  // - _WriteGate: 진입 대기와 해제에 사용할 신호; 이전 gate는 자동 해제하지 않는다.
  _WriteGate pause(String key, {bool afterWrite = false}) {
    final next = _WriteGate(key, afterWrite: afterWrite);
    gate = next;
    return next;
  }

  // 함수이름: setValue
  // 함수역할:
  // - 조건에 맞는 최초 쓰기만 지연하고 다른 키나 이후 호출은 상위 저장소로 바로 전달한다.
  // 매개변수:
  // - valueType(String): 플랫폼 환경설정 타입 이름.
  // - key(String): 저장할 플랫폼 키.
  // - value(Object): 저장할 값.
  // 반환값:
  // - Future<bool>: 실제 저장 결과; afterWrite 대기는 이미 반영된 저장을 true로 완료한다.
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

// 함수이름: _success
// 함수역할:
// - 설정과 서버 버전을 성공 조회·저장 응답 형식으로 묶는다.
// 매개변수:
// - setting(UserSetting): 응답에 넣을 설정 스냅샷.
// - revision(int): 해당 설정의 서버 버전.
// 반환값:
// - http.Response: success가 true인 200 JSON 응답.
http.Response _success(UserSetting setting, int revision) => http.Response(
  jsonEncode({'success': true, 'data': setting.toJson(), 'revision': revision}),
  200,
);

// 함수이름: _snapshot
// 함수역할:
// - 플랫폼 전체 값을 읽어 지정 계정의 원자 스냅샷 JSON을 해석한다.
// 매개변수:
// - storage(_GatedPreferences): 실제 기록된 값을 확인할 메모리 플랫폼.
// - owner(String): 조회할 계정; 기본값은 공통 테스트 계정이다.
// 반환값:
// - Future<Map<String, dynamic>>: 저장된 스냅샷; 누락·잘못된 타입·손상 JSON은 오류로 드러난다.
Future<Map<String, dynamic>> _snapshot(
  _GatedPreferences storage, {
  String owner = _owner,
}) async {
  final persisted = await storage.getAll();
  return jsonDecode(persisted[_key(owner, 'snapshot')]! as String)
      as Map<String, dynamic>;
}

// 함수이름: _expectPendingOff
// 함수역할:
// - 꺼짐 스냅샷과 비어 있지 않은 최신 대기 토큰이 서로 일치하며 호환 키도 동일한 의도를 가리키는지 검증한다.
// 매개변수:
// - storage(_GatedPreferences): 원자 스냅샷과 호환 키를 조회할 저장소.
// 반환값:
// - Future<void>: 값·토큰 일치 검증 완료; 차이가 있으면 테스트가 실패한다.
Future<void> _expectPendingOff(_GatedPreferences storage) async {
  final state = await _snapshot(storage);
  expect(state['setting'], _off.toJson(includeDevicePreferences: true));
  expect(
    state['pending_sync'],
    isA<String>().having((value) => value.isNotEmpty, 'nonempty', isTrue),
  );
  expect(state['pending_sync'], state['latest_intent']);
  final persisted = await storage.getAll();
  expect(persisted[_key(_owner, 'pending_sync')], state['pending_sync']);
  expect(persisted[_key(_owner, 'medication_notifications_enabled')], isFalse);
}

// 함수이름: main
// 함수역할:
// - 환경설정 쓰기를 단계별로 지연해 최신 의도 공개 순서와 계정별 저장 격리를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previousPlatform;
  late _GatedPreferences storage;

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 원래 플랫폼을 보관하고 정적 캐시를 비운 뒤 알림 켜짐·리비전 0의 제어 가능한 저장소를 설치한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 각 사례에 독립 플랫폼 저장소를 제공한다.
  setUp(() {
    previousPlatform = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    storage = _GatedPreferences({
      _key(_owner, 'medication_notifications_enabled'): true,
      _key(_owner, 'server_revision'): 0,
    });
    SharedPreferencesStorePlatform.instance = storage;
  });

  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 남은 쓰기 대기를 해제하고 정적 캐시를 비운 뒤 원래 환경설정 플랫폼을 복원한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 테스트의 플랫폼 교체와 대기 상태를 정리한다.
  tearDown(() {
    storage.gate?.release();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousPlatform;
  });

  // 함수이름: test callback
  // 함수역할:
  // - 대기 토큰의 플랫폼 쓰기 완료를 멈추면 다른 제어기의 재전송은 잠금을 기다리고, 해제 후 모든 PUT과 대기 스냅샷이 최신 꺼짐 값을 쓰는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
      expect(staged['setting'], _off.toJson(includeDevicePreferences: true));
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
      // 함수이름: test callback
      // 함수역할:
      // - 오래된 승인·조회가 스냅샷 또는 호환 필드를 저장 중이면 최신 저장은 기다리며, 이후 네트워크 실패에도 최신 꺼짐과 대기 토큰·서버 버전을 보존하는지 검증한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 한 계정의 스냅샷 쓰기가 멈춰도 다른 계정은 독립적으로 저장·동기화를 완료하며 각 계정의 대기 상태를 섞지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
        _off
            .copyWith(userHash: otherOwner)
            .toJson(includeDevicePreferences: true),
      );
    } finally {
      gate.release();
      await saving;
      if (otherSaving != null) await otherSaving;
    }
    await _expectPendingOff(storage);
  });

  // 함수이름: test callback
  // 함수역할:
  // - 호환 키에 이전 글꼴·언어·대기 토큰이 남아도 로컬 전용 조회는 원자 스냅샷을 우선하고 네트워크 요청이나 스냅샷 변경을 하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
