// 파일명: nearby_care_marker_diff.dart
// 역할: 네이티브 지도 호출 없이 변경할 마커 집합을 계산한다.

import '../entities/nearby_care_entity.dart';

// 표시 모양만 비교한다. 전화번호·영업정보 갱신은 마커를 다시 만들 필요가 없다.
typedef NearbyCareMarkerStyle = ({
  String name,
  double latitude,
  double longitude,
  bool selected,
  bool favorite,
});

// 함수이름: nearbyCareMarkerStyle
// 함수역할: 장소와 선택·즐겨찾기 설정에서 표시 속성만 추출한다.
// 매개변수: place: 장소, selectedId: 선택 ID, favoriteIds: 즐겨찾기 ID.
// 반환값: 비교 가능한 마커 표시 record.
NearbyCareMarkerStyle nearbyCareMarkerStyle(
  NearbyCarePlace place, {
  required String? selectedId,
  required Set<String> favoriteIds,
}) => (
  name: place.name,
  latitude: place.latitude,
  longitude: place.longitude,
  selected: place.placeId == selectedId,
  favorite: favoriteIds.contains(place.placeId),
);

// 전체 지도를 비우지 않고 제거·교체·추가할 ID만 계산한다.
// 클래스명: NearbyCareMarkerDiff
// 역할 및 주요 책임: 이전·새 표시 속성의 차이를 계산한다.
// 속성: remove: 지울 ID, add: 추가하거나 교체할 ID.
class NearbyCareMarkerDiff {
  final Set<String> remove;
  final Set<String> add;

  // 함수이름: NearbyCareMarkerDiff.between
  // 함수역할: 마커 ID별 표시 속성을 비교해 변경 집합을 생성한다.
  // 매개변수: previous: 현재 지도 상태, next: 새 상태. 반환값: 변경 집합 객체.
  NearbyCareMarkerDiff.between(
    Map<String, NearbyCareMarkerStyle> previous,
    Map<String, NearbyCareMarkerStyle> next,
  ) : remove = {
        for (final id in previous.keys)
          if (previous[id] != next[id]) id,
      },
      add = {
        for (final id in next.keys)
          if (previous[id] != next[id]) id,
      };
}
