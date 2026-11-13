// 파일명: reminder_interaction_race_test.dart
// 역할: 알림 설정 저장과 진행 중인 예약·취소·권한 조회의 응답 순서 경합을 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_reminder_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

const _owner = 'reminder-race-patient';
const _cacheKey =
    'medbuddy_medication_reminder_patient_${_owner}_${_owner}_morning';
const _schedules = [
  MedicationSchedule(
    medicationID: '91',
    medicationName: '테스트정',
    scheduleSlotKeys: ['morning'],
  ),
];

// 함수이름: _alarm
// 함수역할:
// - 고정 환자의 아침 알림 서버 응답을 지정 시각과 활성 상태로 만든다.
// 매개변수:
// - hour(int): 정각 알림 시.
// - enabled(bool): 활성 여부; 기본 true.
// 반환값:
// - Map<String, Object>: 환자·시간대·시/분·활성 필드.
Map<String, Object> _alarm(int hour, {bool enabled = true}) => {
  'patient_hash': _owner,
  'slot_key': 'morning',
  'hour': hour,
  'minute': 0,
  'is_enabled': enabled,
};

// 함수이름: _response
// 함수역할:
// - 제공한 데이터를 성공 봉투로 감싼 UTF-8 JSON 응답을 만든다.
// 매개변수:
// - data(Object): data 필드에 넣을 JSON 인코딩 가능 값.
// 반환값:
// - http.Response: application/json, 상태 200의 성공 응답.
http.Response _response(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

// 함수이름: _model
// 함수역할:
// - 고정 환자와 신선한 일정 상태를 사용하는 알림 모델에 HTTP와 알림 기록기를 주입한다.
// 매개변수:
// - client(http.Client): 서버 응답과 순서를 제어할 클라이언트.
// - notifications(RecordingNotificationService): 예약·취소 기록기.
// - readSchedules(List<MedicationSchedule> Function()?): 실시간 일정 공급자; 생략하면 고정 일정.
// 반환값:
// - MedBuddyReminderViewModel: 변경 알림 콜백은 비활성인 독립 모델.
MedBuddyReminderViewModel _model(
  http.Client client,
  RecordingNotificationService notifications, {
  List<MedicationSchedule> Function()? readSchedules,
}) => MedBuddyReminderViewModel(
  setNotification: SetNotification(
    patientHash: _owner,
    client: client,
    notificationRegistrar: notifications.registerNotification,
  ),
  notificationService: notifications,
  patientHash: _owner,
  readUserSetting: () => const UserSetting(),
  readSchedules: readSchedules ?? () => _schedules,
  scheduleIsFresh: () => true,
  onChanged: (_) {},
);

// 함수이름: _save
// 함수역할:
// - 고정 아침 일정의 알림을 지정 정각에 저장한다.
// 매개변수:
// - model(MedBuddyReminderViewModel): 저장 대상 모델.
// - hour(int): 설정할 시; 분은 0.
// 반환값:
// - Future<bool>: 모델이 보고하는 저장 성공 여부.
Future<bool> _save(MedBuddyReminderViewModel model, int hour) =>
    model.requestMedicationReminderSave(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: hour,
      minute: 0,
      schedules: _schedules,
    );

// 클래스명: _PendingPermission
// 역할: 알림 권한 응답을 테스트가 원하는 시점까지 지연한다.
// 주요 책임: 계정 종료와 권한 응답의 순서를 재현한다.
// 속성: result는 권한 승인 여부를 완료할 제어기.
class _PendingPermission extends RecordingNotificationService {
  final result = Completer<bool>();

  // 함수이름: requestPermission
  // 함수역할:
  // - 테스트에서 result를 완료할 때까지 권한 요청을 대기시킨다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: result의 승인/거부 값 또는 주입 오류.
  @override
  Future<bool> requestPermission() => result.future;
}

// 클래스명: _PendingFirstCancellation
// 역할: 첫 알림 취소를 기록한 뒤 지연하는 알림 서비스.
// 주요 책임: 기존 취소와 후속 저장의 실행 순서를 검증할 경합 지점을 제공한다.
// 속성: started/release는 시작·해제 제어기, firstFinished는 첫 취소의 정상 완료 여부.
class _PendingFirstCancellation extends RecordingNotificationService {
  final started = Completer<void>();
  final release = Completer<void>();
  bool firstFinished = false;

  // 함수이름: cancelReminder
  // 함수역할:
  // - 취소를 상위 기록기에 남기고 첫 호출만 release까지 대기한다.
  // 매개변수:
  // - id(int): 취소할 알림 ID.
  // - slotKey(String?): 취소 기록에 전달할 시간대.
  // 반환값:
  // - Future<void>: 취소 완료; 첫 release가 오류이면 firstFinished를 변경하지 않고 오류를 전달한다.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    final first = cancellations.isEmpty;
    await super.cancelReminder(id, slotKey: slotKey);
    if (first) {
      started.complete();
      await release.future;
      firstFinished = true;
    }
  }
}

// 함수이름: main
// 함수역할:
// - 지연 알림 대역으로 오래된 동기화가 최신 사용자 설정을 덮지 않는지 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp
  // 함수역할:
  // - 이전 테스트의 알림 설정 캐시가 남지 않도록 모의 기기 저장소를 비운다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: 분 생략한 꺼짐 저장
  // 함수역할:
  // - 취소 PATCH가 19:00과 환자 쿼리를 전송하고 모델·캐시는 비활성 19:00을 유지하며 기기 예약 없이 취소만 수행하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('시만 지정한 꺼짐 저장은 정각으로 저장하고 성공으로 안내한다', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'PATCH');
      expect(
        request.url.path,
        endsWith('/notification/settings/morning/disable'),
      );
      expect(request.url.queryParameters['patient_hash'], _owner);
      expect(jsonDecode(request.body), {'hour': 19, 'minute': 0});
      return _response(_alarm(19, enabled: false));
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    addTearDown(model.dispose);

    expect(
      await model.requestMedicationReminderCancel(
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 19,
      ),
      isTrue,
    );
    expect(calls, 1);
    final setting = model.medicationReminderSettings['morning']!;
    expect(setting.timeLabel, '19:00');
    expect(setting.isEnabled, isFalse);
    expect(notifications.registrations, isEmpty);
    expect(notifications.cancellations, isNotEmpty);
    final preferences = await SharedPreferences.getInstance();
    final cached = jsonDecode(preferences.getString(_cacheKey)!) as Map;
    expect(cached['hour'], 19);
    expect(cached['minute'], 0);
    expect(cached['is_enabled'], isFalse);
  });

  for (final enabled in [true, false]) {
    // 함수이름: 진행 중 동기화와 새 저장 순서
    // 함수역할:
    // - 예약/취소 동기화의 첫 취소를 지연해도 새 저장이 이를 추월하지 않고 최종 예약·모델·캐시가 09:00 활성 상태인지 확인한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test('진행 중인 ${enabled ? '예약' : '취소'} 동기화가 새 저장을 뒤늦게 덮어쓰지 않는다', () async {
      final notifications = _PendingFirstCancellation();
      var writeOvertookCancellation = false;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return _response([_alarm(8, enabled: enabled)]);
        }
        writeOvertookCancellation = !notifications.firstFinished;
        return _response(_alarm(9));
      });
      addTearDown(client.close);
      final model = _model(client, notifications);
      addTearDown(model.dispose);
      await model.loadMedicationReminderSettings();
      final sync = model.synchronizeIfFresh();
      await notifications.started.future;
      final save = _save(model, 9);
      // 실제 취소가 끝나기 전에 새 저장의 비동기 연속 동작을 진행시킨다.
      await Future<void>.delayed(Duration.zero);
      notifications.release.complete();
      await sync;
      expect(await save, isTrue);
      expect(notifications.registrations.map((item) => item.hour), [9]);
      expect(notifications.cancellations, hasLength(2));
      expect(writeOvertookCancellation, isFalse);
      expect(model.medicationReminderSettings['morning']!.hour, 9);
      expect(model.medicationReminderSettings['morning']!.isEnabled, isTrue);
      final cached = jsonDecode(
        (await SharedPreferences.getInstance()).getString(_cacheKey)!,
      );
      expect(cached['hour'], 9);
      expect(cached['is_enabled'], isTrue);
    });
  }

  // 함수이름: 빈 시간대 비활성화와 사용자 저장
  // 함수역할:
  // - 빈 일정의 서버 비활성화를 먼저 완료한 뒤 사용자 저장을 적용해 서버·기기·캐시가 09:00 활성 상태로 남는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('빈 시간대의 진행 중인 서버 비활성화보다 사용자 저장이 나중에 적용된다', () async {
    final disableStarted = Completer<void>();
    final releaseDisable = Completer<void>();
    final applied = <String>[];
    var serverSetting = _alarm(8);
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([serverSetting]);
      if (request.method == 'PATCH') {
        disableStarted.complete();
        await releaseDisable.future;
        serverSetting = _alarm(8, enabled: false);
        applied.add('disable');
      } else {
        serverSetting = _alarm(9);
        applied.add('save');
      }
      return _response(serverSetting);
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    var schedules = <MedicationSchedule>[];
    final model = _model(client, notifications, readSchedules: () => schedules);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await disableStarted.future;
    schedules = _schedules;
    final save = _save(model, 9);
    await Future<void>.delayed(Duration.zero);
    releaseDisable.complete();
    await sync;
    expect(await save, isTrue);
    expect(applied, ['disable', 'save']);
    expect(serverSetting, _alarm(9));
    expect(notifications.registrations.map((item) => item.hour), [9]);
    expect(model.medicationReminderSettings['morning']!.hour, 9);
    final cached = jsonDecode(
      (await SharedPreferences.getInstance()).getString(_cacheKey)!,
    );
    expect(cached['hour'], 9);
    expect(cached['is_enabled'], isTrue);
  });

  // 함수이름: 이전 동기화 후 꺼짐 저장
  // 함수역할:
  // - 지연된 기존 예약 동기화 뒤 꺼짐 저장이 적용되어 새 기기 예약 없이 모델과 캐시가 비활성 19:00인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('이전 예약 동기화를 기다린 꺼짐 저장은 기기 예약과 캐시를 꺼진 상태로 유지한다', () async {
    final notifications = _PendingFirstCancellation();
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([_alarm(8)]);
      return _response(_alarm(19, enabled: false));
    });
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await notifications.started.future;
    final save = model.requestMedicationReminderCancel(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: 19,
      minute: 0,
    );
    await Future<void>.delayed(Duration.zero);
    notifications.release.complete();
    await sync;
    expect(await save, isTrue);
    expect(notifications.registrations, isEmpty);
    expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
    final cached = jsonDecode(
      (await SharedPreferences.getInstance()).getString(_cacheKey)!,
    );
    expect(cached['hour'], 19);
    expect(cached['is_enabled'], isFalse);
  });

  // 함수이름: 새 조회 세대의 후속 동기화
  // 함수역할:
  // - 이전 취소가 진행 중일 때 새 조회·동기화를 요청해도 최신 09:00 예약 하나가 적용되는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('진행 중인 동기화 뒤에 새 조회 세대의 동기화를 누락하지 않는다', () async {
    final notifications = _PendingFirstCancellation();
    var reads = 0;
    final client = MockClient(
      (_) async => _response([_alarm(++reads == 1 ? 8 : 9)]),
    );
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final oldSync = model.synchronizeIfFresh();
    await notifications.started.future;
    await model.loadMedicationReminderSettings();
    final newSync = model.synchronizeIfFresh();
    notifications.release.complete();
    await oldSync;
    await newSync;
    expect(notifications.registrations.map((item) => item.hour), [9]);
  });

  // 함수이름: 오래된 취소 실패 후 후속 작업
  // 함수역할:
  // - 무효화된 동기화의 취소 오류를 흡수한 뒤 대기 저장이 성공하고 추가 동기화도 09:00을 예약하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('무효화된 동기화의 취소 실패는 대기 중인 저장과 후속 동기화를 막지 않는다', () async {
    final notifications = _PendingFirstCancellation();
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([_alarm(8)]);
      return _response(_alarm(9));
    });
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await notifications.started.future;
    final save = _save(model, 9);
    await Future<void>.delayed(Duration.zero);
    notifications.release.completeError(StateError('취소 실패 테스트'));
    await sync;
    expect(await save, isTrue);
    expect(model.statusMessage, contains('설정되었습니다'));
    await model.synchronizeIfFresh();
    expect(notifications.registrations.map((item) => item.hour), [9, 9]);
  });

  // 함수이름: 늦은 조회와 꺼짐 저장
  // 함수역할:
  // - 꺼짐 저장 후 도착한 이전 활성 조회 결과를 무시해 모델과 캐시가 19:00 비활성 상태를 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('꺼짐 저장 뒤 도착한 이전 조회가 설정과 캐시를 되돌리지 않는다', () async {
    final pendingRead = Completer<http.Response>();
    final readStarted = Completer<void>();
    var reads = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        if (++reads == 1) return _response([_alarm(8)]);
        readStarted.complete();
        return pendingRead.future;
      }
      return _response(_alarm(19, enabled: false));
    });
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    addTearDown(client.close);
    await model.loadMedicationReminderSettings();
    final load = model.loadMedicationReminderSettings();
    await readStarted.future;
    expect(
      await model.requestMedicationReminderCancel(
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 19,
        minute: 0,
      ),
      isTrue,
    );
    pendingRead.complete(_response([_alarm(8)]));
    await load;
    expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
    expect(model.medicationReminderSettings['morning']!.hour, 19);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(_cacheKey)!)['hour'], 19);
  });

  // 함수이름: 종료된 모델의 늦은 저장
  // 함수역할:
  // - 저장 응답 전에 모델을 종료하면 false를 반환하고 기기 예약·취소·설정·캐시를 생성하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('계정 전환으로 종료한 모델의 늦은 저장은 기기 알림을 예약하지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((request) async {
      started.complete();
      return response.future;
    });
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    addTearDown(client.close);
    final save = _save(model, 9);
    await started.future;
    model.dispose();
    response.complete(_response(_alarm(9)));
    expect(await save, isFalse);
    expect(notifications.registrations, isEmpty);
    expect(notifications.cancellations, isEmpty);
    expect(model.medicationReminderSettings, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_cacheKey),
      isNull,
    );
  });

  // 함수이름: 진행 중인 시간대의 중복 쓰기
  // 함수역할:
  // - 첫 09:00 저장이 대기 중이면 두 번째 10:00 요청을 거부하고 서버 쓰기 한 번과 첫 설정값만 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('같은 시간대 저장이 진행 중이면 중복 쓰기를 시작하지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    var writes = 0;
    final client = MockClient((request) async {
      if (++writes == 1) {
        started.complete();
        return response.future;
      }
      return _response(_alarm(10));
    });
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    addTearDown(client.close);
    final first = _save(model, 9);
    await started.future;
    final repeated = await _save(model, 10);
    response.complete(_response(_alarm(9)));
    expect(await first, isTrue);
    expect(repeated, isFalse);
    expect(writes, 1);
    expect(model.medicationReminderSettings['morning']!.hour, 9);
  });

  // 함수이름: 권한 대기 중 세션 종료
  // 함수역할:
  // - 모델 종료 후 권한이 승인되어도 저장을 거부하고 서버 요청과 기기 예약을 시작하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('권한 응답 전에 계정이 종료되면 서버 쓰기를 시작하지 않는다', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _response(_alarm(9));
    });
    addTearDown(client.close);
    final notifications = _PendingPermission();
    final model = _model(client, notifications);
    final save = _save(model, 9);
    model.dispose();
    notifications.result.complete(true);
    expect(await save, isFalse);
    expect(requests, 0);
    expect(notifications.registrations, isEmpty);
  });

  // 함수이름: 종료된 모델의 늦은 취소 응답
  // 함수역할:
  // - 꺼짐 응답 전에 모델을 종료하면 false를 반환하고 알림 취소와 캐시 저장을 수행하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('계정 종료 후 도착한 꺼짐 응답은 기기 예약과 캐시를 건드리지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((_) async {
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    final save = model.requestMedicationReminderCancel(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: 19,
      minute: 0,
    );
    await started.future;
    model.dispose();
    response.complete(_response(_alarm(19, enabled: false)));
    expect(await save, isFalse);
    expect(notifications.cancellations, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_cacheKey),
      isNull,
    );
  });

  // 함수이름: 저장 중 조회 차단과 실패 재시도
  // 함수역할:
  // - 진행 중 저장은 자동 조회를 차단하며 첫 서버 500 오류 후 두 번째 저장이 성공해 10:00을 적용하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('저장 중 자동 조회는 건너뛰고 실패 뒤에는 저장을 다시 시도할 수 있다', () async {
    var reads = 0;
    var writes = 0;
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        reads++;
        return _response([_alarm(8)]);
      }
      if (++writes == 1) {
        started.complete();
        return response.future;
      }
      return _response(_alarm(10));
    });
    addTearDown(client.close);
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    final first = _save(model, 9);
    await started.future;
    await model.loadMedicationReminderSettings();
    expect(reads, 0);
    response.complete(http.Response('{}', 500));
    expect(await first, isFalse);
    expect(await _save(model, 10), isTrue);
    expect(writes, 2);
    expect(model.medicationReminderSettings['morning']!.hour, 10);
  });
}
