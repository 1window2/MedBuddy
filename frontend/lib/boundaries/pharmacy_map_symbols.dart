// 파일명: pharmacy_map_symbols.dart
// 역할: 일반·즐겨찾기 약국 마커와 현재 위치 표시를 그린다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

// 클래스명: PharmacyMapPin
// 역할: 일반 또는 즐겨찾기 시설을 표시하는 지도 핀.
// 주요 책임: 고정 비율에서 선택 여부에 따라 크기를 바꾸고 별과 십자를 구별한다.
// 속성: selected/favorite (bool): 강조·즐겨찾기; size/selectedSize (Size): 출력 크기.
class PharmacyMapPin extends StatelessWidget {
  // 함수이름: PharmacyMapPin
  // 함수역할: 선택·즐겨찾기 상태를 보관한다. 반환값: 지도용 핀.
  // 매개변수: key: 위젯 식별자, selected·favorite: 표시 상태.
  const PharmacyMapPin({
    super.key,
    this.selected = false,
    this.favorite = false,
  });
  final bool selected;
  final bool favorite;
  static const favoriteColor = Color(0xFFB87900);
  static const size = Size(28, 40);
  static const selectedSize = Size(35, 50);

  // 함수이름: build
  // 함수역할: 즐겨찾기 색은 선택 여부와 관계없이 유지하고 별 아이콘을 표시한다.
  // 매개변수: context: 화면 환경. 반환값: 일정한 크기의 마커 이미지.
  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: Stack(
      children: [
        CustomPaint(
          size: size,
          painter: _PharmacyPinPainter(
            favorite
                ? favoriteColor
                : (selected
                      ? MedBuddyColors.primaryDark
                      : MedBuddyColors.primary),
            showCross: !favorite,
          ),
        ),
        if (favorite)
          const Positioned(
            top: 5,
            left: 5,
            child: Icon(Icons.star_rounded, size: 18, color: Colors.white),
          ),
      ],
    ),
  );
}

// 클래스명: _PharmacyPinPainter
// 역할: 지도 핀 외곽과 선택적 십자를 그리는 렌더러.
// 주요 책임: 기준 좌표를 출력 크기에 맞춰 확대하고 흰색 테두리를 유지한다.
// 속성: color (Color): 배경; showCross (bool): 십자 표시.
class _PharmacyPinPainter extends CustomPainter {
  // 함수이름: _PharmacyPinPainter
  // 함수역할: 배경색과 십자 표시 여부를 보관한다. 반환값: 핀 렌더러.
  // 매개변수: color: 배경색, showCross: 십자 표시 여부.
  const _PharmacyPinPainter(this.color, {this.showCross = true});
  final Color color;
  final bool showCross;

  // 함수이름: paint
  // 함수역할: 주어진 크기에 핀과 흰색 외곽선을 그리며 별 영역은 비워 둔다.
  // 매개변수: canvas: 그리기 대상, size: 출력 크기. 반환값: 없음.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 40);
    final path = Path()
      ..moveTo(14, 38)
      ..cubicTo(11, 31, 2, 23, 2, 14)
      ..cubicTo(2, -2, 26, -2, 26, 14)
      ..cubicTo(26, 23, 17, 31, 14, 38)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (showCross) {
      canvas.drawLine(const Offset(10, 14), const Offset(18, 14), cross);
      canvas.drawLine(const Offset(14, 10), const Offset(14, 18), cross);
    }
    canvas.restore();
  }

  // 함수이름: shouldRepaint
  // 함수역할: 이전 색·십자 상태와 다르면 다시 그린다. 반환값: 갱신 필요 여부.
  // 매개변수: oldDelegate: 이전 핀 렌더러.
  @override
  bool shouldRepaint(_PharmacyPinPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.showCross != showCross;
}

// 클래스명: PharmacyDeviceLocationDot
// 역할: 시설 검색 핀과 구분되는 현재 기기 위치 점.
// 주요 책임: 파란 중심·흰 테두리·옅은 주변 영역을 고정 크기로 표시한다.
// 속성: size (Size): 네이티브 지도용 30 크기.
class PharmacyDeviceLocationDot extends StatelessWidget {
  // Function Name: PharmacyDeviceLocationDot
  // Description: Initialize the location artwork. Parameters: key identifies the widget.
  // Returns: A fixed-size device location dot.
  const PharmacyDeviceLocationDot({super.key});
  static const size = Size.square(30);

  // 함수이름: build
  // 함수역할: 현재 위치를 파란 중심점·흰 테두리·반투명 정확도 영역으로 표시한다.
  // 매개변수: context (BuildContext): 위젯 표시 문맥.
  // 반환값: 현재 위치 표시 위젯.
  @override
  Widget build(BuildContext context) => Container(
    width: size.width,
    height: size.height,
    padding: const EdgeInsets.all(6),
    decoration: const BoxDecoration(
      color: Color(0x332563EB),
      shape: BoxShape.circle,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
      ),
    ),
  );
}
