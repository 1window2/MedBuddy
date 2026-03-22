import 'package:flutter/material.dart';
import '../models/drug_info.dart';
import '../services/vision_service.dart';
import '../services/api_service.dart';

class MedicationViewModel extends ChangeNotifier {
  final VisionService _visionService = VisionService();
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<DrugInfo> _drugList = [];
  List<DrugInfo> get drugList => _drugList;

  String _statusMessage = '처방전이나 약통을 촬영해주세요.';
  String get statusMessage => _statusMessage;

  // UI에서 버튼을 누를 때 실행될 메인 함수
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

    // 2. 백엔드 API로 텍스트 전송
    _statusMessage = '약 정보를 검색하는 중...';
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
}