// File Name: prescription_ocr_reading_order_test.dart
// Role: Checks OCR column-to-row ordering using fictional medication text and coordinates.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_ocr_reading_order.dart';

// Function Name: _ordered
// Description: Orders retained OCR lines by their on-screen rows.
// Parameters:
// - lines (List<(String, Rect)>): Text and bounds in recognizer order.
// - masked (Set<int>): Original line indices to exclude; empty by default.
// Returns:
// - List<String>: Unmasked text in resolved reading order.
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

// Function Name: main
// Description:
// - Registers OCR row-order and masked-region regression cases.
// Parameters:
// - None.
// Returns:
// - No value; registers synchronous tests.
void main() {
  // Function Name: test callback
  // Description:
  // - Reassembles medicine, efficacy and dosage columns into row order while retaining independent receipt lines.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
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

  // Function Name: test callback
  // Description:
  // - Keeps a left-panel issue date ahead of the three adjacent right-panel fragments without splitting that medication row.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
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

  // Function Name: test callback
  // Description:
  // - Removes a masked line without reordering the remaining single-column lines and accepts a zero-size rectangle.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('한 열로 쌓인 줄과 가린 줄은 순서를 바꾸지 않고 빼기만 한다', () {
    final lines = <(String, Rect)>[
      for (var row = 0; row < 4; row++)
        ('줄 $row', Rect.fromLTRB(10, row * 20.0, 190, row * 20.0 + 16)),
    ];

    expect(_ordered(lines, masked: {1}), ['줄 0', '줄 2', '줄 3']);
    expect(PrescriptionOcrReadingOrder.order(const [Rect.zero], [0]), [0]);
  });
}
