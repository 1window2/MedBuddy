import 'package:flutter/material.dart';

import '../controls/check_medication_detail_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/input_prescription_control.dart';
import '../controls/manage_user_setting_control.dart';
import '../entities/analyzed_medication_entity.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/user_setting_entity.dart';

// 열거형명: PrescriptionFlowState
// 역할: 처방전 촬영부터 결과 확인까지의 화면 상태를 표현한다.
enum PrescriptionFlowState {
  idle,
  recognizingPrescription,
  previewReady,
  analyzingMedication,
  analysisSucceeded,
  analysisFailed,
  resultReady,
}

// 열거형명: AnalysisProgressStep
// 역할: 분석중 화면에서 현재 처리 단계를 사용자에게 보여주기 위한 상태값이다.
enum AnalysisProgressStep {
  prescriptionRecognition,
  medicationAnalysis,
  scheduleGeneration,
}

// 파일명: medbuddy_view_model.dart
// 역할: 화면 상태와 컨트롤 계층을 연결하는 앱 전역 ViewModel을 정의한다.

// 클래스명: MedBuddyViewModel
// 역할: 처방전 인식, 약품 분석, 복약 정보 저장, 일정 조회, 설정 저장 흐름을 관리한다.
// 주요 책임:
// - 각 Control 객체의 API 호출 결과를 화면 상태로 변환한다.
// - 처방전 분석 흐름의 단계별 상태를 유지한다.
// - 저장된 복약 정보와 오늘의 복약 일정을 캐시한다.
// - 사용자 설정을 불러오고 변경 사항을 화면에 반영한다.
class MedBuddyViewModel extends ChangeNotifier {
  final InputPrescription inputPrescription;
  final CheckMedicationDetail checkMedicationDetail;
  final CheckSavedMedication checkSavedMedication;
  final CheckSchedule checkSchedule;
  final ManageUserSetting manageUserSetting;

  PrescriptionFlowState _prescriptionFlowState = PrescriptionFlowState.idle;
  PrescriptionFlowState get prescriptionFlowState => _prescriptionFlowState;

  AnalysisProgressStep _analysisProgressStep =
      AnalysisProgressStep.prescriptionRecognition;
  AnalysisProgressStep get analysisProgressStep => _analysisProgressStep;

  bool get isPrescriptionAnalyzing {
    return _prescriptionFlowState ==
            PrescriptionFlowState.recognizingPrescription ||
        _prescriptionFlowState == PrescriptionFlowState.analyzingMedication;
  }

  bool get isLoading => isPrescriptionAnalyzing;

  int? _savingMedicationIndex;
  int? get savingMedicationIndex => _savingMedicationIndex;
  bool get isMedicationSaving => _savingMedicationIndex != null;

  final Set<int> _completedMedicationSaveIndexes = {};
  Set<int> get completedMedicationSaveIndexes =>
      Set.unmodifiable(_completedMedicationSaveIndexes);

  bool _isAllMedicationSaving = false;
  bool get isAllMedicationSaving => _isAllMedicationSaving;

  bool _isSavedMedicationLoading = false;
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  bool _isTodayScheduleLoading = false;
  bool get isTodayScheduleLoading => _isTodayScheduleLoading;

  bool _isUserSettingLoading = false;
  bool get isUserSettingLoading => _isUserSettingLoading;

  String _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
  String get statusMessage => _statusMessage;

  String _analysisErrorMessage = '';
  String get analysisErrorMessage => _analysisErrorMessage;

  UserSetting _userSetting = const UserSetting();
  UserSetting get userSetting =>
      manageUserSetting.requestUserSetting(_userSetting);

  List<MedicationSchedule> _recognizedMedicationScheduleList = [];
  List<MedicationSchedule> get recognizedMedicationScheduleList =>
      List.unmodifiable(_recognizedMedicationScheduleList);

  List<MedicationSchedule> get medicationScheduleList =>
      recognizedMedicationScheduleList;

  List<AnalyzedMedication> _analyzedMedicationList = [];
  List<AnalyzedMedication> get analyzedMedicationList =>
      List.unmodifiable(_analyzedMedicationList);

  List<MedicationDetail> _savedMedicationInfoList = [];
  List<MedicationDetail> get savedMedicationInfoList =>
      List.unmodifiable(_savedMedicationInfoList);

  List<MedicationSchedule> _todayMedicationScheduleList = [];
  List<MedicationSchedule> get todayMedicationScheduleList =>
      List.unmodifiable(_todayMedicationScheduleList);

  MedBuddyViewModel({
    InputPrescription? inputPrescription,
    CheckMedicationDetail? checkMedicationDetail,
    CheckSavedMedication? checkSavedMedication,
    CheckSchedule? checkSchedule,
    ManageUserSetting? manageUserSetting,
  })  : inputPrescription = inputPrescription ?? InputPrescription(),
        checkMedicationDetail =
            checkMedicationDetail ?? CheckMedicationDetail(),
        checkSavedMedication = checkSavedMedication ?? CheckSavedMedication(),
        checkSchedule = checkSchedule ?? CheckSchedule(),
        manageUserSetting = manageUserSetting ?? ManageUserSetting();

  // 함수명: loadUserSetting
  // 함수역할:
  // - 앱 시작 시 로컬 저장소에 보관된 사용자 설정을 불러온다.
  // 반환값:
  // - 없음
  Future<void> loadUserSetting() async {
    _isUserSettingLoading = true;
    notifyListeners();

    try {
      _userSetting = await manageUserSetting.requestStoredUserSetting();
    } finally {
      _isUserSettingLoading = false;
      notifyListeners();
    }
  }

  // 함수명: requestPrescriptionImage
  // 함수역할:
  // - 카메라 촬영 기반 처방전 OCR 흐름을 시작한다.
  // 반환값:
  // - 없음
  Future<void> requestPrescriptionImage() async {
    await _requestPrescriptionRecognition(
      imageRequest: inputPrescription.requestPrescriptionImage,
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

  // 함수명: requestMedicationAnalysis
  // 함수역할:
  // - UC-1에서 인식된 약 목록 각각에 대해 공공데이터 기반 상세 정보를 요청한다.
  // - 저장은 하지 않고 분석 성공/실패 화면 상태까지만 변경한다.
  // 반환값:
  // - 없음
  Future<void> requestMedicationAnalysis() async {
    if (_recognizedMedicationScheduleList.isEmpty) {
      _showAnalysisFailure('인식된 처방 내역이 없습니다.');
      return;
    }

    _analysisProgressStep = AnalysisProgressStep.medicationAnalysis;
    _prescriptionFlowState = PrescriptionFlowState.analyzingMedication;
    _statusMessage = '약물 정보를 분석 중입니다...';
    _analysisErrorMessage = '';
    _analyzedMedicationList = [];
    notifyListeners();

    try {
      final analysisResults = await Future.wait(
        _recognizedMedicationScheduleList.map((schedule) async {
          try {
            final detail = await checkMedicationDetail.requestMedicationDetail(
              schedule,
            );
            if (detail == null) {
              return null;
            }
            return AnalyzedMedication(schedule: schedule, detail: detail);
          } catch (_) {
            return null;
          }
        }),
      );
      final analyzedMedicationList = analysisResults
          .whereType<AnalyzedMedication>()
          .toList(growable: false);

      _analysisProgressStep = AnalysisProgressStep.scheduleGeneration;
      notifyListeners();

      if (analyzedMedicationList.isEmpty) {
        _showAnalysisFailure('약물 상세 정보를 찾지 못했습니다.');
        return;
      }

      _analyzedMedicationList = analyzedMedicationList;
      _prescriptionFlowState = PrescriptionFlowState.analysisSucceeded;
      _statusMessage = '처방전 분석이 완료되었습니다.';
      notifyListeners();
    } on StateError catch (error) {
      _showAnalysisFailure(error.message);
    } catch (_) {
      _showAnalysisFailure('처방전 분석 중 오류가 발생했습니다.');
    }
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
    notifyListeners();
  }

  // 함수명: requestAnalyzedMedicationSave
  // 함수역할:
  // - 이미 분석된 약 상세 정보를 저장 목록에 저장한다.
  // 매개변수:
  // - analyzedMedication: OCR 스케줄과 상세 정보가 결합된 분석 결과
  // - medicationIndex: 저장 버튼 로딩 표시를 위한 화면상 인덱스
  // 반환값:
  // - 저장 성공 여부
  Future<bool> requestAnalyzedMedicationSave(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  ) async {
    if (_completedMedicationSaveIndexes.contains(medicationIndex)) {
      _statusMessage = '이미 추가된 약입니다.';
      notifyListeners();
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
        notifyListeners();
      }
      return result.isCompleted;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

  Future<bool> requestAllAnalyzedMedicationSave() async {
    if (_analyzedMedicationList.isEmpty) {
      _statusMessage = '저장할 분석 결과가 없습니다.';
      notifyListeners();
      return false;
    }

    _isAllMedicationSaving = true;
    _statusMessage = '전체 복약 일정을 저장 중입니다...';
    notifyListeners();

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
        notifyListeners();

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
      _statusMessage = _buildBulkSaveMessage(
        savedCount: savedCount,
        duplicateCount: duplicateCount,
        failedCount: failedCount,
      );
      return failedCount == 0;
    } finally {
      _savingMedicationIndex = null;
      _isAllMedicationSaving = false;
      notifyListeners();
    }
  }

  Future<bool> requestMedicationSave(
    MedicationSchedule medicationSchedule,
    int medicationIndex,
  ) async {
    final drugName = medicationSchedule.displayName;
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setSavingMedicationIndex(medicationIndex);

    try {
      final medicationInfo =
          await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
      if (medicationInfo == null) {
        _statusMessage = '해당 의약품 정보를 찾을 수 없습니다.';
        return false;
      }

      final result = await saveMedicationInfo(
        medicationInfo,
        medicationSchedule: medicationSchedule,
      );
      return result.isCompleted;
    } on StateError catch (error) {
      _statusMessage = error.message;
      return false;
    } catch (_) {
      _statusMessage = '의약품 분석 중 오류가 발생했습니다.';
      return false;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

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
    notifyListeners();

    final result = await checkSavedMedication.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
    );
    if (result.status == MedicationSaveStatus.failed) {
      _statusMessage = result.message;
      notifyListeners();
      return result;
    }

    _statusMessage = result.status == MedicationSaveStatus.duplicate
        ? '이미 추가된 약입니다.'
        : '복약 정보가 성공적으로 저장되었습니다.';
    if (refreshAfterSave) {
      await fetchSavedMedicationInfo();
    }
    notifyListeners();
    return result;
  }

  // 함수명: fetchSavedMedicationInfo
  // 함수역할:
  // - 저장된 복약 정보 목록을 서버에서 가져와 화면 상태에 반영한다.
  // 반환값:
  // - 없음
  Future<void> fetchSavedMedicationInfo() async {
    _isSavedMedicationLoading = true;
    notifyListeners();

    try {
      _savedMedicationInfoList =
          await checkSavedMedication.requestSavedMedicationInfo();
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      _isSavedMedicationLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final success = await checkSavedMedication.requestDelete(
      savedMedicationId,
    );

    if (success) {
      _savedMedicationInfoList = _savedMedicationInfoList
          .where((item) => item.id != savedMedicationId)
          .toList(growable: false);
      notifyListeners();
    }
    return success;
  }

  // 함수명: fetchTodayMedicationSchedule
  // 함수역할:
  // - 오늘 기준으로 복용해야 하는 약 일정을 서버에서 가져온다.
  // 반환값:
  // - 없음
  Future<void> fetchTodayMedicationSchedule() async {
    _isTodayScheduleLoading = true;
    notifyListeners();

    try {
      _todayMedicationScheduleList =
          await checkSchedule.requestTodayMedicationSchedule();
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '복약 일정을 불러오지 못했습니다.';
    } finally {
      _isTodayScheduleLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestMedicationStatusUpdate(
    MedicationSchedule medicationSchedule,
    bool medicationStatus,
  ) async {
    if (medicationSchedule.medicationID.trim().isEmpty) {
      return false;
    }

    try {
      final updatedSchedule = await checkSchedule.updateMedicationStatus(
        medicationSchedule.medicationID,
        medicationStatus,
      );
      _todayMedicationScheduleList = _todayMedicationScheduleList
          .map(
            (item) => item.medicationID == updatedSchedule.medicationID
                ? updatedSchedule
                : item,
          )
          .toList(growable: false);
      notifyListeners();
      return true;
    } on StateError catch (error) {
      _statusMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _statusMessage = '복약 상태를 업데이트하지 못했습니다.';
      notifyListeners();
      return false;
    }
  }

  void clearAnalysisResult() {
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _completedMedicationSaveIndexes.clear();
    _isAllMedicationSaving = false;
    _savingMedicationIndex = null;
    _analysisErrorMessage = '';
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.idle;
    _statusMessage = '처방전을 촬영하거나 이미지를 선택해주세요.';
    notifyListeners();
  }

  Future<void> requestUserSettingSave({
    required String fontSizeOption,
    required String readingSpeedOption,
    required String language,
  }) async {
    _userSetting = await manageUserSetting.requestSettingSave(
      currentSetting: _userSetting,
      fontSizeOption: fontSizeOption,
      readingSpeedOption: readingSpeedOption,
      language: language,
    );
    notifyListeners();
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
    }) imageRequest,
    required String cancelledMessage,
  }) async {
    _recognizedMedicationScheduleList = [];
    _analyzedMedicationList = [];
    _analysisErrorMessage = '';
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;

    try {
      final result = await imageRequest(
        onImageSelected: _showPrescriptionRecognitionProgress,
      );
      if (result == null) {
        _statusMessage = cancelledMessage;
        _prescriptionFlowState = PrescriptionFlowState.idle;
        notifyListeners();
        return;
      }

      if (result.isEmpty) {
        _showAnalysisFailure('처방전에서 약 정보를 찾지 못했습니다.');
        return;
      }

      _recognizedMedicationScheduleList = result;
      _prescriptionFlowState = PrescriptionFlowState.previewReady;
      _statusMessage = '처방전 인식이 완료되었습니다.';
      notifyListeners();
    } on StateError catch (error) {
      _showAnalysisFailure(error.message);
    } catch (_) {
      _showAnalysisFailure('처방전 인식 중 오류가 발생했습니다.');
    }
  }

  void _showPrescriptionRecognitionProgress() {
    _analysisProgressStep = AnalysisProgressStep.prescriptionRecognition;
    _prescriptionFlowState = PrescriptionFlowState.recognizingPrescription;
    _statusMessage = '처방전을 인식 중입니다...';
    notifyListeners();
  }

  void _showAnalysisFailure(String message) {
    _analysisErrorMessage = message;
    _statusMessage = message;
    _prescriptionFlowState = PrescriptionFlowState.analysisFailed;
    notifyListeners();
  }

  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    notifyListeners();
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

  @override
  void dispose() {
    inputPrescription.dispose();
    checkMedicationDetail.dispose();
    checkSavedMedication.dispose();
    checkSchedule.dispose();
    super.dispose();
  }
}
