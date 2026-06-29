import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';

class CheckSavedMedication {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  CheckSavedMedication({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<bool> saveMedicationDetail(
    MedicationDetail medicationDetail, {
    MedicationSchedule? medicationSchedule,
  }) async {
    final savePayload = _buildSaveRequest(
      medicationDetail,
      medicationSchedule,
    );

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(savePayload),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200;
    } catch (error, stackTrace) {
      developer.log(
        'Medication detail save failed.',
        name: 'CheckSavedMedication',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  // Function Name: _buildSaveRequest
  // Description:
  // - Builds the JSON request body for the saved medication API.
  // - Preserves prescription-derived schedule fields when a schedule is present.
  // Parameters:
  // - medicationDetail: Medication detail selected for saving.
  // - medicationSchedule: Optional prescription-analysis schedule for the same item.
  // Returns:
  // - JSON-ready save request map.
  Map<String, dynamic> _buildSaveRequest(
    MedicationDetail medicationDetail,
    MedicationSchedule? medicationSchedule,
  ) {
    final savePayload = medicationDetail.toSaveJson();
    savePayload['patient_hash'] = patientHash;
    savePayload['dosage_per_time'] = _readScheduleValue(
      medicationSchedule?.dosage,
      medicationDetail.dosagePerTime,
    );
    savePayload['daily_frequency'] = _readScheduleValue(
      medicationSchedule?.intakeTime,
      medicationDetail.dailyFrequency,
    );
    savePayload['total_days'] = _readScheduleValue(
      medicationSchedule?.medicationTimeLabel,
      medicationDetail.totalDays,
    );
    return savePayload;
  }

  // Function Name: _readScheduleValue
  // Description:
  // - Prefers prescription schedule text and falls back to existing saved detail text.
  // Parameters:
  // - scheduleValue: Value extracted from prescription analysis.
  // - fallbackValue: Value already present on the medication detail.
  // Returns:
  // - Trimmed non-empty schedule value, fallback value, or an empty string.
  String _readScheduleValue(String? scheduleValue, String fallbackValue) {
    final normalizedScheduleValue = scheduleValue?.trim() ?? '';
    if (normalizedScheduleValue.isNotEmpty) {
      return normalizedScheduleValue;
    }
    return fallbackValue.trim();
  }

  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    try {
      final response = await _client
          .get(_buildMedicationUri('list'))
          .timeout(const Duration(seconds: 30));

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw StateError(
          '저장된 복약 정보 조회 실패 (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      if (decodedData['success'] != true) {
        return [];
      }

      return _decodeSavedMedicationInfoList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication list request failed.',
        name: 'CheckSavedMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('저장된 복약 정보를 불러오지 못했습니다.');
    }
  }

  Future<bool> requestDelete(int savedMedicationId) async {
    try {
      final response = await _client
          .delete(_buildMedicationUri('delete/$savedMedicationId'))
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (error, stackTrace) {
      developer.log(
        'Saved medication delete failed.',
        name: 'CheckSavedMedication',
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
    throw StateError('서버 응답 형식이 올바르지 않습니다.');
  }

  List<MedicationDetail> _decodeSavedMedicationInfoList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) =>
            MedicationDetail.fromJson(Map<String, dynamic>.from(item)))
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

  // Function Name: _buildMedicationUri
  // Description:
  // - Builds a medication API URI with the current patient ownership key.
  // Parameters:
  // - path: API path segment under the medication base URL.
  // Returns:
  // - URI scoped with patient_hash query parameter.
  Uri _buildMedicationUri(String path) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        'role': role,
        if (userHash != null && userHash!.trim().isNotEmpty)
          'user_hash': userHash!.trim(),
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
