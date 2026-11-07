// 파일명: user_setting_sync_revision_test.dart
// 역할: 설정 저장의 시간 초과, 응답 역전, 재시작 후 재전송을 검증한다.
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

// 클래스명: _SettingsServer
// 역할: 기대 리비전이 일치하는 저장만 승인하는 메모리 설정 서버 대역이다.
// 주요 책임:
// - 조회 스냅샷을 만들고 쓰기 요청을 기록하며 충돌 시 현재 리비전을 반환한다.
// 속성:
// - setting(UserSetting): 마지막 승인 설정; 처음에는 알림 켜짐 상태이다.
// - revision(int): 승인 저장 때마다 증가하는 서버 버전.
// - writes(List<Map<String, dynamic>>): 실패한 충돌 요청까지 포함한 쓰기 본문 목록.
class _SettingsServer {
  UserSetting setting = _on;
  int revision = 0;
  final writes = <Map<String, dynamic>>[];

  // 함수이름: read
  // 함수역할:
  // - 현재 설정과 서버 버전을 성공 응답으로 직렬화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - http.Response: 호출 시점의 설정 스냅샷을 담은 200 JSON 응답.
  http.Response read() => http.Response(
    jsonEncode({
      'success': true,
      'data': setting.toJson(),
      'revision': revision,
    }),
    200,
  );

  // 함수이름: write
  // 함수역할:
  // - 본문을 기록한 뒤 기대 버전이 맞을 때만 설정을 교체하고 리비전을 증가시킨다.
  // 매개변수:
  // - request(http.Request): expected_revision과 설정 값을 담은 JSON 요청.
  // 반환값:
  // - http.Response: 성공하면 최신 200 스냅샷, 버전 불일치면 현재 버전을 담은 409 응답.
  // - JSON 해석이나 설정 변환 오류는 호출자에게 전달된다.
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

// 함수이름: main
// 함수역할:
// - 버전 충돌·지연 성공·지연 조회에서 최신 설정과 미전송 표시 보존 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 이전 테스트의 스냅샷·대기 토큰·호환 키를 제거한 환경설정 대역을 설치한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 각 사례가 필요한 저장 상태를 직접 구성한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: test 콜백
  // 함수역할:
  // - 오래된 개별 키보다 원자 스냅샷의 알림 끄기·대기 토큰을 우선 복원하고 버전 1로 재전송한 뒤 대기 상태를 해제하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
    // 함수이름: test 콜백
    // 함수역할:
    // - 스냅샷 JSON 또는 setting 타입이 손상되면 계정별 호환 키의 알림 끄기 값을 읽어 설정을 초기화하지 않는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 이전 켜기 요청이 시간 초과된 뒤 끄기를 승인하고 늦은 켜기 요청을 해제해도 서버·조회 설정은 꺼짐이며 추가 승인 버전이 생기지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 두 제어기 중 이전 켜기 요청이 늦게 충돌해도 최신 끄기 설정을 반환하며 오래된 의도를 추가 전송하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 이전 켜기의 서버 승인 뒤 응답만 늦추고 끄기를 충돌 재시도로 승인해도 늦은 성공 결과는 최신 꺼짐 설정을 반환하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 켜짐 조회 스냅샷을 대기시킨 사이 다른 제어기가 끄기를 저장하면 조회 결과와 이후 로컬 조회 모두 꺼짐을 유지하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 대기 저장을 구버전 1로 재전송해 충돌하면 서버 버전 3으로 다시 보내 꺼짐 설정을 승인하고 대기 표시를 지우는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 모든 저장이 새 버전으로 충돌해도 세 번만 요청하고 로컬 꺼짐 값과 미동기화 상태는 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
