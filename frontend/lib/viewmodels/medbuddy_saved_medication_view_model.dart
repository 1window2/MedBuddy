part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_saved_medication_view_model.dart
// 역할: 저장된 복약정보의 저장, 조회, 단건·일괄 삭제 상태를 관리한다.

// 클래스명: MedBuddySavedMedicationViewModel
// 역할: 저장 약 등록·조회·삭제와 기기 사진 연결 상태를 확장한다.
// 주요 책임:
// - 수동 입력·알약 후보를 기존 저장 흐름에 연결하고 부분 실패를 보존하며 성공 후 일정과 알림을 갱신한다.
extension MedBuddySavedMedicationViewModel on MedBuddyViewModel {
  // 함수이름: saveMedicationInfo
  // 함수역할: 약 상세 정보와 선택적 복약 스케줄을 저장 API로 전달하고 저장 목록을 갱신한다.
  // 매개변수:
  // - medicationInfo (MedicationDetail): 저장할 약 상세 정보
  // - medicationSchedule (MedicationSchedule?): OCR에서 추출된 선택적 복약 일정
  // - localImagePath (String): 서버에 전송하지 않는 기기 전용 약 사진 경로
  // - refreshAfterSave (bool): 저장 후 목록·일정·알림을 즉시 갱신할지 여부
  // 반환값:
  // - 저장 성공·중복·실패 상태와 안내 메시지 및 저장 ID를 담은 MedicationSaveResult의 Future.
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

  // 함수이름: saveManualMedication
  // 함수역할: 사용자가 직접 입력한 약을 공공데이터로 보완한 뒤 기존 저장 흐름으로 전달한다. 공공데이터에서 찾지 못해도 사용자가 입력한 일정은 그대로 저장한다.
  // 매개변수:
  // - entry (ManualMedicationEntry): 사용자가 직접 입력한 약과 일정 및 선택 사진
  // 반환값:
  // - Future<MedicationSaveResult>: 사용자가 직접 입력한 약을 공공데이터로 보완한 뒤 기존 저장 흐름으로 전달한다. 공공데이터에서 찾지 못해도 사용자가 입력한 일정은 그대로 저장한다.
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

  // 함수이름: saveIdentifiedPill
  // 함수역할: 사용자가 고른 낱알약 후보와 확인한 복약 일정을 공공데이터 상세 정보로 보완한다. 상세 조회가 실패해도 후보 정보와 사용자 입력 일정으로 기존 저장 흐름을 계속 진행한다.
  // 매개변수:
  // - candidate (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
  // - medicationSchedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // - refreshAfterSave (bool): 저장 후 목록·일정·알림을 즉시 갱신할지 여부
  // 반환값:
  // - Future<MedicationSaveResult>: 사용자가 고른 낱알약 후보와 확인한 복약 일정을 공공데이터 상세 정보로 보완한다. 상세 조회가 실패해도 후보 정보와 사용자 입력 일정으로 기존 저장 흐름을 계속 진행한다.
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

  // 함수이름: saveIdentifiedPills
  // 함수역할: 여러 낱알약 저장 요청을 순서대로 처리하고 저장 목록과 오늘 일정을 마지막에 한 번만 갱신한다. 일부 약의 저장이 실패해도 나머지 요청을 계속 처리해 각 결과를 원래 순서대로 반환한다.
  // 매개변수:
  // - requests (List<IdentifiedPillSaveRequest>): 입력 순서를 보존할 알약 저장 요청 목록
  // 반환값:
  // - Future<List<MedicationSaveResult>>: 여러 낱알약 저장 요청을 순서대로 처리하고 저장 목록과 오늘 일정을 마지막에 한 번만 갱신한다. 일부 약의 저장이 실패해도 나머지 요청을 계속 처리해 각 결과를 원래 순서대로 반환한다.
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

    if (results.any(/* 함수이름: any 콜백
     * 함수역할: 일괄 저장 결과 중 실패가 아닌 결과가 있는지 확인한다.
     * 매개변수:
     * - result (MedicationSaveResult): 해당 입력 알약의 성공 식별 결과
     * 반환값:
     * - 해당 저장 결과가 실패 상태가 아니면 true.
     */(result) => result.status != MedicationSaveStatus.failed)) {
      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }
    _notifyViewModelListeners(MedBuddyFeature.savedMedication);
    return List<MedicationSaveResult>.unmodifiable(results);
  }

  // 함수이름: fetchSavedMedicationInfo
  // 함수역할: 저장된 복약 정보 목록을 서버에서 가져와 화면 상태에 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: requestDeleteSavedMedication
  // 함수역할: 단일 저장 ID를 일괄 삭제 흐름에 전달하고 해당 항목의 전체 성공 여부를 제공한다.
  // 매개변수:
  // - savedMedicationId (int): 대상 저장 복약정보의 식별자
  // 반환값:
  // - Future<bool>: 단일 저장 ID를 일괄 삭제 흐름에 전달하고 해당 항목의 전체 성공 여부를 제공한다.
  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final result = await requestDeleteSavedMedications([savedMedicationId]);
    return result.allSucceeded;
  }

  // 함수이름: requestDeleteSavedMedications
  // 함수역할: 중복 ID를 제거해 삭제를 병렬 요청하고 성공 항목만 목록·기기 사진에서 제거한 뒤 일정과 알림을 갱신하며 성공·실패 수를 반환한다.
  // 매개변수:
  // - savedMedicationIds (Iterable<int>): 처리할 저장 복약정보 식별자 목록
  // 반환값:
  // - Future<SavedMedicationBatchDeleteResult>: 중복 ID를 제거해 삭제를 병렬 요청하고 성공 항목만 목록·기기 사진에서 제거한 뒤 일정과 알림을 갱신하며 성공·실패 수를 반환한다.
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
      uniqueIds.map(/* 함수이름: map 콜백
       * 함수역할: 저장된 약을 개별 삭제하고 예외를 해당 항목의 삭제 실패로 격리한다.
       * 매개변수:
       * - savedMedicationId (int): 대상 저장 복약정보의 식별자
       * 반환값:
       * - 해당 약 삭제 성공 여부를 완료하는 Future.
       */(savedMedicationId) async {
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
          .where(/* 함수이름: where 콜백
           * 함수역할: 삭제에 성공한 약 ID를 현재 저장 목록에서 제외한다.
           * 매개변수:
           * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
           * 반환값:
           * - 삭제된 ID 집합에 속하지 않으면 true.
           */(item) => !deletedIds.contains(item.id))
          .toList(growable: false);
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }

    return SavedMedicationBatchDeleteResult(
      successCount: deletedIds.length,
      failureCount: uniqueIds.length - deletedIds.length,
    );
  }

  // 함수이름: _attachLocalMedicationImages
  // 함수역할: 저장 약 ID별 기기 사진을 조회해 상세 모델에 붙이고 고아 사진을 정리하며 사진 처리 실패 시 원래 목록을 유지한다.
  // 매개변수:
  // - medicationList (List<MedicationDetail>): 사진 경로를 연결할 저장 약 목록
  // 반환값:
  // - Future<List<MedicationDetail>>: 저장 약 ID별 기기 사진을 조회해 상세 모델에 붙이고 고아 사진을 정리하며 사진 처리 실패 시 원래 목록을 유지한다.
  Future<List<MedicationDetail>> _attachLocalMedicationImages(
    List<MedicationDetail> medicationList,
  ) async {
    try {
      final activeIds = medicationList
          .map(/* 함수이름: map 콜백
           * 함수역할: 로컬 이미지 정리에 사용할 저장 약 ID를 추출한다.
           * 매개변수:
           * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
           * 반환값:
           * - 저장 약 ID 또는 null.
           */(item) => item.id)
          .whereType<int>()
          .where(/* 함수이름: where 콜백
           * 함수역할: 로컬 이미지 관리에 사용할 수 있는 양의 저장 약 ID만 남긴다.
           * 매개변수:
           * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
           * 반환값:
           * - ID가 양수이면 true.
           */(id) => id > 0)
          .toSet();
      final itemsWithImages = await Future.wait(
        medicationList.map(/* 함수이름: map 콜백
         * 함수역할: 유효한 저장 약 ID의 로컬 이미지 경로를 찾아 약 상세 정보에 병합한다.
         * 매개변수:
         * - medication (MedicationDetail): 로컬 이미지를 복원할 저장 약 정보
         * 반환값:
         * - 로컬 이미지 경로를 반영한 약 상세 정보의 Future.
         */(medication) async {
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

  // 함수이름: _refreshLocalMedicationImages
  // 함수역할: 비동기로 찾은 사진 경로를 현재 목록의 같은 저장 ID에만 반영해 늦은 사진 조회가 삭제된 항목을 복원하지 않게 한다.
  // 매개변수:
  // - fetchedMedicationList (List<MedicationDetail>): 사진 경로를 연결할 저장 약 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _refreshLocalMedicationImages(
    List<MedicationDetail> fetchedMedicationList,
  ) async {
    final itemsWithImages = await _attachLocalMedicationImages(
      fetchedMedicationList,
    );
    if (itemsWithImages.every(/* 함수이름: every 콜백
     * 함수역할: 저장된 약 전체에 로컬 이미지 경로가 없는지 확인한다.
     * 매개변수:
     * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
     * 반환값:
     * - 해당 약의 로컬 이미지 경로가 비어 있으면 true.
     */(item) => item.localImagePath.isEmpty)) {
      return;
    }

    final localImagePathById = <int, String>{
      for (final item in itemsWithImages)
        if (item.id != null && item.localImagePath.isNotEmpty)
          item.id!: item.localImagePath,
    };
    _savedMedicationInfoList = _savedMedicationInfoList
        .map(/* 함수이름: map 콜백
         * 함수역할: 서버 갱신 결과에 이전 약 ID별 로컬 이미지 경로가 있으면 복원한다.
         * 매개변수:
         * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 이전 로컬 이미지를 유지한 약 정보 또는 원래 항목.
         */(item) {
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

  // 함수이름: _deleteLocalMedicationImage
  // 함수역할: 삭제된 저장 약의 환자별 기기 사진을 정리하고 사진 삭제 실패는 서버 삭제 결과에 전파하지 않는다.
  // 매개변수:
  // - medicationId (int): 대상 저장 복약정보의 식별자
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
