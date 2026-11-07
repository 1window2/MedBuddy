// 파일명: nearby_care_shared_place_ui_test.dart
// 역할: 공유 장소도 수신 기기의 현재 위치와 현재 운영정보로 일반 검색 화면에서 연다.
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

// 공유 당시 정보와 구분하여 최신 조회 요청에 사용할 고정 UTC 시각이다.
final _now = DateTime.utc(2026, 10, 27, 5);
// 부산의 공유 장소와 충분히 떨어진 수신자 좌표로 거리 재계산을 검증한다.
const _recipientLocation = DeviceCoordinate(latitude: 37.55, longitude: 126.92);

// 클래스명: _Location
// 역할: 공유 장소를 여는 수신자의 위치 조회를 제어하는 대역.
// 주요 책임:
// - 권한 거절·정상 좌표·지연 GPS 응답을 재현하고 요청 횟수를 기록한다.
// 속성:
// - denied (bool): true이면 위치 권한 거절 예외를 발생시킨다.
// - pending (Completer<DeviceCoordinate>?): 있을 때 테스트가 좌표 또는 오류 완료를 제어한다.
// - requests (int): 현재 위치 조회 횟수.
class _Location implements DeviceLocationBoundary {
  // 함수이름: _Location
  // 함수역할:
  // - 권한 거절 여부와 선택적인 GPS 대기 응답을 지정한 위치 대역을 만든다.
  // 매개변수:
  // - denied (bool): 기본 false; true이면 pending보다 먼저 권한 거절을 반환한다.
  // - pending (Completer<DeviceCoordinate>?): null이면 고정 수신자 좌표를 즉시 사용한다.
  // 반환값:
  // - _Location; 위치 조회 횟수가 0인 대역.
  _Location({this.denied = false, this.pending});
  final bool denied;
  final Completer<DeviceCoordinate>? pending;
  int requests = 0;

  // 함수이름: requestCurrentCoordinate
  // 함수역할:
  // - 조회 횟수를 기록한 뒤 권한 거절을 우선 처리하고, 정상 시 고정 좌표 또는 주입된 GPS 응답을 돌려준다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<DeviceCoordinate>; 수신자 좌표로 완료하거나 denied 예외 및 pending의 오류를 전달한다.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    requests++;
    if (denied) {
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }
    return pending == null ? _recipientLocation : await pending!.future;
  }

  // 함수이름: openApplicationSettings
  // 함수역할:
  // - 테스트 중 실제 앱 설정을 열지 않고 설정 이동 불가로 응답한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>; false로 완료한다.
  @override
  Future<bool> openApplicationSettings() async => false;

  // 함수이름: openDeviceLocationSettings
  // 함수역할:
  // - 테스트 중 기기 위치 설정을 열지 않고 설정 이동 불가로 응답한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>; false로 완료한다.
  @override
  Future<bool> openDeviceLocationSettings() async => false;
}

// 클래스명: _MapProbe
// 역할: 지도 없이 공유 장소 화면의 검색 상태와 콜백을 관찰하는 대역.
// 주요 책임:
// - 최근 영역·장소·선택을 보관하고 현재 위치 및 지도 영역 검색을 테스트에서 호출하게 한다.
// 속성:
// - area (NearbyCareSearchArea): 최근 지도 빌드의 검색 영역.
// - places (List<NearbyCarePlace>): 최근 전달된 장소 목록.
// - selected (String?): 선택된 장소 ID.
// - locate (VoidCallback): 현재 위치 재조회 콜백.
// - search (Future<bool> Function(NearbyCareSearchArea)): 지정 영역 검색 콜백.
class _MapProbe {
  late NearbyCareSearchArea area;
  late List<NearbyCarePlace> places;
  String? selected;
  late VoidCallback locate;
  late Future<bool> Function(NearbyCareSearchArea) search;

  // 함수이름: build
  // 함수역할:
  // - 최근 지도 상태와 검색 콜백을 보관하고 외부 지도 렌더링 대신 흰 배경을 반환한다.
  // 매개변수:
  // - searchArea (NearbyCareSearchArea): area로 보관할 검색 영역.
  // - centerRevision (int), isSearching (bool): 지도 인터페이스 상태이며 이 대역에서는 사용하지 않는다.
  // - onSearchAreaRequested (Future<bool> Function(NearbyCareSearchArea)): search로 노출할 영역 검색 함수.
  // - onCurrentLocationRequested (VoidCallback): locate로 노출할 위치 재조회 함수.
  // - pharmacies (List<NearbyCarePlace>): places로 보관할 현재 장소 목록.
  // - selectedPharmacyId (String?): selected로 보관할 선택 ID.
  // - onPharmacySelected (ValueChanged<NearbyCarePlace>), onAttributionRequested (VoidCallback): 인터페이스상 콜백으로 대역은 호출하지 않는다.
  // - statusText (String?): 실제 지도용 상태 문구로 대역은 표시하지 않는다.
  // - selectMarkerHint, zoomInTooltip, zoomOutTooltip, configurationUnavailableText, unavailableText (String): 실제 지도용 문구로 대역은 표시하지 않는다.
  // 반환값:
  // - Widget; 상태를 보관한 뒤 반환하는 흰색 ColoredBox.
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

// 함수이름: _sharedPlace
// 함수역할:
// - 현재 조회 결과와 구별할 수 있도록 부산 주소·오래된 갱신일·영업 중 상태를 가진 공유 당시 장소를 만든다.
// 매개변수:
// - hospitals (bool): true이면 의원 이름과 내과 정보를, false이면 약국 이름과 빈 진료과를 사용한다.
// 반환값:
// - NearbyCarePlace; original-provider-id를 가진 과거 공유 스냅샷.
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

// 함수이름: _response
// 함수역할:
// - 공유 스냅샷과 주소·전화·영업시간·상태가 다른 최신 장소 한 건을 JSON 응답으로 만든다.
// 매개변수:
// - id (String): 응답 장소 ID; 기본은 공유 ID이고 다른 값을 넣으면 동명 이업체 상황을 만든다.
// 반환값:
// - http.Response; UTF-8 JSON으로 인코딩한 HTTP 200 응답.
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

// 함수이름: _control
// 함수역할:
// - 위치 대역과 HTTP 처리 함수를 병원 또는 약국 컨트롤에 연결하고 종료 시 두 의존성을 정리한다.
// 매개변수:
// - hospitals (bool): 병원 컨트롤 생성 여부; false이면 약국 컨트롤을 만든다.
// - location (_Location): 위치 조회 동작을 제어할 대역.
// - handler (Future<http.Response> Function(http.Request)): 각 HTTP 요청의 응답 또는 오류를 결정한다.
// 반환값:
// - CheckNearbyCare; 주입된 MockClient를 사용하는 해당 장소 종류의 컨트롤.
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

// 함수이름: _pumpShared
// 함수역할:
// - 고정 시계와 공유 장소를 사용해 844px 높이의 상세 진입 화면을 표시하고 종료 시 화면 크기를 복원한다.
// 매개변수:
// - tester (WidgetTester): 화면 표시와 대기를 수행한다.
// - hospitals (bool): 병원 또는 약국 화면 선택.
// - place (NearbyCarePlace): 현재 정보 재조회 대상인 과거 공유 장소.
// - control (CheckNearbyCare): 위치·조회 응답을 제어할 컨트롤.
// - map (_MapProbe?): 지도 대역; null이면 실제 지도 위젯을 사용한다.
// - language (String): 기본 ko인 표시 언어.
// - width (double): 기본 390인 화면 너비.
// - scale (double): 기본 1인 텍스트 배율.
// - settle (bool): 기본 true; false이면 지연 응답의 로딩 상태를 남긴다.
// 반환값:
// - Future<void>; 화면 표시 후 settle 설정에 따라 안정화까지 기다린다.
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

// 함수이름: _detail
// 함수역할:
// - 공유 장소 ID를 사용하는 상세 위젯의 Finder를 만든다.
// 매개변수:
// - place (NearbyCarePlace): 상세 키에 사용할 placeId를 가진 장소.
// 반환값:
// - Finder; 해당 장소 상세가 현재 트리에 있는지 검사할 검색자.
Finder _detail(NearbyCarePlace place) =>
    find.byKey(ValueKey('pharmacy-detail-${place.placeId}'));

// 함수이름: _expectFresh
// 함수역할:
// - 공유 ID의 장소가 새 객체와 최신 영업 상태·주소로 선택되었고 과거 주소나 스냅샷 안내가 보이지 않는지 검증한다.
// 매개변수:
// - tester (WidgetTester): 상세 화면과 렌더링 예외를 검사한다.
// - place (NearbyCarePlace): 비교할 과거 공유 장소.
// - map (_MapProbe): 현재 선택과 장소 목록이 기록된 지도 대역.
// 반환값:
// - void; 최신 장소가 없거나 과거 정보·렌더링 오류가 남으면 검증이 실패한다.
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

// Function Name: main
// Description:
// - Register hospital and pharmacy shared-place tests for current-data lookup, exact-ID fallback, recovery, location actions, layout, and disposal.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // 함수이름: setUp
  // 함수역할:
  // - 각 공유 장소 테스트 전에 기기 저장값을 비워 안내 확인 상태와 기타 설정이 사례 사이에 섞이지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; SharedPreferences 테스트 초기값을 빈 맵으로 설정한다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final hospitals in [false, true]) {
    final kind = hospitals ? 'hospital' : 'pharmacy';

    // 함수이름: $kind resolves current detail using recipient GPS and clock
    // 함수역할:
    // - 병원·약국 공유 장소가 수신자의 GPS와 현재 시각으로 전체 모드를 한 번 조회하고, 최신 상세와 수신자 기준 영역·거리를 표시하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind does not show stored details while loading
    // 함수역할:
    // - 최신 조회가 대기 중일 때 과거 공유 주소나 상세를 먼저 노출하지 않고, 응답 완료 후에만 새 상세를 여는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind looks up a distant exact ID and rebases distance to recipient
    // 함수역할:
    // - 수신자 주변에서 공유 ID가 없으면 공유 좌표 반경 0.3km를 재조회하고 정확한 ID만 선택하여 거리를 수신자 기준으로 재계산하며, 새로고침에도 GPS를 중복 요청하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // Function Name: $kind never substitutes a same-name place or stale snapshot
    // Description:
    // - When both lookups find only a same-name different-ID place, show nearby places with a missing-shared-place notice, never stale details; refresh makes one ordinary lookup instead of repeating both searches.
    // Parameters:
    // - tester (WidgetTester): renders widgets, performs gestures, and inspects the resulting UI.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
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
      // Refresh must not repeat the two-step lookup for a shared place already known to be absent.
      await tester.tap(
        find.byTooltip(hospitals ? '병원 목록 새로고침' : '약국 목록 새로고침'),
      );
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    });

    // 함수이름: $kind retries failed current lookup without a snapshot fallback
    // 함수역할:
    // - 현재 정보 조회의 HTTP 503 실패는 과거 스냅샷으로 대체하지 않고 오류를 표시하며, 새로고침 성공 후 최신 상세로 복구하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind keeps ordinary location-denied fallback and map actions
    // 함수역할:
    // - 위치 권한이 거절되어도 기본 검색 위치로 최신 장소를 조회하고 실제 지도에 올바른 병원·약국 모드와 선택을 전달하며 기기 좌표를 꾸며내지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind returns to ordinary location and map searches
    // 함수역할:
    // - 공유 상세에서 현재 위치로 돌아오면 선택을 해제하고 GPS를 재조회하며, 이후 지도 영역 검색은 GPS 추가 요청 없이 지정 영역으로 전환하는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind current detail fits narrow English large-text view
    // 함수역할:
    // - 360px·1.6배 영어 화면에서 최신 상세가 렌더링 예외 없이 표시되고, 공유 당시 주소·영업 상태 설명을 노출하지 않는지 검증한다.
    // 매개변수:
    // - tester (WidgetTester): 화면을 표시하고 사용자 입력과 렌더링 결과를 검사한다.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind disposal during GPS prevents any request
    // 함수역할:
    // - GPS 완료 전에 컨트롤을 해제하면 늦은 좌표 응답이 HTTP 요청으로 이어지지 않고 선택 장소 검색이 StateError로 끝나는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

    // 함수이름: $kind disposal during first lookup prevents second request
    // 함수역할:
    // - 첫 조회 대기 중 컨트롤을 해제하면 다른 ID 응답을 받아도 두 번째 검색을 보내지 않고 StateError로 끝나는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>; 비동기 검증이 끝나면 완료한다.
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
