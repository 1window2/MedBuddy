// 파일명: nearby_care_list_view_test.dart
// 역할: 근처 병원·약국 표시 목록(실시간 결과와 목록 전용 즐겨찾기 스냅샷)을 만드는 순수 함수를 위젯 없이 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/nearby_care_list_view.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';

// 함수이름: _place
// 함수역할: 검색 결과 하나를 만든다.
// 매개변수: id: 장소 ID; distanceKm: 거리; open: 지금 영업 여부. 반환값: NearbyCarePlace.
NearbyCarePlace _place(String id, double distanceKm, {bool open = true}) =>
    NearbyCarePlace(
      placeId: id,
      name: id,
      address: '',
      telephone: '',
      latitude: 37.55,
      longitude: 126.92,
      distanceKm: distanceKm,
      todayOpenTime: null,
      todayCloseTime: null,
      isOpenNow: open,
      is24Hours: false,
    );

// 함수이름: _snapshot
// 함수역할: 저장한 즐겨찾기 기록 하나를 만든다.
// 매개변수: id: 장소 ID; latitude: 위도(경도 고정). 반환값: FavoritePlaceSnapshot.
FavoritePlaceSnapshot _snapshot(String id, double latitude) =>
    FavoritePlaceSnapshot(
      placeId: id,
      name: id,
      address: '',
      telephone: '',
      latitude: latitude,
      longitude: 126.92,
      savedAt: DateTime(2026, 11, 28),
    );

const _center = DeviceCoordinate(latitude: 37.55, longitude: 126.92);

void main() {
  final places = [
    _place('b', 0.5),
    _place('a', 0.2),
    _place('c', 0.1, open: false),
  ];
  final snapshots = {
    'far': _snapshot('far', 37.65),
    'near': _snapshot('near', 37.56),
    'b': _snapshot('b', 37.55),
    'gone': _snapshot('gone', 37.57),
  };

  NearbyCareListView build({
    bool favoritesOnly = true,
    bool selectionMode = false,
    Set<String> favoriteIds = const {'b', 'far', 'near'},
    String? retained,
  }) => NearbyCareListView.build(
    places: places,
    favoriteIds: favoriteIds,
    snapshots: snapshots,
    favoritesOnly: favoritesOnly,
    selectionMode: selectionMode,
    hospitals: false,
    retainedPlaceId: retained,
    center: _center,
  );

  test('outside favorites mode every result is listed in display order', () {
    final view = build(favoritesOnly: false);
    // 영업 중인 곳이 먼저, 그 안에서는 즐겨찾기(b)가 가까운 곳(a)보다 먼저다.
    expect(view.live.map((place) => place.placeId), ['b', 'a', 'c']);
    expect(view.snapshots, isEmpty);
  });

  test(
    'favorites mode keeps live favorites and lists other favorites nearest first',
    () {
      final view = build();
      expect(view.live.map((place) => place.placeId), ['b']);
      // 결과에 있는 b와 즐겨찾기가 아닌 gone은 스냅샷으로 나오지 않는다.
      expect(view.snapshots.map((place) => place.placeId), ['near', 'far']);
      expect(
        view.snapshots.first.distanceKm,
        lessThan(view.snapshots.last.distanceKm),
      );
      expect(view.snapshots.first.isOpenNow, isNull);
    },
  );

  test('a just un-starred selected place stays listed in favorites mode', () {
    final view = build(favoriteIds: const {'far'}, retained: 'a');
    expect(view.live.map((place) => place.placeId), ['a']);
  });

  test('chat place sharing never offers snapshots', () {
    final view = build(selectionMode: true);
    expect(view.live.map((place) => place.placeId), ['b']);
    expect(view.snapshots, isEmpty);
  });

  test('the inputs are left unmodified', () {
    final input = [_place('z', 0.9), _place('y', 0.1)];
    final view = NearbyCareListView.build(
      places: input,
      favoriteIds: const {},
      snapshots: const {},
      favoritesOnly: false,
      selectionMode: false,
      hospitals: false,
    );
    expect(view.live.map((place) => place.placeId), ['y', 'z']);
    expect(input.map((place) => place.placeId), ['z', 'y']);
  });
}
