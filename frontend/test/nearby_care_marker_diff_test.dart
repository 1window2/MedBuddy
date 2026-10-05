// 파일명: nearby_care_marker_diff_test.dart
// 역할: 마커 전체 재생성 없이 표시 변경만 반영하는지 검사한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/nearby_care_marker_diff.dart';

// 함수이름: place
// 함수역할: 네트워크 없는 지도 시험 장소를 만든다.
// 매개변수: id/name/latitude/phone: 비교할 장소 속성. 반환값: 합성 장소.
NearbyCarePlace place(
  String id, {
  String? name,
  double latitude = 37.55,
  String phone = '02-000',
}) => NearbyCarePlace(
  placeId: id,
  name: name ?? id,
  address: 'test',
  telephone: phone,
  latitude: latitude,
  longitude: 126.92,
  distanceKm: 0.2,
  todayOpenTime: '09:00',
  todayCloseTime: '18:00',
  isOpenNow: true,
  is24Hours: false,
);

// 함수이름: styles
// 함수역할: 시험 장소를 ID별 표시 속성으로 변환한다.
// 매개변수: places: 장소, selected: 선택 ID, favorites: 즐겨찾기. 반환값: 속성 사전.
Map<String, NearbyCareMarkerStyle> styles(
  List<NearbyCarePlace> places, {
  String? selected,
  Set<String> favorites = const {},
}) => {
  for (final item in places)
    item.placeId: nearbyCareMarkerStyle(
      item,
      selectedId: selected,
      favoriteIds: favorites,
    ),
};

// 함수이름: main
// 함수역할: 선택·즐겨찾기·검색 결과별 마커 갱신 회귀 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수역할: 선택 이동 시 두 ID만 교체하는지 검사한다. 매개변수: 없음. 반환값: 없음.
  test('선택 변경은 기존 선택과 새 선택의 두 마커만 교체한다', () {
    final places = [for (var i = 0; i < 30; i++) place('$i')];
    final delta = NearbyCareMarkerDiff.between(
      styles(places, selected: '1'),
      styles(places, selected: '2'),
    );
    expect(delta.remove, {'1', '2'});
    expect(delta.add, {'1', '2'});
  });

  // 함수역할: 즐겨찾기 하나의 변경이 다른 마커를 건드리지 않는지 검사한다. 매개변수·반환값: 없음.
  test('즐겨찾기 변경은 해당 마커만 교체한다', () {
    final places = [for (var i = 0; i < 30; i++) place('$i')];
    final delta = NearbyCareMarkerDiff.between(
      styles(places),
      styles(places, favorites: {'7'}),
    );
    expect(delta.remove, {'7'});
    expect(delta.add, {'7'});
  });

  // 함수역할: 위치·이름 변화와 표시와 무관한 값의 변경을 구분한다. 매개변수·반환값: 없음.
  test('검색 추가·제거·좌표·이름 변경을 구분하고 순서·연락처 변경은 무시한다', () {
    final before = styles([place('a'), place('b'), place('c')]);
    final delta = NearbyCareMarkerDiff.between(
      before,
      styles([
        place('c', phone: '02-111'),
        place('b', name: 'new', latitude: 37.56),
        place('d'),
      ]),
    );
    expect(delta.remove, {'a', 'b'});
    expect(delta.add, {'b', 'd'});
  });

  // 함수역할: 결과 없음과 반복 조회에서 필요한 제거만 수행하는지 검사한다. 매개변수·반환값: 없음.
  test('빈 결과는 기존 마커만 제거하고 같은 결과는 작업하지 않는다', () {
    final before = styles([place('a')]);
    expect(NearbyCareMarkerDiff.between(before, {}).remove, {'a'});
    expect(NearbyCareMarkerDiff.between(before, {}).add, isEmpty);
    expect(NearbyCareMarkerDiff.between(before, before).remove, isEmpty);
    expect(NearbyCareMarkerDiff.between(before, before).add, isEmpty);
  });
}
