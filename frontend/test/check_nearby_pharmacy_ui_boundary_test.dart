// 파일명: check_nearby_pharmacy_ui_boundary_test.dart
// 역할: 근처 약국 화면의 결과·필터·위치 오류 상태를 검증한다.

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

class _FakeLocationBoundary implements DeviceLocationBoundary {
  final DeviceLocationFailure? failure;

  const _FakeLocationBoundary({this.failure});

  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async {
    if (failure != null) {
      throw DeviceLocationException(failure!);
    }
    return const DeviceCoordinate(latitude: 37.5665, longitude: 126.9780);
  }

  @override
  Future<bool> openApplicationSettings() async => true;

  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

CheckNearbyPharmacy _buildControl({
  DeviceLocationFailure? failure,
  VoidCallback? onRequest,
  List<String?>? requestedModes,
  Set<String> emptyModes = const {},
}) {
  return CheckNearbyPharmacy(
    locationBoundary: _FakeLocationBoundary(failure: failure),
    client: MockClient((request) async {
      onRequest?.call();
      final requestedMode = request.url.queryParameters['search_mode'];
      requestedModes?.add(requestedMode);
      final includeClosed = requestedMode == 'all';
      final isEmpty = emptyModes.contains(requestedMode);
      return http.Response(
        jsonEncode({
          'data': [
            if (!isEmpty) ...[
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
            ],
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    uriLauncher: (_) async => true,
  );
}

Widget _testApp(CheckNearbyPharmacy control) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 640),
        textScaler: TextScaler.linear(1.6),
      ),
      child: CheckNearbyPharmacyUI(
        userSetting: const UserSetting(fontSize: 20),
        control: control,
        mapBuilder: _buildTestMap,
      ),
    ),
  );
}

Widget _buildTestMap({
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
                  (pharmacy) => TextButton(
                    key: ValueKey('test-map-marker-${pharmacy.pharmacyId}'),
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

void main() {
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
            onPharmacySelected: (_) {},
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

  testWidgets('shows open pharmacies first and filters closed pharmacies', (
    tester,
  ) async {
    var requestCount = 0;
    final requestedModes = <String?>[];
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          onRequest: () => requestCount += 1,
          requestedModes: requestedModes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('영업중 메드버디약국'), findsOneWidget);
    expect(find.text('영업종료 메드버디약국'), findsNothing);
    expect(find.text('영업 중'), findsWidgets);
    expect(find.text('24시간'), findsNothing);
    expect(find.text('조회 조건: 선택 시각에 영업'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byKey(const Key('test-nearby-pharmacy-map')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
    await tester.pumpAndSettle();
    expect(find.text('공공심야약국'), findsOneWidget);
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('영업종료 메드버디약국'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a pharmacy card updates the map focus state', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_buildControl()));
    await tester.pumpAndSettle();

    expect(
      find.text('map-status:아래 약국을 누르면 지도에서 위치를 확인할 수 있습니다'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pharmacy-card-open')));
    await tester.pump();

    expect(find.textContaining('map-status:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('show all reloads data after an empty filtered search', (
    tester,
  ) async {
    final requestedModes = <String?>[];
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          requestedModes: requestedModes,
          emptyModes: const {'official_late_night'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('pharmacy-filter-option-officialLateNight')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('공식 지정 공공심야약국이 없습니다'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('전체 약국 보기'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('전체 약국 보기'));
    await tester.pumpAndSettle();

    expect(requestedModes, ['open_at_time', 'official_late_night', 'all']);
    expect(find.text('영업중 메드버디약국'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a clear action when location service is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(_buildControl(failure: DeviceLocationFailure.serviceDisabled)),
    );
    await tester.pumpAndSettle();

    expect(find.text('기기 위치가 꺼져 있습니다'), findsOneWidget);
    expect(find.text('위치 설정 열기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limits repeated refresh requests during the cooldown', (
    tester,
  ) async {
    var requestCount = 0;
    await tester.pumpWidget(
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
