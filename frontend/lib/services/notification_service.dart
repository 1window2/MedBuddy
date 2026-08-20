import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../entities/medication_alarm_entity.dart';

enum MedicationNotificationDestination { schedule, caregiverSchedule }

// 클래스명: MedicationNotificationSelection
// 역할: 사용자가 누른 알림의 이동 화면과 선택 환자를 함께 전달한다.
class MedicationNotificationSelection {
  final MedicationNotificationDestination destination;
  final String? patientHash;

  const MedicationNotificationSelection({
    required this.destination,
    this.patientHash,
  });
}

typedef MedicationNotificationSelectionHandler =
    void Function(MedicationNotificationSelection selection);

// 파일명: notification_service.dart
// 역할: 복약 알림을 휴대폰 로컬 알림으로 예약하고 취소한다.

// 클래스명: NotificationService
// 역할: Flutter local notifications 플러그인을 감싸 복약 알림 전용 API를 제공한다.
// 주요 책임:
// - 앱 시작 시 알림 플러그인과 한국 시간대를 초기화한다.
// - 알림 권한을 요청한다.
// - 복용 기간에 포함된 날짜만 시간대별 알림으로 예약하거나 취소한다.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static MedicationNotificationSelectionHandler? _selectionHandler;
  static MedicationNotificationSelection? _pendingSelection;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  static void setNotificationSelectionHandler(
    MedicationNotificationSelectionHandler? handler,
  ) {
    _selectionHandler = handler;
    final pendingSelection = _pendingSelection;
    if (handler == null || pendingSelection == null) {
      return;
    }
    _pendingSelection = null;
    handler(pendingSelection);
  }

  static MedicationNotificationDestination? destinationFromPayload(
    String? payload,
  ) {
    return selectionFromPayload(payload)?.destination;
  }

  // 함수명: selectionFromPayload
  // 함수역할:
  // - 일반 복약 알림과 보호자 알림 payload를 안전한 화면 이동 정보로 변환한다.
  // 매개변수:
  // - payload: 로컬 알림 또는 FCM 데이터에서 받은 문자열
  // 반환값:
  // - 유효한 이동 대상과 환자 hash, 형식이 잘못됐으면 null
  static MedicationNotificationSelection? selectionFromPayload(
    String? payload,
  ) {
    final segments = payload?.split(':') ?? const <String>[];
    if (segments.length == 3 &&
        segments[0] == 'schedule' &&
        segments[1].trim().isNotEmpty) {
      final notificationID = int.tryParse(segments[2]);
      if (notificationID == null || notificationID < 0) {
        return null;
      }
      return const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
      );
    }
    if (segments.length == 2 &&
        segments[0] == 'caregiver' &&
        segments[1].trim().isNotEmpty) {
      try {
        final patientHash = Uri.decodeComponent(segments[1]).trim();
        if (patientHash.isEmpty) {
          return null;
        }
        return MedicationNotificationSelection(
          destination: MedicationNotificationDestination.caregiverSchedule,
          patientHash: patientHash,
        );
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static void handleNotificationPayload(String? payload) {
    final selection = selectionFromPayload(payload);
    if (selection == null) {
      return;
    }
    final handler = _selectionHandler;
    if (handler == null) {
      _pendingSelection = selection;
      return;
    }
    handler(selection);
  }

  // 함수명: initialize
  // 함수역할:
  // - 알림 플러그인과 timezone 패키지를 한 번만 초기화한다.
  // 반환값:
  // - 없음
  Future<void> initialize() {
    if (_isInitialized) {
      return Future<void>.value();
    }
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      timezone_data.initializeTimeZones();
      timezone.setLocalLocation(timezone.getLocation('Asia/Seoul'));

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _isInitialized = true;

      if (launchDetails?.didNotificationLaunchApp ?? false) {
        handleNotificationPayload(launchDetails?.notificationResponse?.payload);
      }
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    handleNotificationPayload(response.payload);
  }

  // 함수명: requestPermission
  // 함수역할:
  // - Android/iOS에서 알림 표시 권한을 요청한다.
  // 반환값:
  // - 알림 표시 권한이 허용되었거나 권한 요청이 필요 없는 플랫폼이면 True
  Future<bool> requestPermission() async {
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.requestNotificationsPermission() ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }

    return true;
  }

  // 함수명: registerNotification
  // 함수역할:
  // - 복용 기간에 포함된 날짜 중 지정한 시간에만 복약 알림을 예약한다.
  // 매개변수:
  // - id: 시간대별 고정 알림 id
  // - slotTitle: 아침, 점심 등 시간대명
  // - hour: 24시간 기준 시
  // - minute: 분
  // - medicationNames: 알림 본문에 보여줄 약 이름 목록
  // - activeDates: 이 시간대 알림이 필요한 복용 날짜 목록
  // - language: 알림 제목과 안내 문장에 사용할 언어 코드
  // 반환값:
  // - 없음
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    String language = 'ko',
  }) async {
    await initialize();
    await _cancelScheduledNotificationsForSlot(slotKey, legacyId: id);
    final now = timezone.TZDateTime.now(timezone.local);
    final body = _buildReminderBody(medicationNames, language);
    final uniqueDates = <String, DateTime>{};
    for (final activeDate in activeDates) {
      final normalizedDate = DateTime(
        activeDate.year,
        activeDate.month,
        activeDate.day,
      );
      uniqueDates[_dateKey(normalizedDate)] = normalizedDate;
    }
    final sortedDates = uniqueDates.values.toList(growable: false)..sort();

    for (final activeDate in sortedDates) {
      final scheduledDate = timezone.TZDateTime(
        timezone.local,
        activeDate.year,
        activeDate.month,
        activeDate.day,
        hour,
        minute,
      );
      if (!scheduledDate.isAfter(now)) {
        continue;
      }
      final notificationId = _notificationIdForDate(id, slotKey, activeDate);
      try {
        await _scheduleWithMode(
          id: notificationId,
          slotKey: slotKey,
          slotTitle: slotTitle,
          language: language,
          body: body,
          scheduledDate: scheduledDate,
          scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } on PlatformException {
        await _scheduleWithMode(
          id: notificationId,
          slotKey: slotKey,
          slotTitle: slotTitle,
          language: language,
          body: body,
          scheduledDate: scheduledDate,
          scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  // 함수명: _cancelScheduledNotificationsForSlot
  // 함수역할:
  // - 같은 시간대에 남아 있는 기존 반복 알림과 날짜별 단발 알림을 모두 취소한다.
  Future<void> _cancelScheduledNotificationsForSlot(
    String slotKey, {
    int? legacyId,
  }) async {
    if (legacyId != null) {
      await _plugin.cancel(id: legacyId);
    }
    final pendingRequests = await _plugin.pendingNotificationRequests();
    final payloadPrefix = 'schedule:$slotKey:';
    for (final request in pendingRequests) {
      if (request.payload?.startsWith(payloadPrefix) ?? false) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // 함수명: _notificationIdForDate
  // 함수역할:
  // - 시간대와 복용 날짜마다 충돌 가능성이 낮은 고정 알림 ID를 생성한다.
  int _notificationIdForDate(int baseId, String slotKey, DateTime date) {
    final source = '$baseId|$slotKey|${_dateKey(date)}';
    var hash = 0x811C9DC5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 100000 + (hash % 2000000000);
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
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    await initialize();
    if (slotKey != null && slotKey.trim().isNotEmpty) {
      await _cancelScheduledNotificationsForSlot(slotKey, legacyId: id);
      return;
    }
    await _plugin.cancel(id: id);
  }

  // Function Name: cancelAllMedicationReminders
  // Description:
  // - Cancels every pending patient medication reminder before session exit.
  // - Leaves caregiver alerts and unrelated application notifications intact.
  // Returns:
  // - Completes after date-specific and legacy reminder IDs are removed.
  Future<void> cancelAllMedicationReminders() async {
    await initialize();
    final pendingRequests = await _plugin.pendingNotificationRequests();
    for (final request in pendingRequests) {
      if (request.payload?.startsWith('schedule:') ?? false) {
        await _plugin.cancel(id: request.id);
      }
    }
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      await _plugin.cancel(
        id: MedicationAlarm.legacyNotificationIdForSlot(slotKey),
      );
    }
    if (_pendingSelection?.destination ==
        MedicationNotificationDestination.schedule) {
      _pendingSelection = null;
    }
  }

  // 함수명: showCaregiverAlert
  // 역할:
  // - 환자의 복약 체크 변화를 보호자 기기의 즉시 로컬 알림으로 표시한다.
  // 매개변수:
  // - id: 중복 알림을 교체하기 위한 고정 알림 식별자
  // - title: 보호자 알림 제목
  // - body: 보호자에게 보여줄 복약 상태 설명
  // - patientHash: 알림을 누를 때 열어야 하는 환자 식별 hash
  // 반환값:
  // - 없음
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
  }) async {
    await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medbuddy_caregiver_updates',
          '보호자 복약 확인',
          channelDescription: '연동된 환자의 복약 완료 및 미복용 상태 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: patientHash == null || patientHash.trim().isEmpty
          ? null
          : 'caregiver:${Uri.encodeComponent(patientHash.trim())}',
    );
  }
}
