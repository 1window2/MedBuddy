import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../controls/input_prescription_control.dart';
import '../controls/check_medication_detail_control.dart';
import '../controls/check_prescription_change_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../entities/analyzed_medication_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_match_review_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/prescription_flow_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/recognized_text_region_entity.dart';
import '../services/user_facing_error_message.dart';
import 'medbuddy_saved_medication_view_model.dart';

// 파일명: medbuddy_prescription_view_model.dart
// 역할: 처방전 선택, OCR 검토, 약품 분석, 저장 요청 준비 상태를 관리한다.

// Class Name: MedBuddyPrescriptionViewModel
// Role: Owns prescription recognition, review, analysis and save progress.
// Responsibilities: Preserve OCR/user edits, reject obsolete operation results and coordinate candidate review and partial saves.
// Attributes: Flow/progress fields select screens; source rows/regions retain OCR; index maps retain lookup results; injected controls and callbacks perform persistence and refreshes.
class MedBuddyPrescriptionViewModel {
  PrescriptionFlowState _prescriptionFlowState = PrescriptionFlowState.idle;
  // Function Name: prescriptionFlowState
  // Description: Exposes the current input, recognition, review, analysis or result screen state.
  // Parameters: None.
  // Returns: The current PrescriptionFlowState.
  PrescriptionFlowState get prescriptionFlowState => _prescriptionFlowState;
  int _prescriptionOperationId = 0;
  // 갤러리 선택 창이 열려 있어 아직 이미지를 고르지 않은 요청이 있는지 여부.
  bool _isPrescriptionImagePickPending = false;
  AnalysisProgressStep _analysisProgressStep =
      AnalysisProgressStep.prescriptionRecognition;
  // Function Name: analysisProgressStep
  // Description: Exposes the high-level recognition or medication-analysis progress step.
  // Parameters: None.
  // Returns: The current AnalysisProgressStep.
  AnalysisProgressStep get analysisProgressStep => _analysisProgressStep;
  int _completedMedicationAnalysisCount = 0;
  int _totalMedicationAnalysisCount = 0;
  // 함수이름: completedMedicationAnalysisCount
  // 함수역할: 현재 약품 분석 작업에서 완료 처리한 항목 수를 제공한다.
  // 매개변수: 없음.
  // 반환값: 완료된 대상 건수; 성공 여부와는 별개의 진행 수치.
  int get completedMedicationAnalysisCount => _completedMedicationAnalysisCount;
  // 함수이름: totalMedicationAnalysisCount
  // 함수역할: 현재 약품 분석 진행 표시의 전체 대상 수를 제공한다.
  // 매개변수: 없음.
  // 반환값: 이번 분석의 대상 건수.
  int get totalMedicationAnalysisCount => _totalMedicationAnalysisCount;
  // Function Name: isPrescriptionAnalyzing
  // Description: Checks whether the workflow is recognizing an image or analyzing medications.
  // Parameters: None.
  // Returns: True for those two active processing states.
  bool get isPrescriptionAnalyzing {
    return _prescriptionFlowState ==
            PrescriptionFlowState.recognizingPrescription ||
        _prescriptionFlowState == PrescriptionFlowState.analyzingMedication;
  }

  // Function Name: isLoading
  // Description: Provides the compatibility loading flag for prescription processing.
  // Parameters: None.
  // Returns: The same value as isPrescriptionAnalyzing.
  bool get isLoading => isPrescriptionAnalyzing;
  int? _savingMedicationIndex;
  // Function Name: savingMedicationIndex
  // Description: Exposes the analysis-list index currently being saved, or null when no individual save is running.
  // Parameters:
  // - None.
  // Returns:
  // - int?: The analysis-list index currently being saved, or null when no individual save is running.
  int? get savingMedicationIndex => _savingMedicationIndex;
  // Function Name: isMedicationSaving
  // Description: Reports whether an individual medication save has an active list index.
  // Parameters:
  // - None.
  // Returns:
  // - bool: Whether an individual medication save has an active list index.
  bool get isMedicationSaving => _savingMedicationIndex != null;
  final Set<int> _completedMedicationSaveIndexes = {};
  // Function Name: completedMedicationSaveIndexes
  // Description: Exposes analyzed-list indexes already saved or confirmed as duplicates.
  // Parameters: None.
  // Returns: An unmodifiable copy of completed-save indexes.
  Set<int> get completedMedicationSaveIndexes =>
      Set.unmodifiable(_completedMedicationSaveIndexes);
  bool _isAllMedicationSaving = false;
  // Function Name: isAllMedicationSaving
  // Description: Reports whether the batch save of analyzed medications is in progress.
  // Parameters: None.
  // Returns: The batch-save flag.
  bool get isAllMedicationSaving => _isAllMedicationSaving;
  String _analysisErrorMessage = '';
  // Function Name: analysisErrorMessage
  // Description: Exposes the most recent recognition or analysis failure guidance.
  // Parameters: None.
  // Returns: The retained analysis error text, possibly empty.
  String get analysisErrorMessage => _analysisErrorMessage;
  // Function Name: canRetryPrescriptionAnalysis
  // Description: Allows retry only when recognized rows remain after medication-analysis failure or review.
  // Parameters: None.
  // Returns: False during recognition-stage failure or without recognized rows; otherwise true for eligible retry states.
  bool get canRetryPrescriptionAnalysis =>
      (_prescriptionFlowState == PrescriptionFlowState.analysisFailed ||
          _prescriptionFlowState ==
              PrescriptionFlowState.medicationReviewRequired) &&
      _analysisProgressStep != AnalysisProgressStep.prescriptionRecognition &&
      _recognizedMedicationScheduleList.isNotEmpty;
  int _lastPrescriptionRawMedicationCount = 0;
  int _lastPrescriptionParsedMedicationCount = 0;
  int _lastPrescriptionSkippedMedicationCount = 0;
  // Function Name: lastPrescriptionRawMedicationCount
  // Description: Exposes the latest raw OCR medication count before parsing exclusions.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest raw OCR medication count before parsing exclusions.
  int get lastPrescriptionRawMedicationCount =>
      _lastPrescriptionRawMedicationCount;
  // Function Name: lastPrescriptionParsedMedicationCount
  // Description: Exposes the latest count of usable parsed prescription entries.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest count of usable parsed prescription entries.
  int get lastPrescriptionParsedMedicationCount =>
      _lastPrescriptionParsedMedicationCount;
  // Function Name: lastPrescriptionSkippedMedicationCount
  // Description: Exposes the latest number of excluded OCR entries for the review notice.
  // Parameters:
  // - None.
  // Returns:
  // - int: The latest number of excluded OCR entries for the review notice.
  int get lastPrescriptionSkippedMedicationCount =>
      _lastPrescriptionSkippedMedicationCount;
  // Function Name: correctedPrescriptionMedicationCount
  // Description: Counts recognized medication entries with recorded name corrections.
  // Parameters:
  // - None.
  // Returns:
  // - int: Counts recognized medication entries with recorded name corrections.
  int get correctedPrescriptionMedicationCount {
    return _recognizedMedicationScheduleList
        .where(
          /* Function Name: where callback
         * Description: Selects prescription schedules whose recognized medication name has been corrected.
         * Parameters:
         * - schedule (MedicationSchedule): Medication course with name, dose, duration, and slots.
         * Returns:
         * - Whether this schedule has a name correction.
         */
          (schedule) => schedule.hasNameCorrection,
        )
        .length;
  }

  // Function Name: prescriptionRecognitionNotice
  // Description: Builds a localized OCR review notice for corrected names and skipped OCR entries, returning blank when neither occurred.
  // Parameters:
  // - None.
  // Returns:
  // - String: Builds a localized OCR review notice for corrected names and skipped OCR entries, returning blank when neither occurred.
  String get prescriptionRecognitionNotice {
    final correctedCount = correctedPrescriptionMedicationCount;
    final skippedCount = _lastPrescriptionSkippedMedicationCount;
    if (correctedCount <= 0 && skippedCount <= 0) {
      return '';
    }

    final parts = <String>[];
    if (correctedCount > 0) {
      parts.add(
        _isEnglishSetting
            ? '$correctedCount name correction'
            : '$correctedCount개 약명 보정',
      );
    }
    if (skippedCount > 0) {
      parts.add(
        _isEnglishSetting
            ? '$skippedCount OCR item skipped'
            : '$skippedCount개 OCR 항목 제외',
      );
    }

    return _isEnglishSetting
        ? '${parts.join(' · ')}. Please review.'
        : '${parts.join(' · ')} 내역을 확인해주세요.';
  }

  List<MedicationSchedule> _recognizedMedicationScheduleList = [];
  // Function Name: recognizedMedicationScheduleList
  // Description: Exposes the OCR medication rows currently under user review.
  // Parameters: None.
  // Returns: An unmodifiable list of recognized schedules.
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      List.unmodifiable(_recognizedMedicationScheduleList);
  List<RecognizedTextRegion> _recognizedTextRegionList = [];
  // Function Name: recognizedTextRegionList
  // Description: Exposes text and sensitive-information regions used by the current preview.
  // Parameters: None.
  // Returns: An unmodifiable region list.
  List<RecognizedTextRegion> get recognizedTextRegionList =>
      List.unmodifiable(_recognizedTextRegionList);
  String _prescriptionPreviewImagePath = '';
  // Function Name: prescriptionPreviewImagePath
  // Description: Provides the local image path for prescription review.
  // Parameters: None.
  // Returns: The current preview path, or an empty string without a selected preview.
  String get prescriptionPreviewImagePath => _prescriptionPreviewImagePath;
  // Function Name: medicationScheduleList
  // Description: Provides the legacy schedule accessor for recognized prescription rows.
  // Parameters: None.
  // Returns: The same read-only row list as recognizedMedicationScheduleList.
  List<MedicationSchedule> get medicationScheduleList =>
      recognizedMedicationScheduleList;
  List<AnalyzedMedication> _analyzedMedicationList = [];
  // Function Name: analyzedMedicationList
  // Description: Exposes successful detail analyses in their retained prescription order.
  // Parameters: None.
  // Returns: An unmodifiable analysis-result list.
  List<AnalyzedMedication> get analyzedMedicationList =>
      List.unmodifiable(_analyzedMedicationList);
  // 상세조회가 끝난 약은 원래 OCR 행 인덱스와 함께 보존해 재조회 시 중복 호출을 막는다.
  final Map<int, AnalyzedMedication> _analyzedMedicationByScheduleIndex = {};
  final Set<int> _unverifiedMedicationScheduleIndexes = {};
  final Map<int, MedicationMatchReview> _medicationMatchReviews = {};
  final Map<int, MedicationLookupStatus> _medicationLookupStatuses = {};
  PrescriptionRecognitionStage _recognitionStage =
      PrescriptionRecognitionStage.recognizingText;
  // 함수이름: recognitionStage
  // 함수역할: 문자 인식과 약품 구조화를 구분하는 실제 처리 단계를 제공한다.
  // 매개변수: 없음.
  // 반환값: 현재 PrescriptionRecognitionStage.
  PrescriptionRecognitionStage get recognitionStage => _recognitionStage;
  // 함수이름: medicationLookupStatuses
  // 함수역할: 원래 처방전 행 인덱스별 약품 조회 상태를 제공한다.
  // 매개변수: 없음.
  // 반환값: 수정 불가 조회 상태 맵.
  Map<int, MedicationLookupStatus> get medicationLookupStatuses =>
      Map.unmodifiable(_medicationLookupStatuses);
  // 함수이름: medicationMatchReviews
  // 함수역할: 사용자 후보 확인이 필요한 처방전 행의 검토 정보를 제공한다.
  // 매개변수: 없음.
  // 반환값: 원래 행 인덱스별 수정 불가 검토 맵.
  Map<int, MedicationMatchReview> get medicationMatchReviews =>
      Map.unmodifiable(_medicationMatchReviews);
  // Function Name: verifiedMedicationScheduleIndexes
  // Description: Exposes original OCR-row indexes with confirmed detail-analysis results.
  // Parameters: None.
  // Returns: An unmodifiable set of keys from the analysis-result map.
  Set<int> get verifiedMedicationScheduleIndexes =>
      Set.unmodifiable(_analyzedMedicationByScheduleIndex.keys.toSet());
  // Function Name: unverifiedMedicationScheduleIndexes
  // Description: Exposes OCR-row indexes still requiring review or another lookup.
  // Parameters: None.
  // Returns: An unmodifiable set of unverified row indexes.
  Set<int> get unverifiedMedicationScheduleIndexes =>
      Set.unmodifiable(_unverifiedMedicationScheduleIndexes);
  PrescriptionChangeRadar? _prescriptionChangeRadar;
  // Function Name: prescriptionChangeRadar
  // Description: Exposes the comparison between the current and previous prescription.
  // Parameters: None.
  // Returns: The latest radar, or null when unavailable.
  PrescriptionChangeRadar? get prescriptionChangeRadar =>
      _prescriptionChangeRadar;
  bool _isPrescriptionChangeLoading = false;
  // Function Name: isPrescriptionChangeLoading
  // Description: Reports a prescription-comparison request running behind the result view.
  // Parameters: None.
  // Returns: The comparison-loading flag.
  bool get isPrescriptionChangeLoading => _isPrescriptionChangeLoading;
  final InputPrescription inputPrescription;
  final CheckMedicationDetail checkMedicationDetail;
  final CheckPrescriptionChange checkPrescriptionChange;
  final MedBuddySavedMedicationViewModel savedMedications;
  final Future<void> Function() fetchTodayMedicationSchedule;
  final Future<void> Function()
  _synchronizeMedicationReminderSchedulesIfScheduleIsFresh;
  final bool Function() _readEnglish;
  final void Function(String) _onChanged;
  bool _disposed = false;
  String _statusMessage = '';
  // Function Name: MedBuddyPrescriptionViewModel
  // Description: Bind borrowed prescription controls and save/refresh dependencies without starting analysis.
  // Parameters: inputPrescription (InputPrescription): image/OCR input; checkMedicationDetail (CheckMedicationDetail): catalog lookup; checkPrescriptionChange (CheckPrescriptionChange): prior-prescription comparison; savedMedications (MedBuddySavedMedicationViewModel): save owner; fetchTodayMedicationSchedule (Future<void> Function()): schedule refresh; synchronizeReminders (Future<void> Function()): reminder refresh; readEnglish (bool Function()): locale; onChanged (void Function(String)): feature update callback.
  // Returns: MedBuddyPrescriptionViewModel: independent prescription state owner.
  MedBuddyPrescriptionViewModel({
    required this.inputPrescription,
    required this.checkMedicationDetail,
    required this.checkPrescriptionChange,
    required this.savedMedications,
    required this.fetchTodayMedicationSchedule,
    required Future<void> Function() synchronizeReminders,
    required bool Function() readEnglish,
    required void Function(String) onChanged,
  }) : _synchronizeMedicationReminderSchedulesIfScheduleIsFresh =
           synchronizeReminders,
       _readEnglish = readEnglish,
       _onChanged = onChanged;
  // Function Name: _isEnglishSetting
  // Description: Reads current locale. Parameters: None. Returns: English selection.
  bool get _isEnglishSetting => _readEnglish();
  // Function Name: statusMessage
  // Description: Exposes prescription-only feedback. Parameters: None. Returns: Feedback.
  String get statusMessage => _statusMessage;
  // Function Name: idlePrompt
  // Description: Provides the localized prompt while waiting for a prescription image.
  // Parameters: None.
  // Returns: English or Korean capture/gallery guidance.
  String get idlePrompt => _isEnglishSetting
      ? 'Take a prescription photo or choose an image.'
      : '처방전을 촬영하거나 이미지를 선택해주세요.';
  // Function Name: _notifyViewModelListeners
  // Description: Publishes live prescription state. Parameters: None. Returns: None.
  void _notifyViewModelListeners() {
    if (!_disposed) _onChanged(_statusMessage);
  }

  // Function Name: dispose
  // Description: Invalidates pending responses without disposing borrowed controls.
  // Parameters: None. Returns: None.
  void dispose() {
    _disposed = true;
    _cancelPrescriptionOperation();
  }

  // Function Name: clearAnalysisResult
  // Description: Invalidates current work, clears recognition/save state and returns to image input.
  // Parameters: None.
  // Returns: None; request cancellation is immediate and selected-image cleanup is asynchronous.
  void clearAnalysisResult() {
    _cancelPrescriptionOperation();
    inputPrescription.cancelPendingRequests();
    unawaited(inputPrescription.clearSelectedImage());
    _resetPrescriptionRecognitionState();
    _prescriptionFlowState = PrescriptionFlowState.idle;
    _statusMessage = idlePrompt;
    _notifyViewModelListeners();
  }

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
       */ ({onImageSelected, onProgress}) {
        return inputPrescription.requestCapturedPrescriptionImage(
          image,
          onImageSelected: onImageSelected,
          onProgress: onProgress,
        );
      },
      cancelledMessage: _isEnglishSetting
          ? 'Photo capture was canceled.'
          : '사진 촬영이 취소되었습니다.',
    );
  }

  // Function Name: requestPrescriptionImageFromGallery
  // Description: Starts gallery-based recognition, preserving the prior preview until an image is actually selected.
  // Parameters: None.
  // Returns: Completion of the recognition workflow including its cancellation feedback.
  Future<void> requestPrescriptionImageFromGallery() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImageFromGallery,
      cancelledMessage: _isEnglishSetting
          ? 'Image selection was canceled.'
          : '이미지 선택이 취소되었습니다.',
      resetAfterImageSelection: true,
    );
  }

  // Function Name: updateRecognizedMedicationSchedule
  // Description: Applies a user-edited OCR row, preserving original-name provenance and invalidating affected analysis/save state.
  // Parameters: scheduleIndex: Original row index; medicationSchedule: Replacement values.
  // Returns: None; invalid state/index or blank names are ignored, and edited review rows return to pending verification.
  void updateRecognizedMedicationSchedule(
    int scheduleIndex,
    MedicationSchedule medicationSchedule,
  ) {
    final isReviewState =
        _prescriptionFlowState ==
            PrescriptionFlowState.medicationReviewRequired ||
        _prescriptionFlowState == PrescriptionFlowState.analysisSucceeded;
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
          : {
              'user_edit',
              'manual_add',
              'user_selection',
            }.contains(currentSchedule.nameCorrectionSource)
          ? currentSchedule.nameCorrectionSource
          : 'user_review',
    );

    final updatedScheduleList = List<MedicationSchedule>.of(
      _recognizedMedicationScheduleList,
    );
    updatedScheduleList[scheduleIndex] = normalizedSchedule;
    _recognizedMedicationScheduleList = updatedScheduleList;
    _medicationMatchReviews.remove(scheduleIndex);
    if (isReviewState) {
      // 조회 전 미리보기에는 조회 상태가 없으므로 검토 중 수정한 행만 다시 조회 대상으로 표시한다.
      _medicationLookupStatuses[scheduleIndex] = MedicationLookupStatus.pending;
      _analyzedMedicationByScheduleIndex.remove(scheduleIndex);
      _unverifiedMedicationScheduleIndexes.add(scheduleIndex);
      _analyzedMedicationList = _orderedAnalyzedMedications();
      _prescriptionFlowState = PrescriptionFlowState.medicationReviewRequired;
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
    _notifyViewModelListeners();
  }

  // Function Name: addRecognizedMedicationSchedule
  // Description: Adds a manually entered row during preview/review and includes it in subsequent verification.
  // Parameters: medicationSchedule: User-entered name and regimen.
  // Returns: None; invalid workflow states or blank names are ignored, and accepted rows update parse counts and clear obsolete comparison/save state.
  void addRecognizedMedicationSchedule(MedicationSchedule medicationSchedule) {
    final isReviewState =
        _prescriptionFlowState ==
            PrescriptionFlowState.medicationReviewRequired ||
        _prescriptionFlowState == PrescriptionFlowState.analysisSucceeded;
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
      _medicationLookupStatuses[addedIndex] = MedicationLookupStatus.pending;
      _unverifiedMedicationScheduleIndexes.add(addedIndex);
      _analyzedMedicationList = _orderedAnalyzedMedications();
      _prescriptionFlowState = PrescriptionFlowState.medicationReviewRequired;
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
    _notifyViewModelListeners();
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
    // 오류 화면에서 돌아와도 약별 실패 사유를 검색 결과 없음으로 바꾸지 않는다.
    if (_prescriptionFlowState == PrescriptionFlowState.analysisFailed &&
        _medicationLookupStatuses.isNotEmpty) {
      _prescriptionFlowState = PrescriptionFlowState.medicationReviewRequired;
      _notifyViewModelListeners();
      return;
    }
    _medicationMatchReviews.clear();
    _medicationLookupStatuses.clear();
    _analyzedMedicationByScheduleIndex.clear();
    _unverifiedMedicationScheduleIndexes.clear();
    _analyzedMedicationList = [];
    _analysisErrorMessage = '';
    _statusMessage = _isEnglishSetting
        ? 'Review the recognized medication information.'
        : '인식된 약 정보를 다시 확인해주세요.';
    _prescriptionFlowState = PrescriptionFlowState.previewReady;
    _notifyViewModelListeners();
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
      _medicationLookupStatuses.clear();
      _medicationMatchReviews.clear();
      _analyzedMedicationByScheduleIndex.clear();
      _unverifiedMedicationScheduleIndexes.clear();
    }

    final operationId = _beginPrescriptionOperation();
    final recognizedSchedules = List<MedicationSchedule>.of(
      _recognizedMedicationScheduleList,
    );
    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _completedMedicationAnalysisCount = 0;
    _totalMedicationAnalysisCount = targetIndexes.length;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = _isEnglishSetting
        ? 'Analyzing medication information...'
        : '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = _orderedAnalyzedMedications();
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    _notifyViewModelListeners();

    try {
      final analysisBatch = await _analyzeMedicationSchedules(
        recognizedSchedules,
        targetIndexes,
        operationId,
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }

      _unverifiedMedicationScheduleIndexes.removeAll(targetIndexes);
      _medicationMatchReviews.removeWhere(
        (index, _) => targetIndexes.contains(index),
      );
      _medicationMatchReviews.addAll(analysisBatch.reviews);
      for (final index in targetIndexes) {
        _medicationLookupStatuses[index] =
            analysisBatch.analyzedMedicationByScheduleIndex.containsKey(index)
            ? MedicationLookupStatus.verified
            : analysisBatch.errorMessagesByScheduleIndex.containsKey(index)
            ? MedicationLookupStatus.failed
            : analysisBatch.reviews[index]?.candidates.isNotEmpty == true
            ? MedicationLookupStatus.candidates
            : MedicationLookupStatus.notFound;
      }
      _analyzedMedicationByScheduleIndex.addAll(
        analysisBatch.analyzedMedicationByScheduleIndex,
      );
      _unverifiedMedicationScheduleIndexes.addAll(
        analysisBatch.unverifiedScheduleIndexes,
      );
      _analyzedMedicationList = _orderedAnalyzedMedications();

      // 전체 조회가 실패해도 인식된 약과 실패 개수를 유지하고 같은 화면에서 재시도한다.
      if (_unverifiedMedicationScheduleIndexes.isNotEmpty) {
        final unverifiedCount = _unverifiedMedicationScheduleIndexes.length;
        _analysisErrorMessage =
            analysisBatch.errorMessagesByScheduleIndex.values.isEmpty
            ? ''
            : analysisBatch.errorMessagesByScheduleIndex.values.first;
        _prescriptionFlowState = PrescriptionFlowState.medicationReviewRequired;
        _statusMessage = _isEnglishSetting
            ? '$unverifiedCount medication item(s) could not be verified. Review and retry them.'
            : '$unverifiedCount개 약은 확인이 필요합니다. 후보를 처방전과 비교하거나 약명을 수정해주세요.';
        _notifyViewModelListeners();
        return;
      }

      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = _isEnglishSetting
          ? 'Prescription analysis completed.'
          : '처방전 분석이 완료되었습니다.';
      _notifyViewModelListeners();
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

  // Function Name: _analyzeMedicationSchedules
  // Description: Looks up rows in batches of six and retries account-busy results once, sequentially, after their delay.
  // Parameters: schedules: Full row list; scheduleIndexes: Rows to query; operationId: Cancellation generation.
  // Returns: Indexed successful, unmatched, failed and candidate-review results; obsolete operations stop later batches and progress publication.
  Future<_MedicationAnalysisBatch> _analyzeMedicationSchedules(
    List<MedicationSchedule> schedules,
    List<int> scheduleIndexes,
    int operationId,
  ) async {
    const batchSize = 6;
    final analyzedMedicationByScheduleIndex = <int, AnalyzedMedication>{};
    final unmatchedScheduleIndexes = <int>{};
    final errorMessagesByScheduleIndex = <int, String>{};
    final reviews = <int, MedicationMatchReview>{};

    // Function Name: markCompleted
    // Description: Counts a row's terminal lookup attempt only while this analysis operation remains current.
    // Parameters: None.
    // Returns: None; increments progress and notifies listeners, ignoring late cancelled responses.
    void markCompleted() {
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return;
      }
      _completedMedicationAnalysisCount += 1;
      _notifyViewModelListeners();
    }

    // 함수이름: request
    // 함수역할: 한 처방전 행의 상세를 조회하고 미일치·후보·혼잡·오류를 구분한다.
    // 매개변수: index: schedules의 원래 행 인덱스.
    // 반환값: 인덱스와 결과를 담은 Future; 조회 예외는 후보·혼잡 상태나 현지화된 실패 결과로 변환한다.
    Future<_MedicationLookupResult> request(int index) async {
      final schedule = schedules[index];
      try {
        final detail = await checkMedicationDetail.requestMedicationDetail(
          schedule,
        );
        return detail == null
            ? _MedicationLookupResult.unmatched(index)
            : _MedicationLookupResult.matched(
                index,
                AnalyzedMedication(schedule: schedule, detail: detail),
              );
      } on MedicationMatchReview catch (review) {
        return _MedicationLookupResult._(scheduleIndex: index, review: review);
      } on MedicationLookupBusy catch (busy) {
        return _MedicationLookupResult._(
          scheduleIndex: index,
          busy: busy,
          errorMessage: _isEnglishSetting
              ? 'Another request is in progress. Please retry shortly.'
              : '다른 요청을 처리 중입니다. 잠시 후 다시 조회해주세요.',
        );
      } catch (error) {
        return _MedicationLookupResult.failed(
          index,
          UserFacingErrorMessage.resolve(
            error,
            isEnglish: _isEnglishSetting,
            context: UserFacingErrorContext.medicationLookup,
          ),
        );
      }
    }

    // Function Name: lookup
    // Description: Performs one lookup and advances progress unless an initial busy result still has a retry pending.
    // Parameters: index: Original row index; isRetry: Whether this is the terminal retry.
    // Returns: The lookup result; progress is counted once at its final attempt.
    Future<_MedicationLookupResult> lookup(
      int index, {
      bool isRetry = false,
    }) async {
      final result = await request(index);
      if (isRetry || result.busy == null) markCompleted();
      return result;
    }

    for (var start = 0; start < scheduleIndexes.length; start += batchSize) {
      final end = math.min(start + batchSize, scheduleIndexes.length);
      final batchIndexes = scheduleIndexes.sublist(start, end);
      final batchResults = await Future.wait(batchIndexes.map(lookup));
      for (var result in batchResults) {
        // SQLite 계정 잠금 충돌만 선행 조회 종료 후 한 번씩 직렬 재시도한다.
        if (result.busy != null) {
          if (!_isCurrentPrescriptionOperation(operationId)) break;
          final delay = result.busy!.retryAt.difference(DateTime.now());
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          if (!_isCurrentPrescriptionOperation(operationId)) break;
          result = await lookup(result.scheduleIndex, isRetry: true);
        }
        if (result.review != null) {
          reviews[result.scheduleIndex] = result.review!;
        }
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
      if (!_isCurrentPrescriptionOperation(operationId)) break;
    }
    return _MedicationAnalysisBatch(
      analyzedMedicationByScheduleIndex: analyzedMedicationByScheduleIndex,
      unmatchedScheduleIndexes: unmatchedScheduleIndexes,
      errorMessagesByScheduleIndex: errorMessagesByScheduleIndex,
      reviews: reviews,
    );
  }

  // 함수이름: confirmMedicationCandidate
  // 함수역할: 현재 검토 목록에 실제로 속한 후보만 확정하고 다른 미확인 행의 실패 상태는 유지한다.
  // 매개변수: index: 원래 OCR 행; detail: 해당 행의 현재 후보 객체.
  // 반환값: 없음; 유효한 선택은 그 행의 약명·분석 결과를 바꾸지만 자동 저장하지 않는다.
  void confirmMedicationCandidate(int index, MedicationDetail detail) {
    final review = _medicationMatchReviews[index];
    if (_prescriptionFlowState !=
            PrescriptionFlowState.medicationReviewRequired ||
        review == null ||
        !review.candidates.contains(detail)) {
      return;
    }
    final original = _recognizedMedicationScheduleList[index];
    final schedule = original.copyWith(
      medicationName: detail.itemName,
      rawMedicationName: original.rawMedicationName.isEmpty
          ? original.medicationName
          : original.rawMedicationName,
      nameCorrectionSource: 'user_selection',
      nameConfidence: 1,
    );
    _recognizedMedicationScheduleList = List.of(
      _recognizedMedicationScheduleList,
    )..[index] = schedule;
    _analyzedMedicationByScheduleIndex[index] = AnalyzedMedication(
      schedule: schedule,
      detail: detail,
    );
    _unverifiedMedicationScheduleIndexes.remove(index);
    _medicationLookupStatuses[index] = MedicationLookupStatus.verified;
    _medicationMatchReviews.remove(index);
    _analyzedMedicationList = _orderedAnalyzedMedications();
    if (_unverifiedMedicationScheduleIndexes.isEmpty) {
      _analysisErrorMessage = '';
      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
    }
    _notifyViewModelListeners();
  }

  // Function Name: continueWithVerifiedMedicationAnalysis
  // Description: Continues from candidate review using verified rows only and reports how many rows were excluded.
  // Parameters: None.
  // Returns: True when in review with at least one confirmed result; otherwise false without a state transition.
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
    _notifyViewModelListeners();
    return true;
  }

  // Function Name: _orderedAnalyzedMedications
  // Description: Orders successful medication analyses by their original OCR-row indexes.
  // Parameters: None.
  // Returns: A fixed-length result list independent of lookup completion order.
  List<AnalyzedMedication> _orderedAnalyzedMedications() {
    final entries = _analyzedMedicationByScheduleIndex.entries.toList()
      ..sort(
        /* 함수이름: sort 콜백
       * 함수역할: 조회 완료 순서와 무관하게 원래 일정 인덱스 오름차순으로 결과를 정렬한다.
       * 매개변수:
       * - left (MapEntry<int, AnalyzedMedication>): 정렬 비교의 첫 번째 일정 인덱스 항목
       * - right (MapEntry<int, AnalyzedMedication>): 정렬 비교의 두 번째 일정 인덱스 항목
       * 반환값:
       * - 원래 인덱스의 음수·0·양수 비교값.
       */
        (left, right) => left.key.compareTo(right.key),
      );
    return entries
        .map(
          /* 함수이름: map 콜백
     * 함수역할: 인덱스 순으로 정렬된 결과에서 분석 약 정보만 꺼낸다.
     * 매개변수:
     * - entry (MapEntry<int, AnalyzedMedication>): 처리 중인 맵의 키·값 항목
     * 반환값:
     * - 해당 인덱스의 분석 약 정보.
     */
          (entry) => entry.value,
        )
        .toList(growable: false);
  }

  // Function Name: _refreshPrescriptionChangeRadar
  // Description: Loads prescription comparison without blocking results and discards responses after the operation or screen changes.
  // Parameters: operationId: Owning generation; medications: Complete analyzed prescription.
  // Returns: Completion; comparison failure becomes null and only the current result screen receives the outcome.
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
    _notifyViewModelListeners();
  }

  // Function Name: showMedicationAnalysisResult
  // Description: Shows available analysis results and requests comparison only when every recognized row is represented.
  // Parameters: None.
  // Returns: None; an empty analysis becomes failure, while partial results suppress comparison.
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
    _notifyViewModelListeners();
    unawaited(
      _refreshPrescriptionChangeRadar(
        _prescriptionOperationId,
        List<AnalyzedMedication>.of(_analyzedMedicationList),
      ),
    );
  }

  // Function Name: requestMedicationSave
  // Description: Saves one analyzed medication while preventing overlapping individual or batch saves.
  // Parameters: analyzedMedication: Detail and schedule pair; medicationIndex: Display/result index.
  // Returns: True for saved or duplicate outcomes, false when busy/disposed; errors propagate and only the current operation clears its loading marker.
  Future<bool> requestMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) async {
    if (_disposed) return false;
    final operationId = _prescriptionOperationId;
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = _isEnglishSetting
          ? 'Another medication is being saved.'
          : '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners();
      return false;
    }
    if (_completedMedicationSaveIndexes.contains(medicationIndex)) {
      _statusMessage = _isEnglishSetting
          ? 'This medication is already saved.'
          : '이미 추가된 약입니다.';
      _notifyViewModelListeners();
      return true;
    }

    _statusMessage = _isEnglishSetting
        ? 'Saving ${analyzedMedication.displayName}...'
        : '${analyzedMedication.displayName} 저장 중...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final result = await savedMedications.saveMedicationInfo(
        analyzedMedication.detail,
        medicationSchedule: analyzedMedication.schedule,
      );
      if (!_isCurrentPrescriptionOperation(operationId)) {
        return result.isCompleted;
      }
      _statusMessage = savedMedications.statusMessage;
      if (result.isCompleted) {
        _completedMedicationSaveIndexes.add(medicationIndex);
        _notifyViewModelListeners();
      }
      return result.isCompleted;
    } finally {
      if (_isCurrentPrescriptionOperation(operationId)) {
        _setSavingMedicationIndex(null);
      }
    }
  }

  // Function Name: requestAllAnalyzedMedicationSave
  // Description: Saves unfinished analysis rows sequentially and refreshes dependent state once after the batch.
  // Parameters: None.
  // Returns: True when no result failed; false for empty/busy/disposed or invalidated work. Exceptions propagate, with current-operation progress cleared in finally.
  Future<bool> requestAllAnalyzedMedicationSave() async {
    if (_disposed) return false;
    final operationId = _prescriptionOperationId;
    if (_savingMedicationIndex != null || _isAllMedicationSaving) {
      _statusMessage = _isEnglishSetting
          ? 'Another medication is being saved.'
          : '다른 복약 정보를 저장하고 있습니다.';
      _notifyViewModelListeners();
      return false;
    }
    if (_analyzedMedicationList.isEmpty) {
      _statusMessage = _isEnglishSetting
          ? 'There are no analysis results to save.'
          : '저장할 분석 결과가 없습니다.';
      _notifyViewModelListeners();
      return false;
    }

    _isAllMedicationSaving = true;
    _statusMessage = _isEnglishSetting
        ? 'Saving all medication schedules...'
        : '전체 복약 일정을 저장 중입니다...';
    _notifyViewModelListeners();

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
        _notifyViewModelListeners();

        final analyzedMedication = _analyzedMedicationList[index];
        final result = await savedMedications.saveMedicationInfo(
          analyzedMedication.detail,
          medicationSchedule: analyzedMedication.schedule,
          refreshAfterSave: false,
        );
        if (!_isCurrentPrescriptionOperation(operationId)) return false;
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

      await savedMedications.fetchSavedMedicationInfo();
      await fetchTodayMedicationSchedule();
      await _synchronizeMedicationReminderSchedulesIfScheduleIsFresh();
      if (!_isCurrentPrescriptionOperation(operationId)) return false;
      _statusMessage = _buildBulkSaveMessage(
        savedCount: savedCount,
        duplicateCount: duplicateCount,
        failedCount: failedCount,
      );
      return failedCount == 0;
    } finally {
      if (_isCurrentPrescriptionOperation(operationId)) {
        _savingMedicationIndex = null;
        _isAllMedicationSaving = false;
        _notifyViewModelListeners();
      }
    }
  }

  // 함수이름: _requestPrescriptionRecognition
  // 함수역할: 카메라/갤러리 공통 처방전 OCR 흐름을 상태 머신 형태로 처리한다.
  // - 촬영처럼 이미지가 이미 있는 요청은 바로 이전 인식·분석 상태를 지우고 시작한다.
  // - 갤러리처럼 선택 창을 먼저 여는 요청(resetAfterImageSelection)은 이미지를 실제로 고른 뒤에만 이전 상태를 지운다. 선택을 취소하면 실패·검토 중이던 흐름을 그대로 두고, 선택 창이 열려 있는 동안의 두 번째 요청은 무시한다.
  // 매개변수:
  // - imageRequest (Future<List<MedicationSchedule>?> Function({VoidCallback? onImageSelected})): 이미지 선택과 OCR 요청을 수행하는 함수
  // - cancelledMessage (String): 사용자가 취소했을 때 보여줄 상태 메시지
  // - resetAfterImageSelection (bool): 이미지를 고른 뒤에 이전 상태를 지울지 여부
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _requestPrescriptionRecognition({
    required Future<List<MedicationSchedule>?> Function({
      VoidCallback? onImageSelected,
      PrescriptionRecognitionProgressCallback? onProgress,
    })
    imageRequest,
    required String cancelledMessage,
    bool resetAfterImageSelection = false,
  }) async {
    if (resetAfterImageSelection) {
      if (_isPrescriptionImagePickPending) {
        return;
      }
      _isPrescriptionImagePickPending = true;
    }
    final requestGeneration = _prescriptionOperationId;
    int? operationId;
    var ownsImagePicker = resetAfterImageSelection;
    // Function Name: beginRecognition
    // Description: Starts recognition once only if the image-selection request still belongs to the current generation.
    // Parameters: None.
    // Returns: Whether this request owns the active prescription operation after any initial reset.
    bool beginRecognition() {
      if (operationId == null) {
        if (_disposed || _prescriptionOperationId != requestGeneration) {
          return false;
        }
        operationId = _beginPrescriptionOperation();
        _resetPrescriptionRecognitionState();
      }
      return _isCurrentPrescriptionOperation(operationId!);
    }

    if (!resetAfterImageSelection) {
      beginRecognition();
    }

    try {
      final result = await imageRequest(
        onProgress: (stage) {
          if (operationId == null ||
              !_isCurrentPrescriptionOperation(operationId!)) {
            return;
          }
          _recognitionStage = stage;
          _notifyViewModelListeners();
        },
        onImageSelected: /* 함수이름: onImageSelected 콜백
         * 함수역할: 현재 처방 작업이 유지될 때 선택 이미지 미리보기를 갱신하고 문자 인식 진행 상태를 표시한다.
         * 매개변수:
         * - 없음.
         * 반환값:
         * - 없음.
         */ () {
          if (resetAfterImageSelection) {
            _isPrescriptionImagePickPending = false;
            ownsImagePicker = false;
          }
          if (beginRecognition()) {
            _prescriptionPreviewImagePath =
                inputPrescription.lastSelectedImagePath;
            _showPrescriptionRecognitionProgress();
          }
        },
      );
      if (result == null && operationId == null) {
        // 이미지를 고르지 않고 선택 창을 닫았다. 진행 중이던 흐름과 인식 결과는 건드리지 않는다.
        if (!_disposed &&
            _prescriptionOperationId == requestGeneration &&
            _prescriptionFlowState == PrescriptionFlowState.idle) {
          _statusMessage = cancelledMessage;
          _notifyViewModelListeners();
        }
        return;
      }
      if (!beginRecognition()) {
        return;
      }
      if (result == null) {
        _statusMessage = cancelledMessage;
        _prescriptionFlowState = PrescriptionFlowState.idle;
        _notifyViewModelListeners();
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
      // 중간 검토 화면 없이 약품 조회까지 이어가되 후보 확정과 저장은 사용자에게 맡긴다.
      await requestPrescriptionAnalysis();
    } catch (error) {
      if (!beginRecognition()) {
        return;
      }
      _showAnalysisFailure(
        UserFacingErrorMessage.resolve(error, isEnglish: _isEnglishSetting),
      );
    } finally {
      // 이전 분석이 끝나도 이후 요청이 연 갤러리의 중복 실행 방지는 해제하지 않는다.
      if (ownsImagePicker) {
        _isPrescriptionImagePickPending = false;
      }
    }
  }

  // Function Name: _resetPrescriptionRecognitionState
  // Description: Clears prior recognition, analysis, comparison and save-progress state for a new or closed workflow.
  // Parameters: None.
  // Returns: None; this reset does not independently cancel network work or notify listeners.
  void _resetPrescriptionRecognitionState() {
    _recognitionStage = PrescriptionRecognitionStage.recognizingText;
    _medicationLookupStatuses.clear();
    _recognizedMedicationScheduleList = [];
    _medicationMatchReviews.clear();
    _recognizedTextRegionList = [];
    _prescriptionPreviewImagePath = '';
    _analyzedMedicationList = [];
    _analyzedMedicationByScheduleIndex.clear();
    _unverifiedMedicationScheduleIndexes.clear();
    _prescriptionChangeRadar = null;
    _isPrescriptionChangeLoading = false;
    // 이전 작업의 저장 응답은 세대가 달라 표시를 되돌리지 못하므로 여기서 함께 지운다.
    _completedMedicationSaveIndexes.clear();
    _isAllMedicationSaving = false;
    _savingMedicationIndex = null;
    _analysisErrorMessage = '';
    _clearPrescriptionRecognitionCounts();
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _completedMedicationAnalysisCount = 0;
    _totalMedicationAnalysisCount = 0;
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

  // Function Name: _isCurrentPrescriptionOperation
  // Description: Checks operation ownership before applying asynchronous prescription results.
  // Parameters: operationId: Generation captured when the work began.
  // Returns: True only while undisposed and still on that generation.
  bool _isCurrentPrescriptionOperation(int operationId) {
    return !_disposed && _prescriptionOperationId == operationId;
  }

  // Function Name: _showPrescriptionRecognitionProgress
  // Description: Publishes recognition-stage loading after an image has actually been selected.
  // Parameters: None.
  // Returns: None; updates flow state, localized feedback and subscribers.
  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = _isEnglishSetting
        ? 'Recognizing the prescription...'
        : '처방전을 인식 중입니다...';
    _notifyViewModelListeners();
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

  // Function Name: _showAnalysisFailure
  // Description: Stores shared error guidance and transitions the prescription flow to failure.
  // Parameters: message: User-facing failure text.
  // Returns: None; updates both analysis error and status before notifying.
  void _showAnalysisFailure(String message) {
    _analysisErrorMessage = message;
    _statusMessage = message;
    _prescriptionFlowState = PrescriptionFlowState.analysisFailed;
    _notifyViewModelListeners();
  }

  // Function Name: _setSavingMedicationIndex
  // Description: Sets or clears the individual medication-save loading marker.
  // Parameters: value: Displayed result index, or null to clear.
  // Returns: None; notifies prescription subscribers.
  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    _notifyViewModelListeners();
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
  final MedicationLookupBusy? busy;
  final MedicationMatchReview? review;
  final int scheduleIndex;
  final AnalyzedMedication? analyzedMedication;
  final String errorMessage;

  // 함수이름: _MedicationLookupResult._
  // 함수역할: OCR 행 인덱스와 선택적 분석 결과·오류 메시지를 조회 결과 내부 상태로 묶는다.
  // 매개변수:
  // - scheduleIndex (int): 원래 OCR 목록의 대상 행 인덱스
  // - analyzedMedication (AnalyzedMedication?): OCR 일정과 상세정보가 결합된 분석 결과
  // - errorMessage (String): 실패 상태에 사용할 사용자 안내문
  // - busy (MedicationLookupBusy?): 서버 조회 혼잡 및 재시도 정보; review (MedicationMatchReview?): 사용자 확인이 필요한 후보·매칭 검토 결과.
  // 반환값:
  // - _MedicationLookupResult: 초기화된 인스턴스.
  const _MedicationLookupResult._({
    this.busy,
    this.review,
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
  final Map<int, MedicationMatchReview> reviews;
  final Map<int, AnalyzedMedication> analyzedMedicationByScheduleIndex;
  final Set<int> unmatchedScheduleIndexes;
  final Map<int, String> errorMessagesByScheduleIndex;

  // 함수이름: _MedicationAnalysisBatch
  // 함수역할: 인덱스별 분석 성공 결과와 미일치 행 및 오류 메시지를 하나의 조회 묶음으로 보존한다.
  // 매개변수:
  // - analyzedMedicationByScheduleIndex (Map<int, AnalyzedMedication>): 원래 OCR 행 인덱스별 분석 성공 결과
  // - unmatchedScheduleIndexes (Set<int>): 상세 조회에서 일치 약을 찾지 못한 OCR 행
  // - errorMessagesByScheduleIndex (Map<int, String>): 원래 OCR 행별 기술 오류 안내
  // - reviews (Map<int, MedicationMatchReview>): 원래 OCR 행 인덱스별 사용자 검토 결과.
  // 반환값:
  // - _MedicationAnalysisBatch: 초기화된 인스턴스.
  const _MedicationAnalysisBatch({
    this.reviews = const {},
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
