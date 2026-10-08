// 파일명: dose_home_widget_service.dart
// 역할: 암호화된 복약 상태를 Android 위젯에 전달하고 백그라운드 요청을 처리한다.
// PendingIntent에는 불투명 토큰만 전달하며 계정과 약 ID는 암호화 저장소에 둔다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;

import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/dose_widget_state.dart';
import '../entities/medication_schedule_entity.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'dose_outbox_store.dart';
import 'dose_sync_background_service.dart';
import 'dose_sync_service.dart';
import 'firebase_runtime_service.dart';
import 'notification_service.dart';

// 함수형: DoseWidgetTodayScheduleReader
// 역할: 계정의 오늘 복약 일정을 서버에서 읽는다. 조립 계층이 일정 Control로 구현해 넣는다.
typedef DoseWidgetTodayScheduleReader =
    Future<List<MedicationSchedule>> Function(String owner, http.Client client);

// 함수형: DoseWidgetPatientSnapshotReader
// 역할: 보호자 계정에 연동된 환자들의 오늘 일정을 서버에서 읽는다. 조립 계층이 보호자 Control로 구현해 넣는다.
typedef DoseWidgetPatientSnapshotReader =
    Future<List<CaregiverMonitoringSnapshot>> Function(
      String owner,
      http.Client client,
    );

// 클래스명: DoseHomeWidgetPlatform
// 역할: 위젯 서비스가 쓰는 위젯 플러그인·저장소·알림·전송 예약·통신 준비 호출을 묶는다.
// 주요 책임: 기본 구현은 실제 플랫폼을 호출하고, 테스트는 이 클래스를 대체해 호출을 기록한다.
class DoseHomeWidgetPlatform {
  const DoseHomeWidgetPlatform();

  bool get supported => !kIsWeb && Platform.isAndroid;

  // 함수이름: readJournal
  // 함수역할: Android가 먼저 저장해 둔 위젯 클릭 목록을 읽는다. 반환값: JSON 배열 문자열.
  Future<String?> readJournal() => HomeWidget.getWidgetData<String>(
    DoseHomeWidget.journalKey,
    defaultValue: '[]',
  );

  // 함수이름: saveState
  // 함수역할: 위젯이 표시할 상태를 저장한다. 매개변수: state - JSON 문자열. 반환값: 완료 Future.
  Future<void> saveState(String state) =>
      HomeWidget.saveWidgetData<String>(DoseHomeWidget.stateKey, state);

  // 함수이름: updateWidget
  // 함수역할: 저장한 상태로 위젯을 다시 그리게 한다. 반환값: 완료 Future.
  Future<void> updateWidget() =>
      HomeWidget.updateWidget(qualifiedAndroidName: DoseHomeWidget.provider);

  // 함수이름: scheduleUpdate
  // 함수역할: 날짜가 바뀌는 시각에 위젯 갱신을 예약한다. 매개변수: at - 갱신 시각. 반환값: 완료 Future.
  Future<void> scheduleUpdate(DateTime at) => HomeWidget.scheduleWidgetUpdates([
    at,
  ], qualifiedAndroidName: DoseHomeWidget.provider);

  // 함수이름: cancelScheduledUpdates
  // 함수역할: 예약한 위젯 갱신을 취소한다. 반환값: 완료 Future.
  Future<void> cancelScheduledUpdates() =>
      HomeWidget.cancelScheduledWidgetUpdates(
        qualifiedAndroidName: DoseHomeWidget.provider,
      );

  // 함수이름: hasInstalledWidget
  // 함수역할: 홈 화면에 복약 위젯이 하나라도 놓여 있는지 확인한다. 반환값: 있으면 true.
  Future<bool> hasInstalledWidget() async =>
      (await HomeWidget.getInstalledWidgets()).isNotEmpty;

  // 함수이름: openStore
  // 함수역할: 앱과 백그라운드 작업이 공유하는 암호화 저장소를 연다. 반환값: 열린 저장소.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();

  // 함수이름: cancelReminder
  // 함수역할: 기기에 완료를 저장한 시간대의 해당 날짜 재알림을 취소한다.
  // 매개변수: owner - 계정, slotKey - 시간대, date - 복약 기준일. 반환값: 완료 Future.
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) => NotificationService.instance.cancelReminderForDate(
    owner: owner,
    slotKey: slotKey,
    date: date,
  );

  // 함수이름: registerSync
  // 함수역할: 위젯에서 받은 기록의 전송 작업을 예약한다. 매개변수: owner - 계정. 반환값: 완료 Future.
  Future<void> registerSync(String owner) =>
      DoseSyncBackgroundScheduler.register(owner);

  // 함수이름: openClient
  // 함수역할: 호출자가 통신 수단을 넘기지 않았을 때 인증을 준비하고 API 클라이언트를 만든다.
  // 반환값: 이 서비스가 닫아야 하는 클라이언트.
  Future<http.Client> openClient() async {
    if (AuthConfig.mode == AuthenticationMode.firebase) {
      await FirebaseRuntimeService.initialize();
    }
    return AuthenticatedApiClient();
  }
}

// 클래스명: DoseHomeWidget
// 역할: 위젯 상태 발행·새로고침·추가를 연결하며 본인 기록과 환자 조회를 분리한다.
class DoseHomeWidget {
  static const provider = 'com.example.medbuddy_frontend.DoseWidgetProvider';
  static const stateKey = 'dose_widget_state';
  static const journalKey = 'dose_widget_actions';
  // 테스트에서만 교체한다.
  static DoseHomeWidgetPlatform platform = const DoseHomeWidgetPlatform();
  // 서버 조회 함수. 앱 시작과 두 백그라운드 진입점에서 조립 계층이 채우며, 비어 있으면 서버 조회를 실패로 처리한다.
  static DoseWidgetTodayScheduleReader? readTodaySchedules;
  static DoseWidgetPatientSnapshotReader? readPatientSnapshots;
  static bool get supported => platform.supported;
  // 이 실행 환경에서 재알림을 이미 취소한 시간대. 키는 "계정|날짜"이며 현재 것만 보관한다.
  static final Map<String, Set<String>> _cancelledReminderSlots = {};

  // 함수이름: resetForTest
  // 함수역할: 테스트가 바꾼 플랫폼 대역과 재알림 취소 기록을 초기 상태로 되돌린다. 반환값: 없음.
  @visibleForTesting
  static void resetForTest() {
    platform = const DoseHomeWidgetPlatform();
    _cancelledReminderSlots.clear();
  }

  // 함수이름: initialize
  // 함수역할: 위젯이 앱 없이 새로고침을 요청할 때 실행할 백그라운드 진입점을 플러그인에 등록한다.
  // 매개변수: callback: 조립 계층에 정의된 최상위 진입 함수. 반환값: 등록 완료 Future.
  static Future<void> initialize(
    Future<void> Function(Uri? uri) callback,
  ) async {
    if (supported) {
      await HomeWidget.registerInteractivityCallback(callback);
    }
  }

  // 함수이름: _journalActions
  // 함수역할: Android가 저장해 둔 위젯 클릭을 읽는다. 반환값: 아직 처리하지 않은 클릭 목록.
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
    await platform.saveState(
      jsonEncode({...?state?.view, 'handled': handled}),
    );
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

  // 함수이름: _cancelCompletedReminders
  // 함수역할: 완료한 시간대의 재알림을 시간대마다 한 번만 취소한다. 발행할 때마다 같은 취소를
  //   반복하지 않되, 복용을 취소한 시간대는 알림이 다시 등록될 수 있으므로 다음 완료 때 다시 취소한다.
  // 매개변수: state - 방금 만든 위젯 상태. 반환값: 완료 Future. 실패한 시간대는 다음 발행에서 재시도한다.
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

  // 함수이름: _hasInstalledWidget
  // 함수역할: 홈 화면의 위젯 유무를 확인한다. 확인하지 못하면 있는 것으로 보고 갱신을 계속한다.
  static Future<bool> _hasInstalledWidget() async {
    try {
      return await platform.hasInstalledWidget();
    } catch (_) {
      return true;
    }
  }

  // 함수이름: needsNetworkRefresh
  // 함수역할: 주기 작업이 인증과 통신을 준비하기 전에, 통신이 필요한 일이 있는지 기기 안에서만 확인한다.
  // 매개변수: owner - 작업을 등록한 계정.
  // 반환값: 전송할 복용 기록이나 처리할 위젯 클릭이 있거나, 놓여 있는 위젯에 오늘 조회 결과가
  //   없으면 true. 확인하지 못해도 true를 돌려 기존과 같이 전체 갱신을 하게 한다.
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

  static Future<void> clear() async {
    if (!supported) return;
    await platform.cancelScheduledUpdates();
    final actions = await _journalActions();
    await platform.saveState(
      jsonEncode({'handled': actions.map((a) => a['token']).toList()}),
    );
    await platform.updateWidget();
  }

  static Future<bool> pin() async {
    if (!supported || await HomeWidget.isRequestPinWidgetSupported() != true) {
      return false;
    }
    await publish();
    await HomeWidget.requestPinWidget(qualifiedAndroidName: provider);
    return true;
  }
}
