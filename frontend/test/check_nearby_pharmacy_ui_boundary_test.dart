// 파일명: check_nearby_pharmacy_ui_boundary_test.dart
// 역할: 근처 약국 화면의 결과·필터·위치 오류 상태를 검증한다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
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
}) {
  return CheckNearbyPharmacy(
    locationBoundary: _FakeLocationBoundary(failure: failure),
    client: MockClient((_) async {
      onRequest?.call();
      return http.Response(
        jsonEncode({
          'data': [
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
      ),
    ),
  );
}

void main() {
  testWidgets('shows open pharmacies first and filters closed pharmacies', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_buildControl()));
    await tester.pumpAndSettle();

    expect(find.text('영업중 메드버디약국'), findsOneWidget);
    expect(find.text('영업종료 메드버디약국'), findsNothing);
    expect(find.text('영업 중'), findsWidgets);
    expect(find.text('24시간'), findsNothing);
    expect(find.text('전체'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();

    expect(find.text('영업종료 메드버디약국'), findsOneWidget);
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
