import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

typedef CaregiverMedicationInfo = ({
  String caregiverHash,
  String patientHash,
  List<MedicationDetail> savedMedications,
  List<MedicationSchedule> todayMedicationScheduleList,
});

// Class Name: CheckCaregiverMedication
// Role: Requests read-only medication information for one linked patient.
class CheckCaregiverMedication {
  final String baseUrl;
  final String caregiverHash;
  final http.Client _client;
  final bool _ownsClient;

  CheckCaregiverMedication({
    this.baseUrl = ApiConfig.baseUrl,
    this.caregiverHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // Function Name: requestPatientMedicationInfo
  // Description:
  // - Requests the medication information of an explicitly selected linked patient.
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    try {
      final normalizedPatientHash =
          PatientHash.normalizePatientHash(patientHash);
      final response = await _client
          .get(
            Uri.parse(
              '$baseUrl/caregiver/medications/'
              '${Uri.encodeComponent(normalizedPatientHash)}',
            ).replace(
              queryParameters: {
                'caregiver_hash':
                    PatientHash.normalizePatientHash(caregiverHash),
              },
            ),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);
      if (response.statusCode != 200) {
        throw StateError(
          'Caregiver medication lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final responseMap = ApiResponseParser.decodeMap(responseBody);
      final rawData = responseMap['data'];
      if (rawData is! Map) {
        throw StateError('Server response did not include medication data.');
      }
      final data = Map<String, dynamic>.from(rawData);
      final todayMedicationInfo = data['today_medication_info'];
      final rawTodaySchedules = todayMedicationInfo is Map
          ? todayMedicationInfo['schedules']
          : todayMedicationInfo;
      return (
        caregiverHash: _readString(
          data['caregiver_hash'] ?? data['guardian_hash'],
        ),
        patientHash: _readString(data['patient_hash']),
        savedMedications: _readSavedMedications(data['saved_medications']),
        todayMedicationScheduleList: MedicationSchedule.fromScheduleJsonList(
          rawTodaySchedules,
        ),
      );
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Caregiver medication request failed.',
        name: 'CheckCaregiverMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Caregiver medication lookup failed.');
    }
  }

  static List<MedicationDetail> _readSavedMedications(dynamic rawItems) {
    if (rawItems is! List) {
      return const [];
    }
    return rawItems
        .whereType<Map>()
        .map(
          (item) => MedicationDetail.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
