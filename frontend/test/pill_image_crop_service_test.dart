// 파일명: pill_image_crop_service_test.dart
// 역할: 알약별 원본 영역, EXIF 방향, 입력 상한과 여백 처리를 검증한다.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/services/pill_image_crop_service.dart';

// 함수이름: _twoColors
// 함수역할: 왼쪽 빨강·오른쪽 파랑의 방향 검증용 원본을 만든다.
// 매개변수: 없음. 반환값: 320x160 이미지.
img.Image _twoColors() {
  final image = img.Image(width: 320, height: 160);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  img.fillRect(
    image,
    x1: 160,
    y1: 0,
    x2: 319,
    y2: 159,
    color: img.ColorRgb8(0, 0, 255),
  );
  return image;
}

// 함수이름: main
// 함수역할: 실제 이미지 자르기와 실패 입력을 검증한다. 매개변수: 없음. 반환값: 없음.
void main() {
  const service = PillImageCropService();
  // 함수이름: 원본 영역 테스트
  // 함수역할: 이웃 알약 영역을 제외하는지 검증한다. 매개변수: 없음. 반환값: 검증 완료.
  test('정규화 영역만 자르고 다른 영역은 제외한다', () async {
    final result = await service.cropRegion(
      Uint8List.fromList(img.encodePng(_twoColors())),
      const PillBoundingBox(left: .5, top: 0, width: .5, height: 1),
    );
    final crop = img.decodeJpg(result)!;
    expect(crop.width, 176);
    expect(crop.height, 176);
    expect(crop.getPixel(88, 88).b, greaterThan(200));
    expect(crop.getPixel(88, 88).r, lessThan(30));
  });
  // 함수이름: EXIF 방향 테스트
  // 함수역할: 화면 표시·서버 감지와 같은 보정 방향의 영역을 사용하는지 확인한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('EXIF 회전 뒤의 좌표로 원본을 자른다', () async {
    final image = _twoColors()..exif.imageIfd.orientation = 6;
    final result = await service.cropRegion(
      Uint8List.fromList(img.encodeJpg(image)),
      const PillBoundingBox(left: 0, top: .5, width: 1, height: .5),
    );
    final crop = img.decodeJpg(result)!;
    expect(crop.width, 176);
    expect(crop.height, 176);
    expect(crop.getPixel(88, 88).b, greaterThan(200));
  });
  // 함수이름: 작은 영역 테스트
  // 함수역할: 원본을 확대하지 않고 최소 입력 크기만 흰 여백으로 보완한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('작은 영역은 흰 여백으로 입력 크기를 맞춘다', () async {
    final result = await service.cropRegion(
      Uint8List.fromList(img.encodePng(_twoColors())),
      const PillBoundingBox(left: .75, top: .25, width: .1, height: .2),
    );
    final crop = img.decodeJpg(result)!;
    expect(crop.width, 128);
    expect(crop.height, 128);
    expect(crop.getPixel(64, 64).b, greaterThan(200));
    expect(crop.getPixel(10, 10).r, greaterThan(230));
  });
  // 함수이름: 잘못된 입력 테스트
  // 함수역할: 손상 파일과 영역 초과가 전체 원본 전송으로 우회되지 않게 한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('손상 이미지와 원본 밖 영역을 거부한다', () async {
    await expectLater(
      service.cropRegion(
        Uint8List.fromList([1, 2, 3]),
        const PillBoundingBox(left: 0, top: 0, width: 1, height: 1),
      ),
      throwsFormatException,
    );
    await expectLater(
      service.cropRegion(
        Uint8List.fromList(img.encodePng(_twoColors())),
        const PillBoundingBox(left: .9, top: 0, width: .5, height: 1),
      ),
      throwsFormatException,
    );
  });
}
