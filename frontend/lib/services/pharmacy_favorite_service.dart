// 파일명: pharmacy_favorite_service.dart
// 역할: 사용자가 즐겨찾은 약국 식별자를 기기 저장소에 보관한다.

import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: PharmacyFavoriteService
// 역할: 약국 화면과 채팅 선택 화면이 공유하는 사용자별 즐겨찾기 저장소이다.
// 주요 책임:
// - 빈 식별자를 제외하고 중복 제거·정렬된 약국 ID 목록을 기기에 저장한다.
// 속성:
// - _preferencesLoader (Future<SharedPreferences> Function()): 기기 설정 저장소 제공 경계
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
class PharmacyFavoriteService {
  static const String _storageKeyPrefix = 'medbuddy.favorite_pharmacy_ids';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final String userHash;

  // 함수이름: PharmacyFavoriteService
  // 함수역할: 현재 사용자 범위와 교체 가능한 설정 저장소 로더를 연결해 약국 즐겨찾기를 관리한다.
  // 매개변수:
  // - preferencesLoader (Future<SharedPreferences> Function()?): 기기 설정 저장소 제공 경계
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // 반환값:
  // - PharmacyFavoriteService: 초기화된 인스턴스.
  PharmacyFavoriteService({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.userHash = '',
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  // 함수이름: _storageKey
  // 함수역할: 사용자 해시가 있으면 전용 접미사를 붙이고 없으면 구형 공통 즐겨찾기 키를 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 사용자 해시가 있으면 전용 접미사를 붙이고 없으면 구형 공통 즐겨찾기 키를 사용한다.
  String get _storageKey {
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      return _storageKeyPrefix;
    }
    return '$_storageKeyPrefix.$normalizedUserHash';
  }

  // 함수이름: loadFavoriteIds
  // 함수역할: 기기에 저장된 즐겨찾기 약국 식별자를 중복 없이 불러온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 현재 사용자 범위의 약국 식별자 집합
  Future<Set<String>> loadFavoriteIds() async {
    final preferences = await _preferencesLoader();
    return (preferences.getStringList(_storageKey) ?? const <String>[])
        .map(/* 함수이름: map 콜백
         * 함수역할: 저장된 즐겨찾기 약국 ID의 앞뒤 공백을 제거한다.
         * 매개변수:
         * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
         * 반환값:
         * - 공백 정리된 약국 ID.
         */(value) => value.trim())
        .where(/* 함수이름: where 콜백
         * 함수역할: 저장된 즐겨찾기에서 빈 약국 ID를 제외한다.
         * 매개변수:
         * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
         * 반환값:
         * - 약국 ID가 비어 있지 않으면 true.
         */(value) => value.isNotEmpty)
        .toSet();
  }

  // 함수이름: saveFavoriteIds
  // 함수역할: 즐겨찾기 목록을 정렬해 기기 저장소에 한 번에 반영한다.
  // 매개변수:
  // - pharmacyIds (Set<String>): 즐겨찾기로 저장할 약국 식별자 집합
  // 반환값:
  // - 기기 저장소 반영 성공 여부
  Future<bool> saveFavoriteIds(Set<String> pharmacyIds) async {
    final preferences = await _preferencesLoader();
    final normalizedIds =
        pharmacyIds
            .map(/* 함수이름: map 콜백
             * 함수역할: 저장할 즐겨찾기 약국 ID의 앞뒤 공백을 정리한다.
             * 매개변수:
             * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
             * 반환값:
             * - 공백 정리된 약국 ID.
             */(value) => value.trim())
            .where(/* 함수이름: where 콜백
             * 함수역할: 즐겨찾기 저장 목록에서 빈 약국 ID를 제외한다.
             * 매개변수:
             * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
             * 반환값:
             * - 약국 ID가 비어 있지 않으면 true.
             */(value) => value.isNotEmpty)
            .toList(growable: false)
          ..sort();
    return preferences.setStringList(_storageKey, normalizedIds);
  }
}
