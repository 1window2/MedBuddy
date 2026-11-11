// 파일명: medication_schedule_header.dart
// 역할: 본인 일정과 보호자의 환자 일정 화면이 함께 쓰는 녹색 머리글과 시간대 카드 머리줄을 제공한다.

import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import 'keep_words_text.dart';
import 'medbuddy_page_header.dart';

// Class Name: MedicationScheduleHeader
// Role: Show schedule navigation and dose-completion progress.
// Responsibilities: Combine a title, optional back action, primary action and completed/total indicator.
// Attributes: title/subtitle/backTooltip/actionTooltip/progressLabel: labels; onBack/onAction: callbacks; actionKey/actionIcon: action identity; completedCount/totalCount (int): progress.
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

  // Function Name: MedicationScheduleHeader
  // Description: Configure schedule navigation and progress without owning dose state.
  // Parameters: key (Key?): widget identity; title (String)/subtitle (String?): heading; onBack (VoidCallback?)/backTooltip (String?): back action; actionKey (Key)/actionTooltip (String)/onAction (VoidCallback)/actionIcon (IconData): primary action; progressLabel (String): progress caption; completedCount/totalCount (int): counts.
  // Returns: MedicationScheduleHeader: configured header.
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

  // Function Name: build
  // Description: Build a safe-area schedule header with a zero progress value for an empty schedule.
  // Parameters: context (BuildContext): safe-area information.
  // Returns: Widget: heading, navigation and completion bar.
  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final titleText = KeepWordsText(
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
                      child: KeepWordsText(
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

// Class Name: MedicationSlotHeaderStrip
// Role: Label a medication slot using its color, icon and optional status.
// Responsibilities: Place trailing controls beside the slot identity.
// Attributes: style (MedBuddySlotStyle): slot visuals; title/status (String/String?): labels; statusKey (Key?): status identity; trailing (List<Widget>): actions.
class MedicationSlotHeaderStrip extends StatelessWidget {
  final MedBuddySlotStyle style;
  final String title;
  final String? status;
  final Key? statusKey;
  final List<Widget> trailing;

  // Function Name: MedicationSlotHeaderStrip
  // Description: Configure one slot heading and its optional status/actions.
  // Parameters: key (Key?): widget identity; style (MedBuddySlotStyle): visuals; title (String): heading; status (String?)/statusKey (Key?): status label; trailing (List<Widget>): controls.
  // Returns: MedicationSlotHeaderStrip: configured heading.
  const MedicationSlotHeaderStrip({
    super.key,
    required this.style,
    required this.title,
    this.status,
    this.statusKey,
    this.trailing = const [],
  });

  // Function Name: build
  // Description: Build the colored slot stripe, icon, title, optional status and trailing controls.
  // Parameters: context (BuildContext): widget build context.
  // Returns: Widget: slot heading row.
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
                KeepWordsText(
                  title,
                  style: const TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status != null)
                  KeepWordsText(
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
