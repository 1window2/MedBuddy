import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_alarm_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../services/notification_service.dart';

// Function Name: NotificationRegistrar
// Description: Defines platform registration of reminders for explicit active dates, with slot identity, localized text, time, and date-specific medication names.
// Parameters:
// - id (int): Platform identifier used to schedule, replace, or cancel an alert.
// - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
// - slotTitle (String): Localized medication slot name.
// - hour (int): Local hour in 24-hour time.
// - minute (int): Minute component of local time.
// - medicationNames (List<String>): Medication display names used in reminders or recommendations.
// - activeDates (List<DateTime>): Reminder dates within the medication course.
// - medicationNamesByDate (Map<String, List<String>>): Active medication names grouped by calendar date.
// - language (String): Language code used for display or speech guidance.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef NotificationRegistrar =
    Future<void> Function({
      required int id,
      required String slotKey,
      required String slotTitle,
      required int hour,
      required int minute,
      required List<String> medicationNames,
      required List<DateTime> activeDates,
      Map<String, List<String>> medicationNamesByDate,
      String language,
    });

// File Name: set_notification_control.dart
// Role: Persists patient alarm settings and delegates dated notification registration to the platform boundary.

// Class Name: SetNotification
// Role: Coordinates patient medication alarm setting requests with the backend.
// Responsibilities:
// - Load patient-scoped medication alarm settings.
// - Save one enabled alarm setting for a medication schedule slot.
// - Disable one alarm setting while preserving the selected time.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
// - _notificationRegistrar (NotificationRegistrar): Boundary for registering dated local reminders.
class SetNotification {
  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;
  final NotificationRegistrar _notificationRegistrar;

  // Function Name: SetNotification
  // Description: Normalizes patient ownership, binds the alarm API client, and selects an injected or shared platform notification registrar.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - patientHash (String): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // - notificationRegistrar (NotificationRegistrar?): Boundary for registering dated local reminders.
  // Returns:
  // - SetNotification: the initialized instance.
  SetNotification({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
    NotificationRegistrar? notificationRegistrar,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null,
       _notificationRegistrar =
           notificationRegistrar ??
           NotificationService.instance.registerNotification;

  // Function Name: requestMedicationAlarm
  // Description: Requests all schedule-slot medication alarm settings.
  // Parameters:
  // - None.
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
            // Function Name: map callback
            // Description: Parses each server reminder entry into a medication alarm.
            // Parameters:
            // - item (Map): Current response or collection entry being transformed or checked.
            // Returns:
            // - The reminder's slot, time, and enabled state.
            (item) => MedicationAlarm.fromJson(Map<String, dynamic>.from(item)),
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
  // Description: Saves and enables one medication alarm setting.
  // Parameters:
  // - slotKey (String): Medication schedule slot key.
  // - hour (int): 24-hour local alarm hour.
  // - minute (int): Local alarm minute.
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
            body: jsonEncode({'hour': hour, 'minute': minute}),
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
  // Description: Passes active course dates and date-specific medication names to the notification registrar, keeping plugin details inside NotificationService.
  // Parameters:
  // - id (int): Platform identifier used to schedule, replace, or cancel an alert.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized medication slot name.
  // - hour (int): Local hour in 24-hour time.
  // - minute (int): Minute component of local time.
  // - medicationNames (List<String>): Medication display names used in reminders or recommendations.
  // - activeDates (List<DateTime>): Reminder dates within the medication course.
  // - medicationNamesByDate (Map<String, List<String>>): Active medication names grouped by calendar date.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) {
    return _notificationRegistrar(
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      medicationNames: medicationNames,
      activeDates: activeDates,
      medicationNamesByDate: medicationNamesByDate,
      language: language,
    );
  }

  // Function Name: disableAlarmSetting
  // Description: Disables one medication alarm setting.
  // Parameters:
  // - slotKey (String): Medication schedule slot key.
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

  // Function Name: _decodeSetting
  // Description: Requires a medication-alarm data map and converts it to the saved alarm entity.
  // Parameters:
  // - responseBody (String): Server response body decoded as UTF-8.
  // Returns:
  // - MedicationAlarm: Requires a medication-alarm data map and converts it to the saved alarm entity.
  MedicationAlarm _decodeSetting(String responseBody) {
    final decodedData = ApiResponseParser.decodeMap(responseBody);
    final rawSetting = decodedData['data'];
    if (rawSetting is Map) {
      return MedicationAlarm.fromJson(Map<String, dynamic>.from(rawSetting));
    }
    throw StateError('Server response did not include a medication alarm.');
  }

  // Function Name: _buildNotificationUri
  // Description: Builds a notification-setting endpoint URI with the normalized patient hash.
  // Parameters:
  // - path (String): Relative path appended to the configured API resource.
  // Returns:
  // - Uri: Builds a notification-setting endpoint URI with the normalized patient hash.
  Uri _buildNotificationUri(String path) {
    return Uri.parse(
      '$baseUrl/$path',
    ).replace(queryParameters: {'patient_hash': patientHash});
  }

  // Function Name: _normalizeSlotKey
  // Description: Trims and lowercases a slot key and rejects keys outside the supported medication schedule slots.
  // Parameters:
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // Returns:
  // - String: Trims and lowercases a slot key and rejects keys outside the supported medication schedule slots.
  String _normalizeSlotKey(String slotKey) {
    final normalizedSlotKey = slotKey.trim().toLowerCase();
    if (!medicationScheduleSlotKeys.contains(normalizedSlotKey)) {
      throw StateError('Medication alarm slot is not supported.');
    }
    return normalizedSlotKey;
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
