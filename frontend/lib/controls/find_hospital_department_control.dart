// 진단 대신 일상 표현과 진료과 이름을 연결하는 기기 내 검색. 검색어는 저장·전송하지 않는다.
// 진료 분야 참고: https://www.seoulmc.or.kr/site/board/medicalguide/medicalInfo/dictionary/healthSearchList.do
// https://www.amc.seoul.kr/asan/departments/deptListTypeA.do
class FindHospitalDepartment {
  static const _terms = <String, List<String>>{
    'D001': [
      '감기',
      '기침',
      '가래',
      '발열',
      '열이나',
      '몸살',
      '배탈',
      '복통',
      '배아',
      '배가아',
      '설사',
      '변비',
      '소화',
      '속쓰',
      '구토',
      '고혈압',
      '당뇨',
      '독감',
      '열나',
      '고열',
      '메스꺼',
      '토했',
      '토해',
      'cough',
      'coughing',
      'cold',
      'flu',
      'fever',
      'stomach',
      'stomachache',
      'diarrhea',
      'diabetes',
    ],
    'D013': [
      '감기',
      '기침',
      '콧물',
      '코막',
      '비염',
      '축농증',
      '목감기',
      '인후통',
      '편도',
      '중이염',
      '귀아',
      '귀가아',
      '이명',
      '난청',
      '코피',
      'ent',
      'cough',
      'cold',
      'throat',
      'earache',
      'ear pain',
      'rhinitis',
      'runny nose',
    ],
    'D022': [
      '감기',
      '몸살',
      '피로',
      '건강검진',
      '가정의학',
      'family doctor',
      'cold',
      'checkup',
      'fatigue',
    ],
    'D002': [
      '소아',
      '아이',
      '어린이',
      '아기',
      '영유아',
      '청소년',
      'pediatric',
      'child',
      'baby',
    ],
    'D008': [
      '무릎',
      '어깨',
      '허리',
      '관절',
      '골절',
      '삐었',
      '접질',
      '염좌',
      '손목',
      '발목',
      '정형',
      '다리아',
      '다리가아',
      'knee',
      'shoulder',
      'back pain',
      'fracture',
      'sprain',
    ],
    'D005': [
      '피부',
      '두드러기',
      '발진',
      '가려',
      '가렵',
      '여드름',
      '습진',
      '아토피',
      '무좀',
      '탈모',
      'skin',
      'rash',
      'itch',
      'itchy',
      'acne',
      'eczema',
    ],
    'D026': [
      '치아',
      '치통',
      '잇몸',
      '충치',
      '사랑니',
      'tooth',
      'teeth',
      'toothache',
      'gum',
      'dentist',
    ],
    'D012': [
      '눈아',
      '눈이아',
      '눈충혈',
      '눈이충혈',
      '시력',
      '결막염',
      '다래끼',
      '안구건조',
      '눈가려',
      'eye',
      'vision',
      'conjunctivitis',
    ],
    'D011': [
      '생리',
      '월경',
      '임신',
      '산전',
      '질염',
      '갱년기',
      'pregnancy',
      'pregnant',
      'menstrual',
      'gynecology',
    ],
    'D003': [
      '두통',
      '편두통',
      '머리아',
      '머리가아',
      '어지러',
      '손저림',
      '발저림',
      '떨림',
      'headache',
      'headaches',
      'migraine',
      'tremor',
      'dizzy',
    ],
    'D004': [
      '불면',
      '잠이안',
      '수면장애',
      '우울',
      '불안',
      '공황',
      '스트레스',
      '정신과',
      'insomnia',
      'depression',
      'depressed',
      'anxiety',
      'panic',
    ],
    'D014': [
      '소변',
      '방광',
      '전립선',
      '요로',
      '배뇨',
      '혈뇨',
      '비뇨의학과',
      'urination',
      'bladder',
      'prostate',
      'urinary',
    ],
    'D006': ['상처', '치질', '탈장', '외과', 'wound', 'hernia', 'hemorrhoid'],
    'D016': ['재활', '물리치료', '운동치료', 'rehabilitation', 'physical therapy'],
    'D017': ['통증클리닉', '만성통증', 'pain clinic', 'chronic pain'],
  };

  // 앞말에 붙은 '많이 아파', '손목 아파', '아이가 아파'를 치아·목 증상으로 읽지 않게 어절 첫머리에서만 찾는다.
  static const _wordStartTerms = <String, List<String>>{
    'D026': ['이아파', '이가아파'],
    'D013': ['목아', '목이아'],
  };

  static final _ignoredCharacters = RegExp(r'[^a-z0-9가-힣ㄱ-ㅎ]');
  static final _asciiTerm = RegExp(r'^[a-z ]+$', caseSensitive: false);
  // 입력할 때마다 호출되므로 한 번 만든 패턴은 다시 컴파일하지 않는다.
  static final _patterns = <String, RegExp>{};

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_ignoredCharacters, '');

  static bool _containsTerm(String query, String normalized, String term) =>
      _asciiTerm.hasMatch(term)
      ? (_patterns[term] ??= RegExp(
          '\\b${term.split(' ').map(RegExp.escape).join(r'\s+')}\\b',
          caseSensitive: false,
        )).hasMatch(query)
      : normalized.contains(term);

  static bool _startsWord(String query, String term) => (_patterns[term] ??=
          RegExp('(?:^|\\s)${term.split('').join(r'\s*')}'))
      .hasMatch(query);

  // 한 증상을 한 진료과로 확정하지 않고 명칭 일치·연관 표현 순으로 여러 결과를 반환한다.
  static List<String> search(
    String query,
    Map<String, (String, String)> departments,
  ) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return [];
    if (needsUrgentHelp(query)) {
      return departments.containsKey('D024') ? ['D024'] : [];
    }
    final scores = <String, int>{};
    for (final entry in departments.entries) {
      if (entry.key.isEmpty) continue;
      var score = 0;
      for (final label in [entry.value.$1, entry.value.$2]) {
        final name = _normalize(label);
        if (name == normalized) {
          score = 1000;
        } else if (name.contains(normalized) ||
            _containsTerm(query, normalized, label)) {
          score = score < 100 ? 100 : score;
        }
      }
      for (final term in _terms[entry.key] ?? const <String>[]) {
        if (_containsTerm(query, normalized, term)) score += 10;
      }
      for (final term in _wordStartTerms[entry.key] ?? const <String>[]) {
        if (_startsWord(query, term)) score += 10;
      }
      if (score > 0) scores[entry.key] = score;
    }
    return scores.keys.toList()..sort((a, b) {
      final score = scores[b]!.compareTo(scores[a]!);
      return score != 0 ? score : a.compareTo(b);
    });
  }

  // 명시적인 응급 표현은 일반 외래 검색으로만 유도하지 않는다.
  static bool needsUrgentHelp(String query) {
    final text = _normalize(query);
    return [
      '숨을못쉬',
      '숨못쉬',
      '숨이안쉬',
      '숨쉬기힘들',
      '숨쉬기어렵',
      '숨을쉴수없',
      '호흡곤란',
      '의식없',
      '의식이없',
      '의식을잃',
      '의식불명',
      '쓰러졌',
      '가슴통증',
      '가슴이아파',
      '가슴이너무아파',
      '가슴이심하게',
      '뇌졸중',
      '심근경색',
      '응급실',
      'chestpain',
      'heartattack',
      'cannotbreathe',
      'cantbreathe',
      'notbreathing',
      'troublebreathing',
      'unconscious',
      'passedout',
    ].any(text.contains);
  }
}
