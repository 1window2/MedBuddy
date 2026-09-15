// 파일명: display_voice_settings_layout_test.dart
// 역할: 공통 목록형 화면·음성 설정의 선택, 취소, 저장과 접근성 동작을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: main
// 함수역할: 초안 편집과 음성 제어, 좁은 화면·큰 글씨 회귀 사례를 등록한다.
// 매개변수·반환값: 없음.
void main() {
  // 선택창의 굵은 글씨와 현재 값 강조가 모든 표시 설정에 동일하게 적용된다.
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
        final label = option.title! as Text;
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
          options.map((option) => (option.title! as Text).style!.fontSize),
          [14, 17, 23],
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });

  // 네 표시 설정은 최종 저장 시 함께 전달하고 복약 설정은 그대로 유지한다.
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

  // 각 선택창은 현재 값을 표시하고 뒤로 닫으면 초안·저장 상태를 바꾸지 않는다.
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
    // 기기 언어 선택은 system 모드와 실제 해석된 언어를 모두 저장한다.
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

  // 속도 변경과 화면 이탈은 재생을 멈추며 다음 재생에만 새 속도를 적용한다.
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
        // 좁은 화면·큰 글씨에서도 모든 행과 선택지, 미리보기 및 저장에 접근한다.
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
// 함수역할: 설정 행의 선택창에서 값을 확정한다. 매개변수: tester·항목 키·값. 반환값: 초안 반영 완료.
Future<void> _choose(
  WidgetTester tester,
  String preference,
  String value,
) async {
  await _tap(tester, '${preference}Selector');
  await _tap(tester, '$preference-$value');
}

// 함수이름: _pumpSettings
// 함수역할: 실제 저장·음성 출력 없이 화면 및 음성 설정을 연다.
// 매개변수: 화면 도구·너비·초기 설정과 저장·재생 대역. 반환값: 설정 화면 진입 완료.
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
        onSettingSaveRequested:
            ({
              required fontSizeOption,
              required readingSpeedOption,
              required language,
            }) async => UserSettingSaveResult(
              setting: setting,
              synchronizedWithServer: true,
            ),
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
