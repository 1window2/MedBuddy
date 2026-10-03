// 병원 모드가 공통 지도·목록 동작과 별도 진료과·즐겨찾기를 유지하는지 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_nearby_hospital_control.dart';
import 'package:medbuddy_frontend/entities/device_coordinate_entity.dart';
import 'package:medbuddy_frontend/entities/nearby_pharmacy_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/pharmacy_favorite_service.dart';

class _HospitalControl extends CheckNearbyHospital {
  final requests =
      <
        ({
          String? department,
          PharmacySearchMode mode,
          PharmacySearchArea? area,
          DateTime time,
        })
      >[];
  final calls = <String>[];
  final directions = <String>[];
  bool fail = false;
  bool empty = false;
  bool truncated = false;
  bool regionScopeUncertain = false;
  PharmacySearchArea initialArea = PharmacySearchArea(
    center: PharmacySearchArea.hongik.center,
    radiusKm: .3,
    isFallback: true,
  );
  String holidayStatus = 'stale_fallback';
  Completer<void>? responseGate;

  // 네트워크 없이 조회 조건과 지도 지역을 기록한다.
  @override
  Future<NearbyPharmacySearchResult> requestNearbyCareSearch({
    PharmacySearchMode searchMode = PharmacySearchMode.openAtTime,
    DateTime? targetDateTime,
    double maxDistanceKm = 20,
    PharmacySearchArea? searchArea,
  }) async {
    final time = targetDateTime ?? DateTime.now();
    requests.add((
      department: department,
      mode: searchMode,
      area: searchArea,
      time: time,
    ));
    await responseGate?.future;
    if (fail) throw StateError('test failure');
    return NearbyPharmacySearchResult(
      searchArea: searchArea ?? initialArea,
      data: empty
          ? []
          : [
              NearbyPharmacy.fromJson({
                'hospital_id': 'hospital-1',
                'name': '메드버디의원',
                'address': '서울특별시 마포구',
                'telephone': '02-123-4567',
                'latitude': 37.5516,
                'longitude': 126.9250,
                'distance_km': .2,
                'today_open_time': '09:00',
                'today_close_time': '18:00',
                'is_open_now': holidayStatus == 'unknown' ? null : true,
                'departments': ['내과', '이비인후과'],
                'institution_type': '의원',
                'is_official_late_night': true,
                'designation_is_stale': true,
              }),
            ],
      searchMode: searchMode,
      targetDateTime: time,
      catalogUpdatedAt: null,
      catalogIsStale: true,
      searchTruncated: truncated,
      regionScopeUncertain: regionScopeUncertain,
      holidayScheduleStatus: holidayStatus,
    );
  }

  // 전화·길찾기는 실제 앱을 열지 않고 선택 대상을 기록한다.
  @override
  Future<bool> requestPhoneCall(String telephone) async {
    calls.add(telephone);
    return true;
  }

  @override
  Future<bool> requestInstalledMapDirections(NearbyPharmacy pharmacy) async {
    directions.add(pharmacy.pharmacyId);
    return true;
  }
}

class _MapProbe {
  late Future<bool> Function(PharmacySearchArea) search;
  late VoidCallback locate;
  String? selected;
  PharmacySearchArea? area;

  // 지도 계약은 그대로 두고 결과 이름과 선택 콜백만 표시한다.
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
    search = onSearchAreaRequested;
    locate = onCurrentLocationRequested;
    selected = selectedPharmacyId;
    area = searchArea;
    return ColoredBox(
      key: const Key('hospital-test-map'),
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusText != null)
              Text(statusText, maxLines: 2, overflow: TextOverflow.ellipsis),
            for (final pharmacy in pharmacies)
              TextButton(
                key: ValueKey('hospital-marker-${pharmacy.pharmacyId}'),
                onPressed: () => onPharmacySelected(pharmacy),
                child: Text(pharmacy.name),
              ),
          ],
        ),
      ),
    );
  }
}

// 화면 크기·언어·글씨 배율을 명시해 병원 화면을 연다.
Future<void> _pumpHospital(
  WidgetTester tester,
  _HospitalControl control,
  _MapProbe map, {
  double width = 360,
  double scale = 1,
  String language = 'ko',
  bool selection = false,
  bool chooseDepartment = true,
  DateTime Function()? clock,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(control.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child:
              (selection
              ? CheckNearbyPharmacyUI.selection
              : CheckNearbyPharmacyUI.new)(
                hospitals: true,
                clock: clock,
                userSetting: UserSetting(
                  language: language,
                  userHash: 'hospital-ui-test',
                ),
                control: control,
                mapBuilder: map.build,
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (chooseDepartment) {
    await tester.tap(find.byKey(const ValueKey('hospital-department-option-')));
    await tester.pumpAndSettle();
  }
}

// 운영 조건 선택창에서 스크롤이 필요한 항목도 선택한다.
Future<void> _chooseFilter(
  WidgetTester tester,
  String value, {
  bool map = true,
}) async {
  final selector = find.byKey(
    Key(map ? 'pharmacy-map-filter-selector' : 'pharmacy-filter-selector'),
  );
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('pharmacy-filter-option-$value'));
  await tester.scrollUntilVisible(
    option,
    160,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('care-filter-apply')));
  await tester.pumpAndSettle();
}

// 진료과목 선택창에서 공식 코드를 선택한다.
Future<void> _chooseDepartment(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(const Key('hospital-map-department-selector')));
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('hospital-department-option-$code'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

// 진료과는 왼쪽, 운영 조건은 오른쪽이며 텍스트가 버튼 밖으로 나가지 않는다.
void _expectFilterLayout(WidgetTester tester, {bool map = true}) {
  final left = find.byKey(
    Key(
      map ? 'hospital-map-department-selector' : 'hospital-department-selector',
    ),
  );
  final right = find.byKey(
    Key(map ? 'pharmacy-map-filter-selector' : 'pharmacy-filter-selector'),
  );
  final leftRect = tester.getRect(left);
  final rightRect = tester.getRect(right);
  expect(leftRect.right, lessThan(rightRect.left));
  expect(leftRect.top, rightRect.top);
  for (final button in [left, right]) {
    final label = find.descendant(of: button, matching: find.byType(Text));
    final buttonRect = tester.getRect(button);
    final textRect = tester.getRect(label);
    expect(textRect.left, greaterThanOrEqualTo(buttonRect.left));
    expect(textRect.right, lessThanOrEqualTo(buttonRect.right));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  expect(tester.takeException(), isNull);
}

// 병원 전용 표시와 약국 기본 경로의 호환성을 검증한다.
void main() {
  // 일반 검색과 채팅 공유 모두 사용자가 진료과를 고르기 전에는 검색하지 않는다.
  for (final selection in [false, true]) {
    for (final language in ['ko', 'en']) {
      testWidgets('specialty is chosen before search: $selection/$language', (
        tester,
      ) async {
        final control = _HospitalControl();
        await _pumpHospital(
          tester,
          control,
          _MapProbe(),
          selection: selection,
          language: language,
          width: 320,
          scale: 1.6,
          chooseDepartment: false,
        );
        expect(control.requests, isEmpty);
        expect(
          find.text(language == 'ko' ? '진료과목 선택' : 'Select specialty'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('hospital-test-map')), findsNothing);
        expect(find.byKey(const Key('pharmacy-list-toggle')), findsNothing);
        expect(
          find.byTooltip(language == 'ko' ? '병원 목록 새로고침' : 'Refresh hospitals'),
          findsNothing,
        );
        expect(find.byIcon(Icons.radio_button_checked), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(control.requests, isEmpty);
        final option = find.byKey(
          const ValueKey('hospital-department-option-D001'),
        );
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(control.requests, hasLength(1));
        expect(control.requests.single.department, 'D001');
        expect(find.byKey(const Key('hospital-test-map')), findsOneWidget);
        expect(
          find.text(language == 'ko' ? '진료과목 선택' : 'Select specialty'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 전체 선택도 취소나 미선택과 구분하여 첫 요청을 한 번만 만든다.
  testWidgets('all departments requires an explicit first selection', (
    tester,
  ) async {
    final control = _HospitalControl();
    await _pumpHospital(tester, control, _MapProbe(), chooseDepartment: false);
    expect(control.requests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('hospital-department-option-')));
    await tester.pumpAndSettle();
    expect(control.requests, hasLength(1));
    expect(control.requests.single.department, isNull);
    await tester.tap(find.byKey(const Key('hospital-map-department-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(control.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  // 처음 선택하지 않고 화면을 종료하면 뒤늦은 조회도 발생하지 않는다.
  testWidgets('leaving before specialty selection never searches', (
    tester,
  ) async {
    final control = _HospitalControl();
    await _pumpHospital(tester, control, _MapProbe(), chooseDepartment: false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(control.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 날짜·상태를 고르는 동안 조회하지 않고, 취소와 적용을 구분하며 지도 높이를 유지한다.
    testWidgets('hospital date and status apply together in $language', (
      tester,
    ) async {
      final control = _HospitalControl();
      await _pumpHospital(
        tester,
        control,
        _MapProbe(),
        language: language,
        width: 320,
        scale: 1.6,
        clock: () => DateTime(2026, 9, 28, 21, 26),
      );
      final map = find.byKey(const Key('hospital-test-map'));
      final height = tester.getSize(map).height;
      final selector = find.byKey(const Key('pharmacy-map-filter-selector'));
      final date = find.byKey(const Key('care-filter-date'));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text(language == 'ko' ? '날짜' : 'Date'), findsOneWidget);
      expect(
        find.text(language == 'ko' ? '진료 상태' : 'Consultation status'),
        findsOneWidget,
      );
      expect(find.text('2026-09-28'), findsOneWidget);
      expect(find.textContaining('21:26'), findsNothing);
      expect(tester.widget<OutlinedButton>(date).onPressed, isNull);
      final option = find.byKey(
        const ValueKey('pharmacy-filter-option-lateHours'),
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(control.requests, hasLength(1));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(control.requests, hasLength(1));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('2026-09-28'), findsOneWidget);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('30'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('care-filter-apply')));
      await tester.pumpAndSettle();
      expect(control.requests, hasLength(2));
      expect(control.requests.last.mode, PharmacySearchMode.lateHours);
      expect(control.requests.last.time, DateTime(2026, 9, 30, 12));
      expect(find.byKey(const Key('pharmacy-map-search-date')), findsNothing);
      expect(tester.getSize(map).height, greaterThanOrEqualTo(height));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('2026-09-30'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('pharmacy-filter-option-openNow')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026-09-28'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(date).onPressed, isNull);
      await tester.tap(find.byKey(const Key('care-filter-apply')));
      await tester.pumpAndSettle();
      expect(control.requests.last.time, DateTime(2026, 9, 28, 21, 26));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (language, initial, code) in [
    ('ko', 'ㅍ', 'D005'),
    ('ko', 'ㅎ', 'D007'),
    ('en', 'T', 'D007'),
  ]) {
    // 초성 이동은 조회하지 않으며 과목 선택 후에만 기존 검색 지역을 유지해 재조회한다.
    testWidgets('specialty index jumps and selects $language/$initial', (
      tester,
    ) async {
      final control = _HospitalControl();
      await _pumpHospital(tester, control, _MapProbe(), language: language);
      await tester.tap(
        find.byKey(const Key('hospital-map-department-selector')),
      );
      await tester.pumpAndSettle();
      final index = find.byKey(ValueKey('hospital-department-index-$initial'));
      await tester.ensureVisible(index);
      await tester.tap(index);
      await tester.pumpAndSettle();
      final option = find.byKey(ValueKey('hospital-department-option-$code'));
      expect(option.hitTestable(), findsOneWidget);
      expect(control.requests, hasLength(1));
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(control.department, code);
      expect(control.requests, hasLength(2));
      expect(control.requests.last.area?.center, control.initialArea.center);
      await _chooseDepartment(tester, code);
      expect(control.requests, hasLength(2));
      await _chooseDepartment(tester, '');
      expect(control.department, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  // 좁은 화면의 큰 글씨에서도 목록과 초성 영역이 분리되고 취소 시 조회 조건이 유지된다.
  testWidgets('large specialty text stays outside the index rail', (
    tester,
  ) async {
    final control = _HospitalControl();
    await _pumpHospital(tester, control, _MapProbe(), width: 320, scale: 2);
    await tester.tap(find.byKey(const Key('hospital-map-department-selector')));
    await tester.pumpAndSettle();
    final index = find.byKey(const Key('hospital-department-index'));
    final list = find.byKey(const Key('hospital-department-list'));
    expect(tester.getRect(list).right, lessThan(tester.getRect(index).left));
    final jump = find.byKey(const ValueKey('hospital-department-index-ㅈ'));
    await tester.ensureVisible(jump);
    await tester.tap(jump);
    await tester.pumpAndSettle();
    expect(
      find
          .byKey(const ValueKey('hospital-department-option-D016'))
          .hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(control.requests, hasLength(1));
    expect(control.department, isNull);
    expect(tester.takeException(), isNull);
  });

  // 부분 조회 안내가 떠도 환자 위치로 오인하지 않도록 실제 검색 기준을 유지한다.
  testWidgets(
    'chat selection keeps fallback area visible with partial results',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final control = _HospitalControl()..truncated = true;
      await _pumpHospital(tester, control, _MapProbe(), selection: true);
      expect(find.text('검색 기준: 홍익대학교 서울캠퍼스 (위치 확인 불가)'), findsOneWidget);
      await _chooseFilter(tester, 'lateHours');
      expect(find.text('검색 기준: 홍익대학교 서울캠퍼스 (위치 확인 불가)'), findsOneWidget);
      expect(find.text('조회 조건'), findsOneWidget);
      expect(control.requests.last.mode, PharmacySearchMode.lateHours);
      expect(tester.takeException(), isNull);
    },
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'medbuddy.hospital_search_guide_v1': true,
    }),
  );

  for (final language in ['ko', 'en']) {
    // 실제 부분 조회 안내는 시간이 지나거나 필터를 바꿔도 하단에 유지한다.
    testWidgets('partial hospital guide stays below map in $language', (
      tester,
    ) async {
      final control = _HospitalControl()
        ..truncated = true
        ..initialArea = PharmacySearchArea(
          center: PharmacySearchArea.hongik.center,
          radiusKm: 1,
        );
      final map = _MapProbe();
      await _pumpHospital(tester, control, map, language: language);
      final guide = find.text(
        language == 'ko'
            ? '일부 병원 정보를 확인하지 못했어요. 다시 검색하거나 조회 조건을 바꿔보세요.'
            : 'Some hospital data is unavailable. Try again.',
      );
      expect(guide, findsOneWidget);
      final mapFinder = find.byKey(const Key('hospital-test-map'));
      final mapElement = tester.element(mapFinder);
      final heightWithGuide = tester.getSize(mapFinder).height;
      await tester.pump(const Duration(seconds: 3));
      expect(guide, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(guide, findsOneWidget);
      expect(tester.getSize(mapFinder).height, heightWithGuide);
      expect(
        tester.getRect(guide).top,
        greaterThanOrEqualTo(tester.getRect(mapFinder).bottom),
      );
      expect(
        tester.getRect(guide).bottom,
        lessThan(
          tester.getRect(find.byKey(const Key('pharmacy-list-toggle'))).top,
        ),
      );
      expect(tester.element(mapFinder), same(mapElement));
      expect(control.requests, hasLength(1));
      await _chooseFilter(tester, 'lateHours');
      expect(guide, findsOneWidget);
      await map.search(control.initialArea);
      await tester.pumpAndSettle();
      expect(guide, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 하단 부분 조회 안내가 위치 실패나 채팅 공유의 검색 기준을 숨기지 않는다.
  testWidgets('fallback area survives persistent partial hospital guide', (
    tester,
  ) async {
    final control = _HospitalControl()..truncated = true;
    await _pumpHospital(tester, control, _MapProbe(), selection: true);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('검색 기준: 홍익대학교 서울캠퍼스 (위치 확인 불가)'), findsOneWidget);
    expect(find.text('위치를 확인하지 못해 홍익대학교 서울캠퍼스 기준으로 검색했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 안내 표시 중 재조회가 실패해도 오류는 시간 제한 없이 남아 있어야 한다.
  testWidgets('search failure replaces the partial hospital guide', (
    tester,
  ) async {
    final control = _HospitalControl()..truncated = true;
    final map = _MapProbe();
    await _pumpHospital(tester, control, map);
    control.fail = true;
    await map.search(control.initialArea);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('검색하지 못했어요. 지도를 옮겨 다시 검색하거나 새로고침해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 완료 결과에서는 숨기고 다시 부분 결과가 되면 표시한다.
  testWidgets('complete results clear and partial results restore the guide', (
    tester,
  ) async {
    final control = _HospitalControl()..truncated = true;
    final map = _MapProbe();
    await _pumpHospital(tester, control, map);
    const guide = '일부 병원 정보를 확인하지 못했어요. 다시 검색하거나 조회 조건을 바꿔보세요.';
    expect(find.text(guide), findsOneWidget);
    control.truncated = false;
    await map.search(control.initialArea);
    await tester.pumpAndSettle();
    expect(find.text(guide), findsNothing);
    control.truncated = true;
    await map.search(control.initialArea);
    await tester.pumpAndSettle();
    expect(find.text(guide), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  // 안내 중 화면을 닫아도 종료된 화면을 뒤늦게 갱신하지 않는다.
  testWidgets('closing hospital screen does not update disposed state', (
    tester,
  ) async {
    await _pumpHospital(
      tester,
      _HospitalControl()..truncated = true,
      _MapProbe(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  // 확인한 최초 안내는 재진입 시 반복하지 않고, 경고는 그와 독립적으로 남긴다.
  testWidgets('first hospital notice is acknowledged once per device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHospital(tester, _HospitalControl(), _MapProbe());
    expect(find.byKey(const Key('hospital-search-notice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hospital-guide-acknowledge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHospital(tester, _HospitalControl(), _MapProbe());
    expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial warning has no misleading dismiss button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHospital(
      tester,
      _HospitalControl()..truncated = true,
      _MapProbe(),
    );
    expect(find.byKey(const Key('hospital-guide-acknowledge')), findsNothing);
    expect(find.byKey(const Key('hospital-search-notice')), findsOneWidget);
  });

  // 반경 안내는 실제 검색한 3km부터 유지되며 작은 반경에서도 부분 조회가 우선한다.
  for (final language in ['ko', 'en']) {
    // 병원이 없는 지역의 첫 안내가 범위를 더 좁히라는 잘못된 방향을 제시하지 않는다.
    testWidgets(
      'empty rural introduction does not ask to narrow in $language',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final control = _HospitalControl()
          ..empty = true
          ..regionScopeUncertain = true
          ..initialArea = const PharmacySearchArea(
            center: DeviceCoordinate(latitude: 33.36, longitude: 126.356),
            radiusKm: 2,
          );
        await _pumpHospital(tester, control, _MapProbe(), language: language);
        expect(
          find.text(
            language == 'ko'
                ? '공공데이터에 일부 병원이 누락되거나 진료시간이 실제와 다를 수 있어요.'
                : 'Hospital listings and hours may be incomplete or outdated.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'ko' ? '좁혀' : 'smaller'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    // 최초 안내가 긴 언어에서도 확인 버튼과 지도·목록을 가리지 않는다.
    testWidgets('first guide fits narrow large-text screen in $language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHospital(
        tester,
        _HospitalControl(),
        _MapProbe(),
        width: 320,
        scale: 1.6,
        language: language,
      );
      expect(
        tester.getSize(find.byKey(const Key('hospital-test-map'))).height,
        greaterThan(0),
      );
      expect(
        tester.getRect(find.byKey(const Key('pharmacy-list-toggle'))).bottom,
        lessThanOrEqualTo(720),
      );
      await tester.tap(find.byKey(const Key('hospital-guide-acknowledge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide area notice follows searched radius in $language', (
      tester,
    ) async {
      final control = _HospitalControl();
      final map = _MapProbe();
      await _pumpHospital(
        tester,
        control,
        map,
        width: 320,
        scale: 1.6,
        language: language,
      );
      final notice = find.byKey(const Key('hospital-search-notice'));
      for (final radius in [2.9, 3.0, 10.0, 1.0]) {
        await map.search(
          PharmacySearchArea(
            center: control.initialArea.center,
            radiusKm: radius,
            isMapArea: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(notice, radius >= 3 ? findsOneWidget : findsNothing);
        await tester.pump(const Duration(seconds: 5));
        expect(notice, radius >= 3 ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      }
      control.truncated = true;
      await map.search(control.initialArea);
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    testWidgets('hospital filters stay left/right at 320px in $language', (
      tester,
    ) async {
      final control = _HospitalControl();
      await _pumpHospital(
        tester,
        control,
        _MapProbe(),
        width: 320,
        scale: 1.6,
        language: language,
      );
      _expectFilterLayout(tester);
      await _chooseFilter(tester, 'weekendHoliday');
      _expectFilterLayout(tester);
      expect(control.requests.last.mode, PharmacySearchMode.weekendHoliday);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      _expectFilterLayout(tester, map: false);
    });
  }

  testWidgets('specialty and operating filters preserve map and chosen date', (
    tester,
  ) async {
    final control = _HospitalControl();
    final map = _MapProbe();
    await _pumpHospital(tester, control, map);
    for (final key in [
      'hospital-map-department-selector',
      'pharmacy-map-filter-selector',
    ]) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(Key(key))).child,
        isA<Row>(),
      );
    }
    final mapElement = tester.element(
      find.byKey(const Key('hospital-test-map')),
    );
    const area = PharmacySearchArea(
      center: DeviceCoordinate(latitude: 37.5, longitude: 127),
      radiusKm: 4,
      isMapArea: true,
    );
    await map.search(area);
    await tester.pumpAndSettle();
    await _chooseFilter(tester, 'all');
    await tester.tap(find.byKey(const Key('pharmacy-map-filter-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care-filter-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care-filter-apply')));
    await tester.pumpAndSettle();
    final selectedDate = control.requests.last.time;
    expect(selectedDate.hour, 12);
    await _chooseDepartment(tester, 'D013');
    expect(control.requests.last.department, 'D013');
    expect(control.requests.last.area, same(area));
    expect(control.requests.last.time, selectedDate);
    expect(map.area, same(area));
    expect(
      tester.element(find.byKey(const Key('hospital-test-map'))),
      same(mapElement),
    );
    await _chooseDepartment(tester, '');
    expect(control.requests.last.department, isNull);
    await _chooseFilter(tester, 'openNow');
    expect(find.byKey(const Key('pharmacy-map-search-date')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 상세창은 이름을 한 번만 표시하고 공유 버튼을 전화·길찾기에 이어 배치한다.
  for (final scale in [1.0, 1.8]) {
    testWidgets('hospital share action follows directions at scale $scale', (
      tester,
    ) async {
      await _pumpHospital(
        tester,
        _HospitalControl(),
        _MapProbe(),
        selection: true,
        scale: scale,
      );
      await tester.tap(find.byKey(const Key('hospital-marker-hospital-1')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('pharmacy-detail-sheet'));
      expect(
        find.descendant(of: sheet, matching: find.text('메드버디의원')),
        findsOneWidget,
      );
      final share = find.widgetWithText(FilledButton, '채팅에 공유');
      await tester.ensureVisible(share);
      await tester.pumpAndSettle();
      final directions = tester.getRect(
        find.byKey(const Key('pharmacy-directions-hospital-1')),
      );
      final shareRect = tester.getRect(share);
      expect(shareRect.top - directions.bottom, closeTo(8, .1));
      expect(shareRect.right, closeTo(directions.right, .1));
      expect(share.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'hospital list and details reuse phone directions and separate favorites',
    (tester) async {
      final control = _HospitalControl();
      final map = _MapProbe();
      await _pumpHospital(tester, control, map);
      expect(find.text('근처 운영 병원'), findsOneWidget);
      expect(find.text('병원 목록 보기 (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('내과 · 이비인후과'), findsOneWidget);
      expect(find.text('의원'), findsOneWidget);
      expect(find.textContaining('공공심야'), findsNothing);
      expect(find.textContaining('명절 비상운영'), findsNothing);
      expect(find.text('늦게까지 진료'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pharmacy-card-hospital-1')));
      await tester.pumpAndSettle();
      expect(map.selected, 'hospital-1');
      expect(find.byKey(const Key('pharmacy-list-panel')), findsNothing);
      expect(find.byTooltip('병원 정보 닫기'), findsOneWidget);
      expect(find.text('채팅에 공유'), findsNothing);
      await tester.tap(find.byKey(const Key('pharmacy-detail-favorite')));
      await tester.pumpAndSettle();
      expect(
        await PharmacyFavoriteService(
          userHash: 'hospital-ui-test',
          hospitals: true,
        ).loadFavoriteIds(),
        {'hospital-1'},
      );
      expect(
        await PharmacyFavoriteService(
          userHash: 'hospital-ui-test',
        ).loadFavoriteIds(),
        isEmpty,
      );
      await tester.tap(find.text('전화'));
      await tester.pumpAndSettle();
      expect(control.calls, ['02-123-4567']);
      await tester.tap(find.text('길찾기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('설치된 지도 앱 선택'));
      await tester.pumpAndSettle();
      expect(control.directions, ['hospital-1']);
      await tester.tap(find.byKey(const Key('pharmacy-detail-close')));
      await tester.pumpAndSettle();
      expect(map.selected, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hospital source notice excludes pharmacy designation and roster claims',
    (tester) async {
      await _pumpHospital(tester, _HospitalControl(), _MapProbe());
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      final notice = find.textContaining('국립중앙의료원 병원 공공데이터');
      await tester.scrollUntilVisible(
        notice,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('hospital-results-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(notice, findsOneWidget);
      expect(find.textContaining('공공심야'), findsNothing);
      expect(find.textContaining('명절 비상운영'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    // 실패해도 날짜와 조건을 바꿔 바로 정상 결과로 복구할 수 있다.
    testWidgets('holiday search failure keeps controls in $language', (
      tester,
    ) async {
      final control = _HospitalControl();
      await _pumpHospital(
        tester,
        control,
        _MapProbe(),
        width: 320,
        scale: 1.6,
        language: language,
        clock: () => DateTime(2026, 9, 28, 18),
      );
      control.fail = true;
      await _chooseFilter(tester, 'weekendHoliday');
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pharmacy-search-date')), findsNothing);
      _expectFilterLayout(tester, map: false);
      expect(
        find.text(
          language == 'ko'
              ? '병원 정보를 확인할 수 없습니다'
              : 'Hospital information is unavailable',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pharmacy-filter-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('care-filter-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      control.fail = false;
      await _chooseFilter(tester, 'all', map: false);
      expect(control.requests.last.mode, PharmacySearchMode.all);
      expect(
        find.byKey(const ValueKey('pharmacy-card-hospital-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // 평일은 날짜 선택을 안내하고, 평일인 대체공휴일의 결과도 정상 표시한다.
    testWidgets('weekday holiday filter leads to date selection in $language', (
      tester,
    ) async {
      final control = _HospitalControl()
        ..empty = true
        ..holidayStatus = 'not_applicable';
      await _pumpHospital(
        tester,
        control,
        _MapProbe(),
        width: 320,
        scale: 1.6,
        language: language,
        clock: () => DateTime(2026, 9, 28, 18),
      );
      await _chooseFilter(tester, 'weekendHoliday');
      final prompt = language == 'ko'
          ? '주말이나 공휴일을 선택해주세요'
          : 'Choose a weekend or public holiday';
      expect(find.text(prompt), findsOneWidget);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      final action = find.text(
        language == 'ko' ? '조회 조건 변경' : 'Change search conditions',
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('care-filter-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      control
        ..empty = false
        ..holidayStatus = 'weekly_report'
        ..responseGate = Completer<void>();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('care-filter-apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(prompt), findsNothing);
      control.responseGate!.complete();
      await tester.pumpAndSettle();
      expect(control.requests.last.time, DateTime(2026, 10, 5, 12));
      expect(control.requests.last.mode, PharmacySearchMode.weekendHoliday);
      expect(find.text(prompt), findsNothing);
      expect(
        find.byKey(const ValueKey('pharmacy-card-hospital-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'hospital empty and error messages use $language hospital wording',
      (tester) async {
        final control = _HospitalControl()..empty = true;
        await _pumpHospital(tester, control, _MapProbe(), language: language);
        expect(
          find.textContaining(
            language == 'ko' ? '조건에 맞는 병원' : 'No hospitals match',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            language == 'ko' ? '진료 중인 병원이 없습니다' : 'No open hospitals',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'ko' ? '약국' : 'pharmac'),
          findsNothing,
        );
        control.fail = true;
        await tester.tap(
          find.byTooltip(
            language == 'ko' ? '병원 목록 새로고침' : 'Refresh hospital list',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'ko'
                ? '병원 정보를 확인할 수 없습니다'
                : 'Hospital information is unavailable',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(language == 'ko' ? '약국' : 'pharmac'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['ko', 'en']) {
    // 한 건을 정상 조회한 경우 주소 표본만으로 지도 아래 경고를 만들지 않는다.
    testWidgets('sampled region does not add a limit banner in $language', (
      tester,
    ) async {
      final control = _HospitalControl()..regionScopeUncertain = true;
      await _pumpHospital(tester, control, _MapProbe(), language: language);
      expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
      expect(
        find.byKey(const Key('hospital-marker-hospital-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      final source = find.textContaining(
        language == 'ko'
            ? '주변 주소로 검색 지역을 파악하므로'
            : 'Search regions are inferred from nearby addresses',
      );
      await tester.scrollUntilVisible(
        source,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('hospital-results-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(source, findsOneWidget);
      expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 지역이 표본인 빈 결과는 주변에 병원이 없다는 단정 대신 확인한 범위로 한정한다.
    testWidgets(
      'sampled empty region is not an exhaustive search in $language',
      (tester) async {
        final control = _HospitalControl()
          ..regionScopeUncertain = true
          ..empty = true;
        await _pumpHospital(tester, control, _MapProbe(), language: language);
        final message = language == 'ko'
            ? '조회한 병원 중 조건에 맞는 결과가 없습니다'
            : 'No matches among the hospitals checked';
        expect(find.text(message), findsOneWidget);
        expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        expect(find.text(message), findsWidgets);
        expect(find.byKey(const Key('hospital-search-notice')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'partial empty hospital results do not claim an exhaustive search',
    (tester) async {
      final control = _HospitalControl()
        ..empty = true
        ..truncated = true;
      await _pumpHospital(tester, control, _MapProbe());
      const notice = '일부 병원 정보를 확인하지 못했어요. 다시 검색하거나 조회 조건을 바꿔보세요.';
      expect(find.text(notice), findsOneWidget);
      expect(find.text('조회한 병원 중 조건에 맞는 결과가 없습니다'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      expect(find.textContaining('진료 중인 병원이 없습니다'), findsNothing);
      // 시간이 지나도 빈 결과를 전체 병원에 대한 결론처럼 표시하지 않는다.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(notice), findsOneWidget);
      expect(find.text('조회한 병원 중 조건에 맞는 결과가 없습니다'), findsWidgets);
      expect(find.textContaining('진료 중인 병원이 없습니다'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en']) {
    // 달력 장애는 일반 빈 결과 안내로 표시하고, 복구 후에는 정상 진료 결과로 돌아간다.
    testWidgets(
      'calendar recovery restores results without a setup notice in $language',
      (tester) async {
        final control = _HospitalControl()
          ..empty = true
          ..truncated = true
          ..holidayStatus = 'unknown';
        final map = _MapProbe();
        await _pumpHospital(
          tester,
          control,
          map,
          width: 320,
          scale: 1.6,
          language: language,
        );
        final mapFinder = find.byKey(const Key('hospital-test-map'));
        final mapElement = tester.element(mapFinder);
        final unavailable = language == 'ko'
            ? '진료 여부를 확인할 수 없습니다'
            : 'Consultation status cannot be verified';
        expect(find.text(unavailable), findsOneWidget);
        expect(find.byKey(const Key('hospital-calendar-notice')), findsNothing);
        expect(
          find.byKey(const Key('hospital-calendar-show-all')),
          findsNothing,
        );
        expect(
          find.textContaining(
            language == 'ko' ? '진료 중인 병원이 없습니다' : 'No open hospitals',
          ),
          findsNothing,
        );
        expect(tester.getSize(mapFinder).height, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        expect(find.text(unavailable), findsWidgets);
        expect(tester.takeException(), isNull);
        control
          ..empty = false
          ..truncated = false
          ..holidayStatus = 'not_applicable';
        await tester.tap(
          find.byTooltip(
            language == 'ko' ? '병원 목록 새로고침' : 'Refresh hospital list',
          ),
        );
        await tester.pumpAndSettle();
        expect(control.requests.last.mode, PharmacySearchMode.openAtTime);
        expect(tester.element(mapFinder), same(mapElement));
        expect(
          find.byKey(const Key('hospital-marker-hospital-1')),
          findsOneWidget,
        );
        expect(find.text(unavailable), findsNothing);
        expect(find.byKey(const Key('hospital-calendar-notice')), findsNothing);
        expect(
          find.byKey(const Key('hospital-calendar-show-all')),
          findsNothing,
        );
        expect(find.text(language == 'ko' ? '진료 중' : 'Open now'), findsWidgets);
        _expectFilterLayout(tester, map: false);
        await tester.tap(find.byKey(const Key('pharmacy-list-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getSize(mapFinder).height, greaterThan(0));
        _expectFilterLayout(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'pharmacy constructors remain the default and selection stays pharmacy-only',
    () {
      final setting = UserSetting(language: 'ko');
      expect(CheckNearbyPharmacyUI(userSetting: setting).hospitals, isFalse);
      final selection = CheckNearbyPharmacyUI.selection(userSetting: setting);
      expect(selection.hospitals, isFalse);
      expect(selection.selectionMode, isTrue);
    },
  );
}
