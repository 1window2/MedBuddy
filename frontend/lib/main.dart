import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'boundaries/check_schedule_ui_boundary.dart';
import 'services/medication_notification_service.dart';
import 'theme/medbuddy_theme.dart';
import 'viewmodels/medbuddy_view_model.dart';
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
  await MedicationNotificationService.instance.initialize();
  runApp(const MedBuddyApp());
}

// 클래스명: MedBuddyApp
// 역할: 앱 전역 Provider와 MaterialApp 설정을 구성한다.
// 주요 책임:
// - MedBuddyViewModel을 앱 전역 상태로 등록한다.
// - 저장된 사용자 설정을 앱 시작 시 불러온다.
// - 홈 화면과 공통 테마를 설정한다.
class MedBuddyApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const MedBuddyApp({
    super.key,
    this.navigatorKey,
  });

  @override
  State<MedBuddyApp> createState() => _MedBuddyAppState();
}

class _MedBuddyAppState extends State<MedBuddyApp> {
  static const String _scheduleRouteName = '/schedule';

  late final GlobalKey<NavigatorState> _navigatorKey;
  bool _isScheduleRouteOpen = false;

  @override
  void initState() {
    super.initState();
    _navigatorKey = widget.navigatorKey ?? GlobalKey<NavigatorState>();
    MedicationNotificationService.setNotificationSelectionHandler(
      _handleNotificationSelection,
    );
  }

  @override
  void dispose() {
    MedicationNotificationService.setNotificationSelectionHandler(null);
    super.dispose();
  }

  void _handleNotificationSelection(
    MedicationNotificationDestination destination,
  ) {
    if (destination != MedicationNotificationDestination.schedule) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MedBuddyViewModel()..loadUserSetting(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'MedBuddy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: MedBuddyColors.primary,
          ),
          primaryColor: MedBuddyColors.primary,
          scaffoldBackgroundColor: MedBuddyColors.pageBackground,
          useMaterial3: true,
          fontFamilyFallback: const ['Noto Sans KR', 'Roboto', 'Arial'],
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
