// 파일명: check_result_ui_boundary_test.dart
// 역할: 분석 결과의 2×2 표와 저장 동작을 실제 날짜·네트워크에 의존하지 않고 검증한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: medication
// 함수역할:
// - 정기/필요시 복용과 시작일 누락을 선택할 수 있는 분석 결과 약을 만든다.
// 매개변수:
// - asNeeded(bool): 필요시 복용 여부; 기본 false.
// - missing(bool): true이면 처방 시작일을 null로 설정.
// 반환값:
// - AnalyzedMedication: 1정·2회·5일 일정과 비어 있는 상세정보.
AnalyzedMedication medication({bool asNeeded = false, bool missing = false}) =>
    AnalyzedMedication(
      schedule: MedicationSchedule(
        medicationName: asNeeded ? '시험용 필요시 약' : '시험용 긴 이름 약품 100밀리그램',
        dosage: '1정',
        intakeTime: '2회',
        medicationTime: 5,
        prescriptionDate: missing ? null : DateTime(2026, 1, 2),
        dosingMode: asNeeded ? 'as_needed' : 'scheduled',
        scheduleSlotKeys: const ['morning', 'evening'],
      ),
      detail: const MedicationDetail(
        itemName: '',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
    );

// Function Name: screen
// Description:
// - Mounts analysis results with configurable saving, comparison loading, motion and locale state, using deterministic fixture defaults.
// Parameters:
// - english (bool), scale (double): UI language and text scale.
// - items (List<AnalyzedMedication>?): Rows; defaults to regular and as-needed fixtures.
// - saved (Set<int>), saving (int?), savingAll (bool): Completed indexes and current save state.
// - save (Future<bool> Function(AnalyzedMedication, int)?), saveAll (Future<bool> Function()? ): Individual and bulk callbacks; default to success.
// - radar (PrescriptionChangeRadar?), radarLoading (bool): Comparison data and loading state.
// - reduceMotion (bool): Disables animations through MediaQuery.
// Returns:
// - Widget: A themed MaterialApp with fixed save-feedback text and an inert close action.
Widget screen({
  bool english = false,
  double scale = 1,
  List<AnalyzedMedication>? items,
  Set<int> saved = const {},
  int? saving,
  bool savingAll = false,
  Future<bool> Function(AnalyzedMedication, int)? save,
  Future<bool> Function()? saveAll,
  PrescriptionChangeRadar? radar,
  bool radarLoading = false,
  bool reduceMotion = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Platform.environment['MEDBUDDY_TEST_FONT'] == null
      ? MedBuddyTheme.light()
      : MedBuddyTheme.light().copyWith(
          textTheme: MedBuddyTheme.light().textTheme.apply(
            fontFamily: 'Noto Sans KR',
          ),
        ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: CheckResultUI(
    analyzedMedicationList: items ?? [medication(), medication(asNeeded: true)],
    prescriptionChangeRadar: radar,
    isPrescriptionChangeLoading: radarLoading,
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    statusMessageProvider: () => '시험 저장 결과',
    savingMedicationIndex: saving,
    completedMedicationSaveIndexes: saved,
    isAllMedicationSaving: savingAll,
    onCloseRequested: () {},
    onAllMedicationSaveRequested: saveAll ?? () async => true,
    onMedicationSaveRequested: save ?? (_, _) async => true,
  ),
);

// 함수이름: main
// 함수역할:
// - 요약·접이식 분석 결과·저장 상태 변경과 화면 크기별 배치 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  for (final scale in [1.0, 2.0]) {
    // 함수이름: 여러 줄 약명의 헤더 높이
    // 함수역할:
    // - 두 글씨 배율에서 약명 1·2·4줄이 헤더 안에 들어가며 헤더가 증가하고 저장·펼치기 버튼이 겹치지 않는지 확인한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('result header grows for multiline names scale=$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      double previousHeight = 0;
      for (final lines in [1, 2, 4]) {
        final item = AnalyzedMedication(
          schedule: MedicationSchedule(
            medicationName: List.filled(lines, '시험약').join('\n'),
            dosage: '1정',
          ),
          detail: const MedicationDetail(
            itemName: '',
            efficacy: '',
            usageMethod: '',
            warning: '',
          ),
        );
        await tester.pumpWidget(
          screen(items: [item], scale: scale, reduceMotion: true),
        );
        await tester.pumpAndSettle();
        final header = tester.getRect(
          find.byKey(const Key('result-medication-header-0')),
        );
        final name = tester.getRect(
          find.byKey(const Key('result-medication-name-0')),
        );
        final save = tester.getRect(
          find.byKey(const Key('result-medication-save-0')),
        );
        final toggle = tester.getRect(
          find.byKey(const Key('result-medication-toggle-0')),
        );
        expect(name.top, greaterThanOrEqualTo(header.top));
        expect(name.bottom, lessThanOrEqualTo(header.bottom));
        expect(header.height, greaterThanOrEqualTo(previousHeight));
        if (lines == 4) expect(header.height, greaterThan(previousHeight));
        previousHeight = header.height;
        expect(save.center.dy, closeTo(toggle.center.dy, .1));
        expect(save.right, lessThanOrEqualTo(toggle.left));
        if (scale == 1) expect(save.center.dy, closeTo(header.center.dy, .1));
        expect(tester.takeException(), isNull);
      }
      if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../.dart_tool/result_previews/result-multiline-$scale.png',
          ),
        );
      }
    });
  }
  final resultScroll = find.descendant(
    of: find.byKey(const Key('analysis-result-list')),
    matching: find.byType(Scrollable),
  );
  // 함수이름: expand
  // 함수역할:
  // - 대상 펼치기 버튼이 눌릴 때까지 결과 목록을 최대 30회 스크롤한 뒤 누른다.
  // 매개변수:
  // - tester(WidgetTester): 화면 제어기.
  // - index(int): 펼칠 약의 인덱스.
  // 반환값:
  // - Future<void>: 펼치기 전환 완료; 버튼을 찾지 못하면 검증 실패.
  Future<void> expand(WidgetTester tester, int index) async {
    final toggle = find.byKey(Key('result-medication-toggle-$index'));
    for (
      var attempt = 0;
      attempt < 30 && toggle.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(resultScroll, const Offset(0, -60));
      await tester.pumpAndSettle();
    }
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  // 함수이름: 즉시 요약과 결과 조작
  // 함수역할:
  // - 인트로 없이 요약을 보이고 첫 행을 즉시 접고 펼칠 수 있으며 스크롤·저장 상태 재구성 후에도 요약을 고정하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('summary is immediately visible and results are interactive', (
    tester,
  ) async {
    final items = List.generate(12, (_) => medication());
    await tester.pumpWidget(screen(items: items));
    final intro = find.byKey(const Key('analysis-summary-intro'));
    final pinned = find.byKey(const Key('analysis-summary-pinned'));
    expect(intro, findsNothing);
    expect(pinned, findsOneWidget);
    final toggle = find.byKey(const Key('result-medication-toggle-0'));
    await tester.tap(toggle);
    await tester.pump();
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
    final before = tester.getTopLeft(pinned);
    await tester.drag(resultScroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pinned), before);
    await tester.pumpWidget(screen(items: items, saved: {0}));
    await tester.pumpAndSettle();
    expect(intro, findsNothing);
  });

  // 함수이름: 처음 접힌 결과 목록
  // 함수역할:
  // - 결과 안내 문구를 표시하고 두 약의 상세 표는 초기 화면에서 숨기며 선택적 미리보기 캡처 시 오류가 없는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('compact result previews and rounded shared header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen());
    if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../.dart_tool/result_previews/result-immediate.png'),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('분석한 약과 복용 일정을 확인하고 저장합니다.'), findsOneWidget);
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
    expect(find.byKey(const Key('result-medication-summary-1')), findsNothing);
    if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../.dart_tool/result_previews/result-collapsed.png'),
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final english in [false, true]) {
    // 함수이름: 가로 화면의 목록과 저장 접근
    // 함수역할:
    // - 두 언어·2배 글씨의 640x360 화면에서 목록 높이를 확보하고 전체 저장과 첫 약 펼치기를 조작할 수 있는지 확인한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets(
      'landscape keeps results and save action usable english=$english',
      (tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(screen(english: english, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.getSize(resultScroll).height, greaterThan(40));
        expect(
          find.byKey(const Key('prescription-save-all')).hitTestable(),
          findsOneWidget,
        );
        await expand(tester, 0);
        expect(
          find.byKey(const Key('result-medication-summary-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // 함수이름: 동작 줄이기와 즉시 종료
  // 함수역할:
  // - 애니메이션 설정과 무관하게 인트로를 만들지 않고 화면 제거 후 시간을 진행해도 예외가 없는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('summary is immediate with either motion preference', (
    tester,
  ) async {
    await tester.pumpWidget(screen(reduceMotion: true));
    expect(find.byKey(const Key('analysis-summary-intro')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    expect(find.byKey(const Key('analysis-summary-intro')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 저장 재구성 후 펼침 상태
  // 함수역할:
  // - 첫 약을 펼친 채 저장 완료 상태로 재구성해도 열린 표를 유지하고 사용자가 다시 접을 수 있는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('expanded results retain their state across save rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await expand(tester, 0);
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('result-medication-summary-1')), findsNothing);
    await tester.pumpWidget(screen(saved: {0}));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('result-medication-toggle-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result-medication-summary-0')), findsNothing);
  });

  // Function Name: expanded row survives comparison failure
  // Description:
  // - Removes the comparison-loading placeholder without a radar result and verifies the first row stays open while the second stays closed.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('expanded results stay open when the radar request fails', (
    tester,
  ) async {
    await tester.pumpWidget(screen(radarLoading: true));
    await tester.pump(const Duration(milliseconds: 500));
    final toggle = find.byKey(const Key('result-medication-toggle-0'));
    await tester.ensureVisible(toggle);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );

    // 비교 요청이 실패하면 로딩 칸이 사라지고 레이더 없이 다시 그려진다.
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('result-medication-summary-0')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('result-medication-summary-1')), findsNothing);
  });

  // 함수이름: 비교 요약과 저장 인덱스
  // 함수역할:
  // - 처방 비교 요약이 앞에 있어도 첫 약 저장 콜백에는 인덱스 0을 전달하고 상태 메시지를 표시하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('comparison summary does not shift medication save indexes', (
    tester,
  ) async {
    int? savedIndex;
    await tester.pumpWidget(
      screen(
        radar: const PrescriptionChangeRadar(hasPreviousPrescription: false),
        save: (_, index) async {
          savedIndex = index;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    final save = find.descendant(
      of: find.byKey(const Key('result-medication-card-0')),
      matching: find.byIcon(Icons.save_outlined),
    );
    await tester.scrollUntilVisible(save, 100, scrollable: resultScroll);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(savedIndex, 0);
    expect(find.text('시험 저장 결과'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
  // 함수이름: setUpAll
  // 함수역할:
  // - 선택적 테스트 글꼴 파일이 있으면 텍스트·아이콘 글꼴을 로드하고 없으면 기본 환경을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 글꼴 준비 완료; 로드 오류는 전달된다.
  setUpAll(() async {
    final font = Platform.environment['MEDBUDDY_TEST_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in ['Roboto', 'Noto Sans KR', 'Arial', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final english in [false, true]) {
    for (final large in [false, true]) {
      // 함수이름: 정기·필요시 결과 표의 배치
      // 함수역할:
      // - 언어와 화면/글씨 조합에서 두 열의 표, 원래 날짜·시간대·잘리지 않는 이름을 확인하고 필요시 문구와 저장 버튼이 겹치지 않는지 검증한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
      testWidgets('result table english=$english large=$large', (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 390, large ? 568 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(screen(english: english, scale: large ? 2 : 1));
        await tester.pumpAndSettle();

        expect(find.text(english ? 'Frequency' : '1일 횟수'), findsNothing);
        expect(
          find.byKey(const Key('result-medication-summary-0')),
          findsNothing,
        );
        await expand(tester, 0);
        await tester.scrollUntilVisible(
          find.byKey(const Key('result-medication-summary-0')),
          100,
          scrollable: resultScroll,
        );
        await tester.pumpAndSettle();
        final summary = tester.widget<Table>(
          find.byKey(const Key('result-medication-summary-0')),
        );
        final schedule = tester.widget<Table>(
          find.byKey(const Key('result-medication-schedule-0')),
        );
        expect(summary.children.single.children, hasLength(2));
        expect(schedule.children.single.children, hasLength(2));
        expect(find.text('2026-01-02'), findsWidgets);
        expect(
          find.text(english ? 'Morning, Evening' : '아침, 저녁'),
          findsOneWidget,
        );
        final name = tester.widget<Text>(find.text('시험용 긴 이름 약품 100밀리그램'));
        expect(name.maxLines, isNull);
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        final footer = find.byKey(const Key('prescription-save-all'));
        expect(footer.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../.dart_tool/result_previews/result-${english ? 'en' : 'ko'}-${large ? 'large' : 'normal'}.png',
            ),
          );
        }
        final prn = find.text(english ? 'As needed' : '필요시 복용');
        await expand(tester, 1);
        await tester.scrollUntilVisible(prn, 120, scrollable: resultScroll);
        await tester.pumpAndSettle();
        expect(prn.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(prn).bottom,
          lessThan(tester.getRect(footer).top),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: 저장 완료 행과 개별 인덱스
  // 함수역할:
  // - 이미 저장한 첫 행의 저장을 막고 두 번째 필요시 약만 인덱스 1로 전달하며 완료 안내를 표시하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'individual save keeps its index and saved rows cannot save again',
    (tester) async {
      final requests = <int>[];
      await tester.pumpWidget(
        screen(
          saved: {0},
          save: (item, index) async {
            requests.add(index);
            expect(item.schedule.isAsNeeded, isTrue);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      final first = find.descendant(
        of: find.byKey(const Key('result-medication-save-0')),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(first).onPressed, isNull);
      final second = find.byIcon(Icons.save_outlined);
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(requests, [1]);
      expect(find.text('복약 일정 저장 완료'), findsOneWidget);
    },
  );

  // 함수이름: 저장 중 잠금과 실패 재시도
  // 함수역할:
  // - 저장 중 전체·해당 행 저장을 막으며 전체 저장 실패 후 성공 안내 없이 상태 메시지를 표시하고 버튼을 다시 활성화하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'saving disables all commands and failures leave retry available',
    (tester) async {
      await tester.pumpWidget(screen(saving: 0));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('prescription-save-all')),
            )
            .onPressed,
        isNull,
      );
      for (final icon in tester.widgetList<IconButton>(
        find.descendant(
          of: find.byKey(const Key('result-medication-save-0')),
          matching: find.byType(IconButton),
        ),
      )) {
        expect(icon.onPressed, isNull);
      }
      var attempts = 0;
      await tester.pumpWidget(
        screen(
          saveAll: () async {
            attempts++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prescription-save-all')));
      await tester.pumpAndSettle();
      expect(find.text('시험 저장 결과'), findsOneWidget);
      expect(find.text('복약 일정 저장 완료'), findsNothing);
      expect(attempts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('prescription-save-all')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 3));
    },
  );

  // 함수이름: 누락 날짜와 비일일 주기
  // 함수역할:
  // - 시작일을 현재 날짜로 추정하지 않고 정보 없음으로 표시하며 격일 문구는 그대로 유지하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'missing start dates stay unknown and non-daily cycles stay visible',
    (tester) async {
      final item = medication(missing: true);
      await tester.pumpWidget(
        screen(
          items: [
            AnalyzedMedication(
              schedule: item.schedule.copyWith(intakeTime: '격일'),
              detail: item.detail,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await expand(tester, 0);
      expect(find.text('정보 없음'), findsOneWidget);
      expect(find.textContaining('격일'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
