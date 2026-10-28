// 파일명: medication_search_setting_ui_test.dart
// 역할: 약품 검색 슬라이더의 초안·저장·접근성과 작은 화면 배치를 검증한다.
import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

final _slider = find.byKey(const ValueKey('medicationSearchModeSlider'));
Finder _label(String mode) =>
    find.byKey(ValueKey('medicationSearchMode-$mode'));

void main() {
  testWidgets('검색은 알림 수신 뒤에 놓이고 슬라이더와 라벨은 저장 전 초안만 바꾼다', (tester) async {
    final saved = <UserSetting>[];
    await _pumpSettings(
      tester,
      onSave: (setting) async {
        saved.add(setting);
        return UserSettingSaveResult(
          setting: setting,
          synchronizedWithServer: true,
        );
      },
    );
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('chatNotificationsSwitch')))
          .dy,
      lessThan(tester.getTopLeft(find.text('약품 검색')).dy),
    );
    expect(
      tester.getBottomLeft(_label('thorough')).dy,
      lessThan(tester.getTopLeft(find.text('기본 복약 시간')).dy),
    );
    final slider = tester.widget<Slider>(_slider);
    expect(slider.min, 0);
    expect(slider.max, 2);
    expect(slider.divisions, 2);
    expect(slider.value, 1);
    for (final (mode, value) in [
      ('fast', 0.0),
      ('balanced', 1.0),
      ('thorough', 2.0),
    ]) {
      await tester.tap(_label(mode));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(_slider).value, value);
      expect(saved, isEmpty);
    }
    await tester.drag(_slider, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(_slider).value, 0);
    await tester.drag(_slider, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(_slider).value, 2);
    expect(saved, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();
    expect(saved.single.medicationSearchMode, 'thorough');
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('검색 모드만 바꿔도 미저장 확인을 띄우고 취소하거나 원래 값으로 복귀한다', (tester) async {
    var saves = 0;
    await _pumpSettings(
      tester,
      onSave: (setting) async {
        saves++;
        return UserSettingSaveResult(
          setting: setting,
          synchronizedWithServer: true,
        );
      },
    );
    await tester.tap(_label('fast'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-discard-changes')));
    await tester.pumpAndSettle();
    await _openMedicationSettings(tester);
    expect(tester.widget<Slider>(_slider).value, 1);
    await tester.tap(_label('thorough'));
    await tester.pumpAndSettle();
    await tester.tap(_label('balanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 중에는 검색 슬라이더와 라벨을 잠근다', (tester) async {
    final save = Completer<UserSettingSaveResult>();
    UserSetting? saving;
    await _pumpSettings(
      tester,
      onSave: (setting) {
        saving = setting;
        return save.future;
      },
    );
    await tester.tap(_label('fast'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pump();
    expect(tester.widget<Slider>(_slider).onChanged, isNull);
    await tester.tap(_label('thorough'));
    await tester.pump();
    expect(tester.widget<Slider>(_slider).value, 0);
    save.complete(
      UserSettingSaveResult(setting: saving!, synchronizedWithServer: true),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(_slider).onChanged, isNotNull);
  });

  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320px와 큰 글씨에서 세 라벨과 접근성 동작을 유지한다 $language $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final semantics = tester.ensureSemantics();
        final saved = <UserSetting>[];
        await _pumpSettings(
          tester,
          language: language,
          onSave: (setting) async {
            saved.add(setting);
            return UserSettingSaveResult(
              setting: setting,
              synchronizedWithServer: true,
            );
          },
        );
        final title = language == 'en' ? 'Medication search' : '약품 검색';
        final labels = language == 'en'
            ? ['Fast', 'Balanced', 'Thorough']
            : ['속도 우선', '보통', '정확도 우선'];
        final sliderNode = tester
            .getSemantics(
              find.byKey(const ValueKey('medicationSearchModeSemantics')),
            )
            .getSemanticsData();
        expect(sliderNode.label, title);
        expect(sliderNode.value, labels[1]);
        expect(sliderNode.hasAction(SemanticsAction.increase), isTrue);
        expect(sliderNode.hasAction(SemanticsAction.decrease), isTrue);
        expect(sliderNode.increasedValue, labels[2]);
        expect(sliderNode.decreasedValue, labels[0]);
        final rects = <Rect>[];
        for (final (index, mode) in ['fast', 'balanced', 'thorough'].indexed) {
          final label = _label(mode);
          expect(label.hitTestable(), findsOneWidget);
          final rect = tester.getRect(label);
          rects.add(rect);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.height, greaterThanOrEqualTo(48));
          final node = tester.getSemantics(label);
          expect(node.label, '$title, ${labels[index]}');
          expect(node.flagsCollection.isButton, isTrue);
          expect(
            node.flagsCollection.isSelected,
            index == 1 ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
        expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
        semantics.dispose();
        await tester.tap(_label('thorough'));
        await tester.pumpAndSettle();
        expect(tester.getRect(_label('thorough')), rects[2]);
        expect(saved, isEmpty);
        await tester.tap(
          find.widgetWithText(FilledButton, language == 'en' ? 'Save' : '저장하기'),
        );
        await tester.pumpAndSettle();
        expect(saved.single.medicationSearchMode, 'thorough');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

// 함수역할: 실제 설정 화면을 열되 계정·저장·음성 동작은 테스트로 격리한다.
Future<void> _pumpSettings(
  WidgetTester tester, {
  String language = 'ko',
  required Future<UserSettingSaveResult> Function(UserSetting) onSave,
}) async {
  final auth = AuthenticationControl.development();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MedBuddyTheme.light(),
      home: ManageUserSettingUI(
        initialSetting: UserSetting(language: language, languageMode: language),
        authenticationControl: auth,
        previewSpeaker: (text, setting, {onComplete}) async {},
        onExtendedSettingSaveRequested: onSave,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _openMedicationSettings(tester);
}

Future<void> _openMedicationSettings(WidgetTester tester) async {
  final menu = find.byKey(
    const ValueKey('settingsMedicationAndNotificationsMenu'),
  );
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('medicationSearchSection')),
  );
  await tester.pumpAndSettle();
}
