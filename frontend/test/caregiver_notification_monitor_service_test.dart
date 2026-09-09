// 파일명: caregiver_notification_monitor_service_test.dart
// 역할: 보호자 알림 감시의 시간대별 완료와 미복용 조건을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/caregiver_monitoring_snapshot_entity.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/caregiver_notification_monitor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _AlertRecord (typedef)
// 역할: 보호자 알림의 표시 내용과 환자 범위를 함께 검사하는 명명된 레코드 계약.
// 주요 책임:
// - 알림 본문과 환자 범위를 하나의 값으로 기록하고 중복·개인정보 조건 검증에 사용한다.
// 속성:
// - id (int): 알림 식별자.
// - title (String): 잠금 화면에 표시할 알림 제목.
// - body (String): 표시할 알림 본문.
// - patientHash (String): 알림 대상 환자 범위.
typedef _AlertRecord = ({
  int id,
  String title,
  String body,
  String patientHash,
});

// Function Name: main
// Description:
// - Register regression cases for caregiver completion/deadline alerts, privacy, and patient polling.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 테스트 전에 메모리 설정 저장소를 비워 사용자 캐시를 격리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 설정 저장소가 빈 상태로 초기화된다.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복용 완료 모드는 최초 상태를 기준값으로만 저장한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('복용 완료 모드는 최초 상태를 기준값으로만 저장한다', () async {
    final alerts = <_AlertRecord>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
      schedules: [_schedule(morningCompleted: true)],
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();

    expect(alerts, isEmpty);
  });

  // Function Name: test callback
  // Description:
  // - Verify that completing every medication in a slot emits exactly one caregiver alert.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('시간대의 모든 약을 완료하면 보호자에게 한 번만 알린다', () async {
    final alerts = <_AlertRecord>[];
    var schedules = [
      _schedule(medicationID: 'medication-1', morningCompleted: false),
      _schedule(medicationID: 'medication-2', morningCompleted: false),
    ];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
      // 함수이름: scheduleLoader 콜백
      // 함수역할:
      // - 일정 변수가 교체되면 다음 감시 검사에서 변경된 완료 상태를 읽게 한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 현재 캡처한 일정 목록.
      scheduleLoader: () async => schedules,
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    schedules = [
      _schedule(medicationID: 'medication-1', morningCompleted: true),
      _schedule(medicationID: 'medication-2', morningCompleted: false),
    ];
    await monitor.checkNow();
    expect(alerts, isEmpty);

    schedules = [
      _schedule(medicationID: 'medication-1', morningCompleted: true),
      _schedule(medicationID: 'medication-2', morningCompleted: true),
    ];
    await monitor.checkNow();
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.title, '환자 복약 완료');
    expect(alerts.single.body, '연동된 환자의 아침 복약이 모두 완료되었습니다.');
    expect(alerts.single.title, isNot(contains('TEST')));
    expect(alerts.single.body, isNot(contains('TEST')));
    expect(alerts.single.patientHash, 'patient_test');
  });

  // Function Name: test callback
  // Description:
  // - Verify that lock-screen alerts omit cached patient aliases and patient hashes.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('저장한 환자 별칭은 잠금 화면 보호자 알림에 표시하지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      'caregiver_patient_label.caregiver_test.patient_test': '어머니',
    });
    final alerts = <_AlertRecord>[];
    var schedules = [_schedule(morningCompleted: false)];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
      // 함수이름: scheduleLoader 콜백
      // 함수역할:
      // - 일정 변수가 교체되면 다음 감시 검사에서 변경된 완료 상태를 읽게 한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 현재 캡처한 일정 목록.
      scheduleLoader: () async => schedules,
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    schedules = [_schedule(morningCompleted: true)];
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.body, '연동된 환자의 아침 복약이 모두 완료되었습니다.');
    expect(alerts.single.body, isNot(contains('어머니')));
    expect(alerts.single.body, isNot(contains('patient_test')));
  });

  // Function Name: test callback
  // Description:
  // - Verify that overdue incomplete doses emit only one alert per day without revealing the patient
  //   alias.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('마감 시각 이후 미복용 일정은 같은 날 한 번만 알린다', () async {
    SharedPreferences.setMockInitialValues({
      'caregiver_patient_label.caregiver_test.patient_test': '어머니',
    });
    final alerts = <_AlertRecord>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.missedDeadline,
      deadlineHour: 20,
      deadlineMinute: 0,
      schedules: [_schedule(morningCompleted: false)],
      // 함수이름: now 콜백
      // 함수역할:
      // - 실제 시계와 무관하게 복약 마감과 알림 날짜 범위를 검사할 기준 시각을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - DateTime(2026, 7, 29, 20, 5)에서 얻은 기준 DateTime.
      now: () => DateTime(2026, 7, 29, 20, 5),
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.title, '미복용 일정 확인');
    expect(alerts.single.body, startsWith('연동된 환자의 아침 복약 중'));
    expect(alerts.single.body, isNot(contains('어머니')));
    expect(alerts.single.body, isNot(contains('TEST')));
    expect(alerts.single.body, contains('20:00'));
    expect(alerts.single.body, contains('1건'));
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버 전달 모드에서 기기 미복약 감시가 중복 알림을 만들지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 알림 미생성을 확인한 뒤 완료한다.
  test('서버 전달 모드에서는 기기 미복약 감시가 중복 알림을 만들지 않는다', () async {
    final alerts = <_AlertRecord>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.missedDeadline,
      deadlineHour: 20,
      deadlineMinute: 0,
      schedules: [_schedule(morningCompleted: false)],
      now: () => DateTime(2026, 7, 29, 20, 5),
      monitorMissedDeadlines: false,
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();

    expect(alerts, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 영어 설정은 보호자 알림 제목과 본문에 함께 반영된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('영어 설정은 보호자 알림 제목과 본문에 함께 반영된다', () async {
    final alerts = <_AlertRecord>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.missedDeadline,
      deadlineHour: 20,
      deadlineMinute: 0,
      schedules: [_schedule(morningCompleted: false)],
      // 함수이름: now 콜백
      // 함수역할:
      // - 실제 시계와 무관하게 복약 마감과 알림 날짜 범위를 검사할 기준 시각을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - DateTime(2026, 7, 29, 20, 5)에서 얻은 기준 DateTime.
      now: () => DateTime(2026, 7, 29, 20, 5),
      language: 'en',
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();

    expect(alerts.single.title, 'Medication not checked');
    expect(alerts.single.body, contains('morning medication'));
    expect(alerts.single.body, isNot(contains('미복용')));
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 알림 끄기 모드에서는 환자 일정을 조회하거나 알리지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('알림 끄기 모드에서는 환자 일정을 조회하거나 알리지 않는다', () async {
    final alerts = <_AlertRecord>[];
    var scheduleRequestCount = 0;
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.disabled,
      // 함수이름: scheduleLoader 콜백
      // 함수역할:
      // - 비활성 알림 모드에서 일정 조회가 호출되는지 횟수를 기록한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 아침 완료 상태의 일정 한 건.
      scheduleLoader: () async {
        scheduleRequestCount += 1;
        return [_schedule(morningCompleted: true)];
      },
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();

    expect(scheduleRequestCount, 0);
    expect(alerts, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 시간대별 알림은 선택한 시간대의 체크 변화만 감지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('시간대별 알림은 선택한 시간대의 체크 변화만 감지한다', () async {
    final alerts = <_AlertRecord>[];
    var schedules = [
      _schedule(morningCompleted: false, eveningCompleted: false),
    ];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
      slotKey: 'evening',
      // 함수이름: scheduleLoader 콜백
      // 함수역할:
      // - 일정 변수가 교체되면 다음 감시 검사에서 변경된 완료 상태를 읽게 한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 현재 캡처한 일정 목록.
      scheduleLoader: () async => schedules,
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    schedules = [_schedule(morningCompleted: true, eveningCompleted: false)];
    await monitor.checkNow();
    expect(alerts, isEmpty);

    schedules = [_schedule(morningCompleted: true, eveningCompleted: true)];
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.body, contains('저녁'));
  });
  // 함수이름: test 콜백
  // 함수역할:
  // - 백그라운드 조회 실패는 false로 보고하고 다음 조회는 다시 시도해 성공할 수 있는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('returns false when a background data request fails', () async {
    var loadAttemptCount = 0;
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      // Function Name: loadLinks callback
      // Description:
      // - Fail the first link lookup and allow the next attempt to recover, recording both attempts.
      // Parameters:
      // - None.
      // Returns:
      // - Initially StateError; then an empty link list.
      loadLinks: () async {
        loadAttemptCount += 1;
        if (loadAttemptCount == 1) {
          throw StateError('backend unavailable');
        }
        return const <PatientCaregiverLink>[];
      },
      // Function Name: loadSettings callback
      // Description:
      // - Model a patient with no caregiver notification settings.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty slot-to-setting map.
      loadSettings: (_) async => const <String, CaregiverNotification>{},
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
          // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
          // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isFalse);
    expect(await monitor.checkNow(), isTrue);
    expect(loadAttemptCount, 2);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 한 환자 조회가 실패해도 다음 연동 환자의 알림은 계속 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('한 환자 조회가 실패해도 다음 연동 환자의 알림은 계속 확인한다', () async {
    final checkedPatientHashes = <String>[];
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 첫 환자 조회 실패 뒤 두 번째 환자를 계속 확인할 두 활성 연결을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 실패 대상과 성공 대상 환자의 연결 목록.
      loadLinks: () async {
        return const [
          PatientCaregiverLink(
            caregiverHash: 'caregiver_test',
            patientHash: 'patient_failed',
            linkStatus: true,
          ),
          PatientCaregiverLink(
            caregiverHash: 'caregiver_test',
            patientHash: 'patient_success',
            linkStatus: true,
          ),
        ];
      },
      // 함수이름: loadSettings 콜백
      // 함수역할:
      // - 조회 환자를 기록하고 첫 환자 설정에만 오류를 주입한다.
      // 매개변수:
      // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
      // 반환값:
      // - 첫 환자는 StateError; 다음 환자는 빈 설정 맵.
      loadSettings: (patientHash) async {
        checkedPatientHashes.add(patientHash);
        if (patientHash == 'patient_failed') {
          throw StateError('첫 번째 환자 조회 실패');
        }
        return const <String, CaregiverNotification>{};
      },
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
          // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
          // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isFalse);
    expect(checkedPatientHashes, ['patient_failed', 'patient_success']);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 여러 환자는 최대 네 명씩 병렬로 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('여러 환자는 최대 네 명씩 병렬로 확인한다', () async {
    var activeRequestCount = 0;
    var maximumActiveRequestCount = 0;
    final checkedPatientHashes = <String>[];
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 동시 확인 한도를 검사하도록 여섯 개의 활성 환자 연결을 만든다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 서로 다른 환자 식별자를 가진 여섯 연결.
      loadLinks: () async {
        // 함수이름: generate 콜백
        // 함수역할:
        // - 목록 순번을 환자 식별자에 반영한 활성 연결을 만든다.
        // 매개변수:
        // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번.
        // 반환값:
        // - 해당 순번의 PatientCaregiverLink.
        return List.generate(6, (index) {
          return PatientCaregiverLink(
            caregiverHash: 'caregiver_test',
            patientHash: 'patient_$index',
            linkStatus: true,
          );
        });
      },
      // 함수이름: loadSettings 콜백
      // 함수역할:
      // - 지연된 설정 조회의 활성·최대 동시 개수와 완료 환자를 기록한다.
      // 매개변수:
      // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
      // 반환값:
      // - 10ms 지연 후 빈 보호자 알림 설정 맵.
      loadSettings: (patientHash) async {
        activeRequestCount += 1;
        if (activeRequestCount > maximumActiveRequestCount) {
          maximumActiveRequestCount = activeRequestCount;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        checkedPatientHashes.add(patientHash);
        activeRequestCount -= 1;
        return const <String, CaregiverNotification>{};
      },
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
          // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
          // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isTrue);
    expect(checkedPatientHashes, hasLength(6));
    expect(maximumActiveRequestCount, greaterThan(1));
    expect(
      maximumActiveRequestCount,
      lessThanOrEqualTo(
        CaregiverNotificationMonitorService.maximumParallelPatientChecks,
      ),
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 통합 조회 한 번으로 여러 환자를 확인하고 서버 별칭을 캐시한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('통합 조회 한 번으로 여러 환자를 확인하고 서버 별칭을 캐시한다', () async {
    var aggregateRequestCount = 0;
    var legacyLinkRequestCount = 0;
    var legacySettingRequestCount = 0;
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      // 함수이름: loadMonitoringSnapshots 콜백
      // 함수역할:
      // - 통합 요청 횟수를 기록하고 서로 다른 서버 별칭을 가진 두 환자 스냅샷을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 두 환자의 별칭·연결 스냅샷 목록.
      loadMonitoringSnapshots: () async {
        aggregateRequestCount += 1;
        return [
          _monitoringSnapshot(patientHash: 'patient-a', patientAlias: '어머니'),
          _monitoringSnapshot(patientHash: 'patient-b', patientAlias: '아버지'),
        ];
      },
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 통합 조회 성공 시 기존 연결 조회가 실행되는지 횟수로 감시한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 빈 연결 목록.
      loadLinks: () async {
        legacyLinkRequestCount += 1;
        return const <PatientCaregiverLink>[];
      },
      // 함수이름: loadSettings 콜백
      // 함수역할:
      // - 기존 환자별 설정 조회 횟수를 기록해 통합 조회 또는 대체 경로 사용을 구별한다.
      // 매개변수:
      // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
      // 반환값:
      // - 빈 시간대별 보호자 알림 설정 맵.
      loadSettings: (_) async {
        legacySettingRequestCount += 1;
        return const <String, CaregiverNotification>{};
      },
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
          // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
          // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(aggregateRequestCount, 1);
    expect(legacyLinkRequestCount, 0);
    expect(legacySettingRequestCount, 0);
    expect(monitor.hasCaregiverLinks, isTrue);
    expect(
      preferences.getString('caregiver_patient_label.caregiver_test.patient-a'),
      '어머니',
    );
    expect(
      preferences.getString('caregiver_patient_label.caregiver_test.patient-b'),
      '아버지',
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 통합 조회 실패 시 기존 환자별 조회로 자동 복구한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('통합 조회 실패 시 기존 환자별 조회로 자동 복구한다', () async {
    var legacyLinkRequestCount = 0;
    var legacySettingRequestCount = 0;
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      // 함수이름: loadMonitoringSnapshots 콜백
      // 함수역할:
      // - 통합 감시 API 실패를 주입해 기존 환자별 조회로의 복구를 유도한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 통합 조회 실패 StateError.
      loadMonitoringSnapshots: () async {
        throw StateError('구버전 서버 또는 일시적인 통합 조회 실패');
      },
      // 함수이름: loadLinks 콜백
      // 함수역할:
      // - 대체 연결 조회 횟수를 기록하고 고정 환자의 활성 연결을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 고정 환자 연결 한 건.
      loadLinks: () async {
        legacyLinkRequestCount += 1;
        return const [
          PatientCaregiverLink(
            caregiverHash: 'caregiver_test',
            patientHash: 'patient_test',
            linkStatus: true,
          ),
        ];
      },
      // 함수이름: loadSettings 콜백
      // 함수역할:
      // - 기존 환자별 설정 조회 횟수를 기록해 통합 조회 또는 대체 경로 사용을 구별한다.
      // 매개변수:
      // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
      // 반환값:
      // - 빈 시간대별 보호자 알림 설정 맵.
      loadSettings: (_) async {
        legacySettingRequestCount += 1;
        return const <String, CaregiverNotification>{};
      },
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - _ (String): Patient/user scope; the fixed fixture ignores it.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          // 함수이름: sendAlert 콜백
          // 함수역할:
          // - 감시기의 조회·연결 상태를 검사하는 동안 실제 기기 알림은 표시하지 않는다.
          // 매개변수:
          // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
          // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
          // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
          // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - Future<void>; 알림 표시 없이 완료된다.
          ({
            required int id,
            required String title,
            required String body,
            required String patientHash,
          }) async {},
      // 함수이름: permissionRequester 콜백
      // 함수역할:
      // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - true로 완료되는 Future<bool>.
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isTrue);
    expect(legacyLinkRequestCount, 1);
    expect(legacySettingRequestCount, 1);
    expect(monitor.hasCaregiverLinks, isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 알림을 끄면 해당 시간대의 이전 알림 상태를 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('알림을 끄면 해당 시간대의 이전 알림 상태를 정리한다', () async {
    const scope = 'caregiver_alert.caregiver_test.patient_test.morning';
    SharedPreferences.setMockInitialValues({
      '$scope.snapshot_date': '2026-07-29',
      '$scope.snapshot_data': '{"medication":true}',
      '$scope.completion_notice': 'completed',
      '$scope.deadline_notice': 'missed',
    });
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.disabled,
      schedules: [_schedule(morningCompleted: true)],
      alerts: <_AlertRecord>[],
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('$scope.snapshot_date'), isNull);
    expect(preferences.getString('$scope.snapshot_data'), isNull);
    expect(preferences.getString('$scope.completion_notice'), isNull);
    expect(preferences.getString('$scope.deadline_notice'), isNull);
    expect(preferences.getString('$scope.mode'), 'disabled');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 마감 시각에 일정이 없었어도 나중에 추가된 미복용 일정은 알린다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('마감 시각에 일정이 없었어도 나중에 추가된 미복용 일정은 알린다', () async {
    final alerts = <_AlertRecord>[];
    var schedules = <MedicationSchedule>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.missedDeadline,
      deadlineHour: 20,
      deadlineMinute: 0,
      // 함수이름: scheduleLoader 콜백
      // 함수역할:
      // - 일정 변수가 교체되면 다음 감시 검사에서 변경된 완료 상태를 읽게 한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 현재 캡처한 일정 목록.
      scheduleLoader: () async => schedules,
      // 함수이름: now 콜백
      // 함수역할:
      // - 실제 시계와 무관하게 복약 마감과 알림 날짜 범위를 검사할 기준 시각을 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - DateTime(2026, 7, 29, 20, 5)에서 얻은 기준 DateTime.
      now: () => DateTime(2026, 7, 29, 20, 5),
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    schedules = [_schedule(morningCompleted: false)];
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.body, contains('1건'));
  });
}

// 함수이름: _buildMonitor
// 함수역할:
// - 환자 연결·알림 설정·일정 조회와 알림 기록을 주입한 보호자 감시기를 구성한다.
// 매개변수:
// - mode (CaregiverNotificationMode): 복용 완료·미복용 마감·비활성 중 알림 정책.
// - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키.
// - schedules (List<MedicationSchedule>?): 사례에 사용할 인식 결과 또는 현재 복약 일정.
// - scheduleLoader (Future<List<MedicationSchedule>> Function()?): 고정 일정을 대체할 선택적 동적 조회 함수.
// - deadlineHour (int?): 미복용 마감 시각의 시 값.
// - deadlineMinute (int?): 미복용 마감 시각의 분 값.
// - now (DateTime Function()?): 날짜와 마감을 고정할 선택적 시계 함수.
// - language (String): 화면 문구 또는 알림 내용의 언어 코드.
// - monitorMissedDeadlines (bool): 기기에서 미복약 마감을 평가할지 여부.
// - alerts (List<_AlertRecord>): 가로챈 보호자 알림을 쌓을 기록 목록.
// 반환값:
// - 고정 보호자 범위에서 지정한 조건을 검사하는 감시기.
CaregiverNotificationMonitorService _buildMonitor({
  required CaregiverNotificationMode mode,
  String slotKey = 'morning',
  List<MedicationSchedule>? schedules,
  Future<List<MedicationSchedule>> Function()? scheduleLoader,
  int? deadlineHour,
  int? deadlineMinute,
  DateTime Function()? now,
  String language = 'ko',
  bool monitorMissedDeadlines = true,
  required List<_AlertRecord> alerts,
}) {
  return CaregiverNotificationMonitorService(
    caregiverHash: 'caregiver_test',
    // 함수이름: loadLinks 콜백
    // 함수역할:
    // - 감시기 기본 대역에 고정 환자와 보호자의 활성 연결을 제공한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - patient_test와 caregiver_test의 연결 한 건.
    loadLinks: () async {
      return const [
        PatientCaregiverLink(
          caregiverHash: 'caregiver_test',
          patientHash: 'patient_test',
          linkStatus: true,
        ),
      ];
    },
    // 함수이름: loadSettings 콜백
    // 함수역할:
    // - 지정 시간대·모드·마감 시각을 환자 알림 설정에 반영한다.
    // 매개변수:
    // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
    // 반환값:
    // - 해당 시간대를 키로 하는 보호자 알림 설정 맵.
    loadSettings: (_) async {
      return {
        slotKey: CaregiverNotification(
          caregiverHash: 'caregiver_test',
          patientHash: 'patient_test',
          slotKey: slotKey,
          mode: mode,
          deadlineHour: deadlineHour,
          deadlineMinute: deadlineMinute,
        ),
      };
    },
    // 함수이름: loadSchedules 콜백
    // 함수역할:
    // - 사용자 지정 일정 조회를 우선 실행하고 없으면 고정 또는 빈 일정을 제공한다.
    // 매개변수:
    // - _ (String): 고정 대역에서는 사용하지 않는 환자·사용자 범위.
    // 반환값:
    // - 주입한 조회 결과 Future 또는 고정 일정의 Future.
    loadSchedules: (_) {
      return scheduleLoader?.call() ??
          Future.value(schedules ?? const <MedicationSchedule>[]);
    },
    sendAlert:
        // 함수이름: sendAlert 콜백
        // 함수역할:
        // - 알림 식별자·제목·본문·환자 범위를 기록 목록에 보관한다.
        // 매개변수:
        // - id (int): 약·메시지·알림 대역의 식별자.
        // - title (String): 가로챈 알림의 표시 제목.
        // - body (String): 호출자가 전달한 알림 또는 메시지 본문.
        // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
        // 반환값:
        // - Future<void>; 알림 레코드 추가 완료.
        ({
          required int id,
          required String title,
          required String body,
          required String patientHash,
        }) async {
          alerts.add((
            id: id,
            title: title,
            body: body,
            patientHash: patientHash,
          ));
        },
    // 함수이름: permissionRequester 콜백
    // 함수역할:
    // - 기기 권한 창 없이 알림 권한 허용을 재현한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - true로 완료되는 Future<bool>.
    permissionRequester: () async => true,
    // 함수이름: languageProvider 콜백
    // 함수역할:
    // - 보호자 알림 문구에 사용할 테스트 언어를 제공한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 캡처한 언어 코드.
    languageProvider: () => language,
    monitorMissedDeadlines: monitorMissedDeadlines,
    now: now,
  );
}

// 함수이름: _schedule
// 함수역할:
// - 아침·저녁 완료 상태를 지정한 하루 세 번 복용 일정을 만든다.
// 매개변수:
// - medicationID (String): 일정 대역에 부여할 약 식별자.
// - morningCompleted (bool): 아침 복약에 부여할 완료 여부.
// - eveningCompleted (bool): 일정 대역의 저녁 복약 완료 여부.
// 반환값:
// - 2026-07-29 처방일과 지정 완료 상태를 가진 일정.
MedicationSchedule _schedule({
  String medicationID = 'medication-1',
  required bool morningCompleted,
  bool eveningCompleted = false,
}) {
  return MedicationSchedule(
    medicationID: medicationID,
    medicationName: '테스트정',
    dosage: '1',
    intakeTime: '1일 3회',
    medicationTime: 3,
    prescriptionDate: DateTime(2026, 7, 29),
    slotStatuses: {'morning': morningCompleted, 'evening': eveningCompleted},
  );
}

// 함수이름: _monitoringSnapshot
// 함수역할:
// - 환자 별칭 캐시를 검사할 연결 정보와 빈 알림·일정 스냅샷을 만든다.
// 매개변수:
// - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
// - patientAlias (String): 보호자가 지정한 연동 환자 표시 별칭.
// 반환값:
// - 지정 환자와 별칭을 포함한 통합 감시 스냅샷.
CaregiverMonitoringSnapshot _monitoringSnapshot({
  required String patientHash,
  required String patientAlias,
}) {
  return CaregiverMonitoringSnapshot(
    link: PatientCaregiverLink(
      linkId: patientHash == 'patient-a' ? 1 : 2,
      caregiverHash: 'caregiver_test',
      patientHash: patientHash,
      patientAlias: patientAlias,
      linkStatus: true,
    ),
    notificationSettings: const <String, CaregiverNotification>{},
    schedules: const <MedicationSchedule>[],
  );
}
