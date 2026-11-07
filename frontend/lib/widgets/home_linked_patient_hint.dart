// 파일명: home_linked_patient_hint.dart
// 역할: 보호자 계정 홈의 "연동된 환자 일정 보기" 안내를 테두리 없이 글자 높이에 맞춘 행으로 그린다.
import 'package:flutter/material.dart';
import '../theme/medbuddy_theme.dart';

// Class Name: HomeLinkedPatientHint
// Role: Show a home-screen entry to linked-patient schedules.
// Responsibilities: Present localized navigation copy and forward taps to the caller.
// Attributes: isEnglish (bool): locale; onTap (VoidCallback): navigation action.
class HomeLinkedPatientHint extends StatelessWidget {
  final bool isEnglish;
  final VoidCallback onTap;

  // Function Name: HomeLinkedPatientHint
  // Description: Configure the linked-patient navigation hint.
  // Parameters: key (Key?): widget identity; isEnglish (bool): locale; onTap (VoidCallback): selection handler.
  // Returns: HomeLinkedPatientHint: configured widget.
  const HomeLinkedPatientHint({
    super.key,
    required this.isEnglish,
    required this.onTap,
  });

  // Function Name: build
  // Description: Build the accessible tap target with localized title, supporting text and navigation icon.
  // Parameters: context (BuildContext): widget build context.
  // Returns: Widget: linked-patient navigation row.
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const Key('caregiver-home-source-hint'),
        borderRadius: MedBuddyRadii.control,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
          child: Row(
            children: [
              const Icon(
                Icons.people_outline,
                color: MedBuddyColors.primaryDark,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEnglish
                          ? 'View linked patient schedules'
                          : '연동된 환자 일정 보기',
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnglish
                          ? 'Switch Home to “Linked patients”.'
                          : '홈 일정을 ‘연동된 환자’로 바꿔요.',
                      style: const TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
