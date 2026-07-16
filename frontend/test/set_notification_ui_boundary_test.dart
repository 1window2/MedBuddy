import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';

void main() {
  testWidgets('alarm popup returns the time selected by the wheel',
      (tester) async {
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

    expect(find.byType(TextFormField), findsNothing);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byKey(const Key('notification-time-wheel')),
    );
    expect(picker.initialDateTime.hour, 8);
    expect(picker.initialDateTime.minute, 0);

    picker.onDateTimeChanged(DateTime(2000, 1, 1, 21, 37));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pumpAndSettle();

    expect(selectedTime, isNotNull);
    expect(selectedTime!.hour, 21);
    expect(selectedTime!.minute, 37);
  });

  testWidgets('alarm popup returns null when the wheel dialog is closed',
      (tester) async {
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
}
