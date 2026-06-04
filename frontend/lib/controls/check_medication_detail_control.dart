import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';

class CheckMedicationDetail {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  CheckMedicationDetail({
    this.baseUrl = ApiConfig.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule medicationSchedule,
  ) async {
    final medicationName = medicationSchedule.medicationName.trim();
    if (medicationName.isEmpty) {
      return null;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/identify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'extracted_text': medicationName}),
          )
          .timeout(const Duration(seconds: 60));

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw StateError(
          '약품 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      if (decodedData['success'] != true) {
        return null;
      }

      final medicationDetailList = _decodeMedicationDetailList(
        decodedData['data'],
      );
      return medicationDetailList.isEmpty ? null : medicationDetailList.first;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication detail request failed.',
        name: 'CheckMedicationDetail',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('약품 정보를 불러오지 못했습니다.');
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('서버 응답 형식이 올바르지 않습니다.');
  }

  List<MedicationDetail> _decodeMedicationDetailList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) => MedicationDetail.fromJson(Map<String, dynamic>.from(item)))
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
