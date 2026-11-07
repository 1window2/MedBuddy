part of 'medbuddy_view_model.dart';

// File Name: medbuddy_application_flows.dart
// Role: Coordinates recovery, refresh and account deletion across feature owners.

// Class Name: MedBuddyApplicationFlows
// Role: Coordinate recovery, refresh and account cleanup across feature owners.
// Responsibilities: Preserve refresh policies and explicit reset operations without taking ownership of feature-private state.
// Attributes: No extension-owned fields; uses the host view model's feature owners and refresh timestamp.
extension MedBuddyApplicationFlows on MedBuddyViewModel {
  // Function Name: recoverMedicationConnectivity
  // Description: Refreshes visible schedules and reminder settings after connectivity returns without replaying dose writes or replacing native alarms.
  // Parameters: None.
  // Returns: False when schedule loading is already active; otherwise whether both reads succeeded. Existing native snoozes remain untouched.
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

  // Function Name: refreshMedicationOverview
  // Description: Refreshes reminder settings and today's overview before conditional reminder reconciliation.
  // Parameters: None.
  // Returns: Completion of the shared read-and-reconcile flow.
  Future<void> refreshMedicationOverview() =>
      _refreshScheduleAndReminders(fetchTodayMedicationInfo);

  // Function Name: refreshMedicationSchedule
  // Description: Refreshes full schedules and reminder settings, optionally sharing current or recent successful work.
  // Parameters: reuseRecent: Reuse same-day success less than 15 seconds old.
  // Returns: A shared or new refresh Future; explicit error retries may start while an earlier reminder read is pending.
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
    refresh = _refreshScheduleAndReminders(
      fetchTodayMedicationSchedule,
    ).whenComplete(() {
      if (identical(_scheduleRefresh, refresh)) _scheduleRefresh = null;
    });
    return _scheduleRefresh = refresh;
  }

  // Function Name: _refreshScheduleAndReminders
  // Description: Loads reminder settings and the chosen schedule view concurrently, then reconciles only fresh data.
  // Parameters: fetch: Today's overview or full-schedule read.
  // Returns: Completion; records a reuse timestamp only when both reads succeed, otherwise clears it.
  Future<void> _refreshScheduleAndReminders(
    Future<void> Function() fetch,
  ) async {
    await Future.wait([
      loadMedicationReminderSettings(notifyAfterLoad: false),
      fetch(),
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
    try {
      await manageAccount.deleteAccountData();
    } catch (_) {
      // The account still exists: restore the worker and reminders that were
      // canceled above instead of leaving it without alarms until a restart.
      unawaited(
        MedicationReminderBackgroundScheduler.register(
          patientHash,
        ).catchError((Object _) {}),
      );
      unawaited(refreshMedicationSchedule().catchError((Object _) {}));
      rethrow;
    }
    // The server data and identity are already gone, so device cleanup is
    // best-effort: a storage failure must not stop sign-out finalization.
    try {
      await doseSync?.deleteAccountData();
    } catch (_) {
      // Pending dose records stay encrypted under the deleted account's key.
    }
    try {
      // On-device medication photos belong to the deleted account as well.
      await manualMedicationImageStore.removeOrphanImages(
        patientHash: patientHash,
        activeMedicationIds: const {},
      );
    } catch (_) {
      // A file-system failure must not block the remaining local cleanup.
    }
    clearAnalysisResult();
    _savedMedications.clear();
    _schedules.clear();
    _notifyViewModelListeners();
  }
}
