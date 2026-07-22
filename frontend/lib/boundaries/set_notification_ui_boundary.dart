import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/medbuddy_theme.dart';

// 파일명: set_notification_ui_boundary.dart
// 역할: 사용자가 복약 알림 시간을 휠 또는 숫자 입력으로 설정하는 팝업을 제공한다.

// 열거형명: _TimeValueType
// 역할: 직접 입력할 시간 값이 시인지 분인지 구분한다.
enum _TimeValueType { hour, minute }

// 클래스명: SetNotificationUI
// 역할: 오늘의 복약 일정에서 사용하는 알림 시간 설정 팝업을 표시한다.
// 주요 책임:
// - 시와 분을 회전식 휠로 선택할 수 있게 한다.
// - 선택된 시 또는 분을 눌러 숫자로 직접 입력할 수 있게 한다.
// - 확정된 시간을 TimeOfDay로 반환하고 저장과 알림 예약은 호출자에게 위임한다.
// 속성:
// - language: 화면 문구에 적용할 언어 코드
// - slotTitle: 아침, 점심 등 알림 시간대 제목
// - initialTime: 팝업을 열 때 처음 표시할 시간
class SetNotificationUI extends StatefulWidget {
  final String language;
  final String slotTitle;
  final TimeOfDay initialTime;

  const SetNotificationUI({
    super.key,
    required this.language,
    required this.slotTitle,
    required this.initialTime,
  });

  // 함수이름: showNotificationPopup
  // 함수역할:
  // - 알림 시간 설정 팝업을 열고 사용자가 확정한 시간을 반환한다.
  // 매개변수:
  // - context: 팝업을 표시할 화면 컨텍스트
  // - language: 팝업 문구에 적용할 언어 코드
  // - slotTitle: 아침, 점심 등 알림 시간대 제목
  // - initialTime: 휠에 처음 표시할 시간
  // 반환값:
  // - 사용자가 확정한 시간 또는 팝업을 닫으면 null
  static Future<TimeOfDay?> showNotificationPopup(
    BuildContext context, {
    required String language,
    required String slotTitle,
    required TimeOfDay initialTime,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SetNotificationUI(
        language: language,
        slotTitle: slotTitle,
        initialTime: initialTime,
      ),
    );
  }

  @override
  State<SetNotificationUI> createState() => _SetNotificationUIState();
}

// 클래스명: _SetNotificationUIState
// 역할: 휠 위치와 직접 입력값을 동기화하고 확정 시간을 반환한다.
class _SetNotificationUIState extends State<SetNotificationUI> {
  static const int _hourCount = 24;
  static const int _minuteCount = 60;
  static const double _pickerHeight = 220;
  static const double _pickerItemExtent = 46;

  late int _selectedHour;
  late int _selectedMinute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  bool get _isEnglish => widget.language.trim().toLowerCase().startsWith('en');

  // 함수이름: initState
  // 함수역할:
  // - 전달받은 초기 시간으로 시·분 값과 각 휠 컨트롤러를 초기화한다.
  // 반환값:
  // - 없음
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
  // 함수역할:
  // - 팝업이 제거될 때 시·분 휠 컨트롤러를 해제한다.
  // 반환값:
  // - 없음
  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할:
  // - 알림 시간 설정 팝업의 헤더와 시간 선택 영역을 구성한다.
  // 매개변수:
  // - context: 현재 위젯 트리의 화면 컨텍스트
  // 반환값:
  // - 알림 시간 설정 Dialog
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
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
    );
  }

  // 함수이름: _buildHeader
  // 함수역할:
  // - 팝업 닫기, 제목과 시간 확정 버튼을 배치한다.
  // 매개변수:
  // - context: 팝업을 닫거나 결과를 반환할 화면 컨텍스트
  // 반환값:
  // - 알림 팝업 헤더 위젯
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('notification-time-close'),
          tooltip: _isEnglish ? 'Close' : '닫기',
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
  // 함수역할:
  // - 시와 분 회전 휠 위에 선택 영역과 직접 입력 터치 영역을 구성한다.
  // 반환값:
  // - 휠과 직접 입력 동작이 결합된 시간 선택 위젯
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 92,
                child: _buildWheel(
                  key: const Key('notification-hour-wheel'),
                  controller: _hourController,
                  itemCount: _hourCount,
                  selectedValue: _selectedHour,
                  type: _TimeValueType.hour,
                  onSelected: (value) {
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
              SizedBox(
                width: 92,
                child: _buildWheel(
                  key: const Key('notification-minute-wheel'),
                  controller: _minuteController,
                  itemCount: _minuteCount,
                  selectedValue: _selectedMinute,
                  type: _TimeValueType.minute,
                  onSelected: (value) {
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
  // 함수역할:
  // - 지정된 값 범위를 순환해서 선택할 수 있는 회전 휠을 생성한다.
  // 매개변수:
  // - key: 테스트와 접근성 식별에 사용할 키
  // - controller: 휠의 현재 위치를 관리하는 컨트롤러
  // - itemCount: 휠 값의 개수
  // - selectedValue: 현재 선택된 값
  // - type: 직접 입력 동작에 사용할 시·분 구분값
  // - onSelected: 휠 값이 변경됐을 때 실행할 콜백
  // 반환값:
  // - 시 또는 분 선택용 CupertinoPicker
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
        onSelectedItemChanged: (index) => onSelected(index % itemCount),
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
              onTap: () => _showDirectInput(type),
              child: valueText,
            ),
          );
        }),
      ),
    );
  }

  // 함수이름: _showDirectInput
  // 함수역할:
  // - 선택한 시 또는 분을 숫자 키패드로 입력받고 범위를 검증한다.
  // 매개변수:
  // - type: 직접 입력할 값의 종류
  // 반환값:
  // - 입력 취소 또는 휠 동기화가 끝난 Future
  Future<void> _showDirectInput(_TimeValueType type) async {
    final isHour = type == _TimeValueType.hour;
    final maximum = isHour ? 23 : 59;
    final currentValue = isHour ? _selectedHour : _selectedMinute;
    var inputValue = currentValue.toString();
    String? errorText;

    final selectedValue = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final value = int.tryParse(inputValue.trim());
              if (value == null || value < 0 || value > maximum) {
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
                onChanged: (value) => inputValue = value,
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
  // 함수역할:
  // - 현재 선택된 시와 분을 TimeOfDay로 변환해 호출 화면에 반환한다.
  // 반환값:
  // - 없음
  void setNotificationTime() {
    Navigator.pop(
      context,
      TimeOfDay(hour: _selectedHour, minute: _selectedMinute),
    );
  }
}
