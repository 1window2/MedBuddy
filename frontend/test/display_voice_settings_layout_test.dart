// 파일명: display_voice_settings_layout_test.dart
// 역할: 공통 목록형 화면·음성 설정의 선택, 취소, 저장과 접근성 동작을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

// 함수이름: main
// 함수역할: 표시·홈·음성 설정의 초안 저장, 선택 취소, 재생 중지와 크기별 접근성을 검증하는 사례를 등록한다.
// 매개변수: 없음.
// 반환값: 없음. 화면/음성 설정 회귀 테스트 등록.
void main() {
  for (final language in ['ko', 'en']) {
    for (final widgetSupported in [false, true]) {
      // 함수이름: testWidgets: '표시 방식과 홈 화면을 구분하고 음성 미리보기를 마지막에 둔다 $language $widgetSupported'
      // 함수역할: 한국어/영어와 위젯 지원 여부별로 표시 방식·홈 선택·음성 미리보기 행의 위치를 비교한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 행은 지정 순서로 겹치지 않고 홈 위젯 추가는 지원할 때만 보이며 예외가 없다.
      testWidgets(
        '표시 방식과 홈 화면을 구분하고 음성 미리보기를 마지막에 둔다 $language $widgetSupported',
        (tester) async {
          final originalPlatform = DoseHomeWidget.platform;
          DoseHomeWidget.platform = _WidgetPlatform(widgetSupported);
          addTearDown(() => DoseHomeWidget.platform = originalPlatform);
          await _pumpSettings(tester, setting: UserSetting(language: language));
          final keys = [
            'fontSizeSelector',
            'languageSelector',
            'timeFormatSelector',
            'homeScheduleSourceSelector',
            if (widgetSupported) 'addDoseHomeWidget',
            'readingSpeedSelector',
            'settingsVoicePreviewButton',
          ];
          for (var index = 1; index < keys.length; index++) {
            expect(
              tester.getBottomLeft(find.byKey(ValueKey(keys[index - 1]))).dy,
              lessThanOrEqualTo(
                tester.getTopLeft(find.byKey(ValueKey(keys[index]))).dy,
              ),
            );
          }
          expect(
            find.byKey(const ValueKey('addDoseHomeWidget')),
            widgetSupported ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // 함수이름: testWidgets: '값 선택은 굵은 글씨와 초록색 선택 배경으로 통일한다'
  // 함수역할: 각 표시 설정 선택창을 열어 라디오 라벨·현재 선택 배경·글씨 크기를 검사한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 굵기·선택색이 공통 규칙을 따르고 글씨 크기 선택지는 14·17·23으로 표시된다.
  testWidgets('값 선택은 굵은 글씨와 초록색 선택 배경으로 통일한다', (tester) async {
    await _pumpSettings(tester);
    for (final entry in [
      ('homeScheduleSource', 'self'),
      ('fontSize', 'medium'),
      ('readingSpeed', 'medium'),
      ('language', 'ko'),
      ('timeFormat', '24h'),
    ]) {
      await _tap(tester, '${entry.$1}Selector');
      final options = tester.widgetList<RadioListTile<String>>(
        find.byType(RadioListTile<String>),
      );
      expect(options, isNotEmpty);
      for (final option in options) {
        final label = option.title! as KeepWordsText;
        expect(label.style!.fontWeight, FontWeight.w700);
        expect(option.selected, option.value == entry.$2);
        expect(option.activeColor, MedBuddyColors.primary);
        expect(
          label.style!.color,
          option.selected
              ? MedBuddyColors.primaryDark
              : MedBuddyColors.textStrong,
        );
        expect(option.selectedTileColor, MedBuddyColors.successSurface);
      }
      if (entry.$1 == 'fontSize') {
        expect(
          options.map(
            (option) => (option.title! as KeepWordsText).style!.fontSize,
          ),
          [14, 17, 23],
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });

  // 함수이름: testWidgets: '화면과 음성 선택을 함께 저장하며 복약 설정을 유지한다'
  // 함수역할: 복약 알림·공개 범위·아침 시각을 가진 초안에서 크기·속도·시간 형식·언어만 바꾸어 저장 후 이탈한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 저장은 한 번이고 네 표시 값은 바뀌되 복약 설정은 그대로 유지되며 재진입 표기도 일치한다.
  testWidgets('화면과 음성 선택을 함께 저장하며 복약 설정을 유지한다', (tester) async {
    final saves = <UserSetting>[];
    await _pumpSettings(
      tester,
      setting: const UserSetting(
        medicationNotificationsEnabled: false,
        notificationDetailMode: 'type_only',
        defaultMorningTime: '09:15',
      ),
      onSave: saves.add,
    );
    await _choose(tester, 'fontSize', 'large');
    await _choose(tester, 'readingSpeed', 'fast');
    await _choose(tester, 'timeFormat', '12h');
    await _choose(tester, 'language', 'en');
    expect(saves, isEmpty);
    expect(find.text('Display & Voice'), findsOneWidget);
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-save-and-leave');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('AM/PM'), findsOneWidget);
    expect(saves, hasLength(1));
    expect(saves.single.fontSize, 20);
    expect(saves.single.readingSpeed, 1.2);
    expect(saves.single.language, 'en');
    expect(saves.single.languageMode, 'en');
    expect(saves.single.timeFormat, '12h');
    expect(saves.single.medicationNotificationsEnabled, isFalse);
    expect(saves.single.notificationDetailMode, 'type_only');
    expect(saves.single.defaultMorningTime, '09:15');
  });

  // 함수이름: testWidgets: '모든 표시 선택창은 취소 시 원래 값을 유지한다'
  // 함수역할: 각 표시 선택창을 뒤로 닫거나 현재 값으로 재선택한 뒤 저장한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 선택창을 닫는 동안 저장하지 않고 원래 선택 값이 최종 저장에도 유지된다.
  testWidgets('모든 표시 선택창은 취소 시 원래 값을 유지한다', (tester) async {
    final saves = <UserSetting>[];
    await _pumpSettings(tester, onSave: saves.add);
    for (final entry in [
      ('fontSize', 'medium'),
      ('readingSpeed', 'medium'),
      ('language', 'ko'),
      ('timeFormat', '24h'),
    ]) {
      await _tap(tester, '${entry.$1}Selector');
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        entry.$2,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _choose(tester, entry.$1, entry.$2);
      expect(find.byType(RadioGroup<String>), findsNothing);
    }
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saves.single.fontSizeOption, 'medium');
    expect(saves.single.readingSpeedOption, 'medium');
    expect(saves.single.languageMode, 'ko');
    expect(saves.single.timeFormat, '24h');
  });

  for (final locale in ['ko', 'en']) {
    // 함수이름: testWidgets: '기기 언어를 선택하면 해당 언어로 미리 표시한다 $locale'
    // 함수역할: 기기 언어를 ko/en으로 고정한 뒤 언어 선택에서 system을 고르고 저장한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 즉시 기기 언어로 표시되며 system 모드와 해석된 언어가 함께 저장된다.
    testWidgets('기기 언어를 선택하면 해당 언어로 미리 표시한다 $locale', (tester) async {
      tester.platformDispatcher.localeTestValue = Locale(locale);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final saves = <UserSetting>[];
      await _pumpSettings(tester, onSave: saves.add);
      await _choose(tester, 'language', 'system');
      expect(
        find.text(locale == 'en' ? 'Use device language' : '기기 설정 따르기'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, locale == 'en' ? 'Save' : '저장하기'),
      );
      await tester.pumpAndSettle();
      expect(saves.single.languageMode, 'system');
      expect(saves.single.language, locale);
    });
  }

  // 함수이름: testWidgets: '음성 재생 중 속도 변경과 뒤로가기가 기존 중지 동작을 유지한다'
  // 함수역할: 음성 미리보기 재생 중 읽기 속도를 바꾸고 다시 재생한 뒤 설정에서 이탈한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 속도 변경·이탈마다 중지하고 다음 재생에만 slow가 적용되며 재진입은 정지 상태이다.
  testWidgets('음성 재생 중 속도 변경과 뒤로가기가 기존 중지 동작을 유지한다', (tester) async {
    var stops = 0;
    final spoken = <UserSetting>[];
    await _pumpSettings(
      tester,
      speaker: (text, setting, {onComplete}) async {
        spoken.add(setting);
      },
      stopper: () async {
        stops++;
      },
    );
    await _tap(tester, 'settingsVoicePreviewButton');
    expect(find.text('듣기 중지'), findsOneWidget);
    await _choose(tester, 'readingSpeed', 'slow');
    expect(stops, 1);
    expect(find.text('음성으로 들어보기'), findsOneWidget);
    await _tap(tester, 'settingsVoicePreviewButton');
    expect(spoken.last.readingSpeedOption, 'slow');
    await _tap(tester, 'settingsBackButton');
    expect(stops, 2);
    await _tap(tester, 'settings-save-and-leave');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('음성으로 들어보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['ko', 'en']) {
        // 함수이름: testWidgets: '화면·음성 목록과 선택창이 잘리지 않는다 $width $scale $language'
        // 함수역할: 화면 너비·글씨 배율·언어 조합별로 설정 행, 모든 라디오 선택지, 음성 미리보기와 저장 버튼까지 스크롤한다.
        // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
        // 반환값: 행은 48px 이상이며 모든 대상이 터치 가능하고 배치 예외가 없다.
        testWidgets('화면·음성 목록과 선택창이 잘리지 않는다 $width $scale $language', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpSettings(
            tester,
            width: width,
            setting: UserSetting(
              fontSize: 20,
              language: language,
              languageMode: 'system',
            ),
          );
          for (final entry in [
            ('homeScheduleSource', 'self'),
            ('fontSize', 'large'),
            ('language', 'system'),
            ('timeFormat', '24h'),
            ('readingSpeed', 'medium'),
          ]) {
            final row = find.byKey(ValueKey('${entry.$1}Selector'));
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(tester.getRect(row).height, greaterThanOrEqualTo(48));
            expect(row.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(row);
            await tester.pumpAndSettle();
            final options = find.byType(RadioListTile<String>);
            for (var index = 0; index < options.evaluate().length; index++) {
              await tester.ensureVisible(options.at(index));
              await tester.pumpAndSettle();
              expect(options.at(index).hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }
          final preview = find.byKey(
            const ValueKey('settingsVoicePreviewButton'),
          );
          await tester.ensureVisible(preview);
          await tester.pumpAndSettle();
          expect(preview.hitTestable(), findsOneWidget);
          expect(
            find
                .widgetWithText(
                  FilledButton,
                  language == 'en' ? 'Save' : '저장하기',
                )
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

// 클래스명: _WidgetPlatform
// 역할: 기기 위젯 지원 여부만 제공하는 플랫폼 대역.
// 주요 책임: 실제 홈 위젯 추가 없이 지원/미지원 메뉴 배치를 전환한다.
// 속성: supported (bool): 테스트할 플랫폼 지원 여부.
class _WidgetPlatform extends DoseHomeWidgetPlatform {
  @override
  final bool supported;

  // 함수이름: _WidgetPlatform
  // 함수역할: 홈 위젯 지원 여부를 고정한다.
  // 매개변수: supported (bool): 지원 메뉴 표시 조건.
  // 반환값: 새 _WidgetPlatform.
  const _WidgetPlatform(this.supported);
}

// 함수이름: _tap
// 함수역할: 키에 해당하는 항목을 보이게 한 뒤 누른다. 매개변수: tester·key. 반환값: 전환 완료.
Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

// 함수이름: _choose
// 함수역할: 설정 행의 선택창을 열어 지정한 저장 값을 선택한다.
// 매개변수: tester (WidgetTester): 화면 제어; preference (String): 설정 항목 키; value (String): 선택할 저장 값.
// 반환값: 선택값의 초안 반영과 프레임 안정화 완료.
Future<void> _choose(
  WidgetTester tester,
  String preference,
  String value,
) async {
  await _tap(tester, '${preference}Selector');
  await _tap(tester, '$preference-$value');
}

// 함수이름: _pumpSettings
// 함수역할: 기기 화면 크기·인증 정리를 등록하고 저장·음성 대역을 연결한 화면/음성 설정을 연다.
// 매개변수: tester (WidgetTester): 화면 제어; width (double): 화면 너비; setting (UserSetting): 초기값; onSave (ValueChanged<UserSetting>?): 저장 관찰; speaker (SettingPreviewSpeaker?)/stopper (SettingPreviewStopper?): 재생·중지 대역.
// 반환값: 화면/음성 구역 진입 완료.
Future<void> _pumpSettings(
  WidgetTester tester, {
  double width = 411,
  UserSetting setting = const UserSetting(),
  ValueChanged<UserSetting>? onSave,
  SettingPreviewSpeaker? speaker,
  SettingPreviewStopper? stopper,
}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = AuthenticationControl.development();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      home: ManageUserSettingUI(
        initialSetting: setting,
        authenticationControl: auth,
        previewSpeaker: speaker ?? (text, setting, {onComplete}) async {},
        previewStopper: stopper ?? () async {},
        // 저장 결과만 반환하고 실제 계정 설정은 변경하지 않는다.
        onExtendedSettingSaveRequested: (draft) async {
          onSave?.call(draft);
          return UserSettingSaveResult(
            setting: draft,
            synchronizedWithServer: true,
          );
        },
      ),
    ),
  );
  await _tap(tester, 'settingsDisplayAndVoiceMenu');
}
