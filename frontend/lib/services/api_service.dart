import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/drug_info.dart';
import 'api_config.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, dynamic>> uploadPrescriptionImage(String imagePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.uploadPrescriptionUrl),
      );
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw const ApiException('처방전 분석 요청 시간이 초과되었습니다.');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);
      final decodedBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(decodedBody);
        if (data is Map<String, dynamic>) {
          return data;
        }
        throw const ApiException('서버 응답 형식이 올바르지 않습니다.');
      }

      throw ApiException(
        '분석 실패 (${response.statusCode}): ${_extractErrorDetail(decodedBody)}',
      );
    } on ApiException {
      rethrow;
    } on FileSystemException catch (e) {
      developer.log('이미지 파일 접근 에러: $e', name: 'ApiService');
      throw const ApiException('촬영한 이미지 파일을 읽을 수 없습니다.');
    } catch (e) {
      developer.log('처방전 이미지 업로드 에러: $e', name: 'ApiService');
      throw const ApiException('서버 연결에 실패했습니다.');
    }
  }

  Future<List<DrugInfo>> identifyMedication(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/identify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'extracted_text': text}),
      ).timeout(const Duration(seconds: 60), onTimeout: () {
        throw Exception('서버 응답 시간이 초과되었습니다.');
      });

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic> && data['success'] == true) {
          return _decodeDrugInfoList(data['data']);
        }
      }
      return [];
    } catch (e) {
      developer.log('API 통신 에러: $e', name: 'ApiService');
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
      ).timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      developer.log('저장 API 통신 에러: $e', name: 'ApiService');
      return false;
    }
  }

  // 목록 불러오기 (GET /list)
  Future<List<DrugInfo>> getSavedMedications() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/list'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic> && data['success'] == true) {
          return _decodeDrugInfoList(data['data']);
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
      final response = await http
          .delete(Uri.parse('$baseUrl/delete/$id'))
          .timeout(const Duration(seconds: 30));
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(utf8.decode(response.bodyBytes));

        if (decodedData is Map<String, dynamic> &&
            decodedData['success'] == true &&
            decodedData['parsed'] is Map) {
          // 백엔드에서 정리한 parsed dictionary 반환
          return Map<String, dynamic>.from(decodedData['parsed']);
        }
      } else {
        developer.log(
          '파싱 실패: 상태 코드 ${response.statusCode}',
          name: 'ApiService',
        );
      }
      return null;
    } catch (e) {
      developer.log('처방전 파싱 API 통신 에러: $e', name: 'ApiService');
      return null;
    }
  }

  List<DrugInfo> _decodeDrugInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) => DrugInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  String _extractErrorDetail(String responseBody) {
    try {
      final dynamic errorBody = jsonDecode(responseBody);
      if (errorBody is Map<String, dynamic> && errorBody['detail'] != null) {
        return errorBody['detail'].toString();
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
  }
}
