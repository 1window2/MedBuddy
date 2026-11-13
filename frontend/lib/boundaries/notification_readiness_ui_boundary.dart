// 파일명: notification_readiness_ui_boundary.dart
// 역할: 복약 및 알림 설정 안에서 기기 권한과 테스트 알림을 제공한다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/notification_readiness_control.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_preference_row.dart';
import '../widgets/medbuddy_setting_toggle.dart';
import '../widgets/keep_words_text.dart';

// 클래스명: NotificationDeviceSettings
// 역할: 기기 알림 권한과 테스트 알림 설정을 표시한다.
// 주요 책임: 제어기를 통해 운영체제 설정을 확인하고 필요한 권한 화면을 연다.
// 속성: control (NotificationReadinessControl): 기기 설정 제어기; isEnglish (bool): 표시 언어.
class NotificationDeviceSettings extends StatefulWidget {
  final NotificationReadinessControl control;
  final bool isEnglish;

  // 함수이름: NotificationDeviceSettings
  // 함수역할: 외부 소유 알림 설정 제어기와 표시 언어를 연결한다.
  // 매개변수: key (Key?): 위젯 키; control (NotificationReadinessControl): 제어기; isEnglish (bool): 영어 여부.
  // 반환값: 새 NotificationDeviceSettings.
  const NotificationDeviceSettings({
    super.key,
    required this.control,
    required this.isEnglish,
  });

  // 함수이름: createState
  // 함수역할: 앱 복귀와 설정 작업을 감시할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _NotificationDeviceSettingsState.
  @override
  State<NotificationDeviceSettings> createState() =>
      _NotificationDeviceSettingsState();
}

// Class Name: _NotificationDeviceSettingsState
// Role: Tracks operating-system permission checks and serialized settings actions.
// Responsibilities: Refreshes on resume and reports platform failures without pretending a permission changed.
// Attributes: _snapshot (NotificationReadinessSnapshot?): last permission result; _refreshing/_busy (bool): operation locks; _error (String?): action failure.
class _NotificationDeviceSettingsState extends State<NotificationDeviceSettings>
    with WidgetsBindingObserver {
  NotificationReadinessSnapshot? _snapshot;
  bool _refreshing = false;
  bool _busy = false;
  String? _error;

  // 함수이름: _text
  // 함수역할: 사용자 언어에 해당하는 설정 안내를 선택한다.
  // 매개변수: ko/en (String): 한국어·영어 문구.
  // 반환값: 선택한 문구.
  String _text(String ko, String en) => widget.isEnglish ? en : ko;

  // 함수이름: initState
  // 함수역할: 앱 복귀 감시를 등록하고 최초 권한 상태를 조회한다.
  // 매개변수: 없음.
  // 반환값: 없음. 조회는 비동기로 진행한다.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  // 함수이름: dispose
  // 함수역할: 앱 수명 감시를 해제한다. 외부에서 받은 제어기는 해제하지 않는다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 시스템 설정에서 복귀했고 별도 작업이 없으면 권한을 다시 확인한다.
  // 매개변수: state (AppLifecycleState): 새 앱 상태.
  // 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(_refresh());
    }
  }

  // 함수이름: _refresh
  // 함수역할: 중복 조회를 막고 최신 권한 결과를 표시한다. 조회 실패 시 상태를 알 수 없는 것으로 처리한다.
  // 매개변수: 없음.
  // 반환값: 조회 종료 후 완료되는 Future<void>; 화면 종료 후 상태를 갱신하지 않는다.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final snapshot = await widget.control.refresh();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) setState(() => _snapshot = null);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // 함수이름: _run
  // 함수역할: 설정 열기·테스트 요청을 직렬화하고 실패를 안내하며 작업 후 권한을 다시 조회한다.
  // 매개변수: action (Future<void> Function()): 실행 작업; isTest (bool): 테스트 알림 요청 여부.
  // 반환값: 처리와 재조회 완료; 테스트 성공 문구는 전송 요청이지 수신 확인이 아니다.
  Future<void> _run(
    Future<void> Function() action, {
    bool isTest = false,
  }) async {
    if (_busy || _refreshing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && isTest) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: KeepWordsText(
              _text(
                '테스트 알림을 요청했습니다. 휴대폰 알림창을 확인해주세요.',
                'Test notification requested. Check your notification panel.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = isTest
              ? _text(
                  '테스트 알림을 보내지 못했습니다. 휴대폰 알림 설정을 확인해주세요.',
                  'The test could not be sent. Check phone notification settings.',
                )
              : _text(
                  '설정을 열지 못했습니다. 다시 시도해주세요.',
                  'Could not open settings. Please try again.',
                ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  // 함수이름: _permissionToggle
  // 함수역할: 권한이 확인되면 실제 운영체제 값을 스위치로 표시하고, 미지원·미확인 상태는 설명 행으로 표시한다.
  // 매개변수: key/title/description (String): 식별자·문구; value (bool?): 실제 권한; openSettings (Future<void> Function()? ): 설정 동작; supported (bool): 지원 여부.
  // 반환값: 권한 상태를 선행 변경하지 않는 설정 행.
  Widget _permissionToggle({
    required String key,
    required String title,
    required String description,
    required bool? value,
    required Future<void> Function()? openSettings,
    bool supported = true,
  }) {
    final enabled = !_busy && !_refreshing;
    if (!supported || value == null) {
      return MedBuddyPreferenceRow(
        key: ValueKey(key),
        title: title,
        description: !supported
            ? _text('지원하지 않음', 'Unavailable')
            : _refreshing
            ? _text('확인 중', 'Checking')
            : _text('상태를 확인하지 못했습니다.', 'Status could not be checked.'),
        onTap: enabled && openSettings != null
            ? () => unawaited(_run(openSettings))
            : null,
      );
    }
    return MedBuddySettingToggle(
      switchKey: ValueKey(key),
      title: title,
      description: description,
      enabled: value,
      // 운영체제에서 확인한 값만 표시하며 탭만으로 상태를 미리 바꾸지 않는다.
      onChanged: enabled && openSettings != null
          ? (_) => unawaited(_run(openSettings))
          : null,
    );
  }

  // Function Name: build
  // Description: Builds device permission rows and a test action gated by actual notification/channel support.
  // Parameters: context (BuildContext): Theme and feedback location.
  // Returns: Settings column, including unavailable-state and operation-error notices.
  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final snapshot = _snapshot;
    final enabled = !_busy && !_refreshing;
    final channelBlocked =
        snapshot?.notifications == true && snapshot?.medicationChannel == false;
    final canTest =
        control.supportsNotifications &&
        snapshot?.notifications == true &&
        (!control.supportsExactAlarms || snapshot?.medicationChannel == true);
    final canOpenSettings =
        control.supportsSystemSettings || control.supportsNotifications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _permissionToggle(
          key: 'deviceNotificationSettingsRow',
          title: _text('알림 허용', 'Allow notifications'),
          // 앱 알림은 허용됐어도 복약 알림 채널이 꺼져 있으면 복약 알림은 오지 않는다. 사용자는
          // 부제목보다 스위치를 먼저 읽으므로 이때는 꺼짐으로 보인다(누르면 휴대폰 설정이 열린다).
          value: channelBlocked ? false : snapshot?.notifications,
          supported: control.supportsNotifications,
          description: channelBlocked
              ? _text(
                  '복약 알림 꺼짐 · 휴대폰 설정에서 변경',
                  'Medication alerts off. Change in phone settings.',
                )
              : _text('휴대폰의 알림 표시와 소리', 'Phone alerts and sound'),
          openSettings: canOpenSettings
              ? (control.supportsSystemSettings
                    ? control.openSystemSettings
                    : control.requestNotificationPermission)
              : null,
        ),
        if (control.supportsExactAlarms &&
            snapshot?.exactAlarmsEditable != false) ...[
          const Divider(height: 1, color: MedBuddyColors.divider),
          _permissionToggle(
            key: 'deviceExactReminderSettingsRow',
            title: _text('정확한 시간에 알림', 'On-time reminders'),
            value: snapshot?.exactAlarms,
            description: _text('정한 시각에 복약 알림', 'Reminders at the chosen time'),
            openSettings: control.openExactSettings,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('notificationSettingsSendTest'),
          onPressed: enabled && canTest
              ? () => unawaited(
                  _run(
                    () => control.sendTest(widget.isEnglish ? 'en' : 'ko'),
                    isTest: true,
                  ),
                )
              : null,
          icon: const Icon(Icons.notifications_active_outlined),
          label: KeepWordsText(
            _text('테스트 알림 보내기', 'Send test notification'),
            textAlign: TextAlign.center,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
        if (!canTest && !_refreshing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KeepWordsText(
              _text(
                control.supportsNotifications
                    ? '휴대폰에서 복약 알림을 허용한 뒤 테스트할 수 있습니다.'
                    : '이 기기에서는 테스트 알림을 지원하지 않습니다.',
                control.supportsNotifications
                    ? 'Allow medication notifications on your phone to run a test.'
                    : 'Test notifications are unavailable on this device.',
              ),
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: KeepWordsText(
                _error!,
                key: const ValueKey('notificationSettingsError'),
                style: const TextStyle(
                  color: MedBuddyColors.danger,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
