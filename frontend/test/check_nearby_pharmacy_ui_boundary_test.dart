// 파일명: check_nearby_pharmacy_ui_boundary_test.dart
// 역할: 근처 약국 화면의 결과·필터·위치 오류 상태를 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/nearby_pharmacy_map_widget.dart';
import 'package:medbuddy_frontend/controls/check_nearby_pharmacy_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/device_location_service.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

// 클래스명: _DelayedFavorites
// 역할: 즐겨찾기 초기 조회와 저장의 지연·거절·예외를 재현한다.
// 주요 책임: 실제 기기 저장소 없이 요청 ID 사본을 기록하고 테스트가 각 비동기 결과를 완료하게 한다.
// 속성: writes: 저장별 완료 신호; requestedIds: 저장 요청 ID 집합 사본; initialLoad: 선택적 초기 조회 완료 신호.
class _DelayedFavorites extends PharmacyFavoriteService {
  final writes = <Completer<bool>>[];
  final requestedIds = <Set<String>>[];
  Completer<Set<String>>? initialLoad;
  // 함수이름: loadFavoriteIds
  // 함수역할: 초기 조회 신호가 있으면 기다리고 없으면 다른 약국의 기존 즐겨찾기를 제공한다.
  // 매개변수: 없음.
  // 반환값: Future<Set<String>>: 주입한 조회 결과 또는 existing ID 집합; 주입한 비동기 오류는 전파한다.
  @override
  Future<Set<String>> loadFavoriteIds() async =>
      initialLoad == null ? {'existing'} : await initialLoad!.future;
  // 함수이름: saveFavoriteIds
  // 함수역할: 저장 요청을 기록하고 테스트가 완료할 때까지 대기한다.
  // 매개변수: pharmacyIds 저장할 ID 집합. 반환값: 저장 성공 여부.
  @override
  Future<bool> saveFavoriteIds(Set<String> pharmacyIds) {
    final result = Completer<bool>();
    writes.add(result);
    requestedIds.add(Set.of(pharmacyIds));
    return result.future;
  }
}

// 클래스명: _FakeLocationBoundary
// 역할: 현재 위치 성공·실패와 기기 설정 이동을 대신하는 위치 경계.
// 주요 책임: 주입한 위치 오류를 던지거나 고정 서울 좌표를 반환하고 설정 이동은 실제 화면 없이 성공 처리한다.
// 속성: failure (DeviceLocationFailure?): 재현할 위치 실패, null이면 좌표 조회 성공.
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

// Function Name: _buildControl
// Description: Build a pharmacy controller with recorded search modes/times, configurable HTTP rows and holiday verification, and injectable external actions.
// Parameters: failure (DeviceLocationFailure?): Location error; onRequest (VoidCallback?): Request observer; requestedModes (List<String?>?): Captured modes; requestedTimes (List<DateTime>?): Parsed target datetimes; beforeResponse (Future<void> Function()?): Response gate or injected failure; emptyModes (Set<String>): Modes returning no rows; holidayScheduleStatus (String): Calendar-verification status; customPharmacies (List<Map<String, Object?>>?): Row override; uriLauncher (Future<bool> Function(Uri)?): External-app substitute; clipboardWriter (Future<void> Function(String)?): Clipboard substitute.
// Returns: CheckNearbyPharmacy: Mock-backed controller; callbacks may delay or fail requests, and the default URI launcher reports success without opening an app.
CheckNearbyPharmacy _buildControl({
  DeviceLocationFailure? failure,
  VoidCallback? onRequest,
  List<String?>? requestedModes,
  List<DateTime>? requestedTimes,
  Future<void> Function()? beforeResponse,
  Set<String> emptyModes = const {},
  String holidayScheduleStatus = 'not_applicable',
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
        jsonEncode({
          'data': responseData,
          'holiday_schedule_status': holidayScheduleStatus,
        }),
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
// 함수역할: 360x640 MediaQuery와 주입한 지도·시계·즐겨찾기를 사용해 약국 화면을 감싼다.
// 매개변수: control (CheckNearbyPharmacy): 호출자가 수명을 관리할 제어기; clock (DateTime Function()?): 기준 시각; nativeMap (bool): 실제 지도 위젯 사용 여부; language (String): 표시 언어; textScale (double): 글자 배율; favoriteService (PharmacyFavoriteService?): 즐겨찾기 저장소 대역.
// 반환값: Widget: 약국 화면을 담은 MaterialApp; 기본값은 1.6배 글씨와 버튼형 지도 대역이다.
Widget _testApp(
  CheckNearbyPharmacy control, {
  DateTime Function()? clock,
  bool nativeMap = false,
  String language = 'ko',
  double textScale = 1.6,
  PharmacyFavoriteService? favoriteService,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(360, 640),
        textScaler: TextScaler.linear(textScale),
      ),
      child: CheckNearbyPharmacyUI(
        userSetting: UserSetting(fontSize: 20, language: language),
        control: control,
        clock: clock,
        favoriteService: favoriteService,
        mapBuilder: nativeMap ? null : _buildTestMap,
      ),
    ),
  );
}

// Function Name: _buildTestMap
// Description: Render an 80-pixel map substitute with optional status text and horizontal pharmacy buttons that forward selections.
// Parameters: searchArea (NearbyCareSearchArea), centerRevision (int), isSearching (bool): Accepted map state, unused here; onSearchAreaRequested (Future<bool> Function(NearbyCareSearchArea)), onCurrentLocationRequested (VoidCallback): Unused search actions; pharmacies (List<NearbyCarePlace>): Button data; selectedPharmacyId (String?): Unused focus ID; onPharmacySelected (ValueChanged<NearbyCarePlace>): Invoked by a button; onAttributionRequested (VoidCallback): Unused attribution action; statusText (String?): Optional visible status; selectMarkerHint, zoomInTooltip, zoomOutTooltip, configurationUnavailableText, unavailableText (String): Accepted but unused localized map labels.
// Returns: Widget: Fixed-height status/selection layout with no native map or network access.
Widget _buildTestMap({
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
  return SizedBox(
    key: const Key('test-nearby-pharmacy-map'),
    height: 80,
    child: Column(
      children: [
        if (statusText != null)
          Text(
            'map-status:$statusText',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: pharmacies
                .map(
                  // 함수이름: map 콜백
                  // 함수역할:
                  // - 각 약국에 안정된 키와 선택 콜백을 가진 가짜 지도 마커 버튼을 만든다.
                  // 매개변수:
                  // - pharmacy (NearbyCarePlace): 선택 마커에 대응하는 약국.
                  // 반환값:
                  // - 약국명을 표시하는 TextButton.
                  (pharmacy) => TextButton(
                    key: ValueKey('test-map-marker-${pharmacy.placeId}'),
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

// 함수이름: _applySearchFilter
// 함수역할: 조회 조건 초안을 스크롤해 선택한 뒤 적용 버튼으로 실제 검색에 반영한다.
// 매개변수: tester (WidgetTester): 화면 제어기; option (String): pharmacy-filter-option 키에 넣을 검색 조건.
// 반환값: Future<void>: 선택·적용과 결과 화면 안정화 완료.
Future<void> _applySearchFilter(WidgetTester tester, String option) async {
  final target = find.byKey(ValueKey('pharmacy-filter-option-$option'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('care-filter-apply')));
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할: 약국 검색 초안, 위치·지도, 즐겨찾기, 외부 앱 및 화면 수명 회귀 테스트를 등록한다.
// 매개변수: 없음.
// 반환값: void: 테스트 등록만 수행하며 검증은 각 콜백에서 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할: 즐겨찾기 저장소를 격리한다. 매개변수: 없음. 반환값: 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final apply in [false, true]) {
    // 함수이름: testWidgets: 'rapid filter and date drafts send only the final choice: $apply'
    // 함수역할: 필터와 날짜 초안을 연속 변경한 뒤 적용 또는 닫기를 선택하고 지연 응답을 해제한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 적용 전에는 최초 요청뿐이고 적용 시 최종 all·9월 29일 정오만 추가 요청하며 대기 중 선택 버튼은 비활성화된다.
    testWidgets(
      'rapid filter and date drafts send only the final choice: $apply',
      (tester) async {
        final modes = <String?>[];
        final times = <DateTime>[];
        final response = Completer<void>();
        final control = _buildControl(
          requestedModes: modes,
          requestedTimes: times,
          beforeResponse: () async {
            if (modes.length > 1) await response.future;
          },
        );
        addTearDown(control.dispose);
        await tester.binding.setSurfaceSize(const Size(420, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _testApp(
            control,
            textScale: 1,
            clock: () => DateTime(2026, 9, 28, 10),
          ),
        );
        await tester.pumpAndSettle();
        final selector = find.byKey(const Key('pharmacy-map-filter-selector'));
        await tester.tap(selector);
        await tester.pumpAndSettle();
        for (final filter in ['all', 'lateHours', 'weekendHoliday', 'all']) {
          await tester.tap(
            find.byKey(ValueKey('pharmacy-filter-option-$filter')),
          );
        }
        await tester.pumpAndSettle();
        for (final day in ['30', '29']) {
          await tester.tap(find.byKey(const Key('care-filter-date')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(day));
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        }
        expect(modes, ['open_at_time']);
        await tester.tap(
          apply
              ? find.byKey(const Key('care-filter-apply'))
              : find.byTooltip('닫기'),
        );
        await tester.pump();
        if (apply) {
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.widget<OutlinedButton>(selector).onPressed, isNull);
          await tester.tap(selector);
          expect(modes, ['open_at_time', 'all']);
          expect(times.last, DateTime(2026, 9, 29, 12));
        }
        response.complete();
        await tester.pumpAndSettle();
        expect(modes, apply ? ['open_at_time', 'all'] : ['open_at_time']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final fail in [false, true]) {
    // 함수이름: testWidgets: 'late pharmacy search is inert after disposal: $fail'
    // 함수역할: 최초 검색 응답을 보류한 채 화면을 제거하고 성공 또는 오류로 완료한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 검색은 한 번뿐이며 해제된 화면에 대한 예외가 발생하지 않는다.
    testWidgets('late pharmacy search is inert after disposal: $fail', (
      tester,
    ) async {
      final response = Completer<void>();
      final modes = <String?>[];
      final control = _buildControl(
        requestedModes: modes,
        beforeResponse: () => response.future,
      );
      addTearDown(control.dispose);
      await tester.pumpWidget(_testApp(control));
      await tester.pump();
      expect(modes, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      if (fail) {
        response.completeError(StateError('늦은 검색 실패'));
      } else {
        response.complete();
      }
      await tester.pumpAndSettle();
      expect(modes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final apply in [false, true]) {
    // 함수이름: testWidgets: 'conditions double dismissal keeps the nearby route: $apply'
    // 함수역할: 이전 화면 위에 약국을 열고 조건 변경 후 적용 또는 닫기를 연속 두 번 누른다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 약국 경로가 남아 뒤로 이동할 수 있고 적용한 경우에만 all 검색이 추가된다.
    testWidgets('conditions double dismissal keeps the nearby route: $apply', (
      tester,
    ) async {
      final modes = <String?>[];
      final control = _buildControl(requestedModes: modes);
      addTearDown(control.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('previous screen')),
        ),
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => CheckNearbyPharmacyUI(
              userSetting: const UserSetting(language: 'ko'),
              control: control,
              mapBuilder: _buildTestMap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-map-filter-selector')));
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('pharmacy-filter-option-all'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      final dismiss = apply
          ? find.byKey(const Key('care-filter-apply'))
          : find.byTooltip('닫기');
      // 닫힘 프레임이 반영되기 전에 같은 버튼을 다시 누른다.
      await tester.tap(dismiss);
      await tester.tap(dismiss, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(CheckNearbyPharmacyUI), findsOneWidget);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(modes, apply ? ['open_at_time', 'all'] : ['open_at_time']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // 함수이름: testWidgets: 'conditions rapid opening creates only one sheet'
  // 함수역할: 지도 조건 버튼을 프레임 갱신 전에 두 번 누르고 열린 시트를 닫는다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 숨겨진 경로까지 포함해 BottomSheet는 하나이며 닫은 뒤 남지 않는다.
  testWidgets('conditions rapid opening creates only one sheet', (
    tester,
  ) async {
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control));
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('pharmacy-map-filter-selector'));
    await tester.tap(selector);
    await tester.tap(selector, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: testWidgets: 'conditions rapid date opening creates only one calendar'
  // 함수역할: 조건에서 전체 약국을 선택하고 날짜 버튼을 빠르게 두 번 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 숨겨진 경로까지 포함해 달력 대화상자가 하나만 열린다.
  testWidgets('conditions rapid date opening creates only one calendar', (
    tester,
  ) async {
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-map-filter-selector')));
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('pharmacy-filter-option-all'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    final date = find.byKey(const Key('care-filter-date'));
    await tester.ensureVisible(date);
    await tester.pumpAndSettle();
    await tester.tap(date);
    await tester.tap(date, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog, skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dispose in [false, true]) {
    for (final installed in [false, true]) {
      // 함수이름: testWidgets: 'late directions failure starts no fallback after leaving: dispose=$dispose installed=$installed'
      // 함수역할: 설치 앱 또는 Google Maps 실행을 보류한 채 약국 화면을 해제하거나 다른 경로로 덮고 실패 응답을 완료한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 반환값 없음; 외부 실행은 최초 한 번뿐이고 주소 복사 등 후속 대체 동작이나 위젯 예외가 없다.
      testWidgets(
        'late directions failure starts no fallback after leaving: dispose=$dispose installed=$installed',
        (tester) async {
          final response = Completer<bool>();
          final launches = <Uri>[];
          final copies = <String>[];
          final control = _buildControl(
            uriLauncher: (uri) {
              launches.add(uri);
              return response.future;
            },
            clipboardWriter: (value) async => copies.add(value),
          );
          addTearDown(control.dispose);
          await tester.pumpWidget(_testApp(control));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
          await tester.pumpAndSettle();
          final directions = find.byKey(const Key('pharmacy-directions-open'));
          await tester.ensureVisible(directions);
          await tester.tap(directions);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(
              Key(
                installed
                    ? 'directions-choice-installed-app'
                    : 'directions-choice-google-maps',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(launches, hasLength(1));
          if (dispose) {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            unawaited(
              Navigator.of(
                tester.element(find.byType(CheckNearbyPharmacyUI)),
              ).push<void>(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('다른 화면')),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          response.complete(false);
          await tester.pumpAndSettle();
          expect(launches, hasLength(1));
          expect(copies, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets: 'pharmacy date lives inside conditions in $language'
    // 함수역할: 한국어·영어의 작은 화면에서 조건 내부 날짜를 9월 30일로 바꾸고 적용·재진입·달력 취소를 수행한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 적용 시 정오 기준 요청만 추가되고 값이 유지되며 지도 높이·외부 날짜 표시와 중복 요청이 바뀌지 않는다.
    testWidgets('pharmacy date lives inside conditions in $language', (
      tester,
    ) async {
      final times = <DateTime>[];
      final control = _buildControl(requestedTimes: times);
      addTearDown(control.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _testApp(
          control,
          language: language,
          clock: () => DateTime(2026, 9, 28, 21, 26),
        ),
      );
      await tester.pumpAndSettle();
      final map = find.byKey(const Key('test-nearby-pharmacy-map'));
      final height = tester.getSize(map).height;
      final selector = find.byKey(const Key('pharmacy-map-filter-selector'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text(language == 'ko' ? '날짜' : 'Date'), findsOneWidget);
      expect(
        find.text(language == 'ko' ? '영업 상태' : 'Business status'),
        findsOneWidget,
      );
      final option = find.byKey(const ValueKey('pharmacy-filter-option-all'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      final date = find.byKey(const Key('care-filter-date'));
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(times, hasLength(1));
      await tester.tap(find.byKey(const Key('care-filter-apply')));
      await tester.pumpAndSettle();
      expect(times.last, DateTime(2026, 9, 30, 12));
      expect(times, hasLength(2));
      expect(find.byKey(const Key('pharmacy-map-search-date')), findsNothing);
      expect(tester.getSize(map).height, height);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('2026-09-30'), findsOneWidget);
      expect(find.textContaining('12:00'), findsNothing);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-30'), findsOneWidget);
      await tester.tap(find.byKey(const Key('care-filter-apply')));
      await tester.pumpAndSettle();
      expect(times, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 즐겨찾기 중복 저장 차단 테스트
  // 함수역할: 저장이 완료되지 않은 동안 중복 클릭으로 저장 순서가 뒤집히지 않도록 한다.
  // 매개변수: tester 화면 시험 도구. 반환값: 검증 완료 Future.
  testWidgets('즐겨찾기 저장 중 연속 입력은 한 번만 처리한다', (tester) async {
    final favorites = _DelayedFavorites();
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(
      _testApp(control, favoriteService: favorites, textScale: 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    final star = find.byKey(const Key('pharmacy-detail-favorite'));
    await tester.tap(star);
    await tester.pump();
    await tester.tap(star);
    await tester.pump();
    final count = favorites.writes.length;
    for (final write in favorites.writes) {
      write.complete(true);
    }
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(favorites.requestedIds.single, {'existing', 'open'});
    expect(tester.widget<IconButton>(star).tooltip, '즐겨찾기 해제');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final throwsError in [false, true]) {
    // 함수이름: 즐겨찾기 저장 실패 복구 테스트
    // 함수역할: 거절·저장소 예외에서 선택 상태를 복원하고 사용자에게 실패를 알린다.
    // 매개변수: tester 화면 시험 도구. 반환값: 검증 완료 Future.
    testWidgets('즐겨찾기 저장 실패를 복구한다: throws=$throwsError', (tester) async {
      final favorites = _DelayedFavorites();
      final control = _buildControl();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        _testApp(control, favoriteService: favorites, textScale: 1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-map-marker-open')));
      await tester.pumpAndSettle();
      final star = find.byKey(const Key('pharmacy-detail-favorite'));
      await tester.tap(star);
      await tester.pump();
      if (throwsError) {
        favorites.writes.single.completeError(
          StateError('Simulated storage failure'),
        );
      } else {
        favorites.writes.single.complete(false);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<IconButton>(star).tooltip, '즐겨찾기 추가');
      expect(find.textContaining('즐겨찾기를 저장하지 못'), findsOneWidget);
      await tester.tap(star);
      await tester.pump();
      expect(favorites.requestedIds.last, {'existing', 'open'});
      favorites.writes.last.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(star).tooltip, '즐겨찾기 해제');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final throwsError in [false, true]) {
    // 함수이름: 즐겨찾기 초기 조회 보호 테스트
    // 함수역할: 저장 목록을 알기 전에는 쓰기를 막고 조회 실패로 기존 목록을 덮어쓰지 않는다.
    // 매개변수: tester 화면 시험 도구. 반환값: 검증 완료 Future.
    testWidgets('즐겨찾기 초기 조회가 끝나야 변경할 수 있다: throws=$throwsError', (
      tester,
    ) async {
      final initialLoad = Completer<Set<String>>();
      final favorites = _DelayedFavorites()..initialLoad = initialLoad;
      final control = _buildControl();
      addTearDown(control.dispose);
      await tester.pumpWidget(
        _testApp(control, favoriteService: favorites, textScale: 1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-map-marker-open')));
      await tester.pumpAndSettle();
      final star = find.byKey(const Key('pharmacy-detail-favorite'));
      expect(tester.widget<IconButton>(star).onPressed, isNull);
      if (throwsError) {
        initialLoad.completeError(StateError('Simulated load failure'));
      } else {
        initialLoad.complete({'existing', 'open'});
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(favorites.writes, isEmpty);
      if (throwsError) {
        expect(tester.widget<IconButton>(star).onPressed, isNull);
        expect(find.textContaining('즐겨찾기를 불러오지 못'), findsOneWidget);
      } else {
        expect(tester.widget<IconButton>(star).tooltip, '즐겨찾기 해제');
        await tester.tap(star);
        await tester.pump();
        expect(favorites.requestedIds.single, {'existing'});
        favorites.writes.single.complete(true);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // 함수이름: 즐겨찾기 저장 중 화면 종료 테스트
  // 함수역할: 화면을 닫은 뒤 도착한 저장 실패가 해제된 위젯에 접근하지 않는지 검사한다.
  // 매개변수: tester 화면 시험 도구. 반환값: 검증 완료 Future.
  testWidgets('화면 종료 후 즐겨찾기 저장 실패도 안전하게 마무리한다', (tester) async {
    final favorites = _DelayedFavorites();
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(
      _testApp(control, favoriteService: favorites, textScale: 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-detail-favorite')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    favorites.writes.single.completeError(StateError('Simulated late failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 목록 상단 드래그 복귀 테스트
  // 함수역할: 지도 노출 간격과 드래그 닫기를 확인하고 선택·지도·조회 결과가 유지되는지 검증한다.
  // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
  testWidgets('dragging the list header reveals the same map and selection', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      _testApp(_buildControl(onRequest: () => requests++)),
    );
    await tester.pumpAndSettle();
    final mapFinder = find.byKey(const Key('test-nearby-pharmacy-map'));
    final map = tester.element(mapFinder);
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('pharmacy-list-panel'));
    expect(
      tester.getTopLeft(panel).dy - tester.getTopLeft(mapFinder).dy,
      closeTo(12, .1),
    );
    final before = tester.getTopLeft(panel).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pharmacy-list-handle'))),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(tester.getTopLeft(panel).dy, greaterThan(before));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byKey(const Key('pharmacy-detail-sheet')), findsOneWidget);
    expect(tester.element(mapFinder), same(map));
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 목록 드래그 취소·스크롤 분리 테스트
  // 함수역할: 짧은 이동·제스처 취소·목록 스크롤이 패널을 닫지 않는지 확인한다.
  // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'short or cancelled header drags restore the list and scrolling stays independent',
    (tester) async {
      await tester.pumpWidget(_testApp(_buildControl()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('pharmacy-list-panel'));
      final top = tester.getTopLeft(panel).dy;
      for (final cancel in [false, true]) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('pharmacy-list-handle'))),
        );
        await gesture.moveBy(const Offset(0, 24));
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.moveBy(Offset(0, cancel ? 120 : 8));
        await tester.pump(const Duration(milliseconds: 300));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(panel, findsOneWidget);
        expect(tester.getTopLeft(panel).dy, closeTo(top, .1));
      }
      final list = find.descendant(of: panel, matching: find.byType(ListView));
      await tester.drag(list, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.getTopLeft(panel).dy, closeTo(top, .1));
      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 목록 지도 복귀 명령 테스트
  // 함수역할: 손잡이 탭과 기존 하단 버튼이 모두 지도 복귀를 제공하는지 검증한다.
  // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'list handle tap and existing map button both return to the map',
    (tester) async {
      await tester.pumpWidget(_testApp(_buildControl()));
      await tester.pumpAndSettle();
      for (final key in ['pharmacy-list-handle', 'pharmacy-list-toggle']) {
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('지도 크게 보기'), findsOneWidget);
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    // 함수이름: 작은 화면 목록 손잡이 테스트
    // 함수역할: 큰 글씨에서도 상태 문구·손잡이가 겹치지 않고 드래그 복귀가 가능한지 검증한다.
    // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
    testWidgets(
      'small $language list keeps large-text header and handle reachable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _testApp(_buildControl(), language: language, textScale: 2),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        final handle = find.byKey(const Key('pharmacy-list-handle'));
        final filter = find.byKey(const Key('pharmacy-filter-selector'));
        expect(handle.hitTestable(), findsOneWidget);
        expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));
        expect(
          tester.getBottomLeft(handle).dy,
          lessThan(tester.getTopLeft(filter).dy),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(handle, const Offset(0, 160));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: 마커 상세창 테스트
  // 함수역할: 마커 선택, 접기·펼치기, 닫기와 지도 상태 보존을 검증한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('marker opens draggable details without replacing the map', (
    tester,
  ) async {
    var requestCount = 0;
    await tester.pumpWidget(
      _testApp(_buildControl(onRequest: () => requestCount++)),
    );
    await tester.pumpAndSettle();
    final map = tester.element(
      find.byKey(const Key('test-nearby-pharmacy-map')),
    );
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
    final sheet = find.byKey(const Key('pharmacy-detail-sheet'));
    expect(sheet, findsOneWidget);
    final expandedHeight = tester.getSize(sheet).height;
    await tester.drag(
      find.byKey(const Key('pharmacy-detail-handle')),
      const Offset(0, 280),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(sheet).height, lessThan(expandedHeight));
    expect(find.text('서울특별시 종로구'), findsNothing);
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pharmacy-detail-handle')));
    await tester.pumpAndSettle();
    expect(find.text('서울특별시 종로구'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(
      tester.element(find.byKey(const Key('test-nearby-pharmacy-map'))),
      same(map),
    );
    expect(requestCount, 1);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 내용 맞춤 높이 테스트
  // 함수역할: 두 상태의 버튼 아래 여백과 제목·아이콘 정렬을 검증한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('details fit content and align the title actions in both modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(_buildControl()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    for (var mode = 0; mode < 2; mode++) {
      final sheet = tester.getRect(
        find.byKey(const Key('pharmacy-detail-sheet')),
      );
      final directions = tester.getRect(
        find.byKey(const Key('pharmacy-directions-open')),
      );
      expect(sheet.bottom - directions.bottom, closeTo(8, .1));
      final name = tester.getRect(
        find.byKey(const Key('pharmacy-detail-name')),
      );
      final favorite = tester.getRect(
        find.byKey(const Key('pharmacy-detail-favorite')),
      );
      final close = tester.getRect(
        find.byKey(const Key('pharmacy-detail-close')),
      );
      final status = tester.getRect(
        find.byKey(const Key('pharmacy-detail-status')),
      );
      expect(name.center.dy, closeTo(favorite.center.dy, .1));
      expect(name.center.dy, closeTo(close.center.dy, .1));
      expect(status.top - name.bottom, lessThanOrEqualTo(14));
      expect(
        find.byKey(const Key('pharmacy-directions-open')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pharmacy-detail-handle')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 화면 크기 변경 테스트
  // 함수역할: 열린 정보창이 폭·높이 변경 후에도 내용 높이에 맞고 접힘 상태를 유지하는지 검증한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('open details refit after viewport changes', (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(_buildControl()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    for (var mode = 0; mode < 2; mode++) {
      for (final size in [const Size(360, 1000), const Size(600, 1100)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final sheet = tester.getRect(
          find.byKey(const Key('pharmacy-detail-sheet')),
        );
        final action = tester.getRect(
          find.byKey(const Key('pharmacy-directions-open')),
        );
        expect(sheet.bottom - action.bottom, closeTo(8, .1));
        expect(
          find.text('서울특별시 종로구'),
          mode == 0 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('pharmacy-detail-handle')));
      await tester.pumpAndSettle();
    }
  });

  // 함수이름: 지도 즐겨찾기 전달 테스트
  // 함수역할: 저장된 즐겨찾기를 지도에 전달하고 추가·해제 시 선택과 검색 중심을 유지한다.
  // 매개변수: tester: 화면 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'map favorites load and toggle without changing selection or center',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'medbuddy.favorite_pharmacy_ids': ['open'],
      });
      await tester.pumpWidget(_testApp(_buildControl(), nativeMap: true));
      await tester.pumpAndSettle();
      var map = tester.widget<NearbyPharmacyMap>(
        find.byType(NearbyPharmacyMap),
      );
      expect(map.favoritePharmacyIds, {'open'});
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-card-open')));
      await tester.pumpAndSettle();
      map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
      final revision = map.centerRevision;
      for (final favorites in [
        <String>{},
        {'open'},
      ]) {
        await tester.tap(find.byKey(const Key('pharmacy-detail-favorite')));
        await tester.pumpAndSettle();
        map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
        expect(map.favoritePharmacyIds, favorites);
        expect(map.selectedPharmacyId, 'open');
        expect(map.centerRevision, revision);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getStringList('medbuddy.favorite_pharmacy_ids')!.toSet(),
          favorites,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 지도 표시 여백 테스트
  // 함수역할: 정보창 높이에 따라 지도 여백과 조작 버튼을 조정하고 닫으면 복원하는지 검증한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('native map reserves detail space and restores it on close', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_buildControl(), nativeMap: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-card-open')));
    await tester.pumpAndSettle();
    var map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(map.selectedPharmacyId, 'open');
    expect(map.bottomInset, greaterThan(0));
    final revision = map.centerRevision;
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    sheet.controller!.jumpTo(sheet.minChildSize);
    await tester.pumpAndSettle();
    map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(
      map.bottomInset,
      closeTo(
        tester.getSize(find.byKey(const Key('pharmacy-detail-sheet'))).height,
        .1,
      ),
    );
    expect(map.centerRevision, revision);
    await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
    await tester.pumpAndSettle();
    map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(map.bottomInset, 0);
    expect(map.showControls, isTrue);
    expect(map.selectedPharmacyId, isNull);
    expect(map.centerRevision, revision);
  });

  // Function Name: testWidgets: 'details sheet drag updates the map inset without a rebuild of ' 'the header'
  // Description: Collapse an open pharmacy detail sheet by dragging while retaining the header widget instance.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the map inset shrinks to the sheet height within 0.1 pixels, the header is identical, and no widget exception occurs.
  testWidgets('details sheet drag updates the map inset without a rebuild of '
      'the header', (tester) async {
    await tester.pumpWidget(_testApp(_buildControl(), nativeMap: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pharmacy-card-open')));
    await tester.pumpAndSettle();
    // 화면 State가 다시 빌드되면 상단 위젯 인스턴스가 새로 만들어진다.
    final header = tester.widget<MedBuddyPageHeader>(
      find.byType(MedBuddyPageHeader),
    );
    final expandedInset = tester
        .widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap))
        .bottomInset;
    await tester.drag(
      find.byKey(const Key('pharmacy-detail-handle')),
      const Offset(0, 280),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<NearbyPharmacyMap>(
      find.byType(NearbyPharmacyMap),
    );
    expect(map.bottomInset, lessThan(expandedInset));
    expect(
      map.bottomInset,
      closeTo(
        tester.getSize(find.byKey(const Key('pharmacy-detail-sheet'))).height,
        .1,
      ),
    );
    expect(
      tester.widget<MedBuddyPageHeader>(find.byType(MedBuddyPageHeader)),
      same(header),
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 목록·지도 이동 테스트
  // 함수역할: 목록에서 선택하면 지도 상세로 이동하고 뒤로가기가 각 패널을 닫는지 확인한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'list selection opens map details and back closes panels in order',
    (tester) async {
      await tester.pumpWidget(_testApp(_buildControl()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-card-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pharmacy-detail-sheet')), findsOneWidget);
      expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pharmacy-list-panel')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
      expect(find.byKey(const Key('pharmacy-detail-sheet')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pharmacy-detail-sheet')), findsNothing);
      expect(find.byType(CheckNearbyPharmacyUI), findsOneWidget);
    },
  );

  // 함수이름: 상세창 명령 테스트
  // 함수역할: 전화와 즐겨찾기가 목록 전환 없이 선택한 약국에 적용되는지 확인한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'detail actions use the selected pharmacy without opening the list',
    (tester) async {
      final launched = <Uri>[];
      await tester.pumpWidget(
        _testApp(
          _buildControl(
            uriLauncher: (uri) async {
              launched.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-map-marker-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('즐겨찾기 추가'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('즐겨찾기 해제'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pharmacy-detail-handle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('전화'));
      await tester.tap(find.text('전화'));
      await tester.pumpAndSettle();
      expect(launched.single.scheme, 'tel');
      expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
    },
  );

  // 함수이름: 결과 소멸 테스트
  // 함수역할: 선택한 약국이 재조회 결과에서 사라지면 정보창도 닫는지 확인한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('refresh clears details when the selected pharmacy disappears', (
    tester,
  ) async {
    final emptyModes = <String>{};
    await tester.pumpWidget(_testApp(_buildControl(emptyModes: emptyModes)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    emptyModes.add('open_at_time');
    await tester.tap(find.byTooltip('약국 목록 새로고침'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pharmacy-detail-sheet')), findsNothing);
    expect(find.byKey(const Key('test-nearby-pharmacy-map')), findsOneWidget);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 큰 글씨 상세창 테스트
    // 함수역할: 작은 화면의 한글·영문 2배 글씨에서 펼침·접힘이 넘치지 않는지 검증한다.
    // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
    testWidgets('small $language screen supports large-text details', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _testApp(_buildControl(), language: language, textScale: 2),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-map-marker-open')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('pharmacy-detail-handle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 드래그는 먼저 시트를 펼친 뒤 내용을 스크롤하므로 실제 제스처로 확인한다.
      for (
        var drag = 0;
        drag < 8 &&
            find
                .byKey(const Key('pharmacy-directions-open'))
                .hitTestable()
                .evaluate()
                .isEmpty;
        drag++
      ) {
        await tester.drag(
          find.byKey(const Key('pharmacy-detail-sheet')),
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const Key('pharmacy-directions-open')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pharmacy-list-toggle')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: testWidgets: 'detail sheet preserves the pharmacy chat-sharing result'
  // Description: Open pharmacy selection, verify the phone checkbox, and share from the detail sheet after making its action reachable.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the caller receives pharmacy open with phoneVerified true, the title is not duplicated, and navigation returns to the caller.
  testWidgets('detail sheet preserves the pharmacy chat-sharing result', (
    tester,
  ) async {
    NearbyCareSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                selection = await Navigator.push<NearbyCareSelection>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckNearbyPharmacyUI.selection(
                      userSetting: const UserSetting(),
                      control: _buildControl(),
                      mapBuilder: _buildTestMap,
                    ),
                  ),
                );
              },
              child: const Text('open selection'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-map-marker-open')));
    await tester.pumpAndSettle();
    final check = find.byType(CheckboxListTile);
    // 공유 영역에서 상세 제목을 반복하지 않되 전화 확인 기능은 유지한다.
    final title = tester
        .widget<KeepWordsText>(find.byKey(const Key('pharmacy-detail-name')))
        .data;
    expect(
      find.descendant(
        of: find.byKey(const Key('pharmacy-detail-sheet')),
        matching: find.text(title),
      ),
      findsOneWidget,
    );
    for (
      var drag = 0;
      drag < 8 && check.hitTestable().evaluate().isEmpty;
      drag++
    ) {
      await tester.drag(
        find.byKey(const Key('pharmacy-detail-sheet')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('채팅에 공유'));
    // 스크롤에 따른 상세창 높이 재계산이 끝난 위치에서 실제 버튼을 누른다.
    await tester.pumpAndSettle();
    expect(find.text('채팅에 공유').hitTestable(), findsOneWidget);
    await tester.tap(find.text('채팅에 공유'));
    await tester.pumpAndSettle();
    expect(selection?.place.placeId, 'open');
    expect(selection?.phoneVerified, isTrue);
    expect(find.text('open selection'), findsOneWidget);
  });

  // Function Name: testWidgets: 'device dot stays at the fix when the search area moves'
  // Description: Move the map search area after obtaining a device coordinate.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the search longitude changes to the requested center while the device-location object remains the same.
  testWidgets('device dot stays at the fix when the search area moves', (
    tester,
  ) async {
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    var map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    final fix = map.deviceLocation;
    expect(fix, isNotNull);
    const moved = NearbyCareSearchArea(
      center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
      radiusKm: 20,
      isMapArea: true,
    );
    await map.onSearchAreaRequested!(moved);
    await tester.pumpAndSettle();
    map = tester.widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap));
    expect(map.searchArea.center.longitude, moved.center.longitude);
    expect(map.deviceLocation, same(fix));
  });

  for (final language in ['ko', 'en']) {
    // Function Name: testWidgets: 'map distance guide expires once and frees map space: $language'
    // Description: Search a map area in each language, wait three then one second, and search again.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; the distance guide expires at four seconds, increases map height without replacing the map or center, and does not repeat.
    testWidgets(
      'map distance guide expires once and frees map space: $language',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final control = _buildControl();
        addTearDown(control.dispose);
        await tester.pumpWidget(
          _testApp(control, nativeMap: true, language: language),
        );
        await tester.pumpAndSettle();
        final guide = find.text(
          language == 'en'
              ? 'Distances are measured from the searched map center.'
              : '거리는 검색한 지도 중심을 기준으로 표시해요.',
        );
        expect(guide, findsNothing);
        final mapFinder = find.byType(NearbyPharmacyMap);
        final mapElement = tester.element(mapFinder);
        const area = NearbyCareSearchArea(
          center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
          radiusKm: 20,
          isMapArea: true,
        );
        await tester
            .widget<NearbyPharmacyMap>(mapFinder)
            .onSearchAreaRequested!(area);
        await tester.pumpAndSettle();
        expect(guide, findsOneWidget);
        final heightWithGuide = tester.getSize(mapFinder).height;
        await tester.pump(const Duration(seconds: 3));
        expect(guide, findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(guide, findsNothing);
        expect(tester.getSize(mapFinder).height, greaterThan(heightWithGuide));
        expect(tester.element(mapFinder), same(mapElement));
        expect(
          tester.widget<NearbyPharmacyMap>(mapFinder).searchArea.center,
          same(area.center),
        );
        await tester
            .widget<NearbyPharmacyMap>(mapFinder)
            .onSearchAreaRequested!(area);
        await tester.pumpAndSettle();
        expect(guide, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Function Name: testWidgets: 'closing the pharmacy screen cancels the distance guide timer'
  // Description: Start the distance-guide timer with a map-area search, dispose the screen, then advance five seconds.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; no delayed update accesses the disposed widget.
  testWidgets('closing the pharmacy screen cancels the distance guide timer', (
    tester,
  ) async {
    final control = _buildControl();
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    await tester
        .widget<NearbyPharmacyMap>(find.byType(NearbyPharmacyMap))
        .onSearchAreaRequested!(
      const NearbyCareSearchArea(
        center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
        radiusKm: 20,
        isMapArea: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets: 'search failure notice survives the distance guide timeout'
  // Description: Show the map-area guide, inject a subsequent search failure, then advance beyond the guide timeout.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the search-failure notice remains visible after five seconds without a widget exception.
  testWidgets('search failure notice survives the distance guide timeout', (
    tester,
  ) async {
    var fail = false;
    final control = _buildControl(
      beforeResponse: () async {
        if (fail) throw StateError('Simulated search failure');
      },
    );
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    const area = NearbyCareSearchArea(
      center: DeviceCoordinate(latitude: 37.5, longitude: 127.1),
      radiusKm: 20,
      isMapArea: true,
    );
    final mapFinder = find.byType(NearbyPharmacyMap);
    await tester.widget<NearbyPharmacyMap>(mapFinder).onSearchAreaRequested!(
      area,
    );
    await tester.pumpAndSettle();
    fail = true;
    await tester.widget<NearbyPharmacyMap>(mapFinder).onSearchAreaRequested!(
      area,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('검색하지 못했어요. 지도를 옮겨 다시 검색하거나 새로고침해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets: 'fallback search never pretends to be the device position'
  // 함수역할: 위치 서비스 중단 상태로 실제 지도 위젯을 표시하고 안내 시간을 넘긴다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 검색 영역은 대체 위치이고 기기 좌표는 null이며 홍익대 기준 안내가 유지된다.
  testWidgets('fallback search never pretends to be the device position', (
    tester,
  ) async {
    final control = _buildControl(
      failure: DeviceLocationFailure.serviceDisabled,
    );
    addTearDown(control.dispose);
    await tester.pumpWidget(_testApp(control, nativeMap: true));
    await tester.pumpAndSettle();
    final map = tester.widget<NearbyPharmacyMap>(
      find.byType(NearbyPharmacyMap),
    );
    expect(map.searchArea.isFallback, isTrue);
    expect(map.deviceLocation, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('위치를 확인하지 못해 홍익대학교 서울캠퍼스 기준으로 검색했어요.'), findsOneWidget);
  });
  // 함수이름: testWidgets: 'stale background resume refreshes once; brief inactive does not'
  // 함수역할: 짧은 inactive 전환, 10초 백그라운드, 2분 백그라운드 복귀와 반복 resumed 이벤트를 차례로 보낸다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 오래된 결과만 현재 시각으로 한 번 새로 조회하고 반복 복귀·화면 제거 뒤 이벤트는 추가 오류를 내지 않는다.
  testWidgets(
    'stale background resume refreshes once; brief inactive does not',
    (tester) async {
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
    },
  );

  // 함수이름: testWidgets: 'resume queues one fresh search behind an in-flight old request'
  // 함수역할: 자정 직전 첫 검색을 보류하고 백그라운드에서 20초 경과 후 복귀한 뒤 기존 응답을 완료한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 기존 요청 중에는 겹쳐 조회하지 않고 완료 후 새 날짜·시각으로 한 번만 추가 검색한다.
  testWidgets(
    'resume queues one fresh search behind an in-flight old request',
    (tester) async {
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
    },
  );

  // 함수이름: testWidgets: 'filter search advances past midnight and labels reference time'
  // 함수역할: 첫 검색 후 시계를 다음 날 00:50으로 바꾸고 늦게까지 영업 조건을 적용한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 요청은 갱신된 시각을 사용하고 조회 시각 기준 영업·조회일을 표시하되 별도 날짜 줄이나 현재 영업 중 문구는 보이지 않는다.
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
      await _applySearchFilter(tester, 'lateHours');
      expect(requestedTimes.last, now);
      expect(find.text('조회 날짜: 2026-09-12 00:50'), findsNothing);
      expect(find.byKey(const Key('pharmacy-search-date')), findsNothing);
      expect(find.text('조회 시각 영업'), findsWidgets);
      expect(find.text('영업 중'), findsNothing);
      expect(find.textContaining('조회일 '), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  // Function Name: testWidgets: '지도 설정 누락과 약국 좌표 누락을 서로 다르게 안내한다'
  // Description: Mount the native map with a pharmacy that has coordinates but without map configuration.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the missing-configuration message appears, the missing-coordinates message does not, and rendering has no exception.
  testWidgets('지도 설정 누락과 약국 좌표 누락을 서로 다르게 안내한다', (tester) async {
    const pharmacy = NearbyCarePlace(
      placeId: 'configured-location',
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
            searchArea: const NearbyCareSearchArea(
              center: NearbyCareSearchArea.fallbackCenter,
              radiusKm: 20,
              isFallback: true,
            ),
            pharmacies: const [pharmacy],
            selectedPharmacyId: null,
            // 함수이름: onPharmacySelected 콜백
            // 함수역할:
            // - 약국 선택 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
            // 매개변수:
            // - _ (NearbyCarePlace): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
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

  // 함수이름: testWidgets: 'map filters update pins without opening the pharmacy list'
  // 함수역할: 목록을 열지 않은 상태에서 지도 필터를 늦은 영업·주말/공휴일·전체·영업 중 순서로 적용한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 동일 지도에서 전체일 때만 종료 약국 마커가 보이고 요청 모드가 순서대로 기록되며 목록을 연 뒤에는 목록의 조건 버튼을 사용한다.
  testWidgets('map filters update pins without opening the pharmacy list', (
    tester,
  ) async {
    final modes = <String?>[];
    await tester.pumpWidget(_testApp(_buildControl(requestedModes: modes)));
    await tester.pumpAndSettle();
    final map = tester.element(
      find.byKey(const Key('test-nearby-pharmacy-map')),
    );
    for (final option in ['lateHours', 'weekendHoliday', 'all', 'openNow']) {
      await tester.tap(find.byKey(const Key('pharmacy-map-filter-selector')));
      await tester.pumpAndSettle();
      await _applySearchFilter(tester, option);
      expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
      expect(
        tester.element(find.byKey(const Key('test-nearby-pharmacy-map'))),
        same(map),
      );
      expect(
        find.byKey(const ValueKey('test-map-marker-open')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('test-map-marker-closed')),
        option == 'all' ? findsOneWidget : findsNothing,
      );
      expect(find.byKey(const Key('pharmacy-map-search-date')), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(modes, [
      'open_at_time',
      'late_hours',
      'weekend_holiday',
      'all',
      'open_at_time',
    ]);
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('조회 조건'), findsOneWidget);
    expect(find.byKey(const Key('pharmacy-map-filter-selector')), findsNothing);
  });

  // Function Name: calendar verification failure keeps an empty search uncertain
  // Description: A missing calendar must not tell users that every nearby pharmacy is closed.
  // Parameters: tester: Widget test driver. Returns: Completed regression check.
  testWidgets('calendar verification failure keeps an empty search uncertain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        _buildControl(
          emptyModes: {'open_at_time'},
          holidayScheduleStatus: 'unknown',
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The map-first banner must state the same uncertainty as the list.
    expect(find.text('map-status:약국 영업 여부를 확인할 수 없습니다'), findsOneWidget);
    expect(find.textContaining('조건에 맞는 약국이 없어요'), findsNothing);
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('약국 영업 여부를 확인할 수 없습니다'), findsOneWidget);
    expect(find.text('검색한 지역에 영업 중인 약국이 없습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Function Name: calendar verification failure does not blur the all-pharmacies filter
  // Description: The all filter ignores opening hours, so its empty result stays a definite "no match".
  // Parameters: tester: Widget test driver. Returns: Completed regression check.
  testWidgets(
    'calendar verification failure keeps the all filter empty state definite',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          _buildControl(
            emptyModes: {'open_at_time', 'all'},
            holidayScheduleStatus: 'unknown',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('전체 약국 보기'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('전체 약국 보기'));
      await tester.pumpAndSettle();
      expect(find.text('주변 약국을 찾지 못했습니다'), findsOneWidget);
      expect(find.text('약국 영업 여부를 확인할 수 없습니다'), findsNothing);
      expect(
        find.text('map-status:조건에 맞는 약국이 없어요. 지도를 옮기거나 조회 조건을 바꿔보세요.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: testWidgets: 'shows open pharmacies first and filters closed pharmacies'
  // 함수역할: 기본 지도에서 목록을 열고 닫아 상태를 유지한 뒤 전체 약국과 영업 중 필터를 번갈아 적용한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 기본에는 영업 중 약국만 보이고 전체에서 종료 약국이 추가되며 단순 목록 전환은 재조회나 지도 교체를 만들지 않는다.
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
    expect(find.text('조회 조건'), findsOneWidget);
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
    await _applySearchFilter(tester, 'all');
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
    await _applySearchFilter(tester, 'openNow');
    expect(find.byKey(const ValueKey('test-map-marker-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-map-marker-closed')), findsNothing);
    expect(find.byKey(const ValueKey('pharmacy-card-closed')), findsNothing);
  });

  // 함수이름: testWidgets: '영업 중 약국에서 늦게까지 운영하는 결과를 먼저 표시한다'
  // 함수역할: 거리 0.1km의 일반 영업 약국과 0.8km의 늦게까지 영업 약국을 함께 반환한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 두 마커가 존재하고 늦게까지 영업하는 약국이 가로 목록에서 먼저 표시되며 화면 예외가 없다.
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

  // Function Name: testWidgets: 'selecting a pharmacy card updates the map focus state'
  // Description: Open the list and select the open pharmacy while the map-selection hint is visible.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; selecting the card clears the map hint without producing a widget exception.
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
  for (final fromDetails in [false, true]) {
    // 함수이름: testWidgets: '길찾기 연속 선택과 외부 앱 복귀가 약국 화면을 닫지 않는다: $fromDetails'
    // 함수역할: 목록 또는 상세창에서 길찾기 실행을 연속 선택한 뒤 앱 paused·resumed를 재현한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 외부 앱 실행은 한 번이며 약국 경로와 원래 목록·상세창이 유지되고 이전 홈으로 돌아가지 않는다.
    testWidgets('길찾기 연속 선택과 외부 앱 복귀가 약국 화면을 닫지 않는다: $fromDetails', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final launched = <Uri>[];
      final control = _buildControl(
        uriLauncher: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      addTearDown(control.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('test-home')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => CheckNearbyPharmacyUI(
              userSetting: const UserSetting(language: 'ko'),
              control: control,
              mapBuilder: _buildTestMap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      if (fromDetails) {
        await tester.tap(find.byKey(const Key('pharmacy-card-open')));
        await tester.pumpAndSettle();
      }
      final directions = find.byKey(const Key('pharmacy-directions-open'));
      await tester.ensureVisible(directions);
      await tester.tap(directions);
      await tester.pumpAndSettle();
      final choice = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const Key('directions-choice-google-maps')),
          matching: find.byType(ListTile),
        ),
      );
      // 같은 선택창이 닫히는 동안 이미 전달된 두 번째 탭도 재현한다.
      choice.onTap!();
      choice.onTap!();
      await tester.pumpAndSettle();
      expect(launched, hasLength(1));
      expect(find.byType(CheckNearbyPharmacyUI), findsOneWidget);
      expect(find.text('test-home'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          Key(fromDetails ? 'pharmacy-detail-sheet' : 'pharmacy-list-panel'),
        ),
        findsOneWidget,
      );
      expect(find.text('test-home'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: testWidgets: '길찾기는 실행 방법을 묻고 주소 복사를 지원한다'
  // 함수역할: 약국 길찾기 메뉴의 설치 앱·Google Maps·주소 복사 선택지를 확인하고 복사를 선택한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 서울특별시 종로구가 복사되고 성공 안내가 표시되며 위젯 예외가 없다.
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
    await tester.pumpAndSettle();
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
    await _applySearchFilter(tester, 'lateHours');

    expect(find.textContaining('심야 운영 약국이 없습니다'), findsOneWidget);
    expect(find.byKey(const Key('pharmacy-search-date')), findsNothing);
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
