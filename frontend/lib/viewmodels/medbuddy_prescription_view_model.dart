part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_prescription_view_model.dart
// 역할: 처방전 선택, OCR 검토, 약품 분석, 저장 요청 준비 상태를 관리한다.

// 확장명: MedBuddyPrescriptionViewModel
// 역할: MedBuddyViewModel의 해당 기능 상태 전이와 Control 호출을 한곳에 모은다.
extension MedBuddyPrescriptionViewModel on MedBuddyViewModel {
  // 함수이름: requestPrescriptionImage
  // 함수역할:
  // - 시스템 카메라 기반 처방전 OCR 흐름을 시작한다.
  // - 전용 카메라를 사용할 수 없는 기존 호출과 테스트 호환성을 위해 유지한다.
  // 반환값:
  // - 없음
  Future<void> requestPrescriptionImage() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImage,
      cancelledMessage: '사진 촬영이 취소되었습니다.',
    );
  }

  // 함수이름: requestCapturedPrescriptionImage
  // 함수역할:
  // - 전용 촬영 화면에서 반환한 처방전 파일의 OCR 흐름을 시작한다.
  // 매개변수:
  // - image: 전용 카메라 화면에서 촬영한 처방전 이미지
  // 반환값:
  // - 없음
  Future<void> requestCapturedPrescriptionImage(XFile image) async {
    await _requestPrescriptionRecognition(
      imageRequest: ({onImageSelected}) {
        return inputPrescription.requestCapturedPrescriptionImage(
          image,
          onImageSelected: onImageSelected,
        );
      },
      cancelledMessage: '사진 촬영이 취소되었습니다.',
    );
  }

  // 함수명: requestPrescriptionImageFromGallery
  // 함수역할:
  // - 갤러리 이미지 선택 기반 처방전 OCR 흐름을 시작한다.
  // 반환값:
  // - 없음
  Future<void> requestPrescriptionImageFromGallery() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImageFromGallery,
      cancelledMessage: '이미지 선택이 취소되었습니다.',
    );
  }

  // 함수이름: updateRecognizedMedicationSchedule
  // 함수역할:
  // - 사용자가 수정한 OCR 인식 결과를 분석 대기 목록에 반영한다.
  // - 약명이 변경되면 최초 OCR 원문을 보존하고 사용자 수정 정보로 표시한다.
  // 매개변수:
  // - scheduleIndex: 전체 OCR 인식 결과 목록에서 수정할 항목의 인덱스
  // - medicationSchedule: 사용자가 입력한 변경값이 포함된 복약 일정
  // 반환값:
  // - 없음
  void updateRecognizedMedicationSchedule(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) {
    if (_prescriptionFlowState != PrescriptionFlowState.previewReady ||
        scheduleIndex < 0 ||
        scheduleIndex >= _recognizedMedicationScheduleList.length) {
      return;
    }

    final currentSchedule = _recognizedMedicationScheduleList[scheduleIndex];
    final updatedName = medicationSchedule.medicationName.trim();
    if (updatedName.isEmpty) {
      return;
    }

    final isOriginalNameReset =
        medicationSchedule.nameCorrectionSource == 'ocr_reset';
    final isNameChanged = updatedName != currentSchedule.medicationName.trim();
    final originalOcrName = currentSchedule.rawMedicationName.trim().isEmpty
        ? currentSchedule.medicationName.trim()
        : currentSchedule.rawMedicationName.trim();
    final normalizedSchedule = medicationSchedule.copyWith(
      medicationName: updatedName,
      dosage: medicationSchedule.dosage.trim(),
      intakeTime: medicationSchedule.intakeTime.trim(),
      rawMedicationName: isOriginalNameReset
          ? ''
          : isNameChanged
          ? originalOcrName
          : medicationSchedule.rawMedicationName,
      nameConfidence: isOriginalNameReset ? 0 : 1,
      nameCorrectionSource: isOriginalNameReset
          ? 'unverified'
          : isNameChanged
          ? 'user_edit'
          : 'user_review',
    );

    final updatedScheduleList = List<MedicationSchedule>.of(
      _recognizedMedicationScheduleList,
    );
    updatedScheduleList[scheduleIndex] = normalizedSchedule;
    _recognizedMedicationScheduleList = updatedScheduleList;
    _analyzedMedicationList = [];
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _completedMedicationSaveIndexes.clear();
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'The OCR result was updated.'
        : 'OCR 인식 결과를 수정했습니다.';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수명: returnToPrescriptionPreview
  // 역할:
  // - 약품 상세 조회에 실패한 뒤에도 현재 이미지와 OCR 수정 결과를 유지한 채 검토 화면으로 돌아간다.
  void returnToPrescriptionPreview() {
    if (_recognizedMedicationScheduleList.isEmpty) {
      return;
    }
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'Review the recognized medication information.'
        : '인식된 약 정보를 다시 확인해주세요.';
    _prescriptionFlowState = PrescriptionFlowState.previewReady;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: requestPrescriptionAnalysis
  // 함수역할:
  // - UC-1에서 인식된 약 목록 각각에 대해 공공데이터 기반 상세 정보를 요청한다.
  // - 저장은 하지 않고 분석 성공/실패 화면 상태까지만 변경한다.
  // 매개변수:
  // - 없음
  // 반환값:
  // - 없음
  Future<void> requestPrescriptionAnalysis() async {
    if (_recognizedMedicationScheduleList.isEmpty) {
      _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
      _showAnalysisFailure('인식된 처방 내역이 없습니다.');
      return;
    }

    final operationId = _beginPrescriptionOperation();
    final recognizedSchedules = List<MedicationSchedule>.of(
      _recognizedMedicationScheduleList,
    );
    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = [];
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _notifyViewModelListeners(MedBuddyFeature.prescription);

    try {
      final analysisBatch = await _analyzeMedicationSchedules(
        recognizedSchedules,
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      final analyzedMedicationList = analysisBatch.results
          .whereType<AnalyzedMedication>()
          .toList(growable: false);
      final failedAnalysisCount =
          analysisBatch.results.length - analyzedMedicationList.length;

      if (analyzedMedicationList.isEmpty) {
        _showAnalysisFailure(
          analysisBatch.errorMessages.isNotEmpty
              ? analysisBatch.errorMessages.first
              : (_isEnglishSetting
                    ? 'No matching medication was found. Review the OCR medication name.'
                    : '일치하는 약 정보를 찾지 못했습니다. OCR 약 이름을 확인해주세요.'),
        );
        return;
      }

      _analyzedMedicationList = analyzedMedicationList;
      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = failedAnalysisCount > 0
          ? '처방전 분석은 완료되었지만 $failedAnalysisCount개 약 정보는 확인하지 못했습니다.'
          : '처방전 분석이 완료되었습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
    } on StateError catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(
        UserFacingErrorMessage.resolve(
          error,
          isEnglish: _isEnglishSetting,
          context: UserFacingErrorContext.medicationLookup,
        ),
      );
    } catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(
        UserFacingErrorMessage.resolve(
          error,
          isEnglish: _isEnglishSetting,
          context: UserFacingErrorContext.medicationLookup,
        ),
      );
    }
  }

  // 함수이름: _analyzeMedicationSchedules
  // 함수역할:
  // - 처방 약 상세조회를 여섯 건씩 나누어 서버 공공 API 동시 호출 제한을 활용한다.
  // - 일부 조회가 실패해도 나머지 약의 분석 결과와 원래 순서를 유지한다.
  // 매개변수:
  // - schedules: OCR 결과에서 사용자가 확인한 복약 일정 목록
  // 반환값:
  // - 입력 순서와 같은 nullable 분석 결과 목록
  Future<_MedicationAnalysisBatch> _analyzeMedicationSchedules(
    List<MedicationSchedule> schedules,
  ) async {
    const batchSize = 6;
    final results = <AnalyzedMedication?>[];
    final errorMessages = <String>[];
    for (var start = 0; start < schedules.length; start += batchSize) {
      final end = math.min(start + batchSize, schedules.length);
      final batch = schedules.sublist(start, end);
      final batchResults = await Future.wait(
        batch.map((schedule) async {
          try {
            final detail = await checkMedicationDetail.requestMedicationDetail(
              schedule,
            );
            if (detail == null) {
              return null;
            }
            return AnalyzedMedication(schedule: schedule, detail: detail);
          } catch (error) {
            errorMessages.add(
              UserFacingErrorMessage.resolve(
                error,
                isEnglish: _isEnglishSetting,
                context: UserFacingErrorContext.medicationLookup,
              ),
            );
            return null;
          }
        }),
      );
      results.addAll(batchResults);
    }
    return _MedicationAnalysisBatch(
      results: results,
      errorMessages: errorMessages,
    );
  }

  // 함수이름: _refreshPrescriptionChangeRadar
  // 함수역할:
  // - 결과 화면을 막지 않고 현재 처방과 이전 처방의 비교 결과를 요청한다.
  // - 사용자가 화면을 벗어난 뒤 도착한 응답은 현재 상태에 반영하지 않는다.
  // 매개변수:
  // - operationId: 요청 시작 시점의 처방 작업 식별자
  // - medications: 공공데이터 상세조회가 끝난 현재 처방 목록
  // 반환값:
  // - 없음
  Future<void> _refreshPrescriptionChangeRadar(
    int operationId,
    List<AnalyzedMedication> medications,
  ) async {
    PrescriptionChangeRadar? radar;
    try {
      radar = await checkPrescriptionChange.requestPrescriptionChange(
        medications,
      );
    } catch (_) {
      radar = null;
    }
    if (!_isCurrentPrescriptionOperation(operationId) ||
        _prescriptionFlowState != PrescriptionFlowState.resultReady) {
      return;
    }
    _prescriptionChangeRadar = radar;
    _isPrescriptionChangeLoading = false;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수명: showMedicationAnalysisResult
  // 함수역할:
  // - 분석 성공 화면에서 실제 결과 목록 화면으로 이동할 수 있도록 상태를 변경한다.
  // 반환값:
  // - 없음
  void showMedicationAnalysisResult() {
    if (_analyzedMedicationList.isEmpty) {
      _showAnalysisFailure('확인할 분석 결과가 없습니다.');
      return;
    }

    _prescriptionFlowState = PrescriptionFlowState.resultReady;
    if (_analyzedMedicationList.length !=
        _recognizedMedicationScheduleList.length) {
      _prescriptionChangeRadar = null;
      _isPrescriptionChangeLoading = false;
      _notifyViewModelListeners();
      return;
    }
    _isPrescriptionChangeLoading = true;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
    unawaited(
      _refreshPrescriptionChangeRadar(
        _prescriptionOperationId,
        List<AnalyzedMedication>.of(_analyzedMedicationList),
      ),
    );
  }

  // 함수명: requestMedicationSave
  // 함수역할:
  // - 이미 분석된 약 상세 정보를 저장 목록에 저장한다.
  // 매개변수:
  // - analyzedMedication: OCR 스케줄과 상세 정보가 결합된 분석 결과
  // - medicationIndex: 저장 버튼 로딩 표시를 위한 화면상 인덱스
  // 반환값:
  // - 저장 성공 여부
  Future<bool> requestMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) async {
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }
    if (_completedMedicationSaveIndexes.contains(medicationIndex)) {
      _statusMessage = '이미 추가된 약입니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return true;
    }

    _statusMessage = '${analyzedMedication.displayName} 저장 중...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final result = await saveMedicationInfo(
        analyzedMedication.detail,
        medicationSchedule: analyzedMedication.schedule,
      );
      if (result.isCompleted) {
        _completedMedicationSaveIndexes.add(medicationIndex);
        _notifyViewModelListeners(MedBuddyFeature.prescription);
      }
      return result.isCompleted;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

  Future<bool> requestAllAnalyzedMedicationSave() async {
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }
    if (_analyzedMedicationList.isEmpty) {
      _statusMessage = '저장할 분석 결과가 없습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }

    _isAllMedicationSaving = true;
    _statusMessage = '전체 복약 일정을 저장 중입니다...';
    _notifyViewModelListeners(MedBuddyFeature.prescription);

    var savedCount = 0;
    var duplicateCount = 0;
    var failedCount = 0;

    try {
      for (var index = 0; index < _analyzedMedicationList.length; index += 1) {
        if (_completedMedicationSaveIndexes.contains(index)) {
          duplicateCount += 1;
          continue;
        }

        _savingMedicationIndex = index;
        _notifyViewModelListeners(MedBuddyFeature.prescription);

        final analyzedMedication = _analyzedMedicationList[index];
        final result = await saveMedicationInfo(
          analyzedMedication.detail,
          medicationSchedule: analyzedMedication.schedule,
          refreshAfterSave: false,
        );
        if (result.status == MedicationSaveStatus.saved) {
          savedCount += 1;
          _completedMedicationSaveIndexes.add(index);
        } else if (result.status == MedicationSaveStatus.duplicate) {
          duplicateCount += 1;
          _completedMedicationSaveIndexes.add(index);
        } else {
          failedCount += 1;
        }
      }

      await fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
      _statusMessage = _buildBulkSaveMessage(
        savedCount: savedCount,
        duplicateCount: duplicateCount,
        failedCount: failedCount,
      );
      return failedCount == 0;
    } finally {
      _savingMedicationIndex = null;
      _isAllMedicationSaving = false;
      _notifyViewModelListeners(MedBuddyFeature.prescription);
    }
  }

  // 함수명: _requestPrescriptionRecognition
  // 함수역할:
  // - 카메라/갤러리 공통 처방전 OCR 흐름을 상태 머신 형태로 처리한다.
  // - 사용자가 선택을 취소하면 분석 화면으로 넘어가지 않도록 idle 상태로 되돌린다.
  // 매개변수:
  // - imageRequest: 이미지 선택과 OCR 요청을 수행하는 함수
  // - cancelledMessage: 사용자가 취소했을 때 보여줄 상태 메시지
  // 반환값:
  // - 없음
  Future<void> _requestPrescriptionRecognition({
    required Future<List<MedicationSchedule>?> Function({
      VoidCallback? onImageSelected,
    })
    imageRequest,
    required String cancelledMessage,
  }) async {
    final operationId = _beginPrescriptionOperation();
    _recognizedMedicationScheduleList = [];
    _recognizedTextRegionList = [];
    _prescriptionPreviewImagePath = '';
    _analyzedMedicationList = [];
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;

    try {
      final result = await imageRequest(
        onImageSelected: () {
          if (_isCurrentPrescriptionOperation(operationId)) {
            _prescriptionPreviewImagePath =
                inputPrescription.lastSelectedImagePath;
            _showPrescriptionRecognitionProgress();
          }
        },
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      if (result == null) {
        _statusMessage = cancelledMessage;
        _prescriptionFlowState = PrescriptionFlowState.idle;
        _notifyViewModelListeners(MedBuddyFeature.prescription);
        return;
      }

      if (result.isEmpty) {
        _showAnalysisFailure('처방전에서 약 정보를 찾지 못했습니다.');
        return;
      }

      _recognizedMedicationScheduleList = result;
      _recognizedTextRegionList = inputPrescription.lastRecognizedTextRegions;
      _recordPrescriptionRecognitionCounts(result);
      _prescriptionFlowState = PrescriptionFlowState.previewReady;
      _statusMessage = prescriptionRecognitionNotice.isEmpty
          ? '처방전 인식이 완료되었습니다.'
          : '처방전 인식이 완료되었습니다. 인식 내역을 확인해주세요.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
    } on StateError catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(
        UserFacingErrorMessage.resolve(error, isEnglish: _isEnglishSetting),
      );
    } catch (error) {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _showAnalysisFailure(
        UserFacingErrorMessage.resolve(error, isEnglish: _isEnglishSetting),
      );
    }
  }

  int _beginPrescriptionOperation() {
    _prescriptionOperationId += 1;
    return _prescriptionOperationId;
  }

  void _cancelPrescriptionOperation() {
    _prescriptionOperationId += 1;
  }

  bool _isCurrentPrescriptionOperation(int operationId) {
    return _prescriptionOperationId == operationId;
  }

  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = '처방전을 인식 중입니다...';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  void _clearPrescriptionRecognitionCounts() {
    _lastPrescriptionRawMedicationCount = 0;
    _lastPrescriptionParsedMedicationCount = 0;
    _lastPrescriptionSkippedMedicationCount = 0;
  }

  void _recordPrescriptionRecognitionCounts(
    List<MedicationSchedule> schedules,
  ) {
    final parsedCount = inputPrescription.lastParsedMedicationCount > 0
        ? inputPrescription.lastParsedMedicationCount
        : schedules.length;
    final rawCount = inputPrescription.lastRawMedicationCount > 0
        ? inputPrescription.lastRawMedicationCount
        : parsedCount;
    final skippedCount = inputPrescription.lastSkippedMedicationCount > 0
        ? inputPrescription.lastSkippedMedicationCount
        : rawCount - parsedCount;

    _lastPrescriptionParsedMedicationCount = parsedCount < 0 ? 0 : parsedCount;
    _lastPrescriptionRawMedicationCount = rawCount < 0 ? 0 : rawCount;
    _lastPrescriptionSkippedMedicationCount = skippedCount < 0
        ? 0
        : skippedCount;
  }

  void _showAnalysisFailure(String message) {
    _analysisErrorMessage = message;
    _statusMessage = message;
    _prescriptionFlowState = PrescriptionFlowState.analysisFailed;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  String _buildBulkSaveMessage({
    required int savedCount,
    required int duplicateCount,
    required int failedCount,
  }) {
    final parts = <String>[];
    if (savedCount > 0) {
      parts.add('$savedCount개 저장');
    }
    if (duplicateCount > 0) {
      parts.add('$duplicateCount개 중복');
    }
    if (failedCount > 0) {
      parts.add('$failedCount개 실패');
    }
    if (parts.isEmpty) {
      return '이미 추가된 약입니다.';
    }
    return '전체 저장 완료: ${parts.join(', ')}';
  }

  List<String> _slotKeysForSchedule(MedicationSchedule schedule) {
    if (schedule.scheduleSlotKeys.isNotEmpty) {
      return schedule.slotKeys;
    }
    if (schedule.dailyFrequencyCount > 0) {
      return medicationScheduleSlotKeysForFrequency(
        schedule.dailyFrequencyCount,
      );
    }
    if (schedule.slotStatuses.isNotEmpty) {
      final slotKeys = medicationScheduleSlotKeys
          .where((slotKey) => schedule.slotStatuses.containsKey(slotKey))
          .toList(growable: false);
      if (slotKeys.isNotEmpty) {
        return slotKeys;
      }
    }
    return schedule.slotKeys;
  }
}

// 클래스명: _MedicationAnalysisBatch
// 역할: 병렬 약품 조회 결과와 사용자에게 전달할 실패 원인을 함께 보관한다.
class _MedicationAnalysisBatch {
  final List<AnalyzedMedication?> results;
  final List<String> errorMessages;

  const _MedicationAnalysisBatch({
    required this.results,
    required this.errorMessages,
  });
}
