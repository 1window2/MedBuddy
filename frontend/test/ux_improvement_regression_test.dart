import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_today_medication_info_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/user_facing_error_message.dart';

// 파일명: ux_improvement_regression_test.dart
// 역할: 다음 복약 요약, 복용 기간 필터 기준, 오류 안내의 핵심 UX 동작을 검증한다.

void main() {
  testWidgets('홈 카드가 다음 복약 시간과 오늘 진행률을 안내한다', (tester) async {
    final fixedNow = DateTime(2026, 8, 3, 10);
    const schedules = [
      MedicationSchedule(
        medicationName: '아침약',
        scheduleSlotKeys: ['morning'],
        slotStatuses: {'morning': true},
      ),
      MedicationSchedule(medicationName: '점심약', scheduleSlotKeys: ['lunch']),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckTodayMedicationInfoUI(
            title: '오늘의 복약 일정',
            noMedicationLabel: '등록된 약이 없습니다',
            userSetting: const UserSetting(),
            schedules: schedules,
            reminderSettings: const {
              'lunch': MedicationAlarm(
                slotKey: 'lunch',
                hour: 12,
                minute: 30,
                enabled: true,
              ),
            },
            completedCount: 1,
            totalCount: 2,
            isLoading: false,
            onTap: () {},
            nowProvider: () => fixedNow,
          ),
        ),
      ),
    );

    expect(find.text('다음 복약: 점심 12:30'), findsOneWidget);
    expect(find.text('복용할 약 1개 · 오늘 1/2회 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('약 정보 조회 실패 후 OCR 검토 화면으로 돌아갈 수 있다', (tester) async {
    var ocrReviewRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: '약 이름을 찾지 못했습니다.',
          userSetting: const UserSetting(),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          onAnalysisRetryRequested: () {},
          onOcrReviewRequested: () => ocrReviewRequested = true,
          onCameraRetryRequested: () {},
          onGalleryRetryRequested: () {},
          onHomeRequested: () {},
        ),
      ),
    );

    final reviewButton = find.byKey(
      const Key('prescription-ocr-review-button'),
    );
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);

    expect(ocrReviewRequested, isTrue);
  });

  testWidgets('전체 저장 후 오늘 일정과 저장 목록으로 이어지는 선택지를 제공한다', (tester) async {
    var todayScheduleRequested = false;
    var savedMedicationRequested = false;
    const analyzedMedication = AnalyzedMedication(
      schedule: MedicationSchedule(
        medicationName: '테스트정',
        dosage: '1정',
        intakeTime: '1일 1회',
        medicationTime: 3,
      ),
      detail: MedicationDetail(
        itemName: '테스트정',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CheckResultUI(
          analyzedMedicationList: const [analyzedMedication],
          userSetting: const UserSetting(),
          statusMessageProvider: () => '',
          savingMedicationIndex: null,
          completedMedicationSaveIndexes: const {},
          isAllMedicationSaving: false,
          onCloseRequested: () {},
          onTodayScheduleRequested: () => todayScheduleRequested = true,
          onSavedMedicationRequested: () => savedMedicationRequested = true,
          onHomeRequested: () {},
          onAllMedicationSaveRequested: () async => true,
          onMedicationSaveRequested: (_, _) async => true,
        ),
      ),
    );

    await tester.tap(find.text('전체 저장하기'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 일정 확인'), findsOneWidget);
    expect(find.text('저장된 정보 보기'), findsOneWidget);

    await tester.tap(find.text('오늘 일정 확인'));
    await tester.pumpAndSettle();
    expect(todayScheduleRequested, isTrue);

    await tester.tap(find.text('전체 저장하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장된 정보 보기'));
    await tester.pumpAndSettle();
    expect(savedMedicationRequested, isTrue);
  });

  test('복용 종료일과 현재 복용 여부를 조제일자와 투약일로 계산한다', () {
    const medication = MedicationDetail(
      itemName: '테스트약',
      efficacy: '',
      usageMethod: '',
      warning: '',
      prescriptionDate: null,
      totalDays: '3일',
    );
    final scheduledMedication = MedicationDetail(
      itemName: medication.itemName,
      efficacy: medication.efficacy,
      usageMethod: medication.usageMethod,
      warning: medication.warning,
      prescriptionDate: DateTime(2026, 8, 1),
      totalDays: medication.totalDays,
    );

    expect(scheduledMedication.medicationEndDate, DateTime(2026, 8, 3));
    expect(scheduledMedication.isActiveOn(DateTime(2026, 8, 3)), isTrue);
    expect(scheduledMedication.isActiveOn(DateTime(2026, 8, 4)), isFalse);
  });

  test('기술 오류를 사용자가 대응할 수 있는 문구로 구분한다', () {
    expect(
      UserFacingErrorMessage.resolve(
        const SocketException('offline'),
        isEnglish: false,
      ),
      contains('인터넷 연결'),
    );
    expect(
      UserFacingErrorMessage.resolve(
        TimeoutException('slow'),
        isEnglish: false,
      ),
      contains('응답이 지연'),
    );
    expect(
      UserFacingErrorMessage.resolve(
        StateError('404 not found'),
        isEnglish: false,
        context: UserFacingErrorContext.medicationLookup,
      ),
      contains('OCR 약 이름'),
    );
  });
}
