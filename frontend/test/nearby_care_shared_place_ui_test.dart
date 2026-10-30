// 공유 장소도 수신 기기의 현재 위치와 현재 운영정보로 일반 검색 화면에서 연다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/nearby_pharmacy_map_widget.dart';
import 'package:medbuddy_frontend/controls/check_nearby_care_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

final _now = DateTime.utc(2026, 10, 27, 5);
const _recipientLocation = DeviceCoordinate(latitude: 37.55, longitude: 126.92);

class _Location implements DeviceLocationBoundary {
  _Location({this.denied = false, this.pending});
  final bool denied;
  final Completer<DeviceCoordinate>? pending;
  int requests = 0;

  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    requests++;
    if (denied) {
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }
    return pending == null ? _recipientLocation : await pending!.future;
  }

  @override
  Future<bool> openApplicationSettings() async => false;

  @override
  Future<bool> openDeviceLocationSettings() async => false;
}

class _MapProbe {
  late NearbyCareSearchArea area;
  late List<NearbyCarePlace> places;
  String? selected;
  late VoidCallback locate;
  late Future<bool> Function(NearbyCareSearchArea) search;

  Widget build({
    required NearbyCareSearchArea searchArea,
    required int centerRevision,
    required bool isSearching,
    required Future<bool> Function(NearbyCareSearchArea) onSearchAreaRequested,
    required VoidCallback onCurrentLocationRequested,
    required List<NearbyCarePlace> pharmacies,
    required String? selectedPharmacyId,
    required ValueChanged<NearbyCarePlace> onPharmacySelected,
    required VoidCallback onAttributionRequested,
    required String? statusText,
    required String selectMarkerHint,
    required String zoomInTooltip,
    required String zoomOutTooltip,
    required String configurationUnavailableText,
    required String unavailableText,
  }) {
    area = searchArea;
    places = pharmacies;
    selected = selectedPharmacyId;
    locate = onCurrentLocationRequested;
    search = onSearchAreaRequested;
    return const ColoredBox(color: Colors.white);
  }
}

NearbyCarePlace _sharedPlace(bool hospitals) => NearbyCarePlace(
  placeId: 'original-provider-id',
  name: hospitals ? '공유한 메드버디의원' : '공유한 메드버디약국',
  address: '부산광역시 중구 공유 당시 주소',
  telephone: '051-123-4567',
  latitude: 35.1065,
  longitude: 129.0323,
  distanceKm: 0,
  isOpenNow: true,
  todayOpenTime: '09:00',
  todayCloseTime: '18:00',
  minutesUntilClose: 5,
  is24Hours: false,
  sourceUpdatedAt: DateTime(2025, 1, 2),
  departments: hospitals ? ['내과'] : [],
);

http.Response _response({String id = 'original-provider-id'}) => http.Response(
  jsonEncode({
    'data': [
      {
        'pharmacy_id': id,
        // 같은 이름도 ID가 다르면 공유한 장소로 취급하지 않는다.
        'name': '공유한 메드버디약국',
        'address': '새로 조회한 주소',
        'telephone': '02-999-9999',
        'latitude': 35.107,
        'longitude': 129.033,
        'distance_km': .3,
        'is_open_now': false,
        'today_open_time': '08:00',
        'today_close_time': '20:00',
        'departments': ['내과'],
        'source_updated_at': '2026-10-27T04:00:00Z',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

CheckNearbyCare _control(
  bool hospitals,
  _Location location,
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  final CheckNearbyCare control = hospitals
      ? CheckNearbyHospital(locationBoundary: location, client: client)
      : CheckNearbyPharmacy(locationBoundary: location, client: client);
  addTearDown(control.dispose);
  addTearDown(client.close);
  return control;
}

Future<void> _pumpShared(
  WidgetTester tester, {
  required bool hospitals,
  required NearbyCarePlace place,
  required CheckNearbyCare control,
  _MapProbe? map,
  String language = 'ko',
  double width = 390,
  double scale = 1,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: CheckNearbyPharmacyUI(
          userSetting: UserSetting(language: language),
          hospitals: hospitals,
          initialPlace: place,
          control: control,
          mapBuilder: map?.build,
          clock: () => _now,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _detail(NearbyCarePlace place) =>
    find.byKey(ValueKey('pharmacy-detail-${place.placeId}'));

void _expectFresh(WidgetTester tester, NearbyCarePlace place, _MapProbe map) {
  expect(map.selected, place.placeId);
  final current = map.places.singleWhere(
    (item) => item.placeId == place.placeId,
  );
  expect(current, isNot(same(place)));
  expect(current.isOpenNow, false);
  expect(current.todayCloseTime, '20:00');
  expect(_detail(place), findsOneWidget);
  expect(find.text('새로 조회한 주소'), findsOneWidget);
  expect(find.text(place.address), findsNothing);
  expect(find.textContaining('채팅에 공유된 당시 정보'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final hospitals in [false, true]) {
    final kind = hospitals ? 'hospital' : 'pharmacy';

    testWidgets('$kind resolves current detail using recipient GPS and clock', (
      tester,
    ) async {
      final location = _Location();
      final requests = <http.Request>[];
      final control = _control(hospitals, location, (request) async {
        requests.add(request);
        return _response();
      });
      final place = _sharedPlace(hospitals);
      final map = _MapProbe();
      await _pumpShared(
        tester,
        hospitals: hospitals,
        place: place,
        control: control,
        map: map,
      );

      _expectFresh(tester, place, map);
      expect(location.requests, 1);
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['latitude'], '37.5500000');
      expect(requests.single.url.queryParameters['longitude'], '126.9200000');
      expect(
        requests.single.url.queryParameters['target_datetime'],
        _now.toIso8601String(),
      );
      expect(requests.single.url.queryParameters['search_mode'], 'all');
      expect(map.area.center, same(_recipientLocation));
      expect(map.area.isMapArea, false);
      expect(map.area.isFallback, false);
      expect(map.places.single.distanceKm, .3);
    });

    testWidgets('$kind does not show stored details while loading', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final place = _sharedPlace(hospitals);
      final control = _control(hospitals, _Location(), (_) => response.future);
      final map = _MapProbe();
      await _pumpShared(
        tester,
        hospitals: hospitals,
        place: place,
        control: control,
        map: map,
        settle: false,
      );
      await tester.pump();
      expect(_detail(place), findsNothing);
      expect(find.text(place.address), findsNothing);

      response.complete(_response());
      await tester.pumpAndSettle();
      _expectFresh(tester, place, map);
    });

    testWidgets(
      '$kind looks up a distant exact ID and rebases distance to recipient',
      (tester) async {
        final location = _Location();
        final requests = <http.Request>[];
        final control = _control(hospitals, location, (request) async {
          requests.add(request);
          return requests.length.isOdd
              ? _response(id: 'same-name-other-id')
              : _response();
        });
        final place = _sharedPlace(hospitals);
        final map = _MapProbe();
        await _pumpShared(
          tester,
          hospitals: hospitals,
          place: place,
          control: control,
          map: map,
        );

        _expectFresh(tester, place, map);
        expect(requests, hasLength(2));
        expect(location.requests, 1);
        expect(requests.last.url.queryParameters['latitude'], '35.1065000');
        expect(requests.last.url.queryParameters['longitude'], '129.0323000');
        expect(requests.last.url.queryParameters['max_distance_km'], '0.3');
        expect(
          requests.last.url.queryParameters['target_datetime'],
          _now.toIso8601String(),
        );
        expect(map.area.center, same(_recipientLocation));
        expect(map.places, hasLength(2));
        final current = map.places.singleWhere(
          (p) => p.placeId == place.placeId,
        );
        expect(current.distanceKm, greaterThan(300));
        expect(current.distanceKm, lessThan(400));
        expect(current.telephone, '02-999-9999');
        expect(current.departments, ['내과']);
        expect(current.sourceUpdatedAt, DateTime.utc(2026, 10, 27, 4));
        await tester.tap(
          find.byTooltip(hospitals ? '병원 목록 새로고침' : '약국 목록 새로고침'),
        );
        await tester.pumpAndSettle();
        _expectFresh(tester, place, map);
        expect(requests, hasLength(4));
        expect(location.requests, 1);
        expect(map.area.center, same(_recipientLocation));
      },
    );

    testWidgets('$kind never substitutes a same-name place or stale snapshot', (
      tester,
    ) async {
      var requests = 0;
      final control = _control(hospitals, _Location(), (_) async {
        requests++;
        return _response(id: 'same-name-other-id');
      });
      final place = _sharedPlace(hospitals);
      await _pumpShared(
        tester,
        hospitals: hospitals,
        place: place,
        control: control,
        map: _MapProbe(),
      );
      expect(requests, 2);
      expect(_detail(place), findsNothing);
      expect(find.text(place.address), findsNothing);
      expect(find.text('새로 조회한 주소'), findsNothing);
      expect(find.textContaining('정보를 불러오지 못했습니다'), findsNothing);
      expect(find.text('공유된 장소를 지금 목록에서 찾지 못했어요. 주변 장소를 보여드려요.'), findsOneWidget);
      // 찾지 못한 장소는 새로고침해도 같은 두 번의 조회를 되풀이하지 않는다.
      await tester.tap(
        find.byTooltip(hospitals ? '병원 목록 새로고침' : '약국 목록 새로고침'),
      );
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$kind retries failed current lookup without a snapshot fallback',
      (tester) async {
        var failing = true;
        final control = _control(
          hospitals,
          _Location(),
          (_) async =>
              failing ? http.Response('unavailable', 503) : _response(),
        );
        final place = _sharedPlace(hospitals);
        final map = _MapProbe();
        await _pumpShared(
          tester,
          hospitals: hospitals,
          place: place,
          control: control,
          map: map,
        );
        expect(_detail(place), findsNothing);
        expect(find.text(place.address), findsNothing);
        expect(find.textContaining('정보를 불러오지 못했습니다'), findsOneWidget);
        failing = false;
        await tester.tap(
          find.byTooltip(hospitals ? '병원 목록 새로고침' : '약국 목록 새로고침'),
        );
        await tester.pumpAndSettle();
        _expectFresh(tester, place, map);
      },
    );

    testWidgets(
      '$kind keeps ordinary location-denied fallback and map actions',
      (tester) async {
        final location = _Location(denied: true);
        var requests = 0;
        final control = _control(hospitals, location, (_) async {
          requests++;
          return _response();
        });
        final place = _sharedPlace(hospitals);
        await _pumpShared(
          tester,
          hospitals: hospitals,
          place: place,
          control: control,
        );
        final map = tester.widget<NearbyPharmacyMap>(
          find.byType(NearbyPharmacyMap),
        );
        expect(map.hospitals, hospitals);
        expect(map.selectedPharmacyId, place.placeId);
        expect(map.searchArea.isFallback, true);
        expect(map.searchArea.center, NearbyCareSearchArea.fallbackCenter);
        expect(map.deviceLocation, isNull);
        expect(map.pharmacies.single.isOpenNow, false);
        expect(location.requests, 1);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$kind returns to ordinary location and map searches', (
      tester,
    ) async {
      final location = _Location();
      final requests = <http.Request>[];
      final control = _control(hospitals, location, (request) async {
        requests.add(request);
        return _response();
      });
      final place = _sharedPlace(hospitals);
      final map = _MapProbe();
      await _pumpShared(
        tester,
        hospitals: hospitals,
        place: place,
        control: control,
        map: map,
      );
      map.locate();
      await tester.pumpAndSettle();
      expect(location.requests, 2);
      expect(requests, hasLength(2));
      expect(map.selected, isNull);
      expect(_detail(place), findsNothing);
      const area = NearbyCareSearchArea(
        center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
        radiusKm: 1,
        isMapArea: true,
      );
      final search = map.search(area);
      await tester.pumpAndSettle();
      expect(await search, isTrue);
      expect(map.area, same(area));
      expect(location.requests, 2);
      expect(requests, hasLength(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$kind current detail fits narrow English large-text view', (
      tester,
    ) async {
      final place = _sharedPlace(hospitals);
      await _pumpShared(
        tester,
        hospitals: hospitals,
        place: place,
        control: _control(hospitals, _Location(), (_) async => _response()),
        map: _MapProbe(),
        language: 'en',
        width: 360,
        scale: 1.6,
      );
      expect(_detail(place), findsOneWidget);
      expect(find.textContaining('Information shared in chat'), findsNothing);
      expect(find.text('Open when shared'), findsNothing);
      expect(find.text(place.address), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('$kind disposal during GPS prevents any request', () async {
      final gps = Completer<DeviceCoordinate>();
      var requests = 0;
      final control = _control(hospitals, _Location(pending: gps), (_) async {
        requests++;
        return _response();
      });
      final search = control.requestSelectedPlaceSearch(
        place: _sharedPlace(hospitals),
        targetDateTime: _now,
      );
      final expectation = expectLater(search, throwsStateError);
      control.dispose();
      gps.complete(_recipientLocation);
      await expectation;
      expect(requests, 0);
    });

    test(
      '$kind disposal during first lookup prevents second request',
      () async {
        final pending = Completer<http.Response>();
        final requested = Completer<void>();
        var requests = 0;
        final control = _control(hospitals, _Location(), (_) {
          requests++;
          requested.complete();
          return pending.future;
        });
        final search = control.requestSelectedPlaceSearch(
          place: _sharedPlace(hospitals),
          targetDateTime: _now,
        );
        final expectation = expectLater(search, throwsStateError);
        await requested.future;
        control.dispose();
        pending.complete(_response(id: 'other-id'));
        await expectation;
        expect(requests, 1);
      },
    );
  }
}
