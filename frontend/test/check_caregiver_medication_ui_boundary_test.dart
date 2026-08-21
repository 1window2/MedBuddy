import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_caregiver_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/controls/set_caregiver_notification_control.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';

class _FakeCaregiverMedicationControl extends CheckCaregiverMedication {
  _FakeCaregiverMedicationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

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

class _FakeCaregiverNotificationControl extends SetCaregiverNotification {
  _FakeCaregiverNotificationControl()
    : super(baseUrl: 'http://localhost', caregiverHash: 'caregiver-a');

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

void main() {
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
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
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

  testWidgets('보호자 일정은 작은 화면과 2배 글씨에서도 시간대별 상태를 스크롤한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
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
