// 파일명: prescription_ocr_reading_order.dart
// 역할: 기기 OCR 줄을 화면에서 보이는 행 순서로 정렬해, 약 이름과 같은 행의 용법이 이어서 전송되게 한다.

import 'dart:ui' show Rect;

// Class Name: PrescriptionOcrReadingOrder
// Role: Orders selected OCR lines using page gutters, row overlap, and visual alignment without changing their text.
// Responsibilities: Keep nearby medication/direction lines together, partition gutters, and align similarly centered rows across panels.
// Attributes: None; ordering is calculated from caller-supplied line rectangles and selected indexes.
class PrescriptionOcrReadingOrder {
  // Function Name: PrescriptionOcrReadingOrder._
  // Description: Restricts this stateless ordering utility to its static API.
  // Parameters: None.
  // Returns: A private utility instance with no state.
  const PrescriptionOcrReadingOrder._();

  // Function Name: order
  // Description: Groups lines by gutter-separated panels and overlapping rows, then aligns similarly centered rows across panels.
  // Parameters: boxes (List<Rect>) - all OCR boxes, including omitted lines used to detect gutters;
  // - keep (List<int>): Valid indexes into boxes for lines to retain.
  // Returns: Retained indexes in visual row/panel/left-to-right order; fewer than two lines or nonpositive median height preserves order.
  // - Invalid indexes or an empty boxes list with multiple retained indexes can throw; input coordinates are not validated here.
  static List<int> order(List<Rect> boxes, List<int> keep) {
    if (keep.length < 2) return List.of(keep);
    final heights = [for (final box in boxes) box.height]..sort();
    final lineHeight = heights[heights.length ~/ 2];
    if (lineHeight <= 0) return List.of(keep);

    // 어떤 줄도 가로지르지 않는 세로 여백이 줄 높이의 두 배 이상이면 패널 경계로 본다.
    final spans = [for (final box in boxes) (box.left, box.right)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final gutters = <double>[];
    var reach = spans.first.$2;
    for (final (left, right) in spans.skip(1)) {
      if (left - reach >= lineHeight * 2) gutters.add((left + reach) / 2);
      if (right > reach) reach = right;
    }
    // Function Name: panelOf
    // Description: Assigns a line to the panel containing its horizontal center.
    // Parameters: box (Rect) - OCR line rectangle.
    // Returns: Number of detected gutter midpoints strictly left of the center.
    int panelOf(Rect box) =>
        gutters.where((gutter) => box.center.dx > gutter).length;

    // 같은 패널에서 행의 첫 줄과 세로로 절반 이상 겹치면 같은 행이다. 행 범위를 넓히지 않아 옆 행으로 번지지 않는다.
    final rows = <({int panel, Rect anchor, List<int> lines})>[];
    final byCenter = List.of(keep)
      ..sort((a, b) {
        final vertical = boxes[a].center.dy.compareTo(boxes[b].center.dy);
        return vertical != 0
            ? vertical
            : boxes[a].left.compareTo(boxes[b].left);
      });
    for (final index in byCenter) {
      final box = boxes[index];
      final panel = panelOf(box);
      ({int panel, Rect anchor, List<int> lines})? best;
      var bestOverlap = 0.0;
      for (final row in rows) {
        if (row.panel != panel) continue;
        final overlap =
            (box.bottom < row.anchor.bottom ? box.bottom : row.anchor.bottom) -
            (box.top > row.anchor.top ? box.top : row.anchor.top);
        final needed =
            (box.height < row.anchor.height ? box.height : row.anchor.height) /
            2;
        if (overlap >= needed && overlap > bestOverlap) {
          best = row;
          bestOverlap = overlap;
        }
      }
      if (best != null) {
        best.lines.add(index);
      } else {
        rows.add((panel: panel, anchor: box, lines: [index]));
      }
    }
    // 열 사이에 걸친 줄이 없으면 열마다 패널이 되므로, 가운데 높이가 거의 같은 다른 패널의 행을 한 화면
    // 행으로 모은다. 겹침이 아니라 가운데 높이로 비교해, 높이가 큰 왼쪽 줄이 아래 행까지 끌어오지 않게 한다.
    final visualRows = <List<({int panel, Rect anchor, List<int> lines})>>[];
    for (final row in rows..sort(
      (a, b) => a.anchor.center.dy.compareTo(b.anchor.center.dy),
    )) {
      final visualRow = visualRows.where(
        (candidate) =>
            (candidate.first.anchor.center.dy - row.anchor.center.dy).abs() <=
                lineHeight * 0.4 &&
            candidate.every((member) => member.panel != row.panel),
      );
      if (visualRow.isEmpty) {
        visualRows.add([row]);
      } else {
        visualRow.first.add(row);
      }
    }
    visualRows.sort(
      (a, b) => a.first.anchor.top.compareTo(b.first.anchor.top),
    );
    return [
      for (final visualRow in visualRows)
        for (final row
            in visualRow..sort((a, b) => a.panel.compareTo(b.panel)))
          ...(row.lines
            ..sort((a, b) => boxes[a].left.compareTo(boxes[b].left))),
    ];
  }
}
