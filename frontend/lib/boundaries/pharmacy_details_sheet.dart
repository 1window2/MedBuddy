// 파일명: pharmacy_details_sheet.dart
// 역할: 내용 높이에 맞춰 펼치거나 접는 약국 정보창을 제공한다.
part of 'check_nearby_pharmacy_ui_boundary.dart';

// 클래스명: _PharmacyDetailsSheet
// 역할: 지도 위 시설 상세 내용과 높이 통지 구성을 보관한다.
// 주요 책임: 펼침 상태별 내용을 제공하고 높이 변경으로 지도 여백을 조정하게 한다.
// 속성: isEnglish/hospitals (bool): 표시 모드; onExtentChanged (ValueChanged<double>): 높이; contentBuilder (Widget Function(BuildContext,bool)): 내용.
class _PharmacyDetailsSheet extends StatefulWidget {
  static const initialExtent = .65;
  final bool isEnglish;
  final bool hospitals;
  final ValueChanged<double> onExtentChanged;
  final Widget Function(BuildContext, bool) contentBuilder;

  // 함수이름: _PharmacyDetailsSheet
  // 함수역할: 병원·약국 상세의 접힘·펼침 콘텐츠와 높이 변경 알림을 연결한다.
  // 매개변수:
  // - key (Key?): 정보창 상태를 구분할 위젯 키.
  // - isEnglish (bool): 펼침·접힘 도움말을 영문으로 표시할지 여부.
  // - hospitals (bool): 도움말의 시설 종류. 기본값 false는 약국이다.
  // - onExtentChanged (ValueChanged<double>): 부모 높이 대비 시트 높이 비율을 전달해 지도 여백을 갱신할 콜백.
  // - contentBuilder (Widget Function(BuildContext, bool)): 화면 문맥과 접힘 여부로 콘텐츠를 만든다. 표시뿐 아니라 두 상태의 비표시 높이 측정에도 호출된다.
  // 반환값: 높이를 조절할 수 있는 시설 상세 정보창.
  const _PharmacyDetailsSheet({
    super.key,
    required this.isEnglish,
    this.hospitals = false,
    required this.onExtentChanged,
    required this.contentBuilder,
  });

  // 함수이름: createState
  // 함수역할: 드래그 상태를 생성한다. 매개변수: 없음. 반환값: 정보창 상태.
  @override
  State<_PharmacyDetailsSheet> createState() => _PharmacyDetailsSheetState();
}

// 클래스명: _PharmacyDetailsSheetState
// 역할: 실제 상세 내용 크기에 맞춘 시트 높이와 드래그 상태.
// 주요 책임: 접힘·펼침 높이를 측정하고 긴 내용은 스크롤로 제공한다.
// 속성: _controller (DraggableScrollableController): 드래그; _contentHeights (Map<bool,double>): 내용 높이; _compact/_changingExtent/_sizeUpdateScheduled (bool): 갱신 상태.
class _PharmacyDetailsSheetState extends State<_PharmacyDetailsSheet> {
  static const _handleHeight = 32.0;
  final _controller = DraggableScrollableController();
  final _contentHeights = <bool, double>{};
  double _availableHeight = 0;
  double _minimumSize = .24;
  double _maximumSize = _PharmacyDetailsSheet.initialExtent;
  bool _compact = false;
  bool _sizeUpdateScheduled = false;
  bool _changingExtent = false;

  // 함수이름: dispose
  // 함수역할: 드래그 제어기를 해제한다. 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 함수이름: _scheduleSizeUpdate
  // 함수역할: 레이아웃 측정을 모아 다음 프레임에 시트 크기를 적용한다.
  // 매개변수: 없음. 반환값: 없음.
  void _scheduleSizeUpdate() {
    if (_sizeUpdateScheduled) return;
    _sizeUpdateScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sizeUpdateScheduled = false;
      if (!mounted || _availableHeight <= 0 || _contentHeights.length < 2) {
        return;
      }
      final maximum =
          ((_contentHeights[false]! + _handleHeight) / _availableHeight).clamp(
            .01,
            .92,
          );
      // 두 한계가 같으면 Flutter가 드래그를 내용 스크롤로 넘기지 않는다.
      final minimum =
          ((_contentHeights[true]! + _handleHeight) / _availableHeight).clamp(
            .001,
            maximum - .001,
          );
      if ((maximum - _maximumSize).abs() < .0001 &&
          (minimum - _minimumSize).abs() < .0001) {
        return;
      }
      setState(() {
        _minimumSize = minimum;
        _maximumSize = maximum;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.isAttached) return;
        _changingExtent = true;
        _controller.jumpTo(_compact ? _minimumSize : _maximumSize);
        widget.onExtentChanged(_controller.size);
        _changingExtent = false;
      });
    });
  }

  // 함수이름: _onExtentChanged
  // 함수역할: 드래그에 따른 접힘 상태와 지도 여백을 갱신한다.
  // 매개변수: notification: 시트 높이. 반환값: 알림 소비 여부.
  bool _onExtentChanged(DraggableScrollableNotification notification) {
    if (!_changingExtent && _maximumSize - _minimumSize > .02) {
      final compact = notification.extent <= _minimumSize + .015;
      if (_compact != compact) setState(() => _compact = compact);
    }
    widget.onExtentChanged(notification.extent);
    return true;
  }

  // 함수이름: _toggleExtent
  // 함수역할: 버튼으로 접거나 펼친다. 매개변수: 없음. 반환값: 이동 완료.
  Future<void> _toggleExtent() async {
    if (!_controller.isAttached || _changingExtent) return;
    setState(() => _compact = !_compact);
    _changingExtent = true;
    try {
      await _controller.animateTo(
        _compact ? _minimumSize : _maximumSize,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _changingExtent = false;
    }
  }

  // 함수이름: _measureContent
  // 함수역할: 실제 폭·글씨 배율로 두 상태를 측정하되 표시·접근성·입력에서는 제외한다.
  // 매개변수: context: 화면 환경, compact: 접힘 여부. 반환값: 비표시 측정 영역.
  Widget _measureContent(BuildContext context, bool compact) {
    return Offstage(
      child: ExcludeFocus(
        child: SingleChildScrollView(
          primary: false,
          child: _PharmacySheetSizeObserver(
            onSizeChanged: (size) {
              _contentHeights[compact] = size.height;
              _scheduleSizeUpdate();
            },
            child: widget.contentBuilder(context, compact),
          ),
        ),
      ),
    );
  }

  // 함수이름: build
  // 함수역할: 내용에 맞는 두 높이로 스냅되는 정보창을 구성한다.
  // 매개변수: context: 화면 환경. 반환값: 지도 위 정보창.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_availableHeight != constraints.maxHeight) {
          _availableHeight = constraints.maxHeight;
          _scheduleSizeUpdate();
        }
        return Stack(
          children: [
            _measureContent(context, false),
            _measureContent(context, true),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: _onExtentChanged,
              child: DraggableScrollableSheet(
                controller: _controller,
                initialChildSize: _maximumSize,
                minChildSize: _minimumSize,
                maxChildSize: _maximumSize,
                snap: true,
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) => Material(
                  key: const Key('pharmacy-detail-sheet'),
                  elevation: 8,
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    key: const Key('pharmacy-detail-scroll'),
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      Tooltip(
                        message: widget.isEnglish
                            ? (_compact
                                  ? 'Expand ${widget.hospitals ? 'hospital' : 'pharmacy'} details'
                                  : 'Collapse ${widget.hospitals ? 'hospital' : 'pharmacy'} details')
                            : '${widget.hospitals ? '병원' : '약국'} 정보 '
                                  '${_compact ? '펼치기' : '접기'}',
                        child: InkWell(
                          key: const Key('pharmacy-detail-handle'),
                          onTap: _toggleExtent,
                          child: SizedBox(
                            height: _handleHeight,
                            child: Center(
                              child: Icon(
                                _compact
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: MedBuddyColors.textSubtle,
                              ),
                            ),
                          ),
                        ),
                      ),
                      widget.contentBuilder(context, _compact),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// 클래스명: _PharmacySheetSizeObserver
// 역할: 상세 시트 내용 크기를 측정하는 위젯.
// 주요 책임: 자식의 실제 레이아웃 크기 변경을 시트 상태에 전달한다.
// 속성: onSizeChanged (ValueChanged<Size>): 측정 통지; child (Widget, 상속): 측정 대상.
class _PharmacySheetSizeObserver extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSizeChanged;

  // 함수이름: _PharmacySheetSizeObserver
  // 함수역할: 측정 대상을 보관한다. 매개변수: child, onSizeChanged. 반환값: 측정 위젯.
  const _PharmacySheetSizeObserver({
    required this.onSizeChanged,
    required super.child,
  });

  // 함수이름: createRenderObject
  // 함수역할: 측정 렌더러를 생성한다. 매개변수: context. 반환값: 크기 측정 렌더러.
  @override
  _PharmacySheetSizeRenderBox createRenderObject(BuildContext context) =>
      _PharmacySheetSizeRenderBox(onSizeChanged);

  // 함수이름: updateRenderObject
  // 함수역할: 통지 대상을 갱신한다. 매개변수: context, renderObject. 반환값: 없음.
  @override
  void updateRenderObject(
    BuildContext context,
    _PharmacySheetSizeRenderBox renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

// 클래스명: _PharmacySheetSizeRenderBox
// 역할: 시설 상세 내용의 크기 변경 감시 렌더러.
// 주요 책임: 이전 크기와 다를 때만 레이아웃 이후 통지한다.
// 속성: _previousSize (Size?): 마지막 크기; onSizeChanged (ValueChanged<Size>): 통지.
class _PharmacySheetSizeRenderBox extends RenderProxyBox {
  ValueChanged<Size> onSizeChanged;
  Size? _previousSize;

  // 함수이름: _PharmacySheetSizeRenderBox
  // 함수역할: 통지를 보관한다. 매개변수: onSizeChanged. 반환값: 측정 렌더러.
  _PharmacySheetSizeRenderBox(this.onSizeChanged);

  // 함수이름: performLayout
  // 함수역할: 자식 크기가 달라지면 레이아웃 이후 통지한다. 매개변수: 없음. 반환값: 없음.
  @override
  void performLayout() {
    super.performLayout();
    if (_previousSize == size) return;
    _previousSize = size;
    final measuredSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSizeChanged(measuredSize);
    });
  }
}
