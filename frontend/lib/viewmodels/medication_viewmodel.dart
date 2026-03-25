import 'package:flutter/material.dart';
import '../models/drug_info.dart';
import '../services/vision_service.dart';
import '../services/api_service.dart';
import '../utils/prescription_parser.dart';
import 'dart:developer' as developer;

class MedicationViewModel extends ChangeNotifier {
  final VisionService _visionService = VisionService();
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<DrugInfo> _drugList = [];
  List<DrugInfo> get drugList => _drugList;

  String _statusMessage = '처방전이나 약통을 촬영해주세요.';
  String get statusMessage => _statusMessage;

  // 사진 촬영 버튼 함수
  Future<void> processMedicationImage() async {
    _setLoading(true);
    _statusMessage = '사진에서 글자를 읽는 중...';

    // 1. 사진 촬영 및 OCR 처리
    final extractedText = await _visionService.captureAndRecognizeText();
    
    if (extractedText == null || extractedText.isEmpty) {
      _statusMessage = '글자를 인식하지 못했습니다.';
      _setLoading(false);
      return;
    }

    // backend API call
    _statusMessage = '서버에서 처방전을 분석 중입니다...';
    notifyListeners();

    // backend Parser API call
    final parsedData = await _apiService.parsePrescription(extractedText);
    
    if (parsedData != null) {
      developer.log('✅ 백엔드 파싱 완료: $parsedData', name: 'MedicationViewModel');
      
      final patientName = parsedData['patient_name'] ?? '환자';
      final medicines = parsedData['medicines'] as List<dynamic>? ?? [];
      
      developer.log('환자명: $patientName', name: 'MedicationViewModel');
      developer.log('처방받은 약 개수: ${medicines.length}개', name: 'MedicationViewModel');
      
      // 맞춤형 복약 알람을 위한 데이터 check
      for (var med in medicines) {
        developer.log(' - ${med['name']} (하루 ${med['frequency_per_day']}회, ${med['duration_days']}일치)', name: 'MedicationViewModel');
      }
    } else {
      developer.log('❌ 파싱 실패 또는 추출된 데이터가 없습니다.', name: 'MedicationViewModel');
    }

    // 상세 정보 조회 로직
    _statusMessage = '약 상세 정보를 검색하는 중...';
    notifyListeners();
    
    // extractedText 바로 넘김
    _drugList = await _apiService.identifyMedication(extractedText); 

    if (_drugList.isEmpty) {
      _statusMessage = '해당하는 약 정보를 찾을 수 없습니다.';
    } else {
      _statusMessage = '조회 완료!';
    }

    _setLoading(false);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners(); // UI 갱신 신호 발송
  }

  // '내 약통' 상태 관리 변수
  List<DrugInfo> _savedDrugs = [];
  List<DrugInfo> get savedDrugs => _savedDrugs;

  // 저장 버튼 함수
  Future<bool> saveDrugToPillbox(DrugInfo drug) async {
    _statusMessage = '${drug.itemName} 저장 중...';
    notifyListeners();

    bool success = await _apiService.saveMedication(drug);
    
    if (success) {
      _statusMessage = '약통에 성공적으로 저장되었습니다!';
      await fetchPillbox();   
    } 

    else {
      _statusMessage = '저장에 실패했습니다. 다시 시도해주세요.';
    }

    notifyListeners();
    return success;
  }

  // 저장한 약 목록 fetch
  Future<void> fetchPillbox() async {
    _savedDrugs = await _apiService.getSavedMedications();
    notifyListeners();
  }

  // 저장 목록에서 특정 약 지우기
  Future<void> removeDrugFromPillbox(int id) async {
    bool success = await _apiService.deleteMedication(id);
    if (success) {
      _savedDrugs.removeWhere((drug) => drug.id == id);
      notifyListeners();
    }
  }
}
