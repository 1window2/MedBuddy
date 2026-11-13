// 파일명: dose_sync_background_service.dart
// 역할: 연결 조건을 만족할 때 복약 전송을 예약한다. 실제 실행 시점은 Android가 정한다.
// 15분 주기 작업은 보낼 기록이 있거나 홈 위젯에 오늘 데이터가 필요할 때만 두고, 할 일이 없으면 지운다.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'dose_outbox_store.dart';

const doseSyncBackgroundTask = 'medbuddy_dose_sync';
// Marks periodic runs: cancelling the periodic work from inside such a run stops its engine.
const doseSyncPeriodicInputKey = 'periodic';

// Class Name: DoseSyncWorkPlatform
// Role: Adapts Workmanager and outbox opening for background dose uploads.
// Responsibilities: Provide replaceable platform calls for registration, cancellation, and storage access.
// Attributes: None; the default implementation delegates to platform plugins.
class DoseSyncWorkPlatform {
  // Function Name: DoseSyncWorkPlatform
  // Description: Creates a stateless platform adapter without scheduling work or opening storage.
  // Parameters: None.
  // Returns: The default adapter; tests may override its operations.
  const DoseSyncWorkPlatform();

  // Function Name: supported
  // Description: Limits dose background work to native Android.
  // Parameters: None.
  // Returns: True on Android outside the web target; otherwise false.
  bool get supported => !kIsWeb && Platform.isAndroid;

  // Function Name: registerOneOff
  // Description: Requests network-constrained one-off upload with exponential backoff, preserving an already queued job.
  // Parameters: owner (String) - account passed to the worker and used in its unique job name.
  // Returns: Registration completion, not upload completion; platform errors propagate and Android chooses execution time.
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

  // Function Name: registerPeriodic
  // Description: Creates or updates network-constrained recurring uploads with a requested 15-minute interval.
  // Parameters: owner (String) - account associated with the periodic job.
  // Returns: Registration completion; Android may defer execution and platform errors propagate.
  Future<void> registerPeriodic(String owner) =>
      Workmanager().registerPeriodicTask(
        _periodicName(owner),
        doseSyncBackgroundTask,
        inputData: {'patient_hash': owner, doseSyncPeriodicInputKey: true},
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
        tag: doseSyncBackgroundTask,
      );

  // Function Name: cancelAll
  // Description: Cancels tagged one-off and periodic upload work across all accounts.
  // Parameters: None.
  // Returns: Platform cancellation completion; queued dose records remain stored.
  Future<void> cancelAll() => Workmanager().cancelByTag(doseSyncBackgroundTask);

  // Function Name: cancelPeriodic
  // Description: Removes the account's 15-minute retry, including one registered by an earlier app version under the same name.
  // Parameters: owner (String) - account in the unique job name.
  // Returns: Cancellation completion; the one-off upload job is kept.
  Future<void> cancelPeriodic(String owner) =>
      Workmanager().cancelByUniqueName(_periodicName(owner));

  static String _periodicName(String owner) =>
      '$doseSyncBackgroundTask.periodic.$owner';

  // Function Name: openStore
  // Description: Opens the encrypted outbox shared with foreground dose recording.
  // Parameters: None.
  // Returns: Shared store Future; key/database opening errors propagate.
  Future<DoseOutboxStore> openStore() => DoseOutboxStore.open();
}

// 클래스명: DoseSyncBackgroundScheduler
// 역할: 플랫폼 지원 여부에 따라 복약 전송 작업과 영속 세션 복원을 조정한다.
// 주요 책임: 일회·주기 작업 등록, 현재 세션 확인 및 중단 처리를 플랫폼 경계에 위임한다.
// 속성: platform (DoseSyncWorkPlatform): 교체 가능한 작업·저장소 경계; supported (bool): 지원 여부.
class DoseSyncBackgroundScheduler {
  // 테스트에서만 교체한다.
  static DoseSyncWorkPlatform platform = const DoseSyncWorkPlatform();

  // Function Name: supported
  // Description: Uses the installed adapter's background-work capability.
  // Parameters: None.
  // Returns: True when that adapter supports dose background jobs.
  static bool get supported => platform.supported;

  // Function Name: reconcile
  // Description: Keeps the 15-minute retry only while network work remains: queued records, journal taps, or an installed widget without today's data. Otherwise the periodic job is cancelled, then the need is read again so work queued meanwhile is registered again.
  // Parameters: owner (String) - account; needsNetwork (Future<bool> Function()) - current need, read from the outbox and widget state.
  // Returns: Completion; registration and cancellation failures propagate.
  static Future<void> reconcile(
    String owner, {
    required Future<bool> Function() needsNetwork,
  }) async {
    if (!supported) return;
    if (await needsNetwork()) {
      await register(owner);
      return;
    }
    await platform.cancelPeriodic(owner);
    // A record queued between the read and the cancel may have had its periodic job cancelled here; its one-off job remains, and this read restores the retry.
    if (await needsNetwork()) await register(owner);
  }

  // Function Name: finishRun
  // Description: Ends a background dose run: keeps the periodic retry while network work remains and otherwise removes it. A periodic run cancels itself as its last step, because the cancellation stops the running engine; a record queued meanwhile still has its own one-off upload job, and the next app start reconciles again.
  // Parameters: owner (String) - account; periodicRun (bool) - whether the running job is the periodic one; needsNetwork (Future<bool> Function()) - current need.
  // Returns: Completion; registration and cancellation failures propagate.
  static Future<void> finishRun(
    String owner, {
    required bool periodicRun,
    required Future<bool> Function() needsNetwork,
  }) async {
    if (!supported) return;
    if (await needsNetwork()) {
      await platform.registerPeriodic(owner);
      return;
    }
    if (periodicRun) {
      await platform.cancelPeriodic(owner);
      return;
    }
    await reconcile(owner, needsNetwork: needsNetwork);
  }

  // Function Name: register
  // Description: Registers one-off then periodic work without activating or replacing the outbox account. Callers register only when a record was queued or network work is known to remain.
  // Parameters: owner (String) - account to associate with both jobs.
  // Returns: Completion, or an immediate no-op on unsupported platforms; registration failures propagate.
  static Future<void> register(String owner) async {
    if (!supported) return;
    await platform.registerOneOff(owner);
    // Repairs the enqueue/job-registration crash window on subsequent launches.
    await platform.registerPeriodic(owner);
  }

  // 로그아웃 중단 때만 같은 세션의 비활성 저장소를 다시 연다. 작업 등록만으로는 활성화되지 않는다.
  // 함수이름: resume
  // 함수역할: 로그아웃을 취소한 동일 세션일 때 저장소 활성 계정 복구를 요청한다. 작업을 새로 예약하지 않는다.
  // 매개변수: owner (String) - 원래 계정; isCurrent (bool Function()) - 세션 유효성 확인 함수.
  // 반환값: 복구 시도 완료 Future. 미지원·이미 바뀐 세션은 무시하고 저장소 오류는 전파한다.
  static Future<void> resume(
    String owner, {
    required bool Function() isCurrent,
  }) async {
    if (!supported || !isCurrent()) return;
    final store = await platform.openStore();
    await store.restoreDoseSession(owner, isCurrent: isCurrent);
  }

  // Function Name: suspend
  // Description: Cancels upload jobs and attempts account deactivation even if cancellation fails.
  // Parameters: None.
  // Returns: Completion or a platform/storage error; unsupported platforms do nothing and pending records are retained.
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
