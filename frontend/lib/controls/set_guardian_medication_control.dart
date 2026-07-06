import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../entities/today_medication_info_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

// File Name: set_guardian_medication_control.dart
// Role: Requests guardian-visible medication data.

// Class Name: GuardianMedicationInfo
// Role: Carries medication data a guardian may view for one linked patient.
class GuardianMedicationInfo {
  final String guardianHash;
  final String patientHash;
  final List<MedicationDetail> savedMedications;
  final TodayMedicationInfo todayMedicationInfo;

  const GuardianMedicationInfo({
    required this.guardianHash,
    required this.patientHash,
    required this.savedMedications,
    required this.todayMedicationInfo,
  });

  factory GuardianMedicationInfo.fromJson(Map<String, dynamic> json) {
    return GuardianMedicationInfo(
      guardianHash: _readString(json['guardian_hash'] ?? json['guardianHash']),
      patientHash: _readString(json['patient_hash'] ?? json['patientHash']),
      savedMedications: _readSavedMedications(json['saved_medications']),
      todayMedicationInfo: _readTodayMedicationInfo(
        json['today_medication_info'],
      ),
    );
  }

  static TodayMedicationInfo _readTodayMedicationInfo(dynamic value) {
    if (value is Map) {
      return TodayMedicationInfo.fromJson(Map<String, dynamic>.from(value));
    }
    return const TodayMedicationInfo(
      medicationCount: 0,
      totalDoseCount: 0,
      completedDoseCount: 0,
      remainingDoseCount: 0,
      progressRatio: 0,
      schedules: [],
    );
  }

  static List<MedicationDetail> _readSavedMedications(dynamic rawItems) {
    if (rawItems is! List) {
      return const [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) =>
            MedicationDetail.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.id != null && item.id! > 0)
        .toList(growable: false);
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}

// Class Name: SetGuardianMedication
// Role: Connects guardian medication UI flows to backend guardian scope lookup.
class SetGuardianMedication {
  final String baseUrl;
  final String guardianHash;
  final http.Client _client;
  final bool _ownsClient;

  SetGuardianMedication({
    this.baseUrl = ApiConfig.baseUrl,
    this.guardianHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  SetGuardianMedication forGuardian(String guardianHash) {
    return SetGuardianMedication(
      baseUrl: baseUrl,
      guardianHash: PatientHash.normalizePatientHash(guardianHash),
      client: _client,
    );
  }

  // Function Name: requestGuardianMedication
  // Description:
  // - Requests guardian-visible saved medication and today schedule summary.
  // Parameters:
  // - patientHash: Linked patient ownership key selected by the guardian.
  // Returns:
  // - GuardianMedicationInfo entity.
  Future<GuardianMedicationInfo> requestGuardianMedication({
    required String patientHash,
  }) async {
    try {
      final response = await _client
          .get(_buildGuardianMedicationUri(patientHash))
          .timeout(const Duration(seconds: 30));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Guardian medication lookup failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
      final rawInfo = decodedData['data'];
      if (rawInfo is Map) {
        return GuardianMedicationInfo.fromJson(
          Map<String, dynamic>.from(rawInfo),
        );
      }
      throw StateError('Server response did not include guardian medication.');
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Guardian medication request failed.',
        name: 'SetGuardianMedication',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Guardian medication lookup failed.');
    }
  }

  Uri _buildGuardianMedicationUri(String patientHash) {
    return Uri.parse(
      '$baseUrl/guardian/medications/'
      '${Uri.encodeComponent(PatientHash.normalizePatientHash(patientHash))}',
    ).replace(
      queryParameters: {
        'guardian_hash': PatientHash.normalizePatientHash(guardianHash),
      },
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
