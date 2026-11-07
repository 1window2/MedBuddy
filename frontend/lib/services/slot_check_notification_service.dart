// 파일명: slot_check_notification_service.dart
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
import 'dose_home_widget_service.dart';
import 'dose_outbox_store.dart';
import 'dose_sync_background_service.dart';
import 'dose_sync_service.dart';
import 'firebase_runtime_service.dart';
import 'notification_inbox_store.dart';
import 'notification_service.dart';
import 'slot_check_notification_context.dart';
import 'user_setting_preference_keys.dart';

// 클래스명: SlotCheckNotificationPlatform
// 역할: 알림 버튼 처리가 쓰는 저장소·통신·작업 예약·알림 정리를 테스트에서 바꿀 수 있게 모은다.
class SlotCheckNotificationPlatform {
  const SlotCheckNotificationPlatform();

  // 함수이름: openStore
  // 함수역할: 다른 엔진과 겹치지 않게 열림 관문을 거쳐 전송 대기 저장소를 연다. 반환값: 저장소.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();

  // 함수이름: openClient
  // 함수역할: 백그라운드에서도 인증 헤더를 붙이는 통신 수단을 만든다. 반환값: HTTP 클라이언트.
  Future<http.Client> openClient() async {
    if (AuthConfig.mode == AuthenticationMode.firebase) {
      await FirebaseRuntimeService.initialize();
    }
    return AuthenticatedApiClient();
  }

  // 함수이름: scheduleSync
  // 함수역할: 연결되면 전송 대기 기록을 보내는 작업을 예약한다. 매개변수: owner 계정. 반환값: 예약 완료.
  Future<void> scheduleSync(String owner) =>
      DoseSyncBackgroundScheduler.register(owner);

  // 함수이름: dismiss
  // 함수역할: 확인 요청 알림 하나만 지운다. 매개변수: request 요청, id 알림 ID. 반환값: 정리 완료.
  Future<void> dismiss(SlotCheckNotificationContext request, int? id) async {
    if (id == null) return;
    await FlutterLocalNotificationsPlugin().cancel(
      id: id,
      tag: request.eventId,
    );
  }

  // 함수이름: refreshWidget
  // 함수역할: 기기에 저장한 복용을 통신 없이 홈 위젯에 반영한다. 반환값: 발행 완료.
  Future<void> refreshWidget() async {
    await DoseHomeWidget.publish();
  }

  // 함수이름: cancel
  // 함수역할: 기록을 저장한 요청의 알림과 같은 날짜·시간대의 복약 알림을 지운다.
  // 매개변수: request 요청, id 알림 ID. 반환값: 정리 완료.
  Future<void> cancel(SlotCheckNotificationContext request, int? id) async {
    await dismiss(request, id);
    await NotificationService.instance.cancelReminderForDate(
      owner: request.owner,
      slotKey: request.slotKey,
      date: DateTime.parse(request.scheduleDate),
    );
  }

  // 함수이름: refreshSchedule
  // 함수역할: 날짜가 명시된 서버 기간만 받아 자정에 늦게 끝난 조회를 오늘 일정으로 오인하지 않는다.
  // 매개변수: sync 동기화 서비스, client 통신 수단, day 요청 날짜. 반환값: 캐시 저장 완료.
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

// 클래스명: SlotCheckNotificationService
// 역할: 보호자의 시간대 확인 요청 푸시를 표시하고 복용 완료 버튼을 처리한다.
class SlotCheckNotificationService {
  @visibleForTesting
  static SlotCheckNotificationPlatform platform =
      const SlotCheckNotificationPlatform();
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // 함수이름: _isActiveOwner
  // 함수역할: 요청의 환자가 이 기기의 현재 계정인지 확인한다. 매개변수: request 요청. 반환값: 같으면 true.
  static Future<bool> _isActiveOwner(
    SlotCheckNotificationContext request,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(NotificationInboxStore.activeUserKey) ==
        request.owner;
  }

  // 함수이름: _isToday
  // 함수역할: 요청 날짜가 기기의 오늘 복약 날짜인지 확인한다. 매개변수: request 요청. 반환값: 같으면 true.
  static bool _isToday(SlotCheckNotificationContext request) =>
      request.scheduleDate == doseScheduleDay(clock());

  // 함수이름: _isCurrent
  // 함수역할: 현재 계정의 오늘 요청인지 확인한다. 매개변수: request 요청. 반환값: 둘 다 맞으면 true.
  static Future<bool> _isCurrent(SlotCheckNotificationContext request) async =>
      await _isActiveOwner(request) && _isToday(request);

  // 함수이름: display
  // 함수역할: 현재 계정에 온 확인 요청 푸시를 한 번만 표시한다. 오늘 요청에만 복용 완료 버튼을 붙이고,
  //   자정을 넘겨 도착한 요청은 버튼 없이 보여 보호자의 메시지가 사라지지 않게 한다.
  // 매개변수: data FCM 데이터. 반환값: 표시했으면 true.
  static Future<bool> display(Map<String, dynamic> data) async {
    final request = SlotCheckNotificationContext.fromData(data);
    if (request == null || !await _isActiveOwner(request)) return false;
    final actionable = _isToday(request);
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
          withTakenAction: actionable,
        );
      },
    );
  }

  // 함수이름: handle
  // 함수역할: 복용 완료 버튼을 오늘 일정의 해당 시간대 기록으로 암호화 대기열에 저장하고 전송을 시도한다.
  //   날짜가 지난 요청의 버튼은 기록하지 않고 알림만 지워, 눌러도 아무 일이 없는 버튼이 남지 않게 한다.
  // 매개변수: response 알림 동작 응답. 반환값: 기록을 저장했거나 이미 처리했으면 true.
  static Future<bool> handle(NotificationResponse response) async {
    if (response.actionId != SlotCheckNotificationContext.actionId) {
      return false;
    }
    final request = SlotCheckNotificationContext.fromPayload(response.payload);
    if (request == null || !await _isActiveOwner(request)) return false;
    if (request.scheduleDate.compareTo(doseScheduleDay(clock())) < 0) {
      try {
        await platform.dismiss(request, response.id);
      } catch (_) {}
      return false;
    }
    if (!_isToday(request)) return false;
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
      // 위젯은 다음 주기 작업(네트워크 필요)을 기다리지 않고 기기에 저장한 복용을 바로 보여 준다.
      try {
        await platform.refreshWidget();
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

// 함수이름: medBuddySlotCheckNotificationBackground
// 함수역할: 앱을 열지 않는 알림 버튼의 백그라운드 엔진 진입점이다. 매개변수: response 알림 동작 응답.
// 반환값: 처리 완료.
@pragma('vm:entry-point')
Future<void> medBuddySlotCheckNotificationBackground(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SlotCheckNotificationService.handle(response);
}
