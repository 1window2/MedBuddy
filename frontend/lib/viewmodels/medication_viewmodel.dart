import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
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

  List<dynamic> _parsedDrugList = [];
  List<dynamic> get parsedDrugList => _parsedDrugList;

  // 카메라 연동 객체 및 서버 주소 (for emulator and local connected devices)
  final ImagePicker _picker = ImagePicker();
  final String _apiUrl = 'http://localhost:8000/api/v1/medication/upload-prescription';

  Future<void> processMedicationImage() async {
    // 1. 사진 촬영 (또는 갤러리 선택)
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
    
    if (pickedFile == null) {
      _statusMessage = '사진 촬영이 취소되었습니다.';
      notifyListeners();
      return;
    }

    File imageFile = File(pickedFile.path);

    _setLoading(true);
    _statusMessage = '서버에서 AI가 처방전을 분석 중입니다...';

    try {
      // 2. 백엔드로 사진 파일 직접 쏘기
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final String decodedBody = utf8.decode(response.bodyBytes); // 한글 깨짐 방지

      if (response.statusCode == 200) {
        // 3. 백엔드에서 온 JSON 쪼개서 변수에 담기
        final Map<String, dynamic> data = json.decode(decodedBody);

        _hospitalName = data['hospital_name'] ?? '알 수 없음';
        _prescriptionDate = data['prescription_date'] ?? '알 수 없음';
        _parsedDrugList = data['medications'] ?? [];

        _statusMessage = '분석 완료! 처방 내역을 확인해 주세요.';
        developer.log('분석 성공: ${data['hospital_name']}', name: 'MedicationViewModel');
      } else {
        _statusMessage = '분석 실패 (에러코드: ${response.statusCode})';
        developer.log('에러 응답: $decodedBody', name: 'MedicationViewModel');
      }
    } catch (e) {
      _statusMessage = '서버 연결에 실패했습니다.';
      developer.log('네트워크 에러: $e', name: 'MedicationViewModel');
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
      _statusMessage = '약통에 성공적으로 저장되었습니다!';
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
    String drugName = rawDrug['drug_name']; // 추출된 약품명
    
    // 1. 화면을 로딩 상태로 변경
    _statusMessage = '$drugName 정보를 공공 API와 AI가 분석 중입니다...';
    _setLoading(true); 

    try {
      // 2. 백엔드 /identify API 호출 (공공데이터 + Gemini 요약)
      List<DrugInfo> results = await _apiService.identifyMedication(drugName);

      if (results.isNotEmpty) {
        // 가장 유사도가 높은 첫 번째 검색 결과
        DrugInfo identifiedDrug = results.first;

        // 3. 내 약통 저장 로직 연계
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
      // 4. 로딩 스피너 종료
      _setLoading(false);
    }
  }
}