import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/find_hospital_department_control.dart';

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
    test('일상 표현을 관련 과목으로 연결: $query', () {
      expect(
        FindHospitalDepartment.search(query, departments),
        contains(expected),
      );
    });
  }
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
  test('목록에 없는 응급 과목을 결과에 추가하지 않음', () {
    expect(FindHospitalDepartment.search('cannot breathe', const {}), isEmpty);
  });
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
