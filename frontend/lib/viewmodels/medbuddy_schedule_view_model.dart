part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_schedule_view_model.dart
// 역할: 오늘 복약 일정 조회와 시간대별 복용 완료 상태를 관리한다.

// Class Name: MedBuddyScheduleViewModel
// Role: Extends today's schedule loading and individual or whole-slot completion updates.
// Responsibilities:
// - Reject stale load generations, merge server-updated schedules, and publish loading and failure state to schedule listeners.
extension MedBuddyScheduleViewModel on MedBuddyViewModel {
  // 함수역할: 채팅의 복용 기록 응답을 홈·일정에 즉시 반영하고 이전 조회를 무효화한다.
  // 매개변수: schedules: 서버가 확인한 오늘 전체 일정. 반환값: 없음.
  void applyConfirmedTodaySchedules(List<MedicationSchedule> schedules) {
    _todayScheduleEpoch += 1;
    _activeTodayScheduleLoadEpoch = null;
    _todayMedicationScheduleList = List.unmodifiable(schedules);
    _isTodayScheduleLoading = false;
    _hasTodayScheduleLoadError = false;
    _lastTodayScheduleLoadSucceeded = true;
    _notifyViewModelListeners(MedBuddyFeature.schedule);
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

  // 함수이름: _loadTodayMedicationSchedule
  // 함수역할: 조회 세대를 기록해 최신 응답만 오늘 일정에 반영하고 실패 시 목록·성공 플래그·오류 안내를 갱신하며 해당 로딩 상태만 종료한다.
  // 매개변수:
  // - loader (Future<List<MedicationSchedule>> Function()): 대상 환자의 복약 일정 조회 경계
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _loadTodayMedicationSchedule(
    Future<List<MedicationSchedule>> Function() loader,
  ) async {
    int? cacheRevision;
    if (doseSync != null) {
      try {
        cacheRevision = await doseSync!.cacheRevision();
      } catch (_) {
        // Online reads remain available when local persistence is unavailable.
      }
    }
    final loadEpoch = ++_todayScheduleEpoch;
    _activeTodayScheduleLoadEpoch = loadEpoch;
    _isTodayScheduleLoading = true;
    _hasTodayScheduleLoadError = false;
    _notifyViewModelListeners(MedBuddyFeature.schedule);

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
      if (doseSync != null) {
        try {
          await doseSync!.cacheSchedules(
            scheduleList,
            scheduleDate: requestDay,
            expectedRevision: cacheRevision,
          );
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
        _notifyViewModelListeners(MedBuddyFeature.schedule);
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

  // 함수이름: slotKeysForSchedule
  // 함수역할: 명시 시간대·하루 횟수·완료 상태에서 정한 공통 복약 시간대 목록을 화면에 제공한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // 반환값:
  // - List<String>: 명시 시간대·하루 횟수·완료 상태에서 정한 공통 복약 시간대 목록을 화면에 제공한다.
  List<String> slotKeysForSchedule(MedicationSchedule schedule) {
    return _slotKeysForSchedule(schedule);
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
    if (doseSync != null) {
      try {
        // A notification can arrive before the home screen restores its cache.
        await doseSync!.initialize();
        if (!doseSync!.hasCache) await fetchTodayMedicationSchedule();
        if (!doseSync!.hasCache) return false;
      } catch (_) {
        return false;
      }
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
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return true;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return false;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not update the entire medication slot.'
          : '시간대 전체 복약 상태를 업데이트하지 못했습니다.';
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return false;
    }
  }

  // 함수이름: requestMedicationStatusUpdate
  // 함수역할: 저장 ID가 있는 일정의 완료 상태를 서버에 반영하고 해당 약만 교체하며 이전 조회 응답을 무효화하고 실패는 안내와 false로 전달한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // - medicationStatus (bool): 적용하거나 보존할 복용 완료 여부
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Future<bool>: 저장 ID가 있는 일정의 완료 상태를 서버에 반영하고 해당 약만 교체하며 이전 조회 응답을 무효화하고 실패는 안내와 false로 전달한다.
  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    if (medicationSchedule.medicationID.trim().isEmpty) {
      return false;
    }
    if (doseSync != null) {
      final slots = slotKey == null ? medicationSchedule.slotKeys : [slotKey];
      for (final slot in slots) {
        if (!await _queueDoseStatus(
          [medicationSchedule],
          slot,
          medicationStatus,
        )) {
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
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return true;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return false;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not update the medication status.'
          : '복약 상태를 업데이트하지 못했습니다.';
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return false;
    }
  }

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
          : (_isEnglishSetting
                ? 'Please reload today\'s schedule before recording a dose.'
                : '오늘의 복약 일정을 다시 불러온 뒤 기록해주세요.');
      if (!saved) _notifyViewModelListeners(MedBuddyFeature.schedule);
      return saved;
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not save the dose on this device.'
          : '기기에 복용 기록을 저장하지 못했습니다. 다시 시도해주세요.';
      _notifyViewModelListeners(MedBuddyFeature.schedule);
      return false;
    }
  }
}
