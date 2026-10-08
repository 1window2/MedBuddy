part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_empty_widgets.dart
// 역할: 빈 목록의 등록 진입, 조회 실패 안내, 전체 선택과 삭제 버튼 및 날짜 묶음을 제공한다.

// 클래스명: _SavedMedicationStateShell
// 역할: 복약함의 빈 목록·조회 실패·빈 조회 결과가 함께 쓰는 가운데 정렬 안내 틀을 그린다.
// 주요 책임: 아이콘, 안내 문구, 동작 버튼을 세로로 배치하고 큰 글씨에서도 버튼까지 스크롤되게 한다.
// 속성: icon은 상태 아이콘, message는 안내 문구, gap은 문구와 버튼 사이 간격, actions는 동작 버튼 목록이다.
class _SavedMedicationStateShell extends StatelessWidget {
  final IconData icon;
  final Widget message;
  final double gap;
  final List<Widget> actions;

  // 함수이름: _SavedMedicationStateShell
  // 함수역할: 상태 안내의 아이콘·문구·간격·버튼을 받는다.
  // 매개변수: icon, message, gap, actions. 반환값: 안내 틀 위젯.
  const _SavedMedicationStateShell({
    required this.icon,
    required this.message,
    required this.gap,
    required this.actions,
  });

  // 함수이름: build
  // 함수역할: 남은 화면을 채우는 스크롤 영역 가운데에 아이콘, 문구, 버튼을 차례로 놓는다.
  // 매개변수: context는 화면 위치. 반환값: 스크롤 가능한 상태 안내.
  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, color: MedBuddyColors.textMuted, size: 42),
          const SizedBox(height: 14),
          message,
          SizedBox(height: gap),
          ...actions,
        ],
      ),
    ),
  );
}

// 클래스명: _SavedMedicationEmptyState
// 역할: 빈 복약함 안내와 보통 크기의 등록 버튼을 배치한다.
// 주요 책임: 큰 글씨에서도 등록 버튼까지 스크롤되게 한다.
// 속성: text는 문구, onPrescriptionInputRequested는 등록 콜백이다.
class _SavedMedicationEmptyState extends StatelessWidget {
  final _SavedMedicationText text;
  final VoidCallback? onPrescriptionInputRequested;

  // 함수이름: _SavedMedicationEmptyState
  // 함수역할: 빈 상태의 표시와 동작을 받는다.
  // 매개변수: text, onPrescriptionInputRequested. 반환값: 빈 상태 위젯.
  const _SavedMedicationEmptyState({
    required this.text,
    required this.onPrescriptionInputRequested,
  });

  // 함수이름: build
  // 함수역할: 안내와 전체 너비 등록 버튼을 구성한다.
  // 매개변수: context는 화면 위치. 반환값: 스크롤 가능한 빈 상태.
  @override
  Widget build(BuildContext context) => _SavedMedicationStateShell(
    icon: Icons.medication_outlined,
    gap: 24,
    message: Text(
      text.emptyMessage,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: MedBuddyColors.textMuted,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    actions: [
      FilledButton.icon(
        key: const Key('saved-medication-register'),
        onPressed: onPrescriptionInputRequested,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(text.registerMedication, textAlign: TextAlign.center),
      ),
    ],
  );
}

// 클래스명: _SavedMedicationLoadErrorState
// 역할: 저장 목록 조회에 실패했음을 알리고 다시 시도 버튼을 배치한다.
// 주요 책임: 조회 실패를 저장된 약이 없는 상태와 구분하고 큰 글씨에서도 버튼까지 스크롤되게 한다.
// 속성: text는 문구, onRetryRequested는 다시 조회 콜백이다.
class _SavedMedicationLoadErrorState extends StatelessWidget {
  final _SavedMedicationText text;
  final VoidCallback? onRetryRequested;

  // 함수이름: _SavedMedicationLoadErrorState
  // 함수역할: 조회 실패 상태의 표시와 동작을 받는다.
  // 매개변수: text, onRetryRequested. 반환값: 조회 실패 상태 위젯.
  const _SavedMedicationLoadErrorState({
    required this.text,
    required this.onRetryRequested,
  });

  // 함수이름: build
  // 함수역할: 조회 실패 안내와 전체 너비 다시 시도 버튼을 구성한다.
  // 매개변수: context는 화면 위치. 반환값: 스크롤 가능한 조회 실패 상태.
  @override
  Widget build(BuildContext context) => _SavedMedicationStateShell(
    icon: Icons.cloud_off_outlined,
    gap: 24,
    message: Text(
      text.loadFailedMessage,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: MedBuddyColors.textMuted,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    actions: [
      FilledButton.icon(
        key: const Key('saved-medication-retry'),
        onPressed: onRetryRequested,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        icon: const Icon(Icons.refresh),
        label: Text(text.retry, textAlign: TextAlign.center),
      ),
    ],
  );
}

// 클래스명: _SavedMedicationSelectionControl
// 역할: 현재 목록의 전체·일부·미선택 상태와 선택 개수를 표시한다.
// 주요 책임: 큰 글씨일 때 선택 개수를 다음 줄로 배치한다.
// 속성: selectedCount와 visibleCount는 유효 ID 수, enabled는 조작 가능 여부이다.
class _SavedMedicationSelectionControl extends StatelessWidget {
  final _SavedMedicationText text;
  final int selectedCount;
  final int visibleCount;
  final bool enabled;
  final VoidCallback onToggleAll;

  // 함수이름: _SavedMedicationSelectionControl
  // 함수역할: 선택 상태와 전체 전환 콜백을 받는다.
  // 매개변수: text, selectedCount, visibleCount, enabled, onToggleAll. 반환값: 선택 도구.
  const _SavedMedicationSelectionControl({
    required this.text,
    required this.selectedCount,
    required this.visibleCount,
    required this.enabled,
    required this.onToggleAll,
  });

  // 함수이름: build
  // 함수역할: 알림함과 같은 세 상태 체크박스와 개수를 구성한다.
  // 매개변수: context는 화면 위치. 반환값: 전체 선택 행.
  @override
  Widget build(BuildContext context) => CheckboxListTile(
    key: const Key('saved-medication-select-all'),
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: MedBuddyColors.primary,
    tristate: true,
    value: selectedCount == 0
        ? false
        : (selectedCount == visibleCount ? true : null),
    onChanged: !enabled || visibleCount == 0
        ? null
        // 함수역할: 일부 선택도 전체 선택으로 바꾼다. 매개변수: value는 미사용. 반환값: 없음.
        : (value) => onToggleAll(),
    title: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          text.selectAll,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MedBuddyColors.textStrong,
            letterSpacing: 0,
          ),
        ),
        Text(
          text.selectedCount(selectedCount),
          key: const Key('saved-medication-selection-count'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MedBuddyColors.textMuted,
            letterSpacing: 0,
          ),
        ),
      ],
    ),
  );
}

// 클래스명: _SelectionDeleteBar
// 역할: 선택 모드 하단에 전체 너비의 삭제 버튼을 고정한다.
// 주요 책임: 선택 없음과 삭제 진행 중에는 중복 요청을 막는다.
// 속성: selectedCount는 유효 선택 수, isDeleting은 처리 상태이다.
class _SelectionDeleteBar extends StatelessWidget {
  final _SavedMedicationText text;
  final int selectedCount;
  final bool isDeleting;
  final Future<void> Function() onDeleteRequested;

  // 함수이름: _SelectionDeleteBar
  // 함수역할: 삭제 상태와 요청 동작을 받는다.
  // 매개변수: text, selectedCount, isDeleting, onDeleteRequested.
  // 반환값: 하단 삭제 위젯.
  const _SelectionDeleteBar({
    required this.text,
    required this.selectedCount,
    required this.isDeleting,
    required this.onDeleteRequested,
  });

  // 함수이름: build
  // 함수역할: 삭제 아이콘·문구를 큰 글씨에도 잘리지 않게 배치한다.
  // 매개변수: context는 화면 위치. 반환값: 전체 너비 삭제 버튼.
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.only(top: 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: MedBuddyColors.divider)),
    ),
    child: FilledButton.icon(
      key: const Key('saved-medication-delete-selected'),
      onPressed: selectedCount == 0 || isDeleting ? null : onDeleteRequested,
      style: FilledButton.styleFrom(
        backgroundColor: MedBuddyColors.danger,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      icon: const Icon(Icons.delete_outline),
      label: Text(
        isDeleting ? text.deleting : text.deleteSelected,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// 클래스명: _SavedMedicationDateCard
// 역할: 같은 날짜의 저장 약 목록과 그룹 삭제를 담당한다.
// 주요 책임:
// - 날짜·약 개수·묶음 삭제를 한 줄 머리글에 두고 그 아래에 같은 날짜의 저장 약 목록을 구성한다.
// 속성:
// - group (_SavedMedicationGroup): 같은 날짜의 저장 약품 묶음.
// - isSelectionMode (bool): 일반 조작 대신 삭제 선택 모드를 사용할지 여부.
// - enabled (bool): 삭제 중이 아니어서 조작할 수 있는지 여부.
// - selectedMedicationIds (Set<int>): 첨부 또는 삭제 대상으로 선택한 약품 ID 집합.
class _SavedMedicationDateCard extends StatelessWidget {
  final bool showRegisteredDate;
  final _SavedMedicationGroup group;
  final _SavedMedicationText text;
  final bool isSelectionMode;
  final bool enabled;
  final Set<int> selectedMedicationIds;
  final void Function(MedicationDetail medication, bool selected)
  onSelectionChanged;
  final void Function(MedicationDetail medication) onGuideRequested;
  final void Function(MedicationDetail medication) onImageRequested;
  final Future<void> Function() onDeleteRequested;

  // 함수이름: _SavedMedicationDateCard
  // 함수역할: 같은 날짜의 저장 약 목록과 그룹 삭제에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - group (_SavedMedicationGroup): 같은 날짜의 저장 약품 묶음.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - isSelectionMode (bool): 일반 조작 대신 삭제 선택 모드를 사용할지 여부.
  // - enabled (bool): 삭제 중이 아니어서 조작할 수 있는지 여부.
  // - selectedMedicationIds (Set<int>): 첨부 또는 삭제 대상으로 선택한 약품 ID 집합.
  // - onSelectionChanged (void Function(MedicationDetail medication, bool selected)): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // - onGuideRequested (void Function(MedicationDetail medication)): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onImageRequested (void Function(MedicationDetail medication)): 약품 사진을 확대해 표시할 콜백.
  // - onDeleteRequested (Future<void> Function()): 선택한 약품 또는 날짜 그룹 삭제를 요청할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationDateCard 인스턴스.
  const _SavedMedicationDateCard({
    required this.showRegisteredDate,
    required this.group,
    required this.text,
    required this.isSelectionMode,
    required this.enabled,
    required this.selectedMedicationIds,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
    required this.onDeleteRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 같은 날짜의 저장 약 목록과 그룹 삭제 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 같은 날짜의 저장 약 목록과 그룹 삭제에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, isSelectionMode ? 16 : 6, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          group.displayDate,
                          style: TextStyle(
                            color: MedBuddyColors.textStrong,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          text.medicationCount(group.medications.length),
                          style: TextStyle(
                            color: MedBuddyColors.textSubtle,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isSelectionMode)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: MedBuddyColors.danger,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: enabled ? onDeleteRequested : null,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                      ),
                      label: Text(text.delete),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: MedBuddyColors.divider),
          for (final medication in group.medications) ...[
            _SavedMedicationNameRow(
              showRegisteredDate: showRegisteredDate,
              medication: medication,
              text: text,
              isSelectionMode: isSelectionMode,
              enabled: enabled,
              isSelected:
                  medication.id != null &&
                  selectedMedicationIds.contains(medication.id),
              // 함수이름: build.onSelectionChanged callback
              // 함수역할: 같은 날짜의 저장 약 목록과 그룹 삭제에서 캡처된 작업 `onSelectionChanged(medication, selected)`을 실행한다.
              // 매개변수:
              // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onSelectionChanged: (selected) {
                onSelectionChanged(medication, selected);
              },
              // 함수이름: build.onGuideRequested callback
              // 함수역할: 같은 날짜의 저장 약 목록과 그룹 삭제에서 캡처된 작업 `onGuideRequested(medication)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onGuideRequested: () => onGuideRequested(medication),
              // 함수이름: build.onImageRequested callback
              // 함수역할: 같은 날짜의 저장 약 목록과 그룹 삭제에서 캡처된 작업 `onImageRequested(medication)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              onImageRequested: () => onImageRequested(medication),
            ),
            if (medication != group.medications.last)
              const Divider(height: 1, color: MedBuddyColors.divider),
          ],
        ],
      ),
    );
  }
}
