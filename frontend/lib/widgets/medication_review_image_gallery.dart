// 파일명: medication_review_image_gallery.dart
// 역할: 약품·처방전 검토 사진의 미리보기, 썸네일 탐색과 확대 모달을 공유한다.

import 'package:flutter/material.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: MedicationReviewPhoto
// 역할: 검토 사진 한 장의 표시 계약을 보관한다.
// 주요 책임: 이미지 생성과 모달 설명을 화면의 데이터 출처와 분리한다.
// 속성: title (String): 제목; imageBuilder (WidgetBuilder): 확대 제스처와 Hero 없는 이미지;
// aspectRatio (double): 양수인 사진 비율; footer (Widget?): 확대 사진 바로 아래 설명.
@immutable
class MedicationReviewPhoto {
  final String title;
  final WidgetBuilder imageBuilder;
  final double aspectRatio;
  final Widget? footer;

  // 함수이름: MedicationReviewPhoto
  // 함수역할: 여러 위치에서 새로 만들 수 있는 이미지와 선택적인 설명을 저장한다.
  // 매개변수: title/imageBuilder: 필수 제목·이미지; aspectRatio: 기본 4:3; footer: 모달 전용 설명.
  // 반환값: 사진 표시 계약. 잘못된 비율은 디버그 검증에서 거부한다.
  const MedicationReviewPhoto({
    required this.title,
    required this.imageBuilder,
    this.aspectRatio = 4 / 3,
    this.footer,
  }) : assert(aspectRatio > 0 && aspectRatio < double.infinity);
}

// 함수이름: showMedicationReviewPhotos
// 함수역할: 반투명 배경 위 중앙 모달로 사진을 열며 배경·닫기 버튼·뒤로가기로 종료한다.
// 매개변수: context: 화면 위치; photos: 사진 목록; initialIndex: 시작 위치; language: 표시 언어.
// 반환값: 모달 종료 시 완료되는 Future<void>. 빈 목록은 열지 않고 잘못된 인덱스는 범위 안으로 맞춘다.
Future<void> showMedicationReviewPhotos(
  BuildContext context, {
  required List<MedicationReviewPhoto> photos,
  int initialIndex = 0,
  String language = 'ko',
}) async {
  if (photos.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: .78),
    barrierLabel: isEnglishLanguage(language) ? 'Close image' : '사진 닫기',
    builder: (context) => _ReviewPhotosDialog(
      photos: List.unmodifiable(photos),
      initialIndex: initialIndex.clamp(0, photos.length - 1),
      language: language,
    ),
  );
}

// 클래스명: MedicationReviewImageGallery
// 역할: 고정 비율 사진 미리보기와 여러 장일 때만 썸네일·장수를 표시한다.
// 주요 책임: 좌우 넘김·썸네일 선택·확대 진입을 제공하며 첫 사진 비율로 미리보기 높이를 유지한다.
// 속성: photos (List<MedicationReviewPhoto>): 사진 목록; language (String): 접근성 문구 언어.
class MedicationReviewImageGallery extends StatefulWidget {
  final List<MedicationReviewPhoto> photos;
  final String language;

  // 함수이름: MedicationReviewImageGallery
  // 함수역할: 재사용할 검토 사진과 언어를 받는다.
  // 매개변수: key: 위젯 식별자; photos: 빈 목록도 가능한 사진 목록; language: 기본 한국어.
  // 반환값: 미리보기 갤러리.
  const MedicationReviewImageGallery({
    super.key,
    required this.photos,
    this.language = 'ko',
  });

  // 함수이름: createState
  // 함수역할: 선택 위치와 넘김 상태를 생성한다.
  // 매개변수: 없음. 반환값: 갤러리 상태.
  @override
  State<MedicationReviewImageGallery> createState() =>
      _MedicationReviewImageGalleryState();
}

// 클래스명: _MedicationReviewImageGalleryState
// 역할: 미리보기 사진 선택을 관리한다.
// 주요 책임: 넘김과 썸네일 위치를 동기화하고 목록 축소·종료 시 컨트롤러를 정리한다.
// 속성: _pages (PageController): 넘김 위치; _index (int): 현재 사진.
class _MedicationReviewImageGalleryState
    extends State<MedicationReviewImageGallery>
    with AutomaticKeepAliveClientMixin {
  final _pages = PageController();
  int _index = 0;

  // 함수이름: wantKeepAlive
  // 함수역할: 지연 생성 목록 밖으로 스크롤해도 선택한 사진을 유지한다.
  // 매개변수: 없음. 반환값: 상태 보존 여부.
  @override
  bool get wantKeepAlive => true;

  // 함수이름: didUpdateWidget
  // 함수역할: 사진 수가 줄어 선택 위치가 사라지면 첫 사진으로 돌아간다.
  // 매개변수: oldWidget: 이전 갤러리. 반환값: 없음.
  @override
  void didUpdateWidget(covariant MedicationReviewImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.photos.length) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(0);
      });
    }
  }

  // 함수이름: dispose
  // 함수역할: 사진 넘김 컨트롤러를 해제한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // 함수이름: _select
  // 함수역할: 썸네일로 선택한 사진으로 즉시 이동한다.
  // 매개변수: index (int): 유효한 사진 위치. 반환값: 없음.
  void _select(int index) => _pages.jumpToPage(index);

  // 함수이름: build
  // 함수역할: 사진 수와 무관한 고정 미리보기 높이와 필요한 탐색 요소만 구성한다.
  // 매개변수: context: 표시 위치. 반환값: 갤러리 또는 빈 영역.
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.photos.isEmpty) return const SizedBox.shrink();
    final isEnglish = isEnglishLanguage(widget.language);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            key: const Key('medication-review-gallery-preview'),
            aspectRatio: widget.photos.first.aspectRatio,
            child: ColoredBox(
              color: MedBuddyColors.surfaceSubtle,
              child: PageView.builder(
                key: const Key('medication-review-gallery-pages'),
                controller: _pages,
                itemCount: widget.photos.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => Semantics(
                  button: true,
                  label: isEnglish
                      ? 'Enlarge ${widget.photos[index].title}'
                      : '${widget.photos[index].title} 확대',
                  child: GestureDetector(
                    key: Key('medication-review-gallery-photo-$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showMedicationReviewPhotos(
                      context,
                      photos: widget.photos,
                      initialIndex: index,
                      language: widget.language,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _ReviewPhotoContent(photo: widget.photos[index]),
                        const Positioned(
                          right: 8,
                          bottom: 8,
                          child: IgnorePointer(
                            child: CircleAvatar(
                              radius: 17,
                              backgroundColor: Color(0xAD202322),
                              child: Icon(
                                Icons.open_in_full,
                                color: Colors.white,
                                size: 17,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.photos.length > 1)
          _ReviewPhotoThumbnails(
            photos: widget.photos,
            index: _index,
            isEnglish: isEnglish,
            onSelected: _select,
            prefix: 'medication-review-gallery',
          ),
      ],
    );
  }
}

// 클래스명: _ReviewPhotoContent
// 역할: 외부 이미지 위젯의 비율을 유지한다.
// 주요 책임: 서로 다른 사진 비율에도 이미지나 OCR 좌표를 늘이지 않는다.
// 속성: photo (MedicationReviewPhoto): 표시 계약.
class _ReviewPhotoContent extends StatelessWidget {
  final MedicationReviewPhoto photo;

  // 함수이름: _ReviewPhotoContent
  // 함수역할: 비율과 이미지 생성기를 받는다.
  // 매개변수: key: 사진 변경 식별자; photo: 표시 계약. 반환값: 사진 영역.
  const _ReviewPhotoContent({super.key, required this.photo});

  // 함수이름: build
  // 함수역할: 사진을 가용 영역 안에 비율 유지로 배치한다.
  // 매개변수: context: 표시 위치. 반환값: 비율 유지 이미지.
  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: photo.aspectRatio,
      child: HeroMode(
        enabled: false,
        child: Builder(builder: photo.imageBuilder),
      ),
    ),
  );
}

// 클래스명: _ReviewPhotosDialog
// 역할: 사진 확대 모달에 필요한 변경 불가능한 입력을 보관한다.
// 주요 책임: 열릴 당시 목록과 시작 위치를 고정한다.
// 속성: photos: 사진 목록; initialIndex: 시작 위치; language: 언어.
class _ReviewPhotosDialog extends StatefulWidget {
  final List<MedicationReviewPhoto> photos;
  final int initialIndex;
  final String language;

  // 함수이름: _ReviewPhotosDialog
  // 함수역할: 확대 표시할 목록과 시작 위치를 받는다.
  // 매개변수: photos: 비어 있지 않은 목록; initialIndex: 유효 위치; language: 언어.
  // 반환값: 확대 모달.
  const _ReviewPhotosDialog({
    required this.photos,
    required this.initialIndex,
    required this.language,
  });

  // 함수이름: createState
  // 함수역할: 사진 위치와 확대 제스처 상태를 생성한다.
  // 매개변수: 없음. 반환값: 모달 상태.
  @override
  State<_ReviewPhotosDialog> createState() => _ReviewPhotosDialogState();
}

// 클래스명: _ReviewPhotosDialogState
// 역할: 확대와 사진 넘김의 제스처 충돌을 방지한다.
// 주요 책임: 단일 InteractiveViewer가 제스처를 소유하고 원배율 한 손가락 가로 이동만 사진 넘김으로 처리한다.
// 속성: _transform: 확대 행렬; _index: 사진 위치; _zoomed: 확대 여부; _swipeStart/_swipeDelta/_canSwipe: 넘김 판정.
class _ReviewPhotosDialogState extends State<_ReviewPhotosDialog> {
  final _transform = TransformationController();
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  bool _canSwipe = false;
  Offset _swipeStart = Offset.zero;
  Offset _swipeDelta = Offset.zero;

  // 함수이름: initState
  // 함수역할: 확대 행렬 변경에 맞춰 이동 가능 상태를 동기화한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncZoom);
  }

  // 함수이름: _syncZoom
  // 함수역할: 확대된 동안에만 이미지 이동을 활성화한다.
  // 매개변수: 없음. 반환값: 없음.
  void _syncZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  // 함수이름: dispose
  // 함수역할: 확대 감시와 컨트롤러를 해제한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _transform.removeListener(_syncZoom);
    _transform.dispose();
    super.dispose();
  }

  // 함수이름: _select
  // 함수역할: 사진을 바꿀 때 배율·이동을 초기화하고 마지막 사진 밖으로는 이동하지 않는다.
  // 매개변수: index: 요청 위치. 반환값: 없음.
  void _select(int index) {
    if (index < 0 || index >= widget.photos.length || index == _index) return;
    _transform.value = Matrix4.identity();
    setState(() => _index = index);
  }

  // 함수이름: _startInteraction
  // 함수역할: 원배율에서 시작한 한 손가락 제스처만 넘김 후보로 기록한다.
  // 매개변수: details: 시작 위치·손가락 수. 반환값: 없음.
  void _startInteraction(ScaleStartDetails details) {
    _canSwipe = !_zoomed && details.pointerCount == 1;
    _swipeStart = details.localFocalPoint;
    _swipeDelta = Offset.zero;
  }

  // 함수이름: _updateInteraction
  // 함수역할: 확대·두 손가락 동작을 제외하고 가로·세로 이동 거리를 기록한다.
  // 매개변수: details: 현재 배율·위치·손가락 수. 반환값: 없음.
  void _updateInteraction(ScaleUpdateDetails details) {
    _canSwipe = _canSwipe && details.pointerCount == 1 && !_zoomed;
    _swipeDelta = details.localFocalPoint - _swipeStart;
  }

  // 함수이름: _endInteraction
  // 함수역할: 충분히 긴 원배율 가로 제스처만 앞뒤 사진 선택으로 연결한다.
  // 매개변수: details: 종료 속도. 반환값: 없음.
  void _endInteraction(ScaleEndDetails details) {
    if (!_canSwipe || _zoomed) return;
    final dx = _swipeDelta.dx;
    if (dx.abs() >= 40 && dx.abs() > _swipeDelta.dy.abs() * 1.4) {
      _select(_index + (dx < 0 ? 1 : -1));
    }
    _canSwipe = false;
  }

  // 함수이름: build
  // 함수역할: 제목 바로 아래 사진을 놓고 설명과 썸네일의 높이를 제한해 작은 화면에서도 닫기를 보장한다.
  // 매개변수: context: 화면 크기·언어·탐색 위치. 반환값: 중앙 확대 모달.
  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final isEnglish = isEnglishLanguage(widget.language);
    return Dialog(
      key: const Key('medication-review-photo-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: const Color(0xFF202322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            key: const Key('medication-review-viewer-content'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: const Key('medication-review-viewer-heading'),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .18,
                        ),
                        child: SingleChildScrollView(
                          child: Semantics(
                            header: true,
                            child: KeepWordsText(
                              photo.title,
                              key: const Key('medication-review-viewer-title'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('medication-review-viewer-close'),
                      tooltip: isEnglish ? 'Close enlarged image' : '확대 사진 닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: AspectRatio(
                  aspectRatio: photo.aspectRatio,
                  child: ClipRect(
                    child: InteractiveViewer(
                      key: const Key('medication-review-viewer-photo'),
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 5,
                      panEnabled: _zoomed,
                      onInteractionStart: _startInteraction,
                      onInteractionUpdate: _updateInteraction,
                      onInteractionEnd: _endInteraction,
                      child: _ReviewPhotoContent(
                        key: ValueKey(_index),
                        photo: photo,
                      ),
                    ),
                  ),
                ),
              ),
              if (photo.footer != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .25,
                  ),
                  child: SingleChildScrollView(
                    key: const Key('medication-review-viewer-footer'),
                    padding: const EdgeInsets.all(12),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      child: photo.footer!,
                    ),
                  ),
                ),
              if (widget.photos.length > 1)
                _ReviewPhotoThumbnails(
                  photos: widget.photos,
                  index: _index,
                  isEnglish: isEnglish,
                  onSelected: _select,
                  prefix: 'medication-review-viewer',
                  dark: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _ReviewPhotoThumbnails
// 역할: 여러 사진의 선택 상태와 장수를 표시한다.
// 주요 책임: 가로 스크롤 썸네일을 누를 수 있게 하고 현재 선택에 접근성 정보를 부여한다.
// 속성: photos/index: 목록·위치; isEnglish/dark: 언어·배경; onSelected: 선택 동작; prefix: 키 구분.
class _ReviewPhotoThumbnails extends StatefulWidget {
  final List<MedicationReviewPhoto> photos;
  final int index;
  final bool isEnglish;
  final ValueChanged<int> onSelected;
  final String prefix;
  final bool dark;

  // 함수이름: _ReviewPhotoThumbnails
  // 함수역할: 썸네일 선택과 표시 설정을 받는다.
  // 매개변수: photos/index/isEnglish/onSelected/prefix: 목록·선택·언어·콜백·식별자; dark: 어두운 배경 여부.
  // 반환값: 썸네일 탐색 줄.
  const _ReviewPhotoThumbnails({
    required this.photos,
    required this.index,
    required this.isEnglish,
    required this.onSelected,
    required this.prefix,
    this.dark = false,
  });

  // 함수이름: createState
  // 함수역할: 현재 썸네일을 보이게 유지할 스크롤 상태를 생성한다.
  // 매개변수: 없음. 반환값: 썸네일 상태.
  @override
  State<_ReviewPhotoThumbnails> createState() => _ReviewPhotoThumbnailsState();
}

// 클래스명: _ReviewPhotoThumbnailsState
// 역할: 사진 선택에 맞춰 썸네일 스크롤 위치를 유지한다.
// 주요 책임: 화면 밖의 선택된 썸네일을 다시 표시하고 소유한 컨트롤러를 해제한다.
// 속성: _scroll (ScrollController): 가로 썸네일 위치.
class _ReviewPhotoThumbnailsState extends State<_ReviewPhotoThumbnails> {
  final _scroll = ScrollController();

  // 함수이름: initState
  // 함수역할: 첫 레이아웃 후 시작 사진의 썸네일을 표시한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  // 함수이름: didUpdateWidget
  // 함수역할: 사진 선택이 바뀌면 해당 썸네일을 표시한다.
  // 매개변수: oldWidget: 이전 선택 정보. 반환값: 없음.
  @override
  void didUpdateWidget(covariant _ReviewPhotoThumbnails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _revealSelection();
  }

  // 함수이름: _revealSelection
  // 함수역할: 선택한 썸네일이 가시 범위를 벗어난 경우에만 가로 위치를 맞춘다.
  // 매개변수: 없음. 반환값: 없음.
  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final left = widget.index * 72.0;
      final right = left + 64;
      final visibleWidth = _scroll.position.viewportDimension;
      if (left < _scroll.offset || right > _scroll.offset + visibleWidth) {
        _scroll.jumpTo(
          (left - (visibleWidth - 64) / 2).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  // 함수이름: dispose
  // 함수역할: 썸네일 위치 컨트롤러를 해제한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 일정 높이의 썸네일 목록과 줄바꿈 가능한 장수를 배치한다.
  // 매개변수: context: 표시 위치. 반환값: 썸네일과 선택 장수.
  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final index = widget.index;
    final isEnglish = widget.isEnglish;
    final prefix = widget.prefix;
    return SizedBox(
      key: Key('$prefix-thumbnails'),
      height: 80,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: photos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, position) => Semantics(
                button: true,
                selected: position == index,
                label: isEnglish
                    ? 'Photo ${position + 1}: ${photos[position].title}'
                    : '사진 ${position + 1}: ${photos[position].title}',
                child: Tooltip(
                  message: photos[position].title,
                  child: InkWell(
                    key: Key('$prefix-thumbnail-$position'),
                    onTap: () => widget.onSelected(position),
                    child: Container(
                      width: 64,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: MedBuddyColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: position == index
                              ? MedBuddyColors.primary
                              : MedBuddyColors.outline,
                          width: position == index ? 3 : 1,
                        ),
                      ),
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: _ReviewPhotoContent(photo: photos[position]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Semantics(
              liveRegion: true,
              label: isEnglish
                  ? 'Photo ${index + 1} of ${photos.length}'
                  : '전체 ${photos.length}장 중 ${index + 1}번째 사진',
              child: SingleChildScrollView(
                child: Text(
                  '${index + 1} / ${photos.length}',
                  key: Key('$prefix-count'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0,
                    color: widget.dark ? Colors.white : MedBuddyColors.textBody,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
