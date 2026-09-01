import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_reminder_settings_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';

class _FailOnceReminderSchedule extends CheckSchedule {
  int requestCount = 0;

  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      throw StateError('Schedule lookup failed.');
    }
    return const [];
  }
}

class _EmptyReminderSettings extends SetNotification {
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

void main() {
  testWidgets('reminder settings surfaces schedule errors and retries', (
    tester,
  ) async {
    final checkSchedule = _FailOnceReminderSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: _EmptyReminderSettings(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: MedicationReminderSettingsUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reminder-schedule-load-error')),
      findsOneWidget,
    );
    expect(find.text('복약 일정을 불러오지 못했습니다.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-schedule-load-retry')));
    await tester.pumpAndSettle();

    expect(checkSchedule.requestCount, 2);
    expect(find.byKey(const Key('reminder-schedule-load-error')), findsNothing);
    expect(find.text('이 시간대에 등록된 약이 없습니다'), findsNWidgets(4));
  });
}
