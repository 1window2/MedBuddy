// 파일명: medication_schedule_review_ui_boundary_test.dart
// 역할: 분석 후 복용 시작일, 기간, 횟수와 시간대 검토 화면을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_schedule_review_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('OCR 기본값을 수정한 뒤 확인 결과로 반환한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    List<MedicationSchedule>? reviewedSchedules;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-schedule-review'),
                onPressed: () async {
                  reviewedSchedules = await showMedicationScheduleReview(
                    context: context,
                    initialSchedules: [
                      MedicationSchedule(
                        medicationName: '테스트정',
                        prescriptionDate: DateTime(2026, 8, 23),
                        dosage: '1정',
                        intakeTime: '3회',
                        medicationTime: 3,
                        scheduleSlotKeys: ['morning', 'lunch', 'evening'],
                      ),
                    ],
                    userSetting: const UserSetting(),
                    purpose:
                        MedicationScheduleReviewPurpose.prescriptionAnalysis,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-schedule-review')));
    await tester.pumpAndSettle();
    expect(find.text('복약 정보 확인'), findsOneWidget);
    expect(find.text('2026-08-23'), findsOneWidget);
    expect(find.text('3회'), findsWidgets);

    await tester.tap(find.byKey(const Key('schedule-review-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schedule-edit-dosage')),
      '0.5정',
    );
    await tester.enterText(find.byKey(const Key('schedule-edit-days')), '5');
    await tester.tap(find.byKey(const Key('schedule-edit-frequency-2')));
    await tester.tap(find.byKey(const Key('schedule-edit-apply')));
    await tester.pumpAndSettle();

    expect(find.text('0.5정'), findsOneWidget);
    expect(find.text('5일'), findsOneWidget);
    await tester.tap(find.byKey(const Key('schedule-review-confirm')));
    await tester.pumpAndSettle();

    expect(reviewedSchedules, hasLength(1));
    expect(reviewedSchedules?.single.dosage, '0.5정');
    expect(reviewedSchedules?.single.dailyFrequencyCount, 2);
    expect(reviewedSchedules?.single.medicationTime, 5);
    expect(reviewedSchedules?.single.scheduleSlotKeys, ['morning', 'evening']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('큰 글씨와 작은 화면에서도 검토 목록을 스크롤할 수 있다', (tester) async {
    await _setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-large-schedule-review'),
                onPressed: () {
                  showMedicationScheduleReview(
                    context: context,
                    initialSchedules: List.generate(
                      4,
                      (index) => MedicationSchedule(
                        medicationName: '길이가 긴 복약 정보 확인용 약 이름 ${index + 1}',
                        prescriptionDate: DateTime(2026, 8, 23),
                        dosage: '1정',
                        intakeTime: '1회',
                        medicationTime: 7,
                        scheduleSlotKeys: const ['morning'],
                      ),
                    ),
                    userSetting: const UserSetting(fontSize: 20),
                    purpose:
                        MedicationScheduleReviewPurpose.prescriptionAnalysis,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-large-schedule-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('schedule-review-list')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('schedule-review-list')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR 날짜가 일반 범위를 벗어나도 날짜 수정 창을 열 수 있다', (tester) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open-future-schedule-review'),
              onPressed: () {
                showMedicationScheduleReview(
                  context: context,
                  initialSchedules: [
                    MedicationSchedule(
                      medicationName: '미래날짜정',
                      prescriptionDate: DateTime(2035, 1, 2),
                      dosage: '1정',
                      intakeTime: '1회',
                      medicationTime: 3,
                      scheduleSlotKeys: const ['morning'],
                    ),
                  ],
                  userSetting: const UserSetting(),
                  purpose: MedicationScheduleReviewPurpose.prescriptionAnalysis,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-future-schedule-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-review-edit-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-edit-start-date')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
