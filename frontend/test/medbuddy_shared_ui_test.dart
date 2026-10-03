import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_photo_source_sheet.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';

// 공통 제목·사진 선택의 접근성과 기존 처방전 출처 반환 계약을 검증한다.
void main() {
  // 좁은 화면에서도 큰 제목, 뒤로가기, 두 명령을 모두 배치할 수 있는지 확인한다.
  testWidgets('공통 제목은 큰 글씨에서도 잘리지 않고 뒤로가기를 실행한다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MedBuddyTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: MedBuddyPageHeader(
              title: '저장된 복약 정보',
              prominent: true,
              backTooltip: '뒤로가기',
              onBackRequested: () => backs++,
              actions: [
                IconButton(
                  tooltip: '정렬',
                  onPressed: () {},
                  icon: const Icon(Icons.sort),
                ),
                IconButton(
                  tooltip: '선택',
                  onPressed: () {},
                  icon: const Icon(Icons.checklist),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text('저장된 복약 정보'));
    expect(title.style!.fontSize, 21);
    expect(title.style!.color, Colors.white);
    expect(title.style!.fontWeight, FontWeight.w800);
    await tester.tap(find.byTooltip('뒤로가기'));
    expect(backs, 1);
  });

  // 함수역할: 일정 화면의 그라데이션·하단 라운드와 상태 표시줄 여백을 함께 검증한다.
  // 매개변수: tester는 화면 도구. 반환값: 검증 완료.
  testWidgets('공통 헤더는 일정 화면의 색상과 안전 영역을 유지한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MedBuddyTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: Scaffold(
            body: Column(
              children: [
                MedBuddyPageHeader(
                  title: '내 정보',
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MedBuddyPageHeader),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect((decoration.gradient! as LinearGradient).colors, [
      const Color(0xFF249B62),
      MedBuddyColors.topBar,
    ]);
    expect(
      decoration.borderRadius,
      const BorderRadius.vertical(bottom: Radius.circular(28)),
    );
    final title = tester.getRect(find.text('내 정보'));
    expect(title.left, 32);
    expect(title.top, greaterThanOrEqualTo(36));
    final iconContext = tester.element(find.byIcon(Icons.refresh));
    expect(
      IconButtonTheme.of(iconContext).style!.foregroundColor!.resolve({}),
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });

  // 텍스트·주 동작 버튼에 앱의 동일한 기본 규칙이 적용되는지 검사한다.
  test('기본 테마는 같은 제목과 명령 버튼 색상을 제공한다', () {
    final theme = MedBuddyTheme.light();
    expect(theme.colorScheme.primary, MedBuddyColors.primary);
    expect(theme.textTheme.titleLarge!.fontSize, 22);
    expect(theme.textTheme.labelLarge!.letterSpacing, 0);
    expect(
      theme.elevatedButtonTheme.style!.backgroundColor!.resolve({}),
      MedBuddyColors.primary,
    );
    expect(theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height, 48);
  });

  for (final width in [320.0, 411.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      // 함수역할: 버튼 수·글자 종류·확대 배율이 달라도 제목 시작점과 기준선이 동일한지 검사한다.
      // 매개변수: tester는 위젯 도구. 반환값: 제목·부제의 비겹침과 동작 검증 완료.
      testWidgets('주요 제목 높이는 버튼 유무와 무관하다 $width $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        double? baseline;
        for (final title in [
          '오늘의 복약 일정',
          '저장된 복약 정보',
          '채팅',
          '내 정보',
          '환경설정',
          'Chat',
        ]) {
          final hasActions = title == '저장된 복약 정보' || title == '채팅';
          final subtitle = switch (title) {
            '저장된 복약 정보' => '약과 복용 기록을 확인합니다.',
            '채팅' => '가족과 메시지를 주고받습니다.',
            _ => '복약 기록',
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: MedBuddyTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  padding: const EdgeInsets.only(top: 24),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Column(
                    children: [
                      MedBuddyPageHeader(
                        title: title,
                        subtitle: subtitle,
                        onBackRequested: title == '환경설정' ? () {} : null,
                        actions: hasActions
                            ? [
                                IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.sort),
                                ),
                                IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.checklist),
                                ),
                              ]
                            : [],
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
            ),
          );
          final titleRect = tester.getRect(find.text(title));
          expect(titleRect.top, 36);
          final titleWidget = tester.widget<Text>(find.text(title));
          final painter = TextPainter(
            text: TextSpan(text: title, style: titleWidget.style),
            strutStyle: titleWidget.strutStyle,
            textScaler: TextScaler.linear(scale),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: titleRect.width);
          final actualBaseline = painter.computeLineMetrics().first.baseline;
          painter.dispose();
          baseline ??= actualBaseline;
          expect(actualBaseline, closeTo(baseline, 0.01));
          final subtitleRect = tester.getRect(find.text(subtitle));
          final subtitleStyle = tester.widget<Text>(find.text(subtitle)).style!;
          expect(subtitleStyle.fontSize, 13);
          expect(subtitleStyle.height, 1.3);
          expect(subtitleStyle.letterSpacing, 0);
          expect(subtitleRect.top, closeTo(titleRect.bottom + 4, 0.01));
          expect(subtitleRect.left, titleRect.left);
          expect(
            subtitleRect.bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(MedBuddyPageHeader)).bottom,
            ),
          );
          var contentBottom = titleRect.top + 48;
          if (subtitleRect.bottom > contentBottom) {
            contentBottom = subtitleRect.bottom;
          }
          for (final icon in [Icons.sort, Icons.checklist, Icons.arrow_back]) {
            if (icon == Icons.arrow_back && title != '환경설정') continue;
            if (icon != Icons.arrow_back && !hasActions) continue;
            final action = find.widgetWithIcon(IconButton, icon);
            final actionRect = tester.getRect(action);
            if (actionRect.bottom > contentBottom) {
              contentBottom = actionRect.bottom;
            }
            expect(actionRect.height, greaterThanOrEqualTo(48));
            expect(actionRect.overlaps(subtitleRect), isFalse);
          }
          expect(
            tester.getRect(find.byType(MedBuddyPageHeader)).bottom -
                contentBottom,
            closeTo(10, 0.01),
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final language in ['ko', 'en']) {
    for (final source in [ImageSource.camera, ImageSource.gallery, null]) {
      // 두 언어의 좁은 가로 화면에서 선택·취소가 정확한 출처를 반환하는지 검사한다.
      testWidgets('사진 출처 선택과 취소 $language $source', (tester) async {
        tester.view.physicalSize = const Size(320, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ImageSource? result;
        var completed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: MedBuddyTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    result = await showMedicationPhotoSourceOptions(
                      context: context,
                      language: language,
                    );
                    completed = true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (source == null) {
          await tester.binding.handlePopRoute();
        } else {
          final label = source == ImageSource.camera
              ? (language == 'en' ? 'Take Photo' : '카메라로 촬영')
              : (language == 'en' ? 'Choose From Gallery' : '갤러리에서 선택');
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(result, source);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 처방전 진입점이 공통 사진 메뉴의 결과를 기존 열거형으로 변환하는지 검증한다.
  testWidgets('처방전 출처 선택의 반환 형식은 유지된다', (tester) async {
    PrescriptionImageSource? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await showPrescriptionImageSourceOptions(
                  context: context,
                  userSetting: const UserSetting(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(result, PrescriptionImageSource.gallery);
  });
}
