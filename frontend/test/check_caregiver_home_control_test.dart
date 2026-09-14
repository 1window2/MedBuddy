// 파일명: check_caregiver_home_control_test.dart
// 역할: 보호자 홈의 계정·연동 범위, 오류와 진행률을 검증한다.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/caregiver_home_summary_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_home_control.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_monitoring_snapshot_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';

const _link = PatientCaregiverLink(
  linkId: 1,
  patientId: 'patient',
  caregiverId: 'owner',
  patientHash: 'patient',
  caregiverHash: 'owner',
  patientAlias: '엄마',
  linkStatus: true,
);
const _other = PatientCaregiverLink(
  linkId: 2,
  patientId: 'other',
  caregiverId: 'someone',
  patientHash: 'other',
  caregiverHash: 'someone',
  linkStatus: true,
);

// 함수역할: 보호자 전용 홈의 진입과 표시 상태를 검증한다.
void main() {
  test('활성 보호자 연동만 조회하고 다른 계정의 응답은 버린다', () async {
    final api = _Monitoring();
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(api.dispose);
    control.updateLinks([_other]);
    await control.refresh();
    expect(api.calls, 0);
    control.updateLinks([_link]);
    await control.refresh();
    expect(api.calls, 1);
    expect(control.links, [_link]);
    expect(control.snapshotFor(1), isNotNull);
    expect(control.snapshotFor(2), isNull);
    final patientControl = CheckCaregiverHome(
      userHash: 'patient',
      control: api,
    );
    addTearDown(patientControl.dispose);
    patientControl.updateLinks([_link]);
    await patientControl.refresh();
    expect(patientControl.links, isEmpty);
    expect(api.calls, 1);
  });

  test('조회 실패를 일정 없음과 구분하고 재시도 시 복원한다', () async {
    final api = _Monitoring();
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(api.dispose);
    control.updateLinks([_link]);
    await control.refresh();
    expect(control.snapshotFor(1), isNotNull);
    api.failure = true;
    await control.refresh();
    expect(control.hasError, isTrue);
    expect(control.snapshotFor(1), isNull);
    api.failure = false;
    await control.refresh();
    expect(control.hasError, isFalse);
    expect(control.snapshotFor(1), isNotNull);
  });

  test('연동 해제 중 도착한 응답과 종료된 계정의 응답을 버린다', () async {
    final api = _Monitoring()
      ..gate = Completer<List<CaregiverMonitoringSnapshot>>();
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(api.dispose);
    control.updateLinks([_link]);
    final pending = control.refresh();
    await Future<void>.delayed(Duration.zero);
    await control.refresh();
    expect(api.calls, 1);
    control.updateLinks([]);
    expect(control.links, isEmpty);
    api.gate!.complete([_snapshot(_link)]);
    await pending;
    expect(control.snapshotFor(1), isNull);
    api.gate = Completer<List<CaregiverMonitoringSnapshot>>();
    control.updateLinks([_link]);
    final stale = control.refresh();
    await Future<void>.delayed(Duration.zero);
    control.dispose();
    api.gate!.complete([_snapshot(_link)]);
    await stale;
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('환자 별칭·진행률·상세 진입은 큰 글씨에서도 유지된다: $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _Monitoring();
      final control = CheckCaregiverHome(userHash: 'owner', control: api);
      addTearDown(control.dispose);
      addTearDown(api.dispose);
      control.updateLinks([_link]);
      await control.refresh();
      PatientCaregiverLink? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CaregiverHomeSummaryUI(
                    control: control,
                    isEnglish: false,
                    patientLabel: (link) => link.patientAlias!,
                    onPatientRequested: (link) => selected = link,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('엄마'), findsOneWidget);
      expect(find.text('3회 중 1회 복용'), findsOneWidget);
      await tester.tap(find.byKey(const Key('caregiver-home-patient-1')));
      expect(selected, _link);
      expect(tester.takeException(), isNull);
    });
  }
}

// 함수역할: 시간대별 일부 완료를 포함하는 오늘 복약 조회 대역을 만든다.
CaregiverMonitoringSnapshot _snapshot(PatientCaregiverLink link) =>
    CaregiverMonitoringSnapshot(
      link: link,
      notificationSettings: const {},
      schedules: [
        MedicationSchedule(
          medicationName: '약',
          scheduleSlotKeys: const ['morning', 'lunch', 'evening'],
          slotStatuses: const {'morning': true},
        ),
      ],
    );

// 클래스명: _Monitoring
// 역할: 환자 조회 실패·지연과 다른 계정 결과를 재현한다.
class _Monitoring extends CheckCaregiverMedication {
  int calls = 0;
  bool failure = false;
  Completer<List<CaregiverMonitoringSnapshot>>? gate;
  @override
  Future<List<CaregiverMonitoringSnapshot>> requestMonitoringSnapshot() async {
    calls++;
    if (failure) throw StateError('offline');
    return gate != null ? gate!.future : [_snapshot(_link), _snapshot(_other)];
  }
}
