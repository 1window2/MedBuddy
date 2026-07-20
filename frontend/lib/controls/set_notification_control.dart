import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/notification_service.dart';

typedef NotificationRegistrar = Future<void> Function({
  required int id,
  required String slotKey,
  required String slotTitle,
  required int hour,
  required int minute,
  required List<String> medicationNames,
  String language,
});

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
  final http.Client _client;
  final bool _ownsClient;
  final NotificationRegistrar _notificationRegistrar;

  SetNotification({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
    NotificationRegistrar? notificationRegistrar,
  })  : patientHash = PatientHash.normalizePatientHash(patientHash),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _notificationRegistrar = notificationRegistrar ??
            NotificationService.instance.registerNotification;

  // Function Name: requestMedicationAlarm
  // Description:
  // - Requests all schedule-slot medication alarm settings.
  // Returns:
  // - MedicationAlarm list decoded from the backend response.
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
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
            (item) => MedicationAlarm.fromJson(
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

  // Function Name: saveNotificationSetting
  // Description:
  // - Saves and enables one medication alarm setting.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // - hour: 24-hour local alarm hour.
  // - minute: Local alarm minute.
  // Returns:
  // - Saved MedicationAlarm.
  Future<MedicationAlarm> saveNotificationSetting({
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

  // Function Name: registerNotification
  // Description:
  // - Delegates platform notification registration after the setting is saved.
  // - Keeps the use-case operation in SetNotification while the plugin details
  //   remain isolated in NotificationService.
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    String language = 'ko',
  }) {
    return _notificationRegistrar(
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      medicationNames: medicationNames,
      language: language,
    );
  }

  // Function Name: disableAlarmSetting
  // Description:
  // - Disables one medication alarm setting.
  // Parameters:
  // - slotKey: Medication schedule slot key.
  // Returns:
  // - Disabled MedicationAlarm.
  Future<MedicationAlarm> disableAlarmSetting(String slotKey) async {
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

  MedicationAlarm _decodeSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return MedicationAlarm.fromJson(
        Map<String, dynamic>.from(rawSetting),
      );
    }
    throw StateError('Server response did not include a medication alarm.');
  }

  Uri _buildNotificationUri(String path) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {'patient_hash': patientHash},
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
