// 파일명: medication_review_image_gallery_test.dart
// 역할: 검토 갤러리의 넘김·썸네일·확대·모달 종료와 선택 상태 보존을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medication_review_image_gallery.dart';

// 함수이름: _photos
// 함수역할: 실제 네트워크 없이 유한한 이미지 제약과 사진 구분을 확인할 목록을 만든다.
// 매개변수: count: 사진 수; footer: 선택 설명; longTitle: 긴 제목 여부.
// 반환값: 서로 다른 색으로 식별하는 사진 목록.
List<MedicationReviewPhoto> _photos({
  int count = 3,
  Widget? footer,
  bool longTitle = false,
}) => List.generate(
  count,
  (index) => MedicationReviewPhoto(
    title: longTitle
        ? 'Photo ${index + 1} with a long medication name'
        : 'Photo ${index + 1}',
    aspectRatio: index == 1 ? 1 : 4 / 3,
    footer: footer,
    imageBuilder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        expect(constraints.hasBoundedWidth, isTrue);
        expect(constraints.hasBoundedHeight, isTrue);
        expect(constraints.maxWidth, greaterThan(0));
        expect(constraints.maxHeight, greaterThan(0));
        return ColoredBox(
          key: ValueKey('test-photo-$index'),
          color: [Colors.red, Colors.green, Colors.blue][index % 3],
        );
      },
    ),
  ),
);

// 함수이름: _screen
// 함수역할: 갤러리를 스크롤 가능한 검토 화면처럼 배치한다.
// 매개변수: photos: 사진 목록; scale: 글씨 배율.
// 반환값: 갤러리 테스트 앱.
Widget _screen(List<MedicationReviewPhoto> photos, {double scale = 1}) =>
    MaterialApp(
      theme: MedBuddyTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MedicationReviewImageGallery(photos: photos, language: 'en'),
        ),
      ),
    );

// 함수이름: _viewport
// 함수역할: 테스트 화면 크기를 지정하고 종료 때 원복한다.
// 매개변수: tester: 위젯 제어기; size: 화면 크기. 반환값: 없음.
void _viewport(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 함수이름: _viewer
// 함수역할: 현재 확대 사진 위젯의 배율 제어기를 검사하기 위해 반환한다.
// 매개변수: tester: 위젯 제어기. 반환값: 확대 위젯.
InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(
      find.byKey(const Key('medication-review-viewer-photo')),
    );

// 함수이름: main
// 함수역할: 갤러리 탐색·확대와 상태 보존 회귀 사례를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 단일 사진과 모달 검증
  // 함수역할: 사진 한 장에서는 탐색 요소를 숨기고 사진 클릭·닫기·배경 클릭을 구분한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('single photo hides navigation and opens a dismissible modal', (
    tester,
  ) async {
    _viewport(tester);
    await tester.pumpWidget(_screen(_photos(count: 1)));
    expect(
      find.byKey(const Key('medication-review-gallery-thumbnails')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('medication-review-gallery-count')),
      findsNothing,
    );
    final photo = find.byKey(const Key('medication-review-gallery-photo-0'));
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('medication-review-photo-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('medication-review-viewer-count')),
      findsNothing,
    );
    expect(_viewer(tester).minScale, 1);
    expect(_viewer(tester).maxScale, 5);
    await tester.tap(find.byKey(const Key('medication-review-viewer-photo')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('medication-review-photo-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('medication-review-viewer-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('medication-review-photo-dialog')),
      findsNothing,
    );
    await tester.tap(photo);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('medication-review-photo-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 넘김과 썸네일 검증
  // 함수역할: 미리보기 높이를 유지하며 넘김·썸네일·확대 시작 위치·모달 넘김을 동기화한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'paging and thumbnails select photos without resizing the preview',
    (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_screen(_photos()));
      final preview = find.byKey(
        const Key('medication-review-gallery-preview'),
      );
      final size = tester.getSize(preview);
      expect(size.width / size.height, closeTo(4 / 3, .01));
      await tester.drag(preview, const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(tester.getSize(preview), size);
      await tester.tap(
        find.byKey(const Key('medication-review-gallery-thumbnail-2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('medication-review-gallery-photo-2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photo 3'), findsOneWidget);
      final viewer = find.byKey(const Key('medication-review-viewer-photo'));
      await tester.drag(viewer, const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.text('Photo 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('medication-review-viewer-thumbnail-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photo 1'), findsOneWidget);
      await tester.drag(viewer, const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.text('Photo 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 함수이름: 확대와 사진 넘김 분리 검증
  // 함수역할: 두 손가락 확대 뒤 한 손가락 이동은 사진을 바꾸지 않으며 썸네일 선택은 배율을 초기화한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('pinch zoom pans without paging and a new photo resets zoom', (
    tester,
  ) async {
    _viewport(tester);
    await tester.pumpWidget(_screen(_photos()));
    await tester.tap(
      find.byKey(const Key('medication-review-gallery-photo-0')),
    );
    await tester.pumpAndSettle();
    final viewer = find.byKey(const Key('medication-review-viewer-photo'));
    final center = tester.getCenter(viewer);
    final first = await tester.startGesture(
      center - const Offset(25, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(25, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(75, 0));
    await second.moveTo(center + const Offset(75, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(95, 0));
    await second.moveTo(center + const Offset(95, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(
      _viewer(tester).transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(_viewer(tester).panEnabled, isTrue);
    final before = _viewer(tester).transformationController!.value.clone();
    await tester.drag(viewer, const Offset(-90, 10));
    await tester.pumpAndSettle();
    expect(find.text('Photo 1'), findsOneWidget);
    expect(_viewer(tester).transformationController!.value, isNot(before));
    await tester.tap(
      find.byKey(const Key('medication-review-viewer-thumbnail-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photo 2'), findsOneWidget);
    expect(_viewer(tester).transformationController!.value, Matrix4.identity());
    expect(_viewer(tester).panEnabled, isFalse);
    await tester.drag(viewer, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Photo 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(640, 360)]) {
    // 함수이름: 확대 모달 접근성 검증
    // 함수역할: 큰 글씨·긴 설명에서도 사진이 제목에 붙고 설명·썸네일·닫기가 겹치지 않는다.
    // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
    testWidgets('modal fits bounded image builders and large text at $size', (
      tester,
    ) async {
      _viewport(tester, size);
      await tester.pumpWidget(
        _screen(
          _photos(
            footer: Text(List.filled(20, 'Privacy explanation').join(' ')),
            longTitle: true,
          ),
          scale: 2,
        ),
      );
      await tester.tap(
        find.byKey(const Key('medication-review-gallery-photo-0')),
      );
      await tester.pumpAndSettle();
      final heading = tester.getRect(
        find.byKey(const Key('medication-review-viewer-heading')),
      );
      final photo = tester.getRect(
        find.byKey(const Key('medication-review-viewer-photo')),
      );
      final footer = tester.getRect(
        find.byKey(const Key('medication-review-viewer-footer')),
      );
      final thumbnails = tester.getRect(
        find.byKey(const Key('medication-review-viewer-thumbnails')),
      );
      expect(photo.top, closeTo(heading.bottom, .1));
      expect(photo.height, greaterThan(0));
      expect(footer.top, greaterThanOrEqualTo(photo.bottom));
      expect(thumbnails.top, greaterThanOrEqualTo(footer.bottom));
      expect(thumbnails.bottom, lessThan(size.height));
      expect(
        find.byKey(const Key('medication-review-viewer-close')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 선택 상태 보존 검증
  // 함수역할: 지연 목록 밖으로 스크롤하거나 편집 경로를 다녀와도 선택 사진을 유지한다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets('selected preview survives lazy scrolling and an edit route', (
    tester,
  ) async {
    _viewport(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: ListView.builder(
            controller: scroll,
            cacheExtent: 0,
            itemCount: 30,
            itemBuilder: (context, index) => index == 0
                ? MedicationReviewImageGallery(
                    photos: _photos(),
                    language: 'en',
                  )
                : const SizedBox(height: 200),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('medication-review-gallery-thumbnail-2')),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(3000);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => const Scaffold(body: Text('Edit medication')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 빈 목록과 변경 목록 검증
  // 함수역할: 빈 목록은 화면을 열지 않고 선택 사진이 사라지면 처음으로 안전하게 돌아간다.
  // 매개변수: tester: 위젯 제어기. 반환값: 비동기 검증 완료.
  testWidgets(
    'empty photos are inert and shrinking the list resets selection',
    (tester) async {
      _viewport(tester);
      await tester.pumpWidget(_screen(_photos()));
      await tester.tap(
        find.byKey(const Key('medication-review-gallery-thumbnail-2')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(_screen(_photos(count: 1)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('medication-review-gallery-photo-0')),
        findsOneWidget,
      );
      await tester.pumpWidget(_screen([]));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('medication-review-gallery-preview')),
        findsNothing,
      );
      await showMedicationReviewPhotos(
        tester.element(find.byType(Scaffold)),
        photos: [],
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('medication-review-photo-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
