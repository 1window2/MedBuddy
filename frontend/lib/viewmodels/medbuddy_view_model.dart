import 'package:flutter/material.dart';

import '../controls/check_medication_detail_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/input_prescription_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';

class MedBuddyViewModel extends ChangeNotifier {
  final InputPrescription inputPrescription;
  final CheckMedicationDetail checkMedicationDetail;
  final CheckSavedMedication checkSavedMedication;

  bool _isPrescriptionAnalyzing = false;
  bool get isPrescriptionAnalyzing => _isPrescriptionAnalyzing;
  bool get isLoading => _isPrescriptionAnalyzing;

  bool _isMedicationSaving = false;
  bool get isMedicationSaving => _isMedicationSaving;

  bool _isSavedMedicationLoading = false;
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  String _statusMessage = '처방전이나 약봉투를 촬영해 주세요.';
  String get statusMessage => _statusMessage;

  List<MedicationSchedule> _medicationScheduleList = [];
  List<MedicationSchedule> get medicationScheduleList =>
      List.unmodifiable(_medicationScheduleList);

  List<MedicationDetail> _savedMedicationInfoList = [];
  List<MedicationDetail> get savedMedicationInfoList =>
      List.unmodifiable(_savedMedicationInfoList);

  MedBuddyViewModel({
    InputPrescription? inputPrescription,
    CheckMedicationDetail? checkMedicationDetail,
    CheckSavedMedication? checkSavedMedication,
  })  : inputPrescription = inputPrescription ?? InputPrescription(),
        checkMedicationDetail =
            checkMedicationDetail ?? CheckMedicationDetail(),
        checkSavedMedication = checkSavedMedication ?? CheckSavedMedication();

  Future<void> requestPrescriptionImage() async {
    _statusMessage = '서버에서 AI가 처방전을 분석 중입니다...';
    _setPrescriptionAnalyzing(true);

    try {
      final result = await inputPrescription.requestPrescriptionImage();
      if (result == null) {
        _statusMessage = '사진 촬영이 취소되었습니다.';
        return;
      }

      _medicationScheduleList = result;
      _statusMessage = result.isNotEmpty
          ? '분석 완료. 처방 내역을 확인해 주세요.'
          : '분석은 완료됐지만 약품 정보를 찾지 못했습니다.';
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = '처방전 분석 중 오류가 발생했습니다.';
    } finally {
      _setPrescriptionAnalyzing(false);
    }
  }

  Future<bool> requestMedicationSave(
    MedicationSchedule medicationSchedule,
  ) async {
    final drugName = medicationSchedule.displayName;
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setMedicationSaving(true);

    try {
      final medicationInfo = await checkMedicationDetail.requestMedicationDetail(
        medicationSchedule,
      );
      if (medicationInfo == null) {
        _statusMessage = '해당 약품 정보를 찾을 수 없습니다.';
        return false;
      }

      return await saveMedicationInfo(medicationInfo);
    } on StateError catch (error) {
      _statusMessage = error.message;
      return false;
    } catch (_) {
      _statusMessage = '약품 분석 중 오류가 발생했습니다.';
      return false;
    } finally {
      _setMedicationSaving(false);
    }
  }

  Future<bool> saveMedicationInfo(MedicationDetail medicationInfo) async {
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    notifyListeners();

    final success = await checkSavedMedication.saveMedicationDetail(
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

  void clearAnalysisResult() {
    _medicationScheduleList = [];
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
    inputPrescription.dispose();
    checkMedicationDetail.dispose();
    checkSavedMedication.dispose();
    super.dispose();
  }
}
