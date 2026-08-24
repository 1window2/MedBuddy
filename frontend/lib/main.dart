// 파일명: main.dart
// 역할: MedBuddy 앱의 인증, 전역 설정, 알림과 초기 화면 구성을 시작한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

// 파일명: main.dart
// 역할: Flutter 앱의 Provider, 테마, 첫 화면을 초기화한다.

// 함수명: main
// 함수역할:
// - MedBuddy Flutter 앱을 실행한다.
// 반환값:
// - 없음
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

// 클래스명: MedBuddyApp
// 역할: 앱 전역 Provider와 MaterialApp 설정을 구성한다.
// 주요 책임:
// - MedBuddyViewModel을 앱 전역 상태로 등록한다.
// - 저장된 사용자 설정을 앱 시작 시 불러온다.
// - 홈 화면과 공통 테마를 설정한다.
class MedBuddyApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final MedBuddyViewModel Function()? viewModelFactory;
  final void Function(MedicationNotificationSelectionHandler? handler)?
  notificationSelectionRegistrar;
  final Future<void> Function()? sessionReminderCleanup;
  final AuthenticationControl? authenticationControl;
  final AppLanguageControl? appLanguageControl;

  const MedBuddyApp({
    super.key,
    this.navigatorKey,
    this.viewModelFactory,
    this.notificationSelectionRegistrar,
    this.sessionReminderCleanup,
    this.authenticationControl,
    this.appLanguageControl,
  });

  @override
  State<MedBuddyApp> createState() => _MedBuddyAppState();
}

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

  // 함수이름: _prepareSessionEnd
  // 함수역할:
  // - 로컬 복약 알림과 보충 작업을 취소한다.
  // - Firebase 인증이 유효한 동안 서버의 푸시 토큰 등록을 해제한다.
  // 반환값:
  // - 현재 사용자 알림 정보 정리가 완료되면 종료된다.
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

  void _handleNotificationSelection(MedicationNotificationSelection selection) {
    if (_authenticationControl.session == null) {
      _pendingNotificationSelection = selection;
      return;
    }
    _navigateForNotificationWhenReady(selection);
  }

  void _handleAuthenticationChange() {
    _synchronizeCaregiverNotificationMonitor();
    if (_authenticationControl.session == null) {
      _pendingNotificationSelection = null;
      _isScheduleRouteOpen = false;
      _openCaregiverScheduleRouteName = null;
      _openLinkedChatRouteName = null;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    final pendingSelection = _pendingNotificationSelection;
    if (pendingSelection == null) {
      return;
    }
    _pendingNotificationSelection = null;
    _navigateForNotificationWhenReady(pendingSelection);
  }

  // 함수명: _synchronizeCaregiverNotificationMonitor
  // 역할:
  // - 로그인 hash가 바뀔 때 보호자 알림 감시 대상을 함께 교체한다.
  // 반환값:
  // - 없음
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
      languageProvider: () => _appLanguageControl.language,
    );
    _pushNotificationService = pushService;
    unawaited(pushService.start());
    if (AuthConfig.mode == AuthenticationMode.disabled) {
      unawaited(_startLinkedChatNotificationMonitor(userHash, generation));
    }
    unawaited(_startCaregiverNotificationMonitor(userHash, generation));
  }

  // 함수명: _startLinkedChatNotificationMonitor
  // 역할:
  // - 로컬 데모 모드에서 현재 사용자의 활성 연동 채팅을 알림 감시 대상으로 등록한다.
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

  Future<void> _startCaregiverNotificationMonitor(
    String userHash,
    int generation,
  ) async {
    final monitor = CaregiverNotificationMonitorFactory.create(
      caregiverHash: userHash,
      client: _authenticationControl.apiClient,
      languageProvider: () => _appLanguageControl.language,
      pollingInterval: AuthConfig.mode == AuthenticationMode.firebase
          ? const Duration(minutes: 1)
          : CaregiverNotificationMonitorService.defaultPollingInterval,
      monitorCompletionTransitions:
          AuthConfig.mode != AuthenticationMode.firebase,
      onCaregiverStatusChanged: (hasCaregiverLinks) {
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
  // 함수역할:
  // - 보호자로 연결된 환자가 있을 때만 Android 백그라운드 확인 작업을 유지한다.
  // 매개변수:
  // - userHash: 현재 로그인 사용자 식별 hash
  // - generation: 로그인이 바뀐 뒤 도착한 오래된 요청을 차단하는 세대 번호
  // - hasCaregiverLinks: 현재 사용자가 보호자인 활성 연동을 보유했는지 여부
  // 반환값:
  // - 없음
  Future<void> _synchronizeBackgroundCaregiverMonitoring(
    String userHash,
    int generation,
    bool hasCaregiverLinks,
  ) async {
    if (!mounted || generation != _monitorGeneration) {
      return;
    }
    try {
      if (hasCaregiverLinks) {
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

  void _navigateToScheduleWhenReady() {
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      _openSchedule(navigator);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final mountedNavigator = _navigatorKey.currentState;
      if (mountedNavigator == null) {
        return;
      }
      _openSchedule(mountedNavigator);
    });
  }

  // 함수이름: _navigateForNotificationWhenReady
  // 함수역할:
  // - 일반 복약 알림은 본인 일정으로, 보호자 알림은 선택 환자 일정으로 이동시킨다.
  // 매개변수:
  // - selection: 알림 payload에서 해석한 이동 대상과 환자 hash
  // 반환값:
  // - 없음
  void _navigateForNotificationWhenReady(
    MedicationNotificationSelection selection,
  ) {
    if (selection.destination == MedicationNotificationDestination.schedule) {
      _navigateToScheduleWhenReady();
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final mountedNavigator = _navigatorKey.currentState;
      if (mountedNavigator != null) {
        _openCaregiverSchedule(mountedNavigator, patientHash);
      }
    });
  }

  void _openSchedule(NavigatorState navigator) {
    if (_isScheduleRouteOpen) {
      navigator.popUntil(
        (route) => route.settings.name == _scheduleRouteName || route.isFirst,
      );
      return;
    }
    _isScheduleRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: _scheduleRouteName),
            builder: (context) => const CheckScheduleUI(),
          ),
        )
        .whenComplete(() => _isScheduleRouteOpen = false);
  }

  // 함수이름: _openCaregiverSchedule
  // 함수역할:
  // - 보호자 알림에 포함된 환자의 오늘 복약 일정 화면을 중복 없이 연다.
  // 매개변수:
  // - navigator: 앱 전역 Navigator 상태
  // - patientHash: 알림을 발생시킨 환자 식별 hash
  // 반환값:
  // - 없음
  void _openCaregiverSchedule(NavigatorState navigator, String patientHash) {
    final session = _authenticationControl.session;
    if (session == null) {
      return;
    }
    final routeName =
        '$_caregiverScheduleRoutePrefix${Uri.encodeComponent(patientHash)}';
    if (_openCaregiverScheduleRouteName == routeName) {
      navigator.popUntil(
        (route) => route.settings.name == routeName || route.isFirst,
      );
      return;
    }
    _openCaregiverScheduleRouteName = routeName;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: routeName),
            builder: (context) => CheckCaregiverMedicationUI(
              caregiverHash: session.userHash,
              patientHash: patientHash,
              userSetting: UserSetting(language: _appLanguageControl.language),
            ),
          ),
        )
        .whenComplete(() {
          if (_openCaregiverScheduleRouteName == routeName) {
            _openCaregiverScheduleRouteName = null;
          }
        });
  }

  // 함수명: _openLinkedChat
  // 역할:
  // - 채팅 알림에 포함된 연동 식별자의 대화 화면을 중복 없이 연다.
  void _openLinkedChat(NavigatorState navigator, int linkId) {
    final session = _authenticationControl.session;
    if (session == null) {
      return;
    }
    final routeName = '$_linkedChatRoutePrefix$linkId';
    if (_openLinkedChatRouteName == routeName) {
      navigator.popUntil(
        (route) => route.settings.name == routeName || route.isFirst,
      );
      return;
    }
    _openLinkedChatRouteName = routeName;
    navigator
        .push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: routeName),
            builder: (context) => LinkedChatUI(
              linkId: linkId,
              currentUserHash: session.userHash,
              userSetting: UserSetting(language: _appLanguageControl.language),
            ),
          ),
        )
        .whenComplete(() {
          if (_openLinkedChatRouteName == routeName) {
            _openLinkedChatRouteName = null;
          }
        });
  }

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
        builder: (context, authentication, appLanguage, _) {
          final session = authentication.session;
          final application = MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'MedBuddy',
            debugShowCheckedModeBanner: false,
            locale: Locale(appLanguage.language),
            supportedLocales: const [Locale('ko'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) {
              if (session == null) {
                return MedBuddyTextScale(
                  userSetting: UserSetting(language: appLanguage.language),
                  child: child ?? const SizedBox.shrink(),
                );
              }
              final viewModel = context.read<MedBuddyViewModel>();
              return ListenableBuilder(
                listenable: viewModel.updatesFor(MedBuddyFeature.userSetting),
                builder: (context, _) => MedBuddyTextScale(
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
            create: (_) {
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

  // 함수명: _loadUserSettingAndSyncLanguage
  // 역할:
  // - 로그인한 사용자의 설정을 ViewModel로 불러온다.
  // - 불러온 언어를 인증 화면에서도 사용하는 기기 공통 설정과 동기화한다.
  // 매개변수:
  // - viewModel: 로그인한 사용자의 MedBuddy 앱 상태
  // 반환값:
  // - 사용자 설정 조회와 언어 동기화 시도가 끝나면 완료된다.
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
