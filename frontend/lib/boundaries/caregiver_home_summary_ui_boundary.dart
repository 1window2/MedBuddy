// 파일명: caregiver_home_summary_ui_boundary.dart
// 역할: 보호자 홈에서 연결된 환자의 복약 현황과 상세 진입을 제공한다.
import 'package:flutter/material.dart';

import '../controls/check_caregiver_home_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../theme/medbuddy_theme.dart';

// 클래스명: CaregiverHomeSummaryUI
// 역할: 조회 실패·일정 없음·완료 진행률을 구분하고 기존 환자 상세 화면으로 연결한다.
// 속성: control은 조회 상태, patientLabel은 별칭, onPatientRequested는 읽기 전용 상세 진입이다.
class CaregiverHomeSummaryUI extends StatelessWidget {
  final CheckCaregiverHome control;
  final bool isEnglish;
  final VoidCallback? onLinkRequested;
  final VoidCallback? onRefreshRequested;
  final bool isLoadingLinks;
  final bool hasLinkError;
  final String Function(PatientCaregiverLink) patientLabel;
  final ValueChanged<PatientCaregiverLink> onPatientRequested;

  // 함수역할: 보호자 현황의 조회 상태·언어·표시 이름·화면 이동을 받는다.
  const CaregiverHomeSummaryUI({
    super.key,
    required this.control,
    required this.isEnglish,
    this.onLinkRequested,
    this.onRefreshRequested,
    this.isLoadingLinks = false,
    this.hasLinkError = false,
    required this.patientLabel,
    required this.onPatientRequested,
  });

  // 함수역할: 환자별 이름과 완료 비율을 읽기 쉬운 행으로 표시한다. 매개변수: context.
  @override
  Widget build(BuildContext context) => Column(
    key: const Key('caregiver-home-summary'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.people_outline, color: MedBuddyColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEnglish ? 'Patient schedules' : '환자의 오늘 복약',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: MedBuddyColors.textStrong,
                letterSpacing: 0,
              ),
            ),
          ),
          IconButton(
            key: const Key('caregiver-home-refresh'),
            tooltip: isEnglish ? 'Refresh' : '새로고침',
            onPressed: control.isLoading || isLoadingLinks
                ? null
                : (onRefreshRequested ?? control.refresh),
            icon: const Icon(Icons.refresh, color: MedBuddyColors.primaryDark),
          ),
        ],
      ),
      if (control.isLoading || isLoadingLinks)
        const LinearProgressIndicator(minHeight: 2),
      if (control.hasError || hasLinkError)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            isEnglish
                ? 'Could not load medication status. Try again.'
                : '복약 현황을 불러오지 못했습니다. 다시 조회해주세요.',
            style: const TextStyle(
              fontSize: 15,
              color: MedBuddyColors.textMuted,
            ),
          ),
        ),
      if (control.links.isEmpty && !isLoadingLinks && !hasLinkError) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            isEnglish ? 'No linked patients.' : '연결된 환자가 없습니다.',
            style: const TextStyle(
              fontSize: 16,
              color: MedBuddyColors.textMuted,
            ),
          ),
        ),
        if (onLinkRequested != null)
          OutlinedButton.icon(
            key: const Key('caregiver-home-link'),
            onPressed: onLinkRequested,
            icon: const Icon(Icons.person_add_alt),
            label: Text(isEnglish ? 'Link a patient' : '환자 연결'),
          ),
      ],
      if (!hasLinkError)
        for (final link in control.links) _patientRow(link),
    ],
  );

  // 함수역할: 기존 일정의 시간대별 완료 상태를 집계한다. 환자 약을 변경하는 버튼은 제공하지 않는다.
  // 매개변수: 보호자에게 허용된 연동. 반환값: 환자 현황 행.
  Widget _patientRow(PatientCaregiverLink link) {
    final snapshot = control.snapshotFor(link.linkId);
    var total = 0;
    var completed = 0;
    if (snapshot != null) {
      for (final schedule in snapshot.schedules) {
        for (final slot in schedule.slotKeys) {
          total++;
          if (schedule.isSlotCompleted(slot)) completed++;
        }
      }
    }
    final status = snapshot == null
        ? (control.isLoading
              ? (isEnglish ? 'Loading status' : '복약 현황 확인 중')
              : (isEnglish ? 'Status unavailable' : '복약 현황 확인 필요'))
        : total == 0
        ? (isEnglish ? 'No doses scheduled today' : '오늘 복약 일정이 없습니다')
        : (isEnglish
              ? '$completed of $total doses taken'
              : '$total회 중 $completed회 복용');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MedBuddyColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('caregiver-home-patient-${link.linkId}'),
          onTap: () => onPatientRequested(link),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patientLabel(link),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: MedBuddyColors.textStrong,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      color: MedBuddyColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MedBuddyColors.textMuted,
                  ),
                ),
                if (snapshot != null && total > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: completed / total,
                    minHeight: 6,
                    color: MedBuddyColors.primary,
                    backgroundColor: MedBuddyColors.successSurface,
                    semanticsLabel: status,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
