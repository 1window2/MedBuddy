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
import '../entities/offline_schedule_window.dart';
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
// 주요 책임: 공유 저장소 열기, 인증 통신 준비, 복용 전송 예약, 해당 요청 알림 정리를 위임한다.
// 속성: 고유 상태 없음. 기본 구현은 플랫폼 플러그인과 공유 서비스를 사용한다.
class SlotCheckNotificationPlatform {
  // 함수이름: SlotCheckNotificationPlatform
  // 함수역할: 플랫폼 호출 어댑터를 만든다. 생성만으로 저장소나 네트워크를 열지 않는다.
  // 매개변수: 없음.
  // 반환값: 테스트에서 동작을 대체할 수 있는 무상태 어댑터.
  const SlotCheckNotificationPlatform();

  // 함수이름: openStore
  // 함수역할: 복약 확인 동작을 기록할 공유 영속 전송 대기 저장소를 연다.
  // 매개변수: 없음.
  // 반환값: Future<DoseOutboxStore>: 열린 저장소; 열기 실패는 전파된다.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();

  // 함수이름: openClient
  // 함수역할: Firebase 인증 모드에서는 런타임 초기화 후 인증 HTTP 클라이언트를 생성한다.
  // 매개변수: 없음.
  // 반환값: Future<http.Client>: 호출자가 닫아야 하는 새 클라이언트; 초기화 실패는 전파된다.
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

  // Function Name: dismiss
  // Description: Dismiss the tagged slot-check notification when a platform ID is available.
  // Parameters: request (SlotCheckNotificationContext): event tag; id (int?): platform notification ID.
  // Returns: Future<void>: cancellation completion, no-op for null ID.
  Future<void> dismiss(SlotCheckNotificationContext request, int? id) async {
    if (id == null) return;
    await FlutterLocalNotificationsPlugin().cancel(
      id: id,
      tag: request.eventId,
    );
  }

  // Function Name: refreshWidget
  // Description: Publish the current persisted dose projection to the home widget.
  // Parameters: None.
  // Returns: Future<void>: widget publication completion.
  Future<void> refreshWidget() async {
    await DoseHomeWidget.publish();
  }

  // Function Name: cancel
  // Description: Dismiss the request notification and cancel the matching owner's slot reminder for its date.
  // Parameters: request (SlotCheckNotificationContext): owner, slot, event and date; id (int?): request notification ID.
  // Returns: Future<void>: both cancellations complete; failures propagate.
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
            queryParameters: {
              'patient_hash': sync.owner,
              'days': '${OfflineScheduleWindow.maximumDays}',
            },
          ),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw StateError('Schedule lookup failed');
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final end = addCalendarDays(
      DateTime.parse(day),
      OfflineScheduleWindow.maximumDays - 1,
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

// Class Name: SlotCheckNotificationService
// Role: Display and handle linked slot-check notifications under active-owner and current-day guards.
// Responsibilities: Deduplicate display, record durable dose intent and perform best-effort sync, reminder cancellation and widget refresh.
// Attributes: platform (SlotCheckNotificationPlatform): injectable side effects; clock (DateTime Function()): day validation clock.
class SlotCheckNotificationService {
  @visibleForTesting
  static SlotCheckNotificationPlatform platform =
      const SlotCheckNotificationPlatform();
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // Function Name: _isActiveOwner
  // Description: Reload preferences before comparing the request owner with the active notification session.
  // Parameters: request (SlotCheckNotificationContext): expected owner.
  // Returns: Future<bool>: persisted owner match.
  static Future<bool> _isActiveOwner(
    SlotCheckNotificationContext request,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(NotificationInboxStore.activeUserKey) ==
        request.owner;
  }

  // Function Name: _isToday
  // Description: Compare the request date with the current application schedule day.
  // Parameters: request (SlotCheckNotificationContext): dated request.
  // Returns: bool: current-day match.
  static bool _isToday(SlotCheckNotificationContext request) =>
      request.scheduleDate == doseScheduleDay(clock());

  // Function Name: _isCurrent
  // Description: Require both persisted active ownership and the current schedule day.
  // Parameters: request (SlotCheckNotificationContext): candidate action.
  // Returns: Future<bool>: action is current.
  static Future<bool> _isCurrent(SlotCheckNotificationContext request) async =>
      await _isActiveOwner(request) && _isToday(request);

  // Function Name: display
  // Description: Display a valid active-owner request once using an event digest; older/future dates remain visible without the Taken action.
  // Parameters: data (Map<String, dynamic>): request context, language and optional preview.
  // Returns: Future<bool>: deduplicated display result; invalid or wrong-owner data returns false.
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

  // Function Name: handle
  // Description: Handle Taken only for today's active owner; restore/refresh cache, record durable intent, then attempt cleanup and synchronization. Dismiss expired requests without recording.
  // Parameters: response (NotificationResponse): platform action and request payload.
  // Returns: Future<bool>: true after durable recording, including idempotent replay; false for invalid/stale/failed recording. Post-record side-effect failures are best effort.
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
