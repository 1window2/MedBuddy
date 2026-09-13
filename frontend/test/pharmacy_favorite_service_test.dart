// 파일명: pharmacy_favorite_service_test.dart
// 역할: 즐겨찾기 약국 목록의 정규화와 기기 저장 규칙을 검증한다.

import 'package:flutter_test/flutter_test.dart';
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
}
