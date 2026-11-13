// 파일명: find_hospital_department_control_test.dart
// 역할: 일상 증상 표현과 진료과 검색어의 후보 순위·오인식·응급 안내 구분을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/find_hospital_department_control.dart';

// 함수이름: main
// 함수역할:
// - 약어·증상 검색어를 과목 목록에 대조하고 경계 표현·응급 분기 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  const departments = {
    '': ('전체', 'All'),
    'D001': ('내과', 'Internal medicine'),
    'D013': ('이비인후과', 'ENT'),
    'D002': ('소아청소년과', 'Pediatrics'),
    'D022': ('가정의학과', 'Family medicine'),
    'D008': ('정형외과', 'Orthopedics'),
    'D005': ('피부과', 'Dermatology'),
    'D024': ('응급의학과', 'Emergency medicine'),
    'D026': ('치과', 'Dentistry'),
    'D003': ('신경과', 'Neurology'),
  };
  for (final (query, expected) in [
    ('기침이 나요', 'D001'),
    ('감기에 걸렸어요', 'D001'),
    ('기 침!!', 'D013'),
    ('목이 아파요', 'D013'),
    ('무릎이 아파요', 'D008'),
    ('아이 감기', 'D002'),
    ('피부가 가려워요', 'D005'),
    ('COUGH', 'D001'),
    ('a cold', 'D022'),
    ('runny nose', 'D013'),
    ('runny   nose', 'D013'),
    ('ENT', 'D013'),
    ('이가 아파요', 'D026'),
    ('이 아파', 'D026'),
    ('목 아파', 'D013'),
    ('머리가 아파요', 'D003'),
    ('열나요', 'D001'),
    ('toothache', 'D026'),
  ]) {
    // Function Name: test callback
    // Description:
    // - Match Korean and English symptom phrases, spacing variants and abbreviations against the supplied department catalog, including dental and neurology cases.
    // Parameters:
    // - None.
    // Returns:
    // - No value; a failed expectation fails this test.
    test('일상 표현을 관련 과목으로 연결: $query', () {
      expect(
        FindHospitalDepartment.search(query, departments),
        contains(expected),
      );
    });
  }
  // 함수이름: test callback
  // 함수역할:
  // - 정확한 내과 이름은 첫 후보로, 감기는 여러 관련 과목으로 매핑하되 빈 값·무관 단어·단어 내부의 우연한 일치는 제외하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('정확한 과목명 우선, 여러 후보 유지, 알 수 없는 검색어는 비움', () {
    expect(FindHospitalDepartment.search('내과', departments).first, 'D001');
    expect(
      FindHospitalDepartment.search('감기', departments),
      containsAll(['D001', 'D013', 'D022']),
    );
    for (final query in [
      '',
      '  ',
      '???',
      'zxqvw',
      'coldplay',
      'recent',
    ]) {
      expect(FindHospitalDepartment.search(query, departments), isEmpty);
    }
  });
  // Function Name: test callback
  // Description:
  // - Reject false dental matches inside unrelated Korean phrases and false ENT matches where the neck syllable is part of wrist or ankle wording.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('앞말에 붙은 글자를 치아·목 증상으로 읽지 않음', () {
    for (final query in ['배가 많이 아파요', '아이가 아파요', '같이 아파요']) {
      expect(
        FindHospitalDepartment.search(query, departments),
        isNot(contains('D026')),
      );
    }
    for (final query in ['손목 아파요', '발목이 아파요', '손목이 아파요']) {
      expect(
        FindHospitalDepartment.search(query, departments),
        isNot(contains('D013')),
      );
    }
  });
  // 함수이름: test callback
  // 함수역할:
  // - 응급 표현을 검색해도 제공한 과목 목록이 비어 있으면 존재하지 않는 응급 과목 코드를 만들어내지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test('목록에 없는 응급 과목을 결과에 추가하지 않음', () {
    expect(FindHospitalDepartment.search('cannot breathe', const {}), isEmpty);
  });
  // Function Name: test callback
  // Description:
  // - For each explicit urgent phrase, require the urgent-help flag and only the available emergency department, rather than ordinary outpatient candidates.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('명시적 응급 표현은 일반 외래 결과와 구분', () {
    for (final query in [
      '숨을 못 쉬겠어요',
      '숨이 안 쉬어져요',
      '호흡곤란',
      '의식이 없어요',
      '의식을 잃었어요',
      '가슴이 너무 아파요',
      '가슴이 아파요',
      '응급실',
      'cannot breathe',
      'trouble breathing',
      'chest pain',
    ]) {
      expect(FindHospitalDepartment.needsUrgentHelp(query), isTrue);
      expect(FindHospitalDepartment.search(query, departments), ['D024']);
    }
  });
}
