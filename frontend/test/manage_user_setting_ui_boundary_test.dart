// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 설정의 실시간 미리보기, 저장과 음성 안내 상호작용을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 환경설정 저장 중복 방지와 실패 복구 동작을 검증한다.

void main() {
  testWidgets('설정 홈에서 계정 인사와 세 설정 영역을 구분해 표시한다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onSignOutRequested: () async {},
          onDeleteAccountRequested: () async {},
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) async => _saveResult(),
        ),
      ),
    );

    expect(find.text('환경설정'), findsOneWidget);
    expect(find.text('사용자님, 안녕하세요'), findsOneWidget);
    expect(find.text('로컬 데모 계정'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingsLaboratoryMenu')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settingsAccountMenu')), findsOneWidget);
    expect(find.text('중간 · 중간 · 한국어'), findsOneWidget);
    expect(find.text('사용 중인 실험 기능 없음'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsNothing);

    await _openDisplayAndVoice(tester);
    expect(find.text('글씨크기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.text('환경설정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('뒤로가기 버튼은 설정 내용을 스크롤해도 같은 위치에 고정된다', (tester) async {
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

    final backButton = find.byKey(const ValueKey('settingsBackButton'));
    final initialPosition = tester.getTopLeft(backButton);

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(backButton), initialPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English를 선택하면 설정 화면 전체와 저장 언어가 함께 바뀐다', (tester) async {
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

    await _openDisplayAndVoice(tester);
    expect(find.text('추후 업데이트 예정'), findsNothing);
    final englishButton = find.ancestor(
      of: find.text('English'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(englishButton).onTap, isNotNull);

    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('Text Size'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedLanguage, 'en');
    expect(find.text('Text Size'), findsOneWidget);
  });

  testWidgets('기존 영어 설정은 영어로 열리고 한국어로 전환할 수 있다', (tester) async {
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

    await _openDisplayAndVoice(tester);
    expect(find.text('Text Size'), findsOneWidget);
    expect(find.text('글씨크기'), findsNothing);

    await tester.ensureVisible(find.text('한국어'));
    await tester.tap(find.text('한국어'));
    await tester.pump();

    expect(find.text('글씨크기'), findsOneWidget);
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

    await _openDisplayAndVoice(tester);
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

    await _openDisplayAndVoice(tester);
    await tester.ensureVisible(find.text('빠르게'));
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
    expect(find.text('음성 미리보기를 재생하지 못했습니다.'), findsNothing);
  });

  testWidgets('사용자가 음성 미리보기를 중지하면 취소 오류를 안내하지 않는다', (tester) async {
    final playback = Completer<void>();
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          previewSpeaker: (text, setting, {onComplete}) => playback.future,
          previewStopper: () async {
            if (!playback.isCompleted) {
              playback.completeError(StateError('playback cancelled'));
            }
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

    await _openDisplayAndVoice(tester);
    await tester.ensureVisible(find.text('음성으로 들어보기'));
    await tester.tap(find.text('음성으로 들어보기'));
    await tester.pump();
    expect(find.text('듣기 중지'), findsOneWidget);

    await tester.tap(find.text('듣기 중지'));
    await tester.pumpAndSettle();

    expect(find.text('음성으로 들어보기'), findsOneWidget);
    expect(find.text('음성 미리보기를 재생하지 못했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
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

    await _openDisplayAndVoice(tester);
    await tester.tap(find.text('크게'));
    await tester.pump();
    final previewText = tester.widget<Text>(
      find.text('아스피린 100mg을 하루 3회 식후 30분에 복용하세요.'),
    );

    expect(previewText.style?.fontSize, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글씨 크기를 선택하면 저장 전에도 설정 화면 전체 배율이 바뀐다', (tester) async {
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

    await _openDisplayAndVoice(tester);
    double currentScale() {
      final titleContext = tester.element(find.text('글씨크기'));
      return MediaQuery.textScalerOf(titleContext).scale(16) / 16;
    }

    expect(currentScale(), 1.0);
    await tester.tap(find.text('크게'));
    await tester.pump();
    expect(currentScale(), 1.30);

    await tester.ensureVisible(find.text('작게'));
    await tester.tap(find.text('작게'));
    await tester.pump();
    expect(currentScale(), 0.92);
    expect(tester.takeException(), isNull);
  });

  testWidgets('설정을 저장해도 환경설정 화면에 그대로 머문다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageUserSettingUI(
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
              ),
              child: const Text('설정 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    await _openDisplayAndVoice(tester);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('글씨크기'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
    expect(find.text('설정 열기'), findsNothing);
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

    await _openDisplayAndVoice(tester);
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

    await _openDisplayAndVoice(tester);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('실험실에서 근처 운영 약국 노출 여부를 저장한다', (tester) async {
    bool? savedLabSetting;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onNearbyPharmacyLabSettingSaveRequested: (enabled) async {
            savedLabSetting = enabled;
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

    await _openLaboratory(tester);
    await tester.ensureVisible(find.text('근처 운영 약국'));
    await tester.tap(find.byKey(const ValueKey('nearbyPharmacyLabSwitch')));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '저장하기'));
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(savedLabSetting, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('실험실에서 복약 대화 노출 여부를 저장한다', (tester) async {
    bool? savedLabSetting;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onLinkedMedicationChatLabSettingSaveRequested: (enabled) async {
            savedLabSetting = enabled;
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

    await _openLaboratory(tester);
    await tester.ensureVisible(find.text('복약 대화'));
    await tester.tap(
      find.byKey(const ValueKey('linkedMedicationChatLabSwitch')),
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '저장하기'));
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(savedLabSetting, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('계정 삭제 성공 후 빈 화면이 아니라 루트 화면으로 돌아간다', (tester) async {
    var deletionCount = 0;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageUserSettingUI(
                    initialSetting: const UserSetting(),
                    authenticationControl: authenticationControl,
                    onSettingSaveRequested:
                        ({
                          required fontSizeOption,
                          required readingSpeedOption,
                          required language,
                        }) async => _saveResult(),
                    onDeleteAccountRequested: () async {
                      deletionCount += 1;
                    },
                  ),
                ),
              ),
              child: const Text('설정 열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    await _openAccount(tester);
    await tester.ensureVisible(find.text('계정 데이터 삭제'));
    await tester.tap(find.text('계정 데이터 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(deletionCount, 1);
    expect(find.text('설정 열기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDisplayAndVoice(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')));
  await tester.pumpAndSettle();
}

Future<void> _openLaboratory(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settingsLaboratoryMenu')));
  await tester.pumpAndSettle();
}

Future<void> _openAccount(WidgetTester tester) async {
  final accountMenu = find.byKey(const ValueKey('settingsAccountMenu'));
  await tester.ensureVisible(accountMenu);
  await tester.tap(accountMenu);
  await tester.pumpAndSettle();
}

UserSettingSaveResult _saveResult({bool synchronizedWithServer = true}) {
  return UserSettingSaveResult(
    setting: const UserSetting(),
    synchronizedWithServer: synchronizedWithServer,
  );
}
