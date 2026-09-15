import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// File Name: check_today_medication_info_control.dart
// Role: Retrieves the patient-scoped summary of today's medication schedule.

// Class Name: CheckTodayMedicationInfo
// Role: Connects today's medication summary UI flows to the backend control.
// Responsibilities:
// - Request today's schedule summary for one patient.
// - Decode the response into existing MedicationSchedule entities.
// - Keep patient ownership aligned with CheckSchedule.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class CheckTodayMedicationInfo {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckTodayMedicationInfo
  // Description: Normalizes patient ownership and binds today's summary lookup to an injected or owned authenticated client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckTodayMedicationInfo: the initialized instance.
  CheckTodayMedicationInfo({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestTodayMedicationInfo
  // Description: Requests today's medication summary for the current medication scope.
  // Parameters:
  // - None.
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

  // Function Name: _buildTodayInfoUri
  // Description: Builds the dedicated today-summary endpoint URI with the normalized patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Uri: Builds the dedicated today-summary endpoint URI with the normalized patient hash.
  Uri _buildTodayInfoUri() {
    return Uri.parse(
      '$baseUrl/schedule/today/info',
    ).replace(queryParameters: {'patient_hash': patientHash});
  }

  // Function Name: dispose
  // Description: Closes the HTTP client only when this control created it; injected clients remain owned by the caller.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
