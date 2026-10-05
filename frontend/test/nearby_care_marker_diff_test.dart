// 파일명: nearby_care_marker_diff_test.dart
// 역할: 마커 전체 재생성 없이 표시 변경만 반영하는지 검사한다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:medbuddy_frontend/boundaries/nearby_pharmacy_map_widget.dart';
import 'package:medbuddy_frontend/entities/nearby_care_entity.dart';
import 'package:medbuddy_frontend/services/naver_map_config.dart';
import 'package:medbuddy_frontend/services/nearby_care_marker_diff.dart';

// Class Name: _QueueTestMap
// Role: Mounts the existing map state without a native platform view.
// Responsibilities: Supplies synthetic places and substitutes only the test element.
// Attributes: Inherited places, favorites and camera revision are existing map inputs.
class _QueueTestMap extends NearbyPharmacyMap {
  // Function Name: _QueueTestMap
  // Description: Provides fixed display text and a stable key for real state updates.
  // Parameters: places: Synthetic results; favorites: Marker flags.
  // Returns: A map widget with no network, device location or external actions.
  _QueueTestMap({
    required List<NearbyCarePlace> places,
    Set<String> favorites = const {},
  }) : super(
         key: const ValueKey('native-marker-queue-test'),
         searchArea: const NearbyCareSearchArea(
           center: NearbyCareSearchArea.fallbackCenter,
           radiusKm: 20,
         ),
         pharmacies: places,
         favoritePharmacyIds: favorites,
         selectedPharmacyId: null,
         // Function Name: synthetic selection callback
         // Description: Avoids any navigation. Parameters: place: Selected input. Returns: None.
         onPharmacySelected: (place) {},
         // Function Name: synthetic attribution callback
         // Description: Avoids external actions. Parameters: None. Returns: None.
         onAttributionRequested: () {},
         statusText: null,
         selectMarkerHint: 'Select',
         zoomInTooltip: 'Zoom in',
         zoomOutTooltip: 'Zoom out',
         configurationUnavailableText: 'Unconfigured',
         unavailableText: 'Unavailable',
       );

  // Function Name: createElement
  // Description: Keeps the production State while avoiding the unsupported desktop native child.
  // Parameters: None. Returns: The test-only callback-capturing element.
  @override
  StatefulElement createElement() => _QueueTestMapElement(this);
}

// Class Name: _QueueTestMapElement
// Role: Captures real map callbacks but renders no native map.
// Responsibilities: Calls the existing State.build and preserves its update/disposal lifecycle.
// Attributes: map: Latest existing NaverMap configuration.
class _QueueTestMapElement extends StatefulElement {
  NaverMap? map;

  // Function Name: _QueueTestMapElement
  // Description: Lets Flutter mount the widget's original state.
  // Parameters: widget: Synthetic map input. Returns: A lifecycle-preserving test element.
  _QueueTestMapElement(super.widget);

  // Function Name: build
  // Description: Captures callbacks before replacing only the native child with a host-safe box.
  // Parameters: None. Returns: A box; all synchronization remains production-owned.
  @override
  Widget build() {
    final tree = super.build() as Semantics;
    final container = tree.child! as Container;
    final stack = container.child! as Stack;
    map = stack.children.whereType<NaverMap>().single;
    return const SizedBox(width: 400, height: 400);
  }
}

// Class Name: _QueueLocationOverlay
// Role: Replaces the device location overlay with inert existing setter operations.
// Responsibilities: Prevents method-channel or device interactions.
// Attributes: None; unused SDK members use the standard fake dispatch.
class _QueueLocationOverlay implements NLocationOverlay {
  // Function Name: noSuchMethod
  // Description: Ignores location setters not relevant to marker recovery.
  // Parameters: invocation: Existing overlay operation. Returns: Null for void setters.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Class Name: _QueueMapController
// Role: Models the pinned SDK's non-transactional native marker commands.
// Responsibilities: Partly adds then fails, records recovery commands and supports delayed clear.
// Attributes: markers/commands: Observed native state; failure flags/gates: Deterministic failure order.
class _QueueMapController implements NaverMapController {
  final markers = <String>{};
  final commands = <String>[];
  final firstAdd = Completer<void>();
  final firstClear = Completer<void>();
  final NLocationOverlay _location = _QueueLocationOverlay();
  bool failNextAdd = true;
  bool failNextClear = false;
  Completer<void>? clearGate;

  // Function Name: getLocationOverlay
  // Description: Supplies inert location setters to the existing synchronization method.
  // Parameters: None. Returns: The test-owned location overlay.
  @override
  NLocationOverlay getLocationOverlay() => _location;

  // Function Name: addOverlayAll
  // Description: Applies the first marker before the injected native failure, like a non-atomic SDK batch.
  // Parameters: overlays: Existing marker batch. Returns: Success or the injected platform error.
  @override
  Future<void> addOverlayAll(Set<NAddableOverlay> overlays) async {
    final ids = overlays.map((overlay) => overlay.info.id).toList();
    commands.add('add');
    if (!firstAdd.isCompleted) firstAdd.complete();
    if (failNextAdd) {
      failNextAdd = false;
      markers.add(ids.first);
      throw PlatformException(code: 'injected-partial-marker-add');
    }
    markers.addAll(ids);
  }

  // Function Name: deleteOverlay
  // Description: Models the SDK's idempotent individual native removal.
  // Parameters: info: Existing overlay identity. Returns: Completion after removal.
  @override
  Future<void> deleteOverlay(NOverlayInfo info) async {
    commands.add('delete');
    markers.remove(info.id);
  }

  // Function Name: clearOverlays
  // Description: Clears markers, optionally delaying or rejecting the existing recovery operation.
  // Parameters: type: Existing SDK overlay filter. Returns: Success or the injected clear error.
  @override
  Future<void> clearOverlays({NOverlayType? type}) async {
    expect(type, NOverlayType.marker);
    commands.add('clear');
    if (!firstClear.isCompleted) firstClear.complete();
    if (failNextClear) {
      failNextClear = false;
      throw PlatformException(code: 'injected-marker-clear');
    }
    await clearGate?.future;
    markers.clear();
  }

  // Function Name: updateCamera
  // Description: Records existing explicit camera work without a device.
  // Parameters: cameraUpdate: Existing camera request. Returns: False (not canceled).
  @override
  Future<bool> updateCamera(NCameraUpdate cameraUpdate) async {
    commands.add('camera');
    return false;
  }

  // Function Name: noSuchMethod
  // Description: Rejects unused SDK operations instead of silently expanding the fake.
  // Parameters: invocation: Unmodeled SDK operation. Returns: Never; throws UnsupportedError.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected map operation: ${invocation.memberName}',
  );
}

// Function Name: _flushMapOperations
// Description: Drains host image/file work and Flutter fake-async continuations without sleeping the application.
// Parameters: tester: Widget driver; until: Optional observed command completion predicate.
// Returns: Completion after bounded pumping; fails if the requested command never executes.
Future<void> _flushMapOperations(
  WidgetTester tester, {
  bool Function()? until,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (until == null || until()) return;
  }
  expect(
    until!(),
    isTrue,
    reason: 'Map command did not complete during pumping',
  );
}

// 함수이름: place
// 함수역할: 네트워크 없는 지도 시험 장소를 만든다.
// 매개변수: id/name/latitude/phone: 비교할 장소 속성. 반환값: 합성 장소.
NearbyCarePlace place(
  String id, {
  String? name,
  double latitude = 37.55,
  String phone = '02-000',
}) => NearbyCarePlace(
  placeId: id,
  name: name ?? id,
  address: 'test',
  telephone: phone,
  latitude: latitude,
  longitude: 126.92,
  distanceKm: 0.2,
  todayOpenTime: '09:00',
  todayCloseTime: '18:00',
  isOpenNow: true,
  is24Hours: false,
);

// 함수이름: styles
// 함수역할: 시험 장소를 ID별 표시 속성으로 변환한다.
// 매개변수: places: 장소, selected: 선택 ID, favorites: 즐겨찾기. 반환값: 속성 사전.
Map<String, NearbyCareMarkerStyle> styles(
  List<NearbyCarePlace> places, {
  String? selected,
  Set<String> favorites = const {},
}) => {
  for (final item in places)
    item.placeId: nearbyCareMarkerStyle(
      item,
      selectedId: selected,
      favoriteIds: favorites,
    ),
};

// 함수이름: main
// 함수역할: 선택·즐겨찾기·검색 결과별 마커 갱신 회귀 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? imageDirectory;

  // Function Name: marker harness setup
  // Description: Routes SDK image writes to a fresh test-owned directory only.
  // Parameters: None. Returns: Asynchronous setup without SDK authentication or network.
  setUpAll(() async {
    if (!isNaverMapConfigured) return;
    imageDirectory = await Directory.systemTemp.createTemp(
      'medbuddy-marker-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return imageDirectory!.path;
          }
          throw UnsupportedError('Unexpected path operation: ${call.method}');
        });
  });

  // Function Name: marker harness teardown
  // Description: Removes only its own temporary images and path-channel handler.
  // Parameters: None. Returns: Asynchronous test resource cleanup.
  tearDownAll(() async {
    if (!isNaverMapConfigured) return;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await imageDirectory!.delete(recursive: true);
  });

  for (final scenario in ['empty', 'same', 'failed-clear', 'replacement']) {
    // Function Name: native marker recovery regression
    // Description: Exercises production queue recovery after a partially successful native batch.
    // Parameters: tester: Host widget driver. Returns: Deterministic native-state assertions.
    testWidgets(
      'native marker queue recovers after partial add: $scenario',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.library == 'nearby care map') {
            errors.add(details);
          } else {
            previousErrorHandler?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        final controller = _QueueMapController();
        final places = [place('a'), place('b')];

        await tester.pumpWidget(
          MaterialApp(home: _QueueTestMap(places: places)),
        );
        var element =
            tester.element(find.byType(_QueueTestMap)) as _QueueTestMapElement;
        element.map!.onMapReady!(controller);
        await _flushMapOperations(
          tester,
          until: () => controller.firstAdd.isCompleted,
        );
        expect(controller.markers, {'pharmacy-a'});
        expect(errors.single.exception, isA<PlatformException>());

        if (scenario == 'same') {
          await tester.pumpWidget(
            MaterialApp(
              home: _QueueTestMap(places: places, favorites: {'unrelated'}),
            ),
          );
          await _flushMapOperations(tester);
          expect(controller.markers, {'pharmacy-a', 'pharmacy-b'});
          expect(
            controller.commands.where((command) => command == 'clear'),
            hasLength(1),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: _QueueTestMap(
                places: places,
                favorites: {'also-unrelated'},
              ),
            ),
          );
          await _flushMapOperations(tester);
          expect(
            controller.commands.where((command) => command == 'clear'),
            hasLength(1),
          );
          expect(
            controller.commands.where((command) => command == 'add'),
            hasLength(2),
          );
        } else {
          controller.failNextClear = scenario == 'failed-clear';
          controller.clearGate = scenario == 'replacement'
              ? Completer<void>()
              : null;
          await tester.pumpWidget(
            MaterialApp(home: _QueueTestMap(places: const [])),
          );
          await _flushMapOperations(tester);
          if (scenario == 'failed-clear') {
            expect(controller.markers, {'pharmacy-a'});
            expect(errors, hasLength(2));
            await tester.pumpWidget(
              MaterialApp(
                home: _QueueTestMap(places: const [], favorites: {'unrelated'}),
              ),
            );
            await _flushMapOperations(tester);
            expect(
              controller.commands.where((command) => command == 'clear'),
              hasLength(2),
            );
          } else if (scenario == 'replacement') {
            expect(controller.firstClear.isCompleted, isTrue);
            final nextController = _QueueMapController()..failNextAdd = false;
            final nextPlaces = [place('c')];
            await tester.pumpWidget(
              MaterialApp(home: _QueueTestMap(places: nextPlaces)),
            );
            element =
                tester.element(find.byType(_QueueTestMap))
                    as _QueueTestMapElement;
            element.map!.onMapReady!(nextController);
            controller.clearGate!.complete();
            await _flushMapOperations(
              tester,
              until: () => nextController.firstAdd.isCompleted,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: _QueueTestMap(
                  places: nextPlaces,
                  favorites: {'unrelated'},
                ),
              ),
            );
            await _flushMapOperations(tester);
            expect(nextController.markers, {'pharmacy-c'});
            expect(nextController.commands, ['add']);
          }
          expect(controller.markers, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      skip: !isNaverMapConfigured,
    );
  }

  // 함수역할: 선택 이동 시 두 ID만 교체하는지 검사한다. 매개변수: 없음. 반환값: 없음.
  test('선택 변경은 기존 선택과 새 선택의 두 마커만 교체한다', () {
    final places = [for (var i = 0; i < 30; i++) place('$i')];
    final delta = NearbyCareMarkerDiff.between(
      styles(places, selected: '1'),
      styles(places, selected: '2'),
    );
    expect(delta.remove, {'1', '2'});
    expect(delta.add, {'1', '2'});
  });

  // 함수역할: 즐겨찾기 하나의 변경이 다른 마커를 건드리지 않는지 검사한다. 매개변수·반환값: 없음.
  test('즐겨찾기 변경은 해당 마커만 교체한다', () {
    final places = [for (var i = 0; i < 30; i++) place('$i')];
    final delta = NearbyCareMarkerDiff.between(
      styles(places),
      styles(places, favorites: {'7'}),
    );
    expect(delta.remove, {'7'});
    expect(delta.add, {'7'});
  });

  // 함수역할: 위치·이름 변화와 표시와 무관한 값의 변경을 구분한다. 매개변수·반환값: 없음.
  test('검색 추가·제거·좌표·이름 변경을 구분하고 순서·연락처 변경은 무시한다', () {
    final before = styles([place('a'), place('b'), place('c')]);
    final delta = NearbyCareMarkerDiff.between(
      before,
      styles([
        place('c', phone: '02-111'),
        place('b', name: 'new', latitude: 37.56),
        place('d'),
      ]),
    );
    expect(delta.remove, {'a', 'b'});
    expect(delta.add, {'b', 'd'});
  });

  // 함수역할: 결과 없음과 반복 조회에서 필요한 제거만 수행하는지 검사한다. 매개변수·반환값: 없음.
  test('빈 결과는 기존 마커만 제거하고 같은 결과는 작업하지 않는다', () {
    final before = styles([place('a')]);
    expect(NearbyCareMarkerDiff.between(before, {}).remove, {'a'});
    expect(NearbyCareMarkerDiff.between(before, {}).add, isEmpty);
    expect(NearbyCareMarkerDiff.between(before, before).remove, isEmpty);
    expect(NearbyCareMarkerDiff.between(before, before).add, isEmpty);
  });
}
