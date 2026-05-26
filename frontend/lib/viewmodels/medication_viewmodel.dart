import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/drug_info.dart';
import '../services/api_service.dart';

class MedicationViewModel extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _statusMessage = '처방전이나 약봉투를 촬영해 주세요.';
  String get statusMessage => _statusMessage;

  String _hospitalName = '';
  String get hospitalName => _hospitalName;

  String _prescriptionDate = '';
  String get prescriptionDate => _prescriptionDate;

  List<Map<String, dynamic>> _parsedDrugList = [];
  List<Map<String, dynamic>> get parsedDrugList => _parsedDrugList;

  final ImagePicker _picker = ImagePicker();

  Future<void> processMedicationImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
    );

    if (pickedFile == null) {
      _statusMessage = '사진 촬영이 취소되었습니다.';
      notifyListeners();
      return;
    }

    _statusMessage = '서버에서 AI가 처방전을 분석 중입니다...';
    _setLoading(true);

    try {
      final data = await _apiService.uploadPrescriptionImage(pickedFile.path);

      _hospitalName = _textValue(data['hospital_name'], fallback: '알 수 없음');
      _prescriptionDate = _textValue(
        data['prescription_date'],
        fallback: '알 수 없음',
      );
      _parsedDrugList = _toMedicationCandidates(data['medications']);

      _statusMessage = _parsedDrugList.isEmpty
          ? '분석은 완료됐지만 약품 정보를 찾지 못했습니다.'
          : '분석 완료. 처방 내역을 확인해 주세요.';
    } on ApiException catch (e) {
      _statusMessage = e.message;
    } catch (_) {
      _statusMessage = '서버 연결에 실패했습니다.';
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  List<DrugInfo> _savedDrugs = [];
  List<DrugInfo> get savedDrugs => _savedDrugs;

  Future<bool> saveDrugToPillbox(DrugInfo drug) async {
    _statusMessage = '${drug.itemName} 저장 중...';
    notifyListeners();

    bool success = await _apiService.saveMedication(drug);

    if (success) {
      _statusMessage = '약통에 성공적으로 저장되었습니다.';
      await fetchPillbox();
    } else {
      _statusMessage = '저장에 실패했습니다. 다시 시도해주세요.';
    }

    notifyListeners();
    return success;
  }

  Future<void> fetchPillbox() async {
    _savedDrugs = await _apiService.getSavedMedications();
    notifyListeners();
  }

  Future<void> removeDrugFromPillbox(int id) async {
    bool success = await _apiService.deleteMedication(id);
    if (success) {
      _savedDrugs.removeWhere((drug) => drug.id == id);
      notifyListeners();
    }
  }

  Future<bool> analyzeAndSave(Map<String, dynamic> rawDrug) async {
    final drugName = _textValue(rawDrug['drug_name']).trim();
    if (drugName.isEmpty) {
      _statusMessage = '분석할 약품명이 없습니다.';
      notifyListeners();
      return false;
    }

    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setLoading(true);

    try {
      List<DrugInfo> results = await _apiService.identifyMedication(drugName);

      if (results.isNotEmpty) {
        DrugInfo identifiedDrug = results.first;

        bool isSaved = await saveDrugToPillbox(identifiedDrug);
        return isSaved;
      } else {
        _statusMessage = '해당 약품 정보를 찾을 수 없습니다.';
        return false;
      }
    } catch (e) {
      _statusMessage = '분석 중 오류가 발생했습니다.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  List<Map<String, dynamic>> _toMedicationCandidates(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }

  String _textValue(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
