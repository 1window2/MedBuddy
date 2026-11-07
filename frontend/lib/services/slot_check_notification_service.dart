// 역할: 확인 요청을 앱 화면 없이 표시하고 복용 버튼을 기존 암호화 전송 대기열로 연결한다.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/calendar_days.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';
import 'api_config.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'caregiver_alert_delivery_service.dart';
import 'dose_outbox_store.dart';
import 'dose_sync_background_service.dart';
import 'dose_sync_service.dart';
import 'firebase_runtime_service.dart';
import 'notification_inbox_store.dart';
import 'notification_service.dart';
import 'slot_check_notification_context.dart';
import 'user_setting_preference_keys.dart';

class SlotCheckNotificationPlatform {
  const SlotCheckNotificationPlatform();

  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();
  Future<http.Client> openClient() async {
    if (AuthConfig.mode == AuthenticationMode.firebase) {
      await FirebaseRuntimeService.initialize();
    }
    return AuthenticatedApiClient();
  }

  Future<void> scheduleSync(String owner) =>
      DoseSyncBackgroundScheduler.register(owner);
  Future<void> cancel(SlotCheckNotificationContext request, int? id) async {
    if (id != null) {
      await FlutterLocalNotificationsPlugin().cancel(
        id: id,
        tag: request.eventId,
      );
    }
    await NotificationService.instance.cancelReminderForDate(
      owner: request.owner,
      slotKey: request.slotKey,
      date: DateTime.parse(request.scheduleDate),
    );
  }

  // 날짜가 명시된 서버 기간만 받아 자정에 늦게 끝난 조회를 오늘 일정으로 오인하지 않는다.
  Future<void> refreshSchedule(
    DoseSyncService sync,
    http.Client client,
    String day,
  ) async {
    final revision = await sync.cacheRevision();
    final response = await client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/schedule/window').replace(
            queryParameters: {'patient_hash': sync.owner, 'days': '14'},
          ),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw StateError('Schedule lookup failed');
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final end = addCalendarDays(
      DateTime.parse(day),
      13,
    ).toIso8601String().substring(0, 10);
    if (body is! Map ||
        body['success'] != true ||
        body['data'] is! List ||
        body['window_start'] != day ||
        body['window_end'] != end) {
      throw const FormatException('Invalid schedule window');
    }
    await sync.cacheScheduleWindow(
      MedicationSchedule.fromScheduleJsonList(body['data']),
      startDay: day,
      expectedRevision: revision,
    );
  }
}

class SlotCheckNotificationService {
  @visibleForTesting
  static SlotCheckNotificationPlatform platform =
      const SlotCheckNotificationPlatform();
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Future<bool> _isCurrent(SlotCheckNotificationContext request) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(NotificationInboxStore.activeUserKey) ==
            request.owner &&
        request.scheduleDate == doseScheduleDay(clock());
  }

  static Future<bool> display(Map<String, dynamic> data) async {
    final request = SlotCheckNotificationContext.fromData(data);
    if (request == null || !await _isCurrent(request)) return false;
    final digest = (await Sha256().hash(utf8.encode(request.eventId))).bytes;
    final key = digest
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return CaregiverAlertDeliveryService.presentCompletionOnce(
      recipientHash: request.owner,
      eventKey: key,
      present: () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        final details =
            preferences.getString(
              UserSettingPreference.notificationDetailMode.keyFor(
                request.owner,
              ),
            ) !=
            'type_only';
        final language = normalizeAppLanguage(data['language']?.toString());
        await NotificationService.instance.showSlotCheckAlert(
          request: request,
          id:
              digest
                  .take(4)
                  .fold<int>(0, (value, byte) => (value << 8) | byte) &
              0x7fffffff,
          language: language,
          messagePreview: details ? data['message_preview']?.toString() : null,
        );
      },
    );
  }

  static Future<bool> handle(NotificationResponse response) async {
    if (response.actionId != SlotCheckNotificationContext.actionId) {
      return false;
    }
    final request = SlotCheckNotificationContext.fromPayload(response.payload);
    if (request == null || !await _isCurrent(request)) return false;
    http.Client? client;
    DoseSyncService? sync;
    try {
      final store = await platform.openStore();
      // 백그라운드 작업은 계정을 활성화하지 않는다. 로그아웃·전환 시 기존 작업을 거부한다.
      if (!await store.isActive(request.owner)) return false;
      await DoseSyncService.prepareOfflineCache(
        store,
        owner: request.owner,
        now: clock(),
      );
      if ((await store.readCache(request.owner))?['date'] !=
          request.scheduleDate) {
        client = await platform.openClient();
        sync = DoseSyncService(
          owner: request.owner,
          client: client,
          openStore: () async => store,
          clock: clock,
        );
        await platform.refreshSchedule(sync, client, request.scheduleDate);
        await DoseSyncService.prepareOfflineCache(
          store,
          owner: request.owner,
          now: clock(),
        );
      }
      if (!await _isCurrent(request) ||
          !await store.recordSlotCheck(request, clock: clock)) {
        return false;
      }
      // 저장 이후의 예약·인증·통신 실패는 기록을 버리지 않고 다음 전송 기회에 재시도한다.
      try {
        await platform.scheduleSync(request.owner);
      } catch (_) {}
      try {
        await platform.cancel(request, response.id);
      } catch (_) {}
      try {
        client ??= await platform.openClient();
        sync ??= DoseSyncService(
          owner: request.owner,
          client: client,
          openStore: () async => store,
          clock: clock,
        );
        await sync.drain();
      } catch (_) {}
      return true;
    } catch (error) {
      debugPrint('복용 알림 처리 실패: ${error.runtimeType}');
      return false;
    } finally {
      sync?.dispose();
      client?.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> medBuddySlotCheckNotificationBackground(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SlotCheckNotificationService.handle(response);
}
