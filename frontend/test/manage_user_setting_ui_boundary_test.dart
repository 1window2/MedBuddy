import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 환경설정 저장 중복 방지와 실패 복구 동작을 검증한다.

void main() {
  testWidgets('English 선택을 비활성화하고 한국어 설정을 유지한다', (tester) async {
    String? savedLanguage;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async {
                savedLanguage = language;
                return _saveResult();
              },
        ),
      ),
    );

    expect(find.text('추후 업데이트 예정'), findsOneWidget);
    final englishButton = find.ancestor(
      of: find.text('English'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(englishButton).onTap, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(savedLanguage, 'ko');
  });

  testWidgets('기존 영어 설정도 지원 중인 한국어 설정으로 연다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(language: 'en'),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(),
        ),
      ),
    );

    expect(find.text('글씨크기'), findsOneWidget);
    expect(find.text('추후 업데이트 예정'), findsOneWidget);
    expect(find.text('Text Size'), findsNothing);
  });

  testWidgets('환경설정 저장 실패 후 버튼을 복구하고 재시도를 허용한다', (tester) async {
    final saveRequest = Completer<UserSettingSaveResult>();
    var requestCount = 0;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) {
                requestCount += 1;
                return saveRequest.future;
              },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pump();
    expect(find.text('저장 중...'), findsOneWidget);
    expect(requestCount, 1);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(requestCount, 1);

    saveRequest.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('설정을 저장하지 못했습니다.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장하기'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택한 읽기 속도로 음성 미리보기를 재생하고 중지한다', (tester) async {
    UserSetting? spokenSetting;
    String? spokenText;
    void Function()? completionHandler;
    var stopRequestCount = 0;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          previewSpeaker: (text, setting, {onComplete}) async {
            spokenText = text;
            spokenSetting = setting;
            completionHandler = onComplete;
          },
          previewStopper: () async {
            stopRequestCount += 1;
          },
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(),
        ),
      ),
    );

    await tester.tap(find.text('빠르게'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('음성으로 들어보기'));
    await tester.tap(find.text('음성으로 들어보기'));
    await tester.pump();

    expect(spokenText, contains('아스피린'));
    expect(spokenSetting?.readingSpeed, 1.2);
    expect(find.text('듣기 중지'), findsOneWidget);

    completionHandler?.call();
    await tester.pump();
    expect(find.text('음성으로 들어보기'), findsOneWidget);

    await tester.tap(find.text('음성으로 들어보기'));
    await tester.pump();
    await tester.tap(find.text('듣기 중지'));
    await tester.pump();
    expect(stopRequestCount, greaterThanOrEqualTo(2));
    expect(find.text('음성으로 들어보기'), findsOneWidget);
  });

  testWidgets('큰 글씨 선택은 미리보기에서 확실한 크기 차이를 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(),
        ),
      ),
    );

    await tester.tap(find.text('크게'));
    await tester.pump();
    final previewText = tester.widget<Text>(
      find.text('아스피린 100mg을 하루 3회 식후 30분에 복용하세요.'),
    );

    expect(previewText.style?.fontSize, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글씨 크기 선택 버튼은 각 선택지의 실제 크기를 비교해서 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('작게')).style?.fontSize, 14);
    expect(tester.widget<Text>(find.text('중간').first).style?.fontSize, 17);
    expect(tester.widget<Text>(find.text('크게')).style?.fontSize, 23);
    expect(tester.takeException(), isNull);
  });

  testWidgets('서버 저장 실패 시 기기 전용 저장 상태를 안내한다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(synchronizedWithServer: false),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

UserSettingSaveResult _saveResult({bool synchronizedWithServer = true}) {
  return UserSettingSaveResult(
    setting: const UserSetting(),
    synchronizedWithServer: synchronizedWithServer,
  );
}
