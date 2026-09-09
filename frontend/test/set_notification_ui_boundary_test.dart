// File Name: set_notification_ui_boundary_test.dart
// Role: Regression coverage for alarm-wheel selection, numeric validation, cancellation, and
//   accessible dialogs.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';


// 함수이름: main
// 함수역할:
// - 알림 휠 선택, 숫자 검증, 취소와 접근성 대화상자 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 알림 팝업이 시간 휠에서 선택한 시각을 반환하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('alarm popup returns the time selected by the wheel', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Function Name: builder callback
          // Description:
          // - Build the test route or launch button for medication alarm time selection using the supplied
          //   context.
          // Parameters:
          // - context (BuildContext): Widget context used for inherited settings or navigation.
          // Returns:
          // - The route widget or dialog-launching button.
          builder: (context) => ElevatedButton(
            // Function Name: onPressed callback
            // Description:
            // - Open medication alarm time selection and capture the returned selection.
            // Parameters:
            // - None.
            // Returns:
            // - Completion after capturing the dialog result.
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final hourPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('notification-hour-wheel')),
    );
    final minutePicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('notification-minute-wheel')),
    );

    hourPicker.onSelectedItemChanged?.call(21);
    minutePicker.onSelectedItemChanged?.call(37);
    await tester.pump();
    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pumpAndSettle();

    expect(selectedTime, isNotNull);
    expect(selectedTime!.hour, 21);
    expect(selectedTime!.minute, 37);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 시와 분을 숫자로 직접 입력하고 선택 결과에 반영할 수 있는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('selected hour and minute accept direct numeric input', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 알림 시각 선택 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => ElevatedButton(
            // 함수이름: onPressed 콜백
            // 함수역할:
            // - 복약 알림 시각 선택 화면을 열고 선택 결과를 기록한다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 대화상자 선택 결과 기록 완료.
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'ko',
                slotTitle: '아침',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-hour-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '17',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-minute-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '45',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-time-confirm')));
    await tester.pumpAndSettle();

    expect(selectedTime, const TimeOfDay(hour: 17, minute: 45));
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 시·분 허용 범위를 벗어난 직접 입력을 거부하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('direct input rejects values outside the valid range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 알림 시각 선택 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => ElevatedButton(
            // 함수이름: onPressed 콜백
            // 함수역할:
            // - 복약 알림 시각 선택 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 없음; 대화상자가 열린다.
            onPressed: () {
              SetNotificationUI.showNotificationPopup(
                context,
                language: 'ko',
                slotTitle: '아침',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-hour-direct-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notification-direct-time-field')),
      '29',
    );
    await tester.tap(find.byKey(const Key('notification-direct-time-confirm')));
    await tester.pump();

    expect(find.textContaining('0부터 23 사이'), findsOneWidget);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 시간 휠 대화상자를 취소하면 시각 대신 null을 반환하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('alarm popup returns null when the wheel dialog is closed', (
    tester,
  ) async {
    TimeOfDay? selectedTime;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // Function Name: builder callback
          // Description:
          // - Build the test route or launch button for medication alarm time selection using the supplied
          //   context.
          // Parameters:
          // - context (BuildContext): Widget context used for inherited settings or navigation.
          // Returns:
          // - The route widget or dialog-launching button.
          builder: (context) => ElevatedButton(
            // Function Name: onPressed callback
            // Description:
            // - Open medication alarm time selection and capture the returned selection.
            // Parameters:
            // - None.
            // Returns:
            // - Completion after capturing the dialog result.
            onPressed: () async {
              selectedTime = await SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-time-close')));
    await tester.pumpAndSettle();

    expect(selectedTime, isNull);
    expect(find.byType(SetNotificationUI), findsNothing);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기기 어두운 테마에서도 알림 시간 휠이 보이는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('alarm wheel stays visible with a dark device theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          // Function Name: builder callback
          // Description:
          // - Build the test route or launch button for medication alarm time selection using the supplied
          //   context.
          // Parameters:
          // - context (BuildContext): Widget context used for inherited settings or navigation.
          // Returns:
          // - The route widget or dialog-launching button.
          builder: (context) => ElevatedButton(
            // Function Name: onPressed callback
            // Description:
            // - Open medication alarm time selection and allow the test to interact with the displayed route.
            // Parameters:
            // - None.
            // Returns:
            // - No value; the dialog is opened.
            onPressed: () {
              SetNotificationUI.showNotificationPopup(
                context,
                language: 'en',
                slotTitle: 'Morning',
                initialTime: const TimeOfDay(hour: 8, minute: 0),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final pickerFinder = find.byKey(const Key('notification-hour-wheel'));
    final picker = tester.widget<CupertinoPicker>(pickerFinder);
    final pickerTheme = CupertinoTheme.of(tester.element(pickerFinder));
    final selectedHourText = tester.widget<Text>(find.text('08').first);

    expect(picker.backgroundColor, Colors.transparent);
    expect(pickerTheme.brightness, Brightness.light);
    expect(selectedHourText.style?.color, MedBuddyColors.textStrong);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 알림 팝업은 작은 화면과 2배 글자에서도 시간 휠을 스크롤한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('알림 팝업은 작은 화면과 2배 글자에서도 시간 휠을 스크롤한다', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // 함수이름: builder 콜백
        // 함수역할:
        // - 기존 하위 화면에 2배 글씨를 적용해 접근성 배치를 검사한다.
        // 매개변수:
        // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
        // - child (Widget?): 화면 설정을 덮어쓸 기존 하위 위젯.
        // 반환값:
        // - 접근성 설정을 덮어쓴 MediaQuery 하위 트리.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          // 함수이름: builder 콜백
          // 함수역할:
          // - 복약 알림 시각 선택 화면이나 실행 버튼을 주어진 컨텍스트 아래에 구성한다.
          // 매개변수:
          // - context (BuildContext): 상속된 설정 또는 화면 이동에 사용할 위젯 컨텍스트.
          // 반환값:
          // - 테스트 경로 위젯 또는 대화상자 실행 버튼.
          builder: (context) => ElevatedButton(
            // 함수이름: onPressed 콜백
            // 함수역할:
            // - 복약 알림 시각 선택 화면을 열고 표시된 경로와 상호작용할 수 있게 한다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 화면 이동 또는 대화상자 결과 Future.
            onPressed: () => SetNotificationUI.showNotificationPopup(
              context,
              language: 'ko',
              slotTitle: '취침 전 복약 시간',
              initialTime: const TimeOfDay(hour: 22, minute: 0),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-hour-wheel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
