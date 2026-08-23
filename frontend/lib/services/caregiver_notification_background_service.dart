// 파일명: caregiver_notification_background_service.dart
// 역할: 백그라운드에서 보호자 미복용 알림 상태를 주기적으로 확인한다.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../composition/caregiver_notification_monitor_factory.dart';
import '../controls/app_language_control.dart';
import '../entities/patient_hash_entity.dart';
import 'api_config.dart';
import 'auth_config.dart';
import 'authenticated_api_client.dart';
import 'caregiver_notification_monitor_service.dart';
import 'firebase_runtime_service.dart';
import 'medication_reminder_background_service.dart';
import 'notification_service.dart';

const String caregiverNotificationBackgroundTask =
    'medbuddy_caregiver_notification_check';
const String _caregiverNotificationBackgroundTag =
    'medbuddy_caregiver_notification';
const Duration _backgroundAuthRestoreTimeout = Duration(seconds: 5);

Future<User?> _restoreBackgroundFirebaseUser() async {
  final firebaseAuth = FirebaseAuth.instance;
  final currentUser = firebaseAuth.currentUser;
  if (currentUser != null) {
    return currentUser;
  }
  try {
    return await firebaseAuth
        .idTokenChanges()
        .firstWhere((user) => user != null)
        .timeout(_backgroundAuthRestoreTimeout);
  } on TimeoutException {
    return null;
  }
}

// 함수명: caregiverNotificationCallbackDispatcher
// 역할:
// - Android가 앱을 깨운 경우 보호자 상태 또는 환자 복약 알림 일정을 갱신한다.
@pragma('vm:entry-point')
void caregiverNotificationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != caregiverNotificationBackgroundTask &&
        taskName != medicationReminderBackgroundTask) {
      return true;
    }
    final baseUrl = inputData?['base_url']?.toString() ?? ApiConfig.baseUrl;

    CaregiverNotificationMonitorService? monitor;
    MedicationReminderRefreshService? reminderRefresh;
    AuthenticatedApiClient? authenticatedClient;
    try {
      if (AuthConfig.mode == AuthenticationMode.firebase) {
        await FirebaseRuntimeService.initialize();
        final currentUser = await _restoreBackgroundFirebaseUser();
        if (currentUser == null) {
          return false;
        }
        await currentUser.getIdToken();
        authenticatedClient = AuthenticatedApiClient();
      }
      await NotificationService.instance.initialize();
      if (taskName == medicationReminderBackgroundTask) {
        final patientHash = inputData?['patient_hash']?.toString() ?? '';
        if (patientHash.trim().isEmpty) {
          return true;
        }
        reminderRefresh = MedicationReminderRefreshService.live(
          patientHash: patientHash,
          baseUrl: baseUrl,
          client: authenticatedClient,
        );
        return await reminderRefresh.synchronize();
      }

      final caregiverHash = inputData?['caregiver_hash']?.toString() ?? '';
      if (caregiverHash.trim().isEmpty) {
        return true;
      }
      final preferences = await SharedPreferences.getInstance();
      final language = AppLanguageControl.normalizeLanguage(
        preferences.getString(AppLanguageControl.preferenceKey) ?? 'ko',
      );
      monitor = CaregiverNotificationMonitorFactory.create(
        caregiverHash: caregiverHash,
        baseUrl: baseUrl,
        client: authenticatedClient,
        languageProvider: () => language,
        requestPermission: false,
        monitorCompletionTransitions:
            AuthConfig.mode != AuthenticationMode.firebase,
      );
      return await monitor.checkNow();
    } catch (error, stackTrace) {
      developer.log(
        '보호자 백그라운드 알림 확인에 실패했습니다.',
        name: 'CaregiverNotificationMonitorService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      monitor?.dispose();
      reminderRefresh?.dispose();
      authenticatedClient?.close();
    }
  });
}

// 클래스명: CaregiverNotificationBackgroundScheduler
// 역할: Firebase 없이 보호자 상태를 확인할 Android 주기 작업을 관리한다.
class CaregiverNotificationBackgroundScheduler {
  CaregiverNotificationBackgroundScheduler._();

  static bool get _supportsBackgroundWork {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Platform.isAndroid;
  }

  static Future<void> initialize() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().initialize(caregiverNotificationCallbackDispatcher);
  }

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

  static Future<void> cancel() async {
    if (!_supportsBackgroundWork) {
      return;
    }
    await Workmanager().cancelByTag(_caregiverNotificationBackgroundTag);
  }
}
