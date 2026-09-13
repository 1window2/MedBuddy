// 파일명: pharmacy_details_sheet.dart
// 역할: 지도를 탐색하면서 펼치거나 접을 수 있는 약국 정보창을 제공한다.
part of 'check_nearby_pharmacy_ui_boundary.dart';

// 클래스명: _PharmacyDetailsSheet
// 역할: 약국 정보창의 크기와 드래그·접근성 조작을 관리한다.
// 주요 책임: 지도 터치를 막지 않는 하단 시트와 내용 스크롤을 연결한다.
// 속성: minimumSize: 접힘 높이, contentBuilder: 약국 내용, onExtentChanged: 높이 통지.
class _PharmacyDetailsSheet extends StatefulWidget {
  static const initialExtent = .65;
  final double minimumSize;
  final bool isEnglish;
  final ValueChanged<double> onExtentChanged;
  final Widget Function(BuildContext, bool) contentBuilder;

  // 함수이름: _PharmacyDetailsSheet
  // 함수역할: 크기와 표시 콜백을 보관한다. 매개변수: 선언된 설정값. 반환값: 정보창.
  const _PharmacyDetailsSheet({
    super.key,
    required this.minimumSize,
    required this.isEnglish,
    required this.onExtentChanged,
    required this.contentBuilder,
  });

  // 함수이름: minimumExtent
  // 함수역할: 큰 글씨에서도 접힌 제목과 동작을 담을 최소 높이를 계산한다.
  // 매개변수: context: 글씨 배율, height: 지도 영역 높이. 반환값: 최소 높이 비율.
  static double minimumExtent(BuildContext context, double height) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ((160 + 56 * scale) / height).clamp(.24, .55);
  }

  // 함수이름: createState
  // 함수역할: 드래그 상태를 생성한다. 매개변수: 없음. 반환값: 정보창 상태.
  @override
  State<_PharmacyDetailsSheet> createState() => _PharmacyDetailsSheetState();
}

// 클래스명: _PharmacyDetailsSheetState
// 역할: 접힘·펼침과 높이 변화를 화면에 전달한다.
// 주요 책임: 컨트롤러 수명 관리, 스냅 이동, 작은 화면의 내용 스크롤.
// 속성: _controller: 시트 크기 제어, _compact: 접힌 정보 표시 여부.
class _PharmacyDetailsSheetState extends State<_PharmacyDetailsSheet> {
  final _controller = DraggableScrollableController();
  bool _compact = false;

  // 함수이름: dispose
  // 함수역할: 드래그 컨트롤러를 해제한다. 매개변수: 없음. 반환값: 없음.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 함수이름: _onExtentChanged
  // 함수역할: 접힘 표시와 지도에 가려지는 영역의 높이를 갱신한다.
  // 매개변수: notification: 현재 시트 높이. 반환값: 알림 소비 여부.
  bool _onExtentChanged(DraggableScrollableNotification notification) {
    final compact = notification.extent <= widget.minimumSize + .035;
    if (_compact != compact) setState(() => _compact = compact);
    widget.onExtentChanged(notification.extent);
    return true;
  }

  // 함수이름: _toggleExtent
  // 함수역할: 드래그 대신 버튼으로 접거나 펼친다.
  // 매개변수: 없음. 반환값: 없음.
  void _toggleExtent() {
    if (!_controller.isAttached) return;
    unawaited(
      _controller.animateTo(
        _compact ? _PharmacyDetailsSheet.initialExtent : widget.minimumSize,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // 함수이름: build
  // 함수역할: 세 단계로 스냅되는 비모달 정보창을 구성한다.
  // 매개변수: context: 화면 환경. 반환값: 지도 위 하단 정보창.
  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtentChanged,
      child: DraggableScrollableSheet(
        controller: _controller,
        initialChildSize: _PharmacyDetailsSheet.initialExtent,
        minChildSize: widget.minimumSize,
        maxChildSize: .92,
        snap: true,
        snapSizes: const [_PharmacyDetailsSheet.initialExtent],
        shouldCloseOnMinExtent: false,
        builder: (context, scrollController) => Material(
          key: const Key('pharmacy-detail-sheet'),
          elevation: 8,
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            key: const Key('pharmacy-detail-scroll'),
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Tooltip(
                message: widget.isEnglish
                    ? (_compact
                          ? 'Expand pharmacy details'
                          : 'Collapse pharmacy details')
                    : (_compact ? '약국 정보 펼치기' : '약국 정보 접기'),
                child: InkWell(
                  key: const Key('pharmacy-detail-handle'),
                  onTap: _toggleExtent,
                  child: SizedBox(
                    height: 32,
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
    );
  }
}
