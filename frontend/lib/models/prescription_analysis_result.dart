import 'medication_candidate.dart';

class PrescriptionAnalysisResult {
  final String hospitalName;
  final String prescriptionDate;
  final List<MedicationCandidate> medications;

  const PrescriptionAnalysisResult({
    required this.hospitalName,
    required this.prescriptionDate,
    required this.medications,
  });

  factory PrescriptionAnalysisResult.empty() {
    return const PrescriptionAnalysisResult(
      hospitalName: '',
      prescriptionDate: '',
      medications: [],
    );
  }

  factory PrescriptionAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawMedications = json['medications'];
    final medicationList = rawMedications is List
        ? rawMedications
            .whereType<Map>()
            .map(
              (item) => MedicationCandidate.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : <MedicationCandidate>[];

    return PrescriptionAnalysisResult(
      hospitalName: _readString(json['hospital_name']),
      prescriptionDate: _readString(json['prescription_date']),
      medications: medicationList,
    );
  }

  bool get hasMedications => medications.isNotEmpty;

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}
