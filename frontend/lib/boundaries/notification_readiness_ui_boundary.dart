// 파일명: notification_readiness_ui_boundary.dart
// 역할: 첫 약 등록, 기기 알림 권한과 실제 테스트 알림의 확인을 분리해 안내한다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../controls/notification_readiness_control.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';

class NotificationReadinessUI extends StatefulWidget {
  final NotificationReadinessControl control;
  final UserSetting savedSetting;
  final bool isEnglish;
  final VoidCallback? onMedicationRegistrationRequested;
  final VoidCallback? onMedicationScheduleRequested;
  final Future<void> Function()? onWidgetRequested;
  final VoidCallback? onCaregiverSetupRequested;

  const NotificationReadinessUI({
    super.key,
    required this.control,
    required this.savedSetting,
    required this.isEnglish,
    this.onMedicationRegistrationRequested,
    this.onMedicationScheduleRequested,
    this.onWidgetRequested,
    this.onCaregiverSetupRequested,
  });

  @override
  State<NotificationReadinessUI> createState() =>
      _NotificationReadinessUIState();
}

class _NotificationReadinessUIState extends State<NotificationReadinessUI>
    with WidgetsBindingObserver {
  NotificationReadinessSnapshot? _snapshot;
  bool _refreshing = false;
  bool _busy = false;
  bool _testSent = false;
  bool _testObserved = false;
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
    final snapshot = await widget.control.refresh();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _refreshing = false;
      if (snapshot.notifications != true ||
          (widget.control.supportsExactAlarms &&
              snapshot.medicationChannel != true)) {
        _testSent = false;
        _testObserved = false;
      }
    });
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
      if (isTest) {
        _testSent = false;
        _testObserved = false;
      }
    });
    try {
      await action();
      if (mounted && isTest) setState(() => _testSent = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = isTest
              ? _text(
                  '테스트 알림을 보내지 못했습니다. 권한과 휴대폰 설정을 확인해주세요.',
                  'The test could not be sent. Check permission and phone settings.',
                )
              : _text(
                  '요청을 완료하지 못했습니다. 휴대폰 설정에서 확인하거나 다시 시도해주세요.',
                  'The request could not be completed. Check phone settings or try again.',
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

  String _status(bool? value) => value == true
      ? _text('허용됨', 'Allowed')
      : value == false
      ? _text('허용되지 않음', 'Not allowed')
      : _text('확인하지 못함', 'Not verified');

  Widget _action(
    String key,
    IconData icon,
    String label,
    VoidCallback action,
  ) => OutlinedButton.icon(
    key: ValueKey(key),
    onPressed: _busy || _refreshing ? null : action,
    icon: Icon(icon),
    label: Text(label, textAlign: TextAlign.center),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
    ),
  );

  // 설명과 동작을 분리해 모든 항목에 같은 여백과 읽기 순서를 적용한다.
  Widget _section(
    String title,
    IconData icon,
    List<Widget> children, {
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: MedBuddyColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DefaultTextStyle.merge(
          style: const TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 16,
            height: 1.5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            actions[i],
          ],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final snapshot = _snapshot;
    final supported = control.supportsNotifications;
    final canTest =
        supported &&
        snapshot?.notifications == true &&
        (!control.supportsExactAlarms || snapshot?.medicationChannel == true);
    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MedBuddyPageHeader(
              title: _text('사용 준비 점검', 'Setup check'),
              subtitle: _text(
                '약 등록과 알림 수신 상태를 점검합니다.',
                'Check medication setup and notifications.',
              ),
              onBackRequested: () => Navigator.of(context).pop(),
              backTooltip: _text('뒤로', 'Back'),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      if (_refreshing || _busy)
                        LinearProgressIndicator(
                          semanticsLabel: _text('확인 중', 'Checking'),
                        ),
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: const ValueKey('readinessError'),
                            style: const TextStyle(
                              color: MedBuddyColors.danger,
                              height: 1.5,
                            ),
                          ),
                        ),
                      _action(
                        'readinessRefresh',
                        Icons.refresh,
                        _text('다시 점검', 'Check again'),
                        () => unawaited(_refresh()),
                      ),
                      _section(
                        _text('1. 내 약 등록', '1. My medications'),
                        Icons.medication_outlined,
                        [
                          Text(
                            snapshot?.hasMedication == true
                                ? _text(
                                    '등록된 약이 있습니다. 복약함에서 내용과 일정을 확인해주세요.',
                                    'You have saved medications. Review their details and schedules.',
                                  )
                                : snapshot?.hasMedication == false
                                ? _text(
                                    '등록된 약이 없습니다. 본인 복약 알림은 약을 등록한 뒤 이용할 수 있습니다.',
                                    'No medications are saved. Add one to use your own dose reminders.',
                                  )
                                : _text(
                                    '등록 여부를 확인하지 못했습니다. 연결을 확인하거나 복약함에서 확인해주세요.',
                                    'Saved medications could not be checked. Check your connection or medication list.',
                                  ),
                          ),
                          Text(
                            _text(
                              '보호자로만 이용한다면 내 약 등록은 필요하지 않습니다.',
                              'You do not need to add your own medication when using the app only as a caregiver.',
                            ),
                          ),
                        ],
                        actions: [
                          if (widget.onMedicationRegistrationRequested != null)
                            _action(
                              'readinessAddMedication',
                              Icons.add,
                              _text('약 등록', 'Add medication'),
                              widget.onMedicationRegistrationRequested!,
                            ),
                          if (widget.onMedicationScheduleRequested != null)
                            _action(
                              'readinessSchedule',
                              Icons.calendar_month_outlined,
                              _text('내 일정 확인', 'View my schedule'),
                              widget.onMedicationScheduleRequested!,
                            ),
                        ],
                      ),
                      const Divider(height: 1),
                      _section(
                        _text('2. 알림 설정', '2. Notification settings'),
                        Icons.notifications_outlined,
                        [
                          Text(
                            _text(
                                  '앱에 저장된 내 복약 알림: ',
                                  'Saved dose reminder setting: ',
                                ) +
                                (widget
                                        .savedSetting
                                        .medicationNotificationsEnabled
                                    ? _text('켜짐', 'On')
                                    : _text('꺼짐', 'Off')),
                            key: const ValueKey('readinessAppSetting'),
                          ),
                          if (!widget
                              .savedSetting
                              .medicationNotificationsEnabled)
                            Text(
                              _text(
                                '본인 복약 알림이 필요하면 환경설정 > 복약 및 알림에서 켜고 저장해주세요.',
                                'For your own dose reminders, enable and save them in Medication & Notifications.',
                              ),
                            ),
                          Text(
                            supported
                                ? _text(
                                        '휴대폰 알림 권한: ',
                                        'Phone notification permission: ',
                                      ) +
                                      _status(snapshot?.notifications)
                                : _text(
                                    '이 환경에서는 알림을 점검할 수 없습니다. 지원되는 휴대폰에서 확인해주세요.',
                                    'Notification checks are unavailable here. Use a supported phone.',
                                  ),
                            key: const ValueKey('readinessSystemPermission'),
                          ),
                          if (control.supportsExactAlarms) ...[
                            Text(
                              _text(
                                    '복약 알림 채널: ',
                                    'Medication notification channel: ',
                                  ) +
                                  _status(snapshot?.medicationChannel),
                            ),
                            Text(
                              _text('알람 및 리마인더: ', 'Alarms & reminders: ') +
                                  _status(snapshot?.exactAlarms),
                              key: const ValueKey('readinessExactPermission'),
                            ),
                            if (snapshot?.exactAlarms != true)
                              Text(
                                _text(
                                  '정확한 알람이 허용되지 않으면 정한 시각보다 늦게 울릴 수 있습니다.',
                                  'Without exact alarm permission, scheduled reminders may arrive late.',
                                ),
                              ),
                          ],
                        ],
                        actions: [
                          if (supported && snapshot?.notifications != true)
                            _action(
                              'readinessRequestPermission',
                              Icons.notifications_active_outlined,
                              _text(
                                '알림 권한 요청',
                                'Request notification permission',
                              ),
                              () => unawaited(
                                _run(control.requestNotificationPermission),
                              ),
                            ),
                          if (control.supportsExactAlarms &&
                              snapshot?.exactAlarms != true)
                            _action(
                              'readinessRequestExact',
                              Icons.alarm,
                              _text('알람 및 리마인더 허용', 'Allow alarms & reminders'),
                              () => unawaited(
                                _run(control.requestExactPermission),
                              ),
                            ),
                          if (control.supportsSystemSettings)
                            _action(
                              'readinessSystemSettings',
                              Icons.settings_outlined,
                              _text('휴대폰 알림 설정', 'Phone notification settings'),
                              () => unawaited(_run(control.openSystemSettings)),
                            ),
                        ],
                      ),
                      const Divider(height: 1),
                      _section(
                        _text('3. 테스트 알림', '3. Test notification'),
                        Icons.notification_add_outlined,
                        [
                          Text(
                            _text(
                              '복약 기록을 바꾸지 않는 즉시 알림입니다. 알림창에서 직접 표시 여부를 확인해주세요.',
                              'This immediate test does not change dose records. Check your notification panel.',
                            ),
                          ),
                          Text(
                            _text(
                              '한 번의 테스트는 향후 예약 알림·서버 푸시 수신을 보장하지 않습니다. '
                                  '소리, 방해 금지, 절전 설정과 앱 강제 종료도 알림에 영향을 줄 수 있습니다.',
                              'One test does not guarantee future scheduled reminders or server push delivery. '
                                  'Sound, Do Not Disturb, battery restrictions and force-stopping the app can affect alerts.',
                            ),
                            key: const ValueKey('readinessTestLimitations'),
                          ),
                          if (!canTest)
                            Text(
                              _text(
                                '휴대폰 알림 권한과 복약 알림 채널을 먼저 확인해주세요.',
                                'First verify notification permission and the medication notification channel.',
                              ),
                            ),
                          if (_testSent)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _testObserved
                                    ? _text(
                                        '사용자가 이번 테스트 알림을 확인했습니다.',
                                        'You confirmed seeing this test notification.',
                                      )
                                    : _text(
                                        '테스트 표시 요청을 보냈습니다. 실제 표시 여부는 아직 확인되지 않았습니다.',
                                        'The display request was sent. Actual display has not been confirmed.',
                                      ),
                                key: const ValueKey('readinessTestResult'),
                              ),
                            ),
                        ],
                        actions: [
                          if (canTest)
                            _action(
                              'readinessSendTest',
                              Icons.send_outlined,
                              _text('테스트 알림 보내기', 'Send test notification'),
                              () => unawaited(
                                _run(
                                  () => control.sendTest(
                                    widget.isEnglish ? 'en' : 'ko',
                                  ),
                                  isTest: true,
                                ),
                              ),
                            ),
                          if (_testSent && !_testObserved)
                            _action(
                              'readinessConfirmTest',
                              Icons.check,
                              _text(
                                '테스트 알림을 봤어요',
                                'I saw the test notification',
                              ),
                              () => setState(() => _testObserved = true),
                            ),
                        ],
                      ),
                      const Divider(height: 1),
                      _section(
                        _text('선택 설정', 'Optional setup'),
                        Icons.tune,
                        [
                          Text(
                            _text(
                              '위젯과 보호자 연동은 선택 사항이며, 완료하지 않아도 앱을 사용할 수 있습니다.',
                              'Widgets and caregiver links are optional and do not block app use.',
                            ),
                          ),
                          if (widget.onCaregiverSetupRequested == null)
                            Text(
                              _text(
                                '환자·보호자 연동은 내 정보에서 설정할 수 있습니다.',
                                'Manage patient / caregiver links in My Info.',
                              ),
                            ),
                        ],
                        actions: [
                          if (widget.onWidgetRequested != null)
                            _action(
                              'readinessAddWidget',
                              Icons.widgets_outlined,
                              _text('홈 화면 위젯 추가', 'Add home screen widget'),
                              () => unawaited(_run(widget.onWidgetRequested!)),
                            ),
                          if (widget.onCaregiverSetupRequested != null)
                            _action(
                              'readinessCaregiver',
                              Icons.people_outline,
                              _text('환자·보호자 연동', 'Patient / caregiver links'),
                              widget.onCaregiverSetupRequested!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
