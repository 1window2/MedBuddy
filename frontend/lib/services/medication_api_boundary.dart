import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/medication_info.dart';
import '../models/prescription_analysis_result.dart';
import '../models/saved_medication_info.dart';
import 'api_config.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class MedicationAPIBoundary {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  MedicationAPIBoundary({
    this.baseUrl = ApiConfig.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<PrescriptionAnalysisResult> requestPrescriptionAnalysis(
    String imagePath,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload-prescription'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      final streamedResponse = await _client.send(request).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw const ApiException('처방전 분석 요청 시간이 초과되었습니다.');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);
      final decodedBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        final decodedData = _decodeMap(decodedBody);
        return PrescriptionAnalysisResult.fromJson(decodedData);
      }

      throw ApiException(
        '분석 실패 (${response.statusCode}): ${_extractErrorDetail(decodedBody)}',
      );
    } on ApiException {
      rethrow;
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Prescription image file access failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApiException('촬영한 이미지 파일을 읽을 수 없습니다.');
    } catch (error, stackTrace) {
      developer.log(
        'Prescription image upload failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApiException('서버 연결에 실패했습니다.');
    }
  }

  Future<List<MedicationInfo>> requestMedicationInfo(
    String extractedText,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/identify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'extracted_text': extractedText}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw ApiException(
          '약품 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(utf8.decode(response.bodyBytes))}',
        );
      }

      final decodedData = _decodeMap(utf8.decode(response.bodyBytes));
      if (decodedData['success'] == true) {
        return _decodeMedicationInfoList(decodedData['data']);
      }
      return [];
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication identification failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApiException('약품 정보를 불러오지 못했습니다.');
    }
  }

  Future<bool> saveMedicationInfo(MedicationInfo medicationInfo) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(medicationInfo.toSaveJson()),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200;
    } catch (error, stackTrace) {
      developer.log(
        'Medication save failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<List<SavedMedicationInfo>> requestSavedMedicationInfoList() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/list'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw ApiException(
          '저장된 복약 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(utf8.decode(response.bodyBytes))}',
        );
      }

      final decodedData = _decodeMap(utf8.decode(response.bodyBytes));
      if (decodedData['success'] == true) {
        return _decodeSavedMedicationInfoList(decodedData['data']);
      }
      return [];
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication list request failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      throw const ApiException('저장된 복약 정보를 불러오지 못했습니다.');
    }
  }

  Future<bool> requestDeleteSavedMedication(int savedMedicationId) async {
    try {
      final response = await _client
          .delete(Uri.parse('$baseUrl/delete/$savedMedicationId'))
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication delete failed.',
        name: 'MedicationAPIBoundary',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw const ApiException('서버 응답 형식이 올바르지 않습니다.');
  }

  List<MedicationInfo> _decodeMedicationInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) => MedicationInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  List<SavedMedicationInfo> _decodeSavedMedicationInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => SavedMedicationInfo.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((item) => item.id != null && item.id! > 0)
        .toList(growable: false);
  }

  String _extractErrorDetail(String responseBody) {
    try {
      final decodedError = _decodeMap(responseBody);
      if (decodedError['detail'] != null) {
        return decodedError['detail'].toString();
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
