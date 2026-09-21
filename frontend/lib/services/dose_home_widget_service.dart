// 파일명: dose_home_widget_service.dart
// 역할: 암호화된 복약 상태를 Android 위젯에 전달하고 백그라운드 요청을 처리한다.
// PendingIntent에는 불투명 토큰만 전달하며 계정과 약 ID는 암호화 저장소에 둔다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../controls/check_schedule_control.dart';
import '../controls/check_caregiver_medication_control.dart';
import '../entities/dose_widget_state.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'dose_outbox_store.dart';
import 'dose_sync_background_service.dart';
import 'dose_sync_service.dart';
import 'firebase_runtime_service.dart';

@pragma('vm:entry-point')
Future<void> doseHomeWidgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri?.scheme != 'medbuddy-widget' || uri?.host != 'refresh') return;
  await DoseHomeWidget.refreshInBackground();
}

// 클래스명: DoseHomeWidget
// 역할: 위젯 상태 발행·새로고침·추가를 연결하며 본인 기록과 환자 조회를 분리한다.
class DoseHomeWidget {
  static const provider = 'com.example.medbuddy_frontend.DoseWidgetProvider';
  static const stateKey = 'dose_widget_state';
  static const journalKey = 'dose_widget_actions';
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (supported) {
      await HomeWidget.registerInteractivityCallback(doseHomeWidgetCallback);
    }
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
    final store = await DoseOutboxStore.open();
    final journal = await HomeWidget.getWidgetData<String>(
      journalKey,
      defaultValue: '[]',
    );
    final actions = (jsonDecode(journal ?? '[]') as List).whereType<Map>();
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
    await HomeWidget.saveWidgetData<String>(
      stateKey,
      jsonEncode({...?state?.view, 'handled': handled}),
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    if (state != null) {
      await HomeWidget.scheduleWidgetUpdates([
        DateTime.fromMillisecondsSinceEpoch(state.view['expires'] as int),
      ], qualifiedAndroidName: provider);
    }
    if (handled.isNotEmpty && state != null) {
      await DoseSyncBackgroundScheduler.register(state.data['owner'] as String);
    }
    return state;
  }

  static Future<void> refreshInBackground() async {
    if (!supported) return;
    AuthenticatedApiClient? client;
    DoseSyncService? sync;
    try {
      // Local persistence does not require connectivity or an ID-token refresh.
      final state = await publish();
      if (state == null) return;
      final owner = state.data['owner'] as String;
      await DoseSyncBackgroundScheduler.register(owner);
      if (AuthConfig.mode == AuthenticationMode.firebase) {
        await FirebaseRuntimeService.initialize();
      }
      client = AuthenticatedApiClient();
      sync = DoseSyncService(owner: owner, client: client);
      await sync.drain();
      final current = await publish(owner: owner);
      if (current == null) return;
      if ((current.data['config'] as Map?)?['source'] == 'patients') {
        final day = doseWidgetDay(DateTime.now());
        final revision = current.data['patient_revision'] as String?;
        try {
          final snapshots = await CheckCaregiverMedication(
            caregiverHash: owner,
            client: client,
          ).requestMonitoringSnapshot();
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
          final cached = current.data['patient_cache'] as Map?;
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
      final revision = await sync.cacheRevision();
      final day = doseWidgetDay(DateTime.now());
      final schedules = await CheckSchedule(
        patientHash: owner,
        client: client,
      ).requestTodayMedicationSchedule();
      // A request crossing midnight must not relabel yesterday's response.
      if (day == doseWidgetDay(DateTime.now())) {
        await sync.cacheSchedules(
          schedules,
          scheduleDate: day,
          expectedRevision: revision,
        );
      }
      await publish(owner: owner);
    } catch (_) {
      // The journal/outbox remains intact. Never display server success on error.
    } finally {
      sync?.dispose();
      client?.close();
    }
  }

  static Future<void> clear() async {
    if (!supported) return;
    await HomeWidget.cancelScheduledWidgetUpdates(
      qualifiedAndroidName: provider,
    );
    final journal = await HomeWidget.getWidgetData<String>(
      journalKey,
      defaultValue: '[]',
    );
    final actions = (jsonDecode(journal ?? '[]') as List).whereType<Map>();
    await HomeWidget.saveWidgetData<String>(
      stateKey,
      jsonEncode({'handled': actions.map((a) => a['token']).toList()}),
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
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
