import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';

class CheckSchedule {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  CheckSchedule({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // Function Name: requestMedicationSchedule
  // Description:
  // - Class diagram compatible wrapper for today's medication schedule lookup.
  // Returns:
  // - Today's medication schedule list.
  Future<List<MedicationSchedule>> requestMedicationSchedule() {
    return requestTodayMedicationSchedule();
  }

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Requests today's medication schedule scoped to this patient hash.
  // Returns:
  // - Today's medication schedule list.
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    try {
      final response = await _client
          .get(_buildScheduleUri('schedule/today'))
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Schedule lookup failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
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

  // Function Name: updateMedicationStatus
  // Description:
  // - Persists one medication completion status.
  // Parameters:
  // - medicationId: Saved medication identifier.
  // - medicationStatus: New completion status.
  // Returns:
  // - Updated MedicationSchedule.
  Future<MedicationSchedule> updateMedicationStatus(
    String medicationId,
    bool medicationStatus,
  ) async {
    try {
      final response = await _client
          .patch(
            _buildScheduleUri('schedule/$medicationId/status'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'medication_status': medicationStatus}),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Status update failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
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

  List<MedicationSchedule> _decodeMedicationScheduleList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => MedicationSchedule.fromScheduleJson(
            Map<String, dynamic>.from(item),
          ).getTodayMedicationSchedule(),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('Server response format was invalid.');
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

  Uri _buildScheduleUri(String path) {
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
