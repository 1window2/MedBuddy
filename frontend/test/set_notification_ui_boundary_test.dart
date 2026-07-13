import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';

void main() {
  testWidgets('alarm popup accepts a direct HH:mm time', (tester) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await SetNotificationUI.showAlarmSettingPopup(
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
    await tester.enterText(find.byType(TextFormField), '0832');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(selectedTime, isNotNull);
    expect(selectedTime!.hour, 8);
    expect(selectedTime!.minute, 32);
  });

  testWidgets('alarm popup rejects an out-of-range time', (tester) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedTime = await SetNotificationUI.showAlarmSettingPopup(
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
    await tester.enterText(find.byType(TextFormField), '2599');
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(find.text('Enter a valid 24-hour time.'), findsOneWidget);
    expect(selectedTime, isNull);
    expect(find.byType(SetNotificationUI), findsOneWidget);
  });
}
