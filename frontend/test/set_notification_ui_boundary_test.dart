import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 파일명: set_notification_ui_boundary_test.dart
// 역할: 알림 시간 휠, 직접 입력, 닫기와 테마 동작을 검증한다.

void main() {
  testWidgets('alarm popup returns the time selected by the wheel', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final hourPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('notification-hour-wheel')),
    );
    final minutePicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('notification-minute-wheel')),
    );

    hourPicker.onSelectedItemChanged?.call(21);
    minutePicker.onSelectedItemChanged?.call(37);
    await tester.pump();
    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pumpAndSettle();

    expect(selectedTime, isNotNull);
    expect(selectedTime!.hour, 21);
    expect(selectedTime!.minute, 37);
  });

  testWidgets('selected hour and minute accept direct numeric input', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'ko',
                slotTitle: '아침',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-hour-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '17',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-minute-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '45',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pumpAndSettle();

    expect(selectedTime, const TimeOfDay(hour: 17, minute: 45));
  });

  testWidgets('direct input rejects values outside the valid range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              SetNotificationUI.showNotificationPopup(
                context,
                language: 'ko',
                slotTitle: '아침',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-hour-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '29',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pump();

    expect(find.textContaining('0부터 23 사이'), findsOneWidget);
  });

  testWidgets('alarm popup returns null when the wheel dialog is closed', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-time-close')));
    await tester.pumpAndSettle();

    expect(selectedTime, isNull);
    expect(find.byType(SetNotificationUI), findsNothing);
  });

  testWidgets('alarm wheel stays visible with a dark device theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final pickerFinder = find.byKey(const Key('notification-hour-wheel'));
    final picker = tester.widget<CupertinoPicker>(pickerFinder);
    final pickerTheme = CupertinoTheme.of(tester.element(pickerFinder));
    final selectedHourText = tester.widget<Text>(find.text('08').first);

    expect(picker.backgroundColor, Colors.transparent);
    expect(pickerTheme.brightness, Brightness.light);
    expect(selectedHourText.style?.color, MedBuddyColors.textStrong);
  });
}
