import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
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
                  }) async {},
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
                }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('닫기'), findsOneWidget);
      expect(find.bySemanticsLabel('저장하기'), findsOneWidget);
      expect(find.bySemanticsLabel('English. 추후 업데이트 예정'), findsOneWidget);
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
                }) async {},
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
