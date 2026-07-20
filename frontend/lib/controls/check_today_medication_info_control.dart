import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// File Name: check_today_medication_info_control.dart
// Role: Requests today's medication summary from the backend.

// Class Name: CheckTodayMedicationInfo
// Role: Connects today's medication summary UI flows to the backend control.
// Responsibilities:
// - Request today's schedule summary for one patient.
// - Decode the response into existing MedicationSchedule entities.
// - Keep patient ownership aligned with CheckSchedule.
class CheckTodayMedicationInfo {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  CheckTodayMedicationInfo({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : patientHash = PatientHash.normalizePatientHash(patientHash),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  // Function Name: requestTodayMedicationInfo
  // Description:
  // - Requests today's medication summary for the current medication scope.
  // Returns:
  // - MedicationSchedule list from the summary payload.
  Future<List<MedicationSchedule>> requestTodayMedicationInfo() async {
    try {
      final response = await _client
          .get(_buildTodayInfoUri())
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Today medication info lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return MedicationSchedule.fromScheduleJsonList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Today medication info request failed.',
        name: 'CheckTodayMedicationInfo',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Today medication info lookup failed.');
    }
  }

  Uri _buildTodayInfoUri() {
    return Uri.parse('$baseUrl/schedule/today/info').replace(
      queryParameters: {'patient_hash': patientHash},
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
