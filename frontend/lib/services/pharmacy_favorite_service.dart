// 파일명: pharmacy_favorite_service.dart
// 역할: 사용자가 즐겨찾은 약국·병원 식별자와 목록 표시용 기본 정보를 기기 저장소에 보관한다.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../entities/nearby_care_entity.dart';

// Class Name: FavoritePlaceSnapshot
// Role: List-only record of a favorite place's identity fields, kept so favorites outside the current results can still be listed.
// Responsibilities: Convert to and from stored JSON and live places; never carries operating status, which must come from a fresh search.
// Attributes: placeId: NEMC hpid; name/address/telephone: contact fields; latitude/longitude: last known WGS84 location; savedAt: last write time.
class FavoritePlaceSnapshot {
  final String placeId;
  final String name;
  final String address;
  final String telephone;
  final double latitude;
  final double longitude;
  final DateTime savedAt;

  // Function Name: FavoritePlaceSnapshot
  // Description: Captures the stored identity fields of one favorite place.
  // Parameters: placeId, name, address, telephone, latitude, longitude, savedAt: record fields.
  // Returns: An immutable snapshot.
  const FavoritePlaceSnapshot({
    required this.placeId,
    required this.name,
    required this.address,
    required this.telephone,
    required this.latitude,
    required this.longitude,
    required this.savedAt,
  });

  // Function Name: FavoritePlaceSnapshot.fromPlace
  // Description: Copies the identity fields of a live result; status, hours and departments are deliberately left out.
  // Parameters: place: live search result; savedAt: write time.
  // Returns: A snapshot of the place.
  factory FavoritePlaceSnapshot.fromPlace(
    NearbyCarePlace place,
    DateTime savedAt,
  ) => FavoritePlaceSnapshot(
    placeId: place.placeId,
    name: place.name,
    address: place.address,
    telephone: place.telephone,
    latitude: place.latitude,
    longitude: place.longitude,
    savedAt: savedAt,
  );

  // Function Name: tryParse
  // Description: Reads one stored record and rejects it when the name or coordinates are missing or not finite.
  // Parameters: placeId: storage map key; json: stored value.
  // Returns: The snapshot, or null for an unusable record.
  static FavoritePlaceSnapshot? tryParse(String placeId, Object? json) {
    final id = placeId.trim();
    if (id.isEmpty || json is! Map) return null;
    final name = json['name'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (name is! String ||
        name.trim().isEmpty ||
        latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    final address = json['address'];
    final telephone = json['telephone'];
    final savedAt = json['saved_at'];
    return FavoritePlaceSnapshot(
      placeId: id,
      name: name,
      address: address is String ? address : '',
      telephone: telephone is String ? telephone : '',
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      savedAt:
          (savedAt is String ? DateTime.tryParse(savedAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  // Function Name: toJson
  // Description: Encodes the record for the per-owner snapshot map; the place ID is the map key.
  // Parameters: None.
  // Returns: A JSON-compatible map.
  Map<String, Object> toJson() => {
    'name': name,
    'address': address,
    'telephone': telephone,
    'latitude': latitude,
    'longitude': longitude,
    'saved_at': savedAt.toIso8601String(),
  };

  // Function Name: matches
  // Description: Tells whether a live result still has the stored name, address, telephone and coordinates.
  // Parameters: place: live result with the same ID.
  // Returns: True when no stored field would change.
  bool matches(NearbyCarePlace place) =>
      place.name == name &&
      place.address == address &&
      place.telephone == telephone &&
      place.latitude == latitude &&
      place.longitude == longitude;

  // Function Name: toPlace
  // Description: Builds a list item and focus-search hint whose operating status is unknown.
  // Parameters: distanceKm: distance from the current search centre.
  // Returns: A place with every status field unknown.
  NearbyCarePlace toPlace({double distanceKm = 0}) => NearbyCarePlace(
    placeId: placeId,
    name: name,
    address: address,
    telephone: telephone,
    latitude: latitude,
    longitude: longitude,
    distanceKm: distanceKm,
    todayOpenTime: null,
    todayCloseTime: null,
    isOpenNow: null,
    is24Hours: false,
  );
}

// Class Name: PharmacyFavoriteService
// Role: Store favorite care-provider IDs separately by user and provider kind.
// Responsibilities: Load and persist pharmacy or hospital favorite IDs (the source of truth) and their list-only snapshots using a replaceable preference loader.
// Attributes: userHash (String): owner; hospitals (bool): provider kind; _preferencesLoader: storage boundary; _storageKeyPrefix: pharmacy namespace.
class PharmacyFavoriteService {
  static const String _storageKeyPrefix = 'medbuddy.favorite_pharmacy_ids';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final String userHash;
  final bool hospitals;

  // 함수이름: PharmacyFavoriteService
  // 함수역할: 현재 사용자 범위와 교체 가능한 설정 저장소 로더를 연결해 약국 즐겨찾기를 관리한다.
  // 매개변수:
  // - preferencesLoader (Future<SharedPreferences> Function()?): 기기 설정 저장소 제공 경계
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - hospitals (bool): true이면 병원, false이면 약국 즐겨찾기 저장 공간을 사용한다.
  // 반환값:
  // - PharmacyFavoriteService: 초기화된 인스턴스.
  PharmacyFavoriteService({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.userHash = '',
    this.hospitals = false,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  // Function Name: storageKeyFor
  // Description: Choose a hospital/pharmacy namespace and append the trimmed user hash; blank owners retain the legacy unscoped key.
  // Parameters: userHash (String): owner; hospitals (bool): hospital instead of pharmacy namespace.
  // Returns: String: favorite-ID storage key.
  static String storageKeyFor(String userHash, {required bool hospitals}) {
    final prefix = hospitals
        ? 'medbuddy.favorite_hospital_ids'
        : _storageKeyPrefix;
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      return prefix;
    }
    return '$prefix.$normalizedUserHash';
  }

  // Function Name: snapshotStorageKeyFor
  // Description: Chooses the hospital/pharmacy snapshot namespace and appends the trimmed user hash; blank owners keep the unscoped name, as storageKeyFor does.
  // Parameters: userHash (String): owner; hospitals (bool): hospital instead of pharmacy namespace.
  // Returns: String: favorite-snapshot storage key.
  static String snapshotStorageKeyFor(
    String userHash, {
    required bool hospitals,
  }) {
    final prefix = hospitals
        ? 'medbuddy.favorite_hospital_places'
        : 'medbuddy.favorite_pharmacy_places';
    final normalizedUserHash = userHash.trim();
    if (normalizedUserHash.isEmpty) {
      return prefix;
    }
    return '$prefix.$normalizedUserHash';
  }

  // Function Name: refreshedSnapshots
  // Description: Writes a snapshot for each favorite in the results that has none (a legacy ID-only favorite) or whose stored fields changed.
  // Parameters: current: loaded snapshots; places: live results; favoriteIds: saved IDs; now: write time.
  // Returns: The updated map, or null when nothing changed so callers can skip the write.
  static Map<String, FavoritePlaceSnapshot>? refreshedSnapshots(
    Map<String, FavoritePlaceSnapshot> current,
    Iterable<NearbyCarePlace> places,
    Set<String> favoriteIds,
    DateTime now,
  ) {
    Map<String, FavoritePlaceSnapshot>? updated;
    for (final place in places) {
      if (!favoriteIds.contains(place.placeId) || place.name.trim().isEmpty) {
        continue;
      }
      final stored = current[place.placeId];
      if (stored != null && stored.matches(place)) continue;
      (updated ??= Map.of(current))[place.placeId] =
          FavoritePlaceSnapshot.fromPlace(place, now);
    }
    return updated;
  }

  // Function Name: _storageKey
  // Description: Resolve this instance's owner- and provider-specific favorite key.
  // Parameters: None.
  // Returns: String: preference key.
  String get _storageKey => storageKeyFor(userHash, hospitals: hospitals);

  // Function Name: _snapshotStorageKey
  // Description: Resolves this instance's owner- and provider-specific snapshot key.
  // Parameters: None.
  // Returns: String: preference key.
  String get _snapshotStorageKey =>
      snapshotStorageKeyFor(userHash, hospitals: hospitals);

  // Function Name: loadSnapshots
  // Description: Reads the stored snapshots, drops unreadable records and those whose ID is no longer a favorite, and writes the pruned map back when anything was dropped.
  // Parameters: favoriteIds (Set<String>): the ID list, which stays the source of truth.
  // Returns: Snapshots keyed by place ID; unreadable stored JSON counts as no snapshots. Storage failures propagate.
  Future<Map<String, FavoritePlaceSnapshot>> loadSnapshots(
    Set<String> favoriteIds,
  ) async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(_snapshotStorageKey);
    if (raw == null) return {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    final snapshots = <String, FavoritePlaceSnapshot>{};
    var dropped = decoded is! Map;
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final key = entry.key;
        final snapshot = key is String
            ? FavoritePlaceSnapshot.tryParse(key, entry.value)
            : null;
        if (snapshot == null || !favoriteIds.contains(snapshot.placeId)) {
          dropped = true;
          continue;
        }
        snapshots[snapshot.placeId] = snapshot;
      }
    }
    if (dropped) await saveSnapshots(snapshots);
    return snapshots;
  }

  // Function Name: saveSnapshots
  // Description: Replaces the stored snapshot map in place-ID order; an empty map removes the key.
  // Parameters: snapshots (Map<String, FavoritePlaceSnapshot>): records keyed by place ID.
  // Returns: Whether the storage write succeeded.
  Future<bool> saveSnapshots(
    Map<String, FavoritePlaceSnapshot> snapshots,
  ) async {
    final preferences = await _preferencesLoader();
    if (snapshots.isEmpty) {
      return preferences.remove(_snapshotStorageKey);
    }
    final ids = snapshots.keys.toList(growable: false)..sort();
    return preferences.setString(
      _snapshotStorageKey,
      jsonEncode({for (final id in ids) id: snapshots[id]!.toJson()}),
    );
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
        .map(
          /* 함수이름: map 콜백
         * 함수역할: 저장된 즐겨찾기 약국 ID의 앞뒤 공백을 제거한다.
         * 매개변수:
         * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
         * 반환값:
         * - 공백 정리된 약국 ID.
         */
          (value) => value.trim(),
        )
        .where(
          /* 함수이름: where 콜백
         * 함수역할: 저장된 즐겨찾기에서 빈 약국 ID를 제외한다.
         * 매개변수:
         * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
         * 반환값:
         * - 약국 ID가 비어 있지 않으면 true.
         */
          (value) => value.isNotEmpty,
        )
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
            .map(
              /* 함수이름: map 콜백
             * 함수역할: 저장할 즐겨찾기 약국 ID의 앞뒤 공백을 정리한다.
             * 매개변수:
             * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
             * 반환값:
             * - 공백 정리된 약국 ID.
             */
              (value) => value.trim(),
            )
            .where(
              /* 함수이름: where 콜백
             * 함수역할: 즐겨찾기 저장 목록에서 빈 약국 ID를 제외한다.
             * 매개변수:
             * - value (String): 공백·빈 값을 정리할 즐겨찾기 약국 ID
             * 반환값:
             * - 약국 ID가 비어 있지 않으면 true.
             */
              (value) => value.isNotEmpty,
            )
            .toList(growable: false)
          ..sort();
    return preferences.setStringList(_storageKey, normalizedIds);
  }
}
