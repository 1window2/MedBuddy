// 파일명: prescription_ocr_reading_order_test.dart
// 역할: 열 단위로 인식된 약봉투 줄이 화면의 행 순서로 정렬되는지 검증한다. 약 이름과 수치는 가상 예시다.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_ocr_reading_order.dart';

// 함수이름: _ordered
// 함수역할: (글자, 좌표) 목록을 인식기 순서대로 받아 정렬한 글자 목록을 돌려준다.
List<String> _ordered(List<(String, Rect)> lines, {Set<int> masked = const {}}) {
  final keep = [
    for (var index = 0; index < lines.length; index++)
      if (!masked.contains(index)) index,
  ];
  return [
    for (final index in PrescriptionOcrReadingOrder.order([
      for (final line in lines) line.$2,
    ], keep))
      lines[index].$1,
  ];
}

void main() {
  test('약 이름·효능·용법 열이 따로 인식돼도 같은 행끼리 이어진다', () {
    // 인식기는 왼쪽 영수증, 약 이름 열, 용법 열을 각각 블록으로 돌려준다.
    final lines = <(String, Rect)>[
      ('본인부담금 3,000원', const Rect.fromLTRB(10, 170, 260, 186)),
      ('사업장소재지 가상시 가상로 1', const Rect.fromLTRB(10, 300, 270, 318)),
      ('가나정10mg', const Rect.fromLTRB(400, 174, 500, 190)),
      ('다라정', const Rect.fromLTRB(400, 290, 470, 304)),
      ('코팅정', const Rect.fromLTRB(400, 330, 440, 344)),
      ('마바캡슐', const Rect.fromLTRB(400, 360, 480, 376)),
      ('[해열진통제]', const Rect.fromLTRB(535, 176, 700, 190)),
      ('흰색의 원형 필름', const Rect.fromLTRB(400, 312, 760, 326)),
      ('[진해거담제]', const Rect.fromLTRB(530, 288, 690, 304)),
      ('[비염약]', const Rect.fromLTRB(535, 358, 640, 377)),
      ('1정씩3회5일분', const Rect.fromLTRB(760, 176, 830, 188)),
      ('1정씩2회5일분', const Rect.fromLTRB(760, 290, 830, 302)),
      ('0.5정씩3회5일분', const Rect.fromLTRB(760, 361, 840, 373)),
    ];

    expect(_ordered(lines), [
      '본인부담금 3,000원',
      '가나정10mg',
      '[해열진통제]',
      '1정씩3회5일분',
      '다라정',
      '[진해거담제]',
      '1정씩2회5일분',
      '사업장소재지 가상시 가상로 1',
      '흰색의 원형 필름',
      '코팅정',
      '마바캡슐',
      '[비염약]',
      '0.5정씩3회5일분',
    ]);
  });

  test('세로 여백으로 나뉜 패널의 줄은 같은 높이여도 한 행에 넣지 않는다', () {
    final lines = <(String, Rect)>[
      ('발행일 2026-10-26', const Rect.fromLTRB(60, 388, 170, 405)),
      ('가나정', const Rect.fromLTRB(400, 398, 465, 414)),
      ('[효능]', const Rect.fromLTRB(535, 396, 636, 415)),
      ('1정씩1회3일분', const Rect.fromLTRB(760, 399, 830, 410)),
    ];

    // 왼쪽 발행일이 먼저 나오고, 오른쪽 행의 세 줄은 떨어지지 않는다.
    expect(_ordered(lines), [
      '발행일 2026-10-26',
      '가나정',
      '[효능]',
      '1정씩1회3일분',
    ]);
  });

  test('한 열로 쌓인 줄과 가린 줄은 순서를 바꾸지 않고 빼기만 한다', () {
    final lines = <(String, Rect)>[
      for (var row = 0; row < 4; row++)
        ('줄 $row', Rect.fromLTRB(10, row * 20.0, 190, row * 20.0 + 16)),
    ];

    expect(_ordered(lines, masked: {1}), ['줄 0', '줄 2', '줄 3']);
    expect(PrescriptionOcrReadingOrder.order(const [Rect.zero], [0]), [0]);
  });
}
