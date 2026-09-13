import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// File Name: check_schedule_control.dart
// Role: Loads patient medication schedules and persists individual or whole-slot completion changes.

// Class Name: CheckSchedule
// Role: Retrieves medication courses in the patient's schedule and persists completion changes.
// Responsibilities:
// - Scope API requests by patient hash, decode schedule entities, and update individual or entire-slot completion states.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
class CheckSchedule {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckSchedule
  // Description: Normalizes patient ownership and binds schedule reads and completion updates to an injected or owned authenticated client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - CheckSchedule: the initialized instance.
  CheckSchedule({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestTodayMedicationSchedule
  // Description: Requests today's medication schedule scoped to this patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Today's medication schedule list.
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    try {
      final response = await _client
          .get(_buildScheduleUri('schedule/today'))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Schedule lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return _decodeMedicationScheduleList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Today medication schedule request failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Schedule lookup failed.');
    }
  }

  // Function Name: requestMedicationScheduleWindow
  // Description: Requests courses overlapping the rolling reminder window.
  // Parameters:
  // - days (int): Inclusive window length beginning today, up to 14 days.
  // Returns:
  // - Medication courses needed to replenish notifications before they start.
  Future<List<MedicationSchedule>> requestMedicationScheduleWindow({
    int days = 14,
  }) async {
    if (days < 1 || days > 14) {
      throw ArgumentError.value(days, 'days', 'Must be between 1 and 14.');
    }
    try {
      final response = await _client
          .get(_buildScheduleUri('schedule/window', {'days': '$days'}))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Schedule window lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }
      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return _decodeMedicationScheduleList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication schedule window request failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Schedule window lookup failed.');
    }
  }

  // Function Name: updateMedicationStatus
  // Description: Persists one medication completion status.
  // Parameters:
  // - medicationId (String): Saved medication identifier.
  // - medicationStatus (bool): New completion status.
  // - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - Updated MedicationSchedule.
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus, {
    String? slotKey,
  }) async {
    try {
      final response = await _client
          .patch(
            _buildScheduleUri('schedule/$medicationId/status'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'medication_status': medicationStatus,
              if (slotKey != null && slotKey.trim().isNotEmpty)
                'slot_key': slotKey.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Status update failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final rawSchedule = decodedData['data'];
      if (rawSchedule is Map) {
        return MedicationSchedule.fromScheduleJson(
          Map<String, dynamic>.from(rawSchedule),
        );
      }
      throw StateError('Server response did not include an updated schedule.');
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication status update failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Status update failed.');
    }
  }

  // Function Name: updateMedicationSlotStatus
  // Description: Atomically applies one completion state to every medication in a time slot through the backend bulk-update endpoint.
  // Parameters:
  // - slotKey (String): Morning, lunch, evening, or bedtime schedule key.
  // - medicationStatus (bool): Completion state applied to the whole slot.
  // - expectedScheduleDate (String?): ISO dose day to guard delayed actions.
  // Returns:
  // - Updated schedules returned by the backend.
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    final normalizedSlotKey = slotKey.trim().toLowerCase();
    if (!medicationScheduleSlotKeys.contains(normalizedSlotKey)) {
      throw ArgumentError.value(slotKey, 'slotKey', 'Unsupported slot key.');
    }
    try {
      final response = await _client
          .patch(
            _buildScheduleUri('schedule/slot/$normalizedSlotKey/status'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'medication_status': medicationStatus,
              'expected_schedule_date': ?expectedScheduleDate,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Slot status update failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }
      final decodedData = ApiResponseParser.decodeMap(responseBody);
      return _decodeMedicationScheduleList(decodedData['data']);
    } on ArgumentError {
      rethrow;
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication slot status update failed.',
        name: 'CheckSchedule',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Slot status update failed.');
    }
  }

  // Function Name: _decodeMedicationScheduleList
  // Description: Delegates schedule-list decoding and normalization to the shared MedicationSchedule entity parser.
  // Parameters:
  // - rawItems (dynamic): Raw server item or list before model conversion.
  // Returns:
  // - List<MedicationSchedule>: Delegates schedule-list decoding and normalization to the shared MedicationSchedule entity parser.
  List<MedicationSchedule> _decodeMedicationScheduleList(dynamic rawItems) {
    return MedicationSchedule.fromScheduleJsonList(rawItems);
  }

  // Function Name: _buildScheduleUri
  // Description: Builds a schedule endpoint URI with patient ownership and optional window query parameters.
  // Parameters:
  // - path (String): Relative path appended to the configured API resource.
  // - additionalQueryParameters (Map<String, String>): Additional HTTP query fields beyond the ownership scope.
  // Returns:
  // - Uri: Builds a schedule endpoint URI with patient ownership and optional window query parameters.
  Uri _buildScheduleUri(
    String path, [
    Map<String, String> additionalQueryParameters = const {},
  ]) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        ...additionalQueryParameters,
      },
    );
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
