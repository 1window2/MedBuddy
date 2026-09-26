// 파일명: ux_improvement_regression_test.dart
// 역할: 다음 복약 요약, 복용 기간 필터 기준, 오류 안내의 핵심 UX 동작을 검증한다.
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


// 함수이름: main
// 함수역할:
// - 홈 안내, OCR 복구, 저장 후 이동과 대응 가능한 오류 문구 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 홈 카드가 다음 복약 시간과 오늘 진행률을 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
            // 함수이름: onTap 콜백
            // 함수역할:
            // - 표시된 복약 카드 명령 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onTap: () {},
            // 함수이름: nowProvider 콜백
            // 함수역할:
            // - 실제 시계와 무관하게 복약 마감과 알림 날짜 범위를 검사할 기준 시각을 제공한다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - fixedNow에서 얻은 기준 DateTime.
            nowProvider: () => fixedNow,
          ),
        ),
      ),
    );

    expect(find.text('다음 복약: 점심 12:30'), findsOneWidget);
    expect(find.text('복용할 약 1개 · 오늘 1/2회 완료'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 약 정보 조회 실패 후 OCR 검토 화면으로 돌아갈 수 있다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('약 정보 조회 실패 후 OCR 검토 화면으로 돌아갈 수 있다', (tester) async {
    var ocrReviewRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisFailureUI(
          message: '약 이름을 찾지 못했습니다.',
          userSetting: const UserSetting(),
          failureStep: AnalysisProgressStep.medicationAnalysis,
          // 함수이름: onAnalysisRetryRequested 콜백
          // 함수역할:
          // - 약 상세 분석 재시도 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onAnalysisRetryRequested: () {},
          // 함수이름: onOcrReviewRequested 콜백
          // 함수역할:
          // - OCR 검토 복귀 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onOcrReviewRequested: () => ocrReviewRequested = true,
          // 함수이름: onCameraRetryRequested 콜백
          // 함수역할:
          // - 처방전 카메라 재시도 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onCameraRetryRequested: () {},
          // 함수이름: onGalleryRetryRequested 콜백
          // 함수역할:
          // - 갤러리 인식 재시도 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onGalleryRetryRequested: () {},
          // 함수이름: onHomeRequested 콜백
          // 함수역할:
          // - 홈 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 전체 저장 후 오늘 일정과 저장 목록으로 이어지는 선택지를 제공한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
          // 함수이름: statusMessageProvider 콜백
          // 함수역할:
          // - 분석 결과 검사에 불필요한 상태 문구가 표시되지 않게 한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 빈 문자열.
          statusMessageProvider: () => '',
          savingMedicationIndex: null,
          completedMedicationSaveIndexes: const {},
          isAllMedicationSaving: false,
          // 함수이름: onCloseRequested 콜백
          // 함수역할:
          // - 분석 흐름 닫기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onCloseRequested: () {},
          // 함수이름: onTodayScheduleRequested 콜백
          // 함수역할:
          // - 오늘 일정 화면 이동 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onTodayScheduleRequested: () => todayScheduleRequested = true,
          // 함수이름: onSavedMedicationRequested 콜백
          // 함수역할:
          // - 저장 약 목록 이동 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onSavedMedicationRequested: () => savedMedicationRequested = true,
          // 함수이름: onHomeRequested 콜백
          // 함수역할:
          // - 홈 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onHomeRequested: () {},
          // 함수이름: onAllMedicationSaveRequested 콜백
          // 함수역할:
          // - 저장 성공을 제공해 결과 화면의 저장 후 이동 명령을 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - true로 완료되는 Future<bool>.
          onAllMedicationSaveRequested: () async => true,
          // 함수이름: onMedicationSaveRequested 콜백
          // 함수역할:
          // - 저장 성공을 제공해 결과 화면의 저장 후 이동 명령을 검사한다.
          // 매개변수:
          // - _ [1] (AnalyzedMedication): 실제 저장 없이 성공 처리할 분석 약.
          // - _ [2] (int): 성공 대역이 사용하지 않는 저장 행 인덱스.
          // 반환값:
          // - true로 완료되는 Future<bool>.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 복용 종료일과 현재 복용 여부를 조제일자와 투약일로 계산한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 기술 오류를 사용자가 대응할 수 있는 문구로 구분한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
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
