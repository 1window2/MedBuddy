// 파일명: check_caregiver_home_control_test.dart
// 역할: 보호자 홈의 계정·연동 범위, 오류와 진행률을 검증한다.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
// 함수이름: main
// 매개변수: 없음. 반환값: 없음.
void main() {
  test('알림이 꺼져 있어도 홈은 상세 화면과 같은 환자 일정을 조회한다', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.url.queryParameters['caregiver_hash'], 'owner');
      // The monitoring API deliberately omits schedules when all alerts are off.
      final monitoring = request.url.path.endsWith('/monitoring');
      return http.Response(jsonEncode({
        'success': true,
        'data': monitoring ? {
          'patients': [{
            'link': _link.toJson(),
            'notification_settings': [],
            'today_medication_info': {'schedules': []},
          }],
        } : {
          'caregiver_hash': 'owner',
          'patient_hash': 'patient',
          'saved_medications': [],
          'today_medication_info': {'schedules': [{
            'medication_id': '1',
            'patient_hash': 'patient',
            'medication_name': 'Scheduled medicine',
            'schedule_slot_keys': ['morning', 'lunch', 'evening'],
          }]},
        },
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final api = CheckCaregiverMedication(
      caregiverHash: 'owner', baseUrl: 'http://medbuddy.test', client: client,
    );
    final control = CheckCaregiverHome(userHash: 'owner', control: api);
    addTearDown(control.dispose);
    addTearDown(client.close);
    final detail = await api.requestPatientMedicationInfo(patientHash: 'patient');
    control.updateLinks([_link]);
    await control.refresh();
    expect(control.hasError, isFalse);
    expect(control.snapshotFor(1)?.schedules, hasLength(1));
    expect(control.snapshotFor(1)!.schedules.single.slotKeys,
        detail.todayMedicationScheduleList.single.slotKeys);
    expect(paths, ['/caregiver/medications/patient', '/caregiver/medications/patient']);
    expect(control.hasError, isFalse);
  });

  for (final scope in [
    (caregiver: 'someone', patient: 'patient'),
    (caregiver: 'owner', patient: 'other'),
  ]) {
    test('상세 응답의 보호자와 환자 범위가 다르면 오류로 표시한다: $scope', () async {
      final client = MockClient((request) async => http.Response(jsonEncode({
        'data': {
          'caregiver_hash': scope.caregiver,
          'patient_hash': scope.patient,
          'saved_medications': [],
          'today_medication_info': {'schedules': []},
        },
      }), 200));
      final api = CheckCaregiverMedication(
        caregiverHash: 'owner', baseUrl: 'http://medbuddy.test', client: client,
      );
      final control = CheckCaregiverHome(userHash: 'owner', control: api);
      addTearDown(control.dispose);
      addTearDown(client.close);
      control.updateLinks([_link]);
      await control.refresh();
      expect(control.hasError, isTrue);
      expect(control.isLoading, isFalse);
      expect(control.snapshotFor(1), isNull);
    });
  }

  // 함수이름: 보호자 연동 범위 테스트
  // 함수역할: 현재 보호자의 활성 연동만 조회하고 다른 계정의 결과와 환자 역할의 보호자 조회를 제외하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 조회 실패·복구 테스트
  // 함수역할: 통신 실패를 빈 일정과 구분하며 재조회 성공 후 오류 상태가 해제되는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 지연 응답 무효화 테스트
  // 함수역할: 연동 해제나 컨트롤 종료 뒤 도착한 조회 결과가 환자 목록을 복원하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
    // 함수이름: 환자 요약 접근성 테스트
    // 함수역할: 큰 글씨에서도 별칭·진행률과 일정 상세 진입이 유지되고 보호자에게 복용 버튼이 표시되지 않는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
      expect(
        find.byKey(const Key('caregiver-patient-page-indicator')),
        findsNothing,
      );
      expect(find.byType(HomeMedicationPreview), findsOneWidget);
      expect(find.text('오늘의 복약 진행률'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.byKey(const Key('home-slot-page-lunch')), findsOneWidget);
      expect(find.text('약'), findsOneWidget);
      expect(find.text('점심 · 미복용'), findsOneWidget);
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
      await tester.tap(find.text('엄마'));
      expect(selected, _link);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    // 함수이름: 환자·시간대 탐색 분리 테스트
    // 함수역할: 이름 옆 화살표는 환자를 바꾸고 카드 슬라이드는 시간대만 바꾸며 화면 밖 환자와 혼동하지 않는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
    testWidgets('환자는 이름 옆 화살표로만 바꾸고 슬라이드는 시간대만 전환한다: $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
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
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('1 / 2'), findsNothing);
      expect(find.text('2 / 2'), findsNothing);
      final indicator = find.byKey(
        const Key('caregiver-patient-page-indicator'),
      );
      expect(indicator, findsNothing);
      final previous = find.byKey(const Key('caregiver-patient-previous'));
      final next = find.byKey(const Key('caregiver-patient-next'));
      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      expect(tester.widget<IconButton>(next).onPressed, isNotNull);
      expect(
        find.descendant(of: find.byType(HomeMedicationPreview), matching: next),
        findsOneWidget,
      );
      expect(tester.getSize(previous), const Size(48, 48));
      expect(tester.getSize(next), const Size(48, 48));
      final cardRect = tester.getRect(find.byType(HomeMedicationPreview));
      final titleRect = tester.getRect(find.text('엄마'));
      expect(tester.getRect(previous).right, lessThanOrEqualTo(titleRect.left));
      expect(tester.getRect(next).left, greaterThanOrEqualTo(titleRect.right));
      expect(tester.getRect(previous).right, closeTo(titleRect.left, .01));
      expect(tester.getRect(next).left, closeTo(titleRect.right, .01));
      expect(tester.getCenter(previous).dy, closeTo(titleRect.center.dy, .01));
      expect(tester.getCenter(next).dy, closeTo(titleRect.center.dy, .01));
      expect(cardRect.contains(tester.getRect(next).bottomRight), isTrue);
      await tester.tap(find.byKey(const Key('caregiver-home-refresh')));
      expect(refreshes, 1);
      expect(selected, isNull);
      // 아래 시간대 탐색은 상위 환자 넘김 제스처로 전달하지 않는다.
      final slotPager = find.byKey(const Key('home-medication-slot-pager'));
      for (var step = 0; step < 3; step++) {
        await tester.drag(slotPager, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(find.text('엄마'), findsOneWidget);
      }
      expect(find.byKey(const Key('home-slot-page-bedtime')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.ensureVisible(find.text('엄마'));
      await tester.drag(find.text('엄마'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('엄마'), findsOneWidget);
      expect(find.byKey(const Key('home-slot-page-bedtime')), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(previous).onPressed, isNotNull);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      expect(find.byKey(const Key('caregiver-home-patient-1')), findsNothing);
      await tester.tap(find.text('아빠'));
      expect(selected, second);
      selected = null;
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('엄마'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byKey(const Key('caregiver-home-patient-3')), findsOneWidget);
      await tester.drag(find.text('아빠'), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(find.text('아빠'), findsOneWidget);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(find.text('엄마'), findsOneWidget);
      control.updateLinks([second, _link]);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      expect(find.byKey(const Key('caregiver-home-patient-1')), findsOneWidget);
      control.updateLinks([second]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('caregiver-home-patient-3')), findsOneWidget);
      expect(indicator, findsNothing);
      expect(previous, findsNothing);
      expect(next, findsNothing);
      expect(find.byKey(const Key('caregiver-home-patient-1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      // 함수이름: 보호자 제목 반응형 배치 테스트
      // 함수역할: 기본 크기에서는 카드 높이를 유지하고 좁은 화면의 큰 글씨에서는 잘림 없이 줄바꿈하는지 검증한다.
      // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
      testWidgets('하트와 이름 양옆 화살표는 화면 폭과 글씨 크기에 맞게 배치된다: $width, $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // 함수이름: showPreview
        // 함수역할: 같은 제목과 진행률에서 환자 전환 버튼의 유무만 바꿔 배치를 비교한다.
        // 매개변수: navigation: 화살표·새로고침 표시 여부. 반환값: 화면 갱신 완료.
        Future<void> showPreview({required bool navigation}) =>
            tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: HomeMedicationPreview(
                      title: '환자',
                      progressTitle: '오늘의 복약 진행률',
                      progressLabel: '1/3',
                      progress: 1 / 3,
                      scheduleTitle: '남은 복약 일정',
                      scheduleDescription: '점심 · 테스트 약',
                      hasPendingMedication: true,
                      compact: width >= 350,
                      onTap: () {},
                      titleLeading: navigation
                          ? IconButton(
                              tooltip: '이전 환자',
                              onPressed: () {},
                              icon: const Icon(Icons.chevron_left),
                            )
                          : null,
                      titleTrailing: navigation
                          ? IconButton(
                              tooltip: '다음 환자',
                              onPressed: () {},
                              icon: const Icon(Icons.chevron_right),
                            )
                          : null,
                      headerAction: navigation
                          ? IconButton(
                              tooltip: '새로고침',
                              onPressed: () {},
                              icon: const Icon(Icons.refresh),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            );
        await showPreview(navigation: false);
        final patientSize = tester.getSize(find.byType(HomeMedicationPreview));
        await showPreview(navigation: true);
        final caregiverSize = tester.getSize(
          find.byType(HomeMedicationPreview),
        );
        expect(caregiverSize.width, patientSize.width);
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        if ((width >= 390 && scale == 1) || width >= 800) {
          expect(caregiverSize, patientSize);
        } else {
          expect(
            caregiverSize.height,
            greaterThanOrEqualTo(patientSize.height),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: 환자 요약 상태 구분 테스트
  // 함수역할: 조회 전·빈 일정·모두 완료·통신 실패를 서로 다른 문구와 동작으로 표시하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
    expect(find.textContaining('복약 현황 확인 필요'), findsOneWidget);

    api.gate = Completer<List<CaregiverMonitoringSnapshot>>();
    final loading = control.refresh();
    await tester.pump();
    expect(find.textContaining('복약 현황 확인 중'), findsOneWidget);
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
    expect(find.text('이 시간대에 등록된 약이 없습니다.'), findsOneWidget);

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
    expect(find.text('아침 · 복용 완료'), findsOneWidget);
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

  // 함수이름: 영문 시간대 요약 테스트
  // 함수역할: 큰 영문 글씨에서도 완료 수와 약 이름을 간단히 표시하고 불필요한 탭이나 복용 버튼이 생기지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  testWidgets('영문과 큰 글씨에서도 시간대별 완료 수와 약 이름을 간단히 요약한다', (tester) async {
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
    expect(find.byKey(const Key('home-slot-page-morning')), findsOneWidget);
    expect(find.text('Morning · 1/3 taken'), findsOneWidget);
    expect(find.text('Completed medicine +2 more'), findsOneWidget);
    expect(find.text('Second medicine'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// 함수역할: 시간대별 일부 완료를 포함하는 오늘 복약 조회 대역을 만든다.
// 함수이름: _snapshot
// 매개변수: link: 조회 결과에 포함할 환자 연동. 반환값: 아침만 완료된 세 시간대의 환자 조회 결과.
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
  // 함수이름: requestPatientMedicationInfo
  // 함수역할: 조회 횟수를 기록하고 지정한 응답·실패·지연으로 계정 전환 경합을 재현한다.
  // 매개변수: patientHash: 조회할 환자. 반환값: 환자 조회 결과 Future; 실패 설정 시 StateError.
  @override
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    calls++;
    if (failure) throw StateError('offline');
    final results = gate != null
        ? await gate!.future
        : snapshots ?? [_snapshot(_link), _snapshot(_other)];
    final snapshot = results.firstWhere((s) => s.patientHash == patientHash);
    return (
      caregiverHash: snapshot.link.caregiverHash,
      patientHash: snapshot.patientHash,
      savedMedications: const <Never>[],
      todayMedicationScheduleList: snapshot.schedules,
    );
  }
}
