import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home camera entry separates prescription and pill tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pillTaskRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {
            pillTaskRequested = true;
          },
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    await tester.tap(find.text('약 정보 촬영하기'));
    await tester.pumpAndSettle();

    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsOneWidget);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(pillTaskRequested, isTrue);
  });

  testWidgets('home owns navigation into loose-pill identification', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final inputBoundary = tester.widget<InputPrescriptionUI>(
      find.byType(InputPrescriptionUI),
    );
    inputBoundary.onPillIdentificationRequested?.call();
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
  });

  testWidgets('환자 보호자 연동 카드는 다른 홈 카드와 같은 높이와 아이콘을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final savedCard = find.byKey(const ValueKey('homeSavedMedicationCard'));
    final linkCard = find.byKey(const ValueKey('homePatientCaregiverLinkCard'));
    expect(tester.getSize(linkCard).height, tester.getSize(savedCard).height);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('영어 설정은 메인 화면 제목과 설명에 함께 반영된다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'en'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    expect(find.text('Start your medication plan with ease'), findsOneWidget);
    expect(find.text('오늘의 복약 일정'), findsNothing);
    expect(find.text("Today's Medication"), findsOneWidget);
  });

  testWidgets('large grid preserves inherited scale and saved-card wording', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1100));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: _home(userSetting: const UserSetting(fontSize: 20)),
      ),
    );
    await tester.pumpAndSettle();

    final captureTitle = tester.widget<Text>(find.text('약 정보\n촬영하기'));
    final scheduleTitle = tester.widget<Text>(find.text('오늘의\n복약 일정'));
    expect(captureTitle.textScaler, isNull);
    expect(scheduleTitle.textScaler, isNull);
    expect(find.text('저장된\n복약 정보'), findsOneWidget);
    expect(find.text('지정된\n복약 정보'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact subtitles wrap without shrinking inside FittedBox', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(userSetting: const UserSetting(language: 'en')),
      ),
    );

    final subtitleFinder = find.text(
      'Connect patient and caregiver medication schedules',
    );
    final subtitle = tester.widget<Text>(subtitleFinder);
    expect(subtitle.maxLines, 2);
    expect(subtitle.style?.fontSize, 11);
    expect(
      find.ancestor(of: subtitleFinder, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard chooses the earliest alarm and localizes its slot', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          userSetting: const UserSetting(language: 'en'),
          schedules: const [
            MedicationSchedule(
              medicationName: 'MorningMed',
              scheduleSlotKeys: ['morning'],
            ),
            MedicationSchedule(
              medicationName: 'LunchMed',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'morning': MedicationAlarm(
              slotKey: 'morning',
              hour: 20,
              minute: 0,
              enabled: true,
            ),
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 0,
              enabled: true,
            ),
          },
          totalCount: 2,
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.textContaining('Lunch 12:00 · LunchMed'), findsOneWidget);
    expect(find.textContaining('점심 12:00'), findsNothing);
  });

  testWidgets('dashboard represents every due medication and disabled alarm', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '약A',
              scheduleSlotKeys: ['lunch'],
            ),
            MedicationSchedule(
              medicationName: '약B',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 0,
              enabled: false,
            ),
          },
          totalCount: 2,
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.text('다음 복약 일정'), findsOneWidget);
    expect(find.text('다음 복약 알림'), findsNothing);
    expect(find.textContaining('점심 12:00 · 약A 외 1개'), findsOneWidget);
  });

  testWidgets('dashboard uses an overdue-specific status message', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '아침약',
              scheduleSlotKeys: ['morning'],
            ),
          ],
          alarms: const {
            'morning': MedicationAlarm(
              slotKey: 'morning',
              hour: 8,
              minute: 0,
              enabled: true,
            ),
          },
          totalCount: 1,
          nowProvider: () => DateTime(2026, 1, 1, 23),
        ),
      ),
    );

    expect(find.text('미복용한 약을 확인해주세요'), findsOneWidget);
    expect(find.text('미복용 확인'), findsOneWidget);
    expect(find.text('오늘도 복약을 꾸준히 이어가고 있어요'), findsNothing);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

InputPrescriptionUI _home({
  UserSetting userSetting = const UserSetting(),
  List<MedicationSchedule> schedules = const [],
  Map<String, MedicationAlarm> alarms = const {},
  int completedCount = 0,
  int totalCount = 0,
  DateTime Function()? nowProvider,
}) {
  return InputPrescriptionUI(
    statusMessage: '',
    userSetting: userSetting,
    todayMedicationScheduleList: schedules,
    medicationReminderSettings: alarms,
    todayMedicationCompletedCount: completedCount,
    todayMedicationTotalCount: totalCount,
    nowProvider: nowProvider,
    onPrescriptionScanRequested: () {},
    onPrescriptionGalleryRequested: () {},
    onPillIdentificationRequested: () {},
    onTodayScheduleRequested: () {},
    onSavedMedicationRequested: () {},
    onPatientCaregiverLinkRequested: () {},
    onUserSettingRequested: () {},
  );
}
