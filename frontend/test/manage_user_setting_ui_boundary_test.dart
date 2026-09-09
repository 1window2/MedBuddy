// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 설정의 실시간 미리보기, 저장과 음성 안내 상호작용을 검증한다. 환경설정 저장 중복 방지와 실패 복구 동작을 검증한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';


// 함수이름: main
// 함수역할:
// - 설정 탐색, 언어, 글씨 크기, 음성 미리보기와 저장 피드백 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 설정 홈에서 계정 인사와 세 설정 영역을 구분해 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 뒤로가기 버튼은 설정 내용을 스크롤해도 같은 위치에 고정된다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('뒤로가기 버튼은 설정 내용을 스크롤해도 같은 위치에 고정된다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: English를 선택하면 설정 화면 전체와 저장 언어가 함께 바뀐다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
              // 함수이름: onSettingSaveRequested 콜백
              // 함수역할:
              // - 선택 언어를 기록하고 서버 동기화 성공 결과를 제공한다.
              // 매개변수:
              // - fontSizeOption (String): 선택한 앱 글씨 크기 옵션. 이 대역에서는 직접 사용하지 않는다.
              // - readingSpeedOption (String): 선택한 음성 읽기 속도 옵션. 이 대역에서는 직접 사용하지 않는다.
              // - language (String): 화면 문구 또는 알림 내용의 언어 코드.
              // 반환값:
              // - 서버 동기화 상태의 설정 저장 결과.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 기존 영어 설정은 영어로 열리고 한국어로 전환할 수 있다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('기존 영어 설정은 영어로 열리고 한국어로 전환할 수 있다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(language: 'en'),
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
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 환경설정 저장 실패 후 버튼을 복구하고 재시도를 허용한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
              // 함수이름: onSettingSaveRequested 콜백
              // 함수역할:
              // - 저장 시도를 기록하고 응답을 대기시켜 중복 요청 차단과 실패 후 재시도를 검사한다.
              // 매개변수:
              // - fontSizeOption (String): 선택한 앱 글씨 크기 옵션. 이 대역에서는 직접 사용하지 않는다.
              // - readingSpeedOption (String): 선택한 음성 읽기 속도 옵션. 이 대역에서는 직접 사용하지 않는다.
              // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
              // 반환값:
              // - 테스트가 완료시키는 설정 저장 Future.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 선택한 읽기 속도로 음성 미리보기를 재생하고 중지한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 사용자가 음성 미리보기를 중지하면 취소 오류를 안내하지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 큰 글씨 선택은 미리보기에서 확실한 크기 차이를 보여준다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('큰 글씨 선택은 미리보기에서 확실한 크기 차이를 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 글씨 크기를 선택하면 저장 전에도 설정 화면 전체 배율이 바뀐다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('글씨 크기를 선택하면 저장 전에도 설정 화면 전체 배율이 바뀐다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
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
              }) async => _saveResult(),
        ),
      ),
    );

    await _openDisplayAndVoice(tester);
    // 함수이름: currentScale
    // 함수역할:
    // - 설정 제목의 실제 MediaQuery 배율을 기준 글씨 16에 대해 측정한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 제목 위젯에 적용된 글씨 배율.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 설정을 저장해도 환경설정 화면에 그대로 머문다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 글씨 크기 선택 버튼은 각 선택지의 실제 크기를 비교해서 보여준다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('글씨 크기 선택 버튼은 각 선택지의 실제 크기를 비교해서 보여준다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 서버 저장 실패 시 기기 전용 저장 상태를 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('서버 저장 실패 시 기기 전용 저장 상태를 안내한다', (tester) async {
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
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
              // - 서버 미동기화 상태의 설정 저장 결과.
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 실험실에서 근처 운영 약국 노출 여부를 저장한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('실험실에서 근처 운영 약국 노출 여부를 저장한다', (tester) async {
    bool? savedLabSetting;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          // 함수이름: onNearbyPharmacyLabSettingSaveRequested 콜백
          // 함수역할:
          // - 근처 약국 실험 기능의 저장 요청 값을 기록한다.
          // 매개변수:
          // - enabled (bool): 선택한 실험 기능 활성 여부.
          // 반환값:
          // - Future<void>; 선택한 활성 여부 기록 완료.
          onNearbyPharmacyLabSettingSaveRequested: (enabled) async {
            savedLabSetting = enabled;
          },
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 실험실에서 복약 대화 노출 여부를 저장한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('실험실에서 복약 대화 노출 여부를 저장한다', (tester) async {
    bool? savedLabSetting;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          // 함수이름: onLinkedMedicationChatLabSettingSaveRequested 콜백
          // 함수역할:
          // - 복약 대화 실험 기능의 저장 요청 값을 기록한다.
          // 매개변수:
          // - enabled (bool): 선택한 실험 기능 활성 여부.
          // 반환값:
          // - Future<void>; 선택한 활성 여부 기록 완료.
          onLinkedMedicationChatLabSettingSaveRequested: (enabled) async {
            savedLabSetting = enabled;
          },
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

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 실험실에서 다중 알약 일괄 식별 노출 여부를 저장한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('실험실에서 다중 알약 일괄 식별 노출 여부를 저장한다', (tester) async {
    bool? savedLabSetting;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: authenticationControl,
          // 함수이름: onMultiPillIdentificationLabSettingSaveRequested 콜백
          // 함수역할:
          // - 다중 알약 식별 실험 기능의 저장 요청 값을 기록한다.
          // 매개변수:
          // - enabled (bool): 선택한 실험 기능 활성 여부.
          // 반환값:
          // - Future<void>; 선택한 활성 여부 기록 완료.
          onMultiPillIdentificationLabSettingSaveRequested: (enabled) async {
            savedLabSetting = enabled;
          },
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
              }) async => _saveResult(),
        ),
      ),
    );

    await _openLaboratory(tester);
    await tester.ensureVisible(find.text('다중 알약 일괄 식별'));
    await tester.tap(
      find.byKey(const ValueKey('multiPillIdentificationLabSwitch')),
    );
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '저장하기'));
    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pumpAndSettle();

    expect(savedLabSetting, isTrue);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 계정 삭제 성공 후 빈 화면이 아니라 루트 화면으로 돌아간다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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
                        }) async => _saveResult(),
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

// 함수이름: _openLaboratory
// 함수역할:
// - 실험실 설정 메뉴를 열고 화면 전환을 기다린다.
// 매개변수:
// - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
// 반환값:
// - 실험실 화면 전환 완료.
Future<void> _openLaboratory(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settingsLaboratoryMenu')));
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
