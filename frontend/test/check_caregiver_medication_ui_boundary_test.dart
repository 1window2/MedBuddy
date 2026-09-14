// 파일명: check_caregiver_medication_ui_boundary_test.dart
// 역할: 보호자용 복약 진행률과 환자 일정 접근성을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_caregiver_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/controls/set_caregiver_notification_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
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
  // 함수이름: _FakeCaregiverNotificationControl
  // 함수역할:
  // - 보호자 caregiver-a의 로컬 알림 범위를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 고정 보호자 범위의 알림 대역.
  _FakeCaregiverNotificationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

  // 함수이름: requestCaregiverNotificationSetting
  // 함수역할:
  // - 선택 환자와 시간대를 유지한 기본 보호자 알림 설정을 제공한다.
  // 매개변수:
  // - patientHash (String): 요청 데이터 범위를 제한하는 환자 식별자.
  // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키.
  // 반환값:
  // - 요청 범위가 반영된 기본 알림 설정.
  @override
  Future<CaregiverNotification> requestCaregiverNotificationSetting({
    required String patientHash,
    String slotKey = 'morning',
  }) async {
    return CaregiverNotification(
      caregiverHash: 'caregiver-a',
      patientHash: patientHash,
      slotKey: slotKey,
    );
  }

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
}

// 함수이름: main
// 함수역할:
// - 보호자용 복약 진행률과 환자 일정 접근성 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
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
    final missedDoseTime = find.text('확인 시각 21:00');
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
}
