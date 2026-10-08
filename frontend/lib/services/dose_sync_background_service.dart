// 파일명: dose_sync_background_service.dart
// 역할: 연결 조건을 만족할 때 복약 전송을 예약한다. 실제 실행 시점은 Android가 정한다.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'dose_outbox_store.dart';

const doseSyncBackgroundTask = 'medbuddy_dose_sync';

// 클래스명: DoseSyncWorkPlatform
// 역할: 전송 예약이 쓰는 WorkManager 호출과 저장소 열기를 묶는다.
// 주요 책임: 기본 구현은 실제 플러그인을 호출하고, 테스트는 이 클래스를 대체해 호출을 기록한다.
class DoseSyncWorkPlatform {
  const DoseSyncWorkPlatform();

  bool get supported => !kIsWeb && Platform.isAndroid;

  // 함수이름: registerOneOff
  // 함수역할: 연결되는 즉시 한 번 실행할 전송 작업을 등록한다. 대기 중인 작업이 있으면 유지한다.
  // 매개변수: owner - 계정. 반환값: 등록 완료 Future.
  Future<void> registerOneOff(String owner) => Workmanager().registerOneOffTask(
    '$doseSyncBackgroundTask.$owner',
    doseSyncBackgroundTask,
    inputData: {'patient_hash': owner},
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
    tag: doseSyncBackgroundTask,
  );

  // 함수이름: registerPeriodic
  // 함수역할: 15분 주기 전송 작업을 등록하거나 기존 등록을 갱신한다.
  // 매개변수: owner - 계정. 반환값: 등록 완료 Future.
  Future<void> registerPeriodic(String owner) =>
      Workmanager().registerPeriodicTask(
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

  // 함수이름: cancelAll
  // 함수역할: 모든 계정의 일회성·주기 전송 작업을 취소한다. 반환값: 취소 완료 Future.
  Future<void> cancelAll() => Workmanager().cancelByTag(doseSyncBackgroundTask);

  // 함수이름: openStore
  // 함수역할: 앱과 백그라운드 작업이 공유하는 전송 대기 저장소를 연다. 반환값: 열린 저장소.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();
}

// 클래스명: DoseSyncBackgroundScheduler
// 역할: 계정별 일회성·주기 전송 작업을 등록하고 로그아웃 때 중단한다.
class DoseSyncBackgroundScheduler {
  // 테스트에서만 교체한다.
  static DoseSyncWorkPlatform platform = const DoseSyncWorkPlatform();

  static bool get supported => platform.supported;

  static Future<void> register(String owner) async {
    if (!supported) return;
    await platform.registerOneOff(owner);
    // Repairs the enqueue/job-registration crash window on subsequent launches.
    await platform.registerPeriodic(owner);
  }

  // 함수이름: suspend
  // 함수역할: 로그아웃 때 전송 작업을 취소하고 저장소의 활성 계정을 해제한다.
  // 매개변수: 없음. 반환값: 완료 Future. 저장소를 열지 못하면 작업을 취소한 뒤 그 오류를 전달한다.
  static Future<void> suspend() async {
    if (!supported) return;
    try {
      // 저장소 오류로 로그아웃이 중단되어도 이전 계정의 작업이 계속 깨어나지 않게 먼저 취소한다.
      await platform.cancelAll();
    } finally {
      final store = await platform.openStore();
      await store.activate(null);
    }
  }
}
