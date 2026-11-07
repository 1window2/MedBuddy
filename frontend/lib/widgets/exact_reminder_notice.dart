// 파일명: exact_reminder_notice.dart
// 역할: 복약 알림이 늦게 울릴 수 있는 기기에서 '알람 및 리마인더' 허용을 안내한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/medbuddy_theme.dart';
import 'medbuddy_notice.dart';

// Class Name: ExactReminderNotice
// Role: Offer exact-reminder permission guidance when Android reports it unavailable.
// Responsibilities: Recheck permission on resume and promote inexact reminders when allowed.
// Attributes: notificationService (NotificationService): permission/scheduling boundary; isEnglish (bool): locale; margin (EdgeInsetsGeometry): outer spacing.
class ExactReminderNotice extends StatefulWidget {
  final NotificationService notificationService;
  final bool isEnglish;
  final EdgeInsetsGeometry margin;

  // Function Name: ExactReminderNotice
  // Description: Configure the permission notice without requesting permission during construction.
  // Parameters: key (Key?): widget identity; notificationService (NotificationService): permission boundary; isEnglish (bool): locale; margin (EdgeInsetsGeometry): outer spacing.
  // Returns: ExactReminderNotice: configured widget.
  const ExactReminderNotice({
    super.key,
    required this.notificationService,
    required this.isEnglish,
    this.margin = EdgeInsets.zero,
  });

  // Function Name: createState
  // Description: Create lifecycle-aware permission state.
  // Parameters: None.
  // Returns: State<ExactReminderNotice>: notice state.
  @override
  State<ExactReminderNotice> createState() => _ExactReminderNoticeState();
}

// Class Name: _ExactReminderNoticeState
// Role: Track exact-alarm availability and permission-request progress.
// Responsibilities: Observe app resume, refresh capability and prevent duplicate permission prompts.
// Attributes: _allowed (bool?): capability or unknown; _requesting (bool): prompt in progress.
class _ExactReminderNoticeState extends State<ExactReminderNotice>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _requesting = false;

  // Function Name: initState
  // Description: Observe app lifecycle and begin an asynchronous capability refresh.
  // Parameters: None.
  // Returns: void.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  // Function Name: dispose
  // Description: Unregister the lifecycle observer before releasing widget state.
  // Parameters: None.
  // Returns: void.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Function Name: didChangeAppLifecycleState
  // Description: Refresh permission after returning from system settings or another app.
  // Parameters: state (AppLifecycleState): lifecycle event.
  // Returns: void; only resumed triggers a refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  // Function Name: _refresh
  // Description: Query exact-alarm capability and promote schedules when allowed; suppress platform failures and update only mounted state.
  // Parameters: None.
  // Returns: Future<void>: refresh attempt completion.
  Future<void> _refresh() async {
    bool? allowed;
    try {
      allowed = await widget.notificationService.canScheduleExactReminders();
      if (allowed) {
        await widget.notificationService.rescheduleInexactRemindersAsExact();
      }
    } catch (_) {
      // 확인하거나 다시 예약하지 못해도 기존 예약은 그대로 남는다.
    }
    if (mounted && allowed != _allowed) {
      setState(() => _allowed = allowed);
    }
  }

  // Function Name: _requestPermission
  // Description: Prevent duplicate permission prompts, request permission and refresh the resulting capability.
  // Parameters: None.
  // Returns: Future<void>: prompt/refresh completion; request errors are suppressed.
  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await widget.notificationService.requestExactReminderPermission();
    } catch (_) {
      // 설정 화면을 열지 못하면 안내를 그대로 두어 다시 누를 수 있게 한다.
    }
    await _refresh();
    if (mounted) {
      setState(() => _requesting = false);
    }
  }

  // Function Name: build
  // Description: Render localized permission guidance only when capability is explicitly false; disable the action during a request.
  // Parameters: context (BuildContext): widget build context.
  // Returns: Widget: notice or an empty box for allowed/unknown capability.
  @override
  Widget build(BuildContext context) {
    if (_allowed != false) {
      return const SizedBox.shrink();
    }
    final message = widget.isEnglish
        ? 'On this phone, medication reminders can arrive a few minutes '
              'late. Allow "Alarms & reminders" to be reminded on time.'
        : '이 휴대폰에서는 복약 알림이 몇 분 늦게 울릴 수 있습니다. '
              "'알람 및 리마인더'를 허용하면 정한 시각에 맞춰 알려 드립니다.";
    return Padding(
      padding: widget.margin,
      child: MedBuddyNotice(
        key: const Key('exact-reminder-notice'),
        icon: Icons.alarm_outlined,
        message: message,
        action: OutlinedButton(
          key: const Key('exact-reminder-allow'),
          onPressed: _requesting ? null : _requestPermission,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: MedBuddyColors.primaryDark,
          ),
          child: Text(
            widget.isEnglish ? 'Allow on-time reminders' : '정확한 시각에 알림 받기',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
