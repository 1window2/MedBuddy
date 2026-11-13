import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/keep_words_text.dart';

// 파일명: set_notification_ui_boundary.dart
// 역할: 휠·직접 입력을 통한 복약 알림 시각 선택을 제공한다.

// 클래스명: _TimeValueType
// 역할: 직접 숫자를 입력할 알림 시각 부분.
// 주요 책임: 시 입력과 분 입력의 유효 범위를 구분한다.
// 속성: hour/minute: 입력 부분.
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

// Class Name: _SetNotificationUIState
// Role: Wheel and numeric-entry state for a confirmed reminder time.
// Responsibilities: Keeps selected hour/minute synchronized with wheel controllers and validates direct entry.
// Attributes: _selectedHour/_selectedMinute (int): selected time; _hourController/_minuteController (FixedExtentScrollController): wheels; _hourCount/_minuteCount (int): valid cycle sizes.
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
  bool get _isEnglish => isEnglishLanguage(widget.language);

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

  // Function Name: build
  // Description: Combines hour/minute wheels and direct numeric entry with explicit time confirmation.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
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
            borderRadius: MedBuddyRadii.control,
            border: Border.all(color: MedBuddyColors.textBody, width: 1.6),
            boxShadow: MedBuddyShadows.card,
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

  // Function Name: _buildHeader
  // Description: Places close, title and confirm controls in the time-picker header.
  // Parameters: context (BuildContext): popup navigation scope.
  // Returns: The time-picker header.
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
          child: KeepWordsText(
            _isEnglish
                ? '${widget.slotTitle} Reminder'
                : '${widget.slotTitle} 알림',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 20,
              fontWeight: FontWeight.w700,
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

  // Function Name: _buildTimePicker
  // Description: Places selection highlights and direct-entry touch areas over the hour/minute wheels.
  // Parameters: None.
  // Returns: The interactive time-selection body.
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
                borderRadius: MedBuddyRadii.control,
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
                    fontWeight: FontWeight.w700,
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

  // Function Name: _buildWheel
  // Description: Creates a cyclic wheel over the supplied value range and reports selection changes.
  // Parameters: key: identity; controller (FixedExtentScrollController): wheel position; itemCount: range size; selectedValue: current hour/minute; type (_TimeValueType): edited component; onSelected: value callback.
  // Returns: The configured time-component wheel.
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
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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

  // Function Name: _showDirectInput
  // Description: Collects an hour or minute through a numeric keyboard and validates its allowed range.
  // Parameters: type (_TimeValueType): hour or minute to edit.
  // Returns: Future completing after valid entry or cancellation.
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
              title: KeepWordsText(
                isHour
                    ? (_isEnglish ? 'Enter hour' : '시간 입력')
                    : (_isEnglish ? 'Enter minute' : '분 입력'),
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontWeight: FontWeight.w700,
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
