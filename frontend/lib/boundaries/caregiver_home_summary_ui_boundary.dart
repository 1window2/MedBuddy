// 파일명: caregiver_home_summary_ui_boundary.dart
// 역할: 보호자 홈에서 연결된 환자의 복약 현황과 상세 진입을 제공한다.
import 'package:flutter/material.dart';

import '../controls/check_caregiver_home_control.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/home_medication_preview.dart';
import '../widgets/home_medication_slot_pager.dart';
import '../widgets/keep_words_text.dart';

// 클래스명: CaregiverHomeSummaryUI
// 역할: 보호자 홈의 연결 환자 현황과 읽기 전용 상세 진입을 제공한다.
// 주요 책임: 연동 조회 실패·환자 없음·일정 조회 상태를 구분한다.
// 속성: control (CheckCaregiverHome): 조회 상태; isEnglish/isLoadingLinks/hasLinkError (bool): 표시 상태; patientLabel (String Function(PatientCaregiverLink)): 별칭; onPatientRequested (ValueChanged): 상세; onLinkRequested/onRefreshRequested (VoidCallback?): 명령.
class CaregiverHomeSummaryUI extends StatefulWidget {
  final CheckCaregiverHome control;
  final bool isEnglish;
  final VoidCallback? onLinkRequested;
  final VoidCallback? onRefreshRequested;
  final bool isLoadingLinks;
  final bool hasLinkError;
  final String Function(PatientCaregiverLink) patientLabel;
  final ValueChanged<PatientCaregiverLink> onPatientRequested;

  // 함수이름: CaregiverHomeSummaryUI
  // 함수역할: 보호자 현황 조회기와 환자 이름·상세 진입 함수를 연결한다.
  // 매개변수: key (Key?): 키; control (CheckCaregiverHome): 조회기; isEnglish/isLoadingLinks/hasLinkError (bool): 상태; patientLabel: 별칭 함수; onPatientRequested: 상세 함수; onLinkRequested/onRefreshRequested (VoidCallback?): 선택 명령.
  // 반환값: 새 CaregiverHomeSummaryUI.
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

  // 함수이름: createState
  // 함수역할: 환자 선택을 계정별로 유지할 화면 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _CaregiverHomeSummaryUIState.
  @override
  State<CaregiverHomeSummaryUI> createState() => _CaregiverHomeSummaryUIState();
}

// Class Name: _CaregiverHomeSummaryUIState
// Role: Keeps one linked patient selected while presenting caregiver schedule summaries.
// Responsibilities: Separates link failures from missing schedules and prevents header taps from opening details.
// Attributes: _selectedLinkId (int?): selected relationship identifier; widget (CaregiverHomeSummaryUI): current dependencies.
class _CaregiverHomeSummaryUIState extends State<CaregiverHomeSummaryUI> {
  int? _selectedLinkId;
  // 함수이름: control
  // 함수역할: 부모가 제공한 보호자 현황 조회기를 읽는다.
  // 매개변수: 없음.
  // 반환값: 현재 CheckCaregiverHome.
  CheckCaregiverHome get control => widget.control;
  // 함수이름: isEnglish
  // 함수역할: 부모가 지정한 표시 언어를 읽는다.
  // 매개변수: 없음.
  // 반환값: 영어 표시이면 true.
  bool get isEnglish => widget.isEnglish;
  // 함수이름: isLoadingLinks
  // 함수역할: 환자 연동 목록 조회 진행 여부를 읽는다.
  // 매개변수: 없음.
  // 반환값: 조회 중이면 true.
  bool get isLoadingLinks => widget.isLoadingLinks;
  // 함수이름: hasLinkError
  // 함수역할: 환자 연동 목록 자체의 조회 실패 여부를 읽는다.
  // 매개변수: 없음.
  // 반환값: 연동 조회 실패이면 true.
  bool get hasLinkError => widget.hasLinkError;
  // 함수이름: onLinkRequested
  // 함수역할: 새 환자 연동 화면을 여는 부모 명령을 읽는다.
  // 매개변수: 없음.
  // 반환값: VoidCallback 또는 미제공 시 null.
  VoidCallback? get onLinkRequested => widget.onLinkRequested;
  // 함수이름: onRefreshRequested
  // 함수역할: 목록 전체를 다시 조회할 부모 명령을 읽는다.
  // 매개변수: 없음.
  // 반환값: VoidCallback 또는 기본 조회 사용을 뜻하는 null.
  VoidCallback? get onRefreshRequested => widget.onRefreshRequested;
  // 함수이름: patientLabel
  // 함수역할: 부모의 별칭 규칙으로 연동 환자의 표시 이름을 구한다.
  // 매개변수: link (PatientCaregiverLink): 대상 연동.
  // 반환값: 환자 표시 이름.
  String patientLabel(PatientCaregiverLink link) => widget.patientLabel(link);
  // 함수이름: onPatientRequested
  // 함수역할: 선택한 환자의 읽기 전용 상세 열기 요청을 부모에게 전달한다.
  // 매개변수: link (PatientCaregiverLink): 선택 연동.
  // 반환값: 없음.
  void onPatientRequested(PatientCaregiverLink link) =>
      widget.onPatientRequested(link);

  // 함수이름: didUpdateWidget
  // 함수역할: 조회 계정이 변경되면 이전 계정의 환자 선택을 버린다.
  // 매개변수: oldWidget (CaregiverHomeSummaryUI): 이전 설정.
  // 반환값: 없음.
  @override
  void didUpdateWidget(CaregiverHomeSummaryUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control.userHash != control.userHash) _selectedLinkId = null;
  }

  // 함수이름: _index
  // 함수역할: 선택한 연동 ID를 현재 목록에서 찾아 삭제된 선택은 첫 항목으로 되돌린다.
  // 매개변수: 없음.
  // 반환값: 선택 위치; 찾지 못하면 0.
  int get _index {
    final found = control.links.indexWhere(
      (link) => link.linkId == _selectedLinkId,
    );
    return found < 0 ? 0 : found;
  }

  // 함수이름: _select
  // 함수역할: 유효한 다른 목록 위치만 선택하고 그 연동 ID를 보관한다.
  // 매개변수: index (int): 환자 목록 위치.
  // 반환값: 없음. 범위 밖 또는 같은 선택은 무시한다.
  void _select(int index) {
    if (index < 0 || index >= control.links.length || index == _index) return;
    setState(() {
      _selectedLinkId = control.links[index].linkId;
    });
  }

  // 함수이름: _patientPager
  // 함수역할: 비어 있지 않은 목록의 현재 환자를 고정된 헤더 위치로 표시한다.
  // 매개변수: context (BuildContext): 카드 표시 위치.
  // 반환값: 선택 환자의 미리보기; 빈 목록에서는 호출하지 않는다.
  Widget _patientPager(BuildContext context) {
    final index = _index;
    final links = control.links;
    _selectedLinkId = links[index].linkId;
    // 헤더까지 움직이면 원래 화살표 좌표의 재탭이 카드 상세 진입으로 바뀐다.
    return KeyedSubtree(
      key: const Key('caregiver-patient-pager'),
      child: _patientPreview(context, links[index], true),
    );
  }

  // 함수이름: _patientNavigationButton
  // 함수역할: 이전·다음 환자 화살표를 만들고 비활성 화살표의 탭도 부모 카드로 전달되지 않게 한다.
  // 매개변수: previous (bool): 이전 방향 여부.
  // 반환값: 48 크기의 탐색 버튼.
  Widget _patientNavigationButton({required bool previous}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    // 비활성 화살표의 탭이 부모 카드의 일정 열기로 전달되지 않게 한다.
    onTap: () {},
    child: IconButton(
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
    ),
  );

  // Function Name: build
  // Description: Shows the selected patient when links are valid, otherwise distinguishes loading, lookup failure and an empty link list.
  // Parameters: context (BuildContext): Layout and theme location.
  // Returns: Caregiver preview or status panel; empty valid links do not reuse stale schedule errors.
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
                : (isEnglish ? 'No linked patients.' : '연동된 환자가 없습니다.'),
          ),
          if (!loading && !failed && onLinkRequested != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('caregiver-home-link'),
              onPressed: onLinkRequested,
              icon: const Icon(Icons.person_add_alt),
              label: KeepWordsText(isEnglish ? 'Link a patient' : '환자 연동'),
            ),
          ],
        ],
      ),
    );
  }

  // 함수이름: _errorMessage
  // 함수역할: 복약 현황 조회 실패에 맞는 재시도 안내를 선택한다.
  // 매개변수: 없음.
  // 반환값: 현재 언어의 오류 안내.
  String get _errorMessage => isEnglish
      ? 'Could not load medication status. Try again.'
      : '복약 현황을 불러오지 못했습니다. 다시 조회해주세요.';

  // 함수이름: _statusMessage
  // 함수역할: 복약 현황 안내를 높이 제한 없이 줄바꿈할 수 있게 표시한다.
  // 매개변수: message (String): 표시 안내.
  // 반환값: 상태 Text 위젯.
  Widget _statusMessage(String message) => KeepWordsText(
    message,
    style: const TextStyle(fontSize: 15, color: MedBuddyColors.textMuted),
  );

  // Function Name: _patientPreview
  // Description: Aggregates completed schedule slots for one patient and exposes read-only details without medication mutations.
  // Parameters: context (BuildContext): Layout; link (PatientCaregiverLink): permitted patient; showRefresh (bool): refresh button visibility.
  // Returns: Patient preview with loading, error or dose-progress state.
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

  // 함수이름: _refreshButton
  // 함수역할: 조회 중에는 새로고침을 막고 비활성 버튼 탭이 환자 상세로 넘어가지 않게 한다.
  // 매개변수: 없음.
  // 반환값: 부모 갱신 함수 또는 기본 control.refresh를 실행하는 버튼.
  Widget _refreshButton() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    // 조회 중 비활성 버튼의 재탭이 부모 카드의 일정 열기로 전달되지 않게 한다.
    onTap: () {},
    child: IconButton(
      key: const Key('caregiver-home-refresh'),
      tooltip: isEnglish ? 'Refresh' : '새로고침',
      onPressed: control.isLoading || isLoadingLinks
          ? null
          : (onRefreshRequested ?? control.refresh),
      icon: const Icon(Icons.refresh, color: MedBuddyColors.primaryDark),
    ),
  );
}
