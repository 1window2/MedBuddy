// 파일명: dose_sync_background_service.dart
// 역할: 연결 조건을 만족할 때 복약 전송을 예약한다. 실제 실행 시점은 Android가 정한다.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'dose_outbox_store.dart';

const doseSyncBackgroundTask = 'medbuddy_dose_sync';

// 클래스명: DoseSyncBackgroundScheduler
// 역할: 계정별 일회성·주기 전송 작업을 등록하고 로그아웃 때 중단한다.
class DoseSyncBackgroundScheduler {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> register(String owner) async {
    if (!supported) return;
    await Workmanager().registerOneOffTask(
      '$doseSyncBackgroundTask.$owner',
      doseSyncBackgroundTask,
      inputData: {'patient_hash': owner},
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: doseSyncBackgroundTask,
    );
    // Repairs the enqueue/job-registration crash window on subsequent launches.
    await Workmanager().registerPeriodicTask(
      '$doseSyncBackgroundTask.periodic.$owner',
      doseSyncBackgroundTask,
      inputData: {'patient_hash': owner},
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: doseSyncBackgroundTask,
    );
  }

  static Future<void> suspend() async {
    if (!supported) return;
    final store = await DoseOutboxStore.open();
    await store.activate(null);
    await Workmanager().cancelByTag(doseSyncBackgroundTask);
  }
}
