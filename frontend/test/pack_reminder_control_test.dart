// 파일명: pack_reminder_control_test.dart
// 역할: 외출 전 약 챙기기 알림의 설정 저장, 예약 날짜(점심·저녁 약이 있는 날 × 고른 요일), 예약·취소,
//   백그라운드 갱신 연결, 알림 문구·payload 해석, 일정 화면의 설정 줄을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/pack_reminder_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_notification_selection_entity.dart';
import 'package:medbuddy_frontend/entities/medication_reminder_text.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/medication_notification_payload_codec.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/pack_reminder_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2026-11-30은 월요일이다.
final _monday = DateTime(2026, 11, 30, 6);

// medicationTime은 복용 기간(일)이다.
MedicationSchedule _course(
  List<String> slots, {
  DateTime? start,
  int days = 14,
}) => MedicationSchedule(
  medicationName: 'TEST_ONLY',
  prescriptionDate: start ?? DateTime(2026, 11, 30),
  medicationTime: days,
  scheduleSlotKeys: slots,
);

void main() {
  group('setting', () {
    test('defaults to off, 07:30 and every day; JSON round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      expect(
        PackReminderControl.load(preferences, 'usr'),
        const PackReminderSetting(),
      );
      const setting = PackReminderSetting(
        enabled: true,
        hour: 6,
        minute: 45,
        weekdays: {1, 2, 3, 4, 5},
      );
      await PackReminderControl.save(preferences, 'usr', setting);
      expect(
        preferences.getString('medbuddy_pack_reminder_usr'),
        '{"enabled":true,"time":"06:45","days":[1,2,3,4,5]}',
      );
      expect(PackReminderControl.load(preferences, 'usr'), setting);
      expect(
        PackReminderControl.load(preferences, 'other'),
        const PackReminderSetting(),
      );
    });

    test('broken values fall back per field and days never become empty', () {
      final parsed = PackReminderSetting.fromJson({
        'enabled': true,
        'time': '25:99',
        'days': [0, 8, 'x'],
      });
      expect(parsed.enabled, isTrue);
      expect((parsed.hour, parsed.minute), (7, 30));
      expect(parsed.weekdays, PackReminderSetting.allWeekdays);
      const weekdays = PackReminderSetting(weekdays: {3});
      expect(weekdays.copyWith(weekdays: {}).weekdays, {3});
    });
  });

  group('dates', () {
    test('only days with a lunch or evening medicine, on chosen weekdays', () {
      const weekdaysOnly = PackReminderSetting(
        enabled: true,
        weekdays: {1, 2, 3, 4, 5},
      );
      final morningOnly = PackReminderControl.activeDates(
        schedules: [
          _course(['morning']),
        ],
        setting: weekdaysOnly,
        now: _monday,
      );
      expect(morningOnly, isEmpty);

      final evening = PackReminderControl.activeDates(
        schedules: [
          _course(['morning', 'evening']),
        ],
        setting: weekdaysOnly,
        now: _monday,
      );
      expect(evening, isNotEmpty);
      expect(evening.every((d) => d.weekday <= 5), isTrue);
      expect(evening.first, DateTime(2026, 11, 30));
      // 14일 창에서 평일만: 2주 × 5일.
      expect(evening.length, 10);

      final everyDay = PackReminderControl.activeDates(
        schedules: [
          _course(['lunch']),
        ],
        setting: const PackReminderSetting(enabled: true),
        now: _monday,
      );
      expect(everyDay.length, 14);
    });

    test('a three-day course stops when the course ends', () {
      final dates = PackReminderControl.activeDates(
        schedules: [
          _course(['morning', 'lunch', 'evening'], days: 3),
        ],
        setting: const PackReminderSetting(enabled: true),
        now: _monday,
      );
      expect(dates, [
        DateTime(2026, 11, 30),
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 2),
      ]);
    });
  });

  group('synchronize', () {
    test(
      'registers id 84010 as the pack slot, or cancels when not needed',
      () async {
        final calls = <String>[];
        List<DateTime>? registeredDates;
        Future<void> register({
          required int id,
          required String slotKey,
          required String slotTitle,
          required int hour,
          required int minute,
          required List<DateTime> activeDates,
          String language = 'ko',
        }) async {
          calls.add('register $id $slotKey $hour:$minute $slotTitle');
          registeredDates = activeDates;
        }

        Future<void> cancel(int id, {String? slotKey}) async =>
            calls.add('cancel $id $slotKey');

        const on = PackReminderSetting(enabled: true, hour: 7, minute: 10);
        await PackReminderControl.synchronize(
          setting: on,
          schedules: [
            _course(['lunch']),
          ],
          notificationsEnabled: true,
          language: 'ko',
          register: register,
          cancel: cancel,
          now: _monday,
        );
        expect(calls.single, 'register 84010 pack 7:10 약 챙기기');
        expect(registeredDates, hasLength(14));

        for (final (setting, enabled, schedules) in [
          (
            const PackReminderSetting(),
            true,
            [
              _course(['lunch']),
            ],
          ),
          (
            on,
            false,
            [
              _course(['lunch']),
            ],
          ),
          (
            on,
            true,
            [
              _course(['morning']),
            ],
          ),
        ]) {
          calls.clear();
          await PackReminderControl.synchronize(
            setting: setting,
            schedules: schedules,
            notificationsEnabled: enabled,
            language: 'ko',
            register: register,
            cancel: cancel,
            now: _monday,
          );
          expect(calls, ['cancel 84010 pack']);
        }
      },
    );

    test(
      'the background refresh passes the window and the enabled flag',
      () async {
        SharedPreferences.setMockInitialValues({});
        final packCalls = <(int, bool)>[];
        MedicationReminderRefreshService service(bool notificationsOn) =>
            MedicationReminderRefreshService(
              loadSettings: () async => const [
                MedicationAlarm(
                  slotKey: 'lunch',
                  hour: 12,
                  minute: 0,
                  enabled: true,
                ),
              ],
              loadSchedules: () async => [
                _course(['lunch']),
              ],
              loadUserSetting: () async => UserSetting(
                language: 'ko',
                medicationNotificationsEnabled: notificationsOn,
              ),
              registerReminder:
                  ({
                    required id,
                    required slotKey,
                    required slotTitle,
                    required hour,
                    required minute,
                    required activeDates,
                    language = 'ko',
                  }) async {},
              cancelReminder: (id, {slotKey}) async {},
              now: () => _monday,
              synchronizePack:
                  ({
                    required schedules,
                    required notificationsEnabled,
                    required language,
                  }) async {
                    packCalls.add((schedules.length, notificationsEnabled));
                  },
            );
        final on = service(true);
        expect(await on.synchronize(), isTrue);
        on.dispose();
        final off = service(false);
        expect(await off.synchronize(), isTrue);
        off.dispose();
        expect(packCalls, [(1, true), (1, false)]);
      },
    );
  });

  group('notification', () {
    test('text names no medicine and the payload only opens the schedule', () {
      expect(
        medicationReminderTitle(
          packReminderSlotKey,
          slotTitle: '',
          isEnglish: false,
        ),
        '약 챙기기',
      );
      expect(
        medicationReminderBody(packReminderSlotKey, isEnglish: false),
        '오늘 밖에서 드실 점심·저녁 약을 챙겨 가세요.',
      );
      expect(
        medicationReminderBody(packReminderSlotKey, isEnglish: true),
        "Take today's lunch and evening medicines with you.",
      );
      final selection = MedicationNotificationPayloadCodec.decode(
        'schedule:pack:84010:2026-11-30',
        actionId: MedicationNotificationPayloadCodec.markSlotTakenActionId,
      );
      expect(
        selection?.destination,
        MedicationNotificationDestination.schedule,
      );
      expect(selection?.slotKey, packReminderSlotKey);
      expect(selection?.action, MedicationNotificationAction.open);
      expect(selection?.scheduleDate, DateTime(2026, 11, 30));
    });
  });

  group('card', () {
    testWidgets('shows the state, edits time-independent fields and saves', (
      tester,
    ) async {
      var stored = const PackReminderSetting();
      final saved = <PackReminderSetting>[];
      var allow = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PackReminderCard(
              userSetting: const UserSetting(language: 'ko'),
              loadSetting: () async => stored,
              saveSetting: (setting) async {
                saved.add(setting);
                if (allow) stored = setting;
                return allow;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('외출 전 약 챙기기 알림'), findsOneWidget);
      expect(find.text('꺼짐'), findsOneWidget);

      await tester.tap(find.byKey(const Key('schedule-pack-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-enabled')));
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-day-6')));
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-day-7')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-save')));
      await tester.pumpAndSettle();
      expect(saved.single.enabled, isTrue);
      expect(saved.single.weekdays, {1, 2, 3, 4, 5});
      expect(find.text('월 화 수 목 금 · 07:30'), findsOneWidget);

      // 권한을 거부하면 저장하지 않고 안내한다.
      allow = false;
      await tester.tap(find.byKey(const Key('schedule-pack-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-day-6')));
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-save')));
      await tester.pumpAndSettle();
      expect(find.text('알림을 허용해야 켤 수 있어요.'), findsOneWidget);
      expect(find.text('월 화 수 목 금 · 07:30'), findsOneWidget);
    });

    testWidgets('Mon to Sun fit one row; Saturday blue, Sunday red', (
      tester,
    ) async {
      // Galaxy Note10 크기(약 412dp)와 큰 글자에서도 한 줄이어야 한다.
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            home: Scaffold(
              body: PackReminderCard(
                userSetting: const UserSetting(language: 'ko'),
                loadSetting: () async => const PackReminderSetting(),
                saveSetting: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder')));
      await tester.pumpAndSettle();
      final tops = {
        for (var day = 1; day <= 7; day++)
          tester
              .getTopLeft(find.byKey(Key('schedule-pack-reminder-day-$day')))
              .dy,
      };
      expect(tops, hasLength(1));
      expect(tester.takeException(), isNull);
      Color colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;
      expect(colorOf('토'), MedBuddyColors.saturdayBlue);
      expect(colorOf('일'), MedBuddyColors.danger);
      expect(colorOf('월'), MedBuddyColors.primaryDark);
    });

    testWidgets('the last selected weekday cannot be turned off', (
      tester,
    ) async {
      final saved = <PackReminderSetting>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PackReminderCard(
              userSetting: const UserSetting(language: 'ko'),
              loadSetting: () async =>
                  const PackReminderSetting(enabled: true, weekdays: {3}),
              saveSetting: (setting) async {
                saved.add(setting);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-day-3')));
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-day-1')));
      await tester.tap(find.byKey(const Key('schedule-pack-reminder-save')));
      await tester.pumpAndSettle();
      expect(saved.single.weekdays, {1, 3});
    });
  });
}
