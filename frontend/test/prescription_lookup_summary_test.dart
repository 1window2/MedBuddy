// 파일명: prescription_lookup_summary_test.dart
// 역할: 결과 요약의 즉시 표시, 상단 고정, 접근성 및 화면 종료를 검증한다.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

const _statuses = {
  0: MedicationLookupStatus.verified,
  1: MedicationLookupStatus.verified,
  2: MedicationLookupStatus.candidates,
  3: MedicationLookupStatus.candidates,
  4: MedicationLookupStatus.candidates,
  5: MedicationLookupStatus.notFound,
  6: MedicationLookupStatus.notFound,
  7: MedicationLookupStatus.failed,
};

// 함수이름: _screen
// 함수역할:
// - 8개 약과 상태별 개수를 가진 조회 확인 화면에 언어·글씨 배율·동작 줄이기를 적용한다.
// 매개변수:
// - english(bool): 영어 표시 여부.
// - scale(double): 텍스트 배율.
// - reduceMotion(bool): 애니메이션 비활성화 여부.
// - statuses(Map<int, MedicationLookupStatus>): 인덱스별 조회 상태; 검증된 인덱스도 여기서 계산한다.
// 반환값:
// - Widget: 테마와 미디어 설정을 포함한 MaterialApp.
Widget _screen({
  bool english = false,
  double scale = 1,
  bool reduceMotion = false,
  Map<int, MedicationLookupStatus> statuses = _statuses,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: MedBuddyTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: PrescriptionAnalysisPreviewUI(
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    medicationScheduleList: List.generate(
      8,
      (index) => MedicationSchedule(
        medicationName: english
            ? 'Example medication ${index + 1}'
            : '시험약 ${index + 1}',
        dosage: '1정',
        intakeTime: '3회',
        medicationTime: 4,
        prescriptionDate: DateTime(2026, 1, 1),
        scheduleSlotKeys: ['morning', 'lunch', 'evening'],
      ),
    ),
    lookupStatuses: statuses,
    isMedicationLookupReview: true,
    verifiedScheduleIndexes: statuses.entries
        .where((entry) => entry.value == MedicationLookupStatus.verified)
        .map((entry) => entry.key)
        .toSet(),
    onBackRequested: () {},
    onAnalysisRequested: () {},
    onMedicationScheduleChanged: (_, _) {},
  ),
);

// 함수이름: main
// 함수역할:
// - 조회 요약의 폭·글씨 배율·동작 줄이기 설정과 즉시 종료 사례를 등록한다.
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
  for (final english in [false, true]) {
    for (final viewport in [
      (Size(390, 844), 1.0),
      (Size(320, 568), 2.0),
      (Size(640, 360), 2.0),
    ]) {
      // 함수이름: 조회 요약의 즉시 표시와 고정
      // 함수역할:
      // - 두 언어와 화면/글씨 조합에서 인트로 없이 상태별 개수가 표시되고 스크롤·상태 변경 후에도 요약과 제목 위치가 고정되는지 확인한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
      testWidgets(
        'summary appears immediately and stays pinned $english $viewport',
        (tester) async {
          tester.view.physicalSize = viewport.$1;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _screen(english: english, scale: viewport.$2),
          );
          final intro = find.byKey(const Key('lookup-summary-intro'));
          final pinned = find.byKey(const Key('lookup-summary-pinned'));
          expect(intro, findsNothing);
          final firstTop = tester.getTopLeft(pinned).dy;
          if (!english &&
              viewport.$2 == 1 &&
              Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/ocr_share_previews/summary-immediate.png',
              ),
            );
          }
          await tester.pump(const Duration(seconds: 3));
          expect(tester.getTopLeft(pinned).dy, firstTop);
          expect(intro, findsNothing);
          for (final entry in {
            MedicationLookupStatus.verified: 2,
            MedicationLookupStatus.candidates: 3,
            MedicationLookupStatus.notFound: 2,
            MedicationLookupStatus.failed: 1,
          }.entries) {
            expect(
              find.descendant(
                of: find.byKey(Key('lookup-summary-count-${entry.key.name}')),
                matching: find.text('${entry.value}'),
              ),
              findsOneWidget,
            );
          }
          if (!english &&
              viewport.$2 == 1 &&
              Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../.dart_tool/ocr_share_previews/summary-pinned.png',
              ),
            );
          }
          final before = tester.getTopLeft(pinned);
          final titleBefore = tester.getTopLeft(
            find.byKey(const Key('prescription-review-title')),
          );
          final scroll = find
              .ancestor(
                of: find.byKey(const Key('ocr-medication-list')),
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await tester.drag(scroll, const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(pinned), before);
          final scrollRegion = find.byKey(
            const Key('prescription-review-scroll-region'),
          );
          expect(
            tester.getTopLeft(scrollRegion).dy -
                tester
                    .getBottomLeft(
                      find.byKey(const Key('lookup-summary-pinned-viewport')),
                    )
                    .dy,
            closeTo(10, .1),
          );
          expect(
            tester.getTopLeft(
              find.byKey(const Key('prescription-review-title')),
            ),
            titleBefore,
          );
          await tester.pumpWidget(
            _screen(
              english: english,
              scale: viewport.$2,
              statuses: {..._statuses, 7: MedicationLookupStatus.verified},
            ),
          );
          await tester.pumpAndSettle();
          expect(intro, findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const Key('lookup-summary-count-failed')),
              matching: find.text('0'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  // 함수이름: 즉시 종료의 후속 작업
  // 함수역할:
  // - 화면을 바로 제거한 뒤 3초를 진행해도 미완료 작업으로 예외가 발생하지 않는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('leaving immediately does not leave pending work', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
  // 함수이름: 동작 줄이기의 즉시 요약
  // 함수역할:
  // - 애니메이션 비활성화 상태에서 인트로 없이 고정 요약을 바로 렌더링하는지 확인한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  testWidgets('reduced motion shows the pinned summary immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(reduceMotion: true));
    expect(find.byKey(const Key('lookup-summary-intro')), findsNothing);
    expect(find.byKey(const Key('lookup-summary-pinned')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
