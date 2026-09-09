// 파일명: accessibility_layout_regression_test.dart
// 역할: 작은 화면과 큰 글씨에서 주요 화면의 접근성 레이아웃 회귀를 검증한다. 베타 핵심 화면의 작은 화면, 큰 글씨, 접근성, 생명주기 회귀를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_today_medication_info_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/health_recommendation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_reminder_settings_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/set_caregiver_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/caregiver_notification_entity.dart';
import 'package:medbuddy_frontend/entities/health_recommendation_entity.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _AccessibilityScheduleControl
// 역할: 접근성 레이아웃 검증에 사용할 긴 약 이름의 복약 일정을 제공한다.
// 주요 책임:
// - 줄바꿈과 카드 높이를 검사하도록 긴 약명을 가진 두 복약 일정을 제공한다.
class _AccessibilityScheduleControl extends CheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할:
  // - 줄바꿈과 카드 높이를 검사하도록 긴 약명을 가진 두 복약 일정을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 긴 약명과 하루 세 번 복용 정보를 가진 일정 목록.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [
      MedicationSchedule(
        medicationID: 'accessibility-tablet-1',
        medicationName: '대웅바이오클래리트로마이신건조시럽125mg/5mL',
        dosage: '0.5',
        intakeTime: '1일 3회',
        medicationTime: 3,
      ),
      MedicationSchedule(
        medicationID: 'accessibility-tablet-2',
        medicationName: '아세트아미노펜서방정650mg',
        dosage: '1',
        intakeTime: '1일 3회',
        medicationTime: 3,
      ),
    ];
  }
}

// 클래스명: _EmptyNotificationControl
// 역할: 외부 통신 없이 알림 미설정 상태를 제공한다.
// 주요 책임:
// - 알림이 설정되지 않은 접근성 화면을 외부 조회 없이 구성한다.
class _EmptyNotificationControl extends SetNotification {
  // 함수이름: requestMedicationAlarm
  // 함수역할:
  // - 알림이 설정되지 않은 접근성 화면을 외부 조회 없이 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 빈 복약 알림 목록.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// 클래스명: _AccessibilityHealthRecommendationControl
// 역할: 외부 통신 없이 큰 글씨 건강 추천 화면에 긴 안내 문구를 제공한다.
// 주요 책임:
// - 큰 글씨에서 건강 추천 영역이 늘어나는지 검사할 긴 식사·운동·주의 문구를 제공한다.
class _AccessibilityHealthRecommendationControl
    extends CheckHealthRecommendation {
  // 함수이름: requestHealthRecommendation
  // 함수역할:
  // - 큰 글씨에서 건강 추천 영역이 늘어나는지 검사할 긴 식사·운동·주의 문구를 제공한다.
  // 매개변수:
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 고정된 건강 추천과 두 주의 항목.
  @override
  Future<HealthRecommendation> requestHealthRecommendation({
    String language = 'ko',
  }) async {
    return const HealthRecommendation(
      dietRecommendation:
          '복용 중인 약과 음식의 상호작용을 줄이기 위해 규칙적으로 식사하고 충분한 물과 함께 복용하세요.',
      exerciseRecommendation: '몸 상태를 확인하면서 가벼운 걷기부터 시작하고 어지럼증이 있으면 즉시 쉬어주세요.',
      cautionItems: [
        '심한 어지럼증이나 호흡 곤란이 나타나면 즉시 의료진과 상담하세요.',
        '다른 약이나 건강기능식품을 함께 복용하기 전 전문가에게 확인하세요.',
      ],
    );
  }
}

// Function Name: main
// Description:
// - Register regression cases for compact-screen layout, large text, scrolling, and semantic-label
//   regressions.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: group callback
  // Description:
  // - Group the regression cases for compact-screen layout, large text, scrolling, and semantic-label
  //   regressions.
  // Parameters:
  // - None.
  // Returns:
  // - No value; registers the grouped cases.
  group('베타 접근성 레이아웃 회귀', () {
    const viewportCases = [
      (size: Size(320, 568), textScale: 1.6),
      (size: Size(360, 640), textScale: 2.0),
      (size: Size(412, 915), textScale: 2.0),
    ];

    for (final viewportCase in viewportCases) {
      // 함수이름: testWidgets 콜백
      // 함수역할:
      // - 각 화면 너비와 글씨 배율 조합에서도 환경설정 저장 버튼이 남아 있는지 검증한다.
      // 매개변수:
      // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
      // 반환값:
      // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
      testWidgets('환경설정은 ${viewportCase.size.width.toInt()} 너비와 '
          '${viewportCase.textScale}배 글씨에서도 저장 버튼을 유지한다', (tester) async {
        await _setViewport(tester, viewportCase.size);
        final authenticationControl = AuthenticationControl.development();
        addTearDown(authenticationControl.dispose);

        await tester.pumpWidget(
          _scaledMaterialApp(
            textScale: viewportCase.textScale,
            home: ManageUserSettingUI(
              initialSetting: const UserSetting(fontSize: 20),
              authenticationControl: authenticationControl,
              onSettingSaveRequested:
                  // 함수이름: onSettingSaveRequested 콜백
                  // 함수역할:
                  // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
                  // 매개변수:
                  // - fontSizeOption (String): 선택한 앱 글씨 크기 옵션. 이 대역에서는 직접 사용하지 않는다.
                  // - readingSpeedOption (String): 선택한 음성 읽기 속도 옵션. 이 대역에서는 직접 사용하지 않는다.
                  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
                  // 반환값:
                  // - 서버 동기화 상태의 설정 저장 결과.
                  ({
                    required fontSizeOption,
                    required readingSpeedOption,
                    required language,
                  }) async => _synchronizedSettingResult(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openDisplayAndVoiceSettings(tester);

        expect(find.text('글씨크기'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, '저장하기').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 핵심 명령은 TalkBack이 읽을 수 있는 의미 라벨을 제공한다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('핵심 명령은 TalkBack이 읽을 수 있는 의미 라벨을 제공한다', (tester) async {
      await _setViewport(tester, const Size(360, 640));
      final semantics = tester.ensureSemantics();
      final authenticationControl = AuthenticationControl.development();
      addTearDown(authenticationControl.dispose);

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 1.6,
          home: ManageUserSettingUI(
            initialSetting: const UserSetting(),
            authenticationControl: authenticationControl,
            onSettingSaveRequested:
                // 함수이름: onSettingSaveRequested 콜백
                // 함수역할:
                // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
                // 매개변수:
                // - fontSizeOption (String): 선택한 앱 글씨 크기 옵션. 이 대역에서는 직접 사용하지 않는다.
                // - readingSpeedOption (String): 선택한 음성 읽기 속도 옵션. 이 대역에서는 직접 사용하지 않는다.
                // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
                // 반환값:
                // - 서버 동기화 상태의 설정 저장 결과.
                ({
                  required fontSizeOption,
                  required readingSpeedOption,
                  required language,
                }) async => _synchronizedSettingResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openDisplayAndVoiceSettings(tester);

      expect(find.bySemanticsLabel('뒤로가기'), findsOneWidget);
      expect(find.bySemanticsLabel('저장하기'), findsOneWidget);
      expect(find.bySemanticsLabel('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 환경설정 선택값은 앱 일시중지와 재개 후에도 유지된다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('환경설정 선택값은 앱 일시중지와 재개 후에도 유지된다', (tester) async {
      await _setViewport(tester, const Size(360, 640));
      final authenticationControl = AuthenticationControl.development();
      addTearDown(authenticationControl.dispose);

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 1.3,
          home: ManageUserSettingUI(
            initialSetting: const UserSetting(),
            authenticationControl: authenticationControl,
            onSettingSaveRequested:
                // 함수이름: onSettingSaveRequested 콜백
                // 함수역할:
                // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
                // 매개변수:
                // - fontSizeOption (String): 선택한 앱 글씨 크기 옵션. 이 대역에서는 직접 사용하지 않는다.
                // - readingSpeedOption (String): 선택한 음성 읽기 속도 옵션. 이 대역에서는 직접 사용하지 않는다.
                // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
                // 반환값:
                // - 서버 동기화 상태의 설정 저장 결과.
                ({
                  required fontSizeOption,
                  required readingSpeedOption,
                  required language,
                }) async => _synchronizedSettingResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openDisplayAndVoiceSettings(tester);
      await tester.tap(find.text('크게'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('크게'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final viewportSize in const [Size(360, 640), Size(412, 915)]) {
      // 함수이름: 기본 글씨 홈 안내 접근성 테스트
      // 함수역할: 복약 안내를 생략 없이 표시하고 작은 화면에서는 스크롤로 모든 정보에 접근할 수 있는지 확인한다.
      // 매개변수: tester (WidgetTester): 화면 배치와 상호작용 검증 도구.
      // 반환값: 화면 크기별 안내 표시와 스크롤 접근성 검증 완료.
      testWidgets(
        '홈 화면은 ${viewportSize.width.toInt()}x${viewportSize.height.toInt()} '
        '기본 글씨에서 안내를 생략하지 않고 모든 정보에 접근할 수 있다',
        (tester) async {
          await _setViewport(tester, viewportSize);

          await tester.pumpWidget(
            _scaledMaterialApp(
              textScale: 1,
              home: InputPrescriptionUI(
                statusMessage: '',
                userSetting: const UserSetting(),
                todayMedicationScheduleList: const [
                  MedicationSchedule(
                    medicationID: 'compact-home-1',
                    medicationName: '데파스정1밀리그람(에티졸람)',
                    dosage: '1',
                    intakeTime: '1일 3회',
                    medicationTime: 3,
                  ),
                ],
                medicationReminderSettings: const {
                  'morning': MedicationAlarm(
                    slotKey: 'morning',
                    hour: 8,
                    minute: 0,
                    enabled: true,
                  ),
                },
                todayMedicationCompletedCount: 0,
                todayMedicationTotalCount: 4,
                // Function Name: nowProvider callback
                // Description:
                // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
                // Parameters:
                // - None.
                // Returns:
                // - DateTime from DateTime(2026, 8, 30, 7).
                nowProvider: () => DateTime(2026, 8, 30, 7),
                // 함수이름: onPrescriptionScanRequested 콜백
                // 함수역할:
                // - 처방전 카메라 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onPrescriptionScanRequested: () {},
                // 함수이름: onPrescriptionGalleryRequested 콜백
                // 함수역할:
                // - 처방전 갤러리 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onPrescriptionGalleryRequested: () {},
                // 함수이름: onPillIdentificationRequested 콜백
                // 함수역할:
                // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onPillIdentificationRequested: () {},
                // 함수이름: onTodayScheduleRequested 콜백
                // 함수역할:
                // - 오늘 일정 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onTodayScheduleRequested: () {},
                // Function Name: onHealthRecommendationRequested callback
                // Description:
                // - Keep health-recommendation navigation available in the fixture without performing the action.
                // Parameters:
                // - None.
                // Returns:
                // - No value; the action is intentionally inert.
                onHealthRecommendationRequested: () {},
                // Function Name: onMedicationReminderRequested callback
                // Description:
                // - Keep reminder-settings navigation available in the fixture without performing the action.
                // Parameters:
                // - None.
                // Returns:
                // - No value; the action is intentionally inert.
                onMedicationReminderRequested: () {},
                // 함수이름: onUserSettingRequested 콜백
                // 함수역할:
                // - 사용자 설정 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onUserSettingRequested: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final dashboardScrollable = find.descendant(
            of: find.byKey(const ValueKey('homeDashboardScrollView')),
            matching: find.byType(Scrollable),
          );
          expect(dashboardScrollable, findsAtLeastNWidgets(1));
          final guidance = tester.renderObject<RenderParagraph>(
            find.textContaining('시간에 맞춰 챙겨드세요.'),
          );
          expect(guidance.didExceedMaxLines, isFalse);
          final dashboardRect = tester.getRect(
            find.byKey(const ValueKey('homeEncouragementPanel')),
          );
          final firstActionRect = tester.getRect(
            find.byKey(const ValueKey('homePrescriptionAnalysisCard')),
          );
          expect(
            firstActionRect.top - dashboardRect.bottom,
            moreOrLessEquals(
              viewportSize.height >= 900 ? 20 : 12,
              epsilon: 0.1,
            ),
          );
          expect(
            find.byKey(const ValueKey('homeMedicationReminderCard')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('homeMedicationTipCard')),
            findsNothing,
          );
          final reminders = find.byKey(
            const ValueKey('homeMedicationReminderCard'),
          );
          await tester.ensureVisible(reminders);
          await tester.pumpAndSettle();
          expect(reminders.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final viewportCase in const [
      (size: Size(320, 568), textScale: 1.3),
      (size: Size(360, 640), textScale: 2.0),
    ]) {
      // 함수이름: 큰 글씨 홈 화면 스크롤 테스트
      // 함수역할: 강제 줄바꿈 없이 표시된 기능 제목과 설명을 스크롤로 확인할 수 있는지 검사한다.
      // 매개변수: tester (WidgetTester): 화면 배치와 상호작용을 검증하는 도구.
      // 반환값: 모든 기능에 접근할 수 있는지 검증하는 Future<void>.
      testWidgets('홈 화면은 ${viewportCase.size.width.toInt()} 너비와 '
          '${viewportCase.textScale}배 글씨에서도 모든 기능을 스크롤해 표시한다', (tester) async {
        await _setViewport(tester, viewportCase.size);

        await tester.pumpWidget(
          _scaledMaterialApp(
            textScale: viewportCase.textScale,
            home: InputPrescriptionUI(
              statusMessage: '',
              userSetting: const UserSetting(fontSize: 20),
              // 함수이름: onPrescriptionScanRequested 콜백
              // 함수역할:
              // - 처방전 카메라 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 외부 동작을 수행하지 않는다.
              onPrescriptionScanRequested: () {},
              // 함수이름: onPrescriptionGalleryRequested 콜백
              // 함수역할:
              // - 처방전 갤러리 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 외부 동작을 수행하지 않는다.
              onPrescriptionGalleryRequested: () {},
              // 함수이름: onPillIdentificationRequested 콜백
              // 함수역할:
              // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 외부 동작을 수행하지 않는다.
              onPillIdentificationRequested: () {},
              // 함수이름: onTodayScheduleRequested 콜백
              // 함수역할:
              // - 오늘 일정 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 외부 동작을 수행하지 않는다.
              onTodayScheduleRequested: () {},
              // Function Name: onHealthRecommendationRequested callback
              // Description:
              // - Keep health-recommendation navigation available in the fixture without performing the action.
              // Parameters:
              // - None.
              // Returns:
              // - No value; the action is intentionally inert.
              onHealthRecommendationRequested: () {},
              // Function Name: onMedicationReminderRequested callback
              // Description:
              // - Keep reminder-settings navigation available in the fixture without performing the action.
              // Parameters:
              // - None.
              // Returns:
              // - No value; the action is intentionally inert.
              onMedicationReminderRequested: () {},
              // 함수이름: onUserSettingRequested 콜백
              // 함수역할:
              // - 사용자 설정 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
              // 매개변수:
              // - 없음.
              // 반환값:
              // - 없음; 외부 동작을 수행하지 않는다.
              onUserSettingRequested: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('MedBuddy'), findsOneWidget);
        expect(find.text('약 등록·식별'), findsOneWidget);
        expect(find.text('근처 운영 약국'), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(find.text('복약 알림 설정'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: OCR 검토 화면은 작은 화면과 2배 글씨에서 수정·분석 명령을 유지한다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('OCR 검토 화면은 작은 화면과 2배 글씨에서 수정·분석 명령을 유지한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: PrescriptionAnalysisPreviewUI(
            medicationScheduleList: const [
              MedicationSchedule(
                medicationName: '대웅바이오클래리트로마이신건조시럽125mg/5mL',
                dosage: '1정',
                intakeTime: '1일 3회',
                medicationTime: 3,
                nameCorrectionSource: 'unverified',
              ),
              MedicationSchedule(
                medicationName: '아세트아미노펜서방정650mg',
                dosage: '0.5정',
                intakeTime: '1일 2회',
                medicationTime: 2,
                nameCorrectionSource: 'unverified',
              ),
            ],
            userSetting: const UserSetting(fontSize: 20),
            // 함수이름: onBackRequested 콜백
            // 함수역할:
            // - 뒤로가기 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onBackRequested: () {},
            // 함수이름: onAnalysisRequested 콜백
            // 함수역할:
            // - 약 상세 분석 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onAnalysisRequested: () {},
            // 함수이름: onMedicationScheduleChanged 콜백
            // 함수역할:
            // - OCR 일정 수정 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - _ [1] (int): 사용하지 않는 수정 행 인덱스.
            // - _ [2] (MedicationSchedule): 사용하지 않는 수정 일정.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onMedicationScheduleChanged: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final medicationNameCell = find.byKey(const Key('ocr-table-cell-0-name'));
      expect(find.byKey(const Key('ocr-medication-table')), findsOneWidget);
      await tester.ensureVisible(medicationNameCell);
      await tester.pumpAndSettle();
      expect(medicationNameCell.hitTestable(), findsOneWidget);

      await tester.tap(medicationNameCell);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-edit-name')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ocr-edit-cancel')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('prescription-analyze-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('prescription-analyze-button')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 오늘 복약 일정은 작은 화면과 2배 글씨에서도 스크롤할 수 있다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('오늘 복약 일정은 작은 화면과 2배 글씨에서도 스크롤할 수 있다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      SharedPreferences.setMockInitialValues({});
      final viewModel = MedBuddyViewModel(
        checkSchedule: _AccessibilityScheduleControl(),
        setNotification: _EmptyNotificationControl(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: _scaledMaterialApp(
            textScale: 2,
            home: const CheckScheduleUI(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Function Name: testWidgets callback
    // Description:
    // - Verify that quick reminder settings expose every dose slot on a small screen with enlarged text.
    // Parameters:
    // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
    // Returns:
    // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
    testWidgets('복약 알림 빠른 설정은 작은 화면과 큰 글씨에서도 모든 시간대를 제공한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      SharedPreferences.setMockInitialValues({});
      final viewModel = MedBuddyViewModel(
        checkSchedule: _AccessibilityScheduleControl(),
        setNotification: _EmptyNotificationControl(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: _scaledMaterialApp(
            textScale: 1.6,
            home: const MedicationReminderSettingsUI(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('복약 알림 설정'), findsOneWidget);
      expect(find.text('아침'), findsOneWidget);
      expect(find.text('점심'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('저녁'), findsOneWidget);
      expect(find.text('취침 전'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 홈 일정 요약은 긴 약 이름과 2배 글씨에서도 카드 높이를 늘린다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('홈 일정 요약은 긴 약 이름과 2배 글씨에서도 카드 높이를 늘린다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: CheckTodayMedicationInfoUI(
                title: '오늘의 복약 일정',
                noMedicationLabel: '등록된 약이 없습니다',
                userSetting: const UserSetting(),
                schedules: const [
                  MedicationSchedule(
                    medicationName: '대웅바이오클래리트로마이신건조시럽125mg/5mL',
                  ),
                  MedicationSchedule(medicationName: '아세트아미노펜서방정650mg'),
                ],
                completedCount: 1,
                totalCount: 6,
                isLoading: false,
                // 함수이름: onTap 콜백
                // 함수역할:
                // - 표시된 복약 카드 명령 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 없음; 외부 동작을 수행하지 않는다.
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('오늘의 복약 일정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 약 상세정보는 작은 화면과 2배 글씨에서도 끝까지 스크롤된다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('약 상세정보는 작은 화면과 2배 글씨에서도 끝까지 스크롤된다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: const CheckMedicationDetailUI(
            medicationDetail: MedicationDetail(
              itemName: '대웅바이오클래리트로마이신정250mg',
              efficacy: '호흡기 감염과 피부 감염 치료에 사용됩니다.',
              usageMethod: '처방받은 기간 동안 정해진 용량을 복용하세요.',
              warning: '심한 이상 반응이 나타나면 의료진과 상담하세요.',
              dosagePerTime: '1정',
              dailyFrequency: '1일 3회',
              totalDays: '7일',
            ),
            userSetting: UserSetting(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('약 상세정보'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 약 상세정보의 사진을 누르면 확대 화면을 열고 닫는다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('약 상세정보의 사진을 누르면 확대 화면을 열고 닫는다', (tester) async {
      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 1,
          home: const CheckMedicationDetailUI(
            medicationDetail: MedicationDetail(
              itemName: '사진 테스트정',
              efficacy: '테스트 효능',
              usageMethod: '하루 한 번 복용하세요.',
              warning: '주의사항을 확인하세요.',
              imageUrl: 'https://nedrug.mfds.go.kr/tablet.png',
            ),
            userSetting: UserSetting(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('medication-detail-image-button')));
      await tester.pump();
      expect(
        find.byKey(const Key('medication-image-viewer-close')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('medication-image-viewer-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Function Name: testWidgets callback
    // Description:
    // - Verify that medication details display noun-phrase summaries while retaining the original TTS
    //   text.
    // Parameters:
    // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
    // Returns:
    // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
    testWidgets('약 상세정보는 명사형 요약을 표시하고 TTS 원문은 보존한다', (tester) async {
      const medicationDetail = MedicationDetail(
        itemName: '테스트정',
        efficacy: '이 약은 다발성 관절염, 류마티스 관절염, 통증 및 발열을 수반하는 감염증에 사용합니다.',
        usageMethod: '식후 충분한 물과 함께 복용하고 임의로 중단하지 마세요.',
        warning: '주의사항',
        dosagePerTime: '1정',
        dailyFrequency: '1일 1회',
        totalDays: '7일',
      );
      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 1,
          home: const CheckMedicationDetailUI(
            medicationDetail: medicationDetail,
            userSetting: UserSetting(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('다발성 관절염'), findsOneWidget);
      expect(find.text('류마티스 관절염'), findsOneWidget);
      expect(find.text('통증 및 발열을 수반하는 감염증'), findsOneWidget);
      expect(find.text('1회 복용량 · 1정'), findsWidgets);
      expect(find.text('복용 횟수 · 1일 1회'), findsWidgets);
      expect(find.text('복용 기간 · 7일'), findsWidgets);
      expect(find.text(medicationDetail.usageMethod), findsNothing);
      expect(
        medicationDetail.voiceGuideText,
        contains(medicationDetail.usageMethod),
      );
      expect(tester.takeException(), isNull);
    });

    // Function Name: testWidgets callback
    // Description:
    // - Verify that separate efficacy sentences become independent noun-phrase summaries.
    // Parameters:
    // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
    // Returns:
    // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
    testWidgets('약 상세정보는 다중 문장 효능을 독립된 명사형으로 정리한다', (tester) async {
      const medicationDetail = MedicationDetail(
        itemName: '테스트정',
        efficacy:
            '이 약은 우울 증상을 완화합니다. 또한 경추증, '
            '두통 등 질환으로 인한 근육 긴장을 풀어주고, '
            '통증 및 발열을 수반하는 감염증에 사용합니다.',
        usageMethod: '식후 충분한 물과 함께 복용하세요.',
        warning: '주의사항',
      );
      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 1,
          home: const CheckMedicationDetailUI(
            medicationDetail: medicationDetail,
            userSetting: UserSetting(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('우울 증상'), findsOneWidget);
      expect(find.text('경추증'), findsOneWidget);
      expect(find.text('두통 등 질환으로 인한 근육 긴장'), findsOneWidget);
      expect(find.text('통증 및 발열을 수반하는 감염증'), findsOneWidget);
      expect(medicationDetail.efficacy, contains('우울 증상을 완화합니다'));
      expect(tester.takeException(), isNull);
    });
    // Function Name: testWidgets callback
    // Description:
    // - Verify that analysis results keep save actions reachable with long drug names and double-size
    //   text.
    // Parameters:
    // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
    // Returns:
    // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
    testWidgets('처방 분석 결과는 긴 약 이름과 2배 글씨에서도 저장 명령을 유지한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      const schedule = MedicationSchedule(
        medicationName: '대웅바이오클래리트로마이신건조시럽125mg/5mL',
        dosage: '0.5정',
        intakeTime: '1일 3회',
        medicationTime: 7,
      );

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: CheckResultUI(
            analyzedMedicationList: const [
              AnalyzedMedication(
                schedule: schedule,
                detail: MedicationDetail(
                  itemName: '대웅바이오클래리트로마이신건조시럽125mg/5mL',
                  efficacy: '',
                  usageMethod: '',
                  warning: '',
                ),
              ),
            ],
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
      await tester.pumpAndSettle();

      expect(find.text('처방전 분석 결과'), findsOneWidget);
      expect(find.text('전체 저장하기'), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 건강 관리 추천은 작은 화면과 2배 글씨에서도 모든 카드를 표시한다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('건강 관리 추천은 작은 화면과 2배 글씨에서도 모든 카드를 표시한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      final viewModel = MedBuddyViewModel(
        checkHealthRecommendation: _AccessibilityHealthRecommendationControl(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: _scaledMaterialApp(
            textScale: 2,
            home: const HealthRecommendationUI(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('건강 관리 추천'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('주의사항'),
        400,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('주의사항'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 건강 관리 추천의 마지막 카드는 하단 안전영역 위에서 끝난다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('건강 관리 추천의 마지막 카드는 하단 안전영역 위에서 끝난다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      final viewModel = MedBuddyViewModel(
        checkHealthRecommendation: _AccessibilityHealthRecommendationControl(),
      );
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: _scaledMaterialApp(
            textScale: 1.3,
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.only(bottom: 32),
                viewPadding: EdgeInsets.only(bottom: 32),
              ),
              child: HealthRecommendationUI(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.byType(ListView);
      await tester.fling(list, const Offset(0, -4000), 10000);
      await tester.pumpAndSettle();

      final cautionCard = find.byKey(
        const ValueKey('healthRecommendationCautionCard'),
      );
      expect(cautionCard, findsOneWidget);
      expect(tester.getBottomRight(cautionCard).dy, lessThanOrEqualTo(508));
      expect(tester.takeException(), isNull);
    });

    // Function Name: testWidgets callback
    // Description:
    // - Verify that every authentication option remains scrollable on a compact screen with double-size
    //   text.
    // Parameters:
    // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
    // Returns:
    // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
    testWidgets('로그인 화면은 작은 화면과 2배 글씨에서도 모든 인증 수단을 스크롤한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));
      final authenticationControl = AuthenticationControl.development();
      addTearDown(authenticationControl.dispose);

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: AuthenticationUI(control: authenticationControl),
        ),
      );
      await tester.pumpAndSettle();
      final guestButton = find.text('회원가입 없이 계속하기');
      await tester.ensureVisible(guestButton);
      await tester.pumpAndSettle();

      expect(find.text('MedBuddy'), findsOneWidget);
      expect(guestButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 촬영 작업 선택지는 작은 화면과 2배 글씨에서도 스크롤된다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('촬영 작업 선택지는 작은 화면과 2배 글씨에서도 스크롤된다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: Builder(
            // 함수이름: builder 콜백
            // 함수역할:
            // - 약 입력 방식 선택 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
            // 매개변수:
            // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
            // 반환값:
            // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
            builder: (context) => Scaffold(
              body: FilledButton(
                // 함수이름: onPressed 콜백
                // 함수역할:
                // - 약 입력 방식 선택 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 화면 이동 또는 대화상자 결과 Future.
                onPressed: () => showMedicationCaptureTaskOptions(
                  context: context,
                  userSetting: const UserSetting(),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.text('처방전 분석'), findsOneWidget);
      expect(find.text('낱알약 식별'), findsOneWidget);
      expect(find.text('직접 등록'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: testWidgets 콜백
    // 함수역할:
    // - 기대 동작: 보호자 알림 설정은 작은 화면과 2배 글씨에서도 저장 버튼에 접근한다.
    // 매개변수:
    // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
    // 반환값:
    // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
    testWidgets('보호자 알림 설정은 작은 화면과 2배 글씨에서도 저장 버튼에 접근한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: Builder(
            // 함수이름: builder 콜백
            // 함수역할:
            // - 보호자 미복용 알림 설정 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
            // 매개변수:
            // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
            // 반환값:
            // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
            builder: (context) => Scaffold(
              body: FilledButton(
                // 함수이름: onPressed 콜백
                // 함수역할:
                // - 보호자 미복용 알림 설정 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
                // 매개변수:
                // - 없음.
                // 반환값:
                // - 화면 이동 또는 대화상자 결과 Future.
                onPressed: () =>
                    SetCaregiverNotificationUI.showNotificationPopup(
                      context,
                      setting: const CaregiverNotification(
                        mode: CaregiverNotificationMode.missedDeadline,
                        deadlineHour: 21,
                        deadlineMinute: 0,
                      ),
                      slotLabel: '아침',
                    ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final saveButton = find.text('저장하기');
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();

      expect(saveButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// 함수이름: _openDisplayAndVoiceSettings
// 함수역할:
// - 화면 및 음성 설정 메뉴가 보이도록 스크롤한 뒤 열고 전환을 기다린다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// 반환값:
// - 설정 화면 전환 완료.
Future<void> _openDisplayAndVoiceSettings(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('settingsDisplayAndVoiceMenu'));
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

// 함수이름: _setViewport
// 함수역할:
// - 테스트의 논리 화면 크기를 지정하고 픽셀 비율과 크기의 사후 복원을 등록한다.
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

// 함수이름: _scaledMaterialApp
// 함수역할:
// - 지정한 화면에 접근성 글씨 배율을 주입하는 테스트 앱을 구성한다.
// 매개변수:
// - textScale (double): 하위 위젯에 적용할 접근성 글씨 배율.
// - home (Widget): 테스트 앱의 첫 화면으로 배치할 위젯.
// 반환값:
// - 지정 배율의 MediaQuery로 감싼 MaterialApp.
Widget _scaledMaterialApp({required double textScale, required Widget home}) {
  return MaterialApp(
    // 함수이름: builder 콜백
    // 함수역할:
    // - 기존 하위 화면에 textScale배 글씨를 적용해 접근성 배치를 검사한다.
    // 매개변수:
    // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
    // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
    // 반환값:
    // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}

// 함수이름: _synchronizedSettingResult
// 함수역할:
// - 서버 동기화가 성공한 기본 설정 저장 결과를 제공한다.
// 매개변수:
// - 없음.
// 반환값:
// - synchronizedWithServer가 true인 기본 설정 결과.
UserSettingSaveResult _synchronizedSettingResult() {
  return const UserSettingSaveResult(
    setting: UserSetting(),
    synchronizedWithServer: true,
  );
}
