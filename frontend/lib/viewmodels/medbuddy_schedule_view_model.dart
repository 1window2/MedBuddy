part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_schedule_view_model.dart
// 역할: 오늘 복약 일정 조회와 시간대별 복용 완료 상태를 관리한다.

// 확장명: MedBuddyScheduleViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddyScheduleViewModel on MedBuddyViewModel {
  // 함수명: fetchTodayMedicationSchedule
  // 함수역할:
  // - 오늘 기준으로 복용해야 하는 약 일정을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchTodayMedicationSchedule() async {
    await _loadTodayMedicationSchedule(
      checkSchedule.requestTodayMedicationSchedule,
    );
  }

  Future<void> fetchTodayMedicationInfo() async {
    await _loadTodayMedicationSchedule(
      checkTodayMedicationInfo.requestTodayMedicationInfo,
    );
  }

  Future<void> _loadTodayMedicationSchedule(
    Future<List<MedicationSchedule>> Function() loader,
  ) async {
    final loadEpoch = ++_todayScheduleEpoch;
    _todayScheduleLoadCount += 1;
    _isTodayScheduleLoading = true;
    _hasTodayScheduleLoadError = false;
    _notifyViewModelListeners();

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
      _todayScheduleLoadCount -= 1;
      _isTodayScheduleLoading = _todayScheduleLoadCount > 0;
      _notifyViewModelListeners();
    }
  }

  // 함수명: isMedicationDoseCompleted
  // 함수역할:
  // - MedicationCompletion 기반 시간대별 복약 완료 상태를 반환한다.
  // - slot 상태가 없는 이전 응답은 기존 medicationStatus 값으로 처리한다.
  // 매개변수:
  // - slotKey: 확인할 시간대 키
  // - schedule: 확인할 복약 일정
  // 반환값:
  // - 해당 시간대가 완료 처리되어 있으면 True
  bool isMedicationDoseCompleted(String slotKey, MedicationSchedule schedule) {
    return schedule.isSlotCompleted(slotKey);
  }

  List<String> slotKeysForSchedule(MedicationSchedule schedule) {
    return _slotKeysForSchedule(schedule);
  }

  // 함수명: requestMedicationDoseStatusUpdate
  // 함수역할:
  // - 복약 완료 상태를 백엔드 일정 상태 변경 API로 저장한다.
  // - slotKey를 함께 전달해 하루 여러 번 복용하는 약의 완료 상태를 분리한다.
  // 매개변수:
  // - slotKey: 상태를 변경할 시간대 키
  // - schedule: 상태를 변경할 복약 일정
  // - medicationStatus: 새 완료 상태
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
      _statusMessage = '복약 상태를 업데이트하지 못했습니다.';
      _notifyViewModelListeners();
      return false;
    }
  }
}
