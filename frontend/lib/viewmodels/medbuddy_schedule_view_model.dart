part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_schedule_view_model.dart
// 역할: 오늘 복약 일정 조회와 시간대별 복용 완료 상태를 관리한다.

// Class Name: MedBuddyScheduleViewModel
// Role: Extends today's schedule loading and individual or whole-slot completion updates.
// Responsibilities:
// - Reject stale load generations, merge server-updated schedules, and publish loading and failure state to schedule listeners.
extension MedBuddyScheduleViewModel on MedBuddyViewModel {
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
    final loadEpoch = ++_todayScheduleEpoch;
    _activeTodayScheduleLoadEpoch = loadEpoch;
    _isTodayScheduleLoading = true;
    _hasTodayScheduleLoadError = false;
    _notifyViewModelListeners(MedBuddyFeature.schedule);

    try {
      final scheduleList = await loader();
      if (loadEpoch != _todayScheduleEpoch) {
        return;
      }
      _todayMedicationScheduleList = scheduleList;
      _hasTodayScheduleLoadError = false;
      _lastTodayScheduleLoadSucceeded = true;
    } on StateError catch (error) {
      if (loadEpoch == _todayScheduleEpoch) {
        _todayMedicationScheduleList = const [];
        _lastTodayScheduleLoadSucceeded = false;
        _statusMessage = UserFacingErrorMessage.resolve(
          error,
          isEnglish: _isEnglishSetting,
        );
        _hasTodayScheduleLoadError = true;
      }
    } catch (_) {
      if (loadEpoch == _todayScheduleEpoch) {
        _todayMedicationScheduleList = const [];
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
  // 함수역할: 복약 완료 상태를 백엔드 일정 상태 변경 API로 저장한다. slotKey를 함께 전달해 하루 여러 번 복용하는 약의 완료 상태를 분리한다.
  // 매개변수:
  // - slotKey (String): 상태를 변경할 시간대 키
  // - schedule (MedicationSchedule): 상태를 변경할 복약 일정
  // - medicationStatus (bool): 새 완료 상태
  // 반환값:
  // - 백엔드 갱신에 성공하면 True
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
  // Description: Checks or unchecks every active medication in one time slot through one atomic backend request. Replaces only schedules returned by the scoped update while preserving the rest of today's locally loaded schedule.
  // Parameters:
  // - slotKey (String): Time slot whose medications should be updated together.
  // - medicationStatus (bool): Completion state applied to the full slot.
  // Returns:
  // - True when the backend update and local state replacement succeed.
  Future<bool> requestMedicationSlotStatusUpdate(
    String slotKey,
    bool medicationStatus,
  ) async {
    try {
      final updatedSchedules = await checkSchedule.updateMedicationSlotStatus(
        slotKey,
        medicationStatus,
      );
      final updatedById = {
        for (final schedule in updatedSchedules)
          schedule.medicationID: schedule,
      };
      _todayScheduleEpoch += 1;
      _todayMedicationScheduleList = _todayMedicationScheduleList
          .map(/* Function Name: map callback
           * Description: Replaces a schedule with its refreshed ID match while retaining schedules absent from the update set.
           * Parameters:
           * - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
           * Returns:
           * - The refreshed schedule or the unchanged original.
           */(schedule) => updatedById[schedule.medicationID] ?? schedule)
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
}
