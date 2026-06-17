import 'dart:math';

class PatientHash {
  static const String defaultPatientHash = 'local_patient';
  static const int patientLinkCodeLength = 8;
  static const String _patientLinkCodeAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final String patientHash;

  const PatientHash({this.patientHash = defaultPatientHash});

  String generatePatientHash() {
    final random = Random.secure();
    return List.generate(
      patientLinkCodeLength,
      (_) => _patientLinkCodeAlphabet[
          random.nextInt(_patientLinkCodeAlphabet.length)],
    ).join();
  }

  static String normalizePatientHash(String? patientHash) {
    final normalizedPatientHash = patientHash?.trim() ?? '';
    if (normalizedPatientHash.isNotEmpty) {
      return normalizedPatientHash;
    }
    return defaultPatientHash;
  }
}
