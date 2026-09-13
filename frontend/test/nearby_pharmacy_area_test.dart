// 파일명: nearby_pharmacy_area_test.dart
// 역할: 지도 검색 위치 유지, 위치 실패 대체, 빈 결과와 재시도를 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

const _mapArea = PharmacySearchArea(
  center: DeviceCoordinate(latitude: 37.5, longitude: 127.03),
  radiusKm: 3.2,
  isMapArea: true,
);

// 클래스명: _Location
// 역할: 위치 실패·잘못된 좌표·조회 횟수를 재현하는 테스트 경계.
class _Location implements DeviceLocationBoundary {
  Object? error;
  int calls = 0;
  DeviceCoordinate coordinate = const DeviceCoordinate(
    latitude: 37.56,
    longitude: 126.98,
  );

  // 함수이름: requestCurrentCoordinate
  // 함수역할: 위치 조회를 기록하고 설정된 결과를 반환한다. 매개변수: 없음. 반환값: 좌표 또는 오류.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    calls++;
    if (error != null) throw error!;
    return coordinate;
  }

  // 함수이름: openApplicationSettings
  // 함수역할: 실제 설정 창 없이 완료한다. 매개변수: 없음. 반환값: 성공 여부.
  @override
  Future<bool> openApplicationSettings() async => true;

  // 함수이름: openDeviceLocationSettings
  // 함수역할: 실제 위치 설정 없이 완료한다. 매개변수: 없음. 반환값: 성공 여부.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

// 클래스명: _MapProbe
// 역할: 네이티브 지도를 대신해 화면이 전달하는 검색 기준과 사용자 명령을 기록한다.
class _MapProbe {
  late PharmacySearchArea area;
  late Future<bool> Function(PharmacySearchArea) search;
  late VoidCallback locate;
  int revision = 0;

  // 함수이름: build
  // 함수역할: 지도 계약의 검색 위치·명령을 기록한다. 매개변수: 지도 생성 계약. 반환값: 빈 지도 대역.
  Widget build({
    required PharmacySearchArea searchArea,
    required int centerRevision,
    required bool isSearching,
    required Future<bool> Function(PharmacySearchArea) onSearchAreaRequested,
    required VoidCallback onCurrentLocationRequested,
    required List<NearbyPharmacy> pharmacies,
    required String? selectedPharmacyId,
    required ValueChanged<NearbyPharmacy> onPharmacySelected,
    required VoidCallback onAttributionRequested,
    required String? statusText,
    required String selectMarkerHint,
    required String zoomInTooltip,
    required String zoomOutTooltip,
    required String configurationUnavailableText,
    required String unavailableText,
  }) {
    area = searchArea;
    revision = centerRevision;
    search = onSearchAreaRequested;
    locate = onCurrentLocationRequested;
    return const SizedBox.expand(key: Key('area-map'));
  }
}

// 함수이름: _app
// 함수역할: 약국 화면과 지도 대역을 연결한다. 매개변수: 제어기·지도·언어. 반환값: 테스트 앱.
Widget _app(
  CheckNearbyPharmacy control,
  _MapProbe map, {
  String language = 'ko',
}) {
  return MaterialApp(
    home: CheckNearbyPharmacyUI(
      control: control,
      mapBuilder: map.build,
      userSetting: UserSetting(fontSize: 24, language: language),
    ),
  );
}

// 함수이름: main
// 함수역할: 검색 지역과 위치 실패의 회귀 검증을 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 명시적 지도 지역 테스트
  // 함수역할: 지도에서 고른 좌표·반경을 보내며 GPS를 다시 조회하지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test(
    'explicit map area bypasses GPS and preserves query conditions',
    () async {
      final location = _Location()..error = StateError('GPS unavailable');
      late Uri requested;
      final control = CheckNearbyPharmacy(
        locationBoundary: location,
        client: MockClient((request) async {
          requested = request.url;
          return http.Response('{"data":[]}', 200);
        }),
      );
      final time = DateTime(2026, 9, 12, 12);
      final result = await control.requestNearbyPharmacySearch(
        searchArea: _mapArea,
        searchMode: PharmacySearchMode.all,
        targetDateTime: time,
      );
      expect(location.calls, 0);
      expect(requested.queryParameters['latitude'], '37.5000000');
      expect(requested.queryParameters['longitude'], '127.0300000');
      expect(requested.queryParameters['max_distance_km'], '3.2');
      expect(requested.queryParameters['search_mode'], 'all');
      expect(
        requested.queryParameters['target_datetime'],
        time.toIso8601String(),
      );
      expect(result.searchArea, same(_mapArea));
    },
  );

  for (final failure in DeviceLocationFailure.values) {
    // 함수이름: 위치 실패 대체 테스트
    // 함수역할: 권한·GPS 등 모든 위치 실패가 홍익대 검색으로 이어지는지 확인한다.
    // 매개변수: 없음. 반환값: 검증 완료.
    test('location $failure falls back to Hongik', () async {
      final location = _Location()..error = DeviceLocationException(failure);
      late Uri requested;
      final control = CheckNearbyPharmacy(
        locationBoundary: location,
        client: MockClient((request) async {
          requested = request.url;
          return http.Response('{"data":[]}', 200);
        }),
      );
      final result = await control.requestNearbyPharmacySearch();
      expect(result.searchArea!.isFallback, isTrue);
      expect(requested.queryParameters['latitude'], '37.5516000');
      expect(requested.queryParameters['longitude'], '126.9250000');
      expect(result.data, isEmpty);
    });
  }

  // 함수이름: 좌표 검증과 서버 실패 구분 테스트
  // 함수역할: 잘못된 GPS 좌표를 대체하되 서버 실패를 정상 빈 결과로 처리하지 않는지 확인한다.
  // 매개변수: 없음. 반환값: 검증 완료.
  test('invalid GPS falls back but HTTP failure is not hidden', () async {
    final location = _Location()
      ..coordinate = const DeviceCoordinate(latitude: double.nan, longitude: 0);
    final control = CheckNearbyPharmacy(
      locationBoundary: location,
      client: MockClient((_) async => http.Response('{"detail":"down"}', 500)),
    );
    expect((await control.requestSearchArea()).isFallback, isTrue);
    await expectLater(control.requestNearbyPharmacySearch(), throwsStateError);
    await expectLater(
      control.requestSearchArea(radiusKm: 51),
      throwsArgumentError,
    );
    await expectLater(
      control.requestNearbyPharmacySearch(
        searchArea: const PharmacySearchArea(
          center: DeviceCoordinate(latitude: 91, longitude: 127),
        ),
      ),
      throwsArgumentError,
    );
  });

  // 함수이름: 빈 결과와 검색 지역 유지 테스트
  // 함수역할: 검색 결과가 없어도 지도를 유지하고 필터·새로고침이 같은 지역을 사용하는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets(
    'empty map supports area search, filters, refresh and GPS reset',
    (tester) async {
      final location = _Location();
      final requests = <Uri>[];
      final map = _MapProbe();
      final control = CheckNearbyPharmacy(
        locationBoundary: location,
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('{"data":[]}', 200);
        }),
      );
      await tester.pumpWidget(_app(control, map));
      await tester.pumpAndSettle();
      final element = tester.element(find.byKey(const Key('area-map')));
      expect(location.calls, 1);
      final search = map.search(_mapArea);
      await tester.pumpAndSettle();
      expect(await search, isTrue);
      expect(map.area, same(_mapArea));
      expect(map.revision, 0);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pharmacy-filter-option-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('약국 목록 새로고침'));
      await tester.pumpAndSettle();
      expect(location.calls, 1);
      expect(requests.last.queryParameters['latitude'], '37.5000000');
      expect(requests.last.queryParameters['search_mode'], 'all');
      expect(requests.last.queryParameters['max_distance_km'], '3.2');
      expect(tester.element(find.byKey(const Key('area-map'))), same(element));
      map.locate();
      await tester.pumpAndSettle();
      expect(location.calls, 2);
      expect(map.revision, 1);
      expect(map.area.isMapArea, isFalse);
      expect(requests.last.queryParameters['latitude'], '37.5600000');
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 지도 검색 재시도 테스트
  // 함수역할: 지도 검색 실패 시 기존 검색 중심을 보존하며 같은 지역을 다시 요청할 수 있는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('failed map search preserves prior area and supports retry', (
    tester,
  ) async {
    var fail = false;
    final map = _MapProbe();
    final control = CheckNearbyPharmacy(
      locationBoundary: _Location(),
      client: MockClient(
        (_) async => fail
            ? http.Response('{"detail":"down"}', 500)
            : http.Response('{"data":[]}', 200),
      ),
    );
    await tester.pumpWidget(_app(control, map));
    await tester.pumpAndSettle();
    final originalArea = map.area;
    fail = true;
    final failedSearch = map.search(_mapArea);
    await tester.pumpAndSettle();
    expect(await failedSearch, isFalse);
    expect(map.area, same(originalArea));
    expect(find.byKey(const Key('area-map')), findsOneWidget);
    fail = false;
    final retry = map.search(_mapArea);
    await tester.pumpAndSettle();
    expect(await retry, isTrue);
    expect(map.area, same(_mapArea));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 중복 요청 제한 테스트
  // 함수역할: 진행 중에는 중복 검색을 막고 완료 후 내 위치로 전환할 수 있는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('blocks duplicate area searches until pending search completes', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final map = _MapProbe();
    final control = CheckNearbyPharmacy(
      locationBoundary: _Location(),
      client: MockClient((_) async {
        calls++;
        if (calls == 2) return pending.future;
        return http.Response('{"data":[]}', 200);
      }),
    );
    await tester.pumpWidget(_app(control, map));
    await tester.pumpAndSettle();
    final areaSearch = map.search(_mapArea);
    expect(await map.search(PharmacySearchArea.hongik), isFalse);
    map.locate();
    await tester.pump();
    expect(calls, 2);
    pending.complete(http.Response('{"data":[]}', 200));
    await tester.pumpAndSettle();
    expect(await areaSearch, isTrue);
    expect(map.area, same(_mapArea));
    map.locate();
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(map.area.isMapArea, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 위치 대체 안내 접근성 테스트
    // 함수역할: 작은 화면과 큰 글씨에서도 위치 대체 안내가 지도를 밀어 넘치지 않는지 확인한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('fallback layout fits small viewport in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final control = CheckNearbyPharmacy(
        locationBoundary: _Location()..error = StateError('unavailable'),
        client: MockClient((_) async => http.Response('{"data":[]}', 200)),
      );
      await tester.pumpWidget(_app(control, _MapProbe(), language: language));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('area-map')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('area-map'))).height,
        greaterThan(150),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
