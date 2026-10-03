// 파일명: pharmacy_list_panel.dart
// 역할: 목록 상단을 아래로 당겨 지도에 돌아가는 패널을 제공한다.
part of 'check_nearby_pharmacy_ui_boundary.dart';

// 클래스명: _PharmacyListPanel
// 역할: 상단 드래그 영역과 독립적으로 스크롤되는 약국 목록을 배치한다.
// 속성: header: 조회 상태, child: 목록, onDismissed: 지도 복귀, showMapLabel: 접근성 안내.
class _PharmacyListPanel extends StatefulWidget {
  final Widget header;
  final Widget child;
  final VoidCallback onDismissed;
  final String showMapLabel;

  // 함수이름: _PharmacyListPanel
  // 함수역할: 내용과 지도 복귀 콜백을 보관한다. 반환값: 드래그 가능한 목록 패널.
  // 매개변수: header: 조회 상태, child: 목록, onDismissed: 복귀 콜백, showMapLabel: 안내.
  const _PharmacyListPanel({
    required this.header,
    required this.child,
    required this.onDismissed,
    required this.showMapLabel,
  });

  // 함수이름: createState
  // 함수역할: 드래그·복귀 애니메이션 상태를 생성한다. 반환값: 패널 상태.
  // 매개변수: 없음.
  @override
  State<_PharmacyListPanel> createState() => _PharmacyListPanelState();
}

// 클래스명: _PharmacyListPanelState
// 역할: 상단 제스처만 처리해 목록 스크롤과 지도 복귀를 구분한다.
// 속성: _offset: 내려온 거리, _height: 패널 높이, _closing: 중복 닫기 방지.
// - _dragCancelled: 운영체제가 취소한 제스처를 닫기로 처리하지 않는 표시.
class _PharmacyListPanelState extends State<_PharmacyListPanel>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  double _height = 0;
  bool _closing = false;
  bool _dragCancelled = false;

  // 함수이름: dispose
  // 함수역할: 화면 이탈 시 애니메이션을 정리한다. 반환값: 없음.
  // 매개변수: 없음.
  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  // 함수이름: _dismiss
  // 함수역할: 패널을 화면 아래로 이동시킨 뒤 지도로 돌아간다.
  // 매개변수: 없음. 반환값: 애니메이션 완료 또는 취소.
  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    try {
      await _offset
          .animateTo(
            _height,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (mounted) widget.onDismissed();
    } on TickerCanceled {
      // 다른 화면 이동으로 이미 제거된 패널은 복귀 콜백을 실행하지 않는다.
    }
  }

  // 함수이름: _returnToTop
  // 함수역할: 짧은 드래그나 취소 후 원래 위치로 돌아간다. 반환값: 없음.
  // 매개변수: 없음.
  void _returnToTop() {
    if (_closing) return;
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  // 함수이름: _onDragStart
  // 함수역할: 복귀 애니메이션 중 다시 잡으면 현재 위치부터 이동한다.
  // 매개변수: details: 시작 제스처. 반환값: 없음.
  void _onDragStart(DragStartDetails details) {
    _dragCancelled = false;
    if (!_closing) _offset.stop();
  }

  // 함수이름: _onDragUpdate
  // 함수역할: 상단을 아래로 당긴 거리만 반영한다.
  // 매개변수: details: 손가락 이동량. 반환값: 없음.
  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    _offset.value = (_offset.value + details.delta.dy).clamp(0, _height);
  }

  // 함수이름: _onDragEnd
  // 함수역할: 충분한 거리 또는 아래 방향 속도일 때 닫고 나머지는 복원한다.
  // 매개변수: details: 놓는 속도. 반환값: 없음.
  void _onDragEnd(DragEndDetails details) {
    if (_dragCancelled) {
      _returnToTop();
      return;
    }
    final threshold = (_height * .2).clamp(48.0, 96.0);
    if (_offset.value >= threshold ||
        (_offset.value >= 12 && (details.primaryVelocity ?? 0) >= 700)) {
      unawaited(_dismiss());
    } else {
      _returnToTop();
    }
  }

  // 함수이름: build
  // 함수역할: 손잡이·조회 상태만 드래그 가능하게 하고 목록과 버튼 의미를 유지한다.
  // 매개변수: context: 화면 환경. 반환값: 지도 위 목록 패널.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // 함수이름: build.LayoutBuilder 콜백
      // 함수역할: 화면 높이에 맞춰 패널의 이동 한계를 설정하고 내용을 배치한다.
      // 매개변수: context: 화면 환경, constraints: 가용 크기. 반환값: 이동 패널.
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _offset,
          // 함수이름: build.AnimatedBuilder 콜백
          // 함수역할: 목록 내용을 재생성하지 않고 수직 위치만 갱신한다.
          // 매개변수: context: 화면 환경, child: 패널 내용. 반환값: 이동한 내용.
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _offset.value),
            child: child,
          ),
          child: Material(
            key: const Key('pharmacy-list-panel'),
            elevation: 8,
            color: MedBuddyColors.pageBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Listener(
                  // 함수이름: build.onPointerCancel 콜백
                  // 함수역할: 취소된 제스처를 표시하고 패널을 원위치로 돌린다.
                  // 매개변수: _: 미사용 포인터 이벤트. 반환값: 없음.
                  onPointerCancel: (_) {
                    _dragCancelled = true;
                    _returnToTop();
                  },
                  child: GestureDetector(
                    key: const Key('pharmacy-list-drag-area'),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    onVerticalDragCancel: _returnToTop,
                    child: Column(
                      children: [
                        Semantics(
                          button: true,
                          label: widget.showMapLabel,
                          child: Tooltip(
                            message: widget.showMapLabel,
                            excludeFromSemantics: true,
                            child: InkWell(
                              key: const Key('pharmacy-list-handle'),
                              onTap: _dismiss,
                              child: SizedBox(
                                height: 48,
                                width: double.infinity,
                                child: Center(
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: MedBuddyColors.textSubtle,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        widget.header,
                      ],
                    ),
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        );
      },
    );
  }
}
