import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/medication_schedule_header.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final english in [false, true]) {
        testWidgets('schedule title and calendar align $width $scale $english', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final title = english
              ? "Today's Medication Schedule"
              : '오늘의 복약 일정';
          var opened = false;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Column(
                    children: [
                      MedicationScheduleHeader(
                        title: title,
                        historyKey: const Key('history'),
                        historyTooltip: 'History',
                        onHistory: () => opened = true,
                        progressLabel: english ? 'Progress' : '복용 진행률',
                        completedCount: 0,
                        totalCount: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getCenter(find.text(title)).dy,
            closeTo(tester.getCenter(find.byKey(const Key('history'))).dy, .1),
          );
          if (!english && scale == 1) {
            expect(
              tester.getSize(find.byType(MedicationScheduleHeader)).height,
              lessThanOrEqualTo(144),
            );
          }
          await tester.tap(find.byKey(const Key('history')));
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
