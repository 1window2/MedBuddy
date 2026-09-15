// 파일명: caregiver_home_summary_ui_boundary.dart
// 역할: 보호자 홈에서 연결된 환자의 복약 현황과 상세 진입을 제공한다.
import 'package:flutter/material.dart';

import '../controls/check_caregiver_home_control.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/home_medication_preview.dart';

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

  // 함수역할: 연결된 환자별 미리보기를 본인 홈과 같은 양식으로 표시한다. 매개변수: context.
  @override
  Widget build(BuildContext context) => Column(
    key: const Key('caregiver-home-summary'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (control.links.isEmpty || hasLinkError)
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
            _refreshButton(),
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
        for (var index = 0; index < control.links.length; index++)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
            child: _patientPreview(context, control.links[index], index == 0),
          ),
    ],
  );

  // 함수역할: 기존 일정의 시간대별 완료 상태를 집계한다. 환자 약을 변경하는 버튼은 제공하지 않는다.
  // 매개변수: 화면 문맥·허용된 연동·전체 새로고침 표시 여부. 반환값: 읽기 전용 복약 미리보기.
  Widget _patientPreview(
    BuildContext context,
    PatientCaregiverLink link,
    bool showRefresh,
  ) {
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
    final pendingDescription = _pendingDescription(
      snapshot?.schedules ?? const [],
    );
    return HomeMedicationPreview(
      key: ValueKey('caregiver-home-patient-${link.linkId}'),
      title: patientLabel(link),
      progressTitle: isEnglish ? 'Today\'s progress' : '오늘의 복약 진행률',
      progressLabel: snapshot == null ? '-' : '$completed/$total',
      progress: snapshot == null && control.isLoading
          ? null
          : total == 0
          ? 0
          : completed / total,
      progressSemanticsLabel: status,
      scheduleTitle: snapshot == null
          ? status
          : pendingDescription != null
          ? (isEnglish ? 'Remaining medication' : '남은 복약 일정')
          : total == 0
          ? (isEnglish ? 'No doses scheduled today' : '오늘 복약 일정이 없습니다')
          : (isEnglish ? 'All doses completed today' : '오늘의 복약을 모두 완료했어요'),
      scheduleDescription: snapshot == null
          ? (isEnglish
                ? 'Check the patient\'s medication status.'
                : '환자의 복약 상태를 확인해주세요.')
          : pendingDescription ??
                (isEnglish ? 'No remaining doses.' : '남은 복약 일정이 없습니다.'),
      hasPendingMedication: pendingDescription != null,
      compact: MediaQuery.sizeOf(context).width >= 350,
      headerAction: showRefresh ? _refreshButton() : null,
      onTap: () => onPatientRequested(link),
    );
  }

  // 함수역할: 목록 전체의 재조회를 제공하되 환자 상세 화면으로 이동하는 탭과 분리한다.
  Widget _refreshButton() => IconButton(
    key: const Key('caregiver-home-refresh'),
    tooltip: isEnglish ? 'Refresh' : '새로고침',
    onPressed: control.isLoading || isLoadingLinks
        ? null
        : (onRefreshRequested ?? control.refresh),
    icon: const Icon(Icons.refresh, color: MedBuddyColors.primaryDark),
  );

  // 함수역할: 미완료 시간대와 약 이름을 요약한다. 완료 기록만 조회하므로 알림 시각은 추정하지 않는다.
  String? _pendingDescription(List<MedicationSchedule> schedules) {
    for (final slot in medicationScheduleSlotKeys) {
      final pending = schedules
          .where(
            (schedule) =>
                schedule.slotKeys.contains(slot) &&
                !schedule.isSlotCompleted(slot),
          )
          .toList(growable: false);
      if (pending.isEmpty) continue;
      final slotLabel = switch (slot) {
        'morning' => isEnglish ? 'Morning' : '아침',
        'lunch' => isEnglish ? 'Lunch' : '점심',
        'evening' => isEnglish ? 'Evening' : '저녁',
        _ => isEnglish ? 'Bedtime' : '취침 전',
      };
      final name = pending.first.displayNameForLanguage(
        isEnglish ? 'en' : 'ko',
      );
      final additional = pending.length - 1;
      final medications = additional == 0
          ? name
          : isEnglish
          ? '$name and $additional more'
          : '$name 외 $additional개';
      return '$slotLabel · $medications';
    }
    return null;
  }
}
