import 'dart:async';

import '../controls/check_saved_medication_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/manual_medication_entry_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../entities/identified_pill_save_request_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/medication_match_review_entity.dart';
import '../services/app_temp_file.dart';
import '../services/manual_medication_image_store.dart';
import '../services/user_facing_error_message.dart';
import 'saved_medication_batch_delete_result.dart';

// 파일명: medbuddy_saved_medication_view_model.dart
// 역할: 저장된 복약정보의 저장, 조회, 단건·일괄 삭제 상태를 관리한다.

// Class Name: MedBuddySavedMedicationViewModel
// Role: Owns saved-medication list state, device photos and regimen-change workflows.
// Responsibilities: Preserve partial save/delete outcomes, reject stale account work and refresh schedules/reminders after changes.
// Attributes: Query/save/image boundaries and patientHash define ownership; generations guard asynchronous work; lists, feedback and in-flight regimen maps hold state.
class MedBuddySavedMedicationViewModel {
  final CheckSavedMedication checkSavedMedication;
  final CheckMedicationDetail checkMedicationDetail;
  final ManualMedicationImageStore manualMedicationImageStore;
  final String patientHash;
  final bool Function() _readEnglishSetting;
  final Future<void> Function() fetchTodayMedicationSchedule;
  final Future<void> Function()? invalidateSchedule;
  // 처방 변경 요청 동안 일정을 비우되, 변경이 서버에 적용되지 않으면 되돌릴 수 있게 한다.
  final Future<Object?> Function()? suspendSchedule;
  final Future<void> Function(Object? backup)? restoreSchedule;
  final Future<void> Function()
  _synchronizeMedicationReminderSchedulesIfScheduleIsFresh;
  final void Function(String) _onChanged;
  bool _disposed = false;
  int _loadGeneration = 0;
  int _saveGeneration = 0;
  bool _isSavedMedicationLoading = false;
  bool _hasLoadError = false;
  List<MedicationDetail> _savedMedicationInfoList = [];
  String _statusMessage = '';
  final Map<int, Future<MedicationRegimenResult>> _regimenRequests = {};
  final Map<int, String> _regimenOperationIds = {};

  // Function Name: MedBuddySavedMedicationViewModel
  // Description: Bind borrowed catalog/save controls and cross-feature refresh operations for one patient.
  // Parameters: checkSavedMedication (CheckSavedMedication): persistence; checkMedicationDetail (CheckMedicationDetail): catalog lookup; manualMedicationImageStore (ManualMedicationImageStore): device photos; patientHash (String): owner; readEnglishSetting (bool Function()): locale; fetchTodayMedicationSchedule (Future<void> Function()): schedule reload; invalidateSchedule (Future<void> Function()? ): invalidate old projection; suspendSchedule (Future<Object?> Function()? ): suspend and capture backup; restoreSchedule (Future<void> Function(Object?)?): restore backup; synchronizeReminders (Future<void> Function()): reminder refresh; onChanged (void Function(String)): feature updates.
  // Returns: MedBuddySavedMedicationViewModel: independent saved-medication state owner.
  MedBuddySavedMedicationViewModel({
    required this.checkSavedMedication,
    required this.checkMedicationDetail,
    required this.manualMedicationImageStore,
    required this.patientHash,
    required bool Function() readEnglishSetting,
    required this.fetchTodayMedicationSchedule,
    this.invalidateSchedule,
    this.suspendSchedule,
    this.restoreSchedule,
    required Future<void> Function() synchronizeReminders,
    required void Function(String) onChanged,
  }) : _readEnglishSetting = readEnglishSetting,
       _synchronizeMedicationReminderSchedulesIfScheduleIsFresh =
           synchronizeReminders,
       _onChanged = onChanged;

  // Function Name: isLoading
  // Description: Exposes loading owned by the newest request.
  // Parameters: None. Returns: Whether a list request is active.
  bool get isLoading => _isSavedMedicationLoading;

  // Function Name: hasLoadError
  // Description: Tells a failed list request apart from a list that is really empty.
  // Parameters: None. Returns: Whether the newest finished list request failed.
  bool get hasLoadError => _hasLoadError;

  // Function Name: medications
  // Description: Prevents callers from mutating the owned list.
  // Parameters: None. Returns: Read-only medication snapshot.
  List<MedicationDetail> get medications =>
      List.unmodifiable(_savedMedicationInfoList);

  // Function Name: statusMessage
  // Description: Exposes feature-local feedback.
  // Parameters: None. Returns: Latest saved-medication message.
  String get statusMessage => _statusMessage;

  // Function Name: _isEnglishSetting
  // Description: Reads current display language without sharing settings state.
  // Parameters: None. Returns: Whether English feedback is selected.
  bool get _isEnglishSetting => _readEnglishSetting();

  // Function Name: _notifyViewModelListeners
  // Description: Publishes only this feature's feedback while alive.
  // Parameters: None. Returns: None.
  void _notifyViewModelListeners() {
    if (!_disposed) _onChanged(_statusMessage);
  }

  // 함수이름: clear
  // 함수역할: 저장·조회 세대를 바꿔 이전 응답을 무효화하고 계정별 목록·오류·변경 요청 추적을 비운다.
  // 매개변수: 없음.
  // 반환값: 없음; 진행 중 원격 요청 자체를 취소하지는 않는다.
  void clear() {
    _saveGeneration++;
    _loadGeneration++;
    _savedMedicationInfoList = [];
    _isSavedMedicationLoading = false;
    _hasLoadError = false;
    _statusMessage = '';
    _regimenRequests.clear();
    _regimenOperationIds.clear();
  }

  // Function Name: dispose
  // Description: Invalidates completions without disposing borrowed dependencies.
  // Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
    clear();
  }

  // 함수이름: _isCurrentSave
  // 함수역할: 목록 재조회와 별개로 저장 작업의 계정 세대가 여전히 유효한지 확인한다.
  // 매개변수: generation: 저장 시작 시 기록한 세대 번호.
  // 반환값: 종료되지 않았고 현재 저장 세대와 같으면 true.
  bool _isCurrentSave(int generation) =>
      !_disposed && generation == _saveGeneration;

  // 함수이름: _cancelledSaveResult
  // 함수역할: 현재 언어에 맞는 저장 취소 결과를 만든다.
  // 매개변수: 없음.
  // 반환값: 실패 상태의 MedicationSaveResult; 서버 저장을 실행하거나 취소하지 않는다.
  MedicationSaveResult _cancelledSaveResult() => MedicationSaveResult(
    status: MedicationSaveStatus.failed,
    message: _isEnglishSetting
        ? 'Medication saving was canceled.'
        : '복약 정보 저장이 취소되었습니다.',
  );

  // 함수이름: changeMedicationRegimen
  // 함수역할: 같은 약의 동일 요청 ID는 공유하고 서로 다른 동시 변경은 충돌로 반환한다.
  // 매개변수: medicationId: 변경 약 ID; change: 적용할 변경 의도.
  // 반환값: 변경 결과 Future; 종료된 모델은 cancelled이며 완료 후 해당 진행 요청만 제거한다.
  Future<MedicationRegimenResult> changeMedicationRegimen(
    int medicationId,
    MedicationRegimenChange change,
  ) {
    if (_disposed) {
      return Future.value(
        const MedicationRegimenResult(
          failure: MedicationRegimenFailure.cancelled,
        ),
      );
    }
    final pending = _regimenRequests[medicationId];
    if (pending != null) {
      return _regimenOperationIds[medicationId] == change.operationId
          ? pending
          : Future.value(
              const MedicationRegimenResult(
                failure: MedicationRegimenFailure.conflict,
              ),
            );
    }
    final generation = _saveGeneration;
    final request = _applyRegimenChange(medicationId, change, generation);
    _regimenRequests[medicationId] = request;
    _regimenOperationIds[medicationId] = change.operationId;
    unawaited(
      request.whenComplete(() {
        if (identical(_regimenRequests[medicationId], request)) {
          _regimenRequests.remove(medicationId);
          _regimenOperationIds.remove(medicationId);
        }
      }),
    );
    return request;
  }

  // Function Name: _applyRegimenChange
  // Description: Applies a guarded regimen change, copies an edited medication's photo and refreshes affected state.
  // Parameters: medicationId: Original ID; change: Stable request; generation: Owning save generation.
  // Returns: A result distinguishing save success from refresh failure; stale account generations return cancelled and photo-copy failure does not undo a successful change.
  Future<MedicationRegimenResult> _applyRegimenChange(
    int medicationId,
    MedicationRegimenChange change,
    int generation,
  ) async {
    MedicationRegimenResult result;
    try {
      result = await _changingRegimen(
        () => checkSavedMedication.changeRegimen(medicationId, change),
        // 충돌·대상 없음은 서버 상태가 이미 달라졌다는 뜻이므로 일정을 다시 받는다.
        applied: (result) =>
            result.success ||
            result.failure == MedicationRegimenFailure.conflict ||
            result.failure == MedicationRegimenFailure.missing,
      );
    } catch (_) {
      result = const MedicationRegimenResult(
        failure: MedicationRegimenFailure.network,
      );
    }
    if (!_isCurrentSave(generation)) {
      return const MedicationRegimenResult(
        failure: MedicationRegimenFailure.cancelled,
      );
    }
    // 같은 약의 용량·주기 변경은 새 ID로 저장되므로 기기에만 있는 사진을 새 항목에도 이어 붙인다.
    final newMedicationId = result.medicationId;
    if (result.success &&
        change.action == MedicationRegimenAction.edit &&
        newMedicationId != null &&
        newMedicationId != medicationId) {
      try {
        await manualMedicationImageStore.copyImage(
          patientHash: patientHash,
          fromMedicationId: medicationId,
          toMedicationId: newMedicationId,
        );
      } catch (_) {
        // 사진 복사 실패가 이미 서버에 저장된 처방 변경을 실패로 만들지 않게 한다.
      }
    }
    if (result.success ||
        result.failure == MedicationRegimenFailure.conflict ||
        result.failure == MedicationRegimenFailure.missing) {
      try {
        await fetchSavedMedicationInfo();
        if (!_isCurrentSave(generation)) {
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.cancelled,
          );
        }
        await fetchTodayMedicationSchedule();
        if (!_isCurrentSave(generation)) {
          return const MedicationRegimenResult(
            failure: MedicationRegimenFailure.cancelled,
          );
        }
        await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
        if (result.success && _hasLoadError) {
          result = MedicationRegimenResult(
            medicationId: result.medicationId,
            revision: result.revision,
            refreshFailed: true,
          );
        }
      } catch (_) {
        if (result.success) {
          result = MedicationRegimenResult(
            medicationId: result.medicationId,
            revision: result.revision,
            refreshFailed: true,
          );
        }
      }
    }
    if (!_isCurrentSave(generation)) {
      return const MedicationRegimenResult(
        failure: MedicationRegimenFailure.cancelled,
      );
    }
    _statusMessage = result.message(_isEnglishSetting);
    _notifyViewModelListeners();
    return result;
  }

  // Function Name: saveMedicationInfo
  // Description: Saves medication details and optional schedule/photo, then conditionally refreshes dependent state.
  // Parameters: medicationInfo: Detail data; medicationSchedule: Optional OCR/manual schedule; localImagePath: Device-only photo; refreshAfterSave: Whether to refresh immediately.
  // Returns: The save/duplicate/failure result; stale generations skip follow-up effects, and local photo failure does not reverse server success.
  Future<MedicationSaveResult> saveMedicationInfo(
    MedicationDetail medicationInfo, {
    MedicationSchedule? medicationSchedule,
    String localImagePath = '',
    bool refreshAfterSave = true,
  }) async {
    if (_disposed) return _cancelledSaveResult();
    final generation = _saveGeneration;
    _statusMessage = _isEnglishSetting
        ? 'Saving ${medicationInfo.itemName}...'
        : '${medicationInfo.itemName} 저장 중...';
    _notifyViewModelListeners();

    final result = await _changingRegimen(
      () => checkSavedMedication.saveMedicationDetail(
        medicationInfo,
        medicationSchedule: medicationSchedule,
      ),
      applied: (result) => result.status != MedicationSaveStatus.failed,
    );
    // 서버가 이미 저장한 결과는 유지하되 종료된 계정의 사진·일정 작업은 시작하지 않는다.
    if (!_isCurrentSave(generation)) return result;
    if (result.status == MedicationSaveStatus.failed) {
      _statusMessage = _isEnglishSetting
          ? 'Could not save medication information.'
          : result.message;
      _notifyViewModelListeners();
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
        if (!_isCurrentSave(generation)) return result;
        // 보관용 사본을 만든 뒤에는 사진 선택 과정에서 생긴 임시 사본을 남기지 않는다. 앱 임시 폴더 밖의 파일은 지우지 않는다.
        await deleteAppTempFile(localImagePath);
      } catch (_) {
        // 서버 저장은 완료됐으므로 로컬 사진 실패가 복약정보 저장까지 취소하지 않게 한다.
      }
    }

    if (!_isCurrentSave(generation)) return result;

    _statusMessage = result.status == MedicationSaveStatus.duplicate
        ? (_isEnglishSetting
              ? 'This medication is already saved.'
              : '이미 추가된 약입니다.')
        : (_isEnglishSetting
              ? 'Medication information saved.'
              : '복약 정보가 성공적으로 저장되었습니다.');
    if (refreshAfterSave) await _refreshAfterSaves(generation);
    if (!_isCurrentSave(generation)) return result;
    _notifyViewModelListeners();
    return result;
  }

  // Function Name: _refreshAfterSaves
  // Description: Refreshes the saved list, today's schedule and reminders in order while account ownership remains current.
  // Parameters: generation: Save generation captured before the refresh.
  // Returns: Completion; stops before later stages after invalidation and propagates refresh errors.
  Future<void> _refreshAfterSaves(int generation) async {
    await fetchSavedMedicationInfo();
    if (!_isCurrentSave(generation)) return;
    await fetchTodayMedicationSchedule();
    if (!_isCurrentSave(generation)) return;
    await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
  }

  // Function Name: refreshAfterMedicationSaves
  // Description: Runs one shared refresh after a caller has saved multiple medications without per-save refresh.
  // Parameters: None.
  // Returns: Completion after list/schedule/reminder refresh and notification, unless disposed or invalidated.
  Future<void> refreshAfterMedicationSaves() async {
    if (_disposed) return;
    final generation = _saveGeneration;
    await _refreshAfterSaves(generation);
    if (!_isCurrentSave(generation)) return;
    _notifyViewModelListeners();
  }

  // Function Name: saveManualMedication
  // Description: Preserves an explicitly selected catalog item, otherwise attempts lookup and falls back to manual data.
  // Parameters: entry: User-entered medication, schedule and photo; refreshAfterSave: Immediate-refresh policy.
  // Returns: A save result; lookup failure does not prevent manual registration, but account changes cancel further work.
  Future<MedicationSaveResult> saveManualMedication(
    ManualMedicationEntry entry, {
    bool refreshAfterSave = true,
  }) async {
    if (_disposed) return _cancelledSaveResult();
    final generation = _saveGeneration;
    final schedule = entry.toMedicationSchedule();
    final selected = entry.catalogMedication;
    MedicationDetail? medicationDetail =
        selected != null &&
            selected.itemName.trim() == entry.medicationName.trim()
        ? selected
        : null;
    // 사용자가 선택한 품목은 다시 이름 검색으로 다른 약에 연결하지 않는다.
    if (medicationDetail == null) {
      try {
        medicationDetail = await checkMedicationDetail.requestMedicationDetail(
          schedule,
        );
      } catch (_) {
        // 직접 등록은 외부 약품 조회가 잠시 실패해도 사용할 수 있어야 한다.
      }
    }
    if (!_isCurrentSave(generation)) return _cancelledSaveResult();
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
      refreshAfterSave: refreshAfterSave,
    );
  }

  // 함수이름: saveIdentifiedPill
  // 함수역할: 사용자가 고른 낱알약 후보와 확인한 복약 일정을 공공데이터 상세 정보로 보완한다. 상세 조회가 실패해도 후보 정보와 사용자 입력 일정으로 기존 저장 흐름을 계속 진행한다. 이름으로 조회한 상세 정보는 후보와 품목번호가 같을 때만 사용해 다른 제품의 효능·복용법·주의사항·사진이 선택한 품목번호로 저장되지 않게 한다.
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
    if (_disposed) return _cancelledSaveResult();
    final generation = _saveGeneration;
    MedicationDetail? medicationDetail;
    try {
      medicationDetail = await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
    } on MedicationMatchReview catch (review) {
      // 같은 이름의 제품이 여러 개이면 사용자가 이미 고른 품목번호의 제품만 사용한다.
      medicationDetail = _findCatalogDetailByItemSeq(
        review.candidates,
        candidate.itemSeq,
      );
    } catch (_) {
      // 낱알약 후보는 이미 사용자가 확인했으므로 외부 상세 조회 실패가 저장을 막지 않게 한다.
    }
    if (!_isCurrentSave(generation)) return _cancelledSaveResult();
    if (medicationDetail != null &&
        _isDifferentCatalogItem(medicationDetail.itemSeq, candidate.itemSeq)) {
      // 이름 조회가 다른 제품을 반환하면 그 설명과 사진을 버리고 후보 정보만 저장한다.
      medicationDetail = null;
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

  // Function Name: _findCatalogDetailByItemSeq
  // Description: Finds the candidate matching the user's chosen catalog identifier.
  // Parameters: candidates: Unresolved catalog results; itemSeq: Selected product ID.
  // Returns: The first exact trimmed-ID match, or null for blank/missing IDs.
  static MedicationDetail? _findCatalogDetailByItemSeq(
    List<MedicationDetail> candidates,
    String itemSeq,
  ) {
    final chosenItemSeq = itemSeq.trim();
    if (chosenItemSeq.isEmpty) {
      return null;
    }
    for (final detail in candidates) {
      if (detail.itemSeq.trim() == chosenItemSeq) {
        return detail;
      }
    }
    return null;
  }

  // Function Name: _isDifferentCatalogItem
  // Description: Detects a definite product mismatch only when both catalog identifiers are known.
  // Parameters: lookedUpItemSeq: Lookup result; chosenItemSeq: User choice.
  // Returns: True for two nonempty unequal trimmed IDs; missing IDs cannot establish a mismatch.
  static bool _isDifferentCatalogItem(
    String lookedUpItemSeq,
    String chosenItemSeq,
  ) {
    final lookedUp = lookedUpItemSeq.trim();
    final chosen = chosenItemSeq.trim();
    return lookedUp.isNotEmpty && chosen.isNotEmpty && lookedUp != chosen;
  }

  // Function Name: saveIdentifiedPills
  // Description: Saves pill requests sequentially, retaining each outcome and refreshing once if any save completes.
  // Parameters: requests: Ordered candidate-and-schedule requests.
  // Returns: An unmodifiable result list in input order; individual exceptions become failures and invalidated remaining work becomes cancelled.
  Future<List<MedicationSaveResult>> saveIdentifiedPills(
    List<IdentifiedPillSaveRequest> requests,
  ) async {
    final generation = _saveGeneration;
    if (requests.isEmpty) {
      return const [];
    }

    final results = <MedicationSaveResult>[];
    for (final request in requests) {
      if (!_isCurrentSave(generation)) {
        results.add(_cancelledSaveResult());
        continue;
      }
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

    if (!_isCurrentSave(generation)) return List.unmodifiable(results);
    if (results.any(
      /* 함수이름: any 콜백
     * 함수역할: 일괄 저장 결과 중 실패가 아닌 결과가 있는지 확인한다.
     * 매개변수:
     * - result (MedicationSaveResult): 해당 입력 알약의 성공 식별 결과
     * 반환값:
     * - 해당 저장 결과가 실패 상태가 아니면 true.
     */
      (result) => result.status != MedicationSaveStatus.failed,
    )) {
      await _refreshAfterSaves(generation);
    }
    if (!_isCurrentSave(generation)) return List.unmodifiable(results);
    _notifyViewModelListeners();
    return List<MedicationSaveResult>.unmodifiable(results);
  }

  // Function Name: fetchSavedMedicationInfo
  // Description: Loads server rows before resolving device photos, rejecting obsolete load generations.
  // Parameters: None.
  // Returns: Completion of list loading; failures preserve prior rows with error state, while photo reconciliation runs asynchronously.
  Future<void> fetchSavedMedicationInfo() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _isSavedMedicationLoading = true;
    _hasLoadError = false;
    _notifyViewModelListeners();

    List<MedicationDetail>? fetchedMedicationList;
    // 이 시각 이후 저장된 사진은 받은 목록에 없을 수 있으므로 고아 사진 정리에서 제외한다.
    final listRequestedAt = DateTime.now();
    try {
      fetchedMedicationList = await checkSavedMedication
          .requestSavedMedicationInfo();
      if (_disposed || generation != _loadGeneration) return;
      // 서버 목록을 먼저 표시하고 로컬 사진 파일 확인은 화면을 막지 않도록 분리한다.
      // 이미 알고 있는 기기 사진 경로는 그대로 이어 붙여 새로 고칠 때 사진이 깜빡이지 않게 한다.
      _savedMedicationInfoList = _carryOverLocalImagePaths(
        fetchedMedicationList,
      );
      _hasLoadError = false;
    } on StateError catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      // 조회 실패를 저장된 약이 없는 상태와 구분할 수 있게 기록한다.
      _hasLoadError = true;
      _statusMessage = UserFacingErrorMessage.resolve(
        error,
        isEnglish: _isEnglishSetting,
      );
    } catch (_) {
      if (_disposed || generation != _loadGeneration) return;
      _hasLoadError = true;
      _statusMessage = _isEnglishSetting
          ? 'Could not load saved medication information.'
          : '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _isSavedMedicationLoading = false;
        _notifyViewModelListeners();
      }
    }

    if (fetchedMedicationList != null) {
      unawaited(
        _refreshLocalMedicationImages(
          fetchedMedicationList,
          generation,
          listRequestedAt,
        ),
      );
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

  // Function Name: requestDeleteSavedMedications
  // Description: Deletes unique medication IDs concurrently and removes only successful items from visible state.
  // Parameters: savedMedicationIds: Requested stored IDs; duplicates are removed.
  // Returns: Success/failure counts after applicable schedule/reminder refresh; individual delete exceptions count as failures and photo cleanup is asynchronous.
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

    final deleteResults = await _changingRegimen(
      () => Future.wait(
        uniqueIds.map(/* 함수이름: map 콜백
       * 함수역할: 저장된 약을 개별 삭제하고 예외를 해당 항목의 삭제 실패로 격리한다.
       * 매개변수:
       * - savedMedicationId (int): 대상 저장 복약정보의 식별자
       * 반환값:
       * - 해당 약 삭제 성공 여부를 완료하는 Future.
       */ (savedMedicationId) async {
          try {
            return await checkSavedMedication.requestDelete(savedMedicationId);
          } catch (_) {
            return false;
          }
        }),
      ),
      applied: (results) => results.any((deleted) => deleted),
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
      _loadGeneration++;
      _isSavedMedicationLoading = false;
      _savedMedicationInfoList = _savedMedicationInfoList
          .where(
            /* 함수이름: where 콜백
           * 함수역할: 삭제에 성공한 약 ID를 현재 저장 목록에서 제외한다.
           * 매개변수:
           * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
           * 반환값:
           * - 삭제된 ID 집합에 속하지 않으면 true.
           */
            (item) => !deletedIds.contains(item.id),
          )
          .toList(growable: false);
      _notifyViewModelListeners();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
    }

    return SavedMedicationBatchDeleteResult(
      successCount: deletedIds.length,
      failureCount: uniqueIds.length - deletedIds.length,
    );
  }

  // Function Name: _changingRegimen
  // Description: Suspends schedule caches while a regimen mutation is uncertain, restoring them only after a definite non-applied result.
  // Parameters: action: Mutation; applied: Whether the returned result means schedules must be invalidated.
  // Returns: The action result; exceptions keep caches invalidated, account changes before the action throw, and restoration/invalidation errors propagate.
  Future<T> _changingRegimen<T>(
    Future<T> Function() action, {
    required bool Function(T result) applied,
  }) async {
    final generation = _saveGeneration;
    final suspend = suspendSchedule;
    final invalidate = invalidateSchedule;
    Object? backup;
    // 콜백이 없으면 기다리지 않는다. 기다리면 그사이 계정 전환이 끼어들 수 있다.
    if (suspend != null) {
      backup = await suspend();
    } else if (invalidate != null) {
      await invalidate();
    }
    if (!_isCurrentSave(generation)) throw StateError('Account changed.');
    var changed = true;
    try {
      final result = await action();
      changed = applied(result);
      return result;
    } finally {
      final restore = restoreSchedule;
      if (!changed && restore != null) {
        await restore(backup);
      } else {
        await invalidateSchedule?.call();
      }
    }
  }

  // Function Name: _carryOverLocalImagePaths
  // Description: Carries known device-photo paths into fresh server rows by saved medication ID.
  // Parameters: fetchedMedicationList: Server list before filesystem verification.
  // Returns: Rows with preserved known paths, or the original list when no paths are known; later loading verifies files.
  List<MedicationDetail> _carryOverLocalImagePaths(
    List<MedicationDetail> fetchedMedicationList,
  ) {
    final knownImagePathById = <int, String>{
      for (final item in _savedMedicationInfoList)
        if (item.id != null && item.localImagePath.isNotEmpty)
          item.id!: item.localImagePath,
    };
    if (knownImagePathById.isEmpty) {
      return fetchedMedicationList;
    }
    return fetchedMedicationList
        .map(/* 함수이름: map 콜백
         * 함수역할: 같은 저장 ID의 기기 사진 경로를 이미 알고 있으면 새 항목에 유지한다.
         * 매개변수:
         * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 알고 있던 사진 경로를 유지한 약 정보 또는 원래 항목.
         */ (item) {
          final knownImagePath = knownImagePathById[item.id];
          return knownImagePath == null
              ? item
              : item.copyWith(localImagePath: knownImagePath);
        })
        .toList(growable: false);
  }

  // Function Name: _attachLocalMedicationImages
  // Description: Resolves account-owned photos and removes orphans without deleting images newer than the list request.
  // Parameters: medicationList: Saved rows; listRequestedAt: Optional protected-write cutoff.
  // Returns: Photo-enriched rows, or the original list on any image-store failure.
  Future<List<MedicationDetail>> _attachLocalMedicationImages(
    List<MedicationDetail> medicationList, {
    DateTime? listRequestedAt,
  }) async {
    try {
      final activeIds = medicationList
          .map(
            /* 함수이름: map 콜백
           * 함수역할: 로컬 이미지 정리에 사용할 저장 약 ID를 추출한다.
           * 매개변수:
           * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
           * 반환값:
           * - 저장 약 ID 또는 null.
           */
            (item) => item.id,
          )
          .whereType<int>()
          .where(
            /* 함수이름: where 콜백
           * 함수역할: 로컬 이미지 관리에 사용할 수 있는 양의 저장 약 ID만 남긴다.
           * 매개변수:
           * - id (int): 플랫폼 알림의 예약·교체·취소 식별자
           * 반환값:
           * - ID가 양수이면 true.
           */
            (id) => id > 0,
          )
          .toSet();
      final itemsWithImages = await Future.wait(
        medicationList.map(/* 함수이름: map 콜백
         * 함수역할: 유효한 저장 약 ID의 로컬 이미지 경로를 찾아 약 상세 정보에 병합한다.
         * 매개변수:
         * - medication (MedicationDetail): 로컬 이미지를 복원할 저장 약 정보
         * 반환값:
         * - 로컬 이미지 경로를 반영한 약 상세 정보의 Future.
         */ (medication) async {
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
        keepWrittenAfter: listRequestedAt,
      );
      return itemsWithImages;
    } catch (_) {
      // 플러그인을 사용할 수 없는 테스트 환경에서는 서버 목록만 그대로 사용한다.
      return medicationList;
    }
  }

  // Function Name: _refreshLocalMedicationImages
  // Description: Reconciles resolved image paths only into still-present rows of the current load generation.
  // Parameters: fetchedMedicationList: Source server rows; generation: Load owner; listRequestedAt: Orphan-cleanup cutoff.
  // Returns: Completion; stale/failed/unchanged image reads do not notify or restore deleted medications.
  Future<void> _refreshLocalMedicationImages(
    List<MedicationDetail> fetchedMedicationList,
    int generation,
    DateTime listRequestedAt,
  ) async {
    final itemsWithImages = await _attachLocalMedicationImages(
      fetchedMedicationList,
      listRequestedAt: listRequestedAt,
    );
    if (_disposed || generation != _loadGeneration) return;
    // 사진 조회가 실패하면 받은 목록이 그대로 돌아오므로 이어 붙여 둔 경로를 지우지 않는다.
    if (identical(itemsWithImages, fetchedMedicationList)) return;

    final resolvedImagePathById = <int, String>{
      for (final item in itemsWithImages)
        if (item.id != null) item.id!: item.localImagePath,
    };
    var hasChangedImagePath = false;
    final reconciledMedicationList = _savedMedicationInfoList
        .map(/* 함수이름: map 콜백
         * 함수역할: 같은 저장 ID에 대해 방금 확인한 기기 사진 경로가 현재 값과 다르면 반영한다.
         * 매개변수:
         * - item (MedicationDetail): 현재 변환·검사 중인 응답 또는 목록 항목
         * 반환값:
         * - 확인한 사진 경로를 반영한 약 정보 또는 원래 항목.
         */ (item) {
          final resolvedImagePath = resolvedImagePathById[item.id];
          if (resolvedImagePath == null ||
              resolvedImagePath == item.localImagePath) {
            return item;
          }
          hasChangedImagePath = true;
          return item.copyWith(localImagePath: resolvedImagePath);
        })
        .toList(growable: false);
    if (!hasChangedImagePath) return;
    _savedMedicationInfoList = reconciledMedicationList;
    _notifyViewModelListeners();
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
