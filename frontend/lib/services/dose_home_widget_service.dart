// Android presentation bridge. Only opaque action tokens cross PendingIntents;
// account ownership and medication IDs stay in the encrypted dose store.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../controls/check_schedule_control.dart';
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

  // Native Android journals taps before waking Flutter. A killed background
  // process is recovered here on the next widget, app or periodic refresh.
  static Future<DoseWidgetState?> publish({
    String? owner,
    Map<String, dynamic>? configuration,
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
      );
      handled.add(token);
    }
    final state = await store.updateWidget(
      owner: owner,
      now: DateTime.now(),
      configuration: configuration,
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
      await publish(owner: owner);
      final revision = await sync.cacheRevision();
      final day = doseWidgetDay(DateTime.now());
      final schedules = await CheckSchedule(
        patientHash: owner,
        client: client,
      ).requestTodayMedicationSchedule();
      // A request crossing midnight must not relabel yesterday's response.
      if (day == doseWidgetDay(DateTime.now())) {
        await sync.cacheSchedules(schedules, expectedRevision: revision);
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
