import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drug_info.dart';
import 'dart:developer' as developer;

class ApiService {
  // 에뮬레이터 기준 로컬호스트 주소. (iOS 시뮬레이터는 127.0.0.1 사용)
  final String baseUrl = 'http://localhost:8000/api/v1/medication';

  Future<List<DrugInfo>> identifyMedication(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/identify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'extracted_text': text}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final List<dynamic> items = data['data'];
          return items.map((item) => DrugInfo.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      print('API 통신 에러: $e');
      return [];
    }
  }

  // 약통에 저장 (POST /save)
  Future<bool> saveMedication(DrugInfo drug) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'item_name': drug.itemName,
          'efficacy': drug.efficacy,
          'use_method': drug.useMethod,
          'warning_message': drug.warningMessage,
          'ai_guide': drug.aiGuide,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      developer.log('저장 API 통신 에러: $e', name: 'ApiService');
      return false;
    }
  }

  // 목록 불러오기 (GET /list)
  Future<List<DrugInfo>> getSavedMedications() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/list'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final List<dynamic> items = data['data'];
          return items.map((item) => DrugInfo.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      developer.log('불러오기 API 통신 에러: $e', name: 'ApiService');
      return [];
    }
  }

  // 약통에서 삭제하기 (DELETE /delete)
  Future<bool> deleteMedication(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/delete/$id'));
      return response.statusCode == 200;
    } catch (e) {
      developer.log('삭제 API 통신 에러: $e', name: 'ApiService');
      return false;
    }
  }

  // 처방전 텍스트를 백엔드로 보내서 파싱된 데이터(JSON) 받아오기
  Future<Map<String, dynamic>?> parsePrescription(String ocrText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/parse-prescription'),
        headers: {'Content-Type': 'application/json'},
        // 백엔드의 OCRParseRequest 스키마에 맞춰 'text' 키에 담아 보냄
        body: jsonEncode({'text': ocrText}), 
      );

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (decodedData['success'] == true) {
          // 백엔드에서 정리한 parsed dictinoary 반환
          return decodedData['parsed']; 
        }
      } else {
        developer.log('파싱 실패: 상태 코드 ${response.statusCode}', name: 'ApiService');
      }
      return null;
      
    } catch (e) {
      developer.log('처방전 파싱 API 통신 에러: $e', name: 'ApiService');
      return null;
    }
  }
}
