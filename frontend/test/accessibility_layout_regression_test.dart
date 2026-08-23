import 'package:flutter/material.dart';
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

// 파일명: accessibility_layout_regression_test.dart
// 역할: 베타 핵심 화면의 작은 화면, 큰 글씨, 접근성, 생명주기 회귀를 검증한다.

// 클래스명: _AccessibilityScheduleControl
// 역할: 접근성 레이아웃 검증에 사용할 긴 약 이름의 복약 일정을 제공한다.
class _AccessibilityScheduleControl extends CheckSchedule {
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
class _EmptyNotificationControl extends SetNotification {
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// 클래스명: _AccessibilityHealthRecommendationControl
// 역할: 외부 통신 없이 큰 글씨 건강 추천 화면에 긴 안내 문구를 제공한다.
class _AccessibilityHealthRecommendationControl
    extends CheckHealthRecommendation {
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

void main() {
  group('베타 접근성 레이아웃 회귀', () {
    const viewportCases = [
      (size: Size(320, 568), textScale: 1.6),
      (size: Size(360, 640), textScale: 2.0),
      (size: Size(412, 915), textScale: 2.0),
    ];

    for (final viewportCase in viewportCases) {
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
                  ({
                    required fontSizeOption,
                    required readingSpeedOption,
                    required language,
                  }) async => _synchronizedSettingResult(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('글씨크기'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, '저장하기').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

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
                ({
                  required fontSizeOption,
                  required readingSpeedOption,
                  required language,
                }) async => _synchronizedSettingResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('뒤로가기'), findsOneWidget);
      expect(find.bySemanticsLabel('저장하기'), findsOneWidget);
      expect(find.bySemanticsLabel('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

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
                ({
                  required fontSizeOption,
                  required readingSpeedOption,
                  required language,
                }) async => _synchronizedSettingResult(),
          ),
        ),
      );
      await tester.pumpAndSettle();
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

    for (final viewportCase in const [
      (size: Size(320, 568), textScale: 1.3),
      (size: Size(360, 640), textScale: 2.0),
    ]) {
      testWidgets('홈 화면은 ${viewportCase.size.width.toInt()} 너비와 '
          '${viewportCase.textScale}배 글씨에서도 모든 기능을 스크롤해 표시한다', (tester) async {
        await _setViewport(tester, viewportCase.size);

        await tester.pumpWidget(
          _scaledMaterialApp(
            textScale: viewportCase.textScale,
            home: InputPrescriptionUI(
              statusMessage: '',
              userSetting: const UserSetting(fontSize: 20),
              onPrescriptionScanRequested: () {},
              onPrescriptionGalleryRequested: () {},
              onPillIdentificationRequested: () {},
              onTodayScheduleRequested: () {},
              onSavedMedicationRequested: () {},
              onPatientCaregiverLinkRequested: () {},
              onUserSettingRequested: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('MedBuddy'), findsOneWidget);
        expect(find.text('오늘의 복약 일정'), findsOneWidget);
        expect(find.text('약 정보 촬영하기'), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(find.text('환자/보호자 연동'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

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
            onBackRequested: () {},
            onAnalysisRequested: () {},
            onMedicationScheduleChanged: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('prescription-analyze-button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ocr-edit-0')), findsOneWidget);
      expect(
        find.byKey(const Key('prescription-analyze-button')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

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
            statusMessageProvider: () => '',
            savingMedicationIndex: null,
            completedMedicationSaveIndexes: const {},
            isAllMedicationSaving: false,
            onCloseRequested: () {},
            onAllMedicationSaveRequested: () async => true,
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

    testWidgets('촬영 작업 선택지는 작은 화면과 2배 글씨에서도 스크롤된다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('보호자 알림 설정은 작은 화면과 2배 글씨에서도 저장 버튼에 접근한다', (tester) async {
      await _setViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        _scaledMaterialApp(
          textScale: 2,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
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

// 함수명: _setViewport
// 함수역할:
// - 각 테스트에 실제 소형·일반 휴대폰과 비슷한 논리 화면 크기를 적용한다.
// 반환값:
// - 비동기 화면 크기 설정 완료 상태
Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

// 함수명: _scaledMaterialApp
// 함수역할:
// - 운영체제 접근성 글자 배율을 적용한 테스트용 앱을 구성한다.
// 반환값:
// - 지정한 화면을 포함하는 MaterialApp
Widget _scaledMaterialApp({required double textScale, required Widget home}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}

UserSettingSaveResult _synchronizedSettingResult() {
  return const UserSettingSaveResult(
    setting: UserSetting(),
    synchronizedWithServer: true,
  );
}
