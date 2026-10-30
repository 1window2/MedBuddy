// 파일명: feature_search_test.dart
// 역할: 일상 표현의 검색 순위, 무관한 입력, 접근성, 설정 바로가기의 무변경 동작을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/feature_search_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/find_app_feature_control.dart';
import 'package:medbuddy_frontend/entities/feature_search_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: main
// 함수역할: 문장·동의어·띄어쓰기·언어와 화면 이동의 회귀 사례를 등록한다.
void main() {
  final expressions = <String, AppFeature>{
    '폰 글씨가 작아서 크게 보고 싶어': AppFeature.fontSize,
    '잘 안 보여요': AppFeature.fontSize,
    '글시 크게': AppFeature.fontSize,
    '알림이 안 와요': AppFeature.notifications,
    '알람이 안울려요': AppFeature.notifications,
    '그 약 알림 좀 꺼줘': AppFeature.notificationReception,
    '채팅 알림 끄기': AppFeature.notificationReception,
    '잠금화면에 약 이름 숨기고 싶어': AppFeature.notificationPrivacy,
    '새 약을 추가하고 싶어': AppFeature.manualMedication,
    '처방전 없이 직접 입력': AppFeature.manualMedication,
    '처방전 사진 찍어서 등록': AppFeature.prescription,
    '이거 무슨 약이야': AppFeature.pillIdentification,
    '약 모양으로 알아보기': AppFeature.pillIdentification,
    '약 먹었어요': AppFeature.schedule,
    '오늘 먹을 약': AppFeature.schedule,
    '필요할 때 먹는 약': AppFeature.asNeeded,
    '등록한 약 삭제': AppFeature.medicationCabinet,
    '처방 바꾸고 싶어': AppFeature.medicationCabinet,
    '어제 먹은 약 기록': AppFeature.medicationHistory,
    '먹은 기록 보내기': AppFeature.historySharing,
    '먹은 약 기록을 가족한테 보내고 싶어요': AppFeature.historySharing,
    '먹은 기록을 엑셀로': AppFeature.historySharing,
    ' CSV ': AppFeature.historySharing,
    '엄마를 보호자로 연결': AppFeature.caregiverLink,
    '초대 코드': AppFeature.caregiverLink,
    '엄마가 약 먹었는지 확인하고 싶어': AppFeature.caregiverSchedule,
    '환자 기록 확인': AppFeature.caregiverSchedule,
    '가족한테 메시지 보내기': AppFeature.chat,
    '지금 문 연 약국': AppFeature.nearbyPharmacy,
    '근처 병원': AppFeature.nearbyHospital,
    '음식 추천': AppFeature.healthRecommendation,
    '받은 알림 확인': AppFeature.notificationInbox,
    '기본 복약 시간': AppFeature.defaultTimes,
    '영어로 바꾸기': AppFeature.language,
    '오전 오후 대신 24시간': AppFeature.timeFormat,
    '말이 너무 빨라 천천히 읽어줘': AppFeature.readingSpeed,
    '앱 안 열고 체크하고 싶어': AppFeature.homeWidget,
    '계정 삭제': AppFeature.account,
    '개인정보 어디로 보내': AppFeature.dataUse,
    'MAKE TEXT BIGGER!': AppFeature.fontSize,
    'send my medication records to family': AppFeature.historySharing,
    'connect my family': AppFeature.caregiverLink,
    'patient history': AppFeature.caregiverSchedule,
    'turn off alerts': AppFeature.notificationReception,
    'turn off notifications': AppFeature.notificationReception,
    'disable notifications': AppFeature.notificationReception,
    'notifications not working': AppFeature.notifications,
    'test notification': AppFeature.notifications,
    'what is this pill': AppFeature.pillIdentification,
    'did i take my medicine': AppFeature.schedule,
    '어제 약 먹었나': AppFeature.medicationHistory,
    '어제 약 먹었어?': AppFeature.medicationHistory,
  };
  for (final expression in expressions.entries) {
    test('일상 표현을 관련 기능으로 정렬: ${expression.key}', () {
      expect(
        FindAppFeature.search(expression.key).first.feature,
        expression.value,
      );
    });
  }
  test('빈 검색·무관한 질문은 임의 기능으로 연결하지 않는다', () {
    for (final query in ['', '   ', '???', '점심메뉴짜장면', '무릎이 아파요', 'zxqvw']) {
      expect(FindAppFeature.search(query), isEmpty, reason: query);
    }
  });
  test('정확한 이름과 구두점·공백 변형은 같은 목적지를 찾는다', () {
    expect(
      FindAppFeature.entries.map((e) => e.feature).toSet().length,
      AppFeature.values.length,
    );
    for (final entry in FindAppFeature.entries) {
      expect(
        FindAppFeature.search(entry.ko).first.feature,
        entry.feature,
        reason: entry.ko,
      );
      expect(
        FindAppFeature.search(entry.en).first.feature,
        entry.feature,
        reason: entry.en,
      );
    }
    expect(
      FindAppFeature.search('글 씨 크 게!!').first.feature,
      AppFeature.fontSize,
    );
    expect(FindAppFeature.search('위젯', widgetSupported: false), isEmpty);
  });

  for (final english in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('검색·초기화·선택과 좁은 화면 큰 글씨: $english/$scale', (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppFeature? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: MedBuddyTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('open'),
                  onPressed: () async {
                    selected = await Navigator.push<AppFeature>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FeatureSearchUI(isEnglish: english),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            english
                ? 'Find a feature and go straight to it.'
                : '원하는 기능을 검색하고 바로 이동합니다.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('feature-manualMedication')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('featureSearchInput')),
          'zxqvw',
        );
        await tester.pump();
        expect(
          find.text(english ? 'No matching features' : '검색 결과가 없어요'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('featureSearchClear')));
        await tester.pump();
        expect(
          find.byKey(const Key('feature-manualMedication')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('featureSearchInput')),
          english ? 'text bigger' : '글씨 크게',
        );
        await tester.pump();
        expect(selected, isNull);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('feature-fontSize')));
        await tester.pumpAndSettle();
        expect(selected, AppFeature.fontSize);
        expect(find.text('open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 설정 항목으로 바로 들어와도 자동 변경·저장하지 않으며 뒤로가기는 기존 규칙을 따른다.
  for (final target in {
    UserSettingDestination.fontSize: 'fontSizeSelector',
    UserSettingDestination.language: 'languageSelector',
    UserSettingDestination.readingSpeed: 'readingSpeedSelector',
    UserSettingDestination.homeScheduleSource: 'homeScheduleSourceSelector',
    UserSettingDestination.notificationPrivacy: 'notificationPrivacySelector',
    UserSettingDestination.defaultTimes: 'defaultMedicationTime-morning',
  }.entries) {
    testWidgets('설정 바로가기는 ${target.key.name}을 표시하되 저장하지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthenticationControl.development();
      addTearDown(auth.dispose);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: MedBuddyTheme.light(),
          home: ManageUserSettingUI(
            initialSetting: const UserSetting(),
            initialDestination: target.key,
            authenticationControl: auth,
            previewSpeaker: (text, setting, {onComplete}) async {},
            previewStopper: () async {},
            onExtendedSettingSaveRequested: (setting) async {
              saves++;
              return UserSettingSaveResult(
                setting: setting,
                synchronizedWithServer: true,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(target.value)).hitTestable(), findsOneWidget);
      expect(saves, 0);
      await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
        findsOneWidget,
      );
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
