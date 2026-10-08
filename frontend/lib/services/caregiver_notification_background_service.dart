// 파일명: caregiver_notification_background_service.dart
// 역할: 백그라운드에서 보호자 미복용 알림 상태를 주기적으로 확인한다.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../composition/caregiver_notification_monitor_factory.dart';
import '../controls/app_language_control.dart';
import '../entities/patient_hash_entity.dart';
import 'api_config.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'firebase_runtime_service.dart';
import 'medication_reminder_background_service.dart';
import 'dose_sync_service.dart';
import 'dose_home_widget_service.dart';
import 'dose_sync_background_service.dart';
import 'dose_outbox_store.dart';
import 'notification_service.dart';

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

// 클래스명: BackgroundTaskDeps
// 역할: 백그라운드 작업이 쓰는 인증·저장소·위젯·알림·감시 호출을 묶는다.
// 주요 책임: 기본 구현은 실제 서비스를 호출하고, 테스트는 이 클래스를 대체해 작업 종류별 흐름을 검증한다.
class BackgroundTaskDeps {
  const BackgroundTaskDeps();

  // 함수이름: openClient
  // 함수역할: 서버 요청에 필요한 인증을 복원하고 API 클라이언트를 만든다. 통신이 필요한 작업만 호출한다.
  // 매개변수: 없음.
  // 반환값: 호출자가 닫아야 하는 클라이언트. Firebase 로그인 사용자를 복원하지 못하면 null.
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

  // 함수이름: openDoseStore
  // 함수역할: 앱과 백그라운드 작업이 공유하는 복용 기록 저장소를 연다. 반환값: 열린 저장소.
  Future<DoseOutboxStore> openDoseStore() => DoseOutboxStore.open();

  // 함수이름: doseNeedsNetwork
  // 함수역할: 복용 기록 작업에 통신이 필요한지 기기 안에서만 확인한다.
  // 매개변수: owner - 작업을 등록한 계정. 반환값: 전송할 기록이나 새로 읽을 위젯 일정이 있으면 true.
  Future<bool> doseNeedsNetwork(String owner) =>
      DoseHomeWidget.needsNetworkRefresh(owner);

  // 함수이름: refreshDoseWidget
  // 함수역할: 위젯 클릭 기록과 위젯 표시를 갱신한다. sync와 client를 넘기면 이미 전송을 마친 그 서비스와
  //   통신 수단을 다시 쓰고, 넘기지 않으면 기기 안의 상태만으로 갱신한다.
  // 매개변수: sync - 전송을 마친 동기화 서비스, client - 그 서비스의 통신 수단. 반환값: 완료 Future.
  Future<void> refreshDoseWidget({DoseSyncService? sync, http.Client? client}) =>
      DoseHomeWidget.refreshInBackground(sync: sync, client: client);

  // 함수이름: initializeNotifications
  // 함수역할: 로컬 알림을 예약·표시할 수 있게 알림 서비스를 준비한다. 반환값: 완료 Future.
  Future<void> initializeNotifications() =>
      NotificationService.instance.initialize();

  // 함수이름: refreshReminders
  // 함수역할: 서버 일정과 설정으로 환자의 날짜별 복약 알림을 다시 맞춘다.
  // 매개변수: patientHash - 환자 계정, baseUrl - API 주소, client - 인증된 통신 수단.
  // 반환값: 모든 시간대를 맞췄으면 true, 다시 시도해야 하면 false.
  Future<bool> refreshReminders({
    required String patientHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    final reminderRefresh = MedicationReminderRefreshService.live(
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

  // 함수이름: checkCaregiverAlerts
  // 함수역할: 저장된 앱 언어로 보호자 감시를 한 번 실행한다. 권한 창은 띄우지 않는다.
  // 매개변수: caregiverHash - 보호자 계정, baseUrl - API 주소, client - 인증된 통신 수단.
  // 반환값: 확인이 정상 완료됐으면 true.
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

// 함수이름: runBackgroundTask
// 함수역할: 백그라운드 작업 종류에 따라 복용 기록 전송, 복약 알림 갱신, 보호자 감시 중 하나를 실행하고
//   사용한 통신 수단을 닫는다. 복용 기록 작업은 보낼 기록도 새로 읽을 일정도 없으면 인증과 통신을
//   준비하지 않고 끝낸다.
// 매개변수:
// - taskName (String): 스케줄러가 전달한 백그라운드 작업 이름
// - inputData (Map<String, dynamic>?): 작업에 저장된 API 주소와 환자·보호자 범위
// - deps (BackgroundTaskDeps): 작업이 쓰는 서비스 호출 묶음
// 반환값:
// - 작업 성공·무시 여부는 true, 인증 또는 실행 실패는 false로 완료하는 Future.
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
      final store = await deps.openDoseStore();
      if (!await store.isActive(owner)) return true;
      if (!await deps.doseNeedsNetwork(owner)) {
        // 통신할 일이 없다. 기기 안의 상태만으로 위젯을 맞추고 끝낸다.
        await deps.refreshDoseWidget();
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
        return sync.pendingCount == 0 || sync.hasBlocked;
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

// 함수이름: caregiverNotificationCallbackDispatcher
// 함수역할: Android가 앱을 깨운 경우 보호자 상태 또는 환자 복약 알림 일정을 갱신한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음.
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
    return runBackgroundTask(taskName, inputData, const BackgroundTaskDeps());
  });
}

// 클래스명: CaregiverNotificationBackgroundScheduler
// 역할: Android의 보호자 알림 확인 주기 작업을 관리한다.
// 주요 책임:
// - 지원 플랫폼에서 dispatcher를 등록하고 사용자 교체 시 이전 태그 작업을 취소한 뒤 네트워크 조건의 15분 주기 작업을 유지한다.
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
