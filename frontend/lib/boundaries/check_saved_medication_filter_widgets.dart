part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_filter_widgets.dart
// 역할: 저장 약품의 복용 상태 필터와 필터별 빈 결과를 제공한다.

// 클래스명: _SavedMedicationFilterControl
// 역할: 복용 중·종료·전체 약품 선택 필터를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복용 중·종료·전체 약품 선택 필터 위젯을 구성한다.
// 속성:
// - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
// - onChanged (ValueChanged<_SavedMedicationFilterMode>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
class _SavedMedicationFilterControl extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;
  final ValueChanged<_SavedMedicationFilterMode> onChanged;

  // 함수이름: _SavedMedicationFilterControl
  // 함수역할: 복용 중·종료·전체 약품 선택 필터에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - onChanged (ValueChanged<_SavedMedicationFilterMode>): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationFilterControl 인스턴스.
  const _SavedMedicationFilterControl({
    required this.filterMode,
    required this.text,
    required this.onChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복용 중·종료·전체 약품 선택 필터 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복용 중·종료·전체 약품 선택 필터에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Semantics(
        label: text.isEnglish ? 'Medication status filter' : '복약 상태 필터',
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: MedBuddyColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              _buildOption(
                mode: _SavedMedicationFilterMode.active,
                label: text.activeMedication,
              ),
              _buildOption(
                mode: _SavedMedicationFilterMode.ended,
                label: text.endedMedication,
              ),
              _buildOption(
                mode: _SavedMedicationFilterMode.all,
                label: text.allMedication,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildOption
  // 함수역할: 선택한 복용 상태를 강조하고 해당 필터로 변경하는 버튼을 구성한다.
  // 매개변수:
  // - mode (_SavedMedicationFilterMode): 선택한 필터·알림 모드 또는 옵션 종류.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // 반환값: 복용 중·종료·전체 약품 선택 필터에 쓰는 위젯 트리.
  Widget _buildOption({
    required _SavedMedicationFilterMode mode,
    required String label,
  }) {
    final selected = mode == filterMode;
    return Expanded(
      child: Material(
        color: selected ? MedBuddyColors.primary : Colors.white,
        child: InkWell(
          // 함수이름: _buildOption.onTap callback
          // 함수역할: 복용 중·종료·전체 약품 선택 필터에서 캡처된 작업 `onChanged(mode)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onTap: () => onChanged(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : MedBuddyColors.textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _SavedMedicationFilteredEmptyState
// 역할: 선택한 복용 상태에 해당하는 약이 없다는 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 선택한 복용 상태에 해당하는 약이 없다는 안내 위젯을 구성한다.
// 속성:
// - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
class _SavedMedicationFilteredEmptyState extends StatelessWidget {
  final _SavedMedicationFilterMode filterMode;
  final _SavedMedicationText text;

  // 함수이름: _SavedMedicationFilteredEmptyState
  // 함수역할: 선택한 복용 상태에 해당하는 약이 없다는 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _SavedMedicationFilteredEmptyState 인스턴스.
  const _SavedMedicationFilteredEmptyState({
    required this.filterMode,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 선택한 복용 상태에 해당하는 약이 없다는 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 선택한 복용 상태에 해당하는 약이 없다는 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.medication_outlined,
              color: MedBuddyColors.textLight,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              text.filteredEmptyMessage(filterMode),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
