import 'dart:async';

import '../controls/check_schedule_control.dart';
import '../controls/check_today_medication_info_control.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/dose_sync_service.dart';
import '../services/user_facing_error_message.dart';
import 'medbuddy_schedule_slot_policy.dart';

// 파일명: medbuddy_schedule_view_model.dart
// 역할: 오늘 복약 일정 조회와 시간대별 복용 완료 상태를 관리한다.

// Class Name: MedBuddyScheduleViewModel
// Role: Owns today's schedule projection and individual or whole-slot dose updates.
// Responsibilities: Reject stale loads and prior-day taps, merge durable pending changes and publish loading/failure state.
// Attributes: Borrowed query controls and runtime providers perform work; schedule list/day, request epochs and loading/error/status fields retain state.
class MedBuddyScheduleViewModel {
  // 기기 저장소가 응답하지 않아도 서버 일정 표시까지 함께 멈추지 않게 하는 대기 한도.
  static const _localStoreTimeout = Duration(seconds: 5);
  bool _isTodayScheduleLoading = false;
  // Function Name: isTodayScheduleLoading
  // Description: Exposes whether the tracked current schedule load is still pending.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether the tracked current schedule load is still pending.
  bool get isTodayScheduleLoading => _isTodayScheduleLoading;
  bool _hasSettledTodaySchedule = false;
  // Function Name: hasSettledTodaySchedule
  // Description: Distinguishes the initial unresolved schedule from a load that has settled successfully or unsuccessfully.
  // Parameters: None.
  // Returns: Whether today's schedule state has settled at least once.
  bool get hasSettledTodaySchedule => _hasSettledTodaySchedule;
  bool _hasTodayScheduleLoadError = false;
  // Function Name: hasTodayScheduleLoadError
  // Description: Exposes failure of the latest applicable schedule load for retry-state rendering.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Failure of the latest applicable schedule load for retry-state rendering.
  bool get hasTodayScheduleLoadError => _hasTodayScheduleLoadError;
  bool _lastTodayScheduleLoadSucceeded = false;
  // Application day of the list on screen; a tap on an earlier day's list is refused.
  String? _listedScheduleDay;
  int _todayScheduleEpoch = 0;
  // 가장 최근 일정 조회만 화면의 로딩 상태를 종료할 수 있도록 요청 번호를 보관한다.
  int? _activeTodayScheduleLoadEpoch;
  List<MedicationSchedule> _todayMedicationScheduleList = [];
  // Function Name: todayMedicationScheduleList
  // Description: Exposes an unmodifiable list of the currently loaded medication courses for today.
  // Parameters:
  // - None.
  // Returns:
  // - List<MedicationSchedule>: An unmodifiable list of the currently loaded medication courses for today.
  List<MedicationSchedule> get todayMedicationScheduleList =>
      List.unmodifiable(_todayMedicationScheduleList);
  final CheckSchedule checkSchedule;
  final CheckTodayMedicationInfo checkTodayMedicationInfo;
  final DoseSyncService? Function() _readDoseSync;
  final bool Function() _readEnglish;
  final void Function(String) _onChanged;
  bool _disposed = false;
  String _statusMessage = '';
  // Function Name: MedBuddyScheduleViewModel
  // Description: Bind borrowed schedule controls and current runtime providers.
  // Parameters: checkSchedule (CheckSchedule): schedule reads and writes; checkTodayMedicationInfo (CheckTodayMedicationInfo): daily summary; readDoseSync (DoseSyncService? Function()): current durable queue; readEnglish (bool Function()): locale; onChanged (void Function(String)): feature updates.
  // Returns: MedBuddyScheduleViewModel: schedule state owner.
  MedBuddyScheduleViewModel({
    required this.checkSchedule,
    required this.checkTodayMedicationInfo,
    required DoseSyncService? Function() readDoseSync,
    required bool Function() readEnglish,
    required void Function(String) onChanged,
  }) : _readDoseSync = readDoseSync,
       _readEnglish = readEnglish,
       _onChanged = onChanged;
  // Function Name: doseSync
  // Description: Reads the attached durable queue. Parameters: None. Returns: Queue or null.
  DoseSyncService? get doseSync => _readDoseSync();
  // Function Name: _isEnglishSetting
  // Description: Reads display locale. Parameters: None. Returns: English selection.
  bool get _isEnglishSetting => _readEnglish();
  // Function Name: lastLoadSucceeded
  // Description: Reports freshness for reminder reconciliation. Parameters: None. Returns: Freshness.
  bool get lastLoadSucceeded => _lastTodayScheduleLoadSucceeded;
  // Function Name: statusMessage
  // Description: Exposes schedule-local feedback. Parameters: None. Returns: Feedback.
  String get statusMessage => _statusMessage;
  // Function Name: _notifyViewModelListeners
  // Description: Publishes feature changes while alive. Parameters: None. Returns: None.
  void _notifyViewModelListeners() {
    if (!_disposed) _onChanged(_statusMessage);
  }

  // Function Name: applyDoseProjection
  // Description: Applies durable queue state without treating it as a fresh server read.
  // Parameters: schedules: Projected courses; hasCurrentDayCache: Whether the
  //   projection is backed by a server snapshot of the current application day.
  // Returns: None.
  void applyDoseProjection(
    List<MedicationSchedule> schedules, {
    required bool hasCurrentDayCache,
  }) {
    if (_disposed) return;
    if (!hasCurrentDayCache && _activeTodayScheduleLoadEpoch != null) {
      // A projection without today's snapshot has nothing to show. Let the server read that
      // is already in flight finish; its result is projected over pending doses anyway.
      return;
    }
    _todayScheduleEpoch++;
    _activeTodayScheduleLoadEpoch = null;
    _isTodayScheduleLoading = false;
    _hasSettledTodaySchedule = true;
    _todayMedicationScheduleList = schedules;
    if (hasCurrentDayCache) {
      _listedScheduleDay = doseScheduleDay(doseSync?.clock() ?? DateTime.now());
    }
    if (!hasCurrentDayCache) {
      // A projection without today's snapshot (first open of a new day) is
      // unknown, not empty: it must not pass as a successful read, or reminder
      // reconciliation would disable every enabled slot. Flag it for recovery.
      _lastTodayScheduleLoadSucceeded = false;
      _hasTodayScheduleLoadError = true;
    }
    _notifyViewModelListeners();
  }

  // Function Name: clear
  // Description: Invalidates pending reads and clears account state. Parameters: None. Returns: None.
  void clear() {
    _todayScheduleEpoch++;
    _activeTodayScheduleLoadEpoch = null;
    _isTodayScheduleLoading = false;
    _hasSettledTodaySchedule = false;
    _lastTodayScheduleLoadSucceeded = false;
    _hasTodayScheduleLoadError = false;
    _todayMedicationScheduleList = [];
    _listedScheduleDay = null;
  }

  // Function Name: dispose
  // Description: Stops presentation updates without closing borrowed controls. Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
    clear();
  }

  // Function Name: applyConfirmedTodaySchedules
  // Description: Applies a complete server-confirmed schedule, invalidating older in-flight reads.
  // Parameters: schedules: Confirmed current-day schedule list, such as a chat dose-record response.
  // Returns: None; publishes an unmodifiable list and successful settled state unless disposed.
  void applyConfirmedTodaySchedules(List<MedicationSchedule> schedules) {
    if (_disposed) return;
    _todayScheduleEpoch += 1;
    _activeTodayScheduleLoadEpoch = null;
    _todayMedicationScheduleList = List.unmodifiable(schedules);
    _isTodayScheduleLoading = false;
    _hasSettledTodaySchedule = true;
    _hasTodayScheduleLoadError = false;
    _lastTodayScheduleLoadSucceeded = true;
    _notifyViewModelListeners();
  }

  // 함수이름: fetchTodayMedicationSchedule
  // 함수역할: 오늘 기준으로 복용해야 하는 약 일정을 서버에서 가져온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> fetchTodayMedicationSchedule() async {
    await _loadTodayMedicationSchedule(
      checkSchedule.requestTodayMedicationSchedule,
    );
  }

  // 함수이름: fetchTodayMedicationInfo
  // 함수역할: 오늘 복약 요약 조회 Control을 공통 일정 로딩·오류 처리 흐름으로 실행한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> fetchTodayMedicationInfo() async {
    await _loadTodayMedicationSchedule(
      checkTodayMedicationInfo.requestTodayMedicationInfo,
    );
  }

  // Function Name: _loadTodayMedicationSchedule
  // Description: Loads today's schedules with request-generation and midnight guards, preserving online reads when local storage fails.
  // Parameters: loader: Patient-scoped schedule request.
  // Returns: Completion after state publication; applicable failures expose cached projection plus an error, and only the owning load clears its progress state.
  Future<void> _loadTodayMedicationSchedule(
    Future<List<MedicationSchedule>> Function() loader,
  ) async {
    if (_disposed) return;
    int? cacheRevision;
    var localStoreResponsive = true;
    if (doseSync != null) {
      try {
        await () async {
          cacheRevision = await doseSync!.cacheRevision();
          await doseSync!.reload();
          cacheRevision = await doseSync!.cacheRevision();
        }().timeout(_localStoreTimeout);
      } on TimeoutException {
        // 막힌 저장소에 일정 저장까지 기다리면 표시만 더 늦어진다.
        localStoreResponsive = false;
      } catch (_) {
        // Online reads remain available when local persistence is unavailable.
      }
    }
    if (_disposed) return;
    final loadEpoch = ++_todayScheduleEpoch;
    _activeTodayScheduleLoadEpoch = loadEpoch;
    _isTodayScheduleLoading = true;
    _hasTodayScheduleLoadError = false;
    _notifyViewModelListeners();

    final requestDay = doseScheduleDay(doseSync?.clock() ?? DateTime.now());
    try {
      final scheduleList = await loader();
      if (loadEpoch != _todayScheduleEpoch) {
        return;
      }
      if (requestDay != doseScheduleDay(doseSync?.clock() ?? DateTime.now())) {
        throw StateError(
          'The medication schedule has expired. Please refresh.',
        );
      }
      if (doseSync != null && localStoreResponsive) {
        try {
          await doseSync!
              .cacheSchedules(
                scheduleList,
                scheduleDate: requestDay,
                expectedRevision: cacheRevision,
              )
              .timeout(_localStoreTimeout);
        } catch (_) {
          // A local storage failure must not hide a successful online read.
          // Dose writes still fail closed when they cannot be persisted.
        }
      }
      if (loadEpoch != _todayScheduleEpoch) return;
      // Storage and widget publication can also cross the application midnight.
      if (requestDay != doseScheduleDay(doseSync?.clock() ?? DateTime.now())) {
        throw StateError(
          'The medication schedule has expired. Please refresh.',
        );
      }
      _todayMedicationScheduleList =
          doseSync?.project(scheduleList) ?? scheduleList;
      _listedScheduleDay = requestDay;
      _hasTodayScheduleLoadError = false;
      _lastTodayScheduleLoadSucceeded = true;
    } on StateError catch (error) {
      if (loadEpoch == _todayScheduleEpoch) {
        _todayMedicationScheduleList = doseSync?.schedules ?? const [];
        _lastTodayScheduleLoadSucceeded = false;
        _statusMessage = UserFacingErrorMessage.resolve(
          error,
          isEnglish: _isEnglishSetting,
        );
        _hasTodayScheduleLoadError = true;
      }
    } catch (_) {
      if (loadEpoch == _todayScheduleEpoch) {
        _todayMedicationScheduleList = doseSync?.schedules ?? const [];
        _lastTodayScheduleLoadSucceeded = false;
        _statusMessage = _isEnglishSetting
            ? 'Could not load today\'s medication schedule.'
            : '복약 일정을 불러오지 못했습니다.';
        _hasTodayScheduleLoadError = true;
      }
    } finally {
      // 이전 요청이 늦게 끝나도 최신 요청의 로딩 상태를 덮어쓰지 않는다.
      if (_activeTodayScheduleLoadEpoch == loadEpoch) {
        _activeTodayScheduleLoadEpoch = null;
        _isTodayScheduleLoading = false;
        _hasSettledTodaySchedule = true;
        _notifyViewModelListeners();
      }
    }
  }

  // 함수이름: isMedicationDoseCompleted
  // 함수역할: MedicationCompletion 기반 시간대별 복약 완료 상태를 반환한다. slot 상태가 없는 이전 응답은 기존 medicationStatus 값으로 처리한다.
  // 매개변수:
  // - slotKey (String): 확인할 시간대 키
  // - schedule (MedicationSchedule): 확인할 복약 일정
  // 반환값:
  // - 해당 시간대가 완료 처리되어 있으면 True
  bool isMedicationDoseCompleted(String slotKey, MedicationSchedule schedule) {
    return schedule.isSlotCompleted(slotKey);
  }

  // Function Name: slotKeysForSchedule
  // Description: Resolves the shared ordered dose-slot representation for a schedule.
  // Parameters: schedule: Medication with explicit slots, frequency and completion metadata.
  // Returns: The slot keys returned by resolveScheduleSlotKeys.
  List<String> slotKeysForSchedule(MedicationSchedule schedule) {
    return resolveScheduleSlotKeys(schedule);
  }

  // 함수이름: requestMedicationDoseStatusUpdate
  // 함수역할: 시간대별 복용 기록을 기기에 먼저 저장하고 서버 전송을 예약한다. 큐가 없는 실행 환경은 기존 API 경로를 사용한다.
  // 매개변수:
  // - slotKey (String): 상태를 변경할 시간대 키
  // - schedule (MedicationSchedule): 상태를 변경할 복약 일정
  // - medicationStatus (bool): 새 완료 상태
  // 반환값:
  // - 기기 저장(큐가 없으면 서버 갱신)에 성공하면 True. 서버 전송 완료 여부는 큐 상태로 구분한다.
  Future<bool> requestMedicationDoseStatusUpdate(
    String slotKey,
    MedicationSchedule schedule,
    bool medicationStatus,
  ) async {
    return requestMedicationStatusUpdate(
      schedule,
      medicationStatus,
      slotKey: slotKey,
    );
  }

  // Function Name: requestMedicationSlotStatusUpdate
  // Description: Durably queues the visible medicines in a slot, restoring cached data first for notification entry. Without a queue, uses the existing atomic server update.
  // Parameters:
  // - slotKey (String): Time slot whose medications should be updated together.
  // - medicationStatus (bool): Completion state applied to the full slot.
  // - expectedScheduleDate (String?): Optional original dose day checked by the server.
  // Returns:
  // - True after durable local acceptance (or a server update without a queue).
  Future<bool> requestMedicationSlotStatusUpdate(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    if (expectedScheduleDate == null && await _refuseTapOnEarlierDayList()) {
      return false;
    }
    if (doseSync != null) {
      if (!(await _ensureCurrentDayCache()).ready) return false;
      return _queueDoseStatus(
        _todayMedicationScheduleList
            .where((s) => s.slotKeys.contains(slotKey))
            .toList(),
        slotKey,
        medicationStatus,
        scheduleDate: expectedScheduleDate,
      );
    }
    try {
      final updatedSchedules = await checkSchedule.updateMedicationSlotStatus(
        slotKey,
        medicationStatus,
        expectedScheduleDate: expectedScheduleDate,
      );
      final updatedById = {
        for (final schedule in updatedSchedules)
          schedule.medicationID: schedule,
      };
      _todayScheduleEpoch += 1;
      _todayMedicationScheduleList = _todayMedicationScheduleList
          .map(
            /* Function Name: map callback
           * Description: Replaces a schedule with its refreshed ID match while retaining schedules absent from the update set.
           * Parameters:
           * - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
           * Returns:
           * - The refreshed schedule or the unchanged original.
           */
            (schedule) => updatedById[schedule.medicationID] ?? schedule,
          )
          .toList(growable: false);
      _notifyViewModelListeners();
      return true;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
      _notifyViewModelListeners();
      return false;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not update the entire medication slot.'
          : '시간대 전체 복약 상태를 업데이트하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
  }

  // Function Name: requestMedicationStatusUpdate
  // Description: Updates a medication's dose state through the durable queue when attached, otherwise through the server.
  // Parameters: medicationSchedule: Target course; medicationStatus: Desired completion; slotKey: Optional single-slot override.
  // Returns: Whether accepted; stale-day taps are refused and applicable failures update feedback. Queue acceptance does not mean server acknowledgment.
  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    if (medicationSchedule.medicationID.trim().isEmpty) {
      return false;
    }
    if (await _refuseTapOnEarlierDayList()) return false;
    if (doseSync != null) {
      var target = medicationSchedule;
      if ((await _ensureCurrentDayCache()).refetched) {
        // The tapped row was drawn from another day's list. Record against today's entry of
        // the same medicine, and nothing when it is no longer scheduled for that slot.
        final current = _todayMedicationScheduleList
            .where((s) => s.medicationID == medicationSchedule.medicationID)
            .firstOrNull;
        if (current == null ||
            (slotKey != null && !current.slotKeys.contains(slotKey))) {
          _statusMessage = _reloadBeforeRecordingMessage;
          _notifyViewModelListeners();
          return false;
        }
        target = current;
      }
      final slots = slotKey == null ? target.slotKeys : [slotKey];
      for (final slot in slots) {
        if (!await _queueDoseStatus([target], slot, medicationStatus)) {
          return false;
        }
      }
      return true;
    }

    try {
      final updatedSchedule = await checkSchedule.updateMedicationStatus(
        medicationSchedule.medicationID,
        medicationStatus,
        slotKey: slotKey,
      );
      _todayScheduleEpoch += 1;
      _todayMedicationScheduleList = _todayMedicationScheduleList
          .map(
            // 함수이름: map 콜백
            // 함수역할: 수정된 일정과 약 ID가 같은 항목만 새 일정으로 교체한다.
            // 매개변수:
            // - item (MedicationSchedule): 현재 변환·검사 중인 응답 또는 목록 항목
            // 반환값:
            // - 갱신된 일정 또는 기존 항목.
            (item) => item.medicationID == updatedSchedule.medicationID
                ? updatedSchedule
                : item,
          )
          .toList(growable: false);
      _notifyViewModelListeners();
      return true;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
      _notifyViewModelListeners();
      return false;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not update the medication status.'
          : '복약 상태를 업데이트하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
  }

  // Function Name: _ensureCurrentDayCache
  // Description: Makes sure the queue holds today's schedule before a dose is recorded. A
  //   notification can arrive before the home screen restores its cache; it refetches once
  //   instead of rejecting the action. A tap on an earlier day's list never gets here
  //   (`_refuseTapOnEarlierDayList`).
  // Parameters: None.
  // Returns: ready - whether today's schedule is cached; refetched - whether the visible list
  //   was replaced by a new server read. A storage or network failure gives ready == false.
  Future<({bool ready, bool refetched})> _ensureCurrentDayCache() async {
    var refetched = false;
    try {
      await doseSync!.initialize();
      if (!doseSync!.hasCache) {
        refetched = true;
        await fetchTodayMedicationSchedule();
      }
      return (ready: doseSync!.hasCache, refetched: refetched);
    } catch (_) {
      return (ready: false, refetched: refetched);
    }
  }

  // Function Name: _refuseTapOnEarlierDayList
  // Description: A tap on a list drawn for an earlier application day (the app left open
  //   across midnight) records nothing. Today's list is read instead and the user is asked to
  //   check it and tap again, so yesterday's row is never recorded as today's dose and
  //   tonight's reminder of that slot stays. Reminder actions carry their own day and skip this.
  // Parameters: None.
  // Returns: True when the tap was refused.
  Future<bool> _refuseTapOnEarlierDayList() async {
    final listed = _listedScheduleDay;
    final today = doseScheduleDay(doseSync?.clock() ?? DateTime.now());
    if (listed == null || listed == today) return false;
    await fetchTodayMedicationSchedule();
    if (_lastTodayScheduleLoadSucceeded) {
      _statusMessage = _isEnglishSetting
          ? 'The date has changed and today\'s schedule was loaded. Check it and tap again.'
          : '날짜가 바뀌어 오늘 일정을 다시 불러왔습니다. 확인한 뒤 다시 눌러주세요.';
    }
    _notifyViewModelListeners();
    return true;
  }

  // Function Name: _reloadBeforeRecordingMessage
  // Description: Feedback for a dose that cannot be matched to today's schedule.
  // Parameters: None. Returns: Localized guidance.
  String get _reloadBeforeRecordingMessage => _isEnglishSetting
      ? 'Please reload today\'s schedule before recording a dose.'
      : '오늘의 복약 일정을 다시 불러온 뒤 기록해주세요.';

  // Function Name: _queueDoseStatus
  // Description: Persists one slot update through dose synchronization and reports local acceptance separately from server sync.
  // Parameters: schedules: Target medications with parseable IDs; slotKey: Dose slot; completed: Desired state; scheduleDate: Optional date guard.
  // Returns: True only after local acceptance; invalid IDs, refused writes and exceptions return false, with write failures reported to listeners.
  Future<bool> _queueDoseStatus(
    List<MedicationSchedule> schedules,
    String slotKey,
    bool completed, {
    String? scheduleDate,
  }) async {
    try {
      final ids = schedules
          .map((s) => int.tryParse(s.medicationID))
          .whereType<int>()
          .toList();
      if (ids.isEmpty || ids.length != schedules.length) return false;
      final saved = await doseSync!.record(
        medicationIds: ids,
        slotKey: slotKey,
        completed: completed,
        scheduleDate: scheduleDate,
        medicationNames: schedules.map((s) => s.medicationName).toList(),
      );
      _statusMessage = saved
          ? (_isEnglishSetting
                ? 'Saved on this device. Waiting to sync.'
                : '기기에 기록했습니다. 서버 전송 대기 중입니다.')
          : _reloadBeforeRecordingMessage;
      if (!saved) _notifyViewModelListeners();
      return saved;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not save the dose on this device.'
          : '기기에 복용 기록을 저장하지 못했습니다. 다시 시도해주세요.';
      _notifyViewModelListeners();
      return false;
    }
  }
}
