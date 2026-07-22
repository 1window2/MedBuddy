// 파일명: prescription_change_radar_ui_boundary_test.dart
// 역할: 처방 변화 레이더 카드의 핵심 상태와 안내 문구를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_change_radar_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('shows schedule changes and medication safety notice', (
    tester,
  ) async {
    final radar = PrescriptionChangeRadar(
      hasPreviousPrescription: true,
      comparisonStatus: PrescriptionComparisonStatus.comparable,
      previousPrescriptionDate: DateTime(2026, 7, 1),
      currentPrescriptionDate: DateTime(2026, 7, 15),
      summary: const PrescriptionChangeSummary(scheduleChangedCount: 1),
      changes: const [
        PrescriptionMedicationChange(
          type: PrescriptionChangeType.scheduleChanged,
          itemName: '테스트정',
          changedFields: ['daily_frequency'],
          previous: PrescriptionScheduleSnapshot(dailyFrequency: '1일 2회'),
          current: PrescriptionScheduleSnapshot(dailyFrequency: '1일 3회'),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PrescriptionChangeRadarUI(
              radar: radar,
              userSetting: const UserSetting(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('처방 변화 레이더'), findsOneWidget);
    expect(find.text('테스트정'), findsOneWidget);
    expect(find.text('1일 횟수: 1일 2회 → 1일 3회'), findsOneWidget);
    expect(find.textContaining('복용 시작·중단 지시가 아닙니다'), findsOneWidget);
  });

  testWidgets('explains when no previous prescription exists', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrescriptionChangeRadarUI(
            radar: PrescriptionChangeRadar(hasPreviousPrescription: false),
            userSetting: UserSetting(),
          ),
        ),
      ),
    );

    expect(find.textContaining('아직 비교할 이전 처방이 없습니다'), findsOneWidget);
  });

  testWidgets('skips unrelated prescriptions with a clear reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrescriptionChangeRadarUI(
            radar: PrescriptionChangeRadar(
              hasPreviousPrescription: false,
              comparisonStatus: PrescriptionComparisonStatus.unrelated,
              comparisonWindowDays: 90,
            ),
            userSetting: UserSetting(),
          ),
        ),
      ),
    );

    expect(find.textContaining('관련성이 충분한 처방'), findsOneWidget);
    expect(find.textContaining('비교를 생략'), findsOneWidget);
  });

  testWidgets('explains when prescription history is outside the window', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrescriptionChangeRadarUI(
            radar: PrescriptionChangeRadar(
              hasPreviousPrescription: false,
              comparisonStatus: PrescriptionComparisonStatus.expired,
              comparisonWindowDays: 90,
            ),
            userSetting: UserSetting(),
          ),
        ),
      ),
    );

    expect(find.textContaining('최근 90일 비교 기간'), findsOneWidget);
  });
}
