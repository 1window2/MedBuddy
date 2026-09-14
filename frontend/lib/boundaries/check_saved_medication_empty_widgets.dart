part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_empty_widgets.dart
// 역할: 빈 목록의 등록 진입, 전체 선택과 삭제 버튼 및 날짜 묶음을 제공한다.

// 클래스명: _SavedMedicationEmptyState
// 역할: 빈 복약함 안내와 보통 크기의 등록 버튼을 배치한다.
// 주요 책임: 큰 글씨에서도 등록 버튼까지 스크롤되게 한다.
// 속성: text는 문구, userSetting은 배율, onPrescriptionInputRequested는 등록 콜백이다.
class _SavedMedicationEmptyState extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback? onPrescriptionInputRequested;

  // 함수이름: _SavedMedicationEmptyState
  // 함수역할: 빈 상태의 표시와 동작을 받는다.
  // 매개변수: text, userSetting, onPrescriptionInputRequested. 반환값: 빈 상태 위젯.
  const _SavedMedicationEmptyState({
    required this.text,
    required this.userSetting,
    required this.onPrescriptionInputRequested,
  });

  // 함수이름: build
  // 함수역할: 안내와 전체 너비 등록 버튼을 구성한다.
  // 매개변수: context는 화면 위치. 반환값: 스크롤 가능한 빈 상태.
  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.medication_outlined,
            color: MedBuddyColors.textMuted,
            size: 42,
          ),
          const SizedBox(height: 14),
          Text(
            text.emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 16 * userSetting.contentTextScale,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('saved-medication-register'),
            onPressed: onPrescriptionInputRequested,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              backgroundColor: MedBuddyColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: TextStyle(
                fontSize: 16 * userSetting.contentTextScale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            icon: const Icon(Icons.add),
            label: Text(text.registerMedication, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
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
  final UserSetting userSetting;
  final int selectedCount;
  final bool isDeleting;
  final Future<void> Function() onDeleteRequested;

  // 함수이름: _SelectionDeleteBar
  // 함수역할: 삭제 상태와 요청 동작을 받는다.
  // 매개변수: text, userSetting, selectedCount, isDeleting, onDeleteRequested.
  // 반환값: 하단 삭제 위젯.
  const _SelectionDeleteBar({
    required this.text,
    required this.userSetting,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontSize: 16 * userSetting.contentTextScale,
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
// - 부모가 전달한 표시값과 동작을 반영해 같은 날짜의 저장 약 목록과 그룹 삭제 위젯을 구성한다.
// 속성:
// - group (_SavedMedicationGroup): 같은 날짜의 저장 약품 묶음.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - isSelectionMode (bool): 일반 조작 대신 삭제 선택 모드를 사용할지 여부.
// - enabled (bool): 삭제 중이 아니어서 조작할 수 있는지 여부.
// - selectedMedicationIds (Set<int>): 첨부 또는 삭제 대상으로 선택한 약품 ID 집합.
class _SavedMedicationDateCard extends StatelessWidget {
  final _SavedMedicationGroup group;
  final _SavedMedicationText text;
  final UserSetting userSetting;
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
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - isSelectionMode (bool): 일반 조작 대신 삭제 선택 모드를 사용할지 여부.
  // - enabled (bool): 삭제 중이 아니어서 조작할 수 있는지 여부.
  // - selectedMedicationIds (Set<int>): 첨부 또는 삭제 대상으로 선택한 약품 ID 집합.
  // - onSelectionChanged (void Function(MedicationDetail medication, bool selected)): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // - onGuideRequested (void Function(MedicationDetail medication)): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onImageRequested (void Function(MedicationDetail medication)): 약품 사진을 확대해 표시할 콜백.
  // - onDeleteRequested (Future<void> Function()): 선택한 약품 또는 날짜 그룹 삭제를 요청할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationDateCard 인스턴스.
  const _SavedMedicationDateCard({
    required this.group,
    required this.text,
    required this.userSetting,
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
    final scale = userSetting.contentTextScale;

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.displayDate,
                    style: TextStyle(
                      color: const Color(0xFF0A0A0A),
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MedBuddyColors.divider),
          for (final medication in group.medications) ...[
            _SavedMedicationNameRow(
              medication: medication,
              text: text,
              userSetting: userSetting,
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
          if (!isSelectionMode) ...[
            const Divider(height: 1, color: MedBuddyColors.divider),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: const Color(0xFFFF1F2D),
                textStyle: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              onPressed: enabled ? onDeleteRequested : null,
              child: Text(text.delete),
            ),
          ],
        ],
      ),
    );
  }
}
