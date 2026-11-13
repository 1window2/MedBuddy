// 파일명: caregiver_notification_background_service.dart
// 역할: 백그라운드 작업 진입점에서 Control과 서비스를 조립해 보호자 알림 확인, 복약 알림 갱신, 복용 기록 전송을 실행한다.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'caregiver_notification_monitor_factory.dart';
import 'dose_home_widget_background.dart';
import 'medication_reminder_refresh_factory.dart';
import '../controls/app_language_control.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/firebase_runtime_service.dart';
import '../services/medication_reminder_background_service.dart';
import '../services/dose_sync_service.dart';
import '../services/dose_home_widget_service.dart';
import '../services/dose_sync_background_service.dart';
import '../services/dose_outbox_store.dart';
import '../services/notification_service.dart';

const String caregiverNotificationBackgroundTask =
    'medbuddy_caregiver_notification_check';
const String _caregiverNotificationBackgroundTag =
    'medbuddy_caregiver_notification';
const Duration _backgroundAuthRestoreTimeout = Duration(seconds: 5);

// 함수이름: _restoreBackgroundFirebaseUser
// 함수역할: 현재 Firebase 사용자를 우선 사용하고 없으면 토큰 스트림의 첫 복원 사용자를 제한 시간 동안 기다리며 시간 초과 시 null을 제공한다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<User?>: 현재 Firebase 사용자를 우선 사용하고 없으면 토큰 스트림의 첫 복원 사용자를 제한 시간 동안 기다리며 시간 초과 시 null을 제공한다.
Future<User?> _restoreBackgroundFirebaseUser() async {
  final firebaseAuth = FirebaseAuth.instance;
  final currentUser = firebaseAuth.currentUser;
  if (currentUser != null) {
    return currentUser;
  }
  try {
    return await firebaseAuth
        .idTokenChanges()
        .firstWhere(
          /* 함수이름: firstWhere 콜백
         * 함수역할: 복원된 인증 스트림에서 실제 Firebase 사용자가 나타날 때까지 기다린다.
         * 매개변수:
         * - user (User?): 현재 또는 새로 복원된 Firebase 사용자
         * 반환값:
         * - 사용자가 null이 아니면 true.
         */
          (user) => user != null,
        )
        .timeout(_backgroundAuthRestoreTimeout);
  } on TimeoutException {
    return null;
  }
}

// Class Name: BackgroundTaskDeps
// Role: Groups the authentication, persistence, widget, reminder and monitoring boundaries used by background tasks.
// Responsibilities: Provide production defaults while allowing tests to override individual task effects.
// Attributes: No instance fields; methods resolve the shared runtime services when invoked.
class BackgroundTaskDeps {
  // Function Name: BackgroundTaskDeps
  // Description: Creates the stateless production dependency bundle for background dispatch.
  // Parameters: None.
  // Returns: A reusable dependency bundle without starting services.
  const BackgroundTaskDeps();

  // Function Name: openClient
  // Description: Restores Firebase identity when required before creating authenticated HTTP transport.
  // Parameters: None.
  // Returns: A caller-owned client, or null when no Firebase user can be restored; initialization/token errors propagate.
  Future<http.Client?> openClient() async {
    if (AuthConfig.mode == AuthenticationMode.firebase) {
      await FirebaseRuntimeService.initialize();
      final currentUser = await _restoreBackgroundFirebaseUser();
      if (currentUser == null) {
        return null;
      }
      await currentUser.getIdToken();
    }
    return AuthenticatedApiClient();
  }

  // Function Name: openDoseStore
  // Description: Opens the dose outbox shared by foreground and background work.
  // Parameters: None.
  // Returns: The persistent store Future; storage failures propagate.
  Future<DoseOutboxStore> openDoseStore() => DoseOutboxStore.open();

  // Function Name: doseNeedsNetwork
  // Description: Checks local widget/outbox state to decide whether this owner needs network work.
  // Parameters: owner: Account that scheduled the task.
  // Returns: Whether pending records or stale widget schedules require a network refresh.
  Future<bool> doseNeedsNetwork(String owner) =>
      DoseHomeWidget.needsNetworkRefresh(owner);

  // Function Name: cancelDosePeriodic
  // Description: Removes the 15-minute retry of an account that is no longer signed in on this device.
  // Parameters: owner: Account in the job name.
  // Returns: Completion; a periodic run that removes itself may be stopped by the platform right after.
  Future<void> cancelDosePeriodic(String owner) async {
    if (!DoseSyncBackgroundScheduler.supported) return;
    await DoseSyncBackgroundScheduler.platform.cancelPeriodic(owner);
  }

  // Function Name: finishDoseRun
  // Description: Keeps the account's 15-minute retry only while records wait or the widget still lacks today's data, and removes it otherwise.
  // Parameters: owner: Account that scheduled the task; periodicRun: Whether this run is the periodic job.
  // Returns: Completion; a periodic run that removes itself may be stopped by the platform right after.
  Future<void> finishDoseRun(String owner, {required bool periodicRun}) =>
      DoseSyncBackgroundScheduler.finishRun(
        owner,
        periodicRun: periodicRun,
        needsNetwork: () => doseNeedsNetwork(owner),
      );

  // Function Name: refreshDoseWidget
  // Description: Refreshes widget actions and display using local state or an already prepared synchronization context.
  // Parameters: sync: Optional service that already drained work; client: Its optional transport.
  // Returns: Completion of widget refresh; errors propagate to the task dispatcher.
  Future<void> refreshDoseWidget({DoseSyncService? sync, http.Client? client}) =>
      DoseHomeWidget.refreshInBackground(sync: sync, client: client);

  // Function Name: initializeNotifications
  // Description: Initializes the local notification service before reminder or caregiver work.
  // Parameters: None.
  // Returns: Notification-service initialization completion.
  Future<void> initializeNotifications() =>
      NotificationService.instance.initialize();

  // Function Name: refreshReminders
  // Description: Reconciles dated medication reminders using account-scoped server settings and schedules.
  // Parameters: patientHash: Patient owner; baseUrl: API root; client: Authenticated caller-owned transport.
  // Returns: The synchronizer result, with its temporary dependencies disposed even on failure.
  Future<bool> refreshReminders({
    required String patientHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    final reminderRefresh = MedicationReminderRefreshFactory.create(
      patientHash: patientHash,
      baseUrl: baseUrl,
      client: client,
    );
    try {
      return await reminderRefresh.synchronize();
    } finally {
      reminderRefresh.dispose();
    }
  }

  // Function Name: checkCaregiverAlerts
  // Description: Runs one caregiver monitoring pass in the saved app language without requesting permission.
  // Parameters: caregiverHash: Owner; baseUrl: API root; client: Authenticated transport.
  // Returns: Whether monitoring completed; the temporary monitor is always disposed.
  Future<bool> checkCaregiverAlerts({
    required String caregiverHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguageControl.normalizeLanguage(
      preferences.getString(AppLanguageControl.preferenceKey) ?? 'ko',
    );
    final monitor = CaregiverNotificationMonitorFactory.create(
      caregiverHash: caregiverHash,
      baseUrl: baseUrl,
      client: client,
      languageProvider: /* 함수이름: languageProvider 콜백
       * 함수역할: 저장된 앱 언어를 백그라운드 보호자 알림에 제공한다.
       * 매개변수:
       * - 없음.
       * 반환값:
       * - 정규화된 저장 언어 코드.
       */ () =>
          language,
      requestPermission: false,
      monitorCompletionTransitions:
          AuthConfig.mode != AuthenticationMode.firebase,
    );
    try {
      return await monitor.checkNow();
    } finally {
      monitor.dispose();
    }
  }
}

// Function Name: runBackgroundTask
// Description: Dispatches dose synchronization, reminder refresh or caregiver monitoring and closes any acquired client.
// Parameters: taskName: Scheduler job; inputData: Optional endpoint/owner scope; deps: Injectable task boundaries.
// Returns: True for ignored/completed work or blocked dose items needing user action; false for authentication/execution failure or remaining retryable doses.
Future<bool> runBackgroundTask(
  String taskName,
  Map<String, dynamic>? inputData,
  BackgroundTaskDeps deps,
) async {
  if (taskName != caregiverNotificationBackgroundTask &&
      taskName != doseSyncBackgroundTask &&
      taskName != medicationReminderBackgroundTask) {
    return true;
  }
  final baseUrl = inputData?['base_url']?.toString() ?? ApiConfig.baseUrl;

  http.Client? client;
  try {
    if (taskName == doseSyncBackgroundTask) {
      final owner = inputData?['patient_hash']?.toString() ?? '';
      if (owner.isEmpty) return true;
      final periodicRun = inputData?[doseSyncPeriodicInputKey] == true;
      final store = await deps.openDoseStore();
      if (!await store.isActive(owner)) {
        // Records of an account that is not signed in are never sent from here; its next sign-in reconciles the work again.
        await deps.cancelDosePeriodic(owner);
        return true;
      }
      if (!await deps.doseNeedsNetwork(owner)) {
        // 통신할 일이 없다. 기기 안의 상태만으로 위젯을 맞추고, 더 필요 없는 15분 재시도를 지운다.
        await deps.refreshDoseWidget();
        await deps.finishDoseRun(owner, periodicRun: periodicRun);
        return true;
      }
      client = await deps.openClient();
      if (client == null) {
        return false;
      }
      final sync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      try {
        await sync.drain();
        await deps.refreshDoseWidget(sync: sync, client: client);
        final delivered = sync.pendingCount == 0 || sync.hasBlocked;
        // 마지막 단계다. 스스로를 지우는 주기 실행은 플랫폼이 곧바로 멈춘다.
        await deps.finishDoseRun(owner, periodicRun: periodicRun);
        return delivered;
      } finally {
        sync.dispose();
      }
    }

    final isReminderTask = taskName == medicationReminderBackgroundTask;
    final scopeHash =
        inputData?[isReminderTask ? 'patient_hash' : 'caregiver_hash']
            ?.toString() ??
        '';
    if (scopeHash.trim().isEmpty) {
      return true;
    }
    client = await deps.openClient();
    if (client == null) {
      return false;
    }
    await deps.initializeNotifications();
    if (isReminderTask) {
      return await deps.refreshReminders(
        patientHash: scopeHash,
        baseUrl: baseUrl,
        client: client,
      );
    }
    return await deps.checkCaregiverAlerts(
      caregiverHash: scopeHash,
      baseUrl: baseUrl,
      client: client,
    );
  } catch (error, stackTrace) {
    developer.log(
      '보호자 백그라운드 알림 확인에 실패했습니다.',
      name: 'CaregiverNotificationMonitorService',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  } finally {
    client?.close();
  }
}

// Function Name: caregiverNotificationCallbackDispatcher
// Description: Installs a background task callback and reconnects widget readers in the worker isolate.
// Parameters: None.
// Returns: None; Workmanager receives each task's asynchronous completion result.
@pragma('vm:entry-point')
void caregiverNotificationCallbackDispatcher() {
  Workmanager().executeTask(/* 함수이름: executeTask 콜백
   * 함수역할: 작업 이름과 입력을 실제 서비스 묶음과 함께 runBackgroundTask에 넘긴다.
   * 매개변수:
   * - taskName (String): 스케줄러가 전달한 백그라운드 작업 이름
   * - inputData (Map<String, dynamic>?): 작업에 저장된 API 주소와 환자·보호자 범위
   * 반환값:
   * - 작업 성공·무시 여부는 true, 인증 또는 실행 실패는 false로 완료하는 Future.
   */ (taskName, inputData) {
    // 백그라운드 실행 환경에는 앱 시작 코드가 돌지 않으므로 위젯 서비스의 서버 조회 함수를 여기서 연결한다.
    installDoseHomeWidgetReaders();
    return runBackgroundTask(taskName, inputData, const BackgroundTaskDeps());
  });
}

// 클래스명: CaregiverNotificationBackgroundScheduler
// 역할: Android 보호자 감시 작업의 등록과 해제를 관리한다.
// 주요 책임: dispatcher를 준비하고 계정 교체 시 이전 태그를 취소한 뒤 연결 조건의 주기 작업을 유지한다.
// 속성: 인스턴스 상태 없음; 플랫폼 조건과 파일 수준 작업 이름·태그 및 Workmanager를 사용한다.
class CaregiverNotificationBackgroundScheduler {
  // 함수이름: CaregiverNotificationBackgroundScheduler._
  // 함수역할: 보호자 감시 작업의 정적 등록·해제 API만 사용하도록 외부 생성을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - CaregiverNotificationBackgroundScheduler: 초기화된 인스턴스.
  CaregiverNotificationBackgroundScheduler._();

  // 함수이름: _supportsBackgroundWork
  // 함수역할: 웹이 아니고 Flutter 대상과 실제 운영체제가 모두 Android인 경우에만 백그라운드 작업을 허용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 웹이 아니고 Flutter 대상과 실제 운영체제가 모두 Android인 경우에만 백그라운드 작업을 허용한다.
  static bool get _supportsBackgroundWork {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  // 함수이름: initialize
  // 함수역할: 지원되는 Android 환경에서 보호자·환자 알림 작업 dispatcher를 Workmanager에 등록한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  static Future<void> initialize() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().initialize(caregiverNotificationCallbackDispatcher);
  }

  // 함수이름: register
  // 함수역할: 기존 보호자 작업을 취소하고 정규화한 보호자 해시의 네트워크 연결 조건 15분 주기 확인 작업을 등록한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  static Future<void> register(String caregiverHash) async {
    if (!_supportsBackgroundWork) {
      return;
    }
    final normalizedHash = PatientHash.normalizePatientHash(caregiverHash);
    await Workmanager().cancelByTag(_caregiverNotificationBackgroundTag);
    await Workmanager().registerPeriodicTask(
      '$_caregiverNotificationBackgroundTag.$normalizedHash',
      caregiverNotificationBackgroundTask,
      frequency: const Duration(minutes: 15),
      inputData: {
        'caregiver_hash': normalizedHash,
        'base_url': ApiConfig.baseUrl,
      },
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: _caregiverNotificationBackgroundTag,
    );
  }

  // 함수이름: cancel
  // 함수역할: 지원되는 Android 환경에서 보호자 알림 태그의 모든 주기 작업을 취소한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  static Future<void> cancel() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().cancelByTag(_caregiverNotificationBackgroundTag);
  }
}
