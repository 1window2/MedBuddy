class PrescriptionParser {
  
  // 개인정보 마스킹 (On-Device)
  static String maskPrivacyInfo(String text) {
    String masked = text;

    // 주민등록번호 마스킹
    masked = masked.replaceAllMapped(RegExp(r'\d{6}\s*-\s*[1-4]\d{6}'), (match) {
      String original = match.group(0)!;
      return '${original.substring(0, 7)}*******';
    });

    // 전화번호 마스킹
    masked = masked.replaceAllMapped(RegExp(r'010\s*-\s*\d{4}\s*-\s*\d{4}'), (match) {
      return '010-****-****';
    });

    // 환자 이름 유추 마스킹
    masked = masked.replaceAllMapped(RegExp(r'([가-힣]{2,4})\s*(님|환자)'), (match) {
      String name = match.group(1)!;
      String suffix = match.group(2)!;
      String maskedName = name[0] + '*' * (name.length - 1);
      return '$maskedName $suffix';
    });

    return masked;
  }

  // 알람용 복약 정보 추출
  static Map<String, dynamic> extractDosageInfo(String text) {
    int? dailyFrequency;
    int? totalDays;

    // 복용 패턴 찾기(주기)
    final freqMatch = RegExp(r'(1일|하루)\s*(\d+)(회|번)').firstMatch(text);
    if (freqMatch != null) {
      dailyFrequency = int.tryParse(freqMatch.group(2)!);
    }

    // 복용 패턴 찾기(기간)
    final daysMatch = RegExp(r'(\d+)\s*(일분|일치)').firstMatch(text);
    if (daysMatch != null) {
      totalDays = int.tryParse(daysMatch.group(1)!);
    }

    return {
      'daily_frequency': dailyFrequency,
      'total_days': totalDays,
    };
  }
}