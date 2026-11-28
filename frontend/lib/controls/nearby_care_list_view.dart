// 파일명: nearby_care_list_view.dart
// 역할: 근처 병원·약국 화면의 표시 목록(지도·선택에 쓰는 실시간 결과와 목록 전용 즐겨찾기 스냅샷)을 만드는
//   순수 함수. 화면 상태 없이 입력만으로 결과가 정해져 위젯 없이 검증할 수 있다.

import 'package:geolocator/geolocator.dart';

import '../entities/device_coordinate_entity.dart';
import '../entities/nearby_care_entity.dart';
import '../services/pharmacy_favorite_service.dart';
import 'check_nearby_care_control.dart';

// Class Name: NearbyCareListView
// Role: Display lists derived from the latest results and favorites mode.
// Responsibilities: Keeps live places (map markers, selection, sharing) apart from list-only snapshot favorites.
// Attributes: live: sorted live results; snapshots: favorites outside the results, nearest first.
class NearbyCareListView {
  final List<NearbyCarePlace> live;
  final List<NearbyCarePlace> snapshots;

  // Function Name: NearbyCareListView
  // Description: Pairs the live and snapshot lists.
  // Parameters: live, snapshots: display lists.
  // Returns: A NearbyCareListView.
  const NearbyCareListView(this.live, this.snapshots);

  // Function Name: build
  // Description: Sorts a copy of the results by opening status, late-night operation, favorites and distance, then
  //   applies favorites mode: live favorites (plus a just un-starred selected place) first, and list-only snapshots of
  //   other favorites by distance from the search centre. Chat selection never lists snapshots.
  // Parameters: places: latest results; favoriteIds: saved place IDs; snapshots: saved favorite records by ID;
  //   favoritesOnly: favorites mode; retainedPlaceId: un-starred selected place kept in favorites mode;
  //   selectionMode: chat place sharing; hospitals: provider kind; center: search centre for snapshot distances.
  // Returns: New live and snapshot lists; the inputs are not modified.
  static NearbyCareListView build({
    required List<NearbyCarePlace> places,
    required Set<String> favoriteIds,
    required Map<String, FavoritePlaceSnapshot> snapshots,
    required bool favoritesOnly,
    required bool selectionMode,
    required bool hospitals,
    String? retainedPlaceId,
    DeviceCoordinate? center,
  }) {
    final sorted = sortNearbyCarePlaces(
      places,
      favoriteIds: favoriteIds,
      hospitals: hospitals,
    );
    if (!favoritesOnly) return NearbyCareListView(sorted, const []);
    final live = sorted
        .where(
          (place) =>
              favoriteIds.contains(place.placeId) ||
              place.placeId == retainedPlaceId,
        )
        .toList(growable: false);
    if (selectionMode) return NearbyCareListView(live, const []);
    final liveIds = {for (final place in places) place.placeId};
    final listed =
        snapshots.values
            .where(
              (snapshot) =>
                  favoriteIds.contains(snapshot.placeId) &&
                  !liveIds.contains(snapshot.placeId),
            )
            .map(
              (snapshot) => snapshot.toPlace(
                distanceKm: center == null
                    ? 0
                    : Geolocator.distanceBetween(
                            center.latitude,
                            center.longitude,
                            snapshot.latitude,
                            snapshot.longitude,
                          ) /
                          1000,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.distanceKm.compareTo(right.distanceKm));
    return NearbyCareListView(live, listed);
  }
}
