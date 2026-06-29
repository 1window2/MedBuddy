import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

// 파일명: medication_notification_service.dart
// 역할: 복약 알림을 휴대폰 로컬 알림으로 예약하고 취소한다.

// 클래스명: MedicationNotificationService
// 역할: Flutter local notifications 플러그인을 감싸 복약 알림 전용 API를 제공한다.
// 주요 책임:
// - 앱 시작 시 알림 플러그인과 한국 시간대를 초기화한다.
// - 알림 권한을 요청한다.
// - 시간대별 매일 반복 알림을 예약하거나 취소한다.
class MedicationNotificationService {
  MedicationNotificationService._();

  static final MedicationNotificationService instance =
      MedicationNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // 함수명: initialize
  // 함수역할:
  // - 알림 플러그인과 timezone 패키지를 한 번만 초기화한다.
  // 반환값:
  // - 없음
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Asia/Seoul'));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _isInitialized = true;
  }

  // 함수명: requestPermission
  // 함수역할:
  // - Android/iOS에서 알림 표시 권한을 요청한다.
  // 반환값:
  // - 알림 표시 권한이 허용되었거나 권한 요청이 필요 없는 플랫폼이면 True
  Future<bool> requestPermission() async {
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.requestNotificationsPermission() ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }

    return true;
  }

  // 함수명: scheduleDailyReminder
  // 함수역할:
  // - 지정한 시간에 매일 반복되는 복약 알림을 예약한다.
  // 매개변수:
  // - id: 시간대별 고정 알림 id
  // - slotTitle: 아침, 점심 등 시간대명
  // - hour: 24시간 기준 시
  // - minute: 분
  // - medicationNames: 알림 본문에 보여줄 약 이름 목록
  // - language: 알림 제목과 안내 문장에 사용할 언어 코드
  // 반환값:
  // - 없음
  Future<void> scheduleDailyReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) async {
    await initialize();
    await _plugin.cancel(id: id);

    final now = timezone.TZDateTime.now(timezone.local);
    var scheduledDate = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final body = _buildReminderBody(medicationNames, language);

    try {
      await _scheduleWithMode(
        id: id,
        slotKey: slotKey,
        slotTitle: slotTitle,
        language: language,
        body: body,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException {
      await _scheduleWithMode(
        id: id,
        slotKey: slotKey,
        slotTitle: slotTitle,
        language: language,
        body: body,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  // 함수명: _buildReminderBody
  // 함수역할:
  // - 알림 본문을 긴 약품명 나열 대신 사용자가 바로 이해할 수 있는 문장으로 만든다.
  // 매개변수:
  // - medicationNames: 해당 시간대에 복용할 약 이름 목록
  // - language: 안내 문장에 사용할 언어 코드
  // 반환값:
  // - 알림 본문 문자열
  String _buildReminderBody(List<String> medicationNames, String language) {
    final isEnglish = _isEnglish(language);
    final names = medicationNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return isEnglish ? 'Please check your medication.' : '복용할 약을 확인해 주세요.';
    }

    final representativeName = _shortenMedicationName(names.first);
    if (names.length == 1) {
      return isEnglish
          ? 'Time to take $representativeName.'
          : '$representativeName 복용 시간입니다.';
    }
    return isEnglish
        ? 'Time to take $representativeName and ${names.length - 1} more.'
        : '$representativeName 외 ${names.length - 1}개 약을 복용할 시간입니다.';
  }

  bool _isEnglish(String language) {
    return language.trim().toLowerCase().startsWith('en');
  }

  // 함수명: _shortenMedicationName
  // 함수역할:
  // - 알림창에서 한눈에 보이도록 긴 약품명을 짧게 줄인다.
  // 매개변수:
  // - medicationName: 원본 약품명
  // 반환값:
  // - 알림용으로 축약한 약품명
  String _shortenMedicationName(String medicationName) {
    const maxLength = 14;
    if (medicationName.length <= maxLength) {
      return medicationName;
    }
    return '${medicationName.substring(0, maxLength)}...';
  }

  // 함수명: _scheduleWithMode
  // 함수역할:
  // - Android 예약 모드를 주입받아 실제 로컬 알림 예약을 수행한다.
  // 매개변수:
  // - id: 시간대별 고정 알림 id
  // - slotTitle: 알림 제목에 들어갈 시간대명
  // - language: 알림 제목에 사용할 언어 코드
  // - body: 알림 본문
  // - scheduledDate: 예약 기준 시각
  // - scheduleMode: Android 알림 예약 방식
  // 반환값:
  // - 없음
  Future<void> _scheduleWithMode({
    required int id,
    required String slotKey,
    required String slotTitle,
    required String language,
    required String body,
    required timezone.TZDateTime scheduledDate,
    required AndroidScheduleMode scheduleMode,
  }) async {
    final title = _isEnglish(language)
        ? '$slotTitle medication time'
        : '$slotTitle 복약 시간입니다';

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medbuddy_medication_reminders',
          '복약 알림',
          channelDescription: 'MedBuddy 복약 시간 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'schedule:$slotKey:$id',
    );
  }

  // 함수명: cancelReminder
  // 함수역할:
  // - 지정한 복약 알림 예약을 취소한다.
  // 매개변수:
  // - id: 취소할 알림 id
  // 반환값:
  // - 없음
  Future<void> cancelReminder(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }
}
