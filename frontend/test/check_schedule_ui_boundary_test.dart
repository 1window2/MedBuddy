// 파일명: check_schedule_ui_boundary_test.dart
// 역할: 일정 조회·알림 설정의 저장과 취소·기존 화면 배치·복약 완료를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/health_recommendation_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/health_recommendation_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dose_sync_harness.dart';
import 'support/fake_controls.dart';
import 'support/fake_notification_service.dart';

// Class Name: _FailOnceCheckSchedule
// Role: Schedule stub that fails its first read and then permits a successful retry.
// Responsibilities:
// - Count schedule reads, reject the first, and return an empty successful retry.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _FailOnceCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Count schedule reads, reject the first, and return an empty successful retry.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule after the first call; the first call throws StateError.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    if (requestCount == 1) {
      throw StateError('Schedule lookup failed.');
    }
    return const [];
  }
}

// Class Name: _SuccessfulThenFailingCheckSchedule
// Role: Schedule stub that supplies stale data once and fails subsequent refreshes.
// Responsibilities:
// - Return an initial tablet, then fail refreshes to exercise stale-data clearing.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _SuccessfulThenFailingCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Return an initial tablet, then fail refreshes to exercise stale-data clearing.
  // Parameters:
  // - None.
  // Returns:
  // - One initial schedule; later calls throw StateError.
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

// 클래스명: _ActiveCheckSchedule
// 역할: 활성 아침 복약 일정을 제공해 알림 동기화 실패와 일정 로딩을 분리하는 대역.
// 주요 책임:
// - 아침 시간대가 명시된 활성 약 일정을 제공한다.
class _ActiveCheckSchedule extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 아침 시간대가 명시된 활성 약 일정을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 아침에 한 번 복용하는 일정 한 건.
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

// Class Name: _MorningDoseCheckSchedule
// Role: Schedule stub with one pending morning dose for the dose-recording widget tests.
// Responsibilities:
// - Serve a single morning medication whose id is numeric, as saved medications are.
// - Count direct status requests, which the outbox path used by the app must never issue.
// Attributes:
// - directUpdateCount (int): Number of direct per-dose or whole-slot status requests.
class _MorningDoseCheckSchedule extends CheckSchedule {
  int directUpdateCount = 0;

  // 함수이름: _schedule
  // 함수역할:
  // - 서버에 아직 복용 기록이 없는 아침 약 일정을 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 아침 미완료 상태의 테스트 약 일정.
  MedicationSchedule get _schedule => const MedicationSchedule(
    medicationID: '91',
    medicationName: '테스트정',
    dosage: '1',
    intakeTime: '1회',
    medicationTime: 1,
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': false},
  );

  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 서버가 아는 상태(아침 미완료)를 조회 결과로 제공한다. 기기에만 저장된 기록은 포함하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 아침 일정 한 건.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return [_schedule];
  }

  // 함수이름: updateMedicationStatus
  // 함수역할:
  // - 대기열을 거치지 않은 직접 상태 변경 요청을 센다.
  // 매개변수:
  // - medicationId (String): 선택한 저장 약 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - medicationStatus (bool): 요청한 복약 완료 또는 미완료 상태. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 변경하지 않은 일정.
  @override
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    directUpdateCount += 1;
    return _schedule;
  }

  // Function Name: updateMedicationSlotStatus
  // Description:
  // - Count a direct whole-slot status request that bypassed the dose queue.
  // Parameters:
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Not used.
  // - medicationStatus (bool): Requested taken/untaken completion state. Not used.
  // Returns:
  // - The unchanged schedule as a one-item list.
  @override
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    directUpdateCount += 1;
    return [_schedule];
  }
}

// Class Name: _VisualScheduleCheckSchedule
// Role: Visual schedule fixture for explicit dosage units and medication-image rendering.
// Responsibilities:
// - Supply a half-tablet dose and trusted image URL for visual schedule assertions.
class _VisualScheduleCheckSchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Supply a half-tablet dose and trusted image URL for visual schedule assertions.
  // Parameters:
  // - None.
  // Returns:
  // - One once-daily schedule with an explicit dosage unit and image.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationID: 'visual-tablet',
        medicationName: '테스트정',
        dosage: '0.5정',
        intakeTime: '1회',
        medicationTime: 1,
        imageUrl: 'https://nedrug.mfds.go.kr/tablet.png',
      ),
    ];
  }
}

// 클래스명: _EnabledSetNotification
// 역할: 오전 8시 활성 알림을 제공하는 조회 대역.
// 주요 책임:
// - 아침 시간대의 오전 8시 활성 알림을 제공한다.
class _EnabledSetNotification extends SetNotification {
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 아침 시간대의 오전 8시 활성 알림을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 활성 아침 알림 한 건.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [
      MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
    ];
  }
}

// 클래스명: _MutableSetNotification
// 역할: 알림 상태와 저장·해제 요청 횟수를 추적한다.
// 주요 책임: 플랫폼 알림 없이 설정창 취소·저장에 따른 변경을 검증한다.
// 속성: _setting은 현재 알림, saveCount·disableCount는 영속화 요청 횟수.
class _MutableSetNotification extends SetNotification {
  MedicationAlarm _setting;
  int saveCount = 0;
  int disableCount = 0;

  // 함수이름: _MutableSetNotification
  // 함수역할: enabled로 초기 활성 상태를 지정한다. 반환값: 변경 추적 가능한 알림 대역.
  _MutableSetNotification({bool enabled = false, int hour = 8, int minute = 0})
    : _setting = MedicationAlarm(
        slotKey: 'morning',
        hour: hour,
        minute: minute,
        enabled: enabled,
      );

  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 가장 최근에 저장하거나 비활성화한 알림 상태를 조회한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 알림 설정 한 건.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async => [_setting];

  // 함수이름: saveNotificationSetting
  // 함수역할:
  // - 선택한 시간대와 시각을 저장하고 알림을 활성화한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키.
  // - hour (int): 24시간제 기준 선택 알림 시.
  // - minute (int): 선택한 로컬 알림 시각의 분 값.
  // 반환값:
  // - 갱신된 활성 알림 설정.
  @override
  Future<MedicationAlarm> saveNotificationSetting({
    required String slotKey,
    required int hour,
    required int minute,
  }) async {
    saveCount += 1;
    _setting = MedicationAlarm(
      slotKey: slotKey,
      hour: hour,
      minute: minute,
      enabled: true,
    );
    return _setting;
  }

  // 함수이름: disableAlarmSetting
  // 함수역할:
  // - 기존 알림 시각을 보존한 채 활성 상태만 해제한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 비활성으로 바뀐 현재 알림 설정.
  @override
  Future<MedicationAlarm> disableAlarmSetting(String slotKey) async {
    disableCount += 1;
    _setting = _setting.copyWith(enabled: false);
    return _setting;
  }

  // Function Name: registerNotification
  // Description:
  // - Accept reminder registration without creating a real device notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
  //   consumed by this fixture.
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {}
}

// 클래스명: _ScheduleHealthRecommendation
// 역할: 일정에서 건강 추천으로 이동할 때 서버 없이 정상 결과를 제공한다.
// 주요 책임: 실제 추천 화면의 경로와 복귀를 검증할 데이터를 반환한다.
class _ScheduleHealthRecommendation extends CheckHealthRecommendation {
  // 함수이름: requestHealthRecommendation
  // 함수역할: language와 무관한 고정 추천을 반환한다. 반환값: 정상 건강 추천 Future.
  @override
  Future<HealthRecommendation> requestHealthRecommendation({
    String language = 'ko',
  }) async {
    return const HealthRecommendation(
      dietRecommendation: '식사 추천',
      exerciseRecommendation: '운동 추천',
      cautionItems: [],
      medicationNames: ['테스트정'],
    );
  }
}

// 함수이름: _pumpReminderSchedule
// 함수역할: tester에 알림 대역 notification과 textScale 글씨 배율을 적용한 일정을 표시한다. 반환값: 생성한 화면 모델.
Future<MedBuddyViewModel> _pumpReminderSchedule(
  WidgetTester tester,
  _MutableSetNotification notification, {
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final viewModel = MedBuddyViewModel(
    checkSchedule: _ActiveCheckSchedule(),
    setNotification: notification,
    notificationService: RecordingNotificationService(),
  );
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: viewModel,
      child: MaterialApp(
        // 함수역할: context의 child에 요청한 글씨 배율을 적용한다. 반환값: 접근성 설정을 가진 화면 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CheckScheduleUI(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return viewModel;
}

// 함수이름: _editReminderHour
// 함수역할: tester로 설정창의 시간을 hour로 수정하고 시간창만 확정한다. 반환값: 조작 완료 Future.
Future<void> _editReminderHour(WidgetTester tester, String hour) async {
  await tester.tap(find.byKey(const Key('schedule-reminder-edit-time')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notification-hour-direct-input')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('notification-direct-time-field')),
    hour,
  );
  await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notification-time-confirm')));
  await tester.pumpAndSettle();
}

// 함수이름: _pumpDoseSchedule
// 함수역할: 운영 앱과 같이 복용 기록 대기열을 붙인 일정 화면을 tester에 표시한다.
// 매개변수: tester, checkSchedule - 아침 약 일정 대역, showBackButton - 전송 상태 줄을 함께 표시할지,
//   accessibleNavigation - 접근성 탐색 모드 여부.
// 반환값: 대기열에 저장된 기록을 확인할 수 있는 하네스. 테스트 본문 끝에서 닫아야 한다.
Future<DoseSyncHarness> _pumpDoseSchedule(
  WidgetTester tester,
  _MorningDoseCheckSchedule checkSchedule, {
  bool showBackButton = false,
  bool accessibleNavigation = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final viewModel = MedBuddyViewModel(
    checkSchedule: checkSchedule,
    setNotification: EmptySetNotification(),
    notificationService: RecordingNotificationService(),
  );
  final harness = await attachTestDoseSync(viewModel);
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: viewModel,
      child: MaterialApp(
        // 함수역할: context의 child에 접근성 탐색 모드 설정을 적용한다. 반환값: 설정을 덮어쓴 화면 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(accessibleNavigation: accessibleNavigation),
          child: child!,
        ),
        home: CheckScheduleUI(showBackButton: showBackButton),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

// 함수이름: _closeDoseSchedule
// 함수역할: 화면을 내리고 하네스를 닫아 동기화 서비스의 재시도 타이머가 테스트 뒤에 남지 않게 한다.
// 매개변수: tester, harness - 닫을 하네스. 반환값: 정리 완료 Future.
Future<void> _closeDoseSchedule(
  WidgetTester tester,
  DoseSyncHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.close();
}

// 함수이름: main
// 함수역할: 일정·알림·화면 배치·접근성 회귀 사례를 등록한다. 매개변수·반환값: 없음.
void main() {
  // A configured reminder is not a prescribed dose time; disabled alarms must
  // not revert to a hard-coded 08:00 label. Viewing never saves a setting.
  for (final enabled in [true, false]) {
    testWidgets('patient header identifies reminder state $enabled', (tester) async {
      final notification = _MutableSetNotification(enabled: enabled, hour: 2, minute: 38);
      final model = await _pumpReminderSchedule(tester, notification, textScale: 2);
      expect(tester.widget<Text>(find.byKey(const ValueKey('patient-alert-time-morning'))).data,
        enabled ? '복약 알림 02:38' : '복약 알림 꺼짐');
      expect(notification.saveCount, 0);
      expect(model.medicationReminderSettings['morning']!.isEnabled, enabled);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: schedule API failure shows a retry state.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('schedule API failure shows a retry state', (tester) async {
    final checkSchedule = _FailOnceCheckSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: EmptySetNotification(),
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 빈 일정에서 기존 안내 카드를 표시하고 오류 안내와 구분하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('valid empty schedule keeps the domain empty state', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: EmptyCheckSchedule(),
      setNotification: EmptySetNotification(),
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
    expect(find.byKey(const Key('schedule-register-medication')), findsNothing);
    expect(
      find.byKey(const Key('schedule-health-recommendation')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 오늘 일정에 투약 단위와 약품 이미지 영역을 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('오늘 일정에 투약 단위와 약품 이미지 영역을 표시한다', (tester) async {
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: EmptySetNotification(),
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
    await tester.tap(
      find.byKey(const Key('schedule-medication-thumbnail-visual-tablet')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('medication-image-viewer-close')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('medication-image-viewer-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영문 일정 화면은 작은 화면과 큰 글자에서도 넘치지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영문 일정 화면은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _VisualScheduleCheckSchedule(),
      setNotification: EmptySetNotification(),
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
          // 함수이름: builder 콜백
          // 함수역할:
          // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
          // 반환값:
          // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
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
    expect(find.text('0.5 tablet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 켜진 알림과 꺼진 알림 모두 같은 설정창에서 스위치 변경을 저장해야 반영한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('알림 설정과 해제 완료 결과를 화면 하단에 안내한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _MutableSetNotification(),
      notificationService: RecordingNotificationService(),
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
    expect(
      find.byKey(const Key('schedule-reminder-configuration')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notification-time-confirm')), findsNothing);
    expect(viewModel.medicationReminderSettings['morning']!.isEnabled, isFalse);
    await tester.tap(find.byKey(const Key('schedule-reminder-enabled')));
    await tester.pumpAndSettle();
    expect(viewModel.medicationReminderSettings['morning']!.isEnabled, isFalse);
    await tester.tap(find.byKey(const Key('schedule-reminder-save')));
    await tester.pumpAndSettle();

    expect(viewModel.statusMessage, '아침 알림이 08:00으로 설정되었습니다.');
    expect(find.text(viewModel.statusMessage), findsOneWidget);

    await tester.tap(morningReminder);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('schedule-reminder-configuration')),
      findsOneWidget,
    );
    expect(viewModel.medicationReminderSettings['morning']!.isEnabled, isTrue);
    expect(find.text('아침 알림이 해제되었습니다.'), findsNothing);
    expect(
      tester
          .widget<Icon>(find.byIcon(Icons.notifications_active_outlined))
          .color,
      const Color(0xFFFF1744),
    );
    await tester.tap(find.byKey(const Key('schedule-reminder-enabled')));
    await tester.pumpAndSettle();
    expect(viewModel.medicationReminderSettings['morning']!.isEnabled, isTrue);
    await tester.tap(find.byKey(const Key('schedule-reminder-save')));
    await tester.pumpAndSettle();
    expect(viewModel.medicationReminderSettings['morning']!.isEnabled, isFalse);
    expect(find.text('아침 알림이 해제되었습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in [false, true]) {
    // 함수이름: 알림 종 접근성 테스트
    // 함수역할: tester로 활성 여부에 따른 종의 이름과 상태가 중복 없이 전달되는지 검증한다. 반환값: 검증 완료.
    testWidgets(
      'reminder accessibility includes name and value for enabled=$enabled',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpReminderSchedule(
            tester,
            _MutableSetNotification(enabled: enabled),
          );
          final reminder = find.byTooltip('아침 알림 설정');
          expect(tester.widget<Tooltip>(reminder).excludeFromSemantics, isTrue);
          final node = tester.getSemantics(
            find
                .descendant(of: reminder, matching: find.byType(Semantics))
                .first,
          );
          expect(node.label, '아침 알림 설정');
          expect(node.value, enabled ? '켜짐' : '꺼짐');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    for (final dismissal in ['cancel', 'back', 'barrier']) {
      // 함수이름: 알림 설정 닫기 테스트
      // 함수역할: enabled 상태에서 tester로 스위치를 바꾼 뒤 dismissal로 닫으면 저장·해제가 없는지 검증한다. 반환값: 검증 완료.
      testWidgets(
        'reminder $dismissal discards an unsaved switch change from enabled=$enabled',
        (tester) async {
          final notification = _MutableSetNotification(enabled: enabled);
          final model = await _pumpReminderSchedule(tester, notification);
          await tester.tap(find.byTooltip('아침 알림 설정'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('schedule-reminder-enabled')));
          await tester.pumpAndSettle();
          expect(notification.disableCount, 0);
          expect(notification.saveCount, 0);
          if (dismissal == 'cancel') {
            await tester.tap(find.byKey(const Key('schedule-reminder-cancel')));
          } else if (dismissal == 'back') {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tapAt(const Offset(8, 8));
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('schedule-reminder-configuration')),
            findsNothing,
          );
          expect(
            model.medicationReminderSettings['morning']!.isEnabled,
            enabled,
          );
          expect(notification.disableCount, 0);
          expect(notification.saveCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // 함수이름: 알림 시각 초안 테스트
  // 함수역할: tester로 시각을 확정해도 바깥 창 저장 전에는 변경이 없으며 취소하면 초안이 사라지는지 검증한다. 반환값: 검증 완료.
  testWidgets('reminder time changes persist only after configuration save', (
    tester,
  ) async {
    final notification = _MutableSetNotification(enabled: true);
    final model = await _pumpReminderSchedule(tester, notification);
    await tester.tap(find.byTooltip('아침 알림 설정'));
    await tester.pumpAndSettle();
    await _editReminderHour(tester, '9');
    expect(find.text('알림 시간 09:00'), findsOneWidget);
    expect(notification.saveCount, 0);
    expect(model.medicationReminderSettings['morning']!.hour, 8);
    await tester.tap(find.byKey(const Key('schedule-reminder-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('아침 알림 설정'));
    await tester.pumpAndSettle();
    expect(find.text('알림 시간 08:00'), findsOneWidget);
    await _editReminderHour(tester, '10');
    await tester.tap(find.byKey(const Key('schedule-reminder-save')));
    await tester.pumpAndSettle();
    expect(notification.saveCount, 1);
    expect(notification.disableCount, 0);
    expect(model.medicationReminderSettings['morning']!.hour, 10);
    expect(model.medicationReminderSettings['morning']!.isEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 시간 선택 취소 테스트
  // 함수역할: tester로 중첩 시간창을 취소하고 설정을 그대로 저장하면 영속화 요청이 없는지 검증한다. 반환값: 검증 완료.
  testWidgets(
    'cancelled time picker and unchanged save leave the reminder intact',
    (tester) async {
      final notification = _MutableSetNotification(enabled: true);
      await _pumpReminderSchedule(tester, notification);
      await tester.tap(find.byTooltip('아침 알림 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-reminder-edit-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-time-close')));
      await tester.pumpAndSettle();
      expect(find.text('알림 시간 08:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('schedule-reminder-save')));
      await tester.pumpAndSettle();
      expect(notification.saveCount, 0);
      expect(notification.disableCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 꺼진 알림 설정 테스트
  // 함수역할: tester로 꺼진 알림의 동일 설정창에서 활성화·시간 초안을 취소하거나 저장하는 결과를 검증한다. 반환값: 검증 완료.
  testWidgets(
    'disabled reminder shares configuration and only saves confirmed drafts',
    (tester) async {
      final notification = _MutableSetNotification();
      final model = await _pumpReminderSchedule(tester, notification);
      await tester.tap(find.byTooltip('아침 알림 설정'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('schedule-reminder-configuration')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('notification-time-confirm')), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('schedule-reminder-enabled')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('schedule-reminder-save')));
      await tester.pumpAndSettle();
      expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
      expect(notification.saveCount, 0);
      expect(notification.disableCount, 0);

      await tester.tap(find.byTooltip('아침 알림 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-reminder-enabled')));
      await tester.pumpAndSettle();
      await _editReminderHour(tester, '9');
      expect(find.text('알림 시간 09:00'), findsOneWidget);
      expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
      expect(notification.saveCount, 0);
      await tester.tap(find.byKey(const Key('schedule-reminder-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('아침 알림 설정'));
      await tester.pumpAndSettle();
      expect(find.text('알림 시간 08:00'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('schedule-reminder-enabled')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('schedule-reminder-enabled')));
      await tester.pumpAndSettle();
      await _editReminderHour(tester, '10');
      await tester.tap(find.byKey(const Key('schedule-reminder-save')));
      await tester.pumpAndSettle();
      expect(model.medicationReminderSettings['morning']!.isEnabled, isTrue);
      expect(model.medicationReminderSettings['morning']!.hour, 10);
      expect(notification.saveCount, 1);
      expect(notification.disableCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 알림 설정 큰 글씨 테스트
  // 함수역할: tester의 작은 화면·2배 글씨에서 설정과 저장 명령이 스크롤로 접근 가능한지 검증한다. 반환값: 검증 완료.
  testWidgets(
    'reminder configuration supports a compact viewport and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notification = _MutableSetNotification(enabled: true);
      final model = await _pumpReminderSchedule(
        tester,
        notification,
        textScale: 2,
      );
      final reminder = find.byTooltip('아침 알림 설정');
      await tester.ensureVisible(reminder);
      await tester.pumpAndSettle();
      expect(reminder.hitTestable(), findsOneWidget);
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      final enableSwitch = find.byKey(const Key('schedule-reminder-enabled'));
      await tester.ensureVisible(enableSwitch);
      await tester.pumpAndSettle();
      await tester.tap(enableSwitch);
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('schedule-reminder-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
      expect(notification.disableCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final showBackButton in [false, true]) {
    // 함수이름: 기존 헤더와 큰 글씨 테스트
    // 함수역할: tester의 작은 화면·2배 글씨에서 기존 초록 헤더와 진행률·뒤로가기가 유지되는지 검증한다. 반환값: 검증 완료.
    testWidgets(
      'original green schedule header supports large text with back=$showBackButton',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final model = MedBuddyViewModel(
          checkSchedule: EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
        );
        addTearDown(model.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<MedBuddyViewModel>.value(
            value: model,
            child: MaterialApp(
              // 함수역할: context의 child에 2배 글씨를 적용한다. 반환값: 확대된 화면 트리.
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: CheckScheduleUI(showBackButton: showBackButton),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MedBuddyPageHeader), findsNothing);
        expect(
          find.byTooltip('뒤로가기'),
          showBackButton ? findsOneWidget : findsNothing,
        );
        final title = tester.widget<Text>(find.text('오늘의 복약 일정'));
        expect(title.style!.fontSize, 21);
        expect(title.style!.color, Colors.white);
        expect(title.strutStyle, MedBuddyPageHeader.titleStrutStyle);
        expect(tester.getTopLeft(find.text('오늘의 복약 일정')).dy, 12);
        expect(
          find.ancestor(
            of: find.text('오늘의 복약 일정'),
            matching: find.byWidgetPredicate(
              // 초록색 배경과 하단 라운드가 적용된 기존 헤더 컨테이너를 찾는다.
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      MedBuddyColors.topBar &&
                  (widget.decoration! as BoxDecoration).borderRadius ==
                      const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byKey(const Key('schedule-progress-band')), findsNothing);
        expect(find.text('오늘 복용할 약이 없습니다'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: 첨부 선택 모드 테스트
  // 함수역할: tester에 빈 선택 목록을 표시해 등록 CTA 없이 보조 헤더만 나오는지 검증한다. 반환값: 검증 완료.
  testWidgets(
    'empty attachment selection is not the registration empty state',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CheckScheduleUI.selection(schedules: [], language: 'ko'),
        ),
      );
      await tester.pumpAndSettle();
      final header = tester.widget<MedBuddyPageHeader>(
        find.byType(MedBuddyPageHeader),
      );
      expect(header.prominent, isFalse);
      expect(header.onBackRequested, isNotNull);
      expect(find.text('대화할 약 선택'), findsOneWidget);
      expect(
        find.byKey(const Key('schedule-register-medication')),
        findsNothing,
      );
      expect(find.byKey(const Key('schedule-progress-band')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 고정 건강 추천 테스트
  // 함수역할: tester로 하단에 고정된 추천 버튼의 위치와 화면 이동을 검증한다. 반환값: 검증 완료.
  testWidgets('health recommendation stays fixed below the schedule list', (
    tester,
  ) async {
    final model = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: EmptySetNotification(),
      checkHealthRecommendation: _ScheduleHealthRecommendation(),
    );
    addTearDown(model.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: model,
        child: const MaterialApp(home: CheckScheduleUI()),
      ),
    );
    await tester.pumpAndSettle();
    final recommendation = find.byKey(
      const Key('schedule-health-recommendation'),
    );
    final initialPosition = tester.getTopLeft(recommendation);
    expect(recommendation.hitTestable(), findsOneWidget);
    expect(
      find.ancestor(of: recommendation, matching: find.byType(ListView)),
      findsNothing,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(recommendation), initialPosition);
    await tester.tap(recommendation);
    await tester.pumpAndSettle();
    expect(find.byType(HealthRecommendationUI), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CheckScheduleUI), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 복용 체크는 기기 대기열에 저장된 뒤 완료로 표시되고, 완료 안내는 화면 이동 후에도
  //   접근성 모드에서 자동으로 닫힌다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('복약 완료 안내는 화면 이동 후에도 접근성 모드에서 자동으로 닫힌다', (tester) async {
    final checkSchedule = _MorningDoseCheckSchedule();
    final harness = await _pumpDoseSchedule(
      tester,
      checkSchedule,
      accessibleNavigation: true,
    );

    await tester.tap(find.byTooltip('복용 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsOneWidget);
    // 서버 응답과 무관하게 기기 대기열의 기록으로 완료가 표시된다.
    final queued = harness.queued.single;
    expect(queued['medication_ids'], [91]);
    expect(queued['slot_key'], 'morning');
    expect(queued['schedule_date'], doseScheduleDay(DateTime.now()));
    expect(queued['completed'], isTrue);
    expect(queued['medication_names'], ['테스트정']);
    expect(find.byTooltip('복용 완료 취소'), findsOneWidget);
    expect(checkSchedule.directUpdateCount, 0);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 복약 화면에서 이동할 환경설정 도착 화면을 간단한 텍스트로 구성한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트. 이 대역에서는 직접 사용하지 않는다.
        // 반환값:
        // - 환경설정 문구가 있는 Scaffold.
        builder: (context) => const Scaffold(body: Text('환경설정')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('아침 · 테스트정 복용을 완료했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
    await _closeDoseSchedule(tester, harness);
  });

  // 함수이름: 복용 실행 취소 테스트
  // 함수역할: tester로 완료 안내의 실행 취소를 누르면 취소 기록이 완료 기록 뒤에 저장되고 화면이
  //   미복용으로 돌아가는지 검증한다. 반환값: 검증 완료.
  testWidgets('완료 안내의 실행 취소는 취소 기록을 이어서 저장한다', (tester) async {
    final checkSchedule = _MorningDoseCheckSchedule();
    final harness = await _pumpDoseSchedule(tester, checkSchedule);

    await tester.tap(find.byTooltip('복용 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('복용 완료 취소'), findsOneWidget);

    await tester.tap(find.text('실행 취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.queued.map((op) => op['completed']), [true, false]);
    expect(harness.queued.map((op) => op['medication_ids']), [
      [91],
      [91],
    ]);
    expect(harness.queued.map((op) => op['slot_key']).toSet(), {'morning'});
    expect(find.byTooltip('복용 완료'), findsOneWidget);
    expect(find.text('테스트정 복용 완료를 취소했습니다.'), findsOneWidget);
    expect(checkSchedule.directUpdateCount, 0);
    expect(tester.takeException(), isNull);
    await _closeDoseSchedule(tester, harness);
  });

  // 함수이름: 기기 저장 실패 테스트
  // 함수역할: tester로 기기 저장소에 기록하지 못한 복용 체크가 완료로 표시되지 않고 실패를 알리는지
  //   검증한다. 반환값: 검증 완료.
  testWidgets('기기에 저장하지 못한 복용 체크는 완료로 표시하지 않는다', (tester) async {
    final checkSchedule = _MorningDoseCheckSchedule();
    final harness = await _pumpDoseSchedule(tester, checkSchedule);
    // 저장소가 닫혀 기록할 수 없는 상태를 만든다.
    await harness.store.db.close();

    await tester.tap(find.byTooltip('복용 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('복약 상태를 변경하지 못했습니다.'), findsOneWidget);
    expect(find.byTooltip('복용 완료'), findsOneWidget);
    expect(find.byTooltip('복용 완료 취소'), findsNothing);
    expect(harness.queued, isEmpty);
    expect(checkSchedule.directUpdateCount, 0);
    expect(tester.takeException(), isNull);
    await _closeDoseSchedule(tester, harness);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Verify that the whole-slot button beside the alarm toggles all doses between taken and untaken,
  //   storing each change as one queued operation for the slot.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('시간대 전체 버튼은 알림 오른쪽에서 전부 체크와 해제를 반복한다', (tester) async {
    final checkSchedule = _MorningDoseCheckSchedule();
    final harness = await _pumpDoseSchedule(tester, checkSchedule);
    final viewModel = harness.viewModel;

    final reminderButton = find.byTooltip('아침 알림 설정');
    final wholeSlotButton = find.byKey(
      const ValueKey('schedule-entire-slot-toggle-morning'),
    );
    expect(
      find.byKey(const ValueKey('schedule-entire-slot-toggle-lunch')),
      findsNothing,
    );
    expect(find.byTooltip('아침 복약 전부 체크'), findsOneWidget);
    expect(
      tester.getCenter(wholeSlotButton).dx,
      greaterThan(tester.getCenter(reminderButton).dx),
    );

    await tester.tap(wholeSlotButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.queued, hasLength(1));
    expect(harness.queued.single['slot_key'], 'morning');
    expect(harness.queued.single['medication_ids'], [91]);
    expect(harness.queued.single['completed'], isTrue);
    expect(
      harness.queued.single['schedule_date'],
      doseScheduleDay(DateTime.now()),
    );
    expect(find.text('아침 복약을 모두 완료했습니다.'), findsOneWidget);
    expect(find.byTooltip('아침 복약 전부 해제'), findsOneWidget);
    expect(
      viewModel.isMedicationDoseCompleted(
        'morning',
        viewModel.todayMedicationScheduleList.single,
      ),
      isTrue,
    );

    await tester.tap(wholeSlotButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.queued.map((op) => op['completed']), [true, false]);
    expect(harness.queued.last['medication_ids'], [91]);
    expect(find.text('아침 복약 완료를 모두 해제했습니다.'), findsOneWidget);
    expect(find.byTooltip('아침 복약 전부 체크'), findsOneWidget);
    expect(
      viewModel.isMedicationDoseCompleted(
        'morning',
        viewModel.todayMedicationScheduleList.single,
      ),
      isFalse,
    );
    expect(checkSchedule.directUpdateCount, 0);
    expect(tester.takeException(), isNull);
    await _closeDoseSchedule(tester, harness);
  });

  for (final showBackButton in [true, false]) {
    // 함수이름: 전송 확인 필요 표시 테스트
    // 함수역할: tester로 서버가 거부한 복용 기록이 있을 때, 뒤로가기가 있는 일정 화면에만 전송 확인
    //   줄이 표시되는지(홈에서 연 화면은 홈이 표시) 검증한다. 반환값: 검증 완료.
    testWidgets('거부된 복용 기록은 전송 확인 필요로 표시된다 back=$showBackButton', (
      tester,
    ) async {
      final harness = await _pumpDoseSchedule(
        tester,
        _MorningDoseCheckSchedule(),
        showBackButton: showBackButton,
      );
      harness.respond = (_) async => http.Response('rejected', 409);

      await tester.tap(find.byTooltip('복용 완료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await harness.service.drain();
      await tester.pump();

      expect(harness.service.hasBlocked, isTrue);
      expect(
        find.text('복용 기록 전송 확인 필요'),
        showBackButton ? findsOneWidget : findsNothing,
      );
      // 거부된 기록도 기기에는 남아 있고 사용자가 지울 때까지 화면의 완료 표시를 유지한다.
      expect(await harness.pending(), hasLength(1));
      expect(find.byTooltip('복용 완료 취소'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _closeDoseSchedule(tester, harness);
    });
  }

  // Function Name: test callback
  // Description:
  // - Expected behavior: failed refresh clears stale schedule data.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: test callback
  // Description:
  // - Expected behavior: reminder sync failure does not discard a loaded schedule.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('reminder sync failure does not discard a loaded schedule', () async {
    SharedPreferences.setMockInitialValues({});
    final viewModel = MedBuddyViewModel(
      checkSchedule: _ActiveCheckSchedule(),
      setNotification: _EnabledSetNotification(),
      notificationService: RecordingNotificationService(failRegistration: true),
    );
    addTearDown(viewModel.dispose);

    await expectLater(viewModel.refreshMedicationSchedule(), completes);

    expect(viewModel.todayMedicationScheduleList, hasLength(1));
    expect(viewModel.hasTodayScheduleLoadError, isFalse);
    expect(viewModel.statusMessage, contains('알림을 동기화하지 못했습니다'));
  });
}
