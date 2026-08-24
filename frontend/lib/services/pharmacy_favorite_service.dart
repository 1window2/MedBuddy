// 파일명: pharmacy_favorite_service.dart
// 역할: 사용자가 즐겨찾은 약국 식별자를 기기 저장소에 보관한다.

import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: PharmacyFavoriteService
// 역할: 약국 화면과 채팅 선택 화면이 같은 즐겨찾기 목록을 사용하게 한다.
class PharmacyFavoriteService {
  static const String _storageKeyPrefix = 'medbuddy.favorite_pharmacy_ids';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final String userHash;

  PharmacyFavoriteService({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.userHash = '',
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  String get _storageKey {
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      return _storageKeyPrefix;
    }
    return '$_storageKeyPrefix.$normalizedUserHash';
  }

  // 함수명: loadFavoriteIds
  // 역할: 기기에 저장된 즐겨찾기 약국 식별자를 중복 없이 불러온다.
  // 매개변수: 없음
  // 반환값: 현재 사용자 범위의 약국 식별자 집합
  Future<Set<String>> loadFavoriteIds() async {
    final preferences = await _preferencesLoader();
    return (preferences.getStringList(_storageKey) ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  // 함수명: saveFavoriteIds
  // 역할: 즐겨찾기 목록을 정렬해 기기 저장소에 한 번에 반영한다.
  // 매개변수: pharmacyIds - 저장할 약국 식별자 집합
  // 반환값: 기기 저장소 반영 성공 여부
  Future<bool> saveFavoriteIds(Set<String> pharmacyIds) async {
    final preferences = await _preferencesLoader();
    final normalizedIds =
        pharmacyIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
          ..sort();
    return preferences.setStringList(_storageKey, normalizedIds);
  }
}
