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
import 'package:medbuddy_frontend/widgets/home_medication_preview.dart';

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
      expect(find.byType(HomeMedicationPreview), findsOneWidget);
      expect(find.text('오늘의 복약 진행률'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('남은 복약 일정'), findsOneWidget);
      expect(find.text('점심 · 약'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(1 / 3, 0.001));
      expect(progress.semanticsLabel, '3회 중 1회 복용');
      expect(find.text('복용했어요'), findsNothing);
      expect(
        tester
            .widget<HomeMedicationPreview>(find.byType(HomeMedicationPreview))
            .action,
        isNull,
      );
      await tester.tap(find.byKey(const Key('caregiver-home-patient-1')));
      expect(selected, _link);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('환자가 여러 명이어도 각 진행률과 상세 진입을 유지한다', (tester) async {
    const second = PatientCaregiverLink(
      linkId: 3,
      patientId: 'second',
      caregiverId: 'owner',
      patientHash: 'second',
      caregiverHash: 'owner',
      patientAlias: '아빠',
      linkStatus: true,
    );
    final api = _Monitoring()
      ..snapshots = [_snapshot(_link), _snapshot(second)];
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(api.dispose);
    control.updateLinks([_link, second]);
    await control.refresh();
    PatientCaregiverLink? selected;
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: control,
              builder: (context, _) => CaregiverHomeSummaryUI(
                control: control,
                isEnglish: false,
                patientLabel: (link) => link.patientAlias!,
                onPatientRequested: (link) => selected = link,
                onRefreshRequested: () => refreshes++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(HomeMedicationPreview), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('caregiver-home-refresh')));
    expect(refreshes, 1);
    expect(selected, isNull);
    await tester.drag(
      find.byKey(const Key('caregiver-patient-pager')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('caregiver-home-patient-1')), findsNothing);
    await tester.tap(find.byKey(const Key('caregiver-home-patient-3')));
    expect(selected, second);
    await tester.tap(find.byKey(const Key('caregiver-patient-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    control.updateLinks([second, _link]);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('caregiver-home-patient-1')), findsOneWidget);
    control.updateLinks([second]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('caregiver-home-patient-3')), findsOneWidget);
    expect(find.byKey(const Key('caregiver-patient-next')), findsNothing);
    expect(find.byKey(const Key('caregiver-home-patient-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('조회 전·일정 없음·모두 완료·실패를 구분한다', (tester) async {
    final api = _Monitoring();
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(api.dispose);
    control.updateLinks([_link]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: control,
            builder: (context, child) => CaregiverHomeSummaryUI(
              control: control,
              isEnglish: false,
              patientLabel: (link) => link.patientAlias!,
              onPatientRequested: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('-'), findsOneWidget);
    expect(find.text('복약 현황 확인 필요'), findsOneWidget);

    api.gate = Completer<List<CaregiverMonitoringSnapshot>>();
    final loading = control.refresh();
    await tester.pump();
    expect(find.text('복약 현황 확인 중'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('caregiver-home-refresh')))
          .onPressed,
      isNull,
    );
    api.gate!.complete([
      const CaregiverMonitoringSnapshot(
        link: _link,
        notificationSettings: {},
        schedules: [],
      ),
    ]);
    await loading;
    await tester.pump();
    expect(find.text('0/0'), findsOneWidget);
    expect(find.text('오늘 복약 일정이 없습니다'), findsOneWidget);

    api.gate = null;
    api.snapshots = [
      const CaregiverMonitoringSnapshot(
        link: _link,
        notificationSettings: {},
        schedules: [
          MedicationSchedule(
            medicationName: '약',
            scheduleSlotKeys: ['morning', 'lunch', 'evening'],
            slotStatuses: {'morning': true, 'lunch': true, 'evening': true},
          ),
        ],
      ),
    ];
    await control.refresh();
    await tester.pump();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('오늘의 복약을 모두 완료했어요'), findsOneWidget);
    expect(find.text('남은 복약 일정'), findsNothing);

    api.failure = true;
    await control.refresh();
    await tester.pump();
    expect(find.text('복약 현황을 불러오지 못했습니다. 다시 조회해주세요.'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(find.text('복용했어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('영문과 큰 글씨에서 긴 이름·추가 약 개수를 표시하고 완료한 약은 제외한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Monitoring()
      ..snapshots = [
        const CaregiverMonitoringSnapshot(
          link: _link,
          notificationSettings: {},
          schedules: [
            MedicationSchedule(
              medicationName: 'Completed medicine',
              scheduleSlotKeys: ['morning'],
              slotStatuses: {'morning': true},
            ),
            MedicationSchedule(
              medicationName: 'A very long medication name for a narrow screen',
              scheduleSlotKeys: ['morning'],
            ),
            MedicationSchedule(
              medicationName: 'Second medicine',
              scheduleSlotKeys: ['morning'],
            ),
          ],
        ),
      ];
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(api.dispose);
    control.updateLinks([_link]);
    await control.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(2),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CaregiverHomeSummaryUI(
                  control: control,
                  isEnglish: true,
                  patientLabel: (_) =>
                      'A patient with a very long preferred name',
                  onPatientRequested: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Remaining medication'), findsOneWidget);
    expect(
      find.text(
        'Morning · A very long medication name for a narrow screen and 1 more',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Completed medicine'), findsNothing);
    expect(find.text('Taken'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
  List<CaregiverMonitoringSnapshot>? snapshots;
  Completer<List<CaregiverMonitoringSnapshot>>? gate;
  @override
  Future<List<CaregiverMonitoringSnapshot>> requestMonitoringSnapshot() async {
    calls++;
    if (failure) throw StateError('offline');
    return gate != null
        ? gate!.future
        : snapshots ?? [_snapshot(_link), _snapshot(_other)];
  }
}
