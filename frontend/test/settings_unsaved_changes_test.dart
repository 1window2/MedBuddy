// File Name: settings_unsaved_changes_test.dart
// Role: Exercises settings drafts across discard, save-and-leave, system back and pending-save failure.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/set_notification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수역할: 사용자 의도와 실제 저장 결과에 따른 종료 동작을 검증한다.
// 설정 초안의 한 필드를 바꾸는 방법: 설정 영역 키, 값을 바꾸는 조작, 저장 내용에서 달라져야 하는 JSON 값.
typedef _FieldEdit =
    (String, Future<void> Function(WidgetTester), Map<String, Object>);

// Function Name: main
// Description: Registers dirty-state, navigation and draft-field regression cases with injectable save outcomes.
// Parameters: None.
// Returns: None; registers the settings navigation suite.
void main() {
  // Function Name: testWidgets: '홈 일정 선택은 저장·변경 취소를 따르며 내 일정이 기본이다'
  // Description: Changes home schedule source from its default, first discards it and then saves it while leaving.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: The source returns to personal after discard without a save, then persists patients and displays the linked-patient choice.
  testWidgets('홈 일정 선택은 저장·변경 취소를 따르며 내 일정이 기본이다', (tester) async {
    UserSetting? saved;
    await _pump(tester, (setting) async {
      saved = setting;
      return UserSettingSaveResult(
        setting: setting,
        synchronizedWithServer: true,
      );
    });
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('내 일정'), findsOneWidget);
    await _tap(tester, 'homeScheduleSourceSelector');
    await _tap(tester, 'homeScheduleSource-patients');
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-discard-changes');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('내 일정'), findsOneWidget);
    expect(saved, isNull);
    await _tap(tester, 'homeScheduleSourceSelector');
    await _tap(tester, 'homeScheduleSource-patients');
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-save-and-leave');
    expect(saved!.homeScheduleSource, 'patients');
    await _tap(tester, 'settingsDisplayAndVoiceMenu');
    expect(find.text('연동된 환자'), findsOneWidget);
  });

  // 함수이름: testWidgets: '계속 편집과 변경 취소는 저장하지 않으며 시스템 뒤로가기도 확인한다'
  // 함수역할: 채팅 알림 초안을 바꾸고 시스템 뒤로가기에서 계속 편집과 변경 취소를 차례로 선택한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 저장 없이 초안은 취소 전까지 유지되고 취소 후 원래 값으로 복원되며 깨끗한 상태에서는 확인창 없이 이전 경로로 돌아간다.
  testWidgets('계속 편집과 변경 취소는 저장하지 않으며 시스템 뒤로가기도 확인한다', (tester) async {
    var saves = 0;
    await _pump(tester, (setting) async {
      saves++;
      return UserSettingSaveResult(
        setting: setting,
        synchronizedWithServer: true,
      );
    });
    await _edit(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
    await _tap(tester, 'settings-keep-editing');
    expect(_chatEnabled(tester), isFalse);
    await _tap(tester, 'settingsBackButton');
    await _tap(tester, 'settings-discard-changes');
    expect(find.text('환경설정'), findsOneWidget);
    await _tap(tester, 'settingsMedicationAndNotificationsMenu');
    expect(_chatEnabled(tester), isTrue);
    expect(saves, 0);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    await _tap(tester, 'settingsBackButton');
    expect(find.text('Previous screen'), findsOneWidget);
  });

  for (final synchronized in [true, false]) {
    // 함수이름: testWidgets: '저장 후 이탈은 저장된 값을 기준으로 다시 비교한다: $synchronized'
    // 함수역할: 서버 동기화 성공·기기 전용 저장 각각에서 채팅 알림을 저장하고 설정을 다시 연다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 저장한 false가 새 비교 기준이 되어 재진입 후 변경 없이 나갈 때 확인창이 나타나지 않는다.
    testWidgets('저장 후 이탈은 저장된 값을 기준으로 다시 비교한다: $synchronized', (tester) async {
      UserSetting? saved;
      await _pump(tester, (setting) async {
        saved = setting;
        return UserSettingSaveResult(
          setting: setting,
          synchronizedWithServer: synchronized,
        );
      });
      await _edit(tester);
      await _tap(tester, 'settingsBackButton');
      await _tap(tester, 'settings-save-and-leave');
      expect(saved!.chatNotificationsEnabled, isFalse);
      expect(find.text('환경설정'), findsOneWidget);
      await _tap(tester, 'settingsMedicationAndNotificationsMenu');
      expect(_chatEnabled(tester), isFalse);
      await _tap(tester, 'settingsBackButton');
      expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    });
  }

  // 함수이름: testWidgets: '저장 중 뒤로가기는 중복 저장하지 않고 실패하면 편집을 유지한다'
  // 함수역할: 저장 후 이탈 요청을 대기시킨 채 시스템 뒤로가기를 누른 뒤 저장 예외를 완료한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 저장은 한 번뿐이고 실패 시 편집값과 화면이 유지되어 다음 이탈에 미저장 확인을 다시 요구한다.
  testWidgets('저장 중 뒤로가기는 중복 저장하지 않고 실패하면 편집을 유지한다', (tester) async {
    final gate = Completer<UserSettingSaveResult>();
    var saves = 0;
    await _pump(tester, (setting) {
      saves++;
      return gate.future;
    });
    await _edit(tester);
    await _tap(tester, 'settingsBackButton');
    await tester.tap(find.byKey(const Key('settings-save-and-leave')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(saves, 1);
    gate.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('복약 및 알림'), findsOneWidget);
    expect(_chatEnabled(tester), isFalse);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
  });

  // 설정 초안의 열네 필드를 하나씩 바꿔, 각 필드가 미저장 판정·저장 내용·변경 취소에 모두 포함되는지 확인한다.
  // 각 항목: 설정 영역 키, 값을 바꾸는 조작, 저장 내용에서 달라져야 하는 JSON 값.
  final fieldEdits = <String, _FieldEdit>{
    'fontSize': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'fontSize', 'large'),
      {'font_size': 20},
    ),
    'readingSpeed': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'readingSpeed', 'fast'),
      {'reading_speed': 1.2},
    ),
    'language': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'language', 'en'),
      {'language': 'en', 'language_mode': 'en'},
    ),
    'languageMode': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'language', 'system'),
      {'language_mode': 'system'},
    ),
    'timeFormat': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'timeFormat', '12h'),
      {'time_format': '12h'},
    ),
    'homeScheduleSource': (
      'settingsDisplayAndVoiceMenu',
      (tester) => _choose(tester, 'homeScheduleSource', 'patients'),
      {'home_schedule_source': 'patients'},
    ),
    'medicationNotificationsEnabled': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _tap(tester, 'medicationNotificationsSwitch'),
      {'medication_notifications_enabled': false},
    ),
    'caregiverNotificationsEnabled': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _tap(tester, 'caregiverNotificationsSwitch'),
      {'caregiver_notifications_enabled': false},
    ),
    'chatNotificationsEnabled': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _tap(tester, 'chatNotificationsSwitch'),
      {'chat_notifications_enabled': false},
    ),
    'notificationDetailMode': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _choose(tester, 'notificationPrivacy', 'type_only'),
      {'notification_detail_mode': 'type_only'},
    ),
    'defaultMorningTime': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _pickDefaultTime(tester, 'morning', 9, 10),
      {'default_morning_time': '09:10'},
    ),
    'defaultLunchTime': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _pickDefaultTime(tester, 'lunch', 13, 20),
      {'default_lunch_time': '13:20'},
    ),
    'defaultEveningTime': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _pickDefaultTime(tester, 'evening', 19, 30),
      {'default_evening_time': '19:30'},
    ),
    'defaultBedtime': (
      'settingsMedicationAndNotificationsMenu',
      (tester) => _pickDefaultTime(tester, 'bedtime', 23, 40),
      {'default_bedtime': '23:40'},
    ),
  };
  for (final field in fieldEdits.entries) {
    // Function Name: testWidgets: '설정 초안 필드는 미저장 판정·저장·변경 취소에 포함된다: ${field.key}'
    // Description: For each draft field, discards one edit and then saves the same change against the original settings snapshot.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: Discard performs no save; saving produces exactly the expected field delta once and clears dirty state on reentry.
    testWidgets('설정 초안 필드는 미저장 판정·저장·변경 취소에 포함된다: ${field.key}', (
      tester,
    ) async {
      // 기기 언어를 한국어로 고정해 "기기 설정 따르기"가 언어 모드만 바꾸게 한다.
      tester.platformDispatcher.localeTestValue = const Locale('ko');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final (section, edit, changed) = field.value;
      final initial = const UserSetting().toJson();
      final saves = <UserSetting>[];
      await _pump(tester, (setting) async {
        saves.add(setting);
        return UserSettingSaveResult(
          setting: setting,
          synchronizedWithServer: true,
        );
      });

      // 변경 → 미저장 확인 → 변경 취소: 저장하지 않고 원래 값으로 돌아간다.
      await _tap(tester, section);
      await edit(tester);
      await _tap(tester, 'settingsBackButton');
      expect(find.byKey(const Key('unsaved-settings-dialog')), findsOneWidget);
      await _tap(tester, 'settings-discard-changes');
      expect(saves, isEmpty);
      await _tap(tester, section);
      await _tap(tester, 'settingsBackButton');
      expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);

      // 다시 변경 → 저장: 바꾼 값만 달라진 설정 전체가 한 번 전달된다.
      await _tap(tester, section);
      await edit(tester);
      await _tap(tester, 'settingsBackButton');
      await _tap(tester, 'settings-save-and-leave');
      expect(saves, hasLength(1));
      expect(saves.single.toJson(), {...initial, ...changed});

      // 저장한 값이 새 기준이 되어 다시 나갈 때 확인하지 않는다.
      await _tap(tester, section);
      await _tap(tester, 'settingsBackButton');
      expect(find.byKey(const Key('unsaved-settings-dialog')), findsNothing);
    });
  }

  // 함수이름: testWidgets: '두 배 글씨에서도 종료 확인의 세 선택지를 사용할 수 있다'
  // 함수역할: 320×640 화면과 2배 글씨에서 초안을 바꾸고 종료 확인창을 연다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 저장 후 이탈 선택지가 존재하고 레이아웃 예외가 없다. 다른 두 버튼의 직접 탭은 이 사례에서 검사하지 않는다.
  testWidgets('두 배 글씨에서도 종료 확인의 세 선택지를 사용할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      (setting) async =>
          UserSettingSaveResult(setting: setting, synchronizedWithServer: true),
    );
    await _edit(tester);
    await _tap(tester, 'settingsBackButton');
    expect(find.byKey(const Key('settings-save-and-leave')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 함수이름: _pump
// 함수역할: 실제 이전 경로와 저장 대역·무동작 음성 대역을 가진 설정 화면을 열고 인증 자원 정리를 등록한다.
// 매개변수: tester (WidgetTester): 화면 제어; saver (ExtendedUserSettingSaver): 저장 결과/실패 대역.
// 반환값: 화면 진입과 프레임 안정화 완료.
Future<void> _pump(WidgetTester tester, ExtendedUserSettingSaver saver) async {
  final auth = AuthenticationControl.development();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MaterialApp(
      initialRoute: '/settings',
      routes: {
        '/': (_) => const Scaffold(body: Text('Previous screen')),
        '/settings': (_) => ManageUserSettingUI(
          initialSetting: const UserSetting(),
          authenticationControl: auth,
          previewSpeaker: (text, setting, {onComplete}) async {},
          previewStopper: () async {},
          onExtendedSettingSaveRequested: saver,
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: _edit
// 함수역할: 복약 및 알림 화면에서 채팅 알림 스위치를 눌러 미저장 초안을 만든다.
// 매개변수: tester (WidgetTester): 설정 화면 제어.
// 반환값: 초안 변경과 화면 안정화 완료.
Future<void> _edit(WidgetTester tester) async {
  await _tap(tester, 'settingsMedicationAndNotificationsMenu');
  await _tap(tester, 'chatNotificationsSwitch');
}

// 함수이름: _tap
// 함수역할: 키로 대상을 찾아 화면 안으로 스크롤한 뒤 탭하고 전환이 끝나기를 기다린다.
// 매개변수: tester (WidgetTester): 화면 제어; key (String): 대상 ValueKey 값.
// 반환값: 탭과 프레임 안정화 완료.
Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// Function Name: _choose
// Description: Opens a preference selector and chooses the keyed value through the shared sheet.
// Parameters: tester (WidgetTester): UI driver; preferenceKey (String): preference identity; value (String): stored option value.
// Returns: Future<void> completing after selection settles.
Future<void> _choose(
  WidgetTester tester,
  String preferenceKey,
  String value,
) async {
  await _tap(tester, '${preferenceKey}Selector');
  await _tap(tester, '$preferenceKey-$value');
}

// Function Name: _pickDefaultTime
// Description: Opens a default dose-time picker and returns the supplied time through its route.
// Parameters: tester (WidgetTester): UI driver; slotKey (String): dose slot; hour/minute (int): selected time.
// Returns: Future<void> completing after the picker closes.
Future<void> _pickDefaultTime(
  WidgetTester tester,
  String slotKey,
  int hour,
  int minute,
) async {
  await _tap(tester, 'defaultMedicationTime-$slotKey');
  final picker = find.byType(SetNotificationUI);
  Navigator.of(
    tester.element(picker),
  ).pop(TimeOfDay(hour: hour, minute: minute));
  await tester.pumpAndSettle();
}

// 함수이름: _chatEnabled
// 함수역할: 채팅 알림 스위치의 현재 초안 값을 읽는다.
// 매개변수: tester (WidgetTester): 스위치 조회 대상.
// 반환값: bool: 스위치가 켜져 있는지 여부.
bool _chatEnabled(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('chatNotificationsSwitch')))
    .value;
