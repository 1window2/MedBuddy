// 파일명: exact_reminder_notice.dart
// 역할: 복약 알림이 늦게 울릴 수 있는 기기에서 '알람 및 리마인더' 허용을 안내한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: ExactReminderNotice
// 역할: 정확한 알람이 허용되지 않은 동안에만 보이는 안내와 시스템 설정으로 가는 버튼을 담당한다.
// 주요 책임:
// - 화면에 들어올 때와 앱으로 돌아올 때 허용 여부를 다시 확인해, 허용된 뒤에는 스스로 사라진다.
// - 버튼을 누르면 시스템의 '알람 및 리마인더' 화면을 열고, 허용되면 이미 예약된 알림을 정확한 알람으로 바꾼다.
// - 허용하지 않아도 화면 사용을 막지 않는다. 알림은 지금처럼 예약되고 몇 분 늦을 수 있을 뿐이다.
// 속성:
// - notificationService (NotificationService): 허용 여부 확인·요청과 재예약을 맡는 알림 서비스.
// - isEnglish (bool): 영어 문구 사용 여부.
// - margin (EdgeInsetsGeometry): 안내가 보일 때만 적용하는 바깥 여백.
class ExactReminderNotice extends StatefulWidget {
  final NotificationService notificationService;
  final bool isEnglish;
  final EdgeInsetsGeometry margin;

  // 함수이름: ExactReminderNotice
  // 함수역할: 안내에 쓸 알림 서비스와 언어, 바깥 여백을 받는다.
  // 매개변수:
  // - key (Key?): 위젯 식별 키.
  // - notificationService (NotificationService): 허용 여부 확인·요청과 재예약을 맡는 알림 서비스.
  // - isEnglish (bool): 영어 문구 사용 여부.
  // - margin (EdgeInsetsGeometry): 안내가 보일 때만 적용하는 바깥 여백.
  // 반환값: 입력 설정이 반영된 ExactReminderNotice 인스턴스.
  const ExactReminderNotice({
    super.key,
    required this.notificationService,
    required this.isEnglish,
    this.margin = EdgeInsets.zero,
  });

  // 함수이름: createState
  // 함수역할: 허용 여부를 추적하는 상태 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _ExactReminderNoticeState 인스턴스.
  @override
  State<ExactReminderNotice> createState() => _ExactReminderNoticeState();
}

// 클래스명: _ExactReminderNoticeState
// 역할: 정확한 알람 허용 여부를 확인하고 앱 복귀 시 다시 확인한다.
// 속성:
// - _allowed (bool?): 마지막으로 확인한 허용 여부; 확인 전이거나 확인하지 못하면 null이며 안내를 보이지 않는다.
// - _requesting (bool): 시스템 설정 화면을 여는 중인지 여부.
class _ExactReminderNoticeState extends State<ExactReminderNotice>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _requesting = false;

  // 함수이름: initState
  // 함수역할: 앱 실행 상태 관찰을 시작하고 허용 여부를 처음 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  // 함수이름: dispose
  // 함수역할: 앱 실행 상태 관찰을 끝낸다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 시스템 설정에서 돌아오면 허용 여부를 다시 확인한다.
  // 매개변수:
  // - state (AppLifecycleState): 새 앱 실행 상태.
  // 반환값: 없음.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  // 함수이름: _refresh
  // 함수역할: 허용 여부를 읽어 화면에 반영하고, 허용되어 있으면 부정확 알람으로 남은 예약을 정확한 알람으로 바꾼다.
  //   확인에 실패하면 안내를 보이지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값: 확인을 마치면 완료되는 Future<void>.
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

  // 함수이름: _requestPermission
  // 함수역할: 시스템의 '알람 및 리마인더' 화면을 열고, 돌아온 뒤 허용 여부를 다시 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청과 확인을 마치면 완료되는 Future<void>.
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

  // 함수이름: build
  // 함수역할: 정확한 알람이 허용되지 않은 것으로 확인된 동안에만 안내와 버튼을 그린다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정을 참조할 위젯 트리 위치.
  // 반환값: 안내 위젯, 보일 필요가 없으면 빈 위젯.
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
      child: Container(
        key: const Key('exact-reminder-notice'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MedBuddyColors.warningSurface,
          borderRadius: MedBuddyRadii.small,
          border: Border.all(color: MedBuddyColors.warningBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.alarm_outlined,
                  color: MedBuddyColors.reminderAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: MedBuddyColors.reminderAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
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
          ],
        ),
      ),
    );
  }
}
