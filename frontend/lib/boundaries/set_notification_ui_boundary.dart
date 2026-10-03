import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: set_notification_ui_boundary.dart
// 역할: 휠·직접 입력을 통한 복약 알림 시각 선택을 제공한다.

// 클래스명: _TimeValueType
// 역할: 직접 입력할 시 또는 분의 구분을 담당한다.
// 주요 책임:
// - 직접 입력할 시 또는 분의 구분에서 지원하는 선택지를 열거하고 구분한다: hour, minute.
enum _TimeValueType { hour, minute }

// Class Name: SetNotificationUI
// Role: Represents a reminder time confirmed through scroll wheels or numeric input.
// Responsibilities:
// - Supports hour/minute selection through rotating wheels.
// - Allows direct numeric entry by tapping the selected hour or minute.
// - Returns the confirmed TimeOfDay and delegates persistence and scheduling to the caller.
// Attributes:
// - language (String): Language code selecting visible wording.
// - slotTitle (String): Display label for a dose slot or reminder time.
// - initialTime (TimeOfDay): Hour and minute to display in the picker or save.
class SetNotificationUI extends StatefulWidget {
  final String language;
  final String slotTitle;
  final TimeOfDay initialTime;

  // Function Name: SetNotificationUI
  // Description: Initializes a reminder time confirmed through scroll wheels or numeric input with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - language (String): Language code selecting visible wording.
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // - initialTime (TimeOfDay): Hour and minute to display in the picker or save.
  // Returns: Initialized SetNotificationUI instance.
  const SetNotificationUI({
    super.key,
    required this.language,
    required this.slotTitle,
    required this.initialTime,
  });

  // Function Name: showNotificationPopup
  // Description: Opens the reminder-time dialog with its initial time and returns the confirmed time or cancellation.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - language (String): Language code selecting visible wording.
  // - slotTitle (String): Display label for a dose slot or reminder time.
  // - initialTime (TimeOfDay): Hour and minute to display in the picker or save.
  // Returns: Future<TimeOfDay?>: Confirmed reminder time, or null on cancellation.
  static Future<TimeOfDay?> showNotificationPopup(
    BuildContext context, {
    required String language,
    required String slotTitle,
    required TimeOfDay initialTime,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      // Function Name: showNotificationPopup.builder callback
      // Description: Composes a reminder time confirmed through scroll wheels or numeric input with the current parent constraints for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // Returns: Widget subtree for the described layout or fallback.
      builder: (context) => SetNotificationUI(
        language: language,
        slotTitle: slotTitle,
        initialTime: initialTime,
      ),
    );
  }

  // Function Name: createState
  // Description: Creates the state object that coordinates a reminder time confirmed through scroll wheels or numeric input.
  // Parameters:
  // - None.
  // Returns: A new _SetNotificationUIState instance.
  @override
  State<SetNotificationUI> createState() => _SetNotificationUIState();
}

// 클래스명: _SetNotificationUIState
// 역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 화면 상태를 관리한다.
// 주요 책임:
// - 회전 휠과 직접 입력으로 확정하는 알림 시각에 필요한 상태 변경과 사용자 동작을 연결한다.
class _SetNotificationUIState extends State<SetNotificationUI> {
  static const int _hourCount = 24;
  static const int _minuteCount = 60;
  static const double _pickerHeight = 220;
  static const double _pickerItemExtent = 46;

  late int _selectedHour;
  late int _selectedMinute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  // Function Name: _isEnglish
  // Description: Recognizes English locale prefixes after trimming and lowercasing the language code.
  // Parameters:
  // - None.
  // Returns: True when the documented condition holds; false otherwise.
  bool get _isEnglish => widget.language.trim().toLowerCase().startsWith('en');

  // 함수이름: initState
  // 함수역할: 전달받은 초기 시간으로 시·분 값과 각 휠 컨트롤러를 초기화한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
  }

  // 함수이름: dispose
  // 함수역할: _hourController, _minuteController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 회전 휠과 직접 입력으로 확정하는 알림 시각 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 회전 휠과 직접 입력으로 확정하는 알림 시각에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF344054), width: 1.6),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.18),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                const SizedBox(height: 14),
                Semantics(
                  label: _isEnglish ? 'Medication reminder time' : '복약 알림 시간',
                  hint: _isEnglish
                      ? 'Scroll the wheels or tap the selected hour and minute to type.'
                      : '휠을 돌리거나 선택된 시와 분을 눌러 직접 입력하세요.',
                  child: _buildTimePicker(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildHeader
  // 함수역할: 팝업 닫기, 제목과 시간 확정 버튼을 배치한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 회전 휠과 직접 입력으로 확정하는 알림 시각에 쓰는 위젯 트리.
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('notification-time-close'),
          tooltip: _isEnglish ? 'Close' : '닫기',
          // Function Name: _buildHeader.onPressed callback
          // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(context)`.
          // Parameters:
          // - None.
          // Returns: No callback payload; any selection is delivered through the route result.
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(
            backgroundColor: MedBuddyColors.surfaceSubtle,
            foregroundColor: MedBuddyColors.textStrong,
          ),
          icon: const Icon(Icons.close, size: 25),
        ),
        Expanded(
          child: Text(
            _isEnglish
                ? '${widget.slotTitle} Reminder'
                : '${widget.slotTitle} 알림',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        IconButton(
          key: const Key('notification-time-confirm'),
          tooltip: _isEnglish ? 'Confirm' : '확인',
          onPressed: setNotificationTime,
          style: IconButton.styleFrom(
            backgroundColor: MedBuddyColors.primary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check, size: 25),
        ),
      ],
    );
  }

  // 함수이름: _buildTimePicker
  // 함수역할: 시와 분 회전 휠 위에 선택 영역과 직접 입력 터치 영역을 구성한다.
  // 매개변수:
  // - 없음.
  // 반환값: 회전 휠과 직접 입력으로 확정하는 알림 시각에 쓰는 위젯 트리.
  Widget _buildTimePicker() {
    return SizedBox(
      height: _pickerHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: _pickerItemExtent,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: MedBuddyColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildWheel(
                  key: const Key('notification-hour-wheel'),
                  controller: _hourController,
                  itemCount: _hourCount,
                  selectedValue: _selectedHour,
                  type: _TimeValueType.hour,
                  // 함수이름: _buildTimePicker.onSelected callback
                  // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `setState(() => _selectedHour = value)`을 실행한다.
                  // 매개변수:
                  // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onSelected: (value) {
                    // 함수이름: _buildTimePicker.setState callback
                    // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 입력·요청 상태를 `_selectedHour = value`로 갱신한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                    setState(() => _selectedHour = value);
                  },
                ),
              ),
              const SizedBox(
                width: 24,
                child: Text(
                  ':',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Expanded(
                child: _buildWheel(
                  key: const Key('notification-minute-wheel'),
                  controller: _minuteController,
                  itemCount: _minuteCount,
                  selectedValue: _selectedMinute,
                  type: _TimeValueType.minute,
                  // 함수이름: _buildTimePicker.onSelected callback
                  // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `setState(() => _selectedMinute = value)`을 실행한다.
                  // 매개변수:
                  // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                  // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                  onSelected: (value) {
                    // 함수이름: _buildTimePicker.setState callback
                    // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 입력·요청 상태를 `_selectedMinute = value`로 갱신한다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                    setState(() => _selectedMinute = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 함수이름: _buildWheel
  // 함수역할: 지정된 값 범위를 순환해서 선택할 수 있는 회전 휠을 생성한다.
  // 매개변수:
  // - key (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - controller (FixedExtentScrollController): 해당 카메라·지도·입력·스크롤 동작을 제어하는 객체.
  // - itemCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - selectedValue (int): 현재 선택한 시·분 또는 선택지 값.
  // - type (_TimeValueType): 시·분 또는 처방 변화 등 현재 분기 종류.
  // - onSelected (ValueChanged<int>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 회전 휠과 직접 입력으로 확정하는 알림 시각에 쓰는 위젯 트리.
  Widget _buildWheel({
    required Key key,
    required FixedExtentScrollController controller,
    required int itemCount,
    required int selectedValue,
    required _TimeValueType type,
    required ValueChanged<int> onSelected,
  }) {
    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.light),
      child: CupertinoPicker(
        key: key,
        scrollController: controller,
        itemExtent: _pickerItemExtent,
        diameterRatio: 1.25,
        squeeze: 1.05,
        useMagnifier: true,
        magnification: 1.12,
        looping: true,
        selectionOverlay: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        // 함수이름: _buildWheel.onSelectedItemChanged callback
        // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `onSelected(index % itemCount)`을 실행한다.
        // 매개변수:
        // - index (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onSelectedItemChanged: (index) => onSelected(index % itemCount),
        // 함수이름: _buildWheel.generate callback
        // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `Center(child: Text(value.toString().padLeft(2, '0'), style: TextStyle(color: isSelected ? MedBuddyColors.textStrong : MedBuddyColors.textMuted...; Text(value.toString().padLeft(2, '0'), style: TextStyle(color: isSelected ? MedBuddyColors.textStrong : MedBuddyColors.textMuted, fontSize: is...`을 실행한다.
        // 매개변수:
        // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        children: List.generate(itemCount, (value) {
          final isSelected = value == selectedValue;
          final valueText = Center(
            child: Text(
              value.toString().padLeft(2, '0'),
              style: TextStyle(
                color: isSelected
                    ? MedBuddyColors.textStrong
                    : MedBuddyColors.textMuted,
                fontSize: isSelected ? 24 : 20,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          );
          if (!isSelected) {
            return valueText;
          }
          final isHour = type == _TimeValueType.hour;
          return Semantics(
            button: true,
            label: _isEnglish
                ? 'Selected ${isHour ? 'hour' : 'minute'} $value. Tap to type.'
                : '선택된 ${isHour ? '시' : '분'} $value. 눌러서 직접 입력',
            child: GestureDetector(
              key: Key(
                isHour
                    ? 'notification-hour-direct-input'
                    : 'notification-minute-direct-input',
              ),
              behavior: HitTestBehavior.opaque,
              // 함수이름: _buildWheel.onTap callback
              // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `_showDirectInput(type)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onTap: () => _showDirectInput(type),
              child: valueText,
            ),
          );
        }),
      ),
    );
  }

  // 함수이름: _showDirectInput
  // 함수역할: 선택한 시 또는 분을 숫자 키패드로 입력받고 범위를 검증한다.
  // 매개변수:
  // - type (_TimeValueType): 시·분 또는 처방 변화 등 현재 분기 종류.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showDirectInput(_TimeValueType type) async {
    final isHour = type == _TimeValueType.hour;
    final maximum = isHour ? 23 : 59;
    final currentValue = isHour ? _selectedHour : _selectedMinute;
    var inputValue = currentValue.toString();
    String? errorText;

    final selectedValue = await showDialog<int>(
      context: context,
      // 함수이름: _showDirectInput.builder callback
      // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (dialogContext) {
        return StatefulBuilder(
          // 함수이름: _showDirectInput.builder callback
          // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에 TextStyle, Key을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // - setDialogState (StateSetter): 현재 대화상자의 지역 상태를 갱신하는 함수.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (context, setDialogState) {
            // 함수이름: submit
            // 함수역할: 직접 입력한 숫자를 시·분 허용 범위로 검증하고 유효한 값으로 대화상자를 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
            void submit() {
              final value = int.tryParse(inputValue.trim());
              if (value == null || value < 0 || value > maximum) {
                // 함수이름: _showDirectInput.setDialogState callback
                // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 입력·요청 상태를 `errorText = _isEnglish ? 'Enter a number from 0 to $maximum.' : '0부터 $maximum 사이의 숫자를 입력해주세요.'`로 갱신한다.
                // 매개변수:
                // - 없음.
                // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                setDialogState(() {
                  errorText = _isEnglish
                      ? 'Enter a number from 0 to $maximum.'
                      : '0부터 $maximum 사이의 숫자를 입력해주세요.';
                });
                return;
              }
              Navigator.pop(dialogContext, value);
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(
                isHour
                    ? (_isEnglish ? 'Enter hour' : '시간 입력')
                    : (_isEnglish ? 'Enter minute' : '분 입력'),
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              content: TextFormField(
                key: const Key('notification-direct-time-field'),
                initialValue: inputValue,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                // 함수이름: _showDirectInput.onChanged callback
                // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 입력·요청 상태를 `inputValue = value`로 갱신한다.
                // 매개변수:
                // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                onChanged: (value) => inputValue = value,
                // 함수이름: _showDirectInput.onFieldSubmitted callback
                // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각에서 캡처된 작업 `submit()`을 실행한다.
                // 매개변수:
                // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onFieldSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  errorText: errorText,
                  suffixText: isHour
                      ? (_isEnglish ? 'hour' : '시')
                      : (_isEnglish ? 'min' : '분'),
                  hintText: isHour ? '0~23' : '0~59',
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('notification-direct-time-cancel'),
                  // 함수이름: _showDirectInput.onPressed callback
                  // 함수역할: `Navigator.pop(dialogContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                  // 매개변수:
                  // - 없음.
                  // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_isEnglish ? 'Cancel' : '취소'),
                ),
                FilledButton(
                  key: const Key('notification-direct-time-confirm'),
                  onPressed: submit,
                  child: Text(_isEnglish ? 'Apply' : '적용'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || selectedValue == null) {
      return;
    }
    // 함수이름: _showDirectInput.setState callback
    // 함수역할: 회전 휠과 직접 입력으로 확정하는 알림 시각의 입력·요청 상태를 `_selectedHour = selectedValue; _selectedMinute = selectedValue`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      if (isHour) {
        _selectedHour = selectedValue;
        _hourController.jumpToItem(selectedValue);
      } else {
        _selectedMinute = selectedValue;
        _minuteController.jumpToItem(selectedValue);
      }
    });
  }

  // 함수이름: setNotificationTime
  // 함수역할: 현재 선택된 시와 분을 TimeOfDay로 변환해 호출 화면에 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void setNotificationTime() {
    Navigator.pop(
      context,
      TimeOfDay(hour: _selectedHour, minute: _selectedMinute),
    );
  }
}
