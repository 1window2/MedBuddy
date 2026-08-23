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
    String localImagePath = '',
    bool refreshAfterSave = true,
  }) async {
    _statusMessage = _isEnglishSetting
        ? 'Saving ${medicationInfo.itemName}...'
        : '${medicationInfo.itemName} 저장 중...';
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);

    final result = await checkSavedMedication.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
    );
    if (result.status == MedicationSaveStatus.failed) {
      _statusMessage = _isEnglishSetting
          ? 'Could not save medication information.'
          : result.message;
      _notifyViewModelListeners(MedBuddyFeature.savedMedication);
      return result;
    }

    final savedMedicationId = result.savedMedicationId;
    if (localImagePath.trim().isNotEmpty && savedMedicationId != null) {
      try {
        await manualMedicationImageStore.saveImage(
          patientHash: patientHash,
          medicationId: savedMedicationId,
          sourcePath: localImagePath,
        );
      } catch (_) {
        // 서버 저장은 완료됐으므로 로컬 사진 실패가 복약정보 저장까지 취소하지 않게 한다.
      }
    }

    _statusMessage = result.status == MedicationSaveStatus.duplicate
        ? (_isEnglishSetting
              ? 'This medication is already saved.'
              : '이미 추가된 약입니다.')
        : (_isEnglishSetting
              ? 'Medication information saved.'
              : '복약 정보가 성공적으로 저장되었습니다.');
    if (refreshAfterSave) {
      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    return result;
  }

  // 함수명: saveManualMedication
  // 함수역할:
  // - 사용자가 직접 입력한 약을 공공데이터로 보완한 뒤 기존 저장 흐름으로 전달한다.
  // - 공공데이터에서 찾지 못해도 사용자가 입력한 일정은 그대로 저장한다.
  Future<MedicationSaveResult> saveManualMedication(
    ManualMedicationEntry entry,
  ) async {
    final schedule = entry.toMedicationSchedule();
    MedicationDetail? medicationDetail;
    try {
      medicationDetail = await checkMedicationDetail.requestMedicationDetail(
        schedule,
      );
    } catch (_) {
      // 직접 등록은 외부 약품 조회가 잠시 실패해도 사용할 수 있어야 한다.
    }
    medicationDetail ??= MedicationDetail(
      itemName: entry.medicationName.trim(),
      efficacy: '',
      usageMethod: '',
      warning: '',
    );

    return saveMedicationInfo(
      medicationDetail,
      medicationSchedule: schedule,
      localImagePath: entry.localImagePath,
    );
  }

  // 함수명: saveIdentifiedPill
  // 함수역할:
  // - 사용자가 고른 낱알약 후보와 확인한 복약 일정을 공공데이터 상세 정보로 보완한다.
  // - 상세 조회가 실패해도 후보 정보와 사용자 입력 일정으로 기존 저장 흐름을 계속 진행한다.
  Future<MedicationSaveResult> saveIdentifiedPill(
    PillIdentificationCandidate candidate,
    MedicationSchedule medicationSchedule, {
    bool refreshAfterSave = true,
  }) async {
    MedicationDetail? medicationDetail;
    try {
      medicationDetail = await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
    } catch (_) {
      // 낱알약 후보는 이미 사용자가 확인했으므로 외부 상세 조회 실패가 저장을 막지 않게 한다.
    }

    final candidateImageUrl = safeMedicationImageUrl(candidate.imageUrl);
    final resolvedMedicationDetail =
        (medicationDetail ??
                MedicationDetail(
                  itemName: medicationSchedule.medicationName.trim(),
                  efficacy: '',
                  usageMethod: '',
                  warning: '',
                ))
            .copyWith(
              itemSeq: candidate.itemSeq,
              itemName: medicationSchedule.medicationName.trim(),
              prescriptionDate: medicationSchedule.prescriptionDate,
              dosagePerTime: medicationSchedule.dosage,
              dailyFrequency: medicationSchedule.intakeTime,
              totalDays: medicationSchedule.medicationTimeLabel,
              imageUrl: medicationDetail?.imageUrl.trim().isNotEmpty == true
                  ? medicationDetail!.imageUrl
                  : candidateImageUrl,
            );

    return saveMedicationInfo(
      resolvedMedicationDetail,
      medicationSchedule: medicationSchedule.copyWith(
        imageUrl: resolvedMedicationDetail.imageUrl,
      ),
      refreshAfterSave: refreshAfterSave,
    );
  }

  // 함수명: saveIdentifiedPills
  // 함수역할:
  // - 여러 낱알약 저장 요청을 순서대로 처리하고 저장 목록과 오늘 일정을 마지막에 한 번만 갱신한다.
  // - 일부 약의 저장이 실패해도 나머지 요청을 계속 처리해 각 결과를 원래 순서대로 반환한다.
  Future<List<MedicationSaveResult>> saveIdentifiedPills(
    List<IdentifiedPillSaveRequest> requests,
  ) async {
    if (requests.isEmpty) {
      return const [];
    }

    final results = <MedicationSaveResult>[];
    for (final request in requests) {
      try {
        results.add(
          await saveIdentifiedPill(
            request.candidate,
            request.medicationSchedule,
            refreshAfterSave: false,
          ),
        );
      } catch (_) {
        results.add(
          MedicationSaveResult(
            status: MedicationSaveStatus.failed,
            message: _isEnglishSetting
                ? 'Could not save medication information.'
                : '복약 정보를 저장하지 못했습니다.',
          ),
        );
      }
    }

    if (results.any((result) => result.status != MedicationSaveStatus.failed)) {
      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    return List<MedicationSaveResult>.unmodifiable(results);
  }

  // 함수명: fetchSavedMedicationInfo
  // 함수역할:
  // - 저장된 복약 정보 목록을 서버에서 가져와 화면 상태에 반영한다.
  // 반환값:
  // - 없음
  Future<void> fetchSavedMedicationInfo() async {
    _isSavedMedicationLoading = true;
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);

    List<MedicationDetail>? fetchedMedicationList;
    try {
      fetchedMedicationList = await checkSavedMedication
          .requestSavedMedicationInfo();
      // 서버 목록을 먼저 표시하고 로컬 사진 파일 확인은 화면을 막지 않도록 분리한다.
      _savedMedicationInfoList = fetchedMedicationList;
    } on StateError catch (error) {
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
    } catch (_) {
      _statusMessage = _isEnglishSetting
          ? 'Could not load saved medication information.'
          : '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      _isSavedMedicationLoading = false;
      _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    }

    if (fetchedMedicationList != null) {
      unawaited(_refreshLocalMedicationImages(fetchedMedicationList));
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
        final deletedId = uniqueIds[index];
        deletedIds.add(deletedId);
        // 서버 삭제 결과를 먼저 반영하고 로컬 사진 파일은 화면을 막지 않게 정리한다.
        unawaited(_deleteLocalMedicationImage(deletedId));
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

  Future<List<MedicationDetail>> _attachLocalMedicationImages(
    List<MedicationDetail> medicationList,
  ) async {
    try {
      final activeIds = medicationList
          .map((item) => item.id)
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
      final itemsWithImages = await Future.wait(
        medicationList.map((medication) async {
          final medicationId = medication.id;
          if (medicationId == null || medicationId <= 0) {
            return medication;
          }
          final localImagePath = await manualMedicationImageStore.findImagePath(
            patientHash: patientHash,
            medicationId: medicationId,
          );
          return medication.copyWith(localImagePath: localImagePath);
        }),
      );
      await manualMedicationImageStore.removeOrphanImages(
        patientHash: patientHash,
        activeMedicationIds: activeIds,
      );
      return itemsWithImages;
    } catch (_) {
      // 플러그인을 사용할 수 없는 테스트 환경에서는 서버 목록만 그대로 사용한다.
      return medicationList;
    }
  }

  Future<void> _refreshLocalMedicationImages(
    List<MedicationDetail> fetchedMedicationList,
  ) async {
    final itemsWithImages = await _attachLocalMedicationImages(
      fetchedMedicationList,
    );
    if (itemsWithImages.every((item) => item.localImagePath.isEmpty)) {
      return;
    }

    final localImagePathById = <int, String>{
      for (final item in itemsWithImages)
        if (item.id != null && item.localImagePath.isNotEmpty)
          item.id!: item.localImagePath,
    };
    _savedMedicationInfoList = _savedMedicationInfoList
        .map((item) {
          final medicationId = item.id;
          if (medicationId == null) {
            return item;
          }
          final localImagePath = localImagePathById[medicationId];
          return localImagePath == null
              ? item
              : item.copyWith(localImagePath: localImagePath);
        })
        .toList(growable: false);
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
  }

  Future<void> _deleteLocalMedicationImage(int medicationId) async {
    try {
      await manualMedicationImageStore.deleteImage(
        patientHash: patientHash,
        medicationId: medicationId,
      );
    } catch (_) {
      // 남은 로컬 파일은 다음 저장 목록 조회 시 고아 파일 정리에서 다시 제거한다.
    }
  }
}
