// 파일명: dose_home_widget_service.dart
// 역할: 암호화된 복약 상태를 Android 위젯에 전달하고 백그라운드 요청을 처리한다.
// PendingIntent에는 불투명 토큰만 전달하며 계정과 약 ID는 암호화 저장소에 둔다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/dose_widget_state.dart';
import '../entities/medication_schedule_entity.dart';
import 'app_language_resolver.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'dose_outbox_store.dart';
import 'dose_sync_background_service.dart';
import 'dose_sync_service.dart';
import 'firebase_runtime_service.dart';
import 'notification_service.dart';

// Function Name: DoseWidgetTodayScheduleReader
// Description: Loads this account's schedule snapshot through the control supplied by composition.
// Parameters: owner (String): Patient account; client (http.Client): Caller-owned authenticated transport.
// Returns: Future schedule list; retrieval failures propagate to the widget refresh flow.
typedef DoseWidgetTodayScheduleReader =
    Future<List<MedicationSchedule>> Function(String owner, http.Client client);

// Function Name: DoseWidgetPatientSnapshotReader
// Description: Loads linked-patient monitoring snapshots for the caregiver widget.
// Parameters: owner (String): Caregiver account; client (http.Client): Caller-owned authenticated transport.
// Returns: Future linked-patient snapshots; the control implementation supplies scope and errors.
typedef DoseWidgetPatientSnapshotReader =
    Future<List<CaregiverMonitoringSnapshot>> Function(
      String owner,
      http.Client client,
    );

// Class Name: DoseHomeWidgetPlatform
// Role: Adapts the native home-widget, outbox, reminder, and upload scheduling services.
// Responsibilities: Expose replaceable platform operations for tests while keeping account-sensitive data in the encrypted store.
// Attributes: None; the adapter delegates to shared platform services.
class DoseHomeWidgetPlatform {
  // Function Name: DoseHomeWidgetPlatform
  // Description: Creates a stateless adapter without opening storage or invoking Android.
  // Parameters: None.
  // Returns: A reusable platform adapter.
  const DoseHomeWidgetPlatform();

  // Function Name: supported
  // Description: Limits native widget operations to Android outside web builds.
  // Parameters: None.
  // Returns: True only on supported native Android.
  bool get supported => !kIsWeb && Platform.isAndroid;

  // Function Name: readJournal
  // Description: Reads the action journal Android persisted before requesting Dart processing.
  // Parameters: None.
  // Returns: JSON journal string, defaulting to an empty array; plugin errors propagate.
  Future<String?> readJournal() => HomeWidget.getWidgetData<String>(
    DoseHomeWidget.journalKey,
    defaultValue: '[]',
  );

  // Function Name: saveState
  // Description: Stores the JSON projection for the native widget without triggering repaint.
  // Parameters: state (String): Serialized display state and handled action tokens.
  // Returns: Persistence completion; plugin errors propagate.
  Future<void> saveState(String state) =>
      HomeWidget.saveWidgetData<String>(DoseHomeWidget.stateKey, state);

  // Function Name: updateWidget
  // Description: Asks the Android provider to redraw from the saved display state.
  // Parameters: None.
  // Returns: Refresh-request completion, not confirmation that the launcher has painted it.
  Future<void> updateWidget() =>
      HomeWidget.updateWidget(qualifiedAndroidName: DoseHomeWidget.provider);

  // Function Name: scheduleUpdate
  // Description: Requests a provider refresh at the projection's expiration time.
  // Parameters: at (DateTime): Next refresh instant, typically the next dose-day boundary.
  // Returns: Platform scheduling completion; Android controls actual delivery.
  Future<void> scheduleUpdate(DateTime at) => HomeWidget.scheduleWidgetUpdates([
    at,
  ], qualifiedAndroidName: DoseHomeWidget.provider);

  // Function Name: cancelScheduledUpdates
  // Description: Removes scheduled refreshes for the dose widget provider.
  // Parameters: None.
  // Returns: Cancellation completion; existing widget state and queued dose operations are unchanged.
  Future<void> cancelScheduledUpdates() =>
      HomeWidget.cancelScheduledWidgetUpdates(
        qualifiedAndroidName: DoseHomeWidget.provider,
      );

  // Function Name: hasInstalledWidget
  // Description: Checks whether the plugin reports any installed home-widget instances.
  // Parameters: None.
  // Returns: True for a nonempty installed-widget list; plugin errors propagate.
  Future<bool> hasInstalledWidget() async =>
      (await HomeWidget.getInstalledWidgets()).isNotEmpty;

  // Function Name: openStore
  // Description: Opens the encrypted outbox shared with foreground and background recording.
  // Parameters: None.
  // Returns: Shared outbox store Future; initialization errors propagate.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();

  // Function Name: cancelReminder
  // Description: Cancels the reminder for a locally completed account/date/slot through the notification service.
  // Parameters: owner/slotKey (String): Account and dose slot; date (DateTime): Dose date.
  // Returns: Cancellation completion; notification ownership checks and errors belong to the delegated service.
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) => NotificationService.instance.cancelReminderForDate(
    owner: owner,
    slotKey: slotKey,
    date: date,
  );

  // Function Name: registerSync
  // Description: Requests one-off and periodic uploads for operations accepted from widget actions.
  // Parameters: owner (String): Account owning the dose operations.
  // Returns: Registration completion, not upload acknowledgement.
  Future<void> registerSync(String owner) =>
      DoseSyncBackgroundScheduler.register(owner);

  // Function Name: openClient
  // Description: Initializes Firebase when required and creates an authenticated transport for background use.
  // Parameters: None.
  // Returns: A new client that the caller must close; Firebase initialization failures propagate.
  Future<http.Client> openClient() async {
    if (AuthConfig.mode == AuthenticationMode.firebase) {
      await FirebaseRuntimeService.initialize();
    }
    return AuthenticatedApiClient();
  }
}

// Class Name: DoseHomeWidget
// Role: Publishes safe widget projections and coordinates foreground/background refreshes.
// Responsibilities: Apply journal actions durably, distinguish self-recording from caregiver viewing, and refresh only when needed.
// Attributes: platform: Replaceable adapter; provider/stateKey/journalKey: Native identifiers; readTodaySchedules/readScheduleWindow/readPatientSnapshots: Composition loaders; _cancelledReminderSlots: Per-day cancellation memory.
class DoseHomeWidget {
  static const provider = 'com.example.medbuddy_frontend.DoseWidgetProvider';
  static const stateKey = 'dose_widget_state';
  static const journalKey = 'dose_widget_actions';
  // 테스트에서만 교체한다.
  static DoseHomeWidgetPlatform platform = const DoseHomeWidgetPlatform();
  // 서버 조회 함수. 앱 시작과 두 백그라운드 진입점에서 조립 계층이 채우며, 비어 있으면 서버 조회를 실패로 처리한다.
  static DoseWidgetTodayScheduleReader? readTodaySchedules;
  static DoseWidgetTodayScheduleReader? readScheduleWindow;
  static DoseWidgetPatientSnapshotReader? readPatientSnapshots;
  // Function Name: supported
  // Description: Delegates widget capability to the installed platform adapter.
  // Parameters: None.
  // Returns: Whether native widget operations should run.
  static bool get supported => platform.supported;
  // 이 실행 환경에서 재알림을 이미 취소한 시간대. 키는 "계정|날짜"이며 현재 것만 보관한다.
  static final Map<String, Set<String>> _cancelledReminderSlots = {};

  // Function Name: resetForTest
  // Description: Restores the default platform adapter and clears remembered reminder cancellations between tests.
  // Parameters: None.
  // Returns: Nothing; injected schedule-reader callbacks are not reset here.
  @visibleForTesting
  static void resetForTest() {
    platform = const DoseHomeWidgetPlatform();
    _cancelledReminderSlots.clear();
  }

  // Function Name: initialize
  // Description: Registers the composition-provided background interactivity callback on supported platforms.
  // Parameters: callback (Future<void> Function(Uri?)): Top-level widget action entry point.
  // Returns: Registration completion, or a no-op when unsupported; plugin errors propagate.
  static Future<void> initialize(
    Future<void> Function(Uri? uri) callback,
  ) async {
    if (supported) {
      await HomeWidget.registerInteractivityCallback(callback);
    }
  }

  // Function Name: _journalActions
  // Description: Decodes the native journal and keeps map-shaped entries without consuming or acknowledging them.
  // Parameters: None.
  // Returns: Journal map entries; absent storage is empty, but invalid JSON or a non-list root throws.
  static Future<List<Map>> _journalActions() async {
    final journal = await platform.readJournal();
    return (jsonDecode(journal ?? '[]') as List).whereType<Map>().toList();
  }

  // 함수이름: publish
  // 함수역할: Android에 먼저 저장한 클릭을 검증·반영하고 최신 위젯 상태를 발행한다.
  // 매개변수: owner - 계정, configuration - 표시 설정, patientCache - 환자 조회 결과,
  //           expectedPatientRevision - 조회 당시 버전. 반환값: 발행 상태 또는 null.
  // 도중 종료된 요청도 다음 위젯·앱·주기 갱신에서 같은 토큰으로 이어서 처리한다.
  static Future<DoseWidgetState?> publish({
    String? owner,
    Map<String, dynamic>? configuration,
    Map<String, dynamic>? patientCache,
    String? expectedPatientRevision,
  }) async {
    if (!supported) return null;
    final store = await platform.openStore();
    await DoseSyncService.prepareOfflineCache(
      store,
      owner: owner,
      now: DateTime.now(),
    );
    final actions = await _journalActions();
    final handled = <String>[];
    for (final entry in actions) {
      final token = entry['token']?.toString();
      if (token == null) continue;
      await store.updateWidget(
        owner: owner,
        now: DateTime.now(),
        action: entry['action']?.toString(),
        actionToken: token,
        configuration: configuration,
      );
      handled.add(token);
    }
    final state = await store.updateWidget(
      owner: owner,
      now: DateTime.now(),
      configuration: configuration,
      patientCache: patientCache,
      expectedPatientRevision: expectedPatientRevision,
    );
    if (state == null && owner != null) return null;
    await platform.saveState(jsonEncode({...?state?.view, 'handled': handled}));
    await platform.updateWidget();
    if (state != null) {
      // 서버 응답을 기다리지 않고, 기기에 확정한 완료 기록으로 재알림을 취소한다.
      // 취소 실패가 위젯 표시나 전송 대기 기록을 막지 않으며 다음 갱신에서 재시도한다.
      try {
        await _cancelCompletedReminders(state);
      } catch (error) {
        debugPrint('Widget reminder cancellation failed: ${error.runtimeType}');
      }
      await platform.scheduleUpdate(
        DateTime.fromMillisecondsSinceEpoch(state.view['expires'] as int),
      );
    }
    if (handled.isNotEmpty && state != null) {
      await platform.registerSync(state.data['owner'] as String);
    }
    return state;
  }

  // Function Name: _cancelCompletedReminders
  // Description: Cancels each completed dose slot once per account/day, allowing another cancellation after a completion is undone and later repeated.
  // Parameters: state (DoseWidgetState): Newly published projection containing owner and date.
  // Returns: Completion after successful cancellations; failed slots are not remembered and can retry on the next publish.
  static Future<void> _cancelCompletedReminders(DoseWidgetState state) async {
    final owner = state.data['owner'] as String;
    final date = state.view['date'] as String;
    final completed = state.completedReminderSlots(DateTime.now()).toList();
    final key = '$owner|$date';
    _cancelledReminderSlots.removeWhere((other, _) => other != key);
    final cancelled = _cancelledReminderSlots.putIfAbsent(key, () => {});
    cancelled.retainAll(completed);
    for (final slot in completed) {
      if (cancelled.contains(slot)) continue;
      await platform.cancelReminder(
        owner: owner,
        slotKey: slot,
        date: DateTime.parse(date),
      );
      cancelled.add(slot);
    }
  }

  // Function Name: _hasInstalledWidget
  // Description: Checks native widget presence conservatively so a plugin inspection failure does not prevent refresh.
  // Parameters: None.
  // Returns: Reported presence, or true if inspection throws.
  static Future<bool> _hasInstalledWidget() async {
    try {
      return await platform.hasInstalledWidget();
    } catch (_) {
      return true;
    }
  }

  // Function Name: needsNetworkRefresh
  // Description: Checks local upload eligibility, widget actions, and projection freshness before preparing authentication/network work.
  // Parameters: owner (String): Account attached to the scheduled job.
  // Returns: True for eligible uploads, journal actions, stale owned widget snapshots, or inspection failure; otherwise false.
  static Future<bool> needsNetworkRefresh(String owner) async {
    try {
      final store = await platform.openStore();
      if (await store.hasUploadableOperation(owner)) return true;
      if (!supported) return false;
      if ((await _journalActions()).isNotEmpty) return true;
      if (!await _hasInstalledWidget()) return false;
      final need = await store.widgetRefreshNeed(now: DateTime.now());
      return need != null && need.owner == owner && !need.snapshotCurrent;
    } catch (_) {
      return true;
    }
  }

  // 함수이름: refreshInBackground
  // 함수역할: 위젯 클릭을 기기에 기록하고, 전송 대기 기록을 보내고, 필요할 때만 서버 일정을 읽어
  //   위젯에 반영한다. 보낼 기록도 표시할 위젯도 없으면 통신하지 않고 끝낸다.
  // 매개변수: sync/client - 호출자가 이미 준비해 전송까지 마친 동기화 서비스와 통신 수단(호출자가
  //   닫는다). 없으면 직접 만들고 전송한 뒤 닫는다. requestedByWidget - 위젯이 요청한 새로고침이면
  //   오늘 조회 결과가 있어도 서버에서 다시 읽는다.
  // 반환값: 완료 Future. 오류가 나도 클릭 기록과 전송 대기 기록은 남아 다음 갱신에서 이어진다.
  static Future<void> refreshInBackground({
    DoseSyncService? sync,
    http.Client? client,
    bool requestedByWidget = false,
  }) async {
    if (!supported) return;
    http.Client? ownClient;
    DoseSyncService? ownSync;
    try {
      final store = await platform.openStore();
      final tapped = (await _journalActions()).isNotEmpty;
      final installed = await _hasInstalledWidget();
      if (!tapped && !installed && !requestedByWidget) {
        // 표시할 위젯도 기록할 클릭도 없다. 직접 보낼 기록까지 없으면 아무 일도 하지 않는다.
        final active = await store.widgetRefreshNeed(now: DateTime.now());
        if (sync != null ||
            active == null ||
            !await store.hasUploadableOperation(active.owner)) {
          return;
        }
      }
      // Local persistence does not require connectivity or an ID-token refresh.
      final state = await publish();
      if (state == null) return;
      final owner = state.data['owner'] as String;
      if (sync != null && sync.owner != owner) return;
      // 호출자가 넘긴 서비스는 이미 전송을 마쳤다. 방금 기록한 위젯 클릭이 있을 때만 다시 보낸다.
      final upload =
          (sync == null || tapped) && await store.hasUploadableOperation(owner);
      var need = await store.widgetRefreshNeed(now: DateTime.now());
      if (need == null) return;
      // 클릭으로 깨어난 경우가 아니면 위젯의 새로고침 요청은 항상 서버에서 다시 읽는다.
      final forced = requestedByWidget && !tapped;
      if (!upload && !forced && (!installed || need.snapshotCurrent)) return;

      client ??= sync?.client ?? (ownClient = await platform.openClient());
      sync ??= ownSync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
        loadScheduleWindow: readScheduleWindow == null
            ? null
            : () => readScheduleWindow!(owner, client!),
      );
      var changed = false;
      if (upload) {
        await sync.drain();
        changed = true;
        // 전송 확인 응답에는 오늘 일정이 들어 있으므로 성공하면 다시 조회하지 않는다.
        need = await store.widgetRefreshNeed(now: DateTime.now());
        if (need == null) return;
      }
      if (forced || (installed && !need.snapshotCurrent)) {
        if ((state.data['config'] as Map?)?['source'] == 'patients') {
          final day = doseWidgetDay(DateTime.now());
          final revision = state.data['patient_revision'] as String?;
          try {
            final readSnapshots = readPatientSnapshots;
            if (readSnapshots == null) {
              throw StateError('Patient snapshot reader is not installed.');
            }
            final snapshots = await readSnapshots(owner, client);
            if (day == doseWidgetDay(DateTime.now())) {
              await publish(
                owner: owner,
                expectedPatientRevision: revision,
                patientCache: {
                  'date': day,
                  'patients': [
                    for (final snapshot in snapshots)
                      {
                        'link': snapshot.link.toJson(),
                        'schedules': snapshot.schedules
                            .map((s) => s.toJson())
                            .toList(),
                      },
                  ],
                },
              );
            }
          } catch (_) {
            final cached = state.data['patient_cache'] as Map?;
            await publish(
              owner: owner,
              expectedPatientRevision: revision,
              patientCache: {
                'date': day,
                'failed': true,
                'patients': cached?['date'] == day
                    ? (cached?['patients'] ?? [])
                    : [],
              },
            );
          }
          return;
        }
        try {
          final revision = await sync.cacheRevision();
          final day = doseWidgetDay(DateTime.now());
          final readSchedules = readTodaySchedules;
          if (readSchedules == null) {
            throw StateError('Today schedule reader is not installed.');
          }
          final schedules = await readSchedules(owner, client);
          // A request crossing midnight must not relabel yesterday's response.
          if (day == doseWidgetDay(DateTime.now())) {
            await sync.cacheSchedules(
              schedules,
              scheduleDate: day,
              expectedRevision: revision,
            );
            await sync.refreshScheduleWindow();
            changed = changed || await sync.cacheRevision() != revision;
          }
        } catch (_) {
          // 조회 실패는 전송 결과의 발행을 막지 않는다. 저장된 일정은 그대로 둔다.
        }
      }
      if (changed) await publish(owner: owner);
    } catch (_) {
      // The journal/outbox remains intact. Never display server success on error.
    } finally {
      ownSync?.dispose();
      ownClient?.close();
    }
  }

  // Function Name: clear
  // Description: Cancels refresh scheduling and replaces sensitive widget content with localized sign-in state and handled journal tokens.
  // Parameters: None.
  // Returns: Completion after native refresh; preference-read failure uses Korean, other platform/journal errors propagate. Outbox data is not erased.
  static Future<void> clear() async {
    if (!supported) return;
    await platform.cancelScheduledUpdates();
    final actions = await _journalActions();
    // 로그인 안내도 앱 언어를 따르게 한다. 언어가 없으면 위젯은 한국어로 그린다.
    var language = 'ko';
    try {
      final preferences = await SharedPreferences.getInstance();
      language = resolveAppLanguage(
        preferences.getString(appLanguagePreferenceKey) ?? 'ko',
      );
    } catch (_) {
      // 설정을 읽지 못해도 위젯은 비운다.
    }
    await platform.saveState(
      jsonEncode({
        'handled': actions.map((a) => a['token']).toList(),
        'language': language,
      }),
    );
    await platform.updateWidget();
  }

  // 함수이름: pin
  // 함수역할: 현재 상태를 발행한 뒤 지원되는 런처에 위젯 고정 요청을 보낸다.
  // 매개변수: 없음.
  // 반환값: 미지원이면 false, 요청까지 마치면 true. 실제 사용자 배치 완료를 뜻하지 않으며 플러그인 오류는 전파한다.
  static Future<bool> pin() async {
    if (!supported || await HomeWidget.isRequestPinWidgetSupported() != true) {
      return false;
    }
    await publish();
    await HomeWidget.requestPinWidget(qualifiedAndroidName: provider);
    return true;
  }
}
