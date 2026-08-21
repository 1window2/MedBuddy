part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_saved_medication_view_model.dart
// 역할: 저장된 복약정보의 저장, 조회, 단건·일괄 삭제 상태를 관리한다.

// 확장명: MedBuddySavedMedicationViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddySavedMedicationViewModel on MedBuddyViewModel {
  // 함수명: saveMedicationInfo
  // 함수역할:
  // - 약 상세 정보와 선택적 복약 스케줄을 저장 API로 전달하고 저장 목록을 갱신한다.
  // 매개변수:
  // - medicationInfo: 저장할 약 상세 정보
  // - medicationSchedule: OCR에서 추출된 선택적 복약 일정
  // 반환값:
  // - 저장 성공 여부
  Future<MedicationSaveResult> saveMedicationInfo(
    MedicationDetail medicationInfo, {
    MedicationSchedule? medicationSchedule,
    bool refreshAfterSave = true,
  }) async {
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);

    final result = await checkSavedMedication.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
    );
    if (result.status == MedicationSaveStatus.failed) {
      _statusMessage = result.message;
      _notifyViewModelListeners(MedBuddyFeature.savedMedication);
      return result;
    }

    _statusMessage = result.status == MedicationSaveStatus.duplicate
        ? '이미 추가된 약입니다.'
        : '복약 정보가 성공적으로 저장되었습니다.';
    if (refreshAfterSave) {
      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    return result;
  }

  // 함수명: fetchSavedMedicationInfo
  // 함수역할:
  // - 저장된 복약 정보 목록을 서버에서 가져와 화면 상태에 반영한다.
  // 반환값:
  // - 없음
  Future<void> fetchSavedMedicationInfo() async {
    _isSavedMedicationLoading = true;
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);

    try {
      final savedMedicationInfoList = await checkSavedMedication
          .requestSavedMedicationInfo();
      _savedMedicationInfoList = savedMedicationInfoList;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
    } catch (_) {
      _statusMessage = '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      _isSavedMedicationLoading = false;
      _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final result = await requestDeleteSavedMedications([savedMedicationId]);
    return result.allSucceeded;
  }

  Future<SavedMedicationBatchDeleteResult> requestDeleteSavedMedications(
    Iterable<int> savedMedicationIds,
  ) async {
    final uniqueIds = savedMedicationIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) {
      return const SavedMedicationBatchDeleteResult(
        successCount: 0,
        failureCount: 0,
      );
    }

    final deleteResults = await Future.wait(
      uniqueIds.map((savedMedicationId) async {
        try {
          return await checkSavedMedication.requestDelete(savedMedicationId);
        } catch (_) {
          return false;
        }
      }),
    );
    final deletedIds = <int>{};
    for (var index = 0; index < uniqueIds.length; index += 1) {
      if (deleteResults[index]) {
        deletedIds.add(uniqueIds[index]);
      }
    }

    if (deletedIds.isNotEmpty) {
      _savedMedicationInfoList = _savedMedicationInfoList
          .where((item) => !deletedIds.contains(item.id))
          .toList(growable: false);
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }

    return SavedMedicationBatchDeleteResult(
      successCount: deletedIds.length,
      failureCount: uniqueIds.length - deletedIds.length,
    );
  }
}
