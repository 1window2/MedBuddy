import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
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
        scheduleSlotKeys: ['morning'],
      ),
    ];
  }
}

// 클래스명: _CompletableCheckSchedule
// 역할: 복약 완료 안내와 실행 취소 SnackBar의 표시 시간을 검증할 일정을 제공한다.
class _CompletableCheckSchedule extends CheckSchedule {
  bool _completed = false;

  MedicationSchedule get _schedule => MedicationSchedule(
    medicationID: 'completion-tablet',
    medicationName: '테스트정',
    dosage: '1',
    intakeTime: '1회',
    medicationTime: 1,
    scheduleSlotKeys: const ['morning'],
    slotStatuses: {'morning': _completed},
    medicationStatus: _completed,
  );

  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return [_schedule];
  }

  @override
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    _completed = medicationStatus;
    return _schedule;
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
        imageUrl: 'https://nedrug.mfds.go.kr/tablet.png',
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

// 클래스명: _MutableSetNotification
// 역할: 일정 화면에서 알림 설정과 해제 성공 안내를 검증할 수 있도록 상태를 저장한다.
class _MutableSetNotification extends SetNotification {
  MedicationAlarm _setting = const MedicationAlarm(
    slotKey: 'morning',
    hour: 8,
    minute: 0,
    enabled: false,
  );

  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => [_setting];

  @override
  Future<MedicationAlarm> saveNotificationSetting({
    required String slotKey,
    required int hour,
    required int minute,
  }) async {
    _setting = MedicationAlarm(
      slotKey: slotKey,
      hour: hour,
      minute: minute,
      enabled: true,
    );
    return _setting;
  }

  @override
  Future<MedicationAlarm> disableAlarmSetting(String slotKey) async {
    _setting = _setting.copyWith(enabled: false);
    return _setting;
  }

  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) async {}
}

// 클래스명: _SuccessfulNotificationService
// 역할: 플랫폼 알림 예약과 취소가 성공한 상황을 일정 화면 테스트에 제공한다.
class _SuccessfulNotificationService implements NotificationService {
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
  }) async {}

  @override
  Future<void> cancelReminder(int id) async {}

  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
  }) async {}
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

  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
  }) async {}
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

  testWidgets('영문 일정 화면은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: _EmptySetNotification(),
      manageUserSetting: ManageUserSetting(useRemotePersistence: false),
    );
    addTearDown(viewModel.dispose);
    await viewModel.requestUserSettingSave(
      fontSizeOption: 'large',
      readingSpeedOption: 'medium',
      language: 'en',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const CheckScheduleUI(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Today's Medication Schedule"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('알림 설정과 해제 완료 결과를 화면 하단에 안내한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _MutableSetNotification(),
      notificationService: _SuccessfulNotificationService(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();

    final morningReminder = find.byTooltip('아침 알림 설정');
    await tester.tap(morningReminder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(viewModel.statusMessage, '아침 알림이 08:00으로 설정되었습니다.');
    expect(find.text(viewModel.statusMessage), findsOneWidget);

    await tester.tap(morningReminder);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('아침 알림이 해제되었습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('복약 완료 안내는 접근성 모드에서도 5초 뒤 자동으로 닫힌다', (tester) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _CompletableCheckSchedule(),
      setNotification: _EmptySetNotification(),
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
              child: child!,
            );
          },
          home: const CheckScheduleUI(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('복용 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsNothing);
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
