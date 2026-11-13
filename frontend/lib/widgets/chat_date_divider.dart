// 파일명: chat_date_divider.dart
// 역할: 메시지를 휴대폰 현지 날짜별로 구분하는 날짜 머리글을 표시한다.
// 메시지 시각과 같은 휴대폰 현지 날짜를 표시한다. 오늘 여부나 실행 날짜에 의존하지 않는다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';

// 클래스명: ChatDateDivider
// 역할: 대화 목록에 날짜와 요일을 표시한다.
// 주요 책임: 현재 날짜와 무관하게 메시지 시각의 현지 날짜를 한국어 또는 영어로 표현한다.
// 속성: date (DateTime): 메시지 기준 시각; isEnglish (bool): 영어 표시 여부.
class ChatDateDivider extends StatelessWidget {
  // 함수이름: ChatDateDivider
  // 함수역할: 날짜 구분선의 시각과 표시 언어를 설정한다.
  // 매개변수: key (Key?): 위젯 식별 키; date (DateTime): 기준 시각; isEnglish (bool): 영어 여부.
  // 반환값: 상태 없는 날짜 구분선 위젯.
  const ChatDateDivider({
    super.key,
    required this.date,
    required this.isEnglish,
  });
  final DateTime date;
  final bool isEnglish;

  // Function Name: build
  // Description: Converts the supplied instant to the device's local date and renders a localized date/weekday between divider lines.
  // Parameters: context (BuildContext): Position in the widget tree.
  // Returns: A padded row with a wrapping centered label; it does not compare with today's date.
  @override
  Widget build(BuildContext context) {
    final local = date.toLocal();
    const koDays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    const enDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final label = isEnglish
        ? '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} · ${enDays[local.weekday - 1]}'
        : '${local.year}년 ${local.month}월 ${local.day}일 ${koDays[local.weekday - 1]}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 19),
      child: Row(
        children: [
          const Expanded(child: Divider(color: MedBuddyColors.successBorder)),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: KeepWordsText(
              label,
              textAlign: TextAlign.center,
              style: MedBuddyTextStyles.menuBody.copyWith(
                fontSize: 13,
                color: MedBuddyColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: MedBuddyColors.successBorder)),
        ],
      ),
    );
  }
}
