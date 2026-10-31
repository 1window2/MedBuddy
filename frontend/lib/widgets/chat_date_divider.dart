// 메시지 시각과 같은 휴대폰 현지 날짜를 표시한다. 오늘 여부나 실행 날짜에 의존하지 않는다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';

class ChatDateDivider extends StatelessWidget {
  const ChatDateDivider({
    super.key,
    required this.date,
    required this.isEnglish,
  });
  final DateTime date;
  final bool isEnglish;

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
            child: Text(
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
