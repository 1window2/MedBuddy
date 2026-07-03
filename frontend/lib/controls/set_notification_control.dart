import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_reminder_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// File Name: set_notification_control.dart
// Role: Handles medication alarm API calls.

// Class Name: SetNotification
// Role: Coordinates patient medication alarm setting requests with the backend.
// Responsibilities:
// - Load patient-scoped medication alarm settings.
// - Save one enabled alarm setting for a medication schedule slot.
// - Disable one alarm setting while preserving the selected time.
class SetNotification {
  final String baseUrl;
  final String patientHash;
  final String? userHash;
  final String role;
  final http.Client _client;
  final bool _ownsClient;

  SetNotification({
    this.baseUrl = ApiConfig.baseUrl,
    this.patientHash = PatientHash.defaultPatientHash,
    this.userHash,
    this.role = 'patient',
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // Function Name: forScope
  // Description:
  // - Creates a scoped alarm control that reuses this control's HTTP client.
  // Parameters:
  // - patientHash: Patient scope for medication alarms.
  // - userHash: Optional guardian user scope.
  // - role: Requesting user role.
  // Returns:
  // - SetNotification configured for the selected medication access scope.
  SetNotification forScope({
    required String patientHash,
    String? userHash,
    required String role,
  }) {
    return SetNotification(
      baseUrl: baseUrl,
      patientHash: patientHash,
      userHash: userHash,
      role: role,
      client: _client,
    );
  }

  // Function Name: requestMedicationAlarm
  // Description:
  // - Requests all schedule-slot medication alarm settings.
  // Returns:
  // - MedicationReminderSetting list decoded from the backend response.
  Future<List<MedicationReminderSetting>> requestMedicationAlarm() async {
    try {
      final response = await _client
          .get(_buildNotificationUri('notification/settings'))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Medication alarms lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final rawSettings = decodedData['data'];
      if (rawSettings is! List) {
        return const [];
      }
      return rawSettings
          .whereType<Map>()
          .map(
            (item) => MedicationReminderSetting.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication alarms lookup failed.',
        name: 'SetNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Medication alarms lookup failed.');
    }
  }

  // Function Name: requestAlarmToggle
  // Description:
  // - Reads one slot alarm status before the UI decides whether to show a time picker.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // Returns:
  // - MedicationReminderSetting for the requested slot.
  Future<MedicationReminderSetting> requestAlarmToggle(String slotKey) {
    return getAlarmStatus(slotKey);
  }

  // Function Name: getAlarmStatus
  // Description:
  // - Reads one slot alarm status.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // Returns:
  // - MedicationReminderSetting for the requested slot.
  Future<MedicationReminderSetting> getAlarmStatus(String slotKey) async {
    final normalizedSlotKey = _normalizeSlotKey(slotKey);
    try {
      final response = await _client
          .get(
            _buildNotificationUri('notification/settings/$normalizedSlotKey'),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Medication alarm lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication alarm lookup failed.',
        name: 'SetNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Medication alarm lookup failed.');
    }
  }

  // Function Name: setMedicationAlarm
  // Description:
  // - Saves and enables one medication alarm setting.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // - hour: 24-hour local alarm hour.
  // - minute: Local alarm minute.
  // Returns:
  // - Saved MedicationReminderSetting.
  Future<MedicationReminderSetting> setMedicationAlarm({
    required String slotKey,
    required int hour,
    required int minute,
  }) async {
    final normalizedSlotKey = _normalizeSlotKey(slotKey);
    try {
      final response = await _client
          .put(
            _buildNotificationUri('notification/settings/$normalizedSlotKey'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'hour': hour,
              'minute': minute,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Medication alarm save failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication alarm save failed.',
        name: 'SetNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Medication alarm save failed.');
    }
  }

  // Function Name: disableAlarmSetting
  // Description:
  // - Disables one medication alarm setting.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // Returns:
  // - Disabled MedicationReminderSetting.
  Future<MedicationReminderSetting> disableAlarmSetting(String slotKey) async {
    final normalizedSlotKey = _normalizeSlotKey(slotKey);
    try {
      final response = await _client
          .patch(
            _buildNotificationUri(
              'notification/settings/$normalizedSlotKey/disable',
            ),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Medication alarm disable failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSetting(responseBody);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Medication alarm disable failed.',
        name: 'SetNotification',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Medication alarm disable failed.');
    }
  }

  MedicationReminderSetting _decodeSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return MedicationReminderSetting.fromJson(
        Map<String, dynamic>.from(rawSetting),
      );
    }
    throw StateError('Server response did not include a medication alarm.');
  }

  Uri _buildNotificationUri(String path) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {
        'patient_hash': patientHash,
        'role': role,
        if (userHash != null && userHash!.trim().isNotEmpty)
          'user_hash': userHash!.trim(),
      },
    );
  }

  String _normalizeSlotKey(String slotKey) {
    final normalizedSlotKey = slotKey.trim().toLowerCase();
    if (!medicationScheduleSlotKeys.contains(normalizedSlotKey)) {
      throw StateError('Medication alarm slot is not supported.');
    }
    return normalizedSlotKey;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
