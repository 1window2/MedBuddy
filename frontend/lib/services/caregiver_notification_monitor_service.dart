// 파일명: caregiver_notification_monitor_service.dart
// 역할: 앱 실행 중 연동 환자의 시간대별 복용 상태와 보호자 알림을 감시한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';
import '../entities/caregiver_monitoring_snapshot_entity.dart';
import '../entities/caregiver_notification_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../entities/patient_hash_entity.dart';
import 'caregiver_patient_local_state_service.dart';

// 함수이름: CaregiverLinkLoader
// 함수역할: 현재 보호자가 참여한 환자 연동 목록을 비동기로 조회하는 경계이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<List<PatientCaregiverLink>>: 현재 보호자가 참여한 환자 연동 목록을 비동기로 조회하는 경계이다.
typedef CaregiverLinkLoader = Future<List<PatientCaregiverLink>> Function();
// 함수이름: CaregiverMonitoringLoader
// 함수역할: 환자별 연동·알림 설정·오늘 일정을 통합 조회하는 선택적 감시 경계이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<List<CaregiverMonitoringSnapshot>>: 환자별 연동·알림 설정·오늘 일정을 통합 조회하는 선택적 감시 경계이다.
typedef CaregiverMonitoringLoader =
    Future<List<CaregiverMonitoringSnapshot>> Function();
// 함수이름: CaregiverSettingsLoader
// 함수역할: 지정 환자의 모든 시간대별 보호자 알림 설정을 조회하는 경계이다.
// 매개변수:
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// 반환값:
// - Future<Map<String, CaregiverNotification>>: 지정 환자의 모든 시간대별 보호자 알림 설정을 조회하는 경계이다.
typedef CaregiverSettingsLoader =
    Future<Map<String, CaregiverNotification>> Function(String patientHash);
// 함수이름: CaregiverScheduleLoader
// 함수역할: 지정 환자의 오늘 복약 일정과 완료 상태를 조회하는 경계이다.
// 매개변수:
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// 반환값:
// - Future<List<MedicationSchedule>>: 지정 환자의 오늘 복약 일정과 완료 상태를 조회하는 경계이다.
typedef CaregiverScheduleLoader =
    Future<List<MedicationSchedule>> Function(String patientHash);
// 함수이름: CaregiverAlertSender
// 함수역할: 고정 ID와 제목·본문·환자 범위를 받아 보호자 기기에 즉시 알림을 전달하는 경계이다.
// 매개변수:
// - id (int): 플랫폼 알림의 예약·교체·취소 식별자
// - title (String): 기기 알림에 표시할 제목
// - body (String): 전송하거나 표시할 메시지·알림 본문
// - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
// 반환값:
// - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
typedef CaregiverAlertSender =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required String patientHash,
    });
// 함수이름: NotificationPermissionRequester
// 함수역할: 기기 알림 표시 권한을 요청하고 허용 여부를 비동기로 제공하는 경계이다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<bool>: 기기 알림 표시 권한을 요청하고 허용 여부를 비동기로 제공하는 경계이다.
typedef NotificationPermissionRequester = Future<bool> Function();
// 함수이름: PreferencesLoader
// 함수역할: 보호자 감시 스냅샷과 중복 알림 기록에 사용할 기기 설정 저장소를 비동기로 제공한다.
// 매개변수:
// - 없음.
// 반환값:
// - Future<SharedPreferences>: 보호자 감시 스냅샷과 중복 알림 기록에 사용할 기기 설정 저장소를 비동기로 제공한다.
typedef PreferencesLoader = Future<SharedPreferences> Function();
// 함수이름: CaregiverLanguageProvider
// 함수역할: 알림 생성 시점의 현재 앱 언어 코드를 제공해 감시 중 언어 변경을 반영하는 계약이다.
// 매개변수:
// - 없음.
// 반환값:
// - String: 알림 생성 시점의 현재 앱 언어 코드를 제공해 감시 중 언어 변경을 반영하는 계약이다.
typedef CaregiverLanguageProvider = String Function();

// Class Name: CaregiverNotificationMonitorService
// Role: Converts linked-patient completion changes and missed deadlines into caregiver alerts.
// Responsibilities:
// - Restrict checks to active caregiver links, persist per-slot snapshots, isolate patient failures, and suppress duplicate alerts.
// Attributes:
// - caregiverHash (String): Caregiver hash defining the lookup or persistence scope.
// - _loadMonitoringSnapshots (CaregiverMonitoringLoader?): Optional aggregate loader of per-patient settings and schedules.
// - _loadLinks (CaregiverLinkLoader): Boundary for loading active patient-caregiver links.
// - _loadSettings (CaregiverSettingsLoader): Loader of slot-specific alarm or notification settings.
// - _loadSchedules (CaregiverScheduleLoader): Loader of the target patient's medication schedules.
// - _sendAlert (CaregiverAlertSender): Boundary that displays the local alert.
// - _requestPermission (NotificationPermissionRequester): Whether the monitor may request platform notification permission.
// - _languageProvider (CaregiverLanguageProvider): Provider of the language at notification creation time.
// - _now (DateTime Function()): Reference current time or injected clock, as typed.
// - pollingInterval (Duration): Poll interval while caregiver links are active.
// - idlePollingInterval (Duration): Poll interval when no caregiver links are active.
// - requestPermission (bool): Whether the monitor may request platform notification permission.
// - monitorCompletionTransitions (bool): Whether to monitor transitions to full slot completion.
// - _onCaregiverStatusChanged (ValueChanged<bool>?): Receiver of changes to active caregiver-link presence.
// - _onDispose (VoidCallback?): Callback releasing owned dependencies.
// - _hasCaregiverLinks (bool): Whether the current user has active caregiver links.
class CaregiverNotificationMonitorService {
  static const Duration defaultPollingInterval = Duration(seconds: 15);
  static const Duration defaultIdlePollingInterval = Duration(minutes: 5);
  static const int maximumParallelPatientChecks = 4;

  final String caregiverHash;
  final CaregiverMonitoringLoader? _loadMonitoringSnapshots;
  final CaregiverLinkLoader _loadLinks;
  final CaregiverSettingsLoader _loadSettings;
  final CaregiverScheduleLoader _loadSchedules;
  final CaregiverAlertSender _sendAlert;
  final NotificationPermissionRequester _requestPermission;
  final PreferencesLoader _loadPreferences;
  final CaregiverLanguageProvider _languageProvider;
  final DateTime Function() _now;
  final Duration pollingInterval;
  final Duration idlePollingInterval;
  final bool requestPermission;
  final bool monitorCompletionTransitions;
  final ValueChanged<bool>? _onCaregiverStatusChanged;
  final VoidCallback? _onDispose;

  Timer? _timer;
  bool _isChecking = false;
  bool _permissionRequested = false;
  bool _notificationPermissionGranted = true;
  Future<bool>? _permissionRequestFuture;
  bool _hasCaregiverLinks = false;
  bool _isDisposed = false;
  int _consecutiveFailures = 0;

  // 함수이름: hasCaregiverLinks
  // 함수역할: 최근 조회에 현재 사용자가 보호자인 활성 환자 연동이 있었는지 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 현재 사용자의 활성 보호자 연동 존재 여부
  bool get hasCaregiverLinks => _hasCaregiverLinks;

  // 함수이름: CaregiverNotificationMonitorService
  // 함수역할: 환자 조회·알림·권한·저장소·시계 경계를 주입하고 활성·유휴 폴링 주기와 완료 변화 감시 정책을 설정한다.
  // 매개변수:
  // - caregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - loadMonitoringSnapshots (CaregiverMonitoringLoader?): 환자별 설정·일정을 통합 조회할 선택적 경계
  // - loadLinks (CaregiverLinkLoader): 활성 환자·보호자 연동 조회 경계
  // - loadSettings (CaregiverSettingsLoader): 시간대별 알림 조건 조회 경계
  // - loadSchedules (CaregiverScheduleLoader): 대상 환자의 복약 일정 조회 경계
  // - sendAlert (CaregiverAlertSender): 실제 로컬 알림 표시를 수행할 경계
  // - permissionRequester (NotificationPermissionRequester): 기기 알림 권한 요청 경계
  // - preferencesLoader (PreferencesLoader): 기기 설정 저장소 제공 경계
  // - languageProvider (CaregiverLanguageProvider?): 알림 생성 시점의 언어 조회 경계
  // - now (DateTime Function()?): 현재 시각을 제공하는 주입 가능한 시계
  // - pollingInterval (Duration): 활성 보호자 연동이 있을 때 확인 간격
  // - idlePollingInterval (Duration): 활성 보호자 연동이 없을 때의 확인 간격
  // - requestPermission (bool): 감시 중 운영체제 권한 요청을 수행할지 여부
  // - monitorCompletionTransitions (bool): 미완료에서 전체 완료로 바뀐 순간을 감시할지 여부
  // - onCaregiverStatusChanged (ValueChanged<bool>?): 활성 보호자 연동 존재 여부 변경 수신자
  // - onDispose (VoidCallback?): 소유한 의존성 정리 콜백
  // 반환값:
  // - CaregiverNotificationMonitorService: 초기화된 인스턴스.
  CaregiverNotificationMonitorService({
    required this.caregiverHash,
    CaregiverMonitoringLoader? loadMonitoringSnapshots,
    required CaregiverLinkLoader loadLinks,
    required CaregiverSettingsLoader loadSettings,
    required CaregiverScheduleLoader loadSchedules,
    required CaregiverAlertSender sendAlert,
    required NotificationPermissionRequester permissionRequester,
    PreferencesLoader preferencesLoader = SharedPreferences.getInstance,
    CaregiverLanguageProvider? languageProvider,
    DateTime Function()? now,
    this.pollingInterval = defaultPollingInterval,
    this.idlePollingInterval = defaultIdlePollingInterval,
    this.requestPermission = true,
    this.monitorCompletionTransitions = true,
    ValueChanged<bool>? onCaregiverStatusChanged,
    VoidCallback? onDispose,
  }) : _loadMonitoringSnapshots = loadMonitoringSnapshots,
       _loadLinks = loadLinks,
       _loadSettings = loadSettings,
       _loadSchedules = loadSchedules,
       _sendAlert = sendAlert,
       _requestPermission = permissionRequester,
       _loadPreferences = preferencesLoader,
       _languageProvider = languageProvider ?? _defaultLanguage,
       _now = now ?? DateTime.now,
       _onCaregiverStatusChanged = onCaregiverStatusChanged,
       _onDispose = onDispose;

  // 함수이름: _defaultLanguage
  // 함수역할: 언어 제공자가 주입되지 않은 감시에 한국어 기본 코드를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 언어 제공자가 주입되지 않은 감시에 한국어 기본 코드를 제공한다.
  static String _defaultLanguage() => 'ko';

  // 함수이름: start
  // 함수역할: 앱 실행 중 즉시 한 번 확인하고 이후 짧은 주기로 상태를 갱신한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> start() async {
    _timer?.cancel();
    await checkNow();
    _scheduleNextCheck();
  }

  // 함수이름: checkNow
  // 함수역할: 현재 보호자와 연결된 환자별 알림 조건을 한 번 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 확인이 정상 완료됐으면 true
  Future<bool> checkNow() async {
    if (_isChecking) {
      return false;
    }
    _isChecking = true;
    try {
      final normalizedCaregiverHash = PatientHash.normalizePatientHash(
        caregiverHash,
      );
      final preferences = await _loadPreferences();
      final aggregateLoader = _loadMonitoringSnapshots;
      if (aggregateLoader != null) {
        try {
          final snapshots = await aggregateLoader();
          final succeeded = await _checkMonitoringSnapshots(
            preferences,
            normalizedCaregiverHash,
            snapshots,
          );
          _recordCheckResult(succeeded);
          return succeeded;
        } catch (error, stackTrace) {
          developer.log(
            '보호자 통합 조회에 실패해 기존 환자별 조회로 전환합니다.',
            name: 'CaregiverNotificationMonitorService',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final succeeded = await _checkPatientsIndividually(
        preferences,
        normalizedCaregiverHash,
      );
      _recordCheckResult(succeeded);
      return succeeded;
    } catch (error, stackTrace) {
      developer.log(
        '보호자 알림 상태 확인에 실패했습니다.',
        name: 'CaregiverNotificationMonitorService',
        error: error,
        stackTrace: stackTrace,
      );
      _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, 4);
      return false;
    } finally {
      _isChecking = false;
    }
  }

  // 함수이름: _checkMonitoringSnapshots
  // 함수역할: 서버가 한 번에 반환한 여러 환자의 연동, 별칭, 설정, 일정을 처리한다. 서버 별칭을 기기 캐시에 반영해 오프라인에서도 같은 이름을 유지한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - normalizedCaregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - snapshots (List<CaregiverMonitoringSnapshot>): 환자별 연동·설정·일정의 통합 조회 자료
  // 반환값:
  // - Future<bool>: 서버가 한 번에 반환한 여러 환자의 연동, 별칭, 설정, 일정을 처리한다. 서버 별칭을 기기 캐시에 반영해 오프라인에서도 같은 이름을 유지한다.
  Future<bool> _checkMonitoringSnapshots(
    SharedPreferences preferences,
    String normalizedCaregiverHash,
    List<CaregiverMonitoringSnapshot> snapshots,
  ) async {
    final validSnapshots = snapshots
        .where(/* 함수이름: where 콜백
         * 함수역할: 현재 보호자의 유효한 연결 중 자신이 아닌 환자의 스냅샷만 남긴다.
         * 매개변수:
         * - snapshot (CaregiverMonitoringSnapshot): 활성 여부를 확인할 환자 감시 스냅샷
         * 반환값:
         * - 감시할 수 있는 활성 환자 연결이면 true.
         */(snapshot) {
          final link = snapshot.link;
          return link.linkStatus &&
              PatientHash.normalizePatientHash(link.caregiverHash) ==
                  normalizedCaregiverHash &&
              link.patientHash.trim().isNotEmpty &&
              PatientHash.normalizePatientHash(link.patientHash) !=
                  normalizedCaregiverHash;
        })
        .toList(growable: false);
    final patientHashes = validSnapshots
        .map(
          // 함수이름: map 콜백
          // 함수역할: 활성 모니터링 스냅샷에서 정규화된 환자 해시를 추출한다.
          // 매개변수:
          // - snapshot (CaregiverMonitoringSnapshot): 활성 여부를 확인할 환자 감시 스냅샷
          // 반환값:
          // - 정규화된 환자 해시.
          (snapshot) => PatientHash.normalizePatientHash(snapshot.patientHash),
        )
        .toSet()
        .toList(growable: false);
    await _synchronizeLinkedPatients(
      preferences,
      normalizedCaregiverHash,
      patientHashes,
    );

    var allPatientChecksSucceeded = true;
    for (final snapshot in validSnapshots) {
      try {
        final patientHash = PatientHash.normalizePatientHash(
          snapshot.patientHash,
        );
        final serverAlias = snapshot.patientAlias;
        if (serverAlias != null) {
          // 서버의 빈 문자열은 명시적인 별칭 삭제이므로 로컬 캐시에도 반영한다.
          await CaregiverPatientLocalStateService.saveLabel(
            preferences,
            caregiverHash: normalizedCaregiverHash,
            patientHash: patientHash,
            label: serverAlias,
          );
        }
        await _checkResolvedPatient(
          preferences,
          patientHash,
          snapshot.notificationSettings,
          snapshot.schedules,
        );
      } catch (error, stackTrace) {
        allPatientChecksSucceeded = false;
        developer.log(
          '통합 응답에서 연동 환자 한 명의 알림 처리를 완료하지 못했습니다.',
          name: 'CaregiverNotificationMonitorService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return allPatientChecksSucceeded;
  }

  // 함수이름: _checkPatientsIndividually
  // 함수역할: 통합 API를 사용할 수 없을 때 기존 환자별 조회 방식으로 복구한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - normalizedCaregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // 반환값:
  // - Future<bool>: 통합 API를 사용할 수 없을 때 기존 환자별 조회 방식으로 복구한다.
  Future<bool> _checkPatientsIndividually(
    SharedPreferences preferences,
    String normalizedCaregiverHash,
  ) async {
    final links = await _loadLinks();
    final patientHashes = links
        .where(/* 함수이름: where 콜백
         * 함수역할: 보호자 해시가 일치하고 환자 해시가 비어 있지 않으며 본인이 아닌 활성 연결을 선택한다.
         * 매개변수:
         * - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
         * 반환값:
         * - 현재 보호자가 감시할 활성 환자 연결이면 true.
         */(link) {
          return link.linkStatus &&
              PatientHash.normalizePatientHash(link.caregiverHash) ==
                  normalizedCaregiverHash &&
              link.patientHash.trim().isNotEmpty &&
              PatientHash.normalizePatientHash(link.patientHash) !=
                  normalizedCaregiverHash;
        })
        .map(/* 함수이름: map 콜백
         * 함수역할: 활성 연결의 환자 해시를 공통 비교 형식으로 정규화한다.
         * 매개변수:
         * - link (PatientCaregiverLink): 해당 환자·보호자 연동 관계
         * 반환값:
         * - 정규화된 환자 해시.
         */(link) => PatientHash.normalizePatientHash(link.patientHash))
        .toSet()
        .toList(growable: false);
    await _synchronizeLinkedPatients(
      preferences,
      normalizedCaregiverHash,
      patientHashes,
    );

    var allPatientChecksSucceeded = true;
    for (
      var start = 0;
      start < patientHashes.length;
      start += maximumParallelPatientChecks
    ) {
      final proposedEnd = start + maximumParallelPatientChecks;
      final end = proposedEnd < patientHashes.length
          ? proposedEnd
          : patientHashes.length;
      final results = await Future.wait(
        patientHashes
            .sublist(start, end)
            .map(
              // 함수이름: map 콜백
              // 함수역할: 환자별 확인 작업을 오류 격리 경로로 실행한다.
              // 매개변수:
              // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
              // 반환값:
              // - 해당 환자 감시 성공 여부를 완료하는 Future.
              (patientHash) => _checkPatientSafely(preferences, patientHash),
            ),
      );
      if (results.any(/* 함수이름: any 콜백
       * 함수역할: 병렬 환자 확인 결과에 실패가 있는지 검사한다.
       * 매개변수:
       * - succeeded (bool): 해당 환자의 감시 확인 성공 여부
       * 반환값:
       * - 해당 환자 확인이 실패했으면 true.
       */(succeeded) => !succeeded)) {
        allPatientChecksSucceeded = false;
      }
    }
    return allPatientChecksSucceeded;
  }

  // 함수이름: _synchronizeLinkedPatients
  // 함수역할: 활성 환자 목록을 기기에 반영해 해제된 환자 기록을 정리하고 보호자 연동 존재 상태를 갱신한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - normalizedCaregiverHash (String): 조회·저장 범위를 제한할 보호자 해시
  // - patientHashes (List<String>): 현재 활성 연동된 환자 해시 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _synchronizeLinkedPatients(
    SharedPreferences preferences,
    String normalizedCaregiverHash,
    List<String> patientHashes,
  ) async {
    await CaregiverPatientLocalStateService.synchronizeLinkedPatients(
      preferences,
      caregiverHash: normalizedCaregiverHash,
      patientHashes: patientHashes,
    );
    _updateCaregiverStatus(patientHashes.isNotEmpty);
  }

  // 함수이름: _recordCheckResult
  // 함수역할: 확인 성공 시 연속 실패 수를 초기화하고 실패 시 최대 4까지 올려 다음 폴링 지연을 조절한다.
  // 매개변수:
  // - succeeded (bool): 이번 확인 또는 처리의 성공 여부
  // 반환값:
  // - 없음.
  void _recordCheckResult(bool succeeded) {
    _consecutiveFailures = succeeded
        ? 0
        : (_consecutiveFailures + 1).clamp(0, 4);
  }

  // 함수이름: _checkPatientSafely
  // 함수역할: 한 환자 조회 실패를 격리해 같은 묶음의 다른 환자 확인을 계속 진행한다.
  // 매개변수:
  // - preferences (SharedPreferences): 보호자 알림 상태를 기록할 로컬 저장소
  // - patientHash (String): 확인할 환자 식별 hash
  // 반환값:
  // - 해당 환자 확인이 정상 완료됐으면 true
  Future<bool> _checkPatientSafely(
    SharedPreferences preferences,
    String patientHash,
  ) async {
    try {
      await _checkPatient(preferences, patientHash);
      return true;
    } catch (error, stackTrace) {
      developer.log(
        '연동 환자 한 명의 알림 상태 확인에 실패했습니다.',
        name: 'CaregiverNotificationMonitorService',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  // 함수이름: _scheduleNextCheck
  // 함수역할: 보호자 연결이 있으면 짧은 주기, 없으면 저빈도 주기로 다음 확인을 예약한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _scheduleNextCheck() {
    if (_isDisposed) {
      return;
    }
    _timer?.cancel();
    final baseInterval = _hasCaregiverLinks
        ? pollingInterval
        : idlePollingInterval;
    final multiplier = 1 << _consecutiveFailures;
    final proposedMilliseconds = baseInterval.inMilliseconds * multiplier;
    final maximumMilliseconds = const Duration(minutes: 5).inMilliseconds;
    final nextInterval = Duration(
      milliseconds: proposedMilliseconds.clamp(1000, maximumMilliseconds),
    );
    _timer = Timer(nextInterval, /* 함수이름: Timer 콜백
     * 함수역할: 다음 확인 시점에 보호자 감시를 실행하고 후속 확인 타이머를 예약한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 현재 확인과 다음 예약이 완료되는 Future.
     */() async {
      await checkNow();
      _scheduleNextCheck();
    });
  }

  // 함수이름: _updateCaregiverStatus
  // 함수역할: 보호자 연동 존재 여부가 달라진 경우에만 상태를 교체하고 외부 콜백에 알린다.
  // 매개변수:
  // - hasCaregiverLinks (bool): 현재 사용자의 활성 보호자 연동 존재 여부
  // 반환값:
  // - 없음.
  void _updateCaregiverStatus(bool hasCaregiverLinks) {
    if (_hasCaregiverLinks == hasCaregiverLinks) {
      return;
    }
    _hasCaregiverLinks = hasCaregiverLinks;
    _onCaregiverStatusChanged?.call(hasCaregiverLinks);
  }

  // 함수이름: _checkPatient
  // 함수역할: 환자 알림 설정을 먼저 조회하고 활성 조건이 있을 때만 일정을 가져와 시간대별 검사를 수행한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _checkPatient(
    SharedPreferences preferences,
    String patientHash,
  ) async {
    final settings = await _loadSettings(patientHash);
    final hasActiveSetting = settings.values.any(
      // 함수이름: any 콜백
      // 함수역할: 환자의 시간대 설정 중 하나라도 보호자 알림이 켜져 있는지 검사한다.
      // 매개변수:
      // - setting (CaregiverNotification): 확인할 환자 시간대의 보호자 알림 모드와 제한 시각
      // 반환값:
      // - 해당 설정이 비활성 모드가 아니면 true.
      (setting) => setting.mode != CaregiverNotificationMode.disabled,
    );
    final schedules = hasActiveSetting
        ? await _loadSchedules(patientHash)
        : const <MedicationSchedule>[];
    await _checkResolvedPatient(preferences, patientHash, settings, schedules);
  }

  // 함수이름: _checkResolvedPatient
  // 함수역할: 모든 지원 시간대를 순회하고 누락 설정은 비활성 기본값으로 보완해 시간대 조건을 독립적으로 확인한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - settings (Map<String, CaregiverNotification>): 시간대 키로 조회할 보호자 알림 설정
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _checkResolvedPatient(
    SharedPreferences preferences,
    String patientHash,
    Map<String, CaregiverNotification> settings,
    List<MedicationSchedule> schedules,
  ) async {
    for (final slotKey in caregiverNotificationSlotKeys) {
      final setting =
          settings[slotKey] ??
          CaregiverNotification(
            patientHash: patientHash,
            caregiverHash: caregiverHash,
            slotKey: slotKey,
          );
      await _checkSlot(
        preferences: preferences,
        patientHash: patientHash,
        slotKey: slotKey,
        setting: setting,
        schedules: schedules,
      );
    }
  }

  // 함수이름: _checkSlot
  // 함수역할: 한 복약 시간대의 완료 변화 또는 미복용 마감 조건만 독립적으로 확인한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - setting (CaregiverNotification): 확인할 환자 시간대의 보호자 알림 모드와 제한 시각
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _checkSlot({
    required SharedPreferences preferences,
    required String patientHash,
    required String slotKey,
    required CaregiverNotification setting,
    required List<MedicationSchedule> schedules,
  }) async {
    final scope = _preferenceScope(patientHash, slotKey);
    if (setting.mode == CaregiverNotificationMode.disabled) {
      await preferences.remove('$scope.snapshot_date');
      await preferences.remove('$scope.snapshot_data');
      await preferences.remove('$scope.completion_notice');
      await preferences.remove('$scope.deadline_notice');
      await preferences.setString('$scope.mode', setting.mode.wireValue);
      return;
    }

    final now = _now();
    final dateKey = _dateKey(now);
    final currentSnapshot = _buildSnapshot(schedules, slotKey);
    final previousDate = preferences.getString('$scope.snapshot_date');
    final previousMode = preferences.getString('$scope.mode');
    final previousSnapshot = previousDate == dateKey
        ? _decodeSnapshot(preferences.getString('$scope.snapshot_data'))
        : const <String, bool>{};
    final isComparableSnapshot =
        previousDate == dateKey && previousMode == setting.mode.wireValue;

    if (monitorCompletionTransitions &&
        setting.mode == CaregiverNotificationMode.doseCompleted &&
        isComparableSnapshot) {
      await _notifyCompletedSlot(
        preferences: preferences,
        scope: scope,
        patientHash: patientHash,
        slotKey: slotKey,
        previousSnapshot: previousSnapshot,
        currentSnapshot: currentSnapshot,
        dateKey: dateKey,
      );
    }
    if (setting.mode == CaregiverNotificationMode.missedDeadline) {
      await _notifyMissedDeadline(
        preferences: preferences,
        scope: scope,
        patientHash: patientHash,
        slotKey: slotKey,
        setting: setting,
        schedules: schedules,
        now: now,
        dateKey: dateKey,
      );
    }

    await preferences.setString('$scope.mode', setting.mode.wireValue);
    await preferences.setString('$scope.snapshot_date', dateKey);
    await preferences.setString(
      '$scope.snapshot_data',
      jsonEncode(currentSnapshot),
    );
  }

  // Function Name: _notifyCompletedSlot
  // Description: Sends at most one daily slot alert when a nonempty schedule becomes fully completed; individual drug transitions do not create separate alerts, and permission denial leaves the notice unrecorded.
  // Parameters:
  // - preferences (SharedPreferences): Device preference store for user settings and alert records.
  // - scope (String): Alert-history prefix scoped by date, patient, and time slot.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - previousSnapshot (Map<String, bool>): Previous completion flags stored for the same date and mode.
  // - currentSnapshot (Map<String, bool>): Current per-course completion flags for the slot.
  // - dateKey (String): Calendar key for daily snapshots and alert deduplication.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _notifyCompletedSlot({
    required SharedPreferences preferences,
    required String scope,
    required String patientHash,
    required String slotKey,
    required Map<String, bool> previousSnapshot,
    required Map<String, bool> currentSnapshot,
    required String dateKey,
  }) async {
    final wasSlotCompleted =
        previousSnapshot.isNotEmpty &&
        previousSnapshot.values.every(/* 함수이름: every 콜백
         * 함수역할: 이전 시간대 상태가 모두 복약 완료인지 검사한다.
         * 매개변수:
         * - value (bool): 저장된 복약 완료 상태 값
         * 반환값:
         * - 해당 이전 상태의 완료 여부.
         */(value) => value);
    final isSlotCompleted =
        currentSnapshot.isNotEmpty &&
        currentSnapshot.values.every(/* 함수이름: every 콜백
         * 함수역할: 현재 시간대 상태가 모두 복약 완료인지 검사한다.
         * 매개변수:
         * - value (bool): 저장된 복약 완료 상태 값
         * 반환값:
         * - 해당 현재 상태의 완료 여부.
         */(value) => value);
    if (wasSlotCompleted || !isSlotCompleted) {
      return;
    }
    final noticeSignature = '$dateKey|$slotKey';
    if (preferences.getString('$scope.completion_notice') == noticeSignature) {
      return;
    }
    final permissionGranted = await _ensureNotificationPermission();
    if (!permissionGranted) {
      return;
    }
    final text = _CaregiverNotificationText(_languageProvider());
    final slotName = text.slotName(slotKey);
    await _sendAlert(
      id: _stableNotificationId('completed|$patientHash|$dateKey|$slotKey'),
      title: text.completedTitle,
      body: text.completedBody(slotName),
      patientHash: patientHash,
    );
    await preferences.setString('$scope.completion_notice', noticeSignature);
  }

  // 함수이름: _notifyMissedDeadline
  // 함수역할: 유효한 마감 이후 남은 미복약 일정이 있을 때만 허용된 알림을 보내고 날짜·시간대·마감 시각 서명으로 중복을 방지한다.
  // 매개변수:
  // - preferences (SharedPreferences): 사용자별 설정·알림 기록을 읽고 쓸 기기 저장소
  // - scope (String): 날짜·환자·시간대별 알림 기록 저장 접두사
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - setting (CaregiverNotification): 확인할 환자 시간대의 보호자 알림 모드와 제한 시각
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // - now (DateTime): 비교와 날짜 계산의 기준 시각
  // - dateKey (String): 일별 스냅샷 및 알림 중복 방지 날짜 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _notifyMissedDeadline({
    required SharedPreferences preferences,
    required String scope,
    required String patientHash,
    required String slotKey,
    required CaregiverNotification setting,
    required List<MedicationSchedule> schedules,
    required DateTime now,
    required String dateKey,
  }) async {
    if (!setting.hasValidDeadline) {
      return;
    }
    final deadline = DateTime(
      now.year,
      now.month,
      now.day,
      setting.deadlineHour!,
      setting.deadlineMinute!,
    );
    if (now.isBefore(deadline)) {
      return;
    }

    final noticeSignature =
        '$dateKey|$slotKey|${setting.deadlineHour}|'
        '${setting.deadlineMinute}';
    if (preferences.getString('$scope.deadline_notice') == noticeSignature) {
      return;
    }
    final slotSchedules = schedules
        .where(/* 함수이름: where 콜백
         * 함수역할: 확인 중인 시간대에 포함되는 약 일정만 선택한다.
         * 매개변수:
         * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
         * 반환값:
         * - 일정에 대상 시간대가 포함되면 true.
         */(schedule) => schedule.slotKeys.contains(slotKey))
        .toList(growable: false);
    if (slotSchedules.isEmpty) {
      return;
    }
    final remainingCount = slotSchedules
        .where(/* 함수이름: where 콜백
         * 함수역할: 대상 시간대에 아직 복용하지 않은 약 일정을 선택한다.
         * 매개변수:
         * - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
         * 반환값:
         * - 해당 시간대의 복약이 미완료이면 true.
         */(schedule) => !schedule.isSlotCompleted(slotKey))
        .length;
    if (remainingCount == 0) {
      await preferences.setString('$scope.deadline_notice', noticeSignature);
      return;
    }

    final permissionGranted = await _ensureNotificationPermission();
    if (!permissionGranted) {
      return;
    }
    final deadlineLabel =
        '${setting.deadlineHour!.toString().padLeft(2, '0')}:'
        '${setting.deadlineMinute!.toString().padLeft(2, '0')}';
    final text = _CaregiverNotificationText(_languageProvider());
    final slotName = text.slotName(slotKey);
    await _sendAlert(
      id: _stableNotificationId('missed|$patientHash|$noticeSignature'),
      title: text.missedTitle,
      body: text.missedBody(
        slotName: slotName,
        deadlineLabel: deadlineLabel,
        remainingCount: remainingCount,
      ),
      patientHash: patientHash,
    );
    await preferences.setString('$scope.deadline_notice', noticeSignature);
  }

  // 함수이름: _ensureNotificationPermission
  // 함수역할: 권한 요청 생략 정책을 존중하고 진행 중 요청 또는 최초 권한 결과를 재사용해 중복 권한 창을 막는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 권한 요청 생략 정책을 존중하고 진행 중 요청 또는 최초 권한 결과를 재사용해 중복 권한 창을 막는다.
  Future<bool> _ensureNotificationPermission() async {
    if (!requestPermission) {
      return true;
    }
    if (_permissionRequested) {
      final pendingRequest = _permissionRequestFuture;
      if (pendingRequest != null) {
        return pendingRequest;
      }
      return _notificationPermissionGranted;
    }
    _permissionRequested = true;
    final requestFuture = _requestPermission();
    _permissionRequestFuture = requestFuture;
    try {
      _notificationPermissionGranted = await requestFuture;
      return _notificationPermissionGranted;
    } finally {
      _permissionRequestFuture = null;
    }
  }

  // 함수이름: _buildSnapshot
  // 함수역할: 선택 시간대에 속한 일정만 골라 안정 일정 키와 해당 시간대 완료 여부의 사전으로 만든다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Map<String, bool>: 선택 시간대에 속한 일정만 골라 안정 일정 키와 해당 시간대 완료 여부의 사전으로 만든다.
  Map<String, bool> _buildSnapshot(
    List<MedicationSchedule> schedules,
    String slotKey,
  ) {
    final snapshot = <String, bool>{};
    for (final schedule in schedules) {
      if (schedule.slotKeys.contains(slotKey)) {
        snapshot[_scheduleEntryKey(schedule, slotKey)] = schedule
            .isSlotCompleted(slotKey);
      }
    }
    return snapshot;
  }

  // 함수이름: _scheduleEntryKey
  // 함수역할: 저장 약 ID를 우선하고 없으면 약명·조제일을 사용해 시간대 내 일정 비교 키를 만든다.
  // 매개변수:
  // - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 저장 약 ID를 우선하고 없으면 약명·조제일을 사용해 시간대 내 일정 비교 키를 만든다.
  String _scheduleEntryKey(MedicationSchedule schedule, String slotKey) {
    final medicationKey = schedule.medicationID.trim().isNotEmpty
        ? schedule.medicationID.trim()
        : '${schedule.medicationName}|'
              '${schedule.prescriptionDate?.toIso8601String() ?? ''}';
    return '$slotKey|$medicationKey';
  }

  // 함수이름: _decodeSnapshot
  // 함수역할: 저장된 JSON 객체를 문자열 키·불리언 완료 값으로 복원하고 없거나 손상된 기록은 빈 스냅샷으로 취급한다.
  // 매개변수:
  // - rawSnapshot (String?): 기기에 저장된 선택적 완료 스냅샷 JSON
  // 반환값:
  // - Map<String, bool>: 저장된 JSON 객체를 문자열 키·불리언 완료 값으로 복원하고 없거나 손상된 기록은 빈 스냅샷으로 취급한다.
  Map<String, bool> _decodeSnapshot(String? rawSnapshot) {
    if (rawSnapshot == null || rawSnapshot.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! Map) {
        return const {};
      }
      return decoded.map(
        // 함수이름: map 콜백
        // 함수역할: 저장된 상태 맵의 키를 문자열로 맞추고 실제 true 값만 완료로 복원한다.
        // 매개변수:
        // - key (dynamic): Flutter 위젯의 동일성 키
        // - value (dynamic): 저장된 복약 완료 상태 값
        // 반환값:
        // - 문자열 키와 복약 완료 여부의 맵 항목.
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } catch (_) {
      return const {};
    }
  }

  // 함수이름: _preferenceScope
  // 함수역할: 보호자·환자·시간대를 결합해 알림 스냅샷과 중복 방지 기록이 섞이지 않는 저장 접두사를 만든다.
  // 매개변수:
  // - patientHash (String): 조회·저장·알림 대상 환자의 소유권 해시
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 보호자·환자·시간대를 결합해 알림 스냅샷과 중복 방지 기록이 섞이지 않는 저장 접두사를 만든다.
  String _preferenceScope(String patientHash, String slotKey) {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    return 'caregiver_alert.$normalizedCaregiver.$patientHash.$slotKey';
  }

  // 함수이름: _dateKey
  // 함수역할: 감시 시각의 날짜를 연·월·일 두 자리 규칙의 YYYY-MM-DD 서명으로 만든다.
  // 매개변수:
  // - dateTime (DateTime): 달력 날짜 계산 또는 비교의 기준 시각
  // 반환값:
  // - String: 감시 시각의 날짜를 연·월·일 두 자리 규칙의 YYYY-MM-DD 서명으로 만든다.
  String _dateKey(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}';
  }

  // 함수이름: _stableNotificationId
  // 함수역할: 알림 구분 문자열을 FNV 방식으로 접어 보호자 알림용 300000~899999 범위의 안정 ID를 만든다.
  // 매개변수:
  // - source (String): 안정적인 알림 ID를 계산할 범위 문자열
  // 반환값:
  // - int: 알림 구분 문자열을 FNV 방식으로 접어 보호자 알림용 300000~899999 범위의 안정 ID를 만든다.
  int _stableNotificationId(String source) {
    var hash = 0x811C9DC5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 300000 + (hash % 600000);
  }

  // 함수이름: dispose
  // 함수역할: 실행 중인 감시 타이머와 내부 API control을 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _onDispose?.call();
  }
}

// Class Name: _CaregiverNotificationText
// Role: Supplies caregiver completion and missed-dose notification text in the selected language.
// Responsibilities:
// - Format slot names and remaining-count guidance without disclosing patient identifiers in message text.
// Attributes:
// - isEnglish (bool): Whether to select English display text.
class _CaregiverNotificationText {
  final bool isEnglish;

  // 함수이름: _CaregiverNotificationText
  // 함수역할: 언어 코드가 en인지 확인해 보호자 알림의 한국어·영어 문구 선택 상태를 만든다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - _CaregiverNotificationText: 초기화된 인스턴스.
  _CaregiverNotificationText(String language)
    : isEnglish = language.trim().toLowerCase() == 'en';

  // 함수이름: completedTitle
  // 함수역할: 환자의 시간대 복약이 모두 완료되었음을 알리는 제목을 현재 언어로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 환자의 시간대 복약이 모두 완료되었음을 알리는 제목을 현재 언어로 제공한다.
  String get completedTitle =>
      isEnglish ? 'Patient medication completed' : '환자 복약 완료';

  // Function Name: completedBody
  // Description: Formats the linked patient's all-medications-completed message using the supplied localized slot name.
  // Parameters:
  // - slotName (String): Localized medication slot name.
  // Returns:
  // - String: Formats the linked patient's all-medications-completed message using the supplied localized slot name.
  String completedBody(String slotName) => isEnglish
      ? 'The linked patient completed all $slotName medications.'
      : '연동된 환자의 $slotName 복약이 모두 완료되었습니다.';

  // 함수이름: missedTitle
  // 함수역할: 마감까지 확인되지 않은 복약 일정이 있음을 알리는 제목을 현재 언어로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 마감까지 확인되지 않은 복약 일정이 있음을 알리는 제목을 현재 언어로 제공한다.
  String get missedTitle => isEnglish ? 'Medication not checked' : '미복용 일정 확인';

  // Function Name: missedBody
  // Description: Formats unchecked medication count and deadline for a slot, choosing singular or plural English wording where appropriate.
  // Parameters:
  // - slotName (String): Localized medication slot name.
  // - deadlineLabel (String): Display label for the missed-dose deadline.
  // - remainingCount (int): Number of doses still unchecked after the deadline.
  // Returns:
  // - String: Formats unchecked medication count and deadline for a slot, choosing singular or plural English wording where appropriate.
  String missedBody({
    required String slotName,
    required String deadlineLabel,
    required int remainingCount,
  }) {
    if (isEnglish) {
      final itemLabel = remainingCount == 1 ? 'item remains' : 'items remain';
      return 'The linked patient has $remainingCount $slotName medication '
          '$itemLabel unchecked '
          'as of $deadlineLabel.';
    }
    return '연동된 환자의 $slotName 복약 중 $deadlineLabel 기준으로 '
        '아직 체크되지 않은 일정이 $remainingCount건 있습니다.';
  }

  // 함수이름: slotName
  // 함수역할: 복약 시간대 키에 맞는 한국어·영어 이름을 제공하고 알 수 없는 키에는 일반 일정 문구를 사용한다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - String: 복약 시간대 키에 맞는 한국어·영어 이름을 제공하고 알 수 없는 키에는 일반 일정 문구를 사용한다.
  String slotName(String slotKey) {
    return switch (slotKey) {
      'morning' => isEnglish ? 'morning' : '아침',
      'lunch' => isEnglish ? 'lunch' : '점심',
      'evening' => isEnglish ? 'evening' : '저녁',
      'bedtime' => isEnglish ? 'bedtime' : '취침 전',
      _ => isEnglish ? 'scheduled' : '복약 일정',
    };
  }
}
