// 파일명: check_nearby_pharmacy_ui_boundary_test.dart
// 역할: 근처 약국 화면의 결과·필터·위치 오류 상태를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/nearby_pharmacy_map_widget.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';

// 클래스명: _FakeLocationBoundary
// 역할: 위치 성공과 지정된 위치 오류를 선택할 수 있는 경계 대역.
// 주요 책임:
// - 오류가 주입되면 위치 예외를 발생시키고 아니면 고정 서울 좌표를 제공한다.
// - 앱 권한 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
// - 기기 위치 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
class _FakeLocationBoundary implements DeviceLocationBoundary {
  final DeviceLocationFailure? failure;

  // 함수이름: _FakeLocationBoundary
  // 함수역할:
  // - 재현할 위치 오류를 보관하며 미지정 시 고정 좌표를 사용한다.
  // 매개변수:
  // - failure (DeviceLocationFailure?): 재현할 선택적 위치 실패 유형.
  // 반환값:
  // - 지정 실패 조건의 위치 대역.
  const _FakeLocationBoundary({this.failure});

  // 함수이름: requestCurrentCoordinate
  // 함수역할:
  // - 오류가 주입되면 위치 예외를 발생시키고 아니면 고정 서울 좌표를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 성공 시 고정 기기 좌표; 실패 시 DeviceLocationException.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    if (failure != null) {
      throw DeviceLocationException(failure!);
    }
    return const DeviceCoordinate(latitude: 37.5665, longitude: 126.9780);
  }

  // 함수이름: openApplicationSettings
  // 함수역할:
  // - 앱 권한 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - true로 완료되는 Future<bool>.
  @override
  Future<bool> openApplicationSettings() async => true;

  // 함수이름: openDeviceLocationSettings
  // 함수역할:
  // - 기기 위치 설정 화면을 실제로 열지 않고 이동 성공을 재현한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - true로 완료되는 Future<bool>.
  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

// 함수이름: _buildControl
// 함수역할:
// - 검색 모드별 응답·위치 오류·외부 앱·클립보드 동작을 주입한 약국 제어기를 구성한다.
// 매개변수:
// - failure (DeviceLocationFailure?): 재현할 선택적 위치 실패 유형.
// - onRequest (VoidCallback?): 가로챈 약국 요청을 감시할 선택적 콜백.
// - requestedModes (List<String?>?): 수신한 약국 검색 모드를 기록할 선택적 목록.
// - emptyModes (Set<String>): 약국 없음 응답을 제공할 검색 모드 집합.
// - customPharmacies (List<Map<String, Object?>>?): 기본 대역 대신 반환할 선택적 약국 데이터 행.
// - uriLauncher (Future<bool> Function(Uri uri)?): 전화·길찾기 앱 실행을 대신할 선택적 함수.
// - clipboardWriter (Future<void> Function(String text)?): 시스템 클립보드 쓰기를 대신할 선택적 콜백.
// 반환값:
// - 네트워크 없이 필터와 사용자 명령을 검사할 제어기.
CheckNearbyPharmacy _buildControl({
  DeviceLocationFailure? failure,
  VoidCallback? onRequest,
  List<String?>? requestedModes,
  List<DateTime>? requestedTimes,
  Future<void> Function()? beforeResponse,
  Set<String> emptyModes = const {},
  List<Map<String, Object?>>? customPharmacies,
  Future<bool> Function(Uri uri)? uriLauncher,
  Future<void> Function(String text)? clipboardWriter,
}) {
  return CheckNearbyPharmacy(
    locationBoundary: _FakeLocationBoundary(failure: failure),
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 요청 모드를 기록하고 빈 결과·사용자 지정 결과·영업 필터별 기본 약국 목록을 선택한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 선택한 약국 목록을 담은 HTTP 200 응답.
    client: MockClient((request) async {
      onRequest?.call();
      final requestedMode = request.url.queryParameters['search_mode'];
      requestedModes?.add(requestedMode);
      requestedTimes?.add(
        DateTime.parse(request.url.queryParameters['target_datetime']!),
      );
      await beforeResponse?.call();
      final includeClosed = requestedMode == 'all';
      final isEmpty = emptyModes.contains(requestedMode);
      final responseData = isEmpty
          ? <Map<String, Object?>>[]
          : customPharmacies ??
                [
                  {
                    'pharmacy_id': 'open',
                    'name': '영업중 메드버디약국',
                    'address': '서울특별시 종로구',
                    'telephone': '02-123-4567',
                    'latitude': 37.5666,
                    'longitude': 126.9781,
                    'distance_km': 0.42,
                    'today_open_time': '09:00',
                    'today_close_time': '24:00',
                    'is_open_now': true,
                    'is_24_hours': false,
                  },
                  if (includeClosed)
                    {
                      'pharmacy_id': 'closed',
                      'name': '영업종료 메드버디약국',
                      'address': '서울특별시 중구',
                      'telephone': '',
                      'latitude': 37.5667,
                      'longitude': 126.9782,
                      'distance_km': 0.5,
                      'today_open_time': '09:00',
                      'today_close_time': '18:00',
                      'is_open_now': false,
                      'is_24_hours': false,
                    },
                ];
      return http.Response(
        jsonEncode({'data': responseData}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    // 함수이름: callback 콜백
    // 함수역할:
    // - 실제 외부 앱을 열지 않고 기본 URI 실행 성공을 제공한다.
    // 매개변수:
    // - _ (Uri): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
    // 반환값:
    // - true로 완료되는 Future<bool>.
    uriLauncher: uriLauncher ?? (_) async => true,
    clipboardWriter: clipboardWriter,
  );
}

// 함수이름: _testApp
// 함수역할:
// - 작은 화면과 1.6배 글씨, 테스트 지도 경계로 약국 화면을 감싼다.
// 매개변수:
// - control (CheckNearbyPharmacy): 테스트가 주입하고 수명을 관리하는 제어기.
// 반환값:
// - 약국 목록과 가짜 지도가 있는 MaterialApp.
Widget _testApp(CheckNearbyPharmacy control, {DateTime Function()? clock,
    bool nativeMap = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 640),
        textScaler: TextScaler.linear(1.6),
      ),
      child: CheckNearbyPharmacyUI(
        userSetting: const UserSetting(fontSize: 20),
        control: control,
        clock: clock,
        mapBuilder: nativeMap ? null : _buildTestMap,
      ),
    ),
  );
}

// 함수이름: _buildTestMap
// 함수역할:
// - 외부 지도 대신 상태 문구와 가로로 나열한 약국 선택 버튼을 표시한다.
// 매개변수:
// - pharmacies (List<NearbyPharmacy>): 가짜 지도 마커로 표시할 약국 목록.
// - selectedPharmacyId (String?): 현재 지도에서 초점을 맞춘 약국 식별자. 이 대역에서는 직접 사용하지 않는다.
// - onPharmacySelected (ValueChanged<NearbyPharmacy>): 지도에서 고른 약국을 전달받을 처리기.
// - onAttributionRequested (VoidCallback): 지도 출처 표시 요청 콜백. 이 대역에서는 직접 사용하지 않는다.
// - statusText (String?): 대체 지도 위젯에 표시할 선택적 상태 문구.
// - selectMarkerHint (String): 약국 마커 선택에 대한 접근성 힌트. 이 대역에서는 직접 사용하지 않는다.
// - zoomInTooltip (String): 지도 생성 계약의 번역된 확대 안내 문구. 이 대역에서는 직접 사용하지 않는다.
// - zoomOutTooltip (String): 지도 생성 계약의 번역된 축소 안내 문구. 이 대역에서는 직접 사용하지 않는다.
// - configurationUnavailableText (String): 지도 계약이 전달하는 설정 누락 안내 문구. 이 대역에서는 직접 사용하지 않는다.
// - unavailableText (String): 지도 데이터를 사용할 수 없을 때의 대체 문구. 이 대역에서는 직접 사용하지 않는다.
// 반환값:
// - 높이 80의 지도 대체 위젯.
Widget _buildTestMap({
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
  return SizedBox(
    key: const Key('test-nearby-pharmacy-map'),
    height: 80,
    child: Column(
      children: [
        if (statusText != null) Text('map-status:$statusText'),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: pharmacies
                .map(
                  // 함수이름: map 콜백
                  // 함수역할:
                  // - 각 약국에 안정된 키와 선택 콜백을 가진 가짜 지도 마커 버튼을 만든다.
                  // 매개변수:
                  // - pharmacy (NearbyPharmacy): 선택 마커에 대응하는 약국.
                  // 반환값:
                  // - 약국명을 표시하는 TextButton.
                  (pharmacy) => TextButton(
                    key: ValueKey('test-map-marker-${pharmacy.pharmacyId}'),
                    // 함수이름: onPressed 콜백
                    // 함수역할:
                    // - 가짜 지도 마커를 누르면 해당 약국을 선택 처리기에 전달한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값:
                    // - 없음; 선택 콜백이 실행된다.
                    onPressed: () => onPharmacySelected(pharmacy),
                    child: Text('map:${pharmacy.name}'),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    ),
  );
}

// 함수이름: main
// 함수역할:
// - 약국 필터, 지도 선택, 위치 오류와 새로고침 제한 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  testWidgets('device dot stays at the fix when the search area moves', (tester) async {
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    var map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    final fix = map.deviceLocation;
    expect(fix, isNotNull);
    const moved = PharmacySearchArea(
      center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
      isMapArea: true,
    );
    await map.onSearchAreaRequested!(moved);
    await tester.pumpAndSettle();
    map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(map.searchArea.center.longitude, moved.center.longitude);
    expect(map.deviceLocation, same(fix));
  });

  testWidgets('fallback search never pretends to be the device position', (tester) async {
    final control = _buildControl(failure: DeviceLocationFailure.serviceDisabled);
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    final map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(map.searchArea.isFallback, isTrue);
    expect(map.deviceLocation, isNull);
  });
  testWidgets('stale background resume refreshes once; brief inactive does not', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 12, 10);
    final times = <DateTime>[];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      _testApp(_buildControl(requestedTimes: times), clock: () => now),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(times, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(times, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(times, hasLength(2));
    expect(times.last, now);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(times, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume queues one fresh search behind an in-flight old request', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 12, 23, 59, 50);
    final times = <DateTime>[];
    final response = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          requestedTimes: times,
          beforeResponse: () async {
            if (times.length == 1) await response.future;
          },
        ),
        clock: () => now,
      ),
    );
    await tester.pump();
    expect(times, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(times, hasLength(1));
    response.complete();
    await tester.pumpAndSettle();
    expect(times, hasLength(2));
    expect(times.last, now);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filter search advances past midnight and labels reference time',
    (tester) async {
      var now = DateTime(2026, 9, 11, 20, 30);
      final requestedTimes = <DateTime>[];
      await tester.pumpWidget(
        _testApp(
          _buildControl(requestedTimes: requestedTimes),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(requestedTimes.single, now);
      now = DateTime(2026, 9, 12, 0, 50);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pharmacy-filter-option-lateHours')),
      );
      await tester.pumpAndSettle();
      expect(requestedTimes.last, now);
      expect(find.text('조회 날짜: 2026-09-12 00:50'), findsOneWidget);
      expect(find.text('조회 시각 영업'), findsWidgets);
      expect(find.text('영업 중'), findsNothing);
      expect(find.textContaining('조회일 '), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 지도 설정 누락과 약국 좌표 누락을 서로 다르게 안내한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('지도 설정 누락과 약국 좌표 누락을 서로 다르게 안내한다', (tester) async {
    const pharmacy = NearbyPharmacy(
      pharmacyId: 'configured-location',
      name: '좌표가 있는 약국',
      address: '서울특별시 마포구',
      telephone: '02-000-0000',
      latitude: 37.5515,
      longitude: 126.9249,
      distanceKm: 0.2,
      todayOpenTime: '09:00',
      todayCloseTime: '18:00',
      isOpenNow: true,
      is24Hours: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyPharmacyMap(
            pharmacies: const [pharmacy],
            selectedPharmacyId: null,
            // 함수이름: onPharmacySelected 콜백
            // 함수역할:
            // - 약국 선택 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - _ (NearbyPharmacy): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onPharmacySelected: (_) {},
            // 함수이름: onAttributionRequested 콜백
            // 함수역할:
            // - 지도 출처 표시 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - 없음.
            // 반환값:
            // - 없음; 외부 동작을 수행하지 않는다.
            onAttributionRequested: () {},
            statusText: null,
            selectMarkerHint: '약국 선택',
            zoomInTooltip: '확대',
            zoomOutTooltip: '축소',
            configurationUnavailableText: '지도 설정이 없습니다.',
            unavailableText: '약국 좌표가 없습니다.',
          ),
        ),
      ),
    );

    expect(find.text('지도 설정이 없습니다.'), findsOneWidget);
    expect(find.text('약국 좌표가 없습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 영업 중 약국을 우선 표시하고 필터에 따라 영업 종료 약국을 제외하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('shows open pharmacies first and filters closed pharmacies', (
    tester,
  ) async {
    var requestCount = 0;
    final requestedModes = <String?>[];
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          // Function Name: onRequest callback
          // Description:
          // - Count pharmacy refresh requests to detect repeated requests during the cooldown.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the callback completes after its recorded side effects.
          onRequest: () => requestCount += 1,
          requestedModes: requestedModes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
    final mapSize = tester.getSize(
      find.byKey(const Key('test-nearby-pharmacy-map')),
    );
    expect(mapSize.height, greaterThan(224));
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('영업중 메드버디약국'), findsOneWidget);
    expect(find.text('영업종료 메드버디약국'), findsNothing);
    expect(find.text('영업 중'), findsWidgets);
    expect(find.text('24시간'), findsNothing);
    expect(find.text('조회 조건: 현재 영업 중'), findsOneWidget);
    expect(find.byKey(const Key('pharmacy-search-date')), findsNothing);
    expect(find.textContaining('시각:'), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byKey(const Key('test-nearby-pharmacy-map')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final mapElement = tester.element(
      find.byKey(const Key('test-nearby-pharmacy-map')),
    );
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byKey(const Key('test-nearby-pharmacy-map'))),
      same(mapElement),
    );
    expect(requestCount, 1);
    await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
    await tester.pumpAndSettle();
    expect(find.text('공공심야약국'), findsNothing);
    expect(find.text('늦게까지 영업'), findsOneWidget);
    expect(find.text('주말·공휴일 영업'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pharmacy-filter-option-all')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pharmacy-card-closed')),
      180,
      scrollable: find.byType(Scrollable).last,
    );

    expect(requestCount, 2);
    expect(requestedModes, ['open_at_time', 'all']);
    expect(
      find.byKey(const ValueKey('test-map-marker-closed')),
      findsOneWidget,
    );
    expect(
      tester.element(find.byKey(const Key('test-nearby-pharmacy-map'))),
      same(mapElement),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('영업종료 메드버디약국'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('pharmacy-filter-option-openNow')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-map-marker-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-map-marker-closed')), findsNothing);
    expect(find.byKey(const ValueKey('pharmacy-card-closed')), findsNothing);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영업 중 약국에서 늦게까지 운영하는 결과를 먼저 표시한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영업 중 약국에서 늦게까지 운영하는 결과를 먼저 표시한다', (tester) async {
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          customPharmacies: const [
            {
              'pharmacy_id': 'regular',
              'name': '일반 운영 약국',
              'address': '서울특별시 마포구',
              'telephone': '',
              'latitude': 37.5666,
              'longitude': 126.9781,
              'distance_km': 0.1,
              'today_open_time': '09:00',
              'today_close_time': '18:00',
              'is_open_now': true,
              'is_open_late': false,
              'is_24_hours': false,
            },
            {
              'pharmacy_id': 'late',
              'name': '늦게까지 운영 약국',
              'address': '서울특별시 마포구',
              'telephone': '',
              'latitude': 37.5667,
              'longitude': 126.9782,
              'distance_km': 0.8,
              'today_open_time': '09:00',
              'today_close_time': '23:00',
              'is_open_now': true,
              'is_open_late': true,
              'is_24_hours': false,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lateMarker = find.byKey(const ValueKey('test-map-marker-late'));
    final regularMarker = find.byKey(const ValueKey('test-map-marker-regular'));
    expect(lateMarker, findsOneWidget);
    expect(regularMarker, findsOneWidget);
    expect(
      tester.getTopLeft(lateMarker).dx,
      lessThan(tester.getTopLeft(regularMarker).dx),
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 약국 카드 선택이 지도 선택 표시와 일치하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('selecting a pharmacy card updates the map focus state', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_buildControl()));
    await tester.pumpAndSettle();

    expect(
      find.text('map-status:지도 표시를 누르거나 약국 목록을 열어 상세 정보를 확인하세요'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pharmacy-card-open')));
    await tester.pump();

    expect(find.textContaining('map-status:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 길찾기는 실행 방법을 묻고 주소 복사를 지원한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('길찾기는 실행 방법을 묻고 주소 복사를 지원한다', (tester) async {
    String? copiedAddress;
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          // 함수이름: clipboardWriter 콜백
          // 함수역할:
          // - 클립보드에 복사할 약국 주소를 실제 시스템 쓰기 없이 기록한다.
          // 매개변수:
          // - value (String): 클립보드 쓰기 함수에 전달한 약국 주소.
          // 반환값:
          // - Future<void>; 주소 기록 완료.
          clipboardWriter: (value) async {
            copiedAddress = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    final directionsButton = find.byKey(
      const ValueKey('pharmacy-directions-open'),
    );
    await tester.ensureVisible(directionsButton);
    await tester.tap(directionsButton);
    await tester.pumpAndSettle();

    expect(find.text('어떤 앱으로 여시겠습니까?'), findsOneWidget);
    expect(
      find.byKey(const Key('directions-choice-installed-app')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('directions-choice-google-maps')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('directions-choice-copy-address')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('directions-choice-copy-address')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('약국 주소를 복사했습니다.'), findsOneWidget);
    expect(copiedAddress, '서울특별시 종로구');
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 필터 검색 결과가 없어도 전체 보기로 바꾸면 데이터를 다시 조회하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('show all reloads data after an empty filtered search', (
    tester,
  ) async {
    final requestedModes = <String?>[];
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          requestedModes: requestedModes,
          emptyModes: const {'late_hours'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('pharmacy-filter-option-lateHours')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('심야 운영 약국이 없습니다'), findsOneWidget);
    expect(find.byKey(const Key('pharmacy-search-date')), findsOneWidget);
    expect(find.textContaining('시각:'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('전체 약국 보기'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('전체 약국 보기'));
    await tester.pumpAndSettle();

    expect(requestedModes, ['open_at_time', 'late_hours', 'all']);
    expect(find.text('영업중 메드버디약국'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 위치 서비스가 꺼져도 홍익대 기준 안내와 지도를 표시하는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('shows Hongik fallback when location service is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(_buildControl(failure: DeviceLocationFailure.serviceDisabled)),
    );
    await tester.pumpAndSettle();

    expect(find.text('위치를 확인하지 못해 홍익대학교 서울캠퍼스 기준으로 검색했어요.'), findsOneWidget);
    expect(find.byKey(const Key('test-nearby-pharmacy-map')), findsOneWidget);
    expect(find.text('기기 위치가 꺼져 있습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 대기시간 안의 반복 새로고침이 추가 조회를 만들지 않는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('limits repeated refresh requests during the cooldown', (
    tester,
  ) async {
    var requestCount = 0;
    await tester.pumpWidget(
      // 함수이름: onRequest 콜백
      // 함수역할:
      // - 약국 조회 횟수를 기록해 대기시간 내 중복 요청을 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 없음; 기록 또는 상태 변경을 마친다.
      _testApp(_buildControl(onRequest: () => requestCount += 1)),
    );
    await tester.pumpAndSettle();
    expect(requestCount, 1);

    final refreshButton = find.byTooltip('약국 목록 새로고침');
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(requestCount, 2);

    await tester.tap(refreshButton);
    await tester.pump();
    expect(requestCount, 2);
    expect(find.text('새로고침 요청이 많습니다. 잠시 후 다시 시도해주세요.'), findsOneWidget);

    await tester.pump(_refreshTestCooldown);
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(requestCount, 3);
  });
}

const _refreshTestCooldown = Duration(seconds: 10);
