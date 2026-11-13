// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 설정의 실시간 미리보기, 저장과 음성 안내 상호작용을 검증한다. 환경설정 저장 중복 방지와 실패 복구 동작을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/manage_account_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

// 함수이름: main
// 함수역할:
// - 설정 탐색, 언어, 글씨 크기, 음성 미리보기와 저장 피드백 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  for (final language in ['ko', 'en']) {
    for (final width in [320.0, 430.0]) {
      // 함수이름: testWidgets: '설정 홈과 계정의 인사 영역 위치·크기가 같다 $language $width'
      // 함수역할: 언어·화면 너비별로 설정 홈과 계정 화면의 인사 패널·아이콘·헤더 간격을 비교한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 패널 크기·좌우 위치·아이콘 상대 위치·헤더 간격이 같고 예외가 없다.
      testWidgets('설정 홈과 계정의 인사 영역 위치·크기가 같다 $language $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = AuthenticationControl.development();
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ManageUserSettingUI(
              initialSetting: UserSetting(language: language),
              authenticationControl: auth,
              onExtendedSettingSaveRequested: (setting) async => _saveResult(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('settingsAccountWelcomePanel'));
        final icon = find.descendant(
          of: panel,
          matching: find.byIcon(Icons.person_outline_rounded),
        );
        final homeRect = tester.getRect(panel);
        final homeIconOffset = tester.getTopLeft(icon) - homeRect.topLeft;
        final homeGap =
            homeRect.top -
            tester.getBottomLeft(find.byType(MedBuddyPageHeader)).dy;
        await _openAccount(tester);
        final accountRect = tester.getRect(panel);
        expect(accountRect.left, homeRect.left);
        expect(accountRect.size, homeRect.size);
        expect(tester.getTopLeft(icon) - accountRect.topLeft, homeIconOffset);
        // 제목의 줄 수가 달라도 헤더 아래 간격과 인사 영역 내부 배치는 같다.
        expect(
          accountRect.top -
              tester.getBottomLeft(find.byType(MedBuddyPageHeader)).dy,
          homeGap,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in ['ko', 'en']) {
    for (final hasMfa in [false, true]) {
      // 함수이름: testWidgets: '계정은 보안과 데이터 안내 뒤에 로그아웃과 삭제를 배치한다 $language $hasMfa'
      // 함수역할: 언어와 문자 인증 지원 여부별로 계정의 보안·데이터 안내·로그아웃·삭제 순서를 검사한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 보안이 있으면 데이터 안내보다 앞서고 로그아웃과 삭제는 그 뒤에 순서대로 위치한다.
      testWidgets('계정은 보안과 데이터 안내 뒤에 로그아웃과 삭제를 배치한다 $language $hasMfa', (
        tester,
      ) async {
        final auth = _AccountOrderAuthentication(hasMfa);
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ManageUserSettingUI(
              initialSetting: UserSetting(language: language),
              authenticationControl: auth,
              onExtendedSettingSaveRequested: (setting) async => _saveResult(),
              onSignOutRequested: () async {},
              onDeleteAccountRequested: () async {},
            ),
          ),
        );
        await _openAccount(tester);
        final data = find.byKey(const ValueKey('settingsDataUseMenu'));
        final signOut = find.widgetWithIcon(OutlinedButton, Icons.logout);
        final delete = find.widgetWithIcon(
          OutlinedButton,
          Icons.delete_forever_outlined,
        );
        if (hasMfa) {
          expect(
            tester
                .getBottomLeft(
                  find.text(
                    language == 'en'
                        ? 'SMS two-step verification'
                        : '문자 2단계 인증',
                  ),
                )
                .dy,
            lessThan(tester.getTopLeft(data).dy),
          );
        }
        expect(
          tester.getBottomLeft(data).dy,
          lessThan(tester.getTopLeft(signOut).dy),
        );
        expect(
          tester.getBottomLeft(signOut).dy,
          lessThan(tester.getTopLeft(delete).dy),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Function Name: testWidgets: '문자 2단계 인증 영역과 창은 한국어로 표시하고 오류를 보여준다'
  // Description: Renders Korean SMS MFA test panels and requests a code using the development authentication control.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: Korean labels are shown without SMS text, and the unavailable-feature error appears inside the enrollment dialog.
  testWidgets('문자 2단계 인증 영역과 창은 한국어로 표시하고 오류를 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              buildSmsMfaSettingsPanelForTesting(
                enabled: false,
                available: true,
                language: 'ko',
              ),
              Expanded(
                child: buildSmsMfaEnrollmentDialogForTesting(
                  control: authenticationControl,
                  language: 'ko',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('문자 2단계 인증'), findsOneWidget);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.text('문자 인증 켜기'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('smsMfaError')), findsNothing);

    await tester.tap(find.text('인증번호 보내기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<KeepWordsText>(find.byKey(const ValueKey('smsMfaError')))
          .data,
      '현재 버전에서는 문자 인증을 사용할 수 없습니다.',
    );
    expect(find.text('취소'), findsOneWidget);
  });

  // Function Name: testWidgets: '설정 홈에서 계정 인사와 세 설정 영역을 구분해 표시한다'
  // Description: Opens settings with a development account, enters display/voice and returns home.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: The greeting and three active categories appear without laboratory or root-save controls, and navigation returns without exceptions.
  testWidgets('설정 홈에서 계정 인사와 세 설정 영역을 구분해 표시한다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          // 함수이름: onSignOutRequested 콜백
          // 함수역할:
          // - 인증 제공자 로그아웃 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - Future<void>; 부수 효과 없이 완료된다.
          onSignOutRequested: () async {},
          // 함수이름: onDeleteAccountRequested 콜백
          // 함수역할:
          // - 계정 삭제 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - Future<void>; 부수 효과 없이 완료된다.
          onDeleteAccountRequested: () async {},
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
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
    expect(find.byKey(const ValueKey('settingsLaboratoryMenu')), findsNothing);
    expect(
      find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settingsAccountMenu')), findsOneWidget);
    expect(find.text('중간 · 중간 · 한국어'), findsOneWidget);
    expect(find.text('사용 중인 실험 기능 없음'), findsNothing);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsNothing);

    await _openDisplayAndVoice(tester);
    expect(find.text('글자 크기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settingsBackButton')));
    await tester.pumpAndSettle();
    expect(find.text('환경설정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets: '뒤로가기 버튼은 설정 내용을 스크롤해도 같은 위치에 고정된다'
  // Description: Records the settings back-button position and scrolls content upward by 700 pixels.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: The back arrow stays at the same coordinates, no close icon replaces it and layout remains exception-free.
  testWidgets('뒤로가기 버튼은 설정 내용을 스크롤해도 같은 위치에 고정된다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
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

  // 함수이름: testWidgets: 'English를 선택하면 설정 화면 전체와 저장 언어가 함께 바뀐다'
  // 함수역할: 한국어 화면에서 언어를 영어로 고르고 저장 콜백이 받은 언어와 저장 뒤 화면을 검사한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 저장값은 en이고 Text Size가 저장 전후 모두 영어로 표시된다.
  testWidgets('English를 선택하면 설정 화면 전체와 저장 언어가 함께 바뀐다', (tester) async {
    String? savedLanguage;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 선택 언어를 기록하고 서버 동기화 성공 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async {
                savedLanguage = setting.language;
                return _saveResult();
              },
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    expect(find.text('추후 업데이트 예정'), findsNothing);
    await _selectSettingChoice(tester, 'language', 'en');
    expect(find.text('Text Size'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedLanguage, 'en');
    expect(find.text('Text Size'), findsOneWidget);
  });

  // Function Name: testWidgets: '기존 영어 설정은 영어로 열리고 한국어로 전환할 수 있다'
  // Description: Opens existing English settings, then selects Korean in the display section.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: Only the active language's text-size label is present before and after switching.
  testWidgets('기존 영어 설정은 영어로 열리고 한국어로 전환할 수 있다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(language: 'en'),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    expect(find.text('Text Size'), findsOneWidget);
    expect(find.text('글자 크기'), findsNothing);

    await _selectSettingChoice(tester, 'language', 'ko');

    expect(find.text('글자 크기'), findsOneWidget);
    expect(find.text('Text Size'), findsNothing);
  });
  // 함수이름: testWidgets: '환경설정 저장 실패 후 버튼을 복구하고 재시도를 허용한다'
  // 함수역할: 저장 응답을 대기시키고 중복 탭한 뒤 저장 예외를 완료한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 요청은 한 번이며 실패 안내 후 버튼이 다시 활성화되고 프레임 예외가 없다.
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
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 저장 시도를 기록하고 응답을 대기시켜 중복 요청 차단과 실패 후 재시도를 검사한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 테스트가 완료시키는 설정 저장 Future.
              (setting) {
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

  // 함수이름: testWidgets: '선택한 읽기 속도로 음성 미리보기를 재생하고 중지한다'
  // 함수역할: fast 속도로 예시를 재생하고 완료 콜백과 사용자 중지를 각각 실행한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 전달 문구·1.2 배속·재생/정지 라벨이 맞고 완료/중지 뒤 재생 오류를 표시하지 않는다.
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
          // 함수이름: previewSpeaker 콜백
          // 함수역할:
          // - 실제로 소리를 내지 않고 미리보기 문장·읽기 설정·완료 처리기를 기록한다.
          // 매개변수:
          // - text (String): 모의 재생에 전달한 음성 안내 문장.
          // - setting (UserSetting): 미리보기에 전달한 글씨 및 읽기 설정.
          // - onComplete (void Function()?): 모의 음성 재생 완료 시 선택적으로 호출할 처리기.
          // 반환값:
          // - Future<void>; 미리보기 인자 기록 완료.
          previewSpeaker: (text, setting, {onComplete}) async {
            spokenText = text;
            spokenSetting = setting;
            completionHandler = onComplete;
          },
          // 함수이름: previewStopper 콜백
          // 함수역할:
          // - 음성 미리보기 중지 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          previewStopper: () async {
            stopRequestCount += 1;
          },
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    await _selectSettingChoice(tester, 'readingSpeed', 'fast');
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

  // Function Name: testWidgets: '사용자가 음성 미리보기를 중지하면 취소 오류를 안내하지 않는다'
  // Description: Stops a pending preview whose stopper completes playback with a cancellation error.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: The play action is restored without failure feedback or an uncaught exception.
  testWidgets('사용자가 음성 미리보기를 중지하면 취소 오류를 안내하지 않는다', (tester) async {
    final playback = Completer<void>();
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          // 함수이름: previewSpeaker 콜백
          // 함수역할:
          // - 음성 미리보기 완료를 테스트가 결정하도록 재생 Future를 대기시킨다.
          // 매개변수:
          // - text (String): 모의 재생에 전달한 음성 안내 문장. 이 대역에서는 직접 사용하지 않는다.
          // - setting (UserSetting): 미리보기에 전달한 글씨 및 읽기 설정. 이 대역에서는 직접 사용하지 않는다.
          // - onComplete (void Function()?): 모의 음성 재생 완료 시 선택적으로 호출할 처리기. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - 테스트가 제어하는 재생 Future.
          previewSpeaker: (text, setting, {onComplete}) => playback.future,
          // 함수이름: previewStopper 콜백
          // 함수역할:
          // - 아직 진행 중인 미리보기에 취소 오류를 보내 사용자 중지를 재현한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - Future<void>; 대기 중 재생이 취소 오류로 완료된다.
          previewStopper: () async {
            if (!playback.isCompleted) {
              playback.completeError(StateError('playback cancelled'));
            }
          },
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
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

  // 함수이름: testWidgets: '큰 글씨 선택은 미리보기에서 확실한 크기 차이를 보여준다'
  // 함수역할: 글씨 크기를 large로 바꾼 뒤 예시 문장의 Text 스타일을 검사한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 미리보기 크기가 20이며 레이아웃 예외가 없다.
  testWidgets('큰 글씨 선택은 미리보기에서 확실한 크기 차이를 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    await _selectSettingChoice(tester, 'fontSize', 'large');
    final previewText = tester.widget<Text>(
      find.text('아스피린 100mg을 하루 3회 식후 30분에 복용하세요.'),
    );

    expect(previewText.style?.fontSize, 20);
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets: '글씨 크기를 선택하면 저장 전에도 설정 화면 전체 배율이 바뀐다'
  // Description: Changes text size from medium to large and small before saving and measures the title's inherited scale.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: The measured scale changes from 1.0 to 1.30 then 0.92 without exceptions.
  testWidgets('글씨 크기를 선택하면 저장 전에도 설정 화면 전체 배율이 바뀐다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    // Function Name: currentScale
    // Description: Measures the settings title's effective MediaQuery text scale against a 16-point reference.
    // Parameters: None.
    // Returns: double: scaled size divided by 16.
    double currentScale() {
      final titleContext = tester.element(find.text('글자 크기'));
      return MediaQuery.textScalerOf(titleContext).scale(16) / 16;
    }

    expect(currentScale(), 1.0);
    await _selectSettingChoice(tester, 'fontSize', 'large');
    expect(currentScale(), 1.30);

    await _selectSettingChoice(tester, 'fontSize', 'small');
    expect(currentScale(), 0.92);
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets: '설정을 저장해도 환경설정 화면에 그대로 머문다'
  // Description: Pushes settings from a root action and saves from the display/voice section.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: Settings and its save button remain visible; the root opener does not reappear.
  testWidgets('설정을 저장해도 환경설정 화면에 그대로 머문다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Function Name: builder callback
          // Description:
          // - Build the test route or launch button for user settings using the supplied context.
          // Parameters:
          // - context (BuildContext): Widget context used for inherited settings or navigation.
          // Returns:
          // - The route widget or dialog-launching button.
          builder: (context) => Scaffold(
            body: TextButton(
              // Function Name: onPressed callback
              // Description:
              // - Open user settings and allow the test to interact with the displayed route.
              // Parameters:
              // - None.
              // Returns:
              // - The navigation/dialog Future.
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  // Function Name: builder callback
                  // Description:
                  // - Build the test route or launch button for user settings using the supplied context.
                  // Parameters:
                  // - _ (BuildContext): Unused route build context.
                  // Returns:
                  // - The route widget or dialog-launching button.
                  builder: (_) => ManageUserSettingUI(
                    initialSetting: const UserSetting(),
                    authenticationControl: authenticationControl,
                    onExtendedSettingSaveRequested:
                        // 함수이름: onExtendedSettingSaveRequested 콜백
                        // 함수역할:
                        // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
                        // 매개변수:
                        // - setting (UserSetting): 화면에서 편집한 설정 전체.
                        // 반환값:
                        // - 서버 동기화 상태의 설정 저장 결과.
                        (setting) async => _saveResult(),
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

    expect(find.text('글자 크기'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
    expect(find.text('설정 열기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: '글씨 크기 선택 버튼은 각 선택지의 실제 크기를 비교해서 보여준다'
  // 함수역할: 글씨 크기 선택창의 세 라벨 스타일을 비교한 뒤 창을 닫는다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: small·medium·large가 각각 14·17·23으로 표시되고 예외가 없다.
  testWidgets('글씨 크기 선택 버튼은 각 선택지의 실제 크기를 비교해서 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    await tester.tap(find.byKey(const ValueKey('fontSizeSelector')));
    await tester.pumpAndSettle();
    // 함수이름: optionLabel
    // 함수역할: 선택창의 크기 값에 대응하는 라벨 Text를 찾아 실제 글씨 크기를 검사할 수 있게 한다.
    // 매개변수: value (String): small·medium·large 선택 키.
    // 반환값: 해당 선택지의 Text 위젯.
    Text optionLabel(String value) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('fontSize-$value')),
        matching: find.byType(Text),
      ),
    );
    expect(optionLabel('small').style?.fontSize, 14);
    expect(optionLabel('medium').style?.fontSize, 17);
    expect(optionLabel('large').style?.fontSize, 23);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: '서버 저장 실패 시 기기 전용 저장 상태를 안내한다'
  // 함수역할: 저장 대역이 synchronizedWithServer=false를 반환하도록 하고 저장 버튼을 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 기기 전용 저장과 재시도 안내가 표시되며 예외가 없다.
  testWidgets('서버 저장 실패 시 기기 전용 저장 상태를 안내한다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          onExtendedSettingSaveRequested:
              // 함수이름: onExtendedSettingSaveRequested 콜백
              // 함수역할:
              // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
              // 매개변수:
              // - setting (UserSetting): 화면에서 편집한 설정 전체.
              // 반환값:
              // - 서버 미동기화 상태의 설정 저장 결과.
              (setting) async => _saveResult(synchronizedWithServer: false),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('기기에만 저장했습니다. 서버 연결 후 다시 저장해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 실험실 제거 회귀 테스트
    // 함수역할: 큰 글씨와 두 언어에서 실험실 메뉴 없이 세 설정 분류를 제공한다.
    // 매개변수: tester: 위젯 도구. 반환값: 표시 및 메뉴 접근 검증 완료.
    testWidgets('설정에는 실험실 메뉴와 실험 스위치가 없다 $language', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final authenticationControl = AuthenticationControl.development();
      addTearDown(authenticationControl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ManageUserSettingUI(
            initialSetting: UserSetting.fromJson({
              'language': language,
              'font_size': 20,
              'multi_pill_identification_lab_enabled': false,
            }),
            authenticationControl: authenticationControl,
            // 함수이름: 설정 저장 대역
            // 함수역할: 실제 저장 없이 성공 결과를 반환한다.
            // 매개변수: setting은 편집한 설정 전체. 반환값: 저장 결과.
            onExtendedSettingSaveRequested: (setting) async => _saveResult(),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('settingsLaboratoryMenu')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('multiPillIdentificationLabSwitch')),
        findsNothing,
      );
      expect(find.byIcon(Icons.science_outlined), findsNothing);
      expect(find.text('실험실'), findsNothing);
      expect(find.text('Labs'), findsNothing);
      expect(
        find.byKey(const ValueKey('settingsMedicationAndNotificationsMenu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')),
        findsOneWidget,
      );
      final account = find.byKey(const ValueKey('settingsAccountMenu'));
      await tester.ensureVisible(account);
      await tester.pumpAndSettle();
      expect(account.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: testWidgets: '계정 삭제 성공 후 빈 화면이 아니라 루트 화면으로 돌아간다'
  // Description: Pushes settings above a root screen, confirms account deletion and counts the callback.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: Deletion runs once and returns to the root opener without a blank route or exception.
  testWidgets('계정 삭제 성공 후 빈 화면이 아니라 루트 화면으로 돌아간다', (tester) async {
    var deletionCount = 0;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Function Name: builder callback
          // Description:
          // - Build the test route or launch button for user settings using the supplied context.
          // Parameters:
          // - context (BuildContext): Widget context used for inherited settings or navigation.
          // Returns:
          // - The route widget or dialog-launching button.
          builder: (context) => Scaffold(
            body: TextButton(
              // Function Name: onPressed callback
              // Description:
              // - Open user settings and allow the test to interact with the displayed route.
              // Parameters:
              // - None.
              // Returns:
              // - The navigation/dialog Future.
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  // Function Name: builder callback
                  // Description:
                  // - Build the test route or launch button for user settings using the supplied context.
                  // Parameters:
                  // - _ (BuildContext): Unused route build context.
                  // Returns:
                  // - The route widget or dialog-launching button.
                  builder: (_) => ManageUserSettingUI(
                    initialSetting: const UserSetting(),
                    authenticationControl: authenticationControl,
                    onExtendedSettingSaveRequested:
                        // 함수이름: onExtendedSettingSaveRequested 콜백
                        // 함수역할:
                        // - 실제 저장 없이 지정한 서버 동기화 또는 기기 전용 저장 결과를 제공한다.
                        // 매개변수:
                        // - setting (UserSetting): 화면에서 편집한 설정 전체.
                        // 반환값:
                        // - 서버 동기화 상태의 설정 저장 결과.
                        (setting) async => _saveResult(),
                    // Function Name: onDeleteAccountRequested callback
                    // Description:
                    // - Record account deletion so the test can assert the action was dispatched.
                    // Parameters:
                    // - None.
                    // Returns:
                    // - No value; the callback completes after its recorded side effects.
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

  // 계정 삭제 실패는 실패 종류에 따라 현재 화면 언어의 안내로 보여야 한다.
  // 각 항목: 화면 언어, 삭제 콜백이 던지는 실패, 기대하는 안내 문구.
  final deletionFailures = <(String, Object Function(), String)>[
    (
      'ko',
      () => AuthenticationStateError(
        AuthenticationErrorCode.deletionRequiresRecentSignIn,
      ),
      '보안을 위해 로그아웃한 뒤 다시 로그인하고 계정을 삭제해 주세요.',
    ),
    (
      'en',
      () => AuthenticationStateError(
        AuthenticationErrorCode.deletionRequiresRecentSignIn,
      ),
      'For security, sign out and sign in again before deleting this account.',
    ),
    (
      'ko',
      () => AuthenticationStateError(AuthenticationErrorCode.network),
      '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
    ),
    (
      'ko',
      () => AccountDeletionFailure(AccountDeletionFailureReason.serverRejected),
      '계정 데이터를 삭제하지 못했습니다.',
    ),
    (
      'en',
      () => AccountDeletionFailure(AccountDeletionFailureReason.serverRejected),
      'Could not delete account data.',
    ),
    (
      'en',
      () => StateError('한 가지 언어만 가진 오류'),
      'Could not delete account data.',
    ),
    ('ko', () => Exception('transport'), '계정 데이터를 삭제하지 못했습니다.'),
  ];
  for (final (index, (language, failure, message))
      in deletionFailures.indexed) {
    // Function Name: testWidgets: '계정 삭제 실패를 화면 언어로 안내한다 #$index $language'
    // Description: For each language and typed deletion failure, injects the failure and confirms deletion.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: The expected localized snackbar appears and the delete action remains available on the account screen.
    testWidgets('계정 삭제 실패를 화면 언어로 안내한다 #$index $language', (tester) async {
      await _pumpForDeletion(tester, language, () async => throw failure());
      await _requestDeletion(tester, language);
      expect(find.widgetWithText(SnackBar, message), findsOneWidget);
      // 실패 뒤에도 설정 화면에 남아 다시 시도할 수 있다.
      expect(
        find.text(language == 'en' ? 'Delete account' : '계정 데이터 삭제'),
        findsOneWidget,
      );
    });
  }

  // Function Name: testWidgets: 'Google 재인증을 취소하면 계정 삭제 오류를 안내하지 않는다'
  // Description: Cancels Google reauthentication twice through the account-deletion callback.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: Cancellation produces no snackbar and a second deletion attempt is still accepted.
  testWidgets('Google 재인증을 취소하면 계정 삭제 오류를 안내하지 않는다', (tester) async {
    var attempts = 0;
    await _pumpForDeletion(tester, 'ko', () async {
      attempts += 1;
      throw AuthenticationStateError(
        AuthenticationErrorCode.googleSignInCanceled,
      );
    });
    await _requestDeletion(tester, 'ko');
    expect(find.byType(SnackBar), findsNothing);
    await _requestDeletion(tester, 'ko');
    expect(attempts, 2);
  });
}

// 클래스명: _AccountOrderAuthentication
// 역할: 계정 메뉴 순서 확인용 인증 대역.
// 주요 책임: 실제 인증 없이 문자 인증 지원과 고정 계정 표시를 제공하고 사용하지 않는 API는 기본 미구현 오류로 남긴다.
// 속성: phoneAuthenticationEnabled (bool): 보안 영역 노출 여부; 고정 접근자: Test 이름·시험 이메일·비게스트 상태.
class _AccountOrderAuthentication extends ChangeNotifier
    implements AuthenticationControl {
  @override
  final bool phoneAuthenticationEnabled;

  // 함수이름: _AccountOrderAuthentication
  // 함수역할: 문자 인증 보안 영역의 지원 여부를 고정한다.
  // 매개변수: phoneAuthenticationEnabled (bool): 문자 인증 영역 노출 조건.
  // 반환값: 새 _AccountOrderAuthentication.
  _AccountOrderAuthentication(this.phoneAuthenticationEnabled);

  // 함수이름: hasEnrolledSmsMfa
  // 함수역할: 문자 다중 인증이 등록되지 않은 계정을 재현한다.
  // 매개변수: 없음.
  // 반환값: bool: 항상 false.
  @override
  bool get hasEnrolledSmsMfa => false;
  // 함수이름: canEnrollSmsMfa
  // 함수역할: 실제 등록 동작 없이 계정 메뉴 순서만 검사하도록 등록 가능 여부를 끈다.
  // 매개변수: 없음.
  // 반환값: bool: 항상 false.
  @override
  bool get canEnrollSmsMfa => false;
  // 함수이름: isAnonymous
  // 함수역할: 로그인 계정의 메뉴 배치를 검사하도록 게스트 여부를 끈다.
  // 매개변수: 없음.
  // 반환값: bool: 항상 false.
  @override
  bool get isAnonymous => false;
  // 함수이름: signedInDisplayName
  // 함수역할: 계정 인사에 사용할 고정 시험 이름을 제공한다.
  // 매개변수: 없음.
  // 반환값: String?: Test.
  @override
  String? get signedInDisplayName => 'Test';
  // 함수이름: signedInEmail
  // 함수역할: 계정 상세에 사용할 고정 시험 이메일을 제공한다.
  // 매개변수: 없음.
  // 반환값: String?: test@example.com.
  @override
  String? get signedInEmail => 'test@example.com';
  // 함수이름: signedInPhoneNumber
  // 함수역할: 전화번호가 연결되지 않은 시험 계정을 재현한다.
  // 매개변수: 없음.
  // 반환값: String?: null.
  @override
  String? get signedInPhoneNumber => null;
  // 함수이름: noSuchMethod
  // 함수역할: 대역이 구현하지 않은 인증 API 호출을 기본 미구현 처리로 전달한다.
  // 매개변수: invocation (Invocation): 예상하지 않은 멤버 호출.
  // 반환값: 정상 반환 없음. 기본 noSuchMethod 오류를 발생시킨다.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Function Name: _pumpForDeletion
// Description: Builds settings with an explicit language and injectable account-deletion outcome, registering authentication cleanup.
// Parameters: tester (WidgetTester): UI driver; language (String): display and explicit language mode; onDelete (Future<void> Function()): deletion callback.
// Returns: Future<void> completing after the settings widget is mounted.
Future<void> _pumpForDeletion(
  WidgetTester tester,
  String language,
  Future<void> Function() onDelete,
) async {
  final authenticationControl = AuthenticationControl.development();
  addTearDown(authenticationControl.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ManageUserSettingUI(
        initialSetting: UserSetting(language: language, languageMode: language),
        authenticationControl: authenticationControl,
        onExtendedSettingSaveRequested: (setting) async => _saveResult(),
        onDeleteAccountRequested: onDelete,
      ),
    ),
  );
}

// Function Name: _requestDeletion
// Description: Opens account settings if needed, scrolls to deletion and confirms using labels in the chosen language.
// Parameters: tester (WidgetTester): UI driver; language (String): confirmation-label language.
// Returns: Future<void> completing after the deletion interaction settles.
Future<void> _requestDeletion(WidgetTester tester, String language) async {
  final english = language == 'en';
  if (find.text(english ? 'Delete account' : '계정 데이터 삭제').evaluate().isEmpty) {
    await _openAccount(tester);
  }
  final deleteAccount = find.text(english ? 'Delete account' : '계정 데이터 삭제');
  await tester.ensureVisible(deleteAccount);
  await tester.tap(deleteAccount);
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(FilledButton, english ? 'Delete' : '삭제'),
  );
  await tester.pumpAndSettle();
}

// 함수이름: _openDisplayAndVoice
// 함수역할:
// - 화면 및 음성 설정 메뉴를 열고 화면 전환을 기다린다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// 반환값:
// - 메뉴 전환 완료.
Future<void> _openDisplayAndVoice(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settingsDisplayAndVoiceMenu')));
  await tester.pumpAndSettle();
}

// 함수이름: _selectSettingChoice
// 함수역할: 현재 값 행을 열고 지정한 저장 값의 선택지를 화면에 드러내 확정한다.
// 매개변수: tester (WidgetTester): 화면 제어; preference (String): 설정 항목 키; value (String): 선택할 저장 값.
// 반환값: 선택과 미리보기 반영 완료.
Future<void> _selectSettingChoice(
  WidgetTester tester,
  String preference,
  String value,
) async {
  final selector = find.byKey(ValueKey('${preference}Selector'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('$preference-$value'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

// 함수이름: _openAccount
// 함수역할:
// - 계정 설정 메뉴까지 스크롤한 뒤 열고 전환을 기다린다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// 반환값:
// - 계정 화면 전환 완료.
Future<void> _openAccount(WidgetTester tester) async {
  final accountMenu = find.byKey(const ValueKey('settingsAccountMenu'));
  await tester.ensureVisible(accountMenu);
  await tester.tap(accountMenu);
  await tester.pumpAndSettle();
}

// 함수이름: _saveResult
// 함수역할:
// - 서버 동기화 여부를 선택한 기본 설정 저장 결과를 만든다.
// 매개변수:
// - synchronizedWithServer (bool): 저장 대역이 서버 동기화를 보고할지 여부.
// 반환값:
// - 지정 동기화 플래그와 기본 UserSetting을 가진 결과.
UserSettingSaveResult _saveResult({bool synchronizedWithServer = true}) {
  return UserSettingSaveResult(
    setting: const UserSetting(),
    synchronizedWithServer: synchronizedWithServer,
  );
}
