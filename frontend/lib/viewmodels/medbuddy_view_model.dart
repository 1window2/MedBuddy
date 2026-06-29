import 'package:flutter/material.dart';

import '../controls/check_medication_detail_control.dart';
import '../controls/check_schedule_control.dart';
import '../controls/check_saved_medication_control.dart';
import '../controls/input_prescription_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';

class MedBuddyViewModel extends ChangeNotifier {
  final InputPrescription inputPrescription;
  final CheckMedicationDetail checkMedicationDetail;
  final CheckSavedMedication checkSavedMedication;
  final CheckSchedule checkSchedule;
  CheckSavedMedication? _scopedCheckSavedMedication;
  CheckSchedule? _scopedCheckSchedule;

  String _medicationPatientHash = PatientHash.defaultPatientHash;
  String? _medicationUserHash;
  String _medicationRole = 'patient';
  String get medicationPatientHash => _medicationPatientHash;
  String? get medicationUserHash => _medicationUserHash;
  String get medicationRole => _medicationRole;

  bool _isPrescriptionAnalyzing = false;
  bool get isPrescriptionAnalyzing => _isPrescriptionAnalyzing;
  bool get isLoading => _isPrescriptionAnalyzing;

  int? _savingMedicationIndex;
  int? get savingMedicationIndex => _savingMedicationIndex;
  bool get isMedicationSaving => _savingMedicationIndex != null;

  bool _isSavedMedicationLoading = false;
  bool get isSavedMedicationLoading => _isSavedMedicationLoading;

  bool _isTodayScheduleLoading = false;
  bool get isTodayScheduleLoading => _isTodayScheduleLoading;

  String _statusMessage = '처방전이나 약봉투를 촬영해 주세요.';
  String get statusMessage => _statusMessage;

  List<MedicationSchedule> _medicationScheduleList = [];
  List<MedicationSchedule> get medicationScheduleList =>
      List.unmodifiable(_medicationScheduleList);

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
  })  : inputPrescription = inputPrescription ?? InputPrescription(),
        checkMedicationDetail =
            checkMedicationDetail ?? CheckMedicationDetail(),
        checkSavedMedication = checkSavedMedication ?? CheckSavedMedication(),
        checkSchedule = checkSchedule ?? CheckSchedule();

  void setMedicationAccessScope({
    required String patientHash,
    String? userHash,
    String role = 'patient',
  }) {
    final normalizedPatientHash = PatientHash.normalizePatientHash(patientHash);
    final normalizedUserHash = userHash == null || userHash.trim().isEmpty
        ? null
        : PatientHash.normalizePatientHash(userHash);
    final normalizedRole =
        role.trim().isEmpty ? 'patient' : role.trim().toLowerCase();

    if (_medicationPatientHash == normalizedPatientHash &&
        _medicationUserHash == normalizedUserHash &&
        _medicationRole == normalizedRole) {
      return;
    }

    _medicationPatientHash = normalizedPatientHash;
    _medicationUserHash = normalizedUserHash;
    _medicationRole = normalizedRole;
    _rebuildMedicationScopeControls();
    notifyListeners();
  }

  Future<void> requestPrescriptionImage() async {
    await _requestPrescriptionAnalysis(
      imageRequest: inputPrescription.requestPrescriptionImage,
      analyzingMessage: '서버에서 AI가 처방전을 분석 중입니다...',
      cancelledMessage: '사진 촬영이 취소되었습니다.',
    );
  }

  Future<void> requestPrescriptionImageFromGallery() async {
    await _requestPrescriptionAnalysis(
      imageRequest: inputPrescription.requestPrescriptionImageFromGallery,
      analyzingMessage: '서버에서 AI가 선택한 이미지를 분석 중입니다...',
      cancelledMessage: '이미지 선택이 취소되었습니다.',
    );
  }

  Future<void> _requestPrescriptionAnalysis({
    required Future<List<MedicationSchedule>?> Function() imageRequest,
    required String analyzingMessage,
    required String cancelledMessage,
  }) async {
    _statusMessage = analyzingMessage;
    _setPrescriptionAnalyzing(true);

    try {
      final result = await imageRequest();
      if (result == null) {
        _statusMessage = cancelledMessage;
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
        _statusMessage = '해당 약품 정보를 찾을 수 없습니다.';
        return false;
      }

      return await saveMedicationInfo(
        medicationInfo,
        medicationSchedule: medicationSchedule,
      );
    } on StateError catch (error) {
      _statusMessage = error.message;
      return false;
    } catch (_) {
      _statusMessage = '약품 분석 중 오류가 발생했습니다.';
      return false;
    } finally {
      _setSavingMedicationIndex(null);
    }
  }

  Future<bool> saveMedicationInfo(
    MedicationDetail medicationInfo, {
    MedicationSchedule? medicationSchedule,
  }) async {
    _statusMessage = '${medicationInfo.itemName} 저장 중...';
    notifyListeners();

    final success = await _activeCheckSavedMedication.saveMedicationDetail(
      medicationInfo,
      medicationSchedule: medicationSchedule,
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
          await _activeCheckSavedMedication.requestSavedMedicationInfo();
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
    final success = await _activeCheckSavedMedication.requestDelete(
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

  Future<void> fetchTodayMedicationSchedule() async {
    _isTodayScheduleLoading = true;
    notifyListeners();

    try {
      _todayMedicationScheduleList =
          await _activeCheckSchedule.requestTodayMedicationSchedule();
    } on StateError catch (error) {
      _statusMessage = error.message;
    } catch (_) {
      _statusMessage = 'Schedule lookup failed.';
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
      final updatedSchedule = await _activeCheckSchedule.updateMedicationStatus(
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
      _statusMessage = 'Status update failed.';
      notifyListeners();
      return false;
    }
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

  void _setSavingMedicationIndex(int? value) {
    _savingMedicationIndex = value;
    notifyListeners();
  }

  CheckSavedMedication get _activeCheckSavedMedication =>
      _scopedCheckSavedMedication ?? checkSavedMedication;

  CheckSchedule get _activeCheckSchedule =>
      _scopedCheckSchedule ?? checkSchedule;

  void _rebuildMedicationScopeControls() {
    _scopedCheckSavedMedication?.dispose();
    _scopedCheckSchedule?.dispose();
    _scopedCheckSavedMedication = CheckSavedMedication(
      baseUrl: checkSavedMedication.baseUrl,
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
    _scopedCheckSchedule = CheckSchedule(
      baseUrl: checkSchedule.baseUrl,
      patientHash: _medicationPatientHash,
      userHash: _medicationUserHash,
      role: _medicationRole,
    );
  }

  @override
  void dispose() {
    _scopedCheckSavedMedication?.dispose();
    _scopedCheckSchedule?.dispose();
    inputPrescription.dispose();
    checkMedicationDetail.dispose();
    checkSavedMedication.dispose();
    checkSchedule.dispose();
    super.dispose();
  }
}
