// 파일명: prescription_radar_tabs_test.dart
// 역할: 처방 변경 결과의 범주별 접기·펼치기와 빈 범주·갱신 후 선택 상태를 검증한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_change_radar_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: radar
// 함수역할:
// - 변경·추가·누락 범주를 가진 처방 비교 결과를 만들고 변경 개수와 미분류 항목을 조절한다.
// 매개변수:
// - changedCount(int): 변경 목록 길이; 요약의 변경 수 5는 유지된다.
// - unknown(bool): 미분류 항목을 추가할지 여부.
// 반환값:
// - PrescriptionChangeRadar: 고정 이전/현재 처방 날짜와 범주별 항목.
PrescriptionChangeRadar radar({int changedCount = 5, bool unknown = false}) =>
    PrescriptionChangeRadar(
      hasPreviousPrescription: true,
      previousPrescriptionDate: DateTime(2026, 7, 29),
      currentPrescriptionDate: DateTime(2026, 8, 3),
      summary: const PrescriptionChangeSummary(
        addedCount: 2,
        scheduleChangedCount: 5,
        missingCount: 9,
      ),
      changes: [
        for (var i = 0; i < changedCount; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.scheduleChanged,
            itemName: '변경 시험약 ${i + 1}',
            changedFields: const ['dosage_per_time', 'daily_frequency'],
            previous: const PrescriptionScheduleSnapshot(
              dosagePerTime: '1',
              dailyFrequency: '4',
            ),
            current: const PrescriptionScheduleSnapshot(
              dosagePerTime: '1정',
              dailyFrequency: '2회',
            ),
          ),
        for (var i = 0; i < 2; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.added,
            itemName: '새로 확인한 긴 이름의 시험약 ${i + 1} (시험 성분)',
          ),
        for (var i = 0; i < 9; i++)
          PrescriptionMedicationChange(
            type: PrescriptionChangeType.missing,
            itemName: '이전 처방 시험약 ${i + 1}',
          ),
        if (unknown)
          const PrescriptionMedicationChange(
            type: PrescriptionChangeType.unknown,
            itemName: '분류 확인 시험약',
          ),
      ],
    );

// 함수이름: screen
// 함수역할:
// - 변경 비교 위젯을 스크롤 가능한 화면에 언어·텍스트 배율과 함께 배치한다.
// 매개변수:
// - language(String): 표시 언어; 기본 ko.
// - scale(double): 텍스트 배율.
// - data(PrescriptionChangeRadar?): 결과 데이터; 생략하면 기본 radar.
// 반환값:
// - Widget: 테마와 Scaffold를 갖춘 테스트 앱.
Widget screen({
  String language = 'ko',
  double scale = 1,
  PrescriptionChangeRadar? data,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: MedBuddyTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrescriptionChangeRadarUI(
            radar: data ?? radar(),
            userSetting: UserSetting(language: language),
          ),
        ),
      ),
    ),
  ),
);

// 함수이름: tap
// 함수역할:
// - 스크롤로 대상을 보이게 한 뒤 누르고 전환 애니메이션을 완료한다.
// 매개변수:
// - tester(WidgetTester): 화면 제어기.
// - target(Finder): 표시하고 누를 대상.
// 반환값:
// - Future<void>: 상호작용 완료; 대상 누락이나 정착 실패는 테스트 오류.
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할:
// - 변경 범주 탭의 초기 배치, 결과 축소 후 탐색과 접근성 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: setUpAll
  // 함수역할:
  // - 환경 변수로 지정된 테스트 글꼴이 있으면 텍스트·아이콘 글꼴을 로드하고, 없으면 기본 글꼴을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 글꼴 로드 완료; 지정 파일을 읽지 못하면 실패한다.
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

  for (final language in ['ko', 'en']) {
    for (final large in [false, true]) {
      // 함수이름: 범주별 페이지와 단일 상세
      // 함수역할:
      // - 언어·큰 글씨 조합에서 접기/펼치기, 세 항목씩 페이지 이동, 한 개 상세 유지, 마지막 페이지 비활성화와 범주 전환을 검증한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
      testWidgets(
        'tabs page three medications and open one detail $language $large',
        (tester) async {
          tester.view.physicalSize = large
              ? const Size(320, 568)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final data = radar();
          await tester.pumpWidget(
            screen(language: language, scale: large ? 2 : 1, data: data),
          );
          expect(find.text('변경 시험약 1'), findsNothing);
          await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
          expect(find.text('변경 시험약 1'), findsOneWidget);
          expect(find.text('변경 시험약 3'), findsOneWidget);
          expect(find.text('변경 시험약 4'), findsNothing);
          expect(find.byKey(const Key('radar-change-detail')), findsNothing);
          if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true' &&
              !large) {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, 1000),
            );
            await tester.pumpAndSettle();
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/result_previews/radar-tabs-$language.png',
              ),
            );
          }
          await tap(tester, find.text('변경 시험약 1'));
          expect(find.byKey(const Key('radar-change-detail')), findsOneWidget);
          expect(find.text('1정'), findsOneWidget);
          expect(find.text('4'), findsOneWidget);
          await tap(tester, find.text('변경 시험약 2'));
          expect(find.byKey(const Key('radar-change-detail')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('radar-change-0')),
              matching: find.byType(Table),
            ),
            findsNothing,
          );
          await tap(tester, find.byKey(const Key('radar-next-page')));
          expect(find.text('변경 시험약 1'), findsNothing);
          expect(find.text('변경 시험약 5'), findsOneWidget);
          expect(find.byKey(const Key('radar-change-detail')), findsNothing);
          expect(
            tester
                .widget<IconButton>(find.byKey(const Key('radar-next-page')))
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(
            screen(language: language, scale: large ? 2 : 1, data: data),
          );
          expect(find.text('변경 시험약 5'), findsOneWidget);
          await tap(tester, find.byKey(const Key('radar-tab-added')));
          expect(find.text('새로 확인한 긴 이름의 시험약 1 (시험 성분)'), findsOneWidget);
          expect(find.byKey(const Key('radar-next-page')), findsNothing);
          await tap(tester, find.byKey(const Key('radar-tab-missing')));
          expect(find.text('이전 처방 시험약 1'), findsOneWidget);
          await tap(tester, find.byKey(const Key('radar-next-page')));
          await tap(tester, find.byKey(const Key('radar-next-page')));
          expect(find.text('이전 처방 시험약 9'), findsOneWidget);
          expect(
            find.text(
              language == 'ko'
                  ? '이번 처방에서 확인되지 않음'
                  : 'Not found in this prescription',
            ),
            findsOneWidget,
          );
          await tap(tester, find.byKey(const Key('radar-previous-page')));
          expect(find.text('이전 처방 시험약 4'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // 함수이름: 짧아진 결과와 빈 범주
  // 함수역할:
  // - 두 번째 페이지에서 결과를 줄이면 유효 페이지로 돌아오고 빈 범주 안내 후에도 추가 범주를 열 수 있는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('empty category and refreshed shorter results remain usable', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
    await tap(tester, find.byKey(const Key('radar-next-page')));
    await tester.pumpWidget(screen(data: radar(changedCount: 1)));
    await tester.pumpAndSettle();
    expect(find.text('변경 시험약 1'), findsOneWidget);
    expect(find.byKey(const Key('radar-next-page')), findsNothing);
    await tester.pumpWidget(screen(data: radar(changedCount: 0)));
    await tester.pumpAndSettle();
    expect(find.text('이 분류에 해당하는 약이 없습니다.'), findsOneWidget);
    await tap(tester, find.byKey(const Key('radar-tab-added')));
    expect(find.text('새로 확인한 긴 이름의 시험약 1 (시험 성분)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 요약 없는 미분류 항목
  // 함수역할:
  // - 요약 개수가 없어도 미분류 범주와 해당 약을 표시하고 화면 오류가 없는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets(
    'unknown change type is not lost when summary counts are absent',
    (tester) async {
      await tester.pumpWidget(
        screen(
          data: const PrescriptionChangeRadar(
            hasPreviousPrescription: true,
            changes: [
              PrescriptionMedicationChange(
                type: PrescriptionChangeType.unknown,
                itemName: '분류 확인 시험약',
              ),
            ],
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('prescription-radar-toggle')));
      await tap(tester, find.byKey(const Key('radar-tab-unknown')));
      expect(find.text('분류 확인 시험약'), findsOneWidget);
      expect(find.text('기타'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
