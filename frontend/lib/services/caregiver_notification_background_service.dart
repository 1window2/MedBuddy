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
        .firstWhere(/* 함수이름: firstWhere 콜백
         * 함수역할: 복원된 인증 스트림에서 실제 Firebase 사용자가 나타날 때까지 기다린다.
         * 매개변수:
         * - user (User?): 현재 또는 새로 복원된 Firebase 사용자
         * 반환값:
         * - 사용자가 null이 아니면 true.
         */(user) => user != null)
        .timeout(_backgroundAuthRestoreTimeout);
  } on TimeoutException {
    return null;
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
   * 함수역할: 백그라운드 작업 종류에 따라 인증을 복원하고 복약 알림 또는 보호자 감시를 실행한 뒤 사용한 자원을 해제한다.
   * 매개변수:
   * - taskName (String): 스케줄러가 전달한 백그라운드 작업 이름
   * - inputData (Map<String, dynamic>?): 작업에 저장된 API 주소와 환자·보호자 범위
   * 반환값:
   * - 작업 성공·무시 여부는 true, 인증 또는 실행 실패는 false로 완료하는 Future.
   */(taskName, inputData) async {
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
        languageProvider: /* 함수이름: languageProvider 콜백
         * 함수역할: 저장된 앱 언어를 백그라운드 보호자 알림에 제공한다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 정규화된 저장 언어 코드.
         */() => language,
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
