// 파일명: pharmacy_favorite_service_test.dart
// 역할: 즐겨찾기 약국 목록의 정규화와 기기 저장 규칙을 검증한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('같은 기기의 사용자별 즐겨찾기 목록은 서로 섞이지 않는다', () async {
    final preferences = await SharedPreferences.getInstance();
    final patientService = PharmacyFavoriteService(
      userHash: 'patient_test',
      preferencesLoader: () async => preferences,
    );
    final caregiverService = PharmacyFavoriteService(
      userHash: 'caregiver_test',
      preferencesLoader: () async => preferences,
    );

    await patientService.saveFavoriteIds({'pharmacy-a'});
    await caregiverService.saveFavoriteIds({'pharmacy-b'});

    expect(await patientService.loadFavoriteIds(), {'pharmacy-a'});
    expect(await caregiverService.loadFavoriteIds(), {'pharmacy-b'});
  });
}
