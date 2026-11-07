// 파일명: nearby_care_marker_diff.dart
// 역할: 네이티브 지도 호출 없이 변경할 마커 집합을 계산한다.

import '../entities/nearby_care_entity.dart';

// 클래스명: NearbyCareMarkerStyle
// 역할: 네이티브 마커 표시를 결정하는 record 타입이다.
// 주요 책임: 전화번호·영업정보 변경은 제외하고 마커 재생성이 필요한 표시 차이만 비교한다.
// 속성: name (String): 표시명; latitude/longitude (double): 좌표; selected/favorite (bool): 강조 상태.
typedef NearbyCareMarkerStyle = ({
  String name,
  double latitude,
  double longitude,
  bool selected,
  bool favorite,
});

// 함수이름: nearbyCareMarkerStyle
// 함수역할: 장소와 선택·즐겨찾기 설정에서 표시 속성만 추출한다.
// 매개변수: place (NearbyCarePlace): 장소; selectedId (String?): 선택 ID; favoriteIds (Set<String>): 즐겨찾기 ID.
// 반환값: NearbyCareMarkerStyle: 비교 가능한 마커 표시 record.
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
// 역할: 전체 지도를 비우지 않고 필요한 마커 변경 집합을 표현한다.
// 주요 책임: 이전·새 표시 속성을 비교해 삭제·교체·추가할 마커 ID를 구분한다.
// 속성: remove (Set<String>): 삭제하거나 교체할 ID; add (Set<String>): 추가하거나 교체할 ID.
class NearbyCareMarkerDiff {
  final Set<String> remove;
  final Set<String> add;

  // 함수이름: NearbyCareMarkerDiff.between
  // 함수역할: 마커 ID별 표시 속성을 비교해 변경 집합을 생성한다.
  // 매개변수: previous/next (Map<String, NearbyCareMarkerStyle>): 현재·새 ID별 마커 표시 상태.
  // 반환값: NearbyCareMarkerDiff: 속성이 변경된 ID는 remove와 add 양쪽에 포함한다.
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
