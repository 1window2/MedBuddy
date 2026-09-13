part of 'medbuddy_view_model.dart';

// 파일명: medbuddy_prescription_view_model.dart
// 역할: 처방전 선택, OCR 검토, 약품 분석, 저장 요청 준비 상태를 관리한다.

// 클래스명: MedBuddyPrescriptionViewModel
// 역할: 처방전 선택부터 OCR 검토·상세 분석·저장까지의 화면 상태를 확장한다.
// 주요 책임:
// - 사용자 수정과 원본 OCR을 보존하고 작업 세대로 늦은 응답을 차단하며 미확인 항목 재검토 및 부분 저장을 조정한다.
extension MedBuddyPrescriptionViewModel on MedBuddyViewModel {
  // 함수이름: requestCapturedPrescriptionImage
  // 함수역할: 전용 촬영 화면에서 반환한 처방전 파일의 OCR 흐름을 시작한다.
  // 매개변수:
  // - image (XFile): 전용 카메라 화면에서 촬영한 처방전 이미지
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> requestCapturedPrescriptionImage(XFile image) async {
    await _requestPrescriptionRecognition(
      imageRequest: /* 함수이름: imageRequest 콜백
       * 함수역할: 촬영 이미지를 처방전 입력 제어기에 전달하고 이미지 선택 완료 콜백을 연결한다.
       * 매개변수:
       * - onImageSelected (PrescriptionImageSelectedCallback?): 실제 이미지 선택 직후 진행 상태 수신자
       * 반환값:
       * - 촬영 이미지 입력 처리 결과의 Future.
       */({onImageSelected}) {
        return inputPrescription.requestCapturedPrescriptionImage(
          image,
          onImageSelected: onImageSelected,
        );
      },
      cancelledMessage: _isEnglishSetting
          ? 'Photo capture was canceled.'
          : '사진 촬영이 취소되었습니다.',
    );
  }

  // 함수이름: requestPrescriptionImageFromGallery
  // 함수역할: 갤러리 이미지 선택 기반 처방전 OCR 흐름을 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> requestPrescriptionImageFromGallery() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImageFromGallery,
      cancelledMessage: _isEnglishSetting
          ? 'Image selection was canceled.'
          : '이미지 선택이 취소되었습니다.',
    );
  }

  // 함수이름: updateRecognizedMedicationSchedule
  // 함수역할: 사용자가 수정한 OCR 인식 결과를 분석 대기 목록에 반영한다. 약명이 변경되면 최초 OCR 원문을 보존하고 사용자 수정 정보로 표시한다.
  // 매개변수:
  // - scheduleIndex (int): 전체 OCR 인식 결과 목록에서 수정할 항목의 인덱스
  // - medicationSchedule (MedicationSchedule): 사용자가 입력한 변경값이 포함된 복약 일정
  // 반환값:
  // - 없음.
  void updateRecognizedMedicationSchedule(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) {
    final isReviewState =
        _prescriptionFlowState ==
        PrescriptionFlowState.medicationReviewRequired;
    if ((_prescriptionFlowState != PrescriptionFlowState.previewReady &&
            !isReviewState) ||
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
    if (isReviewState) {
      _analyzedMedicationByScheduleIndex.remove(scheduleIndex);
      _unverifiedMedicationScheduleIndexes.add(scheduleIndex);
      _analyzedMedicationList = _orderedAnalyzedMedications();
    } else {
      _analyzedMedicationByScheduleIndex.clear();
      _unverifiedMedicationScheduleIndexes.clear();
      _analyzedMedicationList = [];
    }
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _completedMedicationSaveIndexes.clear();
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'The OCR result was updated.'
        : 'OCR 인식 결과를 수정했습니다.';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: addRecognizedMedicationSchedule
  // 함수역할: OCR이 누락한 약을 사용자가 직접 입력해 현재 처방 검토 목록에 추가한다. 상세조회 재검토 중 추가한 약은 미확인 항목으로 등록해 다음 조회에 포함한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 사용자가 입력한 약명과 복약 정보
  // 반환값:
  // - 없음.
  void addRecognizedMedicationSchedule(MedicationSchedule medicationSchedule) {
    final isReviewState =
        _prescriptionFlowState ==
        PrescriptionFlowState.medicationReviewRequired;
    if (_prescriptionFlowState != PrescriptionFlowState.previewReady &&
        !isReviewState) {
      return;
    }

    final medicationName = medicationSchedule.medicationName.trim();
    if (medicationName.isEmpty) {
      return;
    }
    final normalizedSchedule = medicationSchedule.copyWith(
      medicationName: medicationName,
      dosage: medicationSchedule.dosage.trim(),
      intakeTime: medicationSchedule.intakeTime.trim(),
      rawMedicationName: '',
      nameConfidence: 1,
      nameCorrectionSource: 'manual_add',
    );
    final addedIndex = _recognizedMedicationScheduleList.length;
    _recognizedMedicationScheduleList = [
      ..._recognizedMedicationScheduleList,
      normalizedSchedule,
    ];

    if (isReviewState) {
      _unverifiedMedicationScheduleIndexes.add(addedIndex);
      _analyzedMedicationList = _orderedAnalyzedMedications();
    } else {
      _analyzedMedicationByScheduleIndex.clear();
      _unverifiedMedicationScheduleIndexes.clear();
      _analyzedMedicationList = [];
    }
    _lastPrescriptionParsedMedicationCount =
        _recognizedMedicationScheduleList.length;
    _lastPrescriptionSkippedMedicationCount = math.max(
      0,
      _lastPrescriptionRawMedicationCount -
          _lastPrescriptionParsedMedicationCount,
    );
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _completedMedicationSaveIndexes.clear();
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'The missing medication was added.'
        : '누락된 약을 추가했습니다.';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: returnToPrescriptionPreview
  // 함수역할: 약품 상세 조회에 실패한 뒤에도 현재 이미지와 OCR 수정 결과를 유지한 채 검토 화면으로 돌아간다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void returnToPrescriptionPreview() {
    if (_recognizedMedicationScheduleList.isEmpty) {
      return;
    }
    _analyzedMedicationByScheduleIndex.clear();
    _unverifiedMedicationScheduleIndexes.clear();
    _analyzedMedicationList = [];
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'Review the recognized medication information.'
        : '인식된 약 정보를 다시 확인해주세요.';
    _prescriptionFlowState = PrescriptionFlowState.previewReady;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: requestPrescriptionAnalysis
  // 함수역할: UC-1에서 인식된 약 목록 각각에 대해 공공데이터 기반 상세 정보를 요청한다. 저장은 하지 않고 분석 성공/실패 화면 상태까지만 변경한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> requestPrescriptionAnalysis() async {
    if (_recognizedMedicationScheduleList.isEmpty) {
      _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
      _showAnalysisFailure(
        _isEnglishSetting
            ? 'No recognized prescription information is available.'
            : '인식된 처방 내역이 없습니다.',
      );
      return;
    }

    final isRetryingUnverifiedMedication =
        _prescriptionFlowState ==
            PrescriptionFlowState.medicationReviewRequired &&
        _unverifiedMedicationScheduleIndexes.isNotEmpty;
    final targetIndexes = isRetryingUnverifiedMedication
        ? (_unverifiedMedicationScheduleIndexes.toList()..sort())
        : List<int>.generate(
            _recognizedMedicationScheduleList.length,
            // 함수이름: callback 콜백
            // 함수역할: 현재 처방의 각 일정 위치에 원래 인덱스를 부여한다.
            // 매개변수:
            // - index (int): 현재 목록 항목의 0부터 시작하는 위치
            // 반환값:
            // - 해당 일정의 원래 인덱스.
            (index) => index,
            growable: false,
          );
    if (!isRetryingUnverifiedMedication) {
      _analyzedMedicationByScheduleIndex.clear();
      _unverifiedMedicationScheduleIndexes.clear();
    }

    final operationId = _beginPrescriptionOperation();
    final recognizedSchedules = List<MedicationSchedule>.of(
      _recognizedMedicationScheduleList,
    );
    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = _isEnglishSetting
        ? 'Analyzing medication information...'
        : '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = _orderedAnalyzedMedications();
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _notifyViewModelListeners(MedBuddyFeature.prescription);

    try {
      final analysisBatch = await _analyzeMedicationSchedules(
        recognizedSchedules,
        targetIndexes,
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }

      _unverifiedMedicationScheduleIndexes.removeAll(targetIndexes);
      _analyzedMedicationByScheduleIndex.addAll(
        analysisBatch.analyzedMedicationByScheduleIndex,
      );
      _unverifiedMedicationScheduleIndexes.addAll(
        analysisBatch.unverifiedScheduleIndexes,
      );
      _analyzedMedicationList = _orderedAnalyzedMedications();

      final hasOnlyTechnicalFailures =
          analysisBatch.analyzedMedicationByScheduleIndex.isEmpty &&
          analysisBatch.unmatchedScheduleIndexes.isEmpty &&
          analysisBatch.errorMessagesByScheduleIndex.length ==
              targetIndexes.length;
      if (_analyzedMedicationList.isEmpty && hasOnlyTechnicalFailures) {
        _showAnalysisFailure(
          analysisBatch.errorMessagesByScheduleIndex.values.first,
        );
        return;
      }

      if (_unverifiedMedicationScheduleIndexes.isNotEmpty) {
        final unverifiedCount = _unverifiedMedicationScheduleIndexes.length;
        _analysisErrorMessage =
            analysisBatch.errorMessagesByScheduleIndex.values.isEmpty
            ? ''
            : analysisBatch.errorMessagesByScheduleIndex.values.first;
        _prescriptionFlowState = PrescriptionFlowState.medicationReviewRequired;
        _statusMessage = _isEnglishSetting
            ? '$unverifiedCount medication item(s) could not be verified. Review and retry them.'
            : '$unverifiedCount개 약 정보를 확인하지 못했습니다. 약명을 수정한 뒤 다시 조회해주세요.';
        _notifyViewModelListeners(MedBuddyFeature.prescription);
        return;
      }

      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = _isEnglishSetting
          ? 'Prescription analysis completed.'
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
  // 함수역할: 처방 약 상세조회를 여섯 건씩 나누어 서버 공공 API 동시 호출 제한을 활용한다. 성공, 미일치, 일시적 오류를 원래 OCR 행 인덱스와 함께 구분한다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): OCR 결과에서 사용자가 확인한 전체 복약 일정 목록
  // - scheduleIndexes (List<int>): 이번 요청에서 조회할 OCR 행 인덱스 목록
  // 반환값:
  // - 분석된 약 목록과 일정 인덱스별 성공·미일치·실패 결과를 담은 _MedicationAnalysisBatch의 Future.
  Future<_MedicationAnalysisBatch> _analyzeMedicationSchedules(
    List<MedicationSchedule> schedules,
    List<int> scheduleIndexes,
  ) async {
    const batchSize = 6;
    final analyzedMedicationByScheduleIndex = <int, AnalyzedMedication>{};
    final unmatchedScheduleIndexes = <int>{};
    final errorMessagesByScheduleIndex = <int, String>{};
    for (var start = 0; start < scheduleIndexes.length; start += batchSize) {
      final end = math.min(start + batchSize, scheduleIndexes.length);
      final batchIndexes = scheduleIndexes.sublist(start, end);
      final batchResults = await Future.wait(
        batchIndexes.map(/* 함수이름: map 콜백
         * 함수역할: 일정별 약 상세 조회를 실행하고 일치·미일치·실패를 원래 인덱스와 함께 결과로 묶는다.
         * 매개변수:
         * - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
         * 반환값:
         * - 해당 일정의 상세 조회 결과를 완료하는 Future.
         */(scheduleIndex) async {
          final schedule = schedules[scheduleIndex];
          try {
            final detail = await checkMedicationDetail.requestMedicationDetail(
              schedule,
            );
            if (detail == null) {
              return _MedicationLookupResult.unmatched(scheduleIndex);
            }
            return _MedicationLookupResult.matched(
              scheduleIndex,
              AnalyzedMedication(schedule: schedule, detail: detail),
            );
          } catch (error) {
            return _MedicationLookupResult.failed(
              scheduleIndex,
              UserFacingErrorMessage.resolve(
                error,
                isEnglish: _isEnglishSetting,
                context: UserFacingErrorContext.medicationLookup,
              ),
            );
          }
        }),
      );
      for (final result in batchResults) {
        if (result.analyzedMedication != null) {
          analyzedMedicationByScheduleIndex[result.scheduleIndex] =
              result.analyzedMedication!;
        } else if (result.errorMessage.isNotEmpty) {
          errorMessagesByScheduleIndex[result.scheduleIndex] =
              result.errorMessage;
        } else {
          unmatchedScheduleIndexes.add(result.scheduleIndex);
        }
      }
    }
    return _MedicationAnalysisBatch(
      analyzedMedicationByScheduleIndex: analyzedMedicationByScheduleIndex,
      unmatchedScheduleIndexes: unmatchedScheduleIndexes,
      errorMessagesByScheduleIndex: errorMessagesByScheduleIndex,
    );
  }

  // 함수이름: continueWithVerifiedMedicationAnalysis
  // 함수역할: 사용자가 미확인 약 제외를 명시적으로 확인한 경우에만 확인된 약으로 결과 화면을 진행한다. 자동으로 누락시키지 않고 재검토 화면의 선택을 거쳐 데이터 손실을 알 수 있게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 확인된 약이 한 개 이상이면 true, 아니면 false
  bool continueWithVerifiedMedicationAnalysis() {
    if (_prescriptionFlowState !=
            PrescriptionFlowState.medicationReviewRequired ||
        _analyzedMedicationByScheduleIndex.isEmpty) {
      return false;
    }

    final excludedCount = _unverifiedMedicationScheduleIndexes.length;
    _analyzedMedicationList = _orderedAnalyzedMedications();
    _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
    _statusMessage = _isEnglishSetting
        ? 'Continuing with verified medications. $excludedCount unverified item(s) were excluded.'
        : '확인된 약으로 계속합니다. 미확인 약 $excludedCount개는 결과에서 제외했습니다.';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
    return true;
  }

  // 함수이름: _orderedAnalyzedMedications
  // 함수역할: 성공한 분석 결과를 원래 OCR 행 인덱스 순으로 정렬해 화면 목록으로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - List<AnalyzedMedication>: 성공한 분석 결과를 원래 OCR 행 인덱스 순으로 정렬해 화면 목록으로 제공한다.
  List<AnalyzedMedication> _orderedAnalyzedMedications() {
    final entries = _analyzedMedicationByScheduleIndex.entries.toList()
      ..sort(/* 함수이름: sort 콜백
       * 함수역할: 조회 완료 순서와 무관하게 원래 일정 인덱스 오름차순으로 결과를 정렬한다.
       * 매개변수:
       * - left (MapEntry<int, AnalyzedMedication>): 정렬 비교의 첫 번째 일정 인덱스 항목
       * - right (MapEntry<int, AnalyzedMedication>): 정렬 비교의 두 번째 일정 인덱스 항목
       * 반환값:
       * - 원래 인덱스의 음수·0·양수 비교값.
       */(left, right) => left.key.compareTo(right.key));
    return entries.map(/* 함수이름: map 콜백
     * 함수역할: 인덱스 순으로 정렬된 결과에서 분석 약 정보만 꺼낸다.
     * 매개변수:
     * - entry (MapEntry<int, AnalyzedMedication>): 처리 중인 맵의 키·값 항목
     * 반환값:
     * - 해당 인덱스의 분석 약 정보.
     */(entry) => entry.value).toList(growable: false);
  }

  // 함수이름: _refreshPrescriptionChangeRadar
  // 함수역할: 결과 화면을 막지 않고 현재 처방과 이전 처방의 비교 결과를 요청한다. 사용자가 화면을 벗어난 뒤 도착한 응답은 현재 상태에 반영하지 않는다.
  // 매개변수:
  // - operationId (int): 요청 시작 시점의 처방 작업 식별자
  // - medications (List<AnalyzedMedication>): 공공데이터 상세조회가 끝난 현재 처방 목록
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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

  // 함수이름: showMedicationAnalysisResult
  // 함수역할: 분석 성공 화면에서 실제 결과 목록 화면으로 이동할 수 있도록 상태를 변경한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void showMedicationAnalysisResult() {
    if (_analyzedMedicationList.isEmpty) {
      _showAnalysisFailure(
        _isEnglishSetting
            ? 'No analysis result is available.'
            : '확인할 분석 결과가 없습니다.',
      );
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

  // 함수이름: requestMedicationSave
  // 함수역할: 이미 분석된 약 상세 정보를 저장 목록에 저장한다.
  // 매개변수:
  // - analyzedMedication (AnalyzedMedication): OCR 스케줄과 상세 정보가 결합된 분석 결과
  // - medicationIndex (int): 저장 버튼 로딩 표시를 위한 화면상 인덱스
  // 반환값:
  // - 저장 성공 여부
  Future<bool> requestMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) async {
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = _isEnglishSetting
          ? 'Another medication is being saved.'
          : '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }
    if (_completedMedicationSaveIndexes.contains(medicationIndex)) {
      _statusMessage = _isEnglishSetting
          ? 'This medication is already saved.'
          : '이미 추가된 약입니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return true;
    }

    _statusMessage = _isEnglishSetting
        ? 'Saving ${analyzedMedication.displayName}...'
        : '${analyzedMedication.displayName} 저장 중...';
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

  // 함수이름: requestAllAnalyzedMedicationSave
  // 함수역할: 완료 항목은 재저장하지 않고 나머지 분석 약을 순차 저장한 뒤 목록·일정·알림을 한 번 갱신하며 저장·중복·실패 개수를 안내한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 완료 항목은 재저장하지 않고 나머지 분석 약을 순차 저장한 뒤 목록·일정·알림을 한 번 갱신하며 저장·중복·실패 개수를 안내한다.
  Future<bool> requestAllAnalyzedMedicationSave() async {
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = _isEnglishSetting
          ? 'Another medication is being saved.'
          : '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }
    if (_analyzedMedicationList.isEmpty) {
      _statusMessage = _isEnglishSetting
          ? 'There are no analysis results to save.'
          : '저장할 분석 결과가 없습니다.';
      _notifyViewModelListeners(MedBuddyFeature.prescription);
      return false;
    }

    _isAllMedicationSaving = true;
    _statusMessage = _isEnglishSetting
        ? 'Saving all medication schedules...'
        : '전체 복약 일정을 저장 중입니다...';
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

  // 함수이름: _requestPrescriptionRecognition
  // 함수역할: 카메라/갤러리 공통 처방전 OCR 흐름을 상태 머신 형태로 처리한다. 사용자가 선택을 취소하면 분석 화면으로 넘어가지 않도록 idle 상태로 되돌린다.
  // 매개변수:
  // - imageRequest (Future<List<MedicationSchedule>?> Function({VoidCallback? onImageSelected})): 이미지 선택과 OCR 요청을 수행하는 함수
  // - cancelledMessage (String): 사용자가 취소했을 때 보여줄 상태 메시지
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
    _analyzedMedicationByScheduleIndex.clear();
    _unverifiedMedicationScheduleIndexes.clear();
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;

    try {
      final result = await imageRequest(
        onImageSelected: /* 함수이름: onImageSelected 콜백
         * 함수역할: 현재 처방 작업이 유지될 때 선택 이미지 미리보기를 갱신하고 문자 인식 진행 상태를 표시한다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */() {
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
        _showAnalysisFailure(
          _isEnglishSetting
              ? 'No medication information was found in the prescription.'
              : '처방전에서 약 정보를 찾지 못했습니다.',
        );
        return;
      }

      _recognizedMedicationScheduleList = result;
      _recognizedTextRegionList = inputPrescription.lastRecognizedTextRegions;
      _recordPrescriptionRecognitionCounts(result);
      _prescriptionFlowState = PrescriptionFlowState.previewReady;
      _statusMessage = prescriptionRecognitionNotice.isEmpty
          ? (_isEnglishSetting
                ? 'Prescription recognition completed.'
                : '처방전 인식이 완료되었습니다.')
          : (_isEnglishSetting
                ? 'Prescription recognition completed. Review the recognized information.'
                : '처방전 인식이 완료되었습니다. 인식 내역을 확인해주세요.');
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

  // 함수이름: _beginPrescriptionOperation
  // 함수역할: 새 처방 작업의 세대 번호를 증가시켜 이후 응답의 유효성을 판정할 식별자로 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - int: 새 처방 작업의 세대 번호를 증가시켜 이후 응답의 유효성을 판정할 식별자로 제공한다.
  int _beginPrescriptionOperation() {
    _prescriptionOperationId += 1;
    return _prescriptionOperationId;
  }

  // 함수이름: _cancelPrescriptionOperation
  // 함수역할: 처방 작업 세대를 증가시켜 이미 진행 중인 요청의 늦은 응답을 무효화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _cancelPrescriptionOperation() {
    _prescriptionOperationId += 1;
  }

  // 함수이름: _isCurrentPrescriptionOperation
  // 함수역할: 응답이 시작된 처방 작업과 현재 작업의 세대 번호가 같은지 확인한다.
  // 매개변수:
  // - operationId (int): 이전 비동기 응답을 차단할 현재 작업 세대
  // 반환값:
  // - bool: 응답이 시작된 처방 작업과 현재 작업의 세대 번호가 같은지 확인한다.
  bool _isCurrentPrescriptionOperation(int operationId) {
    return _prescriptionOperationId == operationId;
  }

  // 함수이름: _showPrescriptionRecognitionProgress
  // 함수역할: 실제 이미지 선택 뒤 인식 단계·로딩 상태와 언어별 안내를 설정하고 처방전 화면에 알린다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = _isEnglishSetting
        ? 'Recognizing the prescription...'
        : '처방전을 인식 중입니다...';
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: _clearPrescriptionRecognitionCounts
  // 함수역할: 새 처방 흐름을 위해 원시·파싱·제외 OCR 항목 수를 모두 0으로 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void _clearPrescriptionRecognitionCounts() {
    _lastPrescriptionRawMedicationCount = 0;
    _lastPrescriptionParsedMedicationCount = 0;
    _lastPrescriptionSkippedMedicationCount = 0;
  }

  // 함수이름: _recordPrescriptionRecognitionCounts
  // 함수역할: 입력 Control의 파싱 통계를 우선하고 없으면 일정 개수와 차이로 보완해 음수가 아닌 OCR 개수를 기록한다.
  // 매개변수:
  // - schedules (List<MedicationSchedule>): 조회·비교·예약에 사용할 복약 일정 목록
  // 반환값:
  // - 없음.
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

  // 함수이름: _showAnalysisFailure
  // 함수역할: 분석 오류와 상태 안내를 같은 메시지로 기록하고 실패 화면 상태로 전환한다.
  // 매개변수:
  // - message (String): 사용자에게 표시하거나 오류로 보존할 안내 문구
  // 반환값:
  // - 없음.
  void _showAnalysisFailure(String message) {
    _analysisErrorMessage = message;
    _statusMessage = message;
    _prescriptionFlowState = PrescriptionFlowState.analysisFailed;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: _setSavingMedicationIndex
  // 함수역할: 저장 중인 분석 목록 인덱스를 설정하거나 해제하고 처방전 화면의 저장 버튼 상태를 갱신한다.
  // 매개변수:
  // - value (int?): 현재 저장 중인 약의 원래 인덱스; null은 저장 진행 표시 해제
  // 반환값:
  // - 없음.
  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    _notifyViewModelListeners(MedBuddyFeature.prescription);
  }

  // 함수이름: _buildBulkSaveMessage
  // 함수역할: 양수인 저장·중복·실패 개수만 현재 언어로 조합하고 집계가 없으면 이미 저장된 항목이라는 안내를 제공한다.
  // 매개변수:
  // - savedCount (int): 정상 저장 또는 삭제된 항목 수
  // - duplicateCount (int): 이미 저장되어 중복으로 처리한 항목 수
  // - failedCount (int): 처리에 실패한 항목 수
  // 반환값:
  // - String: 양수인 저장·중복·실패 개수만 현재 언어로 조합하고 집계가 없으면 이미 저장된 항목이라는 안내를 제공한다.
  String _buildBulkSaveMessage({
    required int savedCount,
    required int duplicateCount,
    required int failedCount,
  }) {
    final parts = <String>[];
    if (savedCount > 0) {
      parts.add(_isEnglishSetting ? '$savedCount saved' : '$savedCount개 저장');
    }
    if (duplicateCount > 0) {
      parts.add(
        _isEnglishSetting ? '$duplicateCount duplicate' : '$duplicateCount개 중복',
      );
    }
    if (failedCount > 0) {
      parts.add(_isEnglishSetting ? '$failedCount failed' : '$failedCount개 실패');
    }
    if (parts.isEmpty) {
      return _isEnglishSetting
          ? 'These medications are already saved.'
          : '이미 추가된 약입니다.';
    }
    return _isEnglishSetting
        ? 'Save complete: ${parts.join(', ')}'
        : '전체 저장 완료: ${parts.join(', ')}';
  }

  // Function Name: _slotKeysForSchedule
  // Description: Prefers explicit slots, then known daily frequency, then supported status-map keys, and finally the entity's default slot interpretation.
  // Parameters:
  // - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
  // Returns:
  // - List<String>: Prefers explicit slots, then known daily frequency, then supported status-map keys, and finally the entity's default slot interpretation.
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
          .where(/* 함수이름: where 콜백
           * 함수역할: 일정에 실제 상태 기록이 있는 시간대만 선택한다.
           * 매개변수:
           * - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
           * 반환값:
           * - 상태 맵에 해당 시간대 키가 있으면 true.
           */(slotKey) => schedule.slotStatuses.containsKey(slotKey))
          .toList(growable: false);
      if (slotKeys.isNotEmpty) {
        return slotKeys;
      }
    }
    return schedule.slotKeys;
  }
}

// 클래스명: _MedicationLookupResult
// 역할: 한 OCR 행의 상세조회 성공·미일치·기술 실패를 구분한다.
// 주요 책임:
// - 원래 행 인덱스를 분석 결과 또는 오류 안내와 함께 보존해 선택 재조회에 사용한다.
// 속성:
// - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
// - analyzedMedication (AnalyzedMedication?): OCR 일정과 상세정보가 결합된 분석 결과
// - errorMessage (String): 실패 상태에 사용할 사용자 안내문
class _MedicationLookupResult {
  final int scheduleIndex;
  final AnalyzedMedication? analyzedMedication;
  final String errorMessage;

  // 함수이름: _MedicationLookupResult._
  // 함수역할: OCR 행 인덱스와 선택적 분석 결과·오류 메시지를 조회 결과 내부 상태로 묶는다.
  // 매개변수:
  // - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
  // - analyzedMedication (AnalyzedMedication?): OCR 일정과 상세정보가 결합된 분석 결과
  // - errorMessage (String): 실패 상태에 사용할 사용자 안내문
  // 반환값:
  // - _MedicationLookupResult: 초기화된 인스턴스.
  const _MedicationLookupResult._({
    required this.scheduleIndex,
    this.analyzedMedication,
    this.errorMessage = '',
  });

  // 함수이름: _MedicationLookupResult.matched
  // 함수역할: OCR 행과 공공데이터 상세 정보가 연결된 조회 성공 결과를 만든다.
  // 매개변수:
  // - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
  // - analyzedMedication (AnalyzedMedication): OCR 일정과 상세정보가 결합된 분석 결과
  // 반환값:
  // - _MedicationLookupResult: 초기화된 인스턴스.
  factory _MedicationLookupResult.matched(
    int scheduleIndex,
    AnalyzedMedication analyzedMedication,
  ) {
    return _MedicationLookupResult._(
      scheduleIndex: scheduleIndex,
      analyzedMedication: analyzedMedication,
    );
  }

  // 함수이름: _MedicationLookupResult.unmatched
  // 함수역할: 기술 오류 없이 일치하는 약 상세정보를 찾지 못한 OCR 행을 기록한다.
  // 매개변수:
  // - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
  // 반환값:
  // - _MedicationLookupResult: 초기화된 인스턴스.
  factory _MedicationLookupResult.unmatched(int scheduleIndex) {
    return _MedicationLookupResult._(scheduleIndex: scheduleIndex);
  }

  // 함수이름: _MedicationLookupResult.failed
  // 함수역할: 일시적 조회 오류가 난 OCR 행과 화면에 보여줄 오류 안내를 함께 기록한다.
  // 매개변수:
  // - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
  // - errorMessage (String): 실패 상태에 사용할 사용자 안내문
  // 반환값:
  // - _MedicationLookupResult: 초기화된 인스턴스.
  factory _MedicationLookupResult.failed(
    int scheduleIndex,
    String errorMessage,
  ) {
    return _MedicationLookupResult._(
      scheduleIndex: scheduleIndex,
      errorMessage: errorMessage,
    );
  }
}

// 클래스명: _MedicationAnalysisBatch
// 역할: 병렬 약품 조회 결과를 원래 OCR 행 인덱스별로 보관한다.
// 주요 책임:
// - 성공 결과·미일치 행·기술 오류를 분리하고 재검토가 필요한 인덱스 합집합을 제공한다.
// 속성:
// - analyzedMedicationByScheduleIndex (Map<int, AnalyzedMedication>): 원래 OCR 행 인덱스별 분석 성공 결과
// - unmatchedScheduleIndexes (Set<int>): 상세 조회에서 일치 약을 찾지 못한 OCR 행
// - errorMessagesByScheduleIndex (Map<int, String>): 원래 OCR 행별 기술 오류 안내
class _MedicationAnalysisBatch {
  final Map<int, AnalyzedMedication> analyzedMedicationByScheduleIndex;
  final Set<int> unmatchedScheduleIndexes;
  final Map<int, String> errorMessagesByScheduleIndex;

  // 함수이름: _MedicationAnalysisBatch
  // 함수역할: 인덱스별 분석 성공 결과와 미일치 행 및 오류 메시지를 하나의 조회 묶음으로 보존한다.
  // 매개변수:
  // - analyzedMedicationByScheduleIndex (Map<int, AnalyzedMedication>): 원래 OCR 행 인덱스별 분석 성공 결과
  // - unmatchedScheduleIndexes (Set<int>): 상세 조회에서 일치 약을 찾지 못한 OCR 행
  // - errorMessagesByScheduleIndex (Map<int, String>): 원래 OCR 행별 기술 오류 안내
  // 반환값:
  // - _MedicationAnalysisBatch: 초기화된 인스턴스.
  const _MedicationAnalysisBatch({
    required this.analyzedMedicationByScheduleIndex,
    required this.unmatchedScheduleIndexes,
    required this.errorMessagesByScheduleIndex,
  });

  // 함수이름: unverifiedScheduleIndexes
  // 함수역할: 일치하지 않은 행과 기술 오류가 난 행의 인덱스를 합쳐 재검토 대상을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Set<int>: 일치하지 않은 행과 기술 오류가 난 행의 인덱스를 합쳐 재검토 대상을 제공한다.
  Set<int> get unverifiedScheduleIndexes => {
    ...unmatchedScheduleIndexes,
    ...errorMessagesByScheduleIndex.keys,
  };
}
