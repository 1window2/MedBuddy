// 파일명: medication_schedule_header.dart
// 역할: 본인 일정과 보호자의 환자 일정 화면이 함께 쓰는 녹색 머리글과 시간대 카드 머리줄을 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'medbuddy_page_header.dart';

// 클래스명: MedicationScheduleHeader
// 역할: 일정 화면 상단의 제목, 복용 기록 버튼과 오늘 복약 완료 진행률을 담당한다.
// 주요 책임:
// - 뒤로가기 버튼(선택), 제목과 부제목(선택), 복용 기록 버튼을 한 줄에 배치한다.
// - 완료 수/전체 수와 진행 막대를 머리글 아래쪽 패널에 표시한다.
// 속성 :
//   - title : 머리글 제목 (String)
//   - subtitle : 제목 아래 한 줄 부제목; null이면 제목만 표시한다 (String?)
//   - onBack : 뒤로가기 콜백; null이면 버튼 대신 12px 여백을 둔다 (VoidCallback?)
//   - backTooltip : 뒤로가기 버튼 안내 문구 (String?)
//   - actionKey : 복용 기록 버튼의 위젯 키 (Key)
//   - actionTooltip : 복용 기록 버튼 안내 문구 (String)
//   - onAction : 복용 기록 화면을 여는 콜백 (VoidCallback)
//   - progressLabel : 진행률 패널 제목 (String)
//   - completedCount : 완료한 복약 횟수 (int)
//   - totalCount : 예정된 전체 복약 횟수 (int)
class MedicationScheduleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Key actionKey;
  final String actionTooltip;
  final VoidCallback onAction;
  final IconData actionIcon;
  final String progressLabel;
  final int completedCount;
  final int totalCount;

  // 함수이름: MedicationScheduleHeader
  // 함수역할: 일정 머리글에 표시할 문구, 버튼 동작과 진행률 값을 받는다.
  // 매개변수:
  // - key (Key?): 위젯 식별 키.
  // - title (String): 머리글 제목.
  // - subtitle (String?): 제목 아래 한 줄 부제목; null이면 표시하지 않는다.
  // - onBack (VoidCallback?): 뒤로가기 콜백; null이면 뒤로가기 버튼을 표시하지 않는다.
  // - backTooltip (String?): 뒤로가기 버튼 안내 문구.
  // - actionKey (Key): 복용 기록 버튼의 위젯 키.
  // - actionTooltip (String): 복용 기록 버튼 안내 문구.
  // - onAction (VoidCallback): 복용 기록 화면을 여는 콜백.
  // - progressLabel (String): 진행률 패널 제목.
  // - completedCount (int): 완료한 복약 횟수.
  // - totalCount (int): 예정된 전체 복약 횟수.
  // 반환값: 입력 설정이 반영된 MedicationScheduleHeader 인스턴스.
  const MedicationScheduleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.backTooltip,
    required this.actionKey,
    required this.actionTooltip,
    required this.onAction,
    this.actionIcon = Icons.calendar_month_outlined,
    required this.progressLabel,
    required this.completedCount,
    required this.totalCount,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값을 반영해 제목 줄과 복약 완료 진행률 패널을 구성한다.
  // 매개변수:
  // - context (BuildContext): 상단 안전 영역과 테마를 참조할 위젯 트리 위치.
  // 반환값: 일정 머리글 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: MedBuddyPageHeader.titleStyle,
      strutStyle: MedBuddyPageHeader.titleStrutStyle,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: MedBuddyColors.topBar,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 8,
        20,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBack != null) ...[
                IconButton(
                  tooltip: backTooltip,
                  onPressed: onBack,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 12),
              Expanded(
                // 부제목이 없으면 제목을 Column으로 감싸지 않아 본인 일정 배치를 그대로 유지한다.
                child: subtitle == null
                    ? titleText
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleText,
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MedBuddyColors.onPrimaryMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
              IconButton(
                key: actionKey,
                tooltip: actionTooltip,
                onPressed: onAction,
                icon: Icon(actionIcon, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            margin: const EdgeInsets.only(left: 12, right: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              borderRadius: MedBuddyRadii.control,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        progressLabel,
                        style: const TextStyle(
                          color: MedBuddyColors.onPrimaryMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$completedCount/$totalCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: MedBuddyRadii.pill,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    color: MedBuddyColors.successSurface,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: MedicationSlotHeaderStrip
// 역할: 시간대 카드 맨 위의 색 띠, 시간대 아이콘, 제목과 상태 문구, 뒤쪽 버튼을 담당한다.
// 주요 책임:
// - 시간대 색으로 왼쪽 강조선과 아이콘 배경을 칠하고 제목 아래에 상태 문구(선택)를 표시한다.
// - 호출한 화면이 넘긴 알림·완료 버튼을 오른쪽 끝에 그대로 배치한다.
// 속성 :
//   - style : 시간대 색·배경·아이콘 (MedBuddySlotStyle)
//   - title : 시간대 제목 (String)
//   - status : 제목 아래 상태 문구; null이면 표시하지 않는다 (String?)
//   - statusKey : 상태 문구의 위젯 키 (Key?)
//   - trailing : 오른쪽 끝에 배치할 버튼 목록 (List<Widget>)
class MedicationSlotHeaderStrip extends StatelessWidget {
  final MedBuddySlotStyle style;
  final String title;
  final String? status;
  final Key? statusKey;
  final List<Widget> trailing;

  // 함수이름: MedicationSlotHeaderStrip
  // 함수역할: 시간대 머리줄에 표시할 색, 제목, 상태 문구와 뒤쪽 버튼을 받는다.
  // 매개변수:
  // - key (Key?): 위젯 식별 키.
  // - style (MedBuddySlotStyle): 시간대 색·배경·아이콘.
  // - title (String): 시간대 제목.
  // - status (String?): 제목 아래 상태 문구; null이면 표시하지 않는다.
  // - statusKey (Key?): 상태 문구의 위젯 키.
  // - trailing (List<Widget>): 오른쪽 끝에 배치할 버튼 목록.
  // 반환값: 입력 설정이 반영된 MedicationSlotHeaderStrip 인스턴스.
  const MedicationSlotHeaderStrip({
    super.key,
    required this.style,
    required this.title,
    this.status,
    this.statusKey,
    this.trailing = const [],
  });

  // 함수이름: build
  // 함수역할: 현재 입력값을 반영해 시간대 카드의 머리줄을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정을 참조할 위젯 트리 위치.
  // 반환값: 시간대 머리줄 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: style.tint,
        border: Border(left: BorderSide(color: style.color, width: 5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: style.color,
              borderRadius: MedBuddyRadii.control,
            ),
            child: Icon(style.icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status != null)
                  Text(
                    status!,
                    key: statusKey,
                    style: TextStyle(
                      color: style.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
