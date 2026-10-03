part of 'medbuddy_view_model.dart';

// File Name: medbuddy_application_flows.dart
// Role: Coordinates recovery, refresh and account deletion across feature owners.

// Class Name: MedBuddyApplicationFlows
// Role: Application-level coordination without owning feature-private state.
// Responsibilities: Preserve refresh/recovery policies and explicit reset operations.
extension MedBuddyApplicationFlows on MedBuddyViewModel {
  /// Reconcile only reads and local alarms; never replay a completion write.
  Future<bool> recoverMedicationConnectivity() async {
    if (_schedules.isTodayScheduleLoading) return false;
    // Foreground recovery refreshes the visible state without replacing native
    // alarms (which could otherwise erase an outstanding ten-minute snooze).
    // The persistent reminder worker owns rolling-window reconciliation.
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationSchedule(),
    ]);
    return _schedules.lastLoadSucceeded && _reminders.lastLoadSucceeded;
  }

  // 함수이름: refreshMedicationOverview
  // 함수역할: 알림 설정과 오늘 복약 요약을 함께 조회하고 일정 조회가 성공한 경우에만 로컬 예약을 동기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> refreshMedicationOverview() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationInfo(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    _scheduleRefreshedAt =
        _schedules.lastLoadSucceeded && _reminders.lastLoadSucceeded
        ? DateTime.now()
        : null;
  }

  // 함수이름: refreshMedicationSchedule
  // 함수역할: 알림 설정과 오늘 전체 일정을 함께 조회하고 최신 일정으로 알림 예약을 동기화한다.
  // 매개변수:
  // - reuseRecent (bool): 탭 재방문 시 같은 날의 최근 성공 조회를 재사용할지 여부.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> refreshMedicationSchedule({bool reuseRecent = false}) {
    final last = _scheduleRefreshedAt;
    final now = DateTime.now();
    if (reuseRecent &&
        last != null &&
        _schedules.lastLoadSucceeded &&
        _reminders.lastLoadSucceeded &&
        doseScheduleDay(last) == doseScheduleDay(now) &&
        now.difference(last) >= Duration.zero &&
        now.difference(last) < const Duration(seconds: 15)) {
      return Future<void>.value();
    }
    if (_scheduleRefresh != null &&
        (reuseRecent || !_schedules.hasTodayScheduleLoadError)) {
      return _scheduleRefresh!;
    }
    // 실패 화면의 명시적 재시도는 별도 알림 조회가 끝나기 전에도 허용한다.
    late final Future<void> refresh;
    refresh = _refreshMedicationSchedule().whenComplete(() {
      if (identical(_scheduleRefresh, refresh)) _scheduleRefresh = null;
    });
    return _scheduleRefresh = refresh;
  }

  Future<void> _refreshMedicationSchedule() async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetchTodayMedicationSchedule(),
    ]);
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    _scheduleRefreshedAt =
        _schedules.lastLoadSucceeded && _reminders.lastLoadSucceeded
        ? DateTime.now()
        : null;
  }

  // Function Name: requestAccountDataDeletion
  // Description: Cancels reminder work and session notifications, requests server and local account-data deletion, then clears analysis, saved-medication, and schedule state.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> requestAccountDataDeletion() async {
    await MedicationReminderBackgroundScheduler.cancel();
    await notificationService.cancelAllMedicationReminders();
    await manageAccount.deleteAccountData();
    await doseSync?.deleteAccountData();
    clearAnalysisResult();
    _savedMedications.clear();
    _schedules.clear();
    _notifyViewModelListeners();
  }
}
