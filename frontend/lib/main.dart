// File Name: main.dart
// Role: Bootstraps authentication, global settings, notification routing, and session-owned application services.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'boundaries/check_caregiver_medication_ui_boundary.dart';
import 'boundaries/check_schedule_ui_boundary.dart';
import 'boundaries/linked_chat_ui_boundary.dart';
import 'boundaries/authentication_gate.dart';
import 'boundaries/authentication_ui_boundary.dart';
import 'composition/linked_chat_notification_monitor_factory.dart';
import 'controls/app_language_control.dart';
import 'controls/authentication_control.dart';
import 'entities/user_setting_entity.dart';
import 'services/notification_service.dart';
import 'services/caregiver_notification_monitor_service.dart';
import 'services/caregiver_notification_background_service.dart';
import 'composition/caregiver_notification_monitor_factory.dart';
import 'services/auth_config.dart';
import 'services/linked_chat_notification_monitor_service.dart';
import 'services/medication_reminder_background_service.dart';
import 'services/naver_map_config.dart';
import 'services/push_notification_service.dart';
import 'theme/medbuddy_theme.dart';
import 'theme/medbuddy_text_scale.dart';
import 'viewmodels/medbuddy_view_model.dart';
import 'viewmodels/medbuddy_feature_updates.dart';
import 'views/home_screen.dart';



// Function Name: main
// Description: Initializes Flutter and portrait orientation, attempts map and background setup, starts authentication and language state, runs the app, and then initializes notifications with reported bootstrap failures.
// Parameters:
// - None.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  try {
    await initializeNaverMap();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'MedBuddy bootstrap',
        context: ErrorDescription('initializing Naver Map'),
      ),
    );
  }
  try {
    await CaregiverNotificationBackgroundScheduler.initialize();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'MedBuddy bootstrap',
        context: ErrorDescription('백그라운드 알림 작업을 초기화하는 중'),
      ),
    );
  }
  final authenticationControl = AuthenticationControl.bootstrap();
  final appLanguageControl = AppLanguageControl();
  runApp(
    MedBuddyApp(
      authenticationControl: authenticationControl,
      appLanguageControl: appLanguageControl,
    ),
  );
  try {
    await NotificationService.instance.initialize();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'MedBuddy bootstrap',
        context: ErrorDescription('initializing medication notifications'),
      ),
    );
  }
}

// Class Name: MedBuddyApp
// Role: Configures the application providers, navigation, language, and authentication gate.
// Responsibilities:
// - Create session-scoped view models, load saved settings, apply the shared theme, and coordinate notification entry points.
// Attributes:
// - navigatorKey (GlobalKey<NavigatorState>?): Navigator key used by notification routing.
// - viewModelFactory (MedBuddyViewModel Function()?): Optional factory creating application state for a session.
// - notificationSelectionRegistrar (void Function(MedicationNotificationSelectionHandler? handler)?): Boundary for installing or removing notification-selection handlers.
// - sessionReminderCleanup (Future<void> Function()?): Application reminder-cleanup boundary invoked before sign-out.
// - authenticationControl (AuthenticationControl?): Authentication gate and session lifecycle control.
// - appLanguageControl (AppLanguageControl?): Application language state shared before and after sign-in.
class MedBuddyApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final MedBuddyViewModel Function()? viewModelFactory;
  final void Function(MedicationNotificationSelectionHandler? handler)?
  notificationSelectionRegistrar;
  final Future<void> Function()? sessionReminderCleanup;
  final AuthenticationControl? authenticationControl;
  final AppLanguageControl? appLanguageControl;

  // Function Name: MedBuddyApp
  // Description: Accepts application-owned authentication and language controls plus injectable navigation, view-model, and notification-cleanup boundaries.
  // Parameters:
  // - key (Key?): Flutter widget identity key.
  // - navigatorKey (GlobalKey<NavigatorState>?): Navigator key used by notification routing.
  // - viewModelFactory (MedBuddyViewModel Function()?): Optional factory creating application state for a session.
  // - notificationSelectionRegistrar (void Function(MedicationNotificationSelectionHandler? handler)?): Boundary for installing or removing notification-selection handlers.
  // - sessionReminderCleanup (Future<void> Function()?): Application reminder-cleanup boundary invoked before sign-out.
  // - authenticationControl (AuthenticationControl?): Authentication gate and session lifecycle control.
  // - appLanguageControl (AppLanguageControl?): Application language state shared before and after sign-in.
  // Returns:
  // - MedBuddyApp: the initialized instance.
  const MedBuddyApp({
    super.key,
    this.navigatorKey,
    this.viewModelFactory,
    this.notificationSelectionRegistrar,
    this.sessionReminderCleanup,
    this.authenticationControl,
    this.appLanguageControl,
  });

  // Function Name: createState
  // Description: Creates the state that owns session monitors, authentication listeners, and notification routing for the application root.
  // Parameters:
  // - None.
  // Returns:
  // - State<MedBuddyApp>: Creates the state that owns session monitors, authentication listeners, and notification routing for the application root.
  @override
  State<MedBuddyApp> createState() => _MedBuddyAppState();
}

// Class Name: _MedBuddyAppState
// Role: Owns application-level session listeners, notification monitors, and navigation guards.
// Responsibilities:
// - Replace services on identity changes, clean reminders before sign-out, defer notification navigation until ready, and prevent duplicate destination routes.
// Attributes:
// - _navigatorKey (GlobalKey<NavigatorState>): Navigator key used by notification routing.
// - _authenticationControl (AuthenticationControl): Authentication gate and session lifecycle control.
// - _appLanguageControl (AppLanguageControl): Application language state shared before and after sign-in.
class _MedBuddyAppState extends State<MedBuddyApp> {
  static const String _scheduleRouteName = '/schedule';
  static const String _caregiverScheduleRoutePrefix = '/caregiver-schedule/';
  static const String _linkedChatRoutePrefix = '/linked-chat/';

  late final GlobalKey<NavigatorState> _navigatorKey;
  late final AuthenticationControl _authenticationControl;
  late final bool _ownsAuthenticationControl;
  late final AppLanguageControl _appLanguageControl;
  late final bool _ownsAppLanguageControl;
  bool _isScheduleRouteOpen = false;
  String? _openCaregiverScheduleRouteName;
  String? _openLinkedChatRouteName;
  MedicationNotificationSelection? _pendingNotificationSelection;
  CaregiverNotificationMonitorService? _caregiverNotificationMonitor;
  LinkedChatNotificationMonitorService? _linkedChatNotificationMonitor;
  PushNotificationService? _pushNotificationService;
  String? _monitoredUserHash;
  int _monitorGeneration = 0;

  // Function Name: initState
  // Description: Resolves injected or owned root controls, installs authentication and notification listeners, and starts monitors for the current session.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  @override
  void initState() {
    super.initState();
    _navigatorKey = widget.navigatorKey ?? GlobalKey<NavigatorState>();
    _ownsAuthenticationControl = widget.authenticationControl == null;
    _authenticationControl =
        widget.authenticationControl ?? AuthenticationControl.development();
    _authenticationControl.setBeforeSignOut(_prepareSessionEnd);
    _ownsAppLanguageControl = widget.appLanguageControl == null;
    _appLanguageControl = widget.appLanguageControl ?? AppLanguageControl();
    _authenticationControl.addListener(_handleAuthenticationChange);
    _registerNotificationSelectionHandler(_handleNotificationSelection);
    _synchronizeCaregiverNotificationMonitor();
  }

  // 함수이름: dispose
  // 함수역할: 감시 세대를 무효화하고 보호자·채팅·푸시·백그라운드 작업과 선택 핸들러를 해제하며 직접 소유한 인증·언어 상태만 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  @override
  void dispose() {
    _monitorGeneration += 1;
    _caregiverNotificationMonitor?.dispose();
    unawaited(_linkedChatNotificationMonitor?.dispose());
    unawaited(_pushNotificationService?.stop());
    unawaited(CaregiverNotificationBackgroundScheduler.cancel());
    _registerNotificationSelectionHandler(null);
    _authenticationControl.setBeforeSignOut(null);
    _authenticationControl.removeListener(_handleAuthenticationChange);
    if (_ownsAuthenticationControl) {
      _authenticationControl.dispose();
    }
    if (_ownsAppLanguageControl) {
      _appLanguageControl.dispose();
    }
    super.dispose();
  }

  // Function Name: _prepareSessionEnd
  // Description: Cancels local reminders and replenishment work, then requires server push-token unregistration while the Firebase identity is still valid.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _prepareSessionEnd() async {
    final reminderCleanup = widget.sessionReminderCleanup;
    if (reminderCleanup != null) {
      await reminderCleanup();
    } else {
      await MedicationReminderBackgroundScheduler.cancel();
      await NotificationService.instance.cancelAllMedicationReminders();
    }
    final pushService = _pushNotificationService;
    if (pushService == null) {
      return;
    }
    await pushService.stop(requireServerUnregistration: true);
  }

  // Function Name: _registerNotificationSelectionHandler
  // Description: Installs or removes the app's notification selection callback through the injected registrar or the shared notification service.
  // Parameters:
  // - handler (MedicationNotificationSelectionHandler?): Notification selection receiver; null unregisters it.
  // Returns:
  // - No return value.
  void _registerNotificationSelectionHandler(
    MedicationNotificationSelectionHandler? handler,
  ) {
    final registrar = widget.notificationSelectionRegistrar;
    if (registrar != null) {
      registrar(handler);
      return;
    }
    NotificationService.setNotificationSelectionHandler(handler);
  }

  // 함수이름: _handleNotificationSelection
  // 함수역할: 인증 세션이 없으면 알림 선택을 보류하고 세션이 있으면 준비된 내비게이션으로 전달한다.
  // 매개변수:
  // - selection (MedicationNotificationSelection): 해석된 알림 목적지와 액션 인자
  // 반환값:
  // - 없음.
  void _handleNotificationSelection(MedicationNotificationSelection selection) {
    if (_authenticationControl.session == null) {
      _pendingNotificationSelection = selection;
      return;
    }
    _navigateForNotificationWhenReady(selection);
  }

  // 함수이름: _handleAuthenticationChange
  // 함수역할: 세션에 맞춰 감시 서비스를 교체하고 로그아웃 시 경로 상태를 초기화하며 로그인 후 보류한 알림 이동을 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _handleAuthenticationChange() {
    _synchronizeCaregiverNotificationMonitor();
    if (_authenticationControl.session == null) {
      _pendingNotificationSelection = null;
      _isScheduleRouteOpen = false;
      _openCaregiverScheduleRouteName = null;
      _openLinkedChatRouteName = null;
      _navigatorKey.currentState?.popUntil(/* Function Name: popUntil callback
       * Description: Stops account-transition navigation cleanup at the root route.
       * Parameters:
       * - route (Route<dynamic>): Route currently examined by the navigator.
       * Returns:
       * - Whether this route is the navigator's first route.
       */(route) => route.isFirst);
      return;
    }
    final pendingSelection = _pendingNotificationSelection;
    if (pendingSelection == null) {
      return;
    }
    _pendingNotificationSelection = null;
    _navigateForNotificationWhenReady(pendingSelection);
  }

  // 함수이름: _synchronizeCaregiverNotificationMonitor
  // 함수역할: 로그인 hash가 바뀔 때 보호자 알림 감시 대상을 함께 교체한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _synchronizeCaregiverNotificationMonitor() {
    final userHash = _authenticationControl.session?.userHash.trim();
    if (userHash == _monitoredUserHash) {
      return;
    }
    final generation = ++_monitorGeneration;
    final previousMonitor = _caregiverNotificationMonitor;
    final previousChatMonitor = _linkedChatNotificationMonitor;
    final previousPushService = _pushNotificationService;
    _caregiverNotificationMonitor = null;
    _linkedChatNotificationMonitor = null;
    _pushNotificationService = null;
    _monitoredUserHash = userHash;
    previousMonitor?.dispose();
    unawaited(previousChatMonitor?.dispose());
    if (previousPushService != null) {
      unawaited(previousPushService.stop());
    }

    if (userHash == null || userHash.isEmpty) {
      unawaited(CaregiverNotificationBackgroundScheduler.cancel());
      unawaited(MedicationReminderBackgroundScheduler.cancel());
      return;
    }
    unawaited(MedicationReminderBackgroundScheduler.register(userHash));
    final pushService = PushNotificationService(
      userHash: userHash,
      client: _authenticationControl.apiClient,
      languageProvider: /* 함수이름: languageProvider 콜백
       * 함수역할: 알림 구성 시점에 현재 앱 언어를 읽는다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 현재 앱 언어 코드.
       */() => _appLanguageControl.language,
    );
    _pushNotificationService = pushService;
    unawaited(pushService.start());
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      unawaited(_startLinkedChatNotificationMonitor(userHash, generation));
    }
    unawaited(_startCaregiverNotificationMonitor(userHash, generation));
  }

  // 함수이름: _startLinkedChatNotificationMonitor
  // 함수역할: 로컬 데모 모드에서 현재 사용자의 활성 연동 채팅을 알림 감시 대상으로 등록한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _startLinkedChatNotificationMonitor(
    String userHash,
    int generation,
  ) async {
    final monitor = LinkedChatNotificationMonitorFactory.create(
      userHash: userHash,
      client: _authenticationControl.apiClient,
    );
    if (!mounted || generation != _monitorGeneration) {
      await monitor.dispose();
      return;
    }
    _linkedChatNotificationMonitor = monitor;
    await monitor.start();
    if (!mounted || generation != _monitorGeneration) {
      if (identical(_linkedChatNotificationMonitor, monitor)) {
        _linkedChatNotificationMonitor = null;
      }
      await monitor.dispose();
    }
  }

  // 함수이름: _startCaregiverNotificationMonitor
  // 함수역할: 현재 사용자 세대에 맞는 보호자 감시를 시작하고 인증 모드에 따라 폴링·완료 감시를 조정하며 활성 연동 여부를 백그라운드 작업과 동기화한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - generation (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _startCaregiverNotificationMonitor(
    String userHash,
    int generation,
  ) async {
    final monitor = CaregiverNotificationMonitorFactory.create(
      caregiverHash: userHash,
      client: _authenticationControl.apiClient,
      languageProvider: /* 함수이름: languageProvider 콜백
       * 함수역할: 보호자 모니터가 알림을 만들 때 최신 앱 언어를 제공한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 현재 앱 언어 코드.
       */() => _appLanguageControl.language,
      pollingInterval: AuthConfig.mode == AuthenticationMode.firebase
          ? const Duration(minutes: 1)
          : CaregiverNotificationMonitorService.defaultPollingInterval,
      monitorCompletionTransitions:
          AuthConfig.mode != AuthenticationMode.firebase,
      monitorMissedDeadlines: AuthConfig.mode != AuthenticationMode.firebase,
      onCaregiverStatusChanged: /* 함수이름: onCaregiverStatusChanged 콜백
       * 함수역할: 보호자 연결 유무가 바뀌면 해당 세션 세대의 백그라운드 감시 상태를 갱신한다.
       * 매개변수:
       * - hasCaregiverLinks (bool): 현재 사용자의 활성 보호자 연동 존재 여부
       * 반환값:
       * - 없음; 동기화는 별도로 진행한다.
       */(hasCaregiverLinks) {
        unawaited(
          _synchronizeBackgroundCaregiverMonitoring(
            userHash,
            generation,
            hasCaregiverLinks,
          ),
        );
      },
    );
    if (!mounted || generation != _monitorGeneration) {
      monitor.dispose();
      return;
    }
    _caregiverNotificationMonitor = monitor;
    await monitor.start();
    if (!mounted || generation != _monitorGeneration) {
      monitor.dispose();
      return;
    }
    await _synchronizeBackgroundCaregiverMonitoring(
      userHash,
      generation,
      monitor.hasCaregiverLinks,
    );
  }

  // 함수이름: _synchronizeBackgroundCaregiverMonitoring
  // 함수역할: 보호자로 연결된 환자가 있을 때만 Android 백그라운드 확인 작업을 유지한다.
  // 매개변수:
  // - userHash (String): 현재 로그인 사용자 식별 hash
  // - generation (int): 로그인이 바뀐 뒤 도착한 오래된 요청을 차단하는 세대 번호
  // - hasCaregiverLinks (bool): 현재 사용자가 보호자인 활성 연동을 보유했는지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _synchronizeBackgroundCaregiverMonitoring(
    String userHash,
    int generation,
    bool hasCaregiverLinks,
  ) async {
    if (!mounted || generation != _monitorGeneration) {
      return;
    }
    try {
      if (hasCaregiverLinks &&
          AuthConfig.mode != AuthenticationMode.firebase) {
        await CaregiverNotificationBackgroundScheduler.register(userHash);
      } else {
        await CaregiverNotificationBackgroundScheduler.cancel();
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'MedBuddy caregiver notifications',
          context: ErrorDescription('보호자 백그라운드 확인 작업을 등록하는 중'),
        ),
      );
    }
  }

  // Function Name: _navigateForNotificationWhenReady
  // Description: Routes reminder actions, personal schedules, linked chats, and caregiver patient schedules, retrying navigation after a frame when the root navigator is not ready.
  // Parameters:
  // - selection (MedicationNotificationSelection): Parsed notification destination and action arguments.
  // Returns:
  // - No return value.
  void _navigateForNotificationWhenReady(
    MedicationNotificationSelection selection,
  ) {
    if (selection.destination == MedicationNotificationDestination.schedule) {
      if (selection.action != MedicationNotificationAction.open) {
        _handleMedicationNotificationActionWhenReady(selection);
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator != null) {
        _openSchedule(navigator, initialSlotKey: selection.slotKey);
      } else {
        WidgetsBinding.instance.addPostFrameCallback(/* 함수이름: addPostFrameCallback 콜백
         * 함수역할: 내비게이터가 준비된 다음 프레임에 선택한 복약 시간대 화면을 연다.
         * 매개변수:
         * - _ (Duration): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
         * 반환값:
         * - 없음.
         */(_) {
          if (mounted && _navigatorKey.currentState != null) {
            _openSchedule(
              _navigatorKey.currentState!,
              initialSlotKey: selection.slotKey,
            );
          }
        });
      }
      return;
    }
    if (selection.destination == MedicationNotificationDestination.linkedChat) {
      final linkId = selection.linkId;
      if (linkId == null || linkId < 1) {
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator != null) {
        _openLinkedChat(navigator, linkId);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback(/* 함수이름: addPostFrameCallback 콜백
       * 함수역할: 다음 프레임에 화면이 유지되어 있으면 선택한 가족 채팅을 연다.
       * 매개변수:
       * - _ (Duration): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
       * 반환값:
       * - 없음.
       */(_) {
        if (mounted && _navigatorKey.currentState != null) {
          _openLinkedChat(_navigatorKey.currentState!, linkId);
        }
      });
      return;
    }
    final patientHash = selection.patientHash?.trim() ?? '';
    if (patientHash.isEmpty) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      _openCaregiverSchedule(navigator, patientHash);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(/* 함수이름: addPostFrameCallback 콜백
     * 함수역할: 다음 프레임까지 화면과 내비게이터가 유효하면 선택한 환자 복약 화면을 연다.
     * 매개변수:
     * - _ (Duration): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
     * 반환값:
     * - 없음.
     */(_) {
      if (!mounted) {
        return;
      }
      final mountedNavigator = _navigatorKey.currentState;
      if (mountedNavigator != null) {
        _openCaregiverSchedule(mountedNavigator, patientHash);
      }
    });
  }

  // Function Name: _handleMedicationNotificationActionWhenReady
  // Description: Defers lock-screen medication actions until the navigator and provider context exist, then starts the existing schedule or snooze operation.
  // Parameters:
  // - selection (MedicationNotificationSelection): Parsed notification destination and action arguments.
  // Returns:
  // - No return value.
  void _handleMedicationNotificationActionWhenReady(
    MedicationNotificationSelection selection,
  ) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(/* Function Name: addPostFrameCallback callback
       * Description: Retries a medication-notification action after the next frame while the app state remains mounted.
       * Parameters:
       * - _ (Duration): Unused event value supplied by the enclosing callback contract.
       * Returns:
       * - No return value.
       */(_) {
        if (mounted) {
          _handleMedicationNotificationActionWhenReady(selection);
        }
      });
      return;
    }
    unawaited(_performMedicationNotificationAction(navigator, selection));
  }

  // Function Name: _performMedicationNotificationAction
  // Description: Marks an entire slot taken or schedules a ten-minute snooze, then reports success and offers undo only for a completed status update.
  // Parameters:
  // - navigator (NavigatorState): Application navigator state.
  // - selection (MedicationNotificationSelection): Parsed notification destination and action arguments.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _performMedicationNotificationAction(
    NavigatorState navigator,
    MedicationNotificationSelection selection,
  ) async {
    final slotKey = selection.slotKey?.trim().toLowerCase() ?? '';
    if (slotKey.isEmpty) {
      return;
    }
    final viewModel = navigator.context.read<MedBuddyViewModel>();
    final language = viewModel.userSetting.language;
    final isEnglish = language.trim().toLowerCase().startsWith('en');
    var succeeded = false;
    var canUndo = false;

    switch (selection.action) {
      case MedicationNotificationAction.markSlotTaken:
        succeeded = await viewModel.requestMedicationSlotStatusUpdate(
          slotKey,
          true,
        );
        canUndo = succeeded;
        break;
      case MedicationNotificationAction.snoozeTenMinutes:
        final notificationId = selection.notificationId;
        if (notificationId == null || notificationId < 0) {
          return;
        }
        try {
          await viewModel.notificationService.snoozeMedicationReminder(
            id: notificationId,
            slotKey: slotKey,
            slotTitle: MedicationReminderRefreshService.slotTitle(
              slotKey,
              language,
            ),
            language: language,
          );
          succeeded = true;
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'MedBuddy medication notifications',
              context: ErrorDescription('snoozing a medication reminder'),
            ),
          );
        }
        break;
      case MedicationNotificationAction.open:
        return;
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(navigator.context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          switch (selection.action) {
            MedicationNotificationAction.markSlotTaken => succeeded
                ? (isEnglish
                      ? 'The scheduled medications were marked as taken.'
                      : '예정된 약을 모두 복용 완료로 기록했습니다.')
                : (isEnglish
                      ? 'Could not save medication completion.'
                      : '복약 완료를 저장하지 못했습니다.'),
            MedicationNotificationAction.snoozeTenMinutes => succeeded
                ? (isEnglish
                      ? 'We will remind you again in 10 minutes.'
                      : '10분 후 다시 알려드릴게요.')
                : (isEnglish
                      ? 'Could not schedule another reminder.'
                      : '다시 알림을 예약하지 못했습니다.'),
            MedicationNotificationAction.open => '',
          },
        ),
        duration: Duration(seconds: canUndo ? 5 : 2),
        persist: false,
        action: canUndo
            ? SnackBarAction(
                label: isEnglish ? 'Undo' : '실행 취소',
                onPressed: /* Function Name: onPressed callback
                 * Description: Reverts the selected medication slot to incomplete when the notification-action undo control is pressed.
                 * Parameters:
                 * - None.
                 * Returns:
                 * - No return value; the status update continues asynchronously.
                 */() {
                  unawaited(
                    viewModel.requestMedicationSlotStatusUpdate(slotKey, false),
                  );
                },
              )
            : null,
      ),
    );
  }

  // 함수이름: _openSchedule
  // 함수역할: 본인 복약 일정이 이미 열려 있으면 해당 경로로 돌아가고 없으면 지정 시간대를 선택한 화면을 한 번만 연다.
  // 매개변수:
  // - navigator (NavigatorState): 앱 전역 화면 이동 상태
  // - initialSlotKey (String?): 일정 화면을 열 때 선택할 시간대
  // 반환값:
  // - 없음.
  void _openSchedule(NavigatorState navigator, {String? initialSlotKey}) {
    if (_isScheduleRouteOpen) {
      navigator.popUntil(
        // Function Name: popUntil callback
        // Description: Finds the already-open schedule route without navigating past the root.
        // Parameters:
        // - route (Route<dynamic>): Route currently examined by the navigator.
        // Returns:
        // - Whether this is the schedule route or the root route.
        (route) => route.settings.name == _scheduleRouteName || route.isFirst,
      );
      return;
    }
    _isScheduleRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: _scheduleRouteName),
            builder: /* 함수이름: builder 콜백
             * 함수역할: 알림에서 지정한 시간대를 초기 선택값으로 복약 일정 화면을 구성한다.
             * 매개변수:
             * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
             * 반환값:
             * - 초기 시간대가 적용된 복약 일정 화면.
             */(context) =>
                CheckScheduleUI(initialSlotKey: initialSlotKey),
          ),
        )
        .whenComplete(/* Function Name: whenComplete callback
         * Description: Clears the schedule-route-open guard after that route closes.
         * Parameters:
         * - None.
         * Returns:
         * - The assigned false guard value.
         */() => _isScheduleRouteOpen = false);
  }

  // 함수이름: _openCaregiverSchedule
  // 함수역할: 보호자 알림에 포함된 환자의 오늘 복약 일정 화면을 중복 없이 연다.
  // 매개변수:
  // - navigator (NavigatorState): 앱 전역 Navigator 상태
  // - patientHash (String): 알림을 발생시킨 환자 식별 hash
  // 반환값:
  // - 없음.
  void _openCaregiverSchedule(NavigatorState navigator, String patientHash) {
    final session = _authenticationControl.session;
    if (session == null) {
      return;
    }
    final routeName =
        '$_caregiverScheduleRoutePrefix${Uri.encodeComponent(patientHash)}';
    if (_openCaregiverScheduleRouteName == routeName) {
      navigator.popUntil(
        // 함수이름: popUntil 콜백
        // 함수역할: 이미 열린 보호자 환자 화면 또는 루트까지 경로를 되돌린다.
        // 매개변수:
        // - route (Route<dynamic>): 내비게이터가 확인 중인 화면 경로
        // 반환값:
        // - 대상 경로이거나 첫 경로이면 true.
        (route) => route.settings.name == routeName || route.isFirst,
      );
      return;
    }
    _openCaregiverScheduleRouteName = routeName;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: routeName),
            builder: /* 함수이름: builder 콜백
             * 함수역할: 현재 보호자 세션과 선택한 환자 해시·앱 언어로 환자 복약 화면을 구성한다.
             * 매개변수:
             * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
             * 반환값:
             * - 보호자용 환자 복약 화면.
             */(context) => CheckCaregiverMedicationUI(
              caregiverHash: session.userHash,
              patientHash: patientHash,
              userSetting: UserSetting(language: _appLanguageControl.language),
            ),
          ),
        )
        .whenComplete(/* 함수이름: whenComplete 콜백
         * 함수역할: 닫힌 경로가 현재 추적 중인 환자 화면일 때만 열린 경로 표시를 지운다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */() {
          if (_openCaregiverScheduleRouteName == routeName) {
            _openCaregiverScheduleRouteName = null;
          }
        });
  }

  // 함수이름: _openLinkedChat
  // 함수역할: 채팅 알림에 포함된 연동 식별자의 대화 화면을 중복 없이 연다.
  // 매개변수:
  // - navigator (NavigatorState): 앱 전역 화면 이동 상태
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // 반환값:
  // - 없음.
  void _openLinkedChat(NavigatorState navigator, int linkId) {
    final session = _authenticationControl.session;
    if (session == null) {
      return;
    }
    final routeName = '$_linkedChatRoutePrefix$linkId';
    if (_openLinkedChatRouteName == routeName) {
      navigator.popUntil(
        // 함수이름: popUntil 콜백
        // 함수역할: 이미 열린 연결 채팅 경로를 찾되 루트 경로를 넘지 않는다.
        // 매개변수:
        // - route (Route<dynamic>): 내비게이터가 확인 중인 화면 경로
        // 반환값:
        // - 대상 채팅 경로이거나 첫 경로이면 true.
        (route) => route.settings.name == routeName || route.isFirst,
      );
      return;
    }
    _openLinkedChatRouteName = routeName;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: routeName),
            builder: /* 함수이름: builder 콜백
             * 함수역할: 현재 사용자와 선택한 연결 ID·앱 언어를 가족 채팅 화면에 전달한다.
             * 매개변수:
             * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
             * 반환값:
             * - 선택한 가족 연결의 채팅 화면.
             */(context) => LinkedChatUI(
              linkId: linkId,
              currentUserHash: session.userHash,
              userSetting: UserSetting(language: _appLanguageControl.language),
            ),
          ),
        )
        .whenComplete(/* 함수이름: whenComplete 콜백
         * 함수역할: 닫힌 채팅이 현재 추적 중인 경로일 때 열린 채팅 경로 표시를 지운다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */() {
          if (_openLinkedChatRouteName == routeName) {
            _openLinkedChatRouteName = null;
          }
        });
  }

  // 함수이름: build
  // 함수역할: 인증·언어 상태에 맞는 MaterialApp과 세션별 ViewModel을 구성하고 사용자 접근성 배율 및 인증 게이트를 적용한다.
  // 매개변수:
  // - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
  // 반환값:
  // - Widget: 인증·언어 상태에 맞는 MaterialApp과 세션별 ViewModel을 구성하고 사용자 접근성 배율 및 인증 게이트를 적용한다.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthenticationControl>.value(
          value: _authenticationControl,
        ),
        ChangeNotifierProvider<AppLanguageControl>.value(
          value: _appLanguageControl,
        ),
      ],
      child: Consumer2<AuthenticationControl, AppLanguageControl>(
        builder: /* 함수이름: builder 콜백
         * 함수역할: 인증 상태와 언어에 맞는 앱 루트를 만들고 로그인 세션별 뷰모델 제공자를 연결한다.
         * 매개변수:
         * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
         * - authentication (AuthenticationControl): 구독 중인 인증 게이트 상태
         * - appLanguage (AppLanguageControl): 구독 중인 앱 언어 상태
         * - _ (Widget?): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
         * 반환값:
         * - 인증 상태·언어·테마가 적용된 앱 위젯 트리.
         */(context, authentication, appLanguage, _) {
          final session = authentication.session;
          final application = MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'MedBuddy',
            debugShowCheckedModeBanner: false,
            locale: Locale(appLanguage.language),
            supportedLocales: const [Locale('ko'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: /* 함수이름: builder 콜백
             * 함수역할: 비로그인 기본 설정 또는 로그인 사용자의 설정 변경에 따라 글자 배율을 적용한다.
             * 매개변수:
             * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
             * - child (Widget?): 접근성 배율을 전달할 하위 화면
             * 반환값:
             * - 사용자 글자 배율을 적용하는 앱 래퍼.
             */(context, child) {
              if (session == null) {
                return MedBuddyTextScale(
                  userSetting: UserSetting(language: appLanguage.language),
                  child: child ?? const SizedBox.shrink(),
                );
              }
              final viewModel = context.read<MedBuddyViewModel>();
              return ListenableBuilder(
                listenable: viewModel.updatesFor(MedBuddyFeature.userSetting),
                builder: /* 함수이름: builder 콜백
                 * 함수역할: 사용자 설정이 변경될 때 앱 콘텐츠의 글자 배율을 다시 적용한다.
                 * 매개변수:
                 * - context (BuildContext): 화면 트리의 의존성을 조회할 BuildContext
                 * - _ (Widget?): 콜백 계약으로 전달되지만 사용하지 않는 이벤트 값.
                 * 반환값:
                 * - 현재 사용자 설정을 반영한 글자 배율 위젯.
                 */(context, _) => MedBuddyTextScale(
                  userSetting: viewModel.userSetting,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: MedBuddyColors.primary,
              ),
              primaryColor: MedBuddyColors.primary,
              scaffoldBackgroundColor: MedBuddyColors.pageBackground,
              useMaterial3: true,
              fontFamilyFallback: const ['Noto Sans KR', 'Roboto', 'Arial'],
            ),
            home: AuthenticationGate(
              state: authentication,
              unauthenticatedChild: AuthenticationUI(
                control: authentication,
                languageControl: appLanguage,
              ),
              authenticatedChild: const HomeScreen(),
            ),
          );
          if (session == null) {
            return application;
          }
          return ChangeNotifierProvider<MedBuddyViewModel>(
            key: ValueKey(session.userHash),
            create: /* Function Name: create callback
             * Description: Creates the session-scoped view model and starts loading user settings to synchronize the app language.
             * Parameters:
             * - _ (BuildContext): Unused event value supplied by the enclosing callback contract.
             * Returns:
             * - The view model owned by the session provider.
             */(_) {
              final viewModel =
                  widget.viewModelFactory?.call() ??
                  MedBuddyViewModel(
                    patientHash: session.userHash,
                    apiClient: authentication.apiClient,
                  );
              unawaited(_loadUserSettingAndSyncLanguage(viewModel));
              return viewModel;
            },
            child: application,
          );
        },
      ),
    );
  }

  // Function Name: _loadUserSettingAndSyncLanguage
  // Description: Loads the signed-in user's settings and synchronizes their language to the device-wide control, reporting bootstrap failures without escaping the task.
  // Parameters:
  // - viewModel (MedBuddyViewModel): Feature state for the signed-in user.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _loadUserSettingAndSyncLanguage(
    MedBuddyViewModel viewModel,
  ) async {
    try {
      await viewModel.loadUserSetting();
      await _appLanguageControl.setLanguage(viewModel.userSetting.language);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'MedBuddy settings bootstrap',
          context: ErrorDescription('loading authenticated user settings'),
        ),
      );
    }
  }
}
