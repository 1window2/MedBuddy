// 파일명: pharmacy_favorite_service_test.dart
// 역할: 즐겨찾기 약국 목록의 정규화와 기기 저장 규칙을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 함수이름: main
// 함수역할:
// - 약국 즐겨찾기 정규화와 사용자별 격리 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 테스트 전에 메모리 설정 저장소를 비워 사용자 캐시를 격리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 설정 저장소가 빈 상태로 초기화된다.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 저장된 즐겨찾기 식별자는 공백과 중복을 제거해 불러온다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('저장된 즐겨찾기 식별자는 공백과 중복을 제거해 불러온다', () async {
    SharedPreferences.setMockInitialValues({
      'medbuddy.favorite_pharmacy_ids': [
        ' pharmacy-b ',
        'pharmacy-a',
        'pharmacy-a',
        '',
      ],
    });
    final service = PharmacyFavoriteService();

    final favorites = await service.loadFavoriteIds();

    expect(favorites, {'pharmacy-a', 'pharmacy-b'});
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 즐겨찾기 식별자는 정규화한 뒤 일정한 순서로 저장한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('즐겨찾기 식별자는 정규화한 뒤 일정한 순서로 저장한다', () async {
    final service = PharmacyFavoriteService();

    final saved = await service.saveFavoriteIds({
      ' pharmacy-b ',
      'pharmacy-a',
      '',
    });
    final preferences = await SharedPreferences.getInstance();

    expect(saved, isTrue);
    expect(preferences.getStringList('medbuddy.favorite_pharmacy_ids'), [
      'pharmacy-a',
      'pharmacy-b',
    ]);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 같은 기기의 사용자별 즐겨찾기 목록은 서로 섞이지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('같은 기기의 사용자별 즐겨찾기 목록은 서로 섞이지 않는다', () async {
    final preferences = await SharedPreferences.getInstance();
    final patientService = PharmacyFavoriteService(
      userHash: 'patient_test',
      // 함수이름: preferencesLoader 콜백
      // 함수역할:
      // - 사용자별 즐겨찾기 키를 비교하도록 같은 메모리 설정 저장소를 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 기존 SharedPreferences 인스턴스.
      preferencesLoader: () async => preferences,
    );
    final caregiverService = PharmacyFavoriteService(
      userHash: 'caregiver_test',
      // 함수이름: preferencesLoader 콜백
      // 함수역할:
      // - 사용자별 즐겨찾기 키를 비교하도록 같은 메모리 설정 저장소를 제공한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 기존 SharedPreferences 인스턴스.
      preferencesLoader: () async => preferences,
    );

    await patientService.saveFavoriteIds({'pharmacy-a'});
    await caregiverService.saveFavoriteIds({'pharmacy-b'});

    expect(await patientService.loadFavoriteIds(), {'pharmacy-a'});
    expect(await caregiverService.loadFavoriteIds(), {'pharmacy-b'});
  });

  // Function Name: test callback
  // Description: Snapshot keys follow the ID-key scoping, including the unscoped name for a blank owner.
  // Parameters: None.
  // Returns: void.
  test('snapshot keys are scoped like the ID keys', () {
    expect(
      PharmacyFavoriteService.snapshotStorageKeyFor(
        ' usr_a ',
        hospitals: false,
      ),
      'medbuddy.favorite_pharmacy_places.usr_a',
    );
    expect(
      PharmacyFavoriteService.snapshotStorageKeyFor('usr_a', hospitals: true),
      'medbuddy.favorite_hospital_places.usr_a',
    );
    expect(
      PharmacyFavoriteService.snapshotStorageKeyFor('  ', hospitals: false),
      'medbuddy.favorite_pharmacy_places',
    );
    expect(
      PharmacyFavoriteService.snapshotStorageKeyFor('', hospitals: true),
      'medbuddy.favorite_hospital_places',
    );
  });

  // Function Name: test callback
  // Description: A saved snapshot map round-trips, and an empty map removes the key.
  // Parameters: None.
  // Returns: Future<void>.
  test('snapshots round-trip and an empty map removes the key', () async {
    final service = PharmacyFavoriteService(userHash: 'usr_a', hospitals: true);
    final savedAt = DateTime.utc(2026, 11, 28, 9);
    expect(
      await service.saveSnapshots({'h1': _snapshot('h1', savedAt: savedAt)}),
      isTrue,
    );
    final loaded = await service.loadSnapshots({'h1'});
    expect(loaded.keys, ['h1']);
    final h1 = loaded['h1']!;
    expect(h1.name, '메드버디의원 h1');
    expect(h1.address, '서울 h1');
    expect(h1.telephone, '02-000-0000');
    expect(h1.latitude, 37.5);
    expect(h1.longitude, 127.0);
    expect(h1.savedAt, savedAt);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('medbuddy.favorite_hospital_places.usr_a'),
      isTrue,
    );
    // Pharmacy snapshots of the same owner are a separate namespace.
    expect(
      await PharmacyFavoriteService(userHash: 'usr_a').loadSnapshots({'h1'}),
      isEmpty,
    );
    await service.saveSnapshots({});
    expect(
      preferences.containsKey('medbuddy.favorite_hospital_places.usr_a'),
      isFalse,
    );
  });

  // Function Name: test callback
  // Description: Loading prunes snapshots whose ID is no longer a favorite and unreadable records, and writes the pruned map back.
  // Parameters: None.
  // Returns: Future<void>.
  test(
    'loading prunes snapshots against the ID list and writes back',
    () async {
      SharedPreferences.setMockInitialValues({
        'medbuddy.favorite_pharmacy_places': jsonEncode({
          'kept': _snapshot('kept').toJson(),
          'unstarred': _snapshot('unstarred').toJson(),
          'broken': {'name': '', 'latitude': 'x'},
        }),
      });
      final service = PharmacyFavoriteService();
      final loaded = await service.loadSnapshots({'kept', 'broken'});
      expect(loaded.keys, ['kept']);
      final preferences = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(
                preferences.getString('medbuddy.favorite_pharmacy_places')!,
              )
              as Map<String, dynamic>;
      expect(stored.keys, ['kept']);
      // Unreadable JSON counts as no snapshots instead of a storage failure.
      await preferences.setString('medbuddy.favorite_pharmacy_places', '{');
      expect(await service.loadSnapshots({'kept'}), isEmpty);
      expect(
        preferences.containsKey('medbuddy.favorite_pharmacy_places'),
        isFalse,
      );
    },
  );

  // Function Name: test callback
  // Description: Results refresh a snapshot only for favorites whose stored fields changed or that have none yet (legacy ID-only favorites).
  // Parameters: None.
  // Returns: void.
  test('results refresh snapshots only when a field changes', () {
    final earlier = DateTime.utc(2026, 11, 1);
    final now = DateTime.utc(2026, 11, 28);
    final current = {
      'same': _snapshot('same', savedAt: earlier),
      'moved': _snapshot('moved', savedAt: earlier),
    };
    final unchanged = PharmacyFavoriteService.refreshedSnapshots(
      current,
      [_snapshot('same').toPlace(), _snapshot('other').toPlace()],
      {'same', 'moved'},
      now,
    );
    expect(unchanged, isNull);
    final moved = _snapshot('moved').toPlace();
    final updated = PharmacyFavoriteService.refreshedSnapshots(
      current,
      [
        _snapshot('same').toPlace(),
        NearbyCarePlace(
          placeId: moved.placeId,
          name: moved.name,
          address: '새 주소',
          telephone: moved.telephone,
          latitude: moved.latitude,
          longitude: moved.longitude,
          distanceKm: 1,
          todayOpenTime: '09:00',
          todayCloseTime: '18:00',
          isOpenNow: true,
          is24Hours: false,
        ),
        _snapshot('legacy').toPlace(),
        _snapshot('not-favorite').toPlace(),
      ],
      {'same', 'moved', 'legacy'},
      now,
    )!;
    expect(updated.keys.toSet(), {'same', 'moved', 'legacy'});
    expect(updated['same'], same(current['same']));
    expect(updated['moved']!.address, '새 주소');
    expect(updated['moved']!.savedAt, now);
    expect(updated['legacy']!.savedAt, now);
    // The original map is left for the caller to replace.
    expect(current['moved']!.address, '서울 moved');
  });

  // Function Name: test callback
  // Description: A snapshot becomes a list item with unknown operating status.
  // Parameters: None.
  // Returns: void.
  test('snapshot places carry no live status', () {
    final place = _snapshot('p').toPlace(distanceKm: 2.5);
    expect(place.placeId, 'p');
    expect(place.distanceKm, 2.5);
    expect(place.isOpenNow, isNull);
    expect(place.todayOpenTime, isNull);
    expect(place.todayCloseTime, isNull);
    expect(place.is24Hours, isFalse);
  });
}

// Function Name: _snapshot
// Description: Builds a snapshot with ID-derived name and address.
// Parameters: id (String): place ID; savedAt (DateTime?): write time, a fixed date by default.
// Returns: FavoritePlaceSnapshot at fixed Seoul coordinates.
FavoritePlaceSnapshot _snapshot(String id, {DateTime? savedAt}) =>
    FavoritePlaceSnapshot(
      placeId: id,
      name: '메드버디의원 $id',
      address: '서울 $id',
      telephone: '02-000-0000',
      latitude: 37.5,
      longitude: 127.0,
      savedAt: savedAt ?? DateTime.utc(2026, 11, 2),
    );
