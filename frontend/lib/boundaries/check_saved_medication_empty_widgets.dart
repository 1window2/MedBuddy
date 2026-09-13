part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_empty_widgets.dart
// 역할: 저장 목록의 빈 상태, 선택 삭제 바 및 날짜별 약품 그룹을 제공한다.

// 클래스명: _SavedMedicationEmptyState
// 역할: 비어 있는 복약함 안내와 처방전 입력 진입을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 비어 있는 복약함 안내와 처방전 입력 진입 위젯을 구성한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onPrescriptionInputRequested (VoidCallback): 약 정보 입력 방식 선택을 여는 콜백.
class _SavedMedicationEmptyState extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback onPrescriptionInputRequested;

  // 함수이름: _SavedMedicationEmptyState
  // 함수역할: 비어 있는 복약함 안내와 처방전 입력 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onPrescriptionInputRequested (VoidCallback): 약 정보 입력 방식 선택을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationEmptyState 인스턴스.
  const _SavedMedicationEmptyState({
    required this.text,
    required this.userSetting,
    required this.onPrescriptionInputRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 비어 있는 복약함 안내와 처방전 입력 진입 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 비어 있는 복약함 안내와 처방전 입력 진입에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 34, 22, 32),
                    decoration: BoxDecoration(
                      color: MedBuddyColors.surfaceSubtle,
                      borderRadius: MedBuddyRadii.card,
                      border: Border.all(
                        color: MedBuddyColors.outline,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.medication_outlined,
                          color: MedBuddyColors.textLight,
                          size: 42,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          text.emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MedBuddyColors.textMuted,
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 178),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: MedBuddyColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: MedBuddyRadii.card,
                    ),
                    textStyle: TextStyle(
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  onPressed: onPrescriptionInputRequested,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_camera_outlined, size: 40),
                      const SizedBox(height: 18),
                      Text(text.scanPrescription, textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      Text(
                        text.scanSubtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MedBuddyColors.mint,
                          fontSize: 14 * scale,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 클래스명: _SelectionDeleteBar
// 역할: 선택한 약 개수와 선택 삭제 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 선택한 약 개수와 선택 삭제 명령 위젯을 구성한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - selectedCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
// - onDeleteRequested (Future<void> Function()): 선택한 약품 또는 날짜 그룹 삭제를 요청할 콜백.
class _SelectionDeleteBar extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final int selectedCount;
  final Future<void> Function() onDeleteRequested;

  // 함수이름: _SelectionDeleteBar
  // 함수역할: 선택한 약 개수와 선택 삭제 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - selectedCount (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - onDeleteRequested (Future<void> Function()): 선택한 약품 또는 날짜 그룹 삭제를 요청할 콜백.
  // 반환값: 입력 설정이 반영된 _SelectionDeleteBar 인스턴스.
  const _SelectionDeleteBar({
    required this.text,
    required this.userSetting,
    required this.selectedCount,
    required this.onDeleteRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 선택한 약 개수와 선택 삭제 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 선택한 약 개수와 선택 삭제 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.selectedCount(selectedCount),
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          FilledButton(
            onPressed: selectedCount == 0
                ? null
                // 함수이름: build.onPressed callback
                // 함수역할: 선택한 약 개수와 선택 삭제 명령에서 캡처된 작업 `onDeleteRequested()`을 실행한다.
                // 매개변수:
                // - 없음.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                : () async => onDeleteRequested(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1F2D),
              disabledBackgroundColor: MedBuddyColors.outline,
              foregroundColor: Colors.white,
              minimumSize: const Size(118, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: Text(text.deleteSelected),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _SavedMedicationDateCard
// 역할: 같은 날짜의 저장 약 목록과 그룹 삭제를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 같은 날짜의 저장 약 목록과 그룹 삭제 위젯을 구성한다.
// 속성:
// - group (_SavedMedicationGroup): 같은 날짜의 저장 약품 묶음.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - isSelectionMode (bool): 일반 조작 대신 첨부·삭제 선택 모드를 사용할지 여부.
// - selectedMedicationIds (Set<int>): 첨부 또는 삭제 대상으로 선택한 약품 ID 집합.
class _SavedMedicationDateCard extends StatelessWidget {
  final _SavedMedicationGroup group;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
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
  // - isSelectionMode (bool): 일반 조작 대신 첨부·삭제 선택 모드를 사용할지 여부.
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
              onPressed: onDeleteRequested,
              child: Text(text.delete),
            ),
          ],
        ],
      ),
    );
  }
}

// 클래스명: _SavedMedicationSortControl
// 역할: 저장 목록의 등록일자순과 복용날짜순 정렬 기준을 전환한다.
// 주요 책임:
// - 현재 선택된 정렬 기준을 초록색으로 구분해 표시한다.
// - 사용자가 선택한 기준을 상위 화면 상태로 전달한다.
