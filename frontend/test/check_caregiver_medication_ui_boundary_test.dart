// 파일명: check_caregiver_medication_ui_boundary_test.dart
// 역할: 보호자용 복약 진행률과 환자 일정 접근성, 화면 표시 여부에 따른 주기 갱신을 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_caregiver_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/controls/set_caregiver_notification_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 클래스명: _FakeCaregiverMedicationControl
// 역할: 아침만 완료한 환자 일정을 제공하는 보호자 조회 대역.
// 주요 책임:
// - 선택 환자의 아침 완료·점심 및 저녁 미완료 상태를 외부 조회 없이 제공한다.
class _FakeCaregiverMedicationControl extends CheckCaregiverMedication {
  // 함수이름: _FakeCaregiverMedicationControl
  // 함수역할:
  // - 보호자 caregiver-a의 로컬 조회 범위로 테스트 대역을 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 고정 보호자 범위의 조회 대역.
  _FakeCaregiverMedicationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

  // 함수이름: requestPatientMedicationInfo
  // 함수역할:
  // - 선택 환자의 아침 완료·점심 및 저녁 미완료 상태를 외부 조회 없이 제공한다.
  // 매개변수:
  // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
  // 반환값:
  // - 빈 저장 약 목록과 하루 세 번 복용 일정 한 건.
  @override
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    return (
      caregiverHash: 'caregiver-a',
      patientHash: patientHash,
      savedMedications: const <MedicationDetail>[],
      todayMedicationScheduleList: const [
        MedicationSchedule(
          medicationID: '1',
          medicationName: '테스트정',
          dosage: '1',
          intakeTime: '1일 3회',
          slotStatuses: {'morning': true, 'lunch': false, 'evening': false},
        ),
      ],
    );
  }
}

// 클래스명: _FakeCaregiverNotificationControl
// 역할: 보호자 화면의 시간대별 알림 상태를 고정하는 알림 조회 대역.
// 주요 책임:
// - 선택 환자와 시간대를 유지한 기본 보호자 알림 설정을 제공한다.
// - 모든 지원 시간대 중 아침에만 복용 완료 알림을 활성화한다.
class _FakeCaregiverNotificationControl extends SetCaregiverNotification {
  final CaregiverNotification? morning;
  // 함수이름: _FakeCaregiverNotificationControl
  // 함수역할:
  // - 보호자 caregiver-a의 로컬 알림 범위를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 고정 보호자 범위의 알림 대역.
  _FakeCaregiverNotificationControl({this.morning})
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

  // 함수이름: requestCaregiverNotificationSettings
  // 함수역할:
  // - 모든 지원 시간대 중 아침에만 복용 완료 알림을 활성화한다.
  // 매개변수:
  // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
  // 반환값:
  // - 아침 활성 및 나머지 비활성 설정을 시간대별로 담은 맵.
  @override
  Future<Map<String, CaregiverNotification>>
  requestCaregiverNotificationSettings({required String patientHash}) async {
    return {
      for (final slotKey in caregiverNotificationSlotKeys)
        slotKey: slotKey == 'morning' && morning != null ? morning! : CaregiverNotification(
          caregiverHash: 'caregiver-a',
          patientHash: patientHash,
          slotKey: slotKey,
          mode: slotKey == 'morning'
              ? CaregiverNotificationMode.doseCompleted
              : CaregiverNotificationMode.disabled,
        ),
    };
  }
}

// 클래스명: _CountingCaregiverMedicationControl
// 역할: 환자 복약 조회 횟수를 세고 필요하면 응답 시점을 테스트가 정하게 하는 보호자 조회 대역.
// 주요 책임:
// - 조회마다 횟수를 늘리고 아침 완료 여부를 바꿀 수 있는 일정 한 건을 제공한다.
// 속성:
// - requestCount (int): 지금까지 받은 환자 복약 조회 횟수.
// - morningTaken (bool): 다음 응답에 담을 아침 복용 완료 여부.
// - pendingRequests (List<Completer<void>>): holdRequests가 켜진 동안 대기 중인 조회.
class _CountingCaregiverMedicationControl extends CheckCaregiverMedication {
  int requestCount = 0;
  bool morningTaken = false;
  bool holdRequests = false;
  final List<Completer<void>> pendingRequests = [];

  // 함수이름: _CountingCaregiverMedicationControl
  // 함수역할:
  // - 보호자 caregiver-a의 로컬 조회 범위로 테스트 대역을 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 조회 횟수를 세는 조회 대역.
  _CountingCaregiverMedicationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

  // 함수이름: requestPatientMedicationInfo
  // 함수역할:
  // - 조회 횟수를 기록하고, 보류 중이면 테스트가 완료시킬 때까지 기다린 뒤 일정 한 건을 제공한다.
  // 매개변수:
  // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
  // 반환값:
  // - 응답 시점의 아침 완료 여부가 반영된 일정 한 건.
  @override
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    requestCount += 1;
    if (holdRequests) {
      final pending = Completer<void>();
      pendingRequests.add(pending);
      await pending.future;
    }
    return (
      caregiverHash: 'caregiver-a',
      patientHash: patientHash,
      savedMedications: const <MedicationDetail>[],
      todayMedicationScheduleList: [
        MedicationSchedule(
          medicationID: '1',
          medicationName: '테스트정',
          dosage: '1',
          intakeTime: '1일 1회',
          slotStatuses: {'morning': morningTaken},
        ),
      ],
    );
  }
}

// 클래스명: _CountingCaregiverNotificationControl
// 역할: 알림 설정 조회·저장 횟수를 세고 실패와 응답 시점을 테스트가 정하게 하는 알림 대역.
// 주요 책임:
// - 지정한 횟수만큼 조회를 실패시키고 이후에는 아침 복용 완료 알림 설정을 제공한다.
// - 보류 중인 조회를 테스트가 원하는 시점에 완료시키게 한다.
// 속성:
// - requestCount (int): 지금까지 받은 알림 설정 조회 횟수.
// - failuresRemaining (int): 앞으로 실패시킬 조회 횟수.
// - pendingRequests (List<Completer<void>>): holdRequests가 켜진 동안 대기 중인 조회.
// - savedModes (List<CaregiverNotificationMode>): 저장 요청으로 받은 알림 조건.
class _CountingCaregiverNotificationControl extends SetCaregiverNotification {
  int requestCount = 0;
  int failuresRemaining = 0;
  bool holdRequests = false;
  final List<Completer<void>> pendingRequests = [];
  final List<CaregiverNotificationMode> savedModes = [];

  // 함수이름: _CountingCaregiverNotificationControl
  // 함수역할:
  // - 보호자 caregiver-a의 로컬 알림 범위를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 조회 횟수를 세는 알림 대역.
  _CountingCaregiverNotificationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

  // 함수이름: requestCaregiverNotificationSettings
  // 함수역할:
  // - 조회 횟수를 기록하고 보류·실패 설정을 적용한 뒤 아침에만 복용 완료 알림을 켠 설정을 제공한다.
  // 매개변수:
  // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
  // 반환값:
  // - 시간대별 설정 맵. 실패로 지정된 조회는 StateError.
  @override
  Future<Map<String, CaregiverNotification>>
  requestCaregiverNotificationSettings({required String patientHash}) async {
    requestCount += 1;
    final shouldFail = failuresRemaining > 0;
    if (shouldFail) {
      failuresRemaining -= 1;
    }
    if (holdRequests) {
      final pending = Completer<void>();
      pendingRequests.add(pending);
      await pending.future;
    }
    if (shouldFail) {
      throw StateError('Caregiver notification lookup failed (400): test');
    }
    return {
      for (final slotKey in caregiverNotificationSlotKeys)
        slotKey: CaregiverNotification(
          caregiverHash: 'caregiver-a',
          patientHash: patientHash,
          slotKey: slotKey,
          mode: slotKey == 'morning'
              ? CaregiverNotificationMode.doseCompleted
              : CaregiverNotificationMode.disabled,
        ),
    };
  }

  // 함수이름: saveCaregiverNotificationSetting
  // 함수역할:
  // - 저장 요청의 알림 조건을 기록하고 그대로 저장된 설정을 제공한다.
  // 매개변수:
  // - patientHash, slotKey, mode, deadlineHour, deadlineMinute: 저장할 환자·시간대·조건·마감 시각.
  // 반환값:
  // - 요청 값이 반영된 알림 설정.
  @override
  Future<CaregiverNotification> saveCaregiverNotificationSetting({
    required String patientHash,
    String slotKey = 'morning',
    required CaregiverNotificationMode mode,
    int? deadlineHour,
    int? deadlineMinute,
  }) async {
    savedModes.add(mode);
    return CaregiverNotification(
      caregiverHash: 'caregiver-a',
      patientHash: patientHash,
      slotKey: slotKey,
      mode: mode,
      deadlineHour: deadlineHour,
      deadlineMinute: deadlineMinute,
    );
  }
}

// 함수이름: _pumpCaregiverScreen
// 함수역할:
// - 조회 횟수를 세는 대역으로 보호자 환자 화면을 띄우고 초기 조회가 끝날 때까지 진행한다.
// - 테스트가 바꾼 앱 생명주기 상태를 종료 시 전면 상태로 되돌린다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - control (CheckCaregiverMedication): 환자 복약 조회 대역.
// - notificationControl (SetCaregiverNotification): 알림 설정 조회·저장 대역.
// 반환값:
// - Future<void>; 화면이 초기 조회 결과를 표시하면 완료된다.
Future<void> _pumpCaregiverScreen(
  WidgetTester tester, {
  required CheckCaregiverMedication control,
  required SetCaregiverNotification notificationControl,
}) async {
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: CheckCaregiverMedicationUI(
        caregiverHash: 'caregiver-a',
        patientHash: 'patient-a',
        control: control,
        notificationControl: notificationControl,
      ),
    ),
  );
  await tester.pump();
}

// 함수이름: main
// 함수역할:
// - 보호자용 복약 진행률과 환자 일정 접근성, 주기 갱신 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // Show caregiver alert rules, not fabricated medication times, in both
  // languages and clock formats. Large text must remain readable.
  for (final language in ['en', 'ko']) {
    for (final format in ['12h', '24h']) {
      for (final mode in CaregiverNotificationMode.values) {
        testWidgets('alert label $language $format $mode', (tester) async {
          final setting = UserSetting(language: language, timeFormat: format);
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CheckCaregiverMedicationUI(
              caregiverHash: 'caregiver-a', patientHash: 'patient-a',
              userSetting: setting,
              control: _FakeCaregiverMedicationControl(),
              notificationControl: _FakeCaregiverNotificationControl(morning: CaregiverNotification(
                slotKey: 'morning', mode: mode, deadlineHour: 2, deadlineMinute: 38,
              )),
            ),
          ));
          await tester.pump();
          final expected = switch (mode) {
            CaregiverNotificationMode.disabled => language == 'en' ? 'Caregiver alerts off' : '보호자 알림 꺼짐',
            CaregiverNotificationMode.doseCompleted => language == 'en' ? 'Alert on completion' : '복용 완료 시 알림',
            CaregiverNotificationMode.missedDeadline => '${language == 'en' ? 'Missed-dose alert' : '미복용 알림'} ${setting.formatTime(2, 38)}',
          };
          expect(tester.widget<Text>(find.byKey(const ValueKey('caregiver-alert-time-morning'))).data, expected);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final width in [320.0, 411.0, 1024.0]) {
    // 함수이름: testWidgets 콜백
    // 함수역할: 기본 일정과 같은 카드 폭을 유지하고 체크 표시의 내부 공간만 제거하는지 검증한다.
    // 매개변수: tester는 화면 크기와 위젯 위치를 확인하는 테스트 제어기.
    // 반환값: 검증 완료. 카드 폭이나 이름 여백이 다르면 테스트가 실패한다.
    testWidgets('보호자 일정 카드 폭과 이름 여백을 유지한다 ($width)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: CheckCaregiverMedicationUI(
            caregiverHash: 'caregiver-a',
            patientHash: 'patient-a',
            control: _FakeCaregiverMedicationControl(),
            notificationControl: _FakeCaregiverNotificationControl(),
          ),
        ),
      );
      await tester.pump();

      final medicationName = find.text('테스트정').first;
      final medicationRow = find
          .ancestor(of: medicationName, matching: find.byType(InkWell))
          .first;
      final card = find
          .ancestor(of: medicationRow, matching: find.byType(Material))
          .first;
      final contentWidth = width.clamp(0.0, MedBuddySpacing.contentMaxWidth);
      final cardBounds = tester.getRect(card);
      expect(cardBounds.left, (width - contentWidth) / 2 + 20);
      expect(cardBounds.width, contentWidth - 40);
      expect(tester.getSize(medicationRow).width, cardBounds.width);
      expect(tester.getTopLeft(medicationName).dx, cardBounds.left + 18);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 보호자 화면은 환자의 슬롯별 복약 상태와 진행률을 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보호자 화면은 환자의 슬롯별 복약 상태와 진행률을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckCaregiverMedicationUI(
          caregiverHash: 'caregiver-a',
          patientHash: 'patient-a',
          control: _FakeCaregiverMedicationControl(),
          notificationControl: _FakeCaregiverNotificationControl(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('환자 오늘의 복약 일정'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    // 읽기 전용 화면에는 체크 모양을 남기지 않고 완료 취소선과 진행률은 보존한다.
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    final firstMedication = find.text('테스트정').first;
    expect(
      tester.widget<Text>(firstMedication).style!.decoration,
      TextDecoration.lineThrough,
    );
    final medicationRow = find
        .ancestor(of: firstMedication, matching: find.byType(InkWell))
        .first;
    expect(
      tester.getTopLeft(firstMedication).dx,
      tester.getTopLeft(medicationRow).dx + 18,
    );
    expect(
      find.byKey(const ValueKey('caregiver-notification-morning')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    for (final slotLabel in const ['아침', '점심', '저녁']) {
      await tester.scrollUntilVisible(
        find.text(slotLabel),
        220,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(slotLabel), findsOneWidget);
    }
    expect(find.text('테스트정'), findsWidgets);

    final morningNotification = find.byKey(
      const ValueKey('caregiver-notification-morning'),
    );
    await tester.scrollUntilVisible(
      morningNotification,
      -220,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(morningNotification);
    await tester.pumpAndSettle();

    expect(find.text('아침 알림 설정'), findsOneWidget);

    await tester.tap(find.text('정해진 시각까지 미복용 시 알림'));
    await tester.pump();
    // 저장된 확인 시각이 없으면 그 시간대의 복약 알림(아침 08:00) 한 시간 뒤를 제안한다. 예전 기본값 21:00은
    // 시간대와 무관해 취침 전 알림(22:00)보다 일렀다.
    final missedDoseTime = find.text('확인 시각 09:00');
    await tester.ensureVisible(missedDoseTime);
    await tester.pumpAndSettle();
    await tester.tap(missedDoseTime);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-hour-wheel')), findsOneWidget);
    expect(
      find.byKey(const Key('notification-hour-direct-input')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 보호자 일정은 작은 화면과 2배 글씨에서도 시간대별 상태를 스크롤한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보호자 일정은 작은 화면과 2배 글씨에서도 시간대별 상태를 스크롤한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 2배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CheckCaregiverMedicationUI(
          caregiverHash: 'caregiver-a',
          patientHash: 'patient-a',
          control: _FakeCaregiverMedicationControl(),
          notificationControl: _FakeCaregiverNotificationControl(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('환자 오늘의 복약 일정'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 화면이 보이는 동안 15초마다 환자 복약 상태만 조회하고 알림 설정은 다시 읽지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('보이는 화면은 15초마다 복약 상태만 다시 조회한다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl();
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );
    expect(control.requestCount, 1);
    expect(notificationControl.requestCount, 1);

    await tester.pump(const Duration(seconds: 14));
    expect(control.requestCount, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(control.requestCount, 2);
    await tester.pump(const Duration(seconds: 15));
    expect(control.requestCount, 3);
    expect(notificationControl.requestCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 앱이 전면을 벗어나면 주기 조회를 멈추고, 돌아오면 15초를 기다리지 않고 즉시 복약 상태와 알림 설정을 다시 읽는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('앱이 전면을 벗어나면 조회를 멈추고 복귀하면 즉시 다시 조회한다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl();
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );
    expect(find.text('0/1'), findsOneWidget);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    // 15초의 배수가 아닌 시간 동안 떠나 있어 복귀 뒤 주기가 새로 시작되는지 구분한다.
    await tester.pump(const Duration(seconds: 50));
    expect(control.requestCount, 1);
    expect(notificationControl.requestCount, 1);

    // 화면을 떠나 있는 동안 환자가 아침 약을 복용했다.
    control.morningTaken = true;
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    // 가짜 시계를 15초 주기만큼 진행하지 않아도 복귀 즉시 조회한다.
    await tester.pump();
    expect(control.requestCount, 2);
    expect(notificationControl.requestCount, 2);
    await tester.pump();
    expect(find.text('1/1'), findsOneWidget);

    // 복귀 시점부터 주기가 다시 시작된다.
    await tester.pump(const Duration(seconds: 14));
    expect(control.requestCount, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(control.requestCount, 3);
    expect(notificationControl.requestCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 다른 화면이 위에 열려 있는 동안 조회를 멈추고, 그 화면이 닫히면 즉시 복약 상태를 다시 읽는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('다른 화면에 가려지면 조회를 멈추고 돌아오면 즉시 다시 조회한다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl();
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );
    expect(control.requestCount, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        // 함수이름: builder 콜백
        // 함수역할: 보호자 화면을 가리는 빈 화면을 제공한다.
        // 매개변수: context (BuildContext): 사용하지 않는 위젯 컨텍스트.
        // 반환값: 표식 문구만 가진 화면.
        builder: (context) => const Scaffold(body: Text('covering-route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('covering-route'), findsOneWidget);
    expect(control.requestCount, 1);

    await tester.pump(const Duration(seconds: 60));
    expect(control.requestCount, 1);

    control.morningTaken = true;
    navigator.pop();
    // 닫히는 전환이 끝나거나 15초가 지나기 전에 조회가 시작된다.
    await tester.pump();
    expect(control.requestCount, 2);
    expect(notificationControl.requestCount, 1);
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    expect(control.requestCount, 3);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 복귀 시점에 이전 조회가 아직 끝나지 않았으면 그 조회가 끝난 직후 한 번 더 조회해 오래된 응답으로 끝나지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('복귀 때 진행 중이던 조회가 끝나면 바로 한 번 더 조회한다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl();
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );

    control.holdRequests = true;
    await tester.pump(const Duration(seconds: 15));
    expect(control.requestCount, 2);
    expect(control.pendingRequests, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // 진행 중인 조회와 겹치지 않도록 새 조회는 아직 보내지 않는다.
    expect(control.requestCount, 2);

    control.holdRequests = false;
    control.morningTaken = true;
    control.pendingRequests.single.complete();
    await tester.pump();
    expect(control.requestCount, 3);
    await tester.pump();
    expect(find.text('1/1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 첫 알림 설정 조회가 실패해도 주기마다 다시 조회하지 않고, 알림 버튼을 누르면 다시 조회해 설정 창을 연다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('알림 설정 첫 조회가 실패하면 알림 버튼에서 다시 조회한다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl()
      ..failuresRemaining = 1;
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('caregiver-alert-time-morning')),
          )
          .data,
      '알림 설정 확인 필요',
    );

    await tester.pump(const Duration(seconds: 45));
    expect(control.requestCount, 4);
    expect(notificationControl.requestCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('caregiver-notification-morning')),
    );
    await tester.pumpAndSettle();
    expect(notificationControl.requestCount, 2);
    expect(find.text('아침 알림 설정'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 설정이 없는 상태에서 배경 조회가 진행 중일 때 알림 버튼을 눌러도 무시되지 않고, 그 조회가 끝나면 설정 창이 열린다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('배경 설정 조회 중에 누른 알림 버튼은 조회가 끝나면 설정 창을 연다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl()
      ..failuresRemaining = 1;
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );

    // 앱 복귀가 진행 표시 없는 설정 조회를 시작하고 응답은 아직 오지 않았다.
    notificationControl.holdRequests = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(notificationControl.requestCount, 2);
    expect(notificationControl.pendingRequests, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey('caregiver-notification-morning')),
    );
    await tester.pump();
    // 같은 조회 결과를 기다리며 진행 표시를 보여주고 중복 요청은 보내지 않는다.
    expect(notificationControl.requestCount, 2);
    expect(
      find.byKey(const ValueKey('caregiver-notification-morning')),
      findsNothing,
    );
    expect(find.text('아침 알림 설정'), findsNothing);

    notificationControl.pendingRequests.single.complete();
    await tester.pumpAndSettle();
    expect(notificationControl.requestCount, 2);
    expect(find.text('아침 알림 설정'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 저장보다 먼저 시작된 설정 조회의 늦은 응답이 방금 저장한 알림 설정을 덮어쓰지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('늦게 도착한 설정 조회가 방금 저장한 알림 설정을 덮어쓰지 않는다', (tester) async {
    final control = _CountingCaregiverMedicationControl();
    final notificationControl = _CountingCaregiverNotificationControl();
    await _pumpCaregiverScreen(
      tester,
      control: control,
      notificationControl: notificationControl,
    );
    final alertLabel = find.byKey(
      const ValueKey('caregiver-alert-time-morning'),
    );
    expect(tester.widget<Text>(alertLabel).data, '복용 완료 시 알림');

    notificationControl.holdRequests = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(notificationControl.pendingRequests, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey('caregiver-notification-morning')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('끄기'));
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(notificationControl.savedModes, [
      CaregiverNotificationMode.disabled,
    ]);
    expect(tester.widget<Text>(alertLabel).data, '보호자 알림 꺼짐');

    // 저장 전에 시작된 조회는 아침을 여전히 "복용 완료 시 알림"으로 돌려준다.
    notificationControl.pendingRequests.single.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Text>(alertLabel).data, '보호자 알림 꺼짐');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
