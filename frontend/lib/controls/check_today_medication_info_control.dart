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
// - Request today's schedule summary for patient or guardian scope.
// - Decode the response into existing MedicationSchedule entities.
// - Keep scope construction aligned with CheckSchedule and CheckSavedMedication.
class CheckTodayMedicationInfo {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  CheckTodayMedicationInfo({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  CheckTodayMedicationInfo forScope({
    required String patientHash,
    String? userHash,
    String role = 'patient',
  }) {
    return CheckTodayMedicationInfo(
      baseUrl: baseUrl,
      patientHash: PatientHash.normalizePatientHash(patientHash),
      userHash: userHash == null || userHash.trim().isEmpty
          ? null
          : PatientHash.normalizePatientHash(userHash),
      role: role.trim().isEmpty ? 'patient' : role.trim().toLowerCase(),
      client: _client,
    );
  }

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
