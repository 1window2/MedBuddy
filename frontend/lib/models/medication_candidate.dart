class MedicationCandidate {
  final String drugName;
  final String dosagePerTime;
  final String dailyFrequency;
  final String totalDays;

  const MedicationCandidate({
    required this.drugName,
    required this.dosagePerTime,
    required this.dailyFrequency,
    required this.totalDays,
  });

  factory MedicationCandidate.fromJson(Map<String, dynamic> json) {
    return MedicationCandidate(
      drugName: _readString(json['drug_name']),
      dosagePerTime: _readString(json['dosage_per_time']),
      dailyFrequency: _readString(json['daily_frequency']),
      totalDays: _readString(json['total_days']),
    );
  }

  String get displayName => drugName.isEmpty ? '약품명 확인 필요' : drugName;

  Map<String, dynamic> toJson() {
    return {
      'drug_name': drugName,
      'dosage_per_time': dosagePerTime,
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
    };
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}
