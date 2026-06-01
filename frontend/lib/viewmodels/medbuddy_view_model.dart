import 'package:flutter/material.dart';

import '../controls/medication_save_control.dart';
import '../controls/prescription_analysis_control.dart';
import '../controls/saved_medication_control.dart';
import '../models/medication_candidate.dart';
import '../models/medication_info.dart';
import '../models/prescription_analysis_result.dart';
import '../models/saved_medication_info.dart';
import '../services/medication_api_boundary.dart';

class MedBuddyViewModel extends ChangeNotifier {
  final PrescriptionAnalysisControl prescriptionAnalysisControl;
  final MedicationSaveControl medicationSaveControl;
  final SavedMedicationControl savedMedicationControl;
  final MedicationAPIBoundary? _ownedMedicationAPIBoundary;

  bool _isPrescriptionAnalyzing = false;
  bool get isPrescriptionAnalyzing => _isPrescriptionAnalyzing;
  bool get isLoading => _isPrescriptionAnalyzing;

  bool _isMedicationSaving = false;
  bool get isMedicationSaving => _isMedicationSaving;

  bool _isSavedMedicationLoading = false;
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  String _statusMessage = '처방전이나 약봉투를 촬영해 주세요.';
  String get statusMessage => _statusMessage;

  PrescriptionAnalysisResult _prescriptionAnalysisResult =
      PrescriptionAnalysisResult.empty();
  PrescriptionAnalysisResult get prescriptionAnalysisResult =>
      _prescriptionAnalysisResult;

  List<MedicationCandidate> get medicationCandidates =>
      _prescriptionAnalysisResult.medications;

  List<SavedMedicationInfo> _savedMedicationInfoList = [];
  List<SavedMedicationInfo> get savedMedicationInfoList =>
      List.unmodifiable(_savedMedicationInfoList);

  factory MedBuddyViewModel({
    PrescriptionAnalysisControl? prescriptionAnalysisControl,
    MedicationSaveControl? medicationSaveControl,
    SavedMedicationControl? savedMedicationControl,
    MedicationAPIBoundary? medicationAPIBoundary,
  }) {
    final needsAPIBoundary = prescriptionAnalysisControl == null ||
        medicationSaveControl == null ||
        savedMedicationControl == null;
    final sharedAPIBoundary = medicationAPIBoundary ??
        (needsAPIBoundary ? MedicationAPIBoundary() : null);

    return MedBuddyViewModel._(
      prescriptionAnalysisControl: prescriptionAnalysisControl ??
          PrescriptionAnalysisControl(
            medicationAPIBoundary: sharedAPIBoundary!,
          ),
      medicationSaveControl: medicationSaveControl ??
          MedicationSaveControl(medicationAPIBoundary: sharedAPIBoundary!),
      savedMedicationControl: savedMedicationControl ??
          SavedMedicationControl(medicationAPIBoundary: sharedAPIBoundary!),
      ownedMedicationAPIBoundary:
          medicationAPIBoundary == null ? sharedAPIBoundary : null,
    );
  }

  MedBuddyViewModel._({
    required this.prescriptionAnalysisControl,
    required this.medicationSaveControl,
    required this.savedMedicationControl,
    required MedicationAPIBoundary? ownedMedicationAPIBoundary,
  }) : _ownedMedicationAPIBoundary = ownedMedicationAPIBoundary;

  Future<void> requestPrescriptionImage() async {
    _statusMessage = '서버에서 AI가 처방전을 분석 중입니다...';
    _setPrescriptionAnalyzing(true);

    try {
      final result =
          await prescriptionAnalysisControl.requestPrescriptionImage();
      if (result == null) {
        _statusMessage = '사진 촬영이 취소되었습니다.';
        return;
      }

      _prescriptionAnalysisResult = result;
      _statusMessage = result.hasMedications
          ? '분석 완료. 처방 내역을 확인해 주세요.'
          : '분석은 완료됐지만 약품 정보를 찾지 못했습니다.';
    } on ApiException catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '처방전 분석 중 오류가 발생했습니다.';
    } finally {
      _setPrescriptionAnalyzing(false);
    }
  }

  Future<bool> requestMedicationSave(
    MedicationCandidate medicationCandidate,
  ) async {
    final drugName = medicationCandidate.displayName;
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setMedicationSaving(true);

    try {
      final medicationInfo = await medicationSaveControl.requestMedicationInfo(
        medicationCandidate,
      );
      if (medicationInfo == null) {
        _statusMessage = '해당 약품 정보를 찾을 수 없습니다.';
        return false;
      }

      return await saveMedicationInfo(medicationInfo);
    } on ApiException catch (error) {
      _statusMessage = error.message;
      return false;
    } catch (_) {
      _statusMessage = '약품 분석 중 오류가 발생했습니다.';
      return false;
    } finally {
      _setMedicationSaving(false);
    }
  }

  Future<bool> saveMedicationInfo(MedicationInfo medicationInfo) async {
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    notifyListeners();

    final success = await medicationSaveControl.requestMedicationSave(
      medicationInfo,
    );
    if (!success) {
      _statusMessage = '저장에 실패했습니다. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }

    _statusMessage = '약통에 성공적으로 저장되었습니다.';
    await fetchSavedMedicationInfo();
    notifyListeners();
    return true;
  }

  Future<void> fetchSavedMedicationInfo() async {
    _isSavedMedicationLoading = true;
    notifyListeners();

    try {
      _savedMedicationInfoList =
          await savedMedicationControl.requestSavedMedicationInfo();
    } on ApiException catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '저장된 복약 정보를 불러오지 못했습니다.';
    } finally {
      _isSavedMedicationLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    final success = await savedMedicationControl.requestDeleteSavedMedication(
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

  void clearPrescriptionAnalysisResult() {
    _prescriptionAnalysisResult = PrescriptionAnalysisResult.empty();
    _statusMessage = '처방전이나 약봉투를 촬영해 주세요.';
    notifyListeners();
  }

  void _setPrescriptionAnalyzing(bool value) {
    _isPrescriptionAnalyzing = value;
    notifyListeners();
  }

  void _setMedicationSaving(bool value) {
    _isMedicationSaving = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _ownedMedicationAPIBoundary?.dispose();
    super.dispose();
  }
}
