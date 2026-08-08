import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/caregiver_notification_monitor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _AlertRecord = ({int id, String title, String body});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('시간대의 모든 약을 완료하면 보호자에게 한 번만 알린다', () async {
    final alerts = <_AlertRecord>[];
    var schedules = [
      _schedule(medicationID: 'medication-1', morningCompleted: false),
      _schedule(medicationID: 'medication-2', morningCompleted: false),
    ];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
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
    expect(alerts.single.body, '환자가 아침에 복용할 약을 모두 복용했습니다.');
  });

  test('마감 시각 이후 미복용 일정은 같은 날 한 번만 알린다', () async {
    final alerts = <_AlertRecord>[];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.missedDeadline,
      deadlineHour: 20,
      deadlineMinute: 0,
      schedules: [_schedule(morningCompleted: false)],
      now: () => DateTime(2026, 7, 29, 20, 5),
      alerts: alerts,
    );
    addTearDown(monitor.dispose);

    await monitor.checkNow();
    await monitor.checkNow();

    expect(alerts, hasLength(1));
    expect(alerts.single.title, '미복용 일정 확인');
    expect(alerts.single.body, contains('20:00'));
    expect(alerts.single.body, contains('1건'));
  });

  test('알림 끄기 모드에서는 환자 일정을 조회하거나 알리지 않는다', () async {
    final alerts = <_AlertRecord>[];
    var scheduleRequestCount = 0;
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.disabled,
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

  test('시간대별 알림은 선택한 시간대의 체크 변화만 감지한다', () async {
    final alerts = <_AlertRecord>[];
    var schedules = [
      _schedule(morningCompleted: false, eveningCompleted: false),
    ];
    final monitor = _buildMonitor(
      mode: CaregiverNotificationMode.doseCompleted,
      slotKey: 'evening',
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
  test('returns false when a background data request fails', () async {
    var loadAttemptCount = 0;
    final monitor = CaregiverNotificationMonitorService(
      caregiverHash: 'caregiver_test',
      loadLinks: () async {
        loadAttemptCount += 1;
        if (loadAttemptCount == 1) {
          throw StateError('backend unavailable');
        }
        return const <PatientCaregiverLink>[];
      },
      loadSettings: (_) async => const <String, CaregiverNotification>{},
      loadSchedules: (_) async => const <MedicationSchedule>[],
      sendAlert:
          ({
            required int id,
            required String title,
            required String body,
          }) async {},
      permissionRequester: () async => true,
    );
    addTearDown(monitor.dispose);

    expect(await monitor.checkNow(), isFalse);
    expect(await monitor.checkNow(), isTrue);
    expect(loadAttemptCount, 2);
  });
}

CaregiverNotificationMonitorService _buildMonitor({
  required CaregiverNotificationMode mode,
  String slotKey = 'morning',
  List<MedicationSchedule>? schedules,
  Future<List<MedicationSchedule>> Function()? scheduleLoader,
  int? deadlineHour,
  int? deadlineMinute,
  DateTime Function()? now,
  required List<_AlertRecord> alerts,
}) {
  return CaregiverNotificationMonitorService(
    caregiverHash: 'caregiver_test',
    loadLinks: () async {
      return const [
        PatientCaregiverLink(
          caregiverHash: 'caregiver_test',
          patientHash: 'patient_test',
          linkStatus: true,
        ),
      ];
    },
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
    loadSchedules: (_) {
      return scheduleLoader?.call() ??
          Future.value(schedules ?? const <MedicationSchedule>[]);
    },
    sendAlert:
        ({required int id, required String title, required String body}) async {
          alerts.add((id: id, title: title, body: body));
        },
    permissionRequester: () async => true,
    now: now,
  );
}

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
