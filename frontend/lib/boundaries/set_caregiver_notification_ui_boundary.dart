import 'package:flutter/material.dart';

import '../entities/caregiver_notification_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'set_notification_ui_boundary.dart';

// 파일명: set_caregiver_notification_ui_boundary.dart
// 역할: 보호자 알림 조건과 마감 시각 선택을 제공한다.

// 클래스명: SetCaregiverNotificationUI
// 역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자를 담당한다.
// 주요 책임:
// - 현재 보호자 알림 조건·마감 시각을 편집하고 저장으로 확정된 설정을 반환한다.
class SetCaregiverNotificationUI {
  // 함수이름: SetCaregiverNotificationUI._
  // 함수역할: 정적 대화상자 도우미가 외부에서 인스턴스화되지 않도록 제한한다.
  // 매개변수:
  // - 없음.
  // 반환값: 입력 설정이 반영된 SetCaregiverNotificationUI 인스턴스.
  const SetCaregiverNotificationUI._();

  // 함수이름: showNotificationPopup
  // 함수역할: 현재 보호자 알림 조건·마감 시각을 편집하고 저장으로 확정된 설정을 반환한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - setting (CaregiverNotification): 표시하거나 편집할 복약 시간대의 알림 설정.
  // - language (String): 화면 문구를 선택할 언어 코드.
  // - slotLabel (String?): 시간대 또는 알림 시각의 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: Future<CaregiverNotification?>: 확정한 보호자 알림 조건과 마감 시각; 취소 시 null.
  static Future<CaregiverNotification?> showNotificationPopup(
    BuildContext context, {
    required CaregiverNotification setting,
    String language = 'ko',
    String? slotLabel,
    UserSetting userSetting = const UserSetting(),
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
      // 함수이름: showNotificationPopup.builder callback
      // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - dialogContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (dialogContext) {
        return StatefulBuilder(
          // 함수이름: showNotificationPopup.builder callback
          // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자에 EdgeInsets.symmetric, EdgeInsets.fromLTRB, Icon, TextStyle, SizedBox을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // - setDialogState (StateSetter): 현재 대화상자의 지역 상태를 갱신하는 함수.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (context, setDialogState) {
            // 함수이름: selectDeadline
            // 함수역할: 현재 마감 시각의 선택 창을 열고 취소하지 않은 시각을 대화상자 상태에 반영한다.
            // 매개변수:
            // - 없음.
            // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
            Future<void> selectDeadline() async {
              final selectedTime =
                  await SetNotificationUI.showNotificationPopup(
                    dialogContext,
                    language: language,
                    slotTitle: slotLabel ?? (isEnglish ? 'Missed dose' : '미복용'),
                    initialTime: deadline,
                  );
              if (selectedTime != null) {
                // 함수이름: showNotificationPopup.setDialogState callback
                // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자의 입력·요청 상태를 `deadline = selectedTime`로 갱신한다.
                // 매개변수:
                // - 없음.
                // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
                            // Function Name: showNotificationPopup.onPressed callback
                            // Description: Closes this route with the selection or cancellation encoded by `Navigator.pop(dialogContext)`.
                            // Parameters:
                            // - None.
                            // Returns: No callback payload; any selection is delivered through the route result.
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
                        // 함수이름: showNotificationPopup.onTap callback
                        // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자에서 캡처된 작업 `setDialogState(() => selectedMode = CaregiverNotificationMode.disabled)`을 실행한다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onTap: () => setDialogState(
                          // 함수이름: showNotificationPopup.setDialogState callback
                          // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자의 입력·요청 상태를 `selectedMode = CaregiverNotificationMode.disabled`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
                        // 함수이름: showNotificationPopup.onTap callback
                        // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자에서 캡처된 작업 `setDialogState(() => selectedMode = CaregiverNotificationMode.doseCompleted)`을 실행한다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onTap: () => setDialogState(
                          // 함수이름: showNotificationPopup.setDialogState callback
                          // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자의 입력·요청 상태를 `selectedMode = CaregiverNotificationMode.doseCompleted`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
                        // 함수이름: showNotificationPopup.onTap callback
                        // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자에서 캡처된 작업 `setDialogState(() => selectedMode = CaregiverNotificationMode.missedDeadline)`을 실행한다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onTap: () => setDialogState(
                          // 함수이름: showNotificationPopup.setDialogState callback
                          // 함수역할: 보호자의 알림 조건과 미복용 마감 시각 대화상자의 입력·요청 상태를 `selectedMode = CaregiverNotificationMode.missedDeadline`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
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
                            '${userSetting.formatTime(deadline.hour, deadline.minute)}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        // 함수이름: showNotificationPopup.onPressed callback
                        // 함수역할: `Navigator.pop(dialogContext, setting.updateNotificationSetting(selectedMode, deadlineHour: deadline.hour, deadlineMinute: deadline.minute))`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
}

// 클래스명: _NotificationModeOption
// 역할: 보호자 알림 모드의 설명과 선택 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 보호자 알림 모드의 설명과 선택 표시 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
// - selected (bool): 현재 선택 집합에 포함되는지 여부.
// - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _NotificationModeOption extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  // 함수이름: _NotificationModeOption
  // 함수역할: 보호자 알림 모드의 설명과 선택 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - description (String): 주 표시 아래에 제공할 설명 또는 계정 상세.
  // - selected (bool): 현재 선택 집합에 포함되는지 여부.
  // - onTap (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _NotificationModeOption 인스턴스.
  const _NotificationModeOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 보호자 알림 모드의 설명과 선택 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 보호자 알림 모드의 설명과 선택 표시에 쓰는 위젯 트리.
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
