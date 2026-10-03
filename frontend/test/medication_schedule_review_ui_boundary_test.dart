// 파일명: medication_schedule_review_ui_boundary_test.dart
// 역할: 분석 후 복용 시작일, 기간, 횟수와 시간대 검토 화면을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_schedule_review_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할:
// - OCR 일정 편집, 날짜 범위와 접근성 검토 대화상자 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: OCR 기본값을 수정한 뒤 확인 결과로 반환한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('OCR 기본값을 수정한 뒤 확인 결과로 반환한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    List<MedicationSchedule>? reviewedSchedules;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 일정 검토 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-schedule-review'),
                // 함수이름: onPressed 콜백
                // 함수역할:
                // - 복약 일정 검토 화면을 열고 선택 결과를 기록한다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 대화상자 선택 결과 기록 완료.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 큰 글씨와 작은 화면에서도 검토 목록을 스크롤할 수 있다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('큰 글씨와 작은 화면에서도 검토 목록을 스크롤할 수 있다', (tester) async {
    await _setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 1.3배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 일정 검토 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-large-schedule-review'),
                // 함수이름: onPressed 콜백
                // 함수역할:
                // - 복약 일정 검토 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 화면 이동 또는 대화상자 결과 Future.
                onPressed: () {
                  showMedicationScheduleReview(
                    context: context,
                    initialSchedules: List.generate(
                      4,
                      // 함수이름: generate 콜백
                      // 함수역할:
                      // - 스크롤 도달 범위를 검사할 긴 약명의 일주일 아침 일정을 순번별로 만든다.
                      // 매개변수:
                      // - index (int): 0부터 시작하는 행 또는 생성 대역의 순번.
                      // 반환값:
                      // - 2026-08-23 시작, 7일 복용 일정 한 건.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: OCR 날짜가 일반 범위를 벗어나도 날짜 수정 창을 열 수 있다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('OCR 날짜가 일반 범위를 벗어나도 날짜 수정 창을 열 수 있다', (tester) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 일정 검토 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open-future-schedule-review'),
              // 함수이름: onPressed 콜백
              // 함수역할:
              // - 복약 일정 검토 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 대화상자가 열린다.
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

// 함수이름: _setViewport
// 함수역할:
// - 작은 논리 화면 크기를 적용하고 테스트 종료 시 크기와 픽셀 비율 복원을 등록한다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// - size (Size): 레이아웃 검사에 사용할 논리 화면 크기.
// 반환값:
// - 화면 크기 설정 완료.
Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
