// 파일명: notification_readiness_ui_boundary.dart
// 역할: 복약 및 알림 설정 안에서 기기 권한과 테스트 알림을 제공한다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/notification_readiness_control.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_preference_row.dart';
import '../widgets/medbuddy_setting_toggle.dart';

class NotificationDeviceSettings extends StatefulWidget {
  final NotificationReadinessControl control;
  final bool isEnglish;

  const NotificationDeviceSettings({
    super.key,
    required this.control,
    required this.isEnglish,
  });

  @override
  State<NotificationDeviceSettings> createState() =>
      _NotificationDeviceSettingsState();
}

class _NotificationDeviceSettingsState extends State<NotificationDeviceSettings>
    with WidgetsBindingObserver {
  NotificationReadinessSnapshot? _snapshot;
  bool _refreshing = false;
  bool _busy = false;
  String? _error;

  String _text(String ko, String en) => widget.isEnglish ? en : ko;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 시스템 설정에서 돌아오면 화면을 닫았다 열 필요 없이 다시 점검한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(_refresh());
    }
  }

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

  // 연타와 화면 이탈을 처리하고 플랫폼 오류를 사용자 문구로 바꾼다.
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
            content: Text(
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
          value: snapshot?.notifications,
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
          label: Text(
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
            child: Text(
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
              child: Text(
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
