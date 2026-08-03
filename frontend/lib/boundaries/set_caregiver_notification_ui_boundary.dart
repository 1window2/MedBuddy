import 'package:flutter/material.dart';

import '../entities/caregiver_notification_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'set_notification_ui_boundary.dart';

// 파일명: set_caregiver_notification_ui_boundary.dart
// 역할: 보호자가 환자별 복약 알림 조건과 마감 시각을 선택하는 창을 제공한다.

class SetCaregiverNotificationUI {
  const SetCaregiverNotificationUI._();

  static Future<CaregiverNotification?> showNotificationPopup(
    BuildContext context, {
    required CaregiverNotification setting,
    String language = 'ko',
    String? slotLabel,
  }) {
    final isEnglish = language.trim().toLowerCase().startsWith('en');
    var selectedMode = setting.mode;
    var deadline = TimeOfDay(
      hour: setting.deadlineHour ?? 21,
      minute: setting.deadlineMinute ?? 0,
    );

    return showDialog<CaregiverNotification>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> selectDeadline() async {
              final selectedTime =
                  await SetNotificationUI.showNotificationPopup(
                    dialogContext,
                    language: language,
                    slotTitle: slotLabel ?? (isEnglish ? 'Missed dose' : '미복용'),
                    initialTime: deadline,
                  );
              if (selectedTime != null) {
                setDialogState(() => deadline = selectedTime);
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.9,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: isEnglish ? 'Close' : '닫기',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                          Expanded(
                            child: Text(
                              slotLabel == null
                                  ? (isEnglish
                                        ? 'Caregiver notifications'
                                        : '보호자 알림 설정')
                                  : (isEnglish
                                        ? '$slotLabel notifications'
                                        : '$slotLabel 알림 설정'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: MedBuddyColors.textStrong,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _NotificationModeOption(
                        title: isEnglish ? 'Off' : '끄기',
                        description: isEnglish
                            ? 'Do not receive medication updates.'
                            : '환자의 복약 상태 알림을 받지 않습니다.',
                        selected:
                            selectedMode == CaregiverNotificationMode.disabled,
                        onTap: () => setDialogState(
                          () =>
                              selectedMode = CaregiverNotificationMode.disabled,
                        ),
                      ),
                      _NotificationModeOption(
                        title: isEnglish
                            ? 'When a dose is marked taken'
                            : '복용 확인 즉시 알림',
                        description: isEnglish
                            ? 'Notify me whenever the patient marks a dose as taken.'
                            : '환자가 약을 복용 완료로 표시하면 바로 알려줍니다.',
                        selected:
                            selectedMode ==
                            CaregiverNotificationMode.doseCompleted,
                        onTap: () => setDialogState(
                          () => selectedMode =
                              CaregiverNotificationMode.doseCompleted,
                        ),
                      ),
                      _NotificationModeOption(
                        title: isEnglish
                            ? 'If doses remain unchecked'
                            : '정해진 시각까지 미복용 시 알림',
                        description: isEnglish
                            ? 'Notify me if any scheduled dose is still unchecked at the selected time.'
                            : '선택한 시각까지 복용하지 않은 약이 남아 있으면 알려줍니다.',
                        selected:
                            selectedMode ==
                            CaregiverNotificationMode.missedDeadline,
                        onTap: () => setDialogState(
                          () => selectedMode =
                              CaregiverNotificationMode.missedDeadline,
                        ),
                      ),
                      if (selectedMode ==
                          CaregiverNotificationMode.missedDeadline) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: selectDeadline,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            '${isEnglish ? 'Check at' : '확인 시각'} '
                            '${_formatTime(deadline)}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                            setting.updateNotificationSetting(
                              selectedMode,
                              deadlineHour: deadline.hour,
                              deadlineMinute: deadline.minute,
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: MedBuddyColors.primary,
                        ),
                        child: Text(isEnglish ? 'Save' : '저장하기'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

class _NotificationModeOption extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _NotificationModeOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? MedBuddyColors.primary
                  : MedBuddyColors.textLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
