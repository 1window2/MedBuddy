import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailOnceCheckSchedule extends CheckSchedule {
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

class _EmptyCheckSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

class _SuccessfulThenFailingCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      return const [
        MedicationSchedule(
          medicationName: 'stale-tablet',
          intakeTime: '1 time',
          medicationTime: 1,
        ),
      ];
    }
    throw StateError('Schedule lookup failed.');
  }
}

class _ActiveCheckSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationName: 'active-tablet',
        intakeTime: '1 time',
        medicationTime: 1,
      ),
    ];
  }
}

// 클래스명: _VisualScheduleCheckSchedule
// 역할: 투약 단위와 약품 이미지 표시 테스트용 일정을 제공한다.
class _VisualScheduleCheckSchedule extends CheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationID: 'visual-tablet',
        medicationName: '테스트정',
        dosage: '0.5',
        intakeTime: '1회',
        medicationTime: 1,
        imageUrl: 'https://example.com/tablet.png',
      ),
    ];
  }
}

class _EmptySetNotification extends SetNotification {
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

class _EnabledSetNotification extends SetNotification {
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [
      MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
    ];
  }
}

class _FailingNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) async {
    throw StateError('Notification registration failed.');
  }

  @override
  Future<void> cancelReminder(int id) async {}
}

void main() {
  testWidgets('schedule API failure shows a retry state', (tester) async {
    final checkSchedule = _FailOnceCheckSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('schedule-load-error')), findsOneWidget);
    expect(find.byKey(const Key('schedule-load-retry')), findsOneWidget);
    expect(checkSchedule.requestCount, 1);

    await tester.tap(find.byKey(const Key('schedule-load-retry')));
    await tester.pumpAndSettle();

    expect(checkSchedule.requestCount, 2);
    expect(find.byKey(const Key('schedule-load-error')), findsNothing);
    expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
  });

  testWidgets('valid empty schedule keeps the domain empty state', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _EmptyCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('schedule-load-error')), findsNothing);
    expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
  });

  testWidgets('오늘 일정에 투약 단위와 약품 이미지 영역을 표시한다', (tester) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('0.5정'), findsOneWidget);
    expect(
      find.byKey(const Key('schedule-medication-thumbnail-visual-tablet')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('failed refresh clears stale schedule data', () async {
    final checkSchedule = _SuccessfulThenFailingCheckSchedule();
    final viewModel = MedBuddyViewModel(checkSchedule: checkSchedule);
    addTearDown(viewModel.dispose);

    await viewModel.fetchTodayMedicationSchedule();
    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);

    await viewModel.fetchTodayMedicationSchedule();
    expect(viewModel.todayMedicationScheduleList, isEmpty);
    expect(viewModel.hasTodayScheduleLoadError, isTrue);
  });

  test('reminder sync failure does not discard a loaded schedule', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _EnabledSetNotification(),
      notificationService: _FailingNotificationService(),
    );
    addTearDown(viewModel.dispose);

    await expectLater(viewModel.refreshMedicationSchedule(), completes);

    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);
    expect(viewModel.statusMessage, contains('알림을 동기화하지 못했습니다'));
  });
}
