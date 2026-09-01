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

typedef CaregiverLinkLoader = Future<List<PatientCaregiverLink>> Function();
typedef CaregiverMonitoringLoader =
    Future<List<CaregiverMonitoringSnapshot>> Function();
typedef CaregiverSettingsLoader =
    Future<Map<String, CaregiverNotification>> Function(String patientHash);
typedef CaregiverScheduleLoader =
    Future<List<MedicationSchedule>> Function(String patientHash);
typedef CaregiverAlertSender =
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required String patientHash,
    });
typedef NotificationPermissionRequester = Future<bool> Function();
typedef PreferencesLoader = Future<SharedPreferences> Function();
typedef CaregiverLanguageProvider = String Function();

// 클래스명: CaregiverNotificationMonitorService
// 역할:
// - 연동된 환자의 복약 체크 변화를 확인하고 보호자 로컬 알림으로 변환한다.
// 주요 책임:
// - 보호자로 연결된 환자만 조회한다.
// - 복용 완료 및 지정 시각 미복용 조건을 판정한다.
// - 같은 상태에 대한 중복 알림을 차단한다.
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

  bool get hasCaregiverLinks => _hasCaregiverLinks;

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

  static String _defaultLanguage() => 'ko';

  // 함수명: start
  // 역할:
  // - 앱 실행 중 즉시 한 번 확인하고 이후 짧은 주기로 상태를 갱신한다.
  // 반환값:
  // - 없음
  Future<void> start() async {
    _timer?.cancel();
    await checkNow();
    _scheduleNextCheck();
  }

  // 함수명: checkNow
  // 역할:
  // - 현재 보호자와 연결된 환자별 알림 조건을 한 번 확인한다.
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
  // 함수역할:
  // - 서버가 한 번에 반환한 여러 환자의 연동, 별칭, 설정, 일정을 처리한다.
  // - 서버 별칭을 기기 캐시에 반영해 오프라인에서도 같은 이름을 유지한다.
  Future<bool> _checkMonitoringSnapshots(
    SharedPreferences preferences,
    String normalizedCaregiverHash,
    List<CaregiverMonitoringSnapshot> snapshots,
  ) async {
    final validSnapshots = snapshots
        .where((snapshot) {
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
  // 함수역할:
  // - 통합 API를 사용할 수 없을 때 기존 환자별 조회 방식으로 복구한다.
  Future<bool> _checkPatientsIndividually(
    SharedPreferences preferences,
    String normalizedCaregiverHash,
  ) async {
    final links = await _loadLinks();
    final patientHashes = links
        .where((link) {
          return link.linkStatus &&
              PatientHash.normalizePatientHash(link.caregiverHash) ==
                  normalizedCaregiverHash &&
              link.patientHash.trim().isNotEmpty &&
              PatientHash.normalizePatientHash(link.patientHash) !=
                  normalizedCaregiverHash;
        })
        .map((link) => PatientHash.normalizePatientHash(link.patientHash))
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
              (patientHash) => _checkPatientSafely(preferences, patientHash),
            ),
      );
      if (results.any((succeeded) => !succeeded)) {
        allPatientChecksSucceeded = false;
      }
    }
    return allPatientChecksSucceeded;
  }

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

  void _recordCheckResult(bool succeeded) {
    _consecutiveFailures = succeeded
        ? 0
        : (_consecutiveFailures + 1).clamp(0, 4);
  }

  // 함수이름: _checkPatientSafely
  // 함수역할:
  // - 한 환자 조회 실패를 격리해 같은 묶음의 다른 환자 확인을 계속 진행한다.
  // 매개변수:
  // - preferences: 보호자 알림 상태를 기록할 로컬 저장소
  // - patientHash: 확인할 환자 식별 hash
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
  // 함수역할:
  // - 보호자 연결이 있으면 짧은 주기, 없으면 저빈도 주기로 다음 확인을 예약한다.
  // 반환값:
  // - 없음
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
    _timer = Timer(nextInterval, () async {
      await checkNow();
      _scheduleNextCheck();
    });
  }

  void _updateCaregiverStatus(bool hasCaregiverLinks) {
    if (_hasCaregiverLinks == hasCaregiverLinks) {
      return;
    }
    _hasCaregiverLinks = hasCaregiverLinks;
    _onCaregiverStatusChanged?.call(hasCaregiverLinks);
  }

  Future<void> _checkPatient(
    SharedPreferences preferences,
    String patientHash,
  ) async {
    final settings = await _loadSettings(patientHash);
    final hasActiveSetting = settings.values.any(
      (setting) => setting.mode != CaregiverNotificationMode.disabled,
    );
    final schedules = hasActiveSetting
        ? await _loadSchedules(patientHash)
        : const <MedicationSchedule>[];
    await _checkResolvedPatient(preferences, patientHash, settings, schedules);
  }

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

  // 함수명: _checkSlot
  // 역할:
  // - 한 복약 시간대의 완료 변화 또는 미복용 마감 조건만 독립적으로 확인한다.
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

  // 함수명: _notifyCompletedSlot
  // 역할:
  // - 시간대에 포함된 약이 하나 이상이고 모두 완료된 순간 보호자에게 한 번만 알린다.
  // - 약별 완료 변화는 알리지 않아 같은 시간대의 알림이 여러 번 울리지 않게 한다.
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
        previousSnapshot.values.every((value) => value);
    final isSlotCompleted =
        currentSnapshot.isNotEmpty &&
        currentSnapshot.values.every((value) => value);
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
        .where((schedule) => schedule.slotKeys.contains(slotKey))
        .toList(growable: false);
    if (slotSchedules.isEmpty) {
      return;
    }
    final remainingCount = slotSchedules
        .where((schedule) => !schedule.isSlotCompleted(slotKey))
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

  String _scheduleEntryKey(MedicationSchedule schedule, String slotKey) {
    final medicationKey = schedule.medicationID.trim().isNotEmpty
        ? schedule.medicationID.trim()
        : '${schedule.medicationName}|'
              '${schedule.prescriptionDate?.toIso8601String() ?? ''}';
    return '$slotKey|$medicationKey';
  }

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
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } catch (_) {
      return const {};
    }
  }

  String _preferenceScope(String patientHash, String slotKey) {
    final normalizedCaregiver = PatientHash.normalizePatientHash(caregiverHash);
    return 'caregiver_alert.$normalizedCaregiver.$patientHash.$slotKey';
  }

  String _dateKey(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}';
  }

  int _stableNotificationId(String source) {
    var hash = 0x811C9DC5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 300000 + (hash % 600000);
  }

  // 함수명: dispose
  // 역할:
  // - 실행 중인 감시 타이머와 내부 API control을 정리한다.
  // 반환값:
  // - 없음
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _onDispose?.call();
  }
}

// 클래스명: _CaregiverNotificationText
// 역할: 보호자 복약 완료 및 미복용 알림 문구를 현재 앱 언어로 제공한다.
class _CaregiverNotificationText {
  final bool isEnglish;

  _CaregiverNotificationText(String language)
    : isEnglish = language.trim().toLowerCase() == 'en';

  String get completedTitle =>
      isEnglish ? 'Patient medication completed' : '환자 복약 완료';

  String completedBody(String slotName) => isEnglish
      ? 'The linked patient completed all $slotName medications.'
      : '연동된 환자의 $slotName 복약이 모두 완료되었습니다.';

  String get missedTitle => isEnglish ? 'Medication not checked' : '미복용 일정 확인';

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
