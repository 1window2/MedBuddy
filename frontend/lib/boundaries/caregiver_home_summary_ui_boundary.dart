// 파일명: caregiver_home_summary_ui_boundary.dart
// 역할: 보호자 홈에서 연결된 환자의 복약 현황과 상세 진입을 제공한다.
import 'package:flutter/material.dart';

import '../controls/check_caregiver_home_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/home_medication_preview.dart';
import '../widgets/home_medication_slot_pager.dart';

// 클래스명: CaregiverHomeSummaryUI
// 역할: 조회 실패·일정 없음·완료 진행률을 구분하고 기존 환자 상세 화면으로 연결한다.
// 속성: control은 조회 상태, patientLabel은 별칭, onPatientRequested는 읽기 전용 상세 진입이다.
class CaregiverHomeSummaryUI extends StatefulWidget {
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

  @override
  State<CaregiverHomeSummaryUI> createState() => _CaregiverHomeSummaryUIState();
}

class _CaregiverHomeSummaryUIState extends State<CaregiverHomeSummaryUI> {
  int? _selectedLinkId;
  int _direction = 1;
  CheckCaregiverHome get control => widget.control;
  bool get isEnglish => widget.isEnglish;
  bool get isLoadingLinks => widget.isLoadingLinks;
  bool get hasLinkError => widget.hasLinkError;
  VoidCallback? get onLinkRequested => widget.onLinkRequested;
  VoidCallback? get onRefreshRequested => widget.onRefreshRequested;
  String patientLabel(PatientCaregiverLink link) => widget.patientLabel(link);
  void onPatientRequested(PatientCaregiverLink link) =>
      widget.onPatientRequested(link);

  @override
  void didUpdateWidget(CaregiverHomeSummaryUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control.userHash != control.userHash) _selectedLinkId = null;
  }

  int get _index {
    final found = control.links.indexWhere(
      (link) => link.linkId == _selectedLinkId,
    );
    return found < 0 ? 0 : found;
  }

  void _select(int index) {
    if (index < 0 || index >= control.links.length || index == _index) return;
    setState(() {
      _direction = index > _index ? 1 : -1;
      _selectedLinkId = control.links[index].linkId;
    });
  }

  // 환자는 이름 양옆 화살표로만 전환하고 슬라이드는 내부 시간대 요약에 맡긴다.
  Widget _patientPager(BuildContext context) {
    final index = _index;
    final links = control.links;
    _selectedLinkId = links[index].linkId;
    return ClipRect(
      key: const Key('caregiver-patient-pager'),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(_direction * .12, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _patientPreview(context, links[index], true),
      ),
    );
  }

  // 이름 양옆에서 환자를 전환해 카드 아래에 별도 표시 영역을 만들지 않는다.
  Widget _patientNavigationButton({required bool previous}) => IconButton(
    key: Key(
      previous ? 'caregiver-patient-previous' : 'caregiver-patient-next',
    ),
    tooltip: previous
        ? (isEnglish ? 'Previous patient' : '이전 환자')
        : (isEnglish ? 'Next patient' : '다음 환자'),
    onPressed: (previous ? _index > 0 : _index < control.links.length - 1)
        ? () => _select(_index + (previous ? -1 : 1))
        : null,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    padding: EdgeInsets.zero,
    color: MedBuddyColors.primaryDark,
    icon: Icon(previous ? Icons.chevron_left : Icons.chevron_right),
  );

  // 함수역할: 연결된 환자별 미리보기를 본인 홈과 같은 양식으로 표시한다. 매개변수: context.
  @override
  Widget build(BuildContext context) {
    if (!hasLinkError && control.links.isNotEmpty) {
      return SizedBox(
        key: const Key('caregiver-home-summary'),
        child: _patientPager(context),
      );
    }
    final loading = control.isLoading || isLoadingLinks;
    // 연결 목록이 정상적으로 비어 있으면 이전 환자 일정 오류를 재사용하지 않는다.
    final failed = hasLinkError;
    return HomeMedicationPreview.status(
      key: const Key('caregiver-home-summary'),
      title: isEnglish ? 'Patient schedules' : '환자의 오늘 복약',
      compact: MediaQuery.sizeOf(context).width >= 350,
      headerAction: _refreshButton(),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
          ],
          _statusMessage(
            failed
                ? _errorMessage
                : loading
                ? (isEnglish ? 'Loading status' : '복약 현황 확인 중')
                : (isEnglish ? 'No linked patients.' : '연결된 환자가 없습니다.'),
          ),
          if (!loading && !failed && onLinkRequested != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('caregiver-home-link'),
              onPressed: onLinkRequested,
              icon: const Icon(Icons.person_add_alt),
              label: Text(isEnglish ? 'Link a patient' : '환자 연결'),
            ),
          ],
        ],
      ),
    );
  }

  String get _errorMessage => isEnglish
      ? 'Could not load medication status. Try again.'
      : '복약 현황을 불러오지 못했습니다. 다시 조회해주세요.';

  // 상태 문구는 카드 안에서 줄바꿈하며 큰 글씨에서도 잘리지 않게 한다.
  Widget _statusMessage(String message) => Text(
    message,
    style: const TextStyle(fontSize: 15, color: MedBuddyColors.textMuted),
  );

  // 함수역할: 기존 일정의 시간대별 완료 상태를 집계한다. 환자 약을 변경하는 버튼은 제공하지 않는다.
  // 매개변수: 화면 문맥·허용된 연동·전체 새로고침 표시 여부. 반환값: 읽기 전용 복약 미리보기.
  Widget _patientPreview(
    BuildContext context,
    PatientCaregiverLink link,
    bool showRefresh,
  ) {
    final snapshot = control.snapshotFor(link.linkId);
    if (snapshot == null && control.hasError) {
      return HomeMedicationPreview.status(
        key: ValueKey('caregiver-home-patient-${link.linkId}'),
        title: patientLabel(link),
        compact: MediaQuery.sizeOf(context).width >= 350,
        headerAction: showRefresh ? _refreshButton() : null,
        titleLeading: control.links.length > 1
            ? _patientNavigationButton(previous: true)
            : null,
        titleTrailing: control.links.length > 1
            ? _patientNavigationButton(previous: false)
            : null,
        content: _statusMessage(_errorMessage),
        onTap: () => onPatientRequested(link),
      );
    }
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
      scheduleTitle: '',
      scheduleDescription: '',
      hasPendingMedication: false,
      compact: MediaQuery.sizeOf(context).width >= 350,
      headerAction: showRefresh ? _refreshButton() : null,
      titleLeading: control.links.length > 1
          ? _patientNavigationButton(previous: true)
          : null,
      titleTrailing: control.links.length > 1
          ? _patientNavigationButton(previous: false)
          : null,
      scheduleContent: HomeMedicationSlotPager(
        schedules: snapshot?.schedules ?? const [],
        isEnglish: isEnglish,
        isLoading: snapshot == null && control.isLoading,
        compact: MediaQuery.sizeOf(context).width >= 350,
        hasError: snapshot == null && !control.isLoading,
        showDetailsButton: true,
        onDetailsRequested: () => onPatientRequested(link),
      ),
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
}
