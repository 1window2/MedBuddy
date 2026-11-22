// 파일명: prescription_review_header_test.dart
// 역할: OCR 검토 헤더의 공통 글꼴·제목·약 추가 명령 정렬과 좁은 화면 접근성을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

// 함수이름: _screen
// 함수역할: 제목과 약 추가 명령을 가진 단일 OCR 검토 화면을 구성한다.
// 매개변수: scale: 글씨 배율; language: 표시 언어; canAdd: 추가 명령 여부; theme: 공통 테마.
// 반환값: 설정된 테스트 앱.
Widget _screen({
  double scale = 1,
  String language = 'ko',
  bool canAdd = true,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? MedBuddyTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: PrescriptionAnalysisPreviewUI(
    userSetting: UserSetting(language: language),
    medicationScheduleList: [
      MedicationSchedule(
        medicationName: '시험약',
        dosage: '1정',
        intakeTime: '1회',
        medicationTime: 3,
        prescriptionDate: DateTime(2026, 11, 15),
        scheduleSlotKeys: const ['morning'],
      ),
    ],
    onBackRequested: () {},
    onAnalysisRequested: () {},
    onMedicationScheduleChanged: (_, _) {},
    onMedicationScheduleAdded: canAdd ? (_) {} : null,
  ),
);

// 함수이름: main
// 함수역할: 헤더 정렬과 큰 글씨 줄바꿈·추가 편집 진입 사례를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  testWidgets('약 추가 버튼은 앱 공통 버튼의 글자 크기와 굵기를 유지한다', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    final label = tester.widget<RichText>(
      find.descendant(
        of: find.descendant(
          of: find.byKey(const Key('ocr-add-medication-button')),
          matching: find.byType(KeepWordsText),
        ),
        matching: find.byType(RichText),
      ),
    );
    final expected = MedBuddyTheme.light().outlinedButtonTheme.style!.textStyle!
        .resolve({})!;
    expect(label.text.style!.fontSize, expected.fontSize);
    expect(label.text.style!.fontWeight, expected.fontWeight);
    expect(label.text.style!.letterSpacing, expected.letterSpacing);
  });

  testWidgets('약 추가 버튼은 공통 테마의 글꼴과 대체 글꼴을 그대로 상속한다', (tester) async {
    final theme = MedBuddyTheme.light();
    final buttonStyle = theme.outlinedButtonTheme.style!;
    final typography = buttonStyle.textStyle!
        .resolve({})!
        .copyWith(
          fontFamily: 'MedBuddyTypographyTest',
          fontFamilyFallback: const ['MedBuddyFallback'],
        );
    await tester.pumpWidget(
      _screen(
        theme: theme.copyWith(
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: buttonStyle.copyWith(
              textStyle: WidgetStatePropertyAll(typography),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = tester.widget<RichText>(
      find.descendant(
        of: find.descendant(
          of: find.byKey(const Key('ocr-add-medication-button')),
          matching: find.byType(KeepWordsText),
        ),
        matching: find.byType(RichText),
      ),
    );
    expect(label.text.style!.fontFamily, typography.fontFamily);
    expect(label.text.style!.fontFamilyFallback, typography.fontFamilyFallback);
    expect(label.text.style!.fontWeight, typography.fontWeight);
  });

  // 함수이름: 헤더 양끝 정렬 검증
  // 함수역할: 일반 휴대폰과 넓은 화면에서 제목·버튼이 한 줄의 본문 양끝에 있는지 확인한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  for (final width in [390.0, 1000.0]) {
    testWidgets('제목과 약 추가가 본문 경계의 같은 헤더에 있다 $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_screen());
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('prescription-review-header'));
      final title = find.byKey(const Key('prescription-review-title'));
      final button = find.byKey(const Key('ocr-add-medication-button'));
      final list = find.byKey(const Key('ocr-medication-list'));
      expect(find.descendant(of: header, matching: button), findsOneWidget);
      expect(button, findsOneWidget);
      final titleRect = tester.getRect(title);
      final buttonRect = tester.getRect(button);
      final bodyRect = tester.getRect(list);
      expect(titleRect.left, closeTo(bodyRect.left, .1));
      expect(buttonRect.right, closeTo(bodyRect.right, .1));
      expect(titleRect.center.dy, closeTo(buttonRect.center.dy, 1));
      expect(titleRect.right, lessThan(buttonRect.left));
      expect(buttonRect.bottom, lessThan(bodyRect.top));
      expect(tester.widget<KeepWordsText>(title).textAlign, TextAlign.start);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-edit-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    for (final size in [const Size(320, 568), const Size(640, 360)]) {
      // 함수이름: 큰 글씨 헤더 검증
      // 함수역할: 제한된 화면에서 헤더 안 줄바꿈과 추가 명령의 스크롤 접근성을 확인한다.
      // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
      testWidgets('큰 글씨 헤더에서 추가 명령이 넘치지 않는다 $language $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_screen(scale: 2, language: language));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.byKey(const Key('ocr-add-medication-button'));
        final header = find.byKey(const Key('prescription-review-header'));
        expect(find.descendant(of: header, matching: button), findsOneWidget);
        final buttonRect = tester.getRect(button);
        expect(buttonRect.left, greaterThanOrEqualTo(16));
        expect(buttonRect.right, lessThanOrEqualTo(size.width - 16));
        // 헤더보다 높은 버튼도 중앙을 스크롤 영역 안에 드러내어 누른다.
        await Scrollable.ensureVisible(tester.element(button), alignment: .5);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ocr-edit-name')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: 추가 명령 숨김 검증
  // 함수역할: 추가 콜백이 없는 화면에는 새 명령을 만들지 않는다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('추가 콜백이 없으면 제목만 표시한다', (tester) async {
    await tester.pumpWidget(_screen(canAdd: false));
    expect(find.byKey(const Key('prescription-review-title')), findsOneWidget);
    expect(find.byKey(const Key('ocr-add-medication-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
