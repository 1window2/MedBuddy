// 파일명: nearby_care_favorites_ui_test.dart
// 역할: 즐겨찾기만 보기 모드, 목록 전용 스냅샷, 별 버튼 표시와 스냅샷 확인 검색을 검증한다.

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
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

const _device = DeviceCoordinate(latitude: 37.5665, longitude: 126.9780);
const _pharmacyIdsKey = 'medbuddy.favorite_pharmacy_ids';
const _pharmacyPlacesKey = 'medbuddy.favorite_pharmacy_places';

// Class Name: _Location
// Role: Fixed device location for nearby-care tests.
// Responsibilities: Returns one Seoul coordinate and opens no settings.
// Attributes: None.
class _Location implements DeviceLocationBoundary {
  // Function Name: requestCurrentCoordinate
  // Description: Returns the fixed device coordinate.
  // Parameters: None.
  // Returns: Future<DeviceCoordinate>: _device.
  @override
  Future<DeviceCoordinate> requestCurrentCoordinate() async => _device;

  // Function Name: openApplicationSettings
  // Description: Reports that settings were not opened.
  // Parameters: None.
  // Returns: Future<bool>: false.
  @override
  Future<bool> openApplicationSettings() async => false;

  // Function Name: openDeviceLocationSettings
  // Description: Reports that settings were not opened.
  // Parameters: None.
  // Returns: Future<bool>: false.
  @override
  Future<bool> openDeviceLocationSettings() async => false;
}

// Class Name: _Request
// Role: Recorded nearby-care query.
// Responsibilities: Keeps the fields the favorites tests assert on.
// Attributes: mode: search_mode; latitude: query centre; radius: max_distance_km; department: hospital department or null.
class _Request {
  final String mode;
  final double latitude;
  final String radius;
  final String? department;

  // Function Name: _Request
  // Description: Stores one recorded query.
  // Parameters: mode, latitude, radius, department: query fields.
  // Returns: A _Request.
  const _Request(this.mode, this.latitude, this.radius, this.department);
}

// Class Name: _Server
// Role: In-memory nearby-care API.
// Responsibilities: Returns open places for time filters and every near place for `all`; far places only for a focused query around their own coordinates.
// Attributes: near/far: place rows; requests: recorded queries.
class _Server {
  final List<Map<String, Object?>> near;
  final List<Map<String, Object?>> far;
  final requests = <_Request>[];

  // Function Name: _Server
  // Description: Stores the rows served by the fake API.
  // Parameters: near: places in ordinary searches; far: places found only by a focused query.
  // Returns: A _Server.
  _Server({required this.near, this.far = const []});

  // Function Name: handle
  // Description: Records the query and answers with the matching rows.
  // Parameters: request (http.Request): intercepted request.
  // Returns: Future<http.Response>: HTTP 200 JSON response.
  Future<http.Response> handle(http.Request request) async {
    final query = request.url.queryParameters;
    final mode = query['search_mode']!;
    final latitude = double.parse(query['latitude']!);
    requests.add(
      _Request(mode, latitude, query['max_distance_km']!, query['department']),
    );
    final focused = far
        .where((row) => ((row['latitude'] as double) - latitude).abs() < .001)
        .toList();
    final rows = focused.isNotEmpty
        ? focused
        : near.where((row) => mode == 'all' || row['is_open_now'] == true);
    return http.Response(
      jsonEncode({'data': rows.toList(), 'holiday_schedule_status': 'ok'}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

// Function Name: _row
// Description: Builds one API row.
// Parameters: id: place ID; open: is_open_now; latitude/longitude: location; address: address text; hospitals: use hospital_id.
// Returns: Map<String, Object?>: JSON-compatible row.
Map<String, Object?> _row(
  String id, {
  bool open = true,
  double latitude = 37.5666,
  double longitude = 126.9781,
  String? address,
  bool hospitals = false,
}) => {
  hospitals ? 'hospital_id' : 'pharmacy_id': id,
  'name': '장소 $id',
  'address': address ?? '서울 $id',
  'telephone': '02-111-1111',
  'latitude': latitude,
  'longitude': longitude,
  'distance_km': .4,
  'today_open_time': '09:00',
  'today_close_time': '18:00',
  'is_open_now': open,
  'is_24_hours': false,
};

// Function Name: _snapshotJson
// Description: Encodes stored snapshots for the given places.
// Parameters: places: (id, latitude, longitude) triples.
// Returns: String: JSON map keyed by place ID.
String _snapshotJson(List<(String, double, double)> places) => jsonEncode({
  for (final (id, latitude, longitude) in places)
    id: FavoritePlaceSnapshot(
      placeId: id,
      name: '장소 $id',
      address: '서울 $id',
      telephone: '02-111-1111',
      latitude: latitude,
      longitude: longitude,
      savedAt: DateTime.utc(2026, 11, 1),
    ).toJson(),
});

// Class Name: _MapProbe
// Role: Map substitute recording markers, selection and status.
// Responsibilities: Shows one button per marker and keeps the latest map inputs.
// Attributes: places: markers; selected: selected ID; status: map status text.
class _MapProbe {
  List<NearbyCarePlace> places = const [];
  String? selected;
  String? status;

  // Function Name: ids
  // Description: Lists marker IDs in display order.
  // Parameters: None.
  // Returns: List<String>: marker IDs.
  List<String> get ids => [for (final place in places) place.placeId];

  // Function Name: build
  // Description: Records the map inputs and renders marker buttons.
  // Parameters: the NearbyPharmacyMapBuilder contract; only pharmacies, selectedPharmacyId, onPharmacySelected and statusText are used.
  // Returns: Widget: white box with marker buttons.
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
    places = pharmacies;
    selected = selectedPharmacyId;
    status = statusText;
    return ColoredBox(
      key: const Key('favorites-test-map'),
      color: Colors.white,
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(
          children: [
            for (final place in pharmacies)
              TextButton(
                key: ValueKey('fav-marker-${place.placeId}'),
                onPressed: () => onPharmacySelected(place),
                child: Text(place.placeId),
              ),
          ],
        ),
      ),
    );
  }
}

// Function Name: _pump
// Description: Shows the nearby-care screen with the fake server and map at the given surface size.
// Parameters: tester; server; map; hospitals; selection: chat selection mode; size: surface size; clock: search clock.
// Returns: Future<CheckNearbyCare>: the control, disposed on tear-down.
Future<CheckNearbyCare> _pump(
  WidgetTester tester,
  _Server server,
  _MapProbe map, {
  bool hospitals = false,
  bool selection = false,
  Size size = const Size(390, 844),
  DateTime Function()? clock,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = MockClient(server.handle);
  final CheckNearbyCare control = hospitals
      ? CheckNearbyHospital(locationBoundary: _Location(), client: client)
      : CheckNearbyPharmacy(locationBoundary: _Location(), client: client);
  addTearDown(control.dispose);
  final setting = UserSetting(language: 'ko');
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1)),
        child: selection
            ? CheckNearbyPharmacyUI.selection(
                userSetting: setting,
                hospitals: hospitals,
                control: control,
                mapBuilder: map.build,
                clock: clock,
              )
            : CheckNearbyPharmacyUI(
                userSetting: setting,
                hospitals: hospitals,
                control: control,
                mapBuilder: map.build,
                clock: clock,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return control;
}

final _toggle = find.byKey(const Key('nearby-favorites-toggle'));

// Function Name: _tapToggle
// Description: Taps the favorites-only map command and waits for any lookup.
// Parameters: tester.
// Returns: Future<void>.
Future<void> _tapToggle(WidgetTester tester) async {
  await tester.tap(_toggle);
  await tester.pumpAndSettle();
}

// Function Name: _openList
// Description: Expands the result list.
// Parameters: tester.
// Returns: Future<void>.
Future<void> _openList(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
  await tester.pumpAndSettle();
}

// Function Name: _storedSnapshots
// Description: Reads the unscoped pharmacy snapshot map.
// Parameters: None.
// Returns: Future<Map<String, dynamic>>: stored records, empty when absent.
Future<Map<String, dynamic>> _storedSnapshots() async {
  final raw = (await SharedPreferences.getInstance()).getString(
    _pharmacyPlacesKey,
  );
  return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
}

// Function Name: _toggleTooltip
// Description: Reads the favorites-only command tooltip.
// Parameters: tester.
// Returns: String?: tooltip.
String? _toggleTooltip(WidgetTester tester) => tester
    .widget<IconButton>(
      find.descendant(of: _toggle, matching: find.byType(IconButton)),
    )
    .tooltip;

// Function Name: main
// Description: Registers favorites-mode, snapshot and star widget tests.
// Parameters: None.
// Returns: void.
void main() {
  // Function Name: pharmacyServer
  // Description: Serves two open places (one favorite), one closed favorite and one far favorite found only by a focused query.
  // Parameters: None.
  // Returns: _Server: fresh fake API.
  _Server pharmacyServer() => _Server(
    near: [
      _row('open-fav'),
      _row('closed-fav', open: false),
      _row('open-other'),
    ],
    far: [_row('far-fav', latitude: 37.60, longitude: 127.05)],
  );
  final favoritePrefs = <String, Object>{
    _pharmacyIdsKey: ['open-fav', 'closed-fav', 'far-fav', 'gone-fav'],
    _pharmacyPlacesKey: _snapshotJson([
      ('far-fav', 37.60, 127.05),
      ('gone-fav', 37.57, 126.98),
    ]),
  };

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Function Name: favorites mode test
  // Description: Turning favorites mode on clears the selection, searches all opening states and limits markers to live favorites; turning it off restores the open-now search.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('favorites mode filters markers and switches pharmacy query', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map);
    expect(server.requests.map((r) => r.mode), ['open_at_time']);
    expect(map.ids.toSet(), {'open-fav', 'open-other'});
    expect(_toggleTooltip(tester), '즐겨찾기만 보기');

    await tester.tap(find.byKey(const ValueKey('fav-marker-open-other')));
    await tester.pumpAndSettle();
    expect(map.selected, 'open-other');

    await _tapToggle(tester);
    expect(map.selected, isNull);
    expect(find.byKey(const Key('pharmacy-detail-sheet')), findsNothing);
    expect(server.requests.last.mode, 'all');
    expect(map.ids, ['open-fav', 'closed-fav']);
    expect(_toggleTooltip(tester), '모두 보기');
    // Snapshot favorites are list-only and never become markers.
    expect(map.ids, isNot(contains('far-fav')));
    expect(find.text('약국 목록 보기 (4)'), findsOneWidget);

    await _tapToggle(tester);
    expect(server.requests.last.mode, 'open_at_time');
    expect(map.ids.toSet(), {'open-fav', 'open-other'});
    expect(_toggleTooltip(tester), '즐겨찾기만 보기');
    expect(tester.takeException(), isNull);
  });

  // Function Name: list order test
  // Description: The expanded list shows live favorites first, then snapshots by distance with the tap hint, with no mode chip; the map star turns the mode off.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('favorites list orders live then snapshots and star exits', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map, size: const Size(390, 2400));
    await _tapToggle(tester);
    await _openList(tester);
    // 다른 조회 조건처럼 목록 위에 모드 칩을 두지 않는다.
    expect(find.byKey(const Key('nearby-favorites-chip')), findsNothing);
    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    final order = [
      'pharmacy-card-open-fav',
      'pharmacy-card-closed-fav',
      'pharmacy-snapshot-gone-fav',
      'pharmacy-snapshot-far-fav',
    ].map(top).toList();
    expect(order, orderedEquals([...order]..sort()));
    expect(find.text('운영 정보는 누르면 확인해요'), findsNWidgets(2));
    // A snapshot row has no live status badge.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pharmacy-snapshot-far-fav')),
        matching: find.text('시간 확인 필요'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pharmacy-card-open-other')),
      findsNothing,
    );

    // 목록을 접고 지도 별 버튼을 다시 누르면 모두 보기로 돌아간다.
    await _openList(tester);
    await _tapToggle(tester);
    expect(_toggleTooltip(tester), '즐겨찾기만 보기');
    await _openList(tester);
    expect(
      find.byKey(const ValueKey('pharmacy-snapshot-far-fav')),
      findsNothing,
    );
    expect(server.requests.last.mode, 'open_at_time');
    expect(tester.takeException(), isNull);
  });

  // Function Name: snapshot focus success test
  // Description: Tapping a snapshot runs the shared focus search, which selects the fresh live place and closes the list.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('snapshot tap focuses the live place', (tester) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map, size: const Size(390, 2400));
    await _tapToggle(tester);
    await _openList(tester);
    final before = server.requests.length;
    await tester.tap(find.byKey(const ValueKey('pharmacy-snapshot-far-fav')));
    await tester.pumpAndSettle();
    final focus = server.requests.sublist(before);
    expect(focus.map((r) => r.mode), ['all', 'all']);
    expect(focus.first.latitude, closeTo(_device.latitude, 1e-6));
    expect(focus.last.latitude, closeTo(37.60, 1e-6));
    expect(focus.last.radius, '0.3');
    expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
    expect(map.selected, 'far-fav');
    expect(map.ids, contains('far-fav'));
    expect(
      find.byKey(const ValueKey('pharmacy-detail-far-fav')),
      findsOneWidget,
    );
    expect(find.text('이 곳의 정보를 찾지 못했어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Function Name: snapshot focus failure test
  // Description: A snapshot missing from both lookups shows the not-found notice and stays a snapshot.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('snapshot tap reports a place that cannot be found', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map, size: const Size(390, 2400));
    await _tapToggle(tester);
    await _openList(tester);
    await tester.tap(find.byKey(const ValueKey('pharmacy-snapshot-gone-fav')));
    await tester.pumpAndSettle();
    expect(find.text('이 곳의 정보를 찾지 못했어요'), findsOneWidget);
    expect(map.selected, isNull);
    expect(find.byKey(const Key('pharmacy-detail-sheet')), findsNothing);
    // 안내가 사라진 뒤 목록 버튼을 누른다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _openList(tester);
    expect(
      find.byKey(const ValueKey('pharmacy-snapshot-gone-fav')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // Function Name: retained un-star test
  // Description: Un-starring the selected place in favorites mode keeps it listed until it is deselected.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('un-starred selected place stays until deselected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map);
    await _tapToggle(tester);
    await tester.tap(find.byKey(const ValueKey('fav-marker-open-fav')));
    await tester.pumpAndSettle();
    final star = find.byKey(const Key('pharmacy-detail-favorite'));
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(star).tooltip, '즐겨찾기 추가');
    expect(map.selected, 'open-fav');
    expect(map.ids, contains('open-fav'));
    expect(
      find.byKey(const ValueKey('pharmacy-detail-open-fav')),
      findsOneWidget,
    );
    expect((await _storedSnapshots()).containsKey('open-fav'), isFalse);
    await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
    await tester.pumpAndSettle();
    expect(map.ids, ['closed-fav']);
    expect(tester.takeException(), isNull);
  });

  // Function Name: snapshot lifecycle test
  // Description: Loading prunes snapshots against the IDs and records legacy ID-only favorites from results; starring writes, un-starring removes, and later results rewrite only changed fields.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('snapshots follow star, results and un-star', (tester) async {
    var now = DateTime.utc(2026, 11, 28, 1);
    SharedPreferences.setMockInitialValues({
      _pharmacyIdsKey: ['open-fav'],
      _pharmacyPlacesKey: _snapshotJson([('stale', 37.5, 127.0)]),
    });
    final server = _Server(near: [_row('open-fav'), _row('open-other')]);
    final map = _MapProbe();
    await _pump(tester, server, map, clock: () => now);
    var stored = await _storedSnapshots();
    expect(stored.keys, ['open-fav']);
    expect(stored['open-fav']['saved_at'], '2026-11-28T01:00:00.000Z');

    await tester.tap(find.byKey(const ValueKey('fav-marker-open-other')));
    await tester.pumpAndSettle();
    final star = find.byKey(const Key('pharmacy-detail-favorite'));
    await tester.tap(star);
    await tester.pumpAndSettle();
    stored = await _storedSnapshots();
    expect(stored.keys.toSet(), {'open-fav', 'open-other'});
    expect(stored['open-other']['name'], '장소 open-other');
    expect(stored['open-other']['address'], '서울 open-other');
    expect(stored['open-other']['telephone'], '02-111-1111');
    expect(stored['open-other']['latitude'], 37.5666);
    expect(stored['open-other']['longitude'], 126.9781);

    await tester.tap(star);
    await tester.pumpAndSettle();
    expect((await _storedSnapshots()).keys, ['open-fav']);

    // Same fields: the refresh does not rewrite the record.
    now = DateTime.utc(2026, 11, 28, 2);
    await tester.tap(find.byTooltip('약국 목록 새로고침'));
    await tester.pumpAndSettle();
    expect(
      (await _storedSnapshots())['open-fav']['saved_at'],
      '2026-11-28T01:00:00.000Z',
    );

    // A changed address is written with the new time.
    server.near[0] = _row('open-fav', address: '서울 새 주소');
    now = DateTime.utc(2026, 11, 28, 3);
    await tester.pump(const Duration(seconds: 11));
    await tester.tap(find.byTooltip('약국 목록 새로고침'));
    await tester.pumpAndSettle();
    stored = await _storedSnapshots();
    expect(stored['open-fav']['address'], '서울 새 주소');
    expect(stored['open-fav']['saved_at'], '2026-11-28T03:00:00.000Z');
    expect(tester.takeException(), isNull);
  });

  // Function Name: empty state test
  // Description: Favorites mode without any favorite, and with favorites that are neither live nor stored, shows the matching empty message.
  // Parameters: tester.
  // Returns: Future<void>.
  for (final hasFavorite in [false, true]) {
    testWidgets('favorites empty state: hasFavorite=$hasFavorite', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        if (hasFavorite) _pharmacyIdsKey: ['nowhere'],
      });
      final map = _MapProbe();
      await _pump(tester, pharmacyServer(), map);
      await _tapToggle(tester);
      final title = hasFavorite ? '이 지역에는 즐겨찾기한 약국이 없어요' : '아직 즐겨찾기한 약국이 없어요';
      expect(map.ids, isEmpty);
      expect(map.status, '$title. 별 버튼으로 추가할 수 있어요.');
      await _openList(tester);
      expect(find.text(title), findsOneWidget);
      expect(find.text('별 버튼으로 추가할 수 있어요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '모두 보기'));
      await tester.pumpAndSettle();
      expect(map.ids.toSet(), {'open-fav', 'open-other'});
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: chat selection test
  // Description: Chat place sharing in favorites mode offers live favorites only, never snapshots.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('chat selection mode lists no snapshots', (tester) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final map = _MapProbe();
    await _pump(
      tester,
      pharmacyServer(),
      map,
      selection: true,
      size: const Size(390, 2400),
    );
    await _tapToggle(tester);
    await _openList(tester);
    expect(
      find.byKey(const ValueKey('pharmacy-card-open-fav')),
      findsOneWidget,
    );
    expect(find.textContaining('운영 정보는 누르면'), findsNothing);
    expect(
      find.byKey(const ValueKey('pharmacy-snapshot-far-fav')),
      findsNothing,
    );
    expect(find.text('약국 목록 보기 (2)'), findsNothing);
    await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('약국 목록 보기 (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Function Name: star appearance test
  // Description: The star is a 48 dp target; unselected draws a thick outline (32 px dark star under a 22 px white star), selected a 32 px amber star.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('star button size and colours', (tester) async {
    final map = _MapProbe();
    await _pump(tester, pharmacyServer(), map);
    await tester.tap(find.byKey(const ValueKey('fav-marker-open-fav')));
    await tester.pumpAndSettle();
    final star = find.byKey(const Key('pharmacy-detail-favorite'));
    expect(tester.getSize(star), const Size(48, 48));
    List<Icon> icons() => tester
        .widgetList<Icon>(
          find.descendant(of: star, matching: find.byType(Icon)),
        )
        .toList();
    var drawn = icons();
    expect(drawn.map((icon) => icon.icon), [
      Icons.star_rounded,
      Icons.star_rounded,
    ]);
    expect(drawn.map((icon) => icon.size), [32, 22]);
    expect(drawn.map((icon) => icon.color), [
      MedBuddyColors.textStrong,
      Colors.white,
    ]);
    await tester.tap(star);
    await tester.pumpAndSettle();
    drawn = icons();
    expect(drawn, hasLength(1));
    expect(drawn.single.icon, Icons.star_rounded);
    expect(drawn.single.size, 32);
    expect(drawn.single.color, nearbyFavoriteStarColor);
    expect(nearbyFavoriteStarColor, const Color(0xFFF2A900));
    expect(tester.getSize(star), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  // Function Name: toggle visibility test
  // Description: The toggle is shown only while at least 210 dp of map remain above the details sheet, 100 dp above the sheet edge, and never over the expanded list.
  // Parameters: tester.
  // Returns: Future<void>.
  for (final height in [844.0, 420.0, 380.0]) {
    testWidgets('favorites toggle visibility at height $height', (
      tester,
    ) async {
      final map = _MapProbe();
      await _pump(tester, pharmacyServer(), map, size: Size(390, height));
      final mapRect = tester.getRect(
        find.byKey(const Key('favorites-test-map')),
      );
      // 지도 대역은 지도 영역 전체를 채운다. 가장 낮은 화면은 처음부터 숨긴다.
      expect(mapRect.height >= 210, height >= 420);
      expect(_toggle, mapRect.height >= 210 ? findsOneWidget : findsNothing);
      if (mapRect.height >= 210) {
        final toggleRect = tester.getRect(_toggle);
        expect(toggleRect.size, const Size(48, 48));
        expect(mapRect.bottom - toggleRect.bottom, closeTo(100, .1));
        expect(mapRect.right - toggleRect.right, closeTo(8, .1));
      }
      await tester.tap(find.byKey(const ValueKey('fav-marker-open-fav')));
      await tester.pumpAndSettle();
      final sheetTop = tester
          .getTopLeft(find.byKey(const Key('pharmacy-detail-sheet')))
          .dy;
      final visibleMap = sheetTop - mapRect.top;
      // 큰 화면은 정보창 위에도 버튼을 두고, 작은 화면은 정보창이 열리면 숨긴다.
      expect(visibleMap >= 210, height > 800);
      expect(_toggle, visibleMap >= 210 ? findsOneWidget : findsNothing);
      if (visibleMap >= 210) {
        expect(sheetTop - tester.getRect(_toggle).bottom, closeTo(100, 1));
      }
      await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
      await tester.pumpAndSettle();
      await _openList(tester);
      expect(_toggle, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: back test
  // Description: Back closes details first, then leaves favorites mode before the screen.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('back leaves favorites mode before the screen', (tester) async {
    SharedPreferences.setMockInitialValues(favoritePrefs);
    final server = pharmacyServer();
    final map = _MapProbe();
    await _pump(tester, server, map);
    await _tapToggle(tester);
    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();
    expect(_toggleTooltip(tester), '즐겨찾기만 보기');
    expect(server.requests.last.mode, 'open_at_time');
    expect(find.byType(CheckNearbyPharmacyUI), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Function Name: hospital favorites test
  // Description: Hospital favorites mode keeps the department search; a snapshot tap searches every department and state, and leaving the mode restores the department and filter.
  // Parameters: tester.
  // Returns: Future<void>.
  testWidgets('hospital favorites keep then restore the department', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'medbuddy.hospital_search_guide_v1': true,
      'medbuddy.favorite_hospital_ids': ['h-near', 'h-far'],
      'medbuddy.favorite_hospital_places': _snapshotJson([
        ('h-far', 37.60, 127.05),
      ]),
    });
    final server = _Server(
      near: [_row('h-near', hospitals: true), _row('h-other', hospitals: true)],
      far: [_row('h-far', latitude: 37.60, longitude: 127.05, hospitals: true)],
    );
    final map = _MapProbe();
    final control =
        await _pump(
              tester,
              server,
              map,
              hospitals: true,
              size: const Size(390, 2400),
            )
            as CheckNearbyHospital;
    final option = find.byKey(
      const ValueKey('hospital-department-option-D001'),
    );
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(server.requests.last.department, 'D001');
    expect(server.requests.last.mode, 'open_at_time');
    final searches = server.requests.length;

    await _tapToggle(tester);
    expect(server.requests.length, searches);
    expect(map.ids, ['h-near']);
    await _openList(tester);
    expect(
      find.byKey(const ValueKey('pharmacy-snapshot-h-far')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pharmacy-snapshot-h-far')));
    await tester.pumpAndSettle();
    expect(control.department, isNull);
    expect(server.requests.last.department, isNull);
    expect(server.requests.last.mode, 'all');
    expect(map.selected, 'h-far');

    await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
    await tester.pumpAndSettle();
    await _tapToggle(tester);
    expect(control.department, 'D001');
    expect(server.requests.last.department, 'D001');
    expect(server.requests.last.mode, 'open_at_time');
    expect(tester.takeException(), isNull);
  });
}
