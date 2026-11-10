// File Name: check_result_ui_boundary.dart
// Role: UI boundaries and helpers for prescription analysis results and individual or bulk schedule saving.

import 'package:flutter/material.dart';

import '../entities/analyzed_medication_entity.dart';
import '../entities/json_value_reader.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/expandable_medication_section.dart';
import '../widgets/pinned_analysis_summary.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/responsive_card_header.dart';
import 'prescription_change_radar_ui_boundary.dart';

// 파일명: check_result_ui_boundary.dart
// 역할: 공공데이터 분석이 끝난 처방전 결과 목록 화면을 구성한다.

// Class Name: CheckResultUI
// Role: Represents analyzed medications and individual or bulk save state.
// Responsibilities:
// - Displays the analyzed medication count and each schedule.
// - Shows per-item saving, bulk save, and disabled controls for saved items.
// - Reports save outcomes through a Snackbar.
// Attributes:
// - analyzedMedicationList (List<AnalyzedMedication>): Prescription analysis results containing medication details and schedules.
// - prescriptionChangeRadar (PrescriptionChangeRadar?): Comparison status and changes against a previous prescription.
// - isPrescriptionChangeLoading (bool): Whether the associated save, analysis, or medication update is in progress.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
class CheckResultUI extends StatelessWidget {
  final List<AnalyzedMedication> analyzedMedicationList;
  final PrescriptionChangeRadar? prescriptionChangeRadar;
  final bool isPrescriptionChangeLoading;
  final UserSetting userSetting;
  final String Function() statusMessageProvider;
  final int? savingMedicationIndex;
  final Set<int> completedMedicationSaveIndexes;
  final bool isAllMedicationSaving;
  final VoidCallback? onCloseRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onHomeRequested;
  final Future<bool> Function() onAllMedicationSaveRequested;
  final Future<bool> Function(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  )
  onMedicationSaveRequested;

  // Function Name: CheckResultUI
  // Description: Binds analyzed medications, comparison results and externally owned per-item/bulk save state to result review and navigation.
  // Parameters: key: identity; analyzedMedicationList: analyzed details/schedules; prescriptionChangeRadar/isPrescriptionChangeLoading: comparison result/progress; userSetting: display settings; statusMessageProvider: latest result text; savingMedicationIndex/completedMedicationSaveIndexes/isAllMedicationSaving: save progress; onCloseRequested/onTodayScheduleRequested/onSavedMedicationRequested/onHomeRequested: navigation; onAllMedicationSaveRequested/onMedicationSaveRequested: persistence callbacks returning success.
  // Returns: A configured CheckResultUI.
  const CheckResultUI({
    super.key,
    required this.analyzedMedicationList,
    this.prescriptionChangeRadar,
    this.isPrescriptionChangeLoading = false,
    required this.userSetting,
    required this.statusMessageProvider,
    required this.savingMedicationIndex,
    required this.completedMedicationSaveIndexes,
    required this.isAllMedicationSaving,
    required this.onCloseRequested,
    this.onTodayScheduleRequested,
    this.onSavedMedicationRequested,
    this.onHomeRequested,
    required this.onAllMedicationSaveRequested,
    required this.onMedicationSaveRequested,
  });

  // Function Name: build
  // Description: Renders analyzed medications and individual or bulk save state from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for analyzed medications and individual or bulk save state.
  @override
  Widget build(BuildContext context) {
    final text = _ResultText(userSetting.language);
    final hasRadarSlot =
        prescriptionChangeRadar != null || isPrescriptionChangeLoading;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .3,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    child: _ResultHeader(
                      title: text.title,
                      subtitle: text.subtitle,
                      backTooltip: text.back,
                      onCloseRequested: onCloseRequested,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: PinnedAnalysisSummary(
                        summary: _AnalysisSummary(
                          count: analyzedMedicationList.length,
                          text: text,
                        ),
                        child: ListView.builder(
                          key: const Key('analysis-result-list'),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          itemCount:
                              analyzedMedicationList.length +
                              (hasRadarSlot ? 1 : 0),
                          // 변경 비교 칸이 사라져 위치가 당겨져도 펼친 약 카드의 상태를 같은 약에 유지한다.
                          findChildIndexCallback: (key) => key is ValueKey<int>
                              ? key.value + (hasRadarSlot ? 1 : 0)
                              : null,
                          // Function Name: build.itemBuilder callback
                          // Description: Composes analyzed medications and individual or bulk save state with the current parent constraints for the active layout.
                          // Parameters:
                          // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
                          // - index (int): Zero-based position of the target medication, photo, or row.
                          // Returns: Widget subtree for the described layout or fallback.
                          itemBuilder: (context, index) {
                            if (hasRadarSlot && index == 0) {
                              if (isPrescriptionChangeLoading) {
                                return PrescriptionChangeRadarLoadingUI(
                                  userSetting: userSetting,
                                );
                              }
                              return PrescriptionChangeRadarUI(
                                radar: prescriptionChangeRadar!,
                                userSetting: userSetting,
                              );
                            }

                            final medicationIndex =
                                index - (hasRadarSlot ? 1 : 0);
                            final analyzedMedication =
                                analyzedMedicationList[medicationIndex];
                            return _MedicationResultCard(
                              key: ValueKey(medicationIndex),
                              medicationIndex: medicationIndex,
                              analyzedMedication: analyzedMedication,
                              text: text,
                              isMedicationSaving:
                                  savingMedicationIndex == medicationIndex,
                              isMedicationSaved: completedMedicationSaveIndexes
                                  .contains(medicationIndex),
                              isAllMedicationSaving:
                                  isAllMedicationSaving ||
                                  savingMedicationIndex != null,
                              // 함수이름: build.onMedicationSaveRequested callback
                              // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
                              // 매개변수:
                              // - 없음.
                              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                              onMedicationSaveRequested: () async {
                                final success = await onMedicationSaveRequested(
                                  analyzedMedication,
                                  medicationIndex,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                // 이 클로저의 완료 집합은 저장 전 사본이므로 방금 저장한 약을 더해 판단한다.
                                final allSaved =
                                    {
                                      ...completedMedicationSaveIndexes,
                                      medicationIndex,
                                    }.length >=
                                    analyzedMedicationList.length;
                                if (success && allSaved) {
                                  await _showSaveCompletedSheet(context, text);
                                  return;
                                }
                                _showSaveResultMessage(context, success);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    _BulkSaveButton(
                      text: text,
                      isSaving:
                          isAllMedicationSaving ||
                          savingMedicationIndex != null,
                      isCompleted:
                          completedMedicationSaveIndexes.length >=
                          analyzedMedicationList.length,
                      // 함수이름: build.onPressed callback
                      // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      onPressed: () async {
                        final success = await onAllMedicationSaveRequested();
                        if (!context.mounted) {
                          return;
                        }
                        if (success) {
                          await _showSaveCompletedSheet(context, text);
                          return;
                        }
                        _showSaveResultMessage(context, false);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Function Name: _showSaveResultMessage
  // Description: Shows the latest save result for two seconds with success or failure coloring.
  // Parameters: context (BuildContext): snackbar host; success (bool): save outcome.
  // Returns: None.
  void _showSaveResultMessage(BuildContext context, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(statusMessageProvider()),
        backgroundColor: success
            ? MedBuddyColors.primary
            : MedBuddyColors.danger,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 함수이름: _showSaveCompletedSheet
  // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showSaveCompletedSheet(BuildContext context, _ResultText text) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // 함수이름: _showSaveCompletedSheet.builder callback
      // 함수역할: 분석 약 목록과 개별·전체 저장 상태에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (sheetContext) => _SaveCompletedSheet(
        text: text,
        onTodayScheduleRequested: onTodayScheduleRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onTodayScheduleRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onTodayScheduleRequested!.call();
              },
        onSavedMedicationRequested: onSavedMedicationRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onSavedMedicationRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onSavedMedicationRequested!.call();
              },
        onHomeRequested: onHomeRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onHomeRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onHomeRequested!.call();
              },
      ),
    );
  }
}

// 클래스명: _SaveCompletedSheet
// 역할: 저장 완료 후 오늘 일정·복약함·홈 이동을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 완료 후 오늘 일정·복약함·홈 이동 위젯을 구성한다.
// 속성:
// - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
// - onSavedMedicationRequested (VoidCallback?): 저장 복약함 화면을 여는 콜백.
// - onHomeRequested (VoidCallback?): 홈 화면으로 이동할 콜백.
class _SaveCompletedSheet extends StatelessWidget {
  final _ResultText text;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onHomeRequested;

  // 함수이름: _SaveCompletedSheet
  // 함수역할: 저장 완료 후 오늘 일정·복약함·홈 이동에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
  // - onSavedMedicationRequested (VoidCallback?): 저장 복약함 화면을 여는 콜백.
  // - onHomeRequested (VoidCallback?): 홈 화면으로 이동할 콜백.
  // 반환값: 입력 설정이 반영된 _SaveCompletedSheet 인스턴스.
  const _SaveCompletedSheet({
    required this.text,
    required this.onTodayScheduleRequested,
    required this.onSavedMedicationRequested,
    required this.onHomeRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 완료 후 오늘 일정·복약함·홈 이동 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 완료 후 오늘 일정·복약함·홈 이동에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        26,
        24,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: MedBuddyColors.primary,
            size: 58,
          ),
          const SizedBox(height: 12),
          Text(
            text.saveCompletedTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text.saveCompletedDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          if (onTodayScheduleRequested != null)
            FilledButton.icon(
              onPressed: onTodayScheduleRequested,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(text.openTodaySchedule),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: MedBuddyColors.primary,
              ),
            ),
          if (onSavedMedicationRequested != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onSavedMedicationRequested,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(text.openSavedMedication),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
              ),
            ),
          ],
          if (onHomeRequested != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onHomeRequested,
              child: Text(text.returnHome),
            ),
          ],
        ],
      ),
    );
  }
}

// Class Name: _ResultHeader
// Role: Analysis-result header and close action.
// Responsibilities: Labels the result screen and exposes the supplied close callback.
// Attributes: title: heading; backTooltip: close-action description; onCloseRequested: optional navigation callback.
class _ResultHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String backTooltip;
  final VoidCallback? onCloseRequested;

  // 함수이름: _ResultHeader
  // 함수역할: 처방 분석 결과 제목과 닫기 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - backTooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - onCloseRequested (VoidCallback?): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // - subtitle (String): 결과 제목 아래에 표시할 분석 약품·복용 일정 확인 안내.
  // 반환값: 입력 설정이 반영된 _ResultHeader 인스턴스.
  const _ResultHeader({
    required this.title,
    required this.subtitle,
    required this.backTooltip,
    required this.onCloseRequested,
  });

  // Function Name: build
  // Description: Renders the result title and accessible close action.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return MedBuddyPageHeader(
      title: title,
      subtitle: subtitle,
      backTooltip: backTooltip,
      leading: IconButton(
        tooltip: backTooltip,
        onPressed: onCloseRequested,
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }
}

// Class Name: _AnalysisSummary
// Role: Represents a summary of analyzed medications ready to save.
// Responsibilities:
// - Composes a summary of analyzed medications ready to save using the display values and actions supplied by its parent.
// Attributes:
// - count (int): Item count or ordinal number used in wording or a list.
class _AnalysisSummary extends StatelessWidget {
  final int count;
  final _ResultText text;

  // 함수이름: _AnalysisSummary
  // 함수역할: 저장 가능한 분석 약품 수 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _AnalysisSummary 인스턴스.
  const _AnalysisSummary({required this.count, required this.text});

  // Function Name: build
  // Description: Renders a summary of analyzed medications ready to save from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a summary of analyzed medications ready to save.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.successBorder),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: MedBuddyColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.complete,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  text.summary(count),
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _BulkSaveButton
// 역할: 전체 분석 약 저장 버튼.
// 주요 책임: 저장 중이거나 완료한 상태에서 중복 저장을 막고 진행·완료 상태를 보여 준다.
// 속성: text: 표시 문구; isSaving/isCompleted: 저장 상태; onPressed: 전체 저장 콜백.
class _BulkSaveButton extends StatelessWidget {
  final _ResultText text;
  final bool isSaving;
  final bool isCompleted;
  final Future<void> Function() onPressed;

  // 함수이름: _BulkSaveButton
  // 함수역할: 중복 요청을 막는 전체 저장·완료 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - isSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - isCompleted (bool): 복약 또는 저장 작업의 완료 상태.
  // - onPressed (Future<void> Function()): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _BulkSaveButton 인스턴스.
  const _BulkSaveButton({
    required this.text,
    required this.isSaving,
    required this.isCompleted,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 전체 저장의 진행·완료 표시를 구성하고 중복 실행할 수 없는 상태에서는 버튼을 비활성화한다.
  // 매개변수: context (BuildContext): 테마·접근성 문맥.
  // 반환값: 상태가 반영된 전체 저장 버튼.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('prescription-save-all'),
          // 함수이름: build.onPressed callback
          // 함수역할: 중복 요청을 막는 전체 저장·완료 상태에서 캡처된 작업 `onPressed()`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onPressed: isSaving || isCompleted ? null : () async => onPressed(),
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isCompleted ? Icons.check_circle_outline : Icons.done_all,
                  size: 22,
                ),
          label: Text(
            isCompleted
                ? text.allSaved
                : isSaving
                ? text.savingAll
                : text.saveAll,
          ),
          style: FilledButton.styleFrom(
            disabledBackgroundColor: MedBuddyColors.textLight,
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(66),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// Class Name: _MedicationResultCard
// Role: One analyzed medication and its save action.
// Responsibilities: Displays dosage, frequency and duration while respecting item and bulk-save progress.
// Attributes: analyzedMedication: analysis data; text: display labels; isMedicationSaving/isMedicationSaved/isAllMedicationSaving: save state; onMedicationSaveRequested: item save.
class _MedicationResultCard extends StatelessWidget {
  final int medicationIndex;
  final AnalyzedMedication analyzedMedication;
  final _ResultText text;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onMedicationSaveRequested;

  // Function Name: _MedicationResultCard
  // Description: Bind an analyzed medication, its display labels and save state to an expandable result card.
  // Parameters:
  // - key (Key?): Preserve this card's element identity when the list changes.
  // - medicationIndex (int): Zero-based result position used for the displayed one-based number and child keys.
  // - analyzedMedication (AnalyzedMedication): Medication details and schedule to review.
  // - text (_ResultText): Localized labels.
  // - isMedicationSaving, isMedicationSaved, isAllMedicationSaving (bool): Per-item progress, saved state and batch-save progress that govern the save button.
  // - onMedicationSaveRequested (Future<void> Function()): Save this medication when the button is enabled.
  // Returns: A configured _MedicationResultCard; construction does not start saving.
  const _MedicationResultCard({
    super.key,
    required this.medicationIndex,
    required this.analyzedMedication,
    required this.text,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onMedicationSaveRequested,
  });

  // Function Name: build
  // Description: Displays medication details and dose information with an item-save action governed by current item/bulk save state.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    final schedule = analyzedMedication.schedule;
    final slots = schedule.slotSummaryLabelForLanguage(text.language);

    return Container(
      key: Key('result-medication-card-$medicationIndex'),
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.small,
        border: Border.all(color: MedBuddyColors.outline),
      ),
      child: ExpandableMedicationSection(
        initiallyExpanded: false,
        isEnglish: text.isEnglish,
        toggleKey: Key('result-medication-toggle-$medicationIndex'),
        headerBuilder: (toggle) {
          final name = Text(
            analyzedMedication.displayNameForLanguage(text.language),
            key: Key('result-medication-name-$medicationIndex'),
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MedicationSaveIconButton(
                key: Key('result-medication-save-$medicationIndex'),
                text: text,
                isMedicationSaving: isMedicationSaving,
                isMedicationSaved: isMedicationSaved,
                isAllMedicationSaving: isAllMedicationSaving,
                onPressed: onMedicationSaveRequested,
              ),
              toggle,
            ],
          );
          final numberedName = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Text(
                  '${medicationIndex + 1}',
                  key: Key('result-medication-number-$medicationIndex'),
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(child: name),
            ],
          );
          return Container(
            key: Key('result-medication-header-$medicationIndex'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            color: MedBuddyColors.successSurface,
            child: ResponsiveCardHeader(
              title: numberedName,
              actions: actions,
              spacing: 10,
            ),
          );
        },
        details: Column(
          children: [
            const Divider(height: 1),
            Table(
              key: Key('result-medication-summary-$medicationIndex'),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                verticalInside: BorderSide(color: MedBuddyColors.outline),
              ),
              children: [
                TableRow(
                  children: [
                    _DoseInfoCell(
                      label: text.dose,
                      value: _displayValue(
                        schedule.dosageLabelForLanguage(text.language),
                      ),
                    ),
                    _DoseInfoCell(
                      label: text.duration,
                      value: _displayValue(
                        schedule.durationLabelForLanguage(text.language),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 1),
            Table(
              key: Key('result-medication-schedule-$medicationIndex'),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                verticalInside: BorderSide(color: MedBuddyColors.outline),
              ),
              children: [
                TableRow(
                  children: [
                    _DoseInfoCell(
                      label: text.medicationStartDate,
                      value:
                          formatJsonDate(schedule.prescriptionDate) ??
                          text.noInformation,
                    ),
                    _DoseInfoCell(
                      label: text.scheduleSlots,
                      value: _displayValue(slots),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Function Name: _displayValue
  // Description: Replaces an empty medication field with the localized missing-information label.
  // Parameters: value (String): field value.
  // Returns: The trimmed value or missing-information text.
  String _displayValue(String value) {
    return value.trim().isEmpty ? text.noInformation : value.trim();
  }
}

// 클래스명: _MedicationSaveIconButton
// 역할: 개별 약 저장 아이콘.
// 주요 책임: 개별·전체 저장 중 또는 저장 완료 시 중복 요청을 막고 완료 여부를 표시한다.
// 속성: text: 표시 문구; isMedicationSaving/isMedicationSaved/isAllMedicationSaving: 저장 상태; onPressed: 개별 저장 콜백.
class _MedicationSaveIconButton extends StatelessWidget {
  final _ResultText text;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onPressed;

  // 함수이름: _MedicationSaveIconButton
  // 함수역할: 개별 저장 버튼에 표시 문구와 저장 상태 및 저장 동작을 전달한다.
  // 매개변수: key (Key?): 목록 안의 저장 버튼 식별 키; text (_ResultText): 문구; isMedicationSaving/isMedicationSaved/isAllMedicationSaving (bool): 진행·완료 상태; onPressed (Future<void> Function()): 저장 동작.
  // 반환값: 새 _MedicationSaveIconButton.
  const _MedicationSaveIconButton({
    super.key,
    required this.text,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onPressed,
  });

  // Function Name: build
  // Description: Renders the medication-save icon disabled during saving or after completion from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the medication-save icon disabled during saving or after completion.
  @override
  Widget build(BuildContext context) {
    final isDisabled =
        isMedicationSaving || isMedicationSaved || isAllMedicationSaving;

    return Tooltip(
      message: isMedicationSaved ? text.saved : text.saveSchedule,
      child: IconButton(
        // 어르신이 누르기 쉽게 최소 48dp 터치 영역을 둔다.
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        style: IconButton.styleFrom(
          foregroundColor: MedBuddyColors.primary,
          disabledForegroundColor: MedBuddyColors.textLight,
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
        ),
        // Function Name: build.onPressed callback
        // Description: Connects the medication-save icon disabled during saving or after completion to the captured operation `onPressed()`.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onPressed: isDisabled ? null : () async => onPressed(),
        icon: isMedicationSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: MedBuddyColors.primary,
                ),
              )
            : Icon(
                isMedicationSaved
                    ? Icons.check_circle_outline
                    : Icons.save_outlined,
                size: 22,
              ),
      ),
    );
  }
}

// Class Name: _DoseInfoCell
// Role: A labeled dosage-table value.
// Responsibilities: Centers each label/value while allowing the cell height to follow content and text scale.
// Attributes: label (String): dose field name; value (String): displayed dose value.
class _DoseInfoCell extends StatelessWidget {
  final String label;
  final String value;

  // 함수이름: _DoseInfoCell
  // 함수역할: 복약 정보 셀의 라벨과 값을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 입력 설정이 반영된 _DoseInfoCell 인스턴스.
  const _DoseInfoCell({required this.label, required this.value});

  // Function Name: build
  // Description: Centers one dose, frequency or duration label above its value.
  // Parameters: context (BuildContext): theme, accessibility and navigation scope.
  // Returns: The described widget tree.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _ResultText
// 역할: 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _ResultText {
  final String language;

  // 함수이름: _ResultText
  // 함수역할: 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _ResultText 인스턴스.
  const _ResultText(this.language);

  // Function Name: isEnglish
  // Description: Uses the shared language-code rule for result messages.
  // Parameters: None.
  // Returns: True when the language selects English.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 분석 결과" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Prescription Analysis Result' : '처방전 분석 결과';
  // 함수이름: subtitle
  // 함수역할: 분석한 약과 복용 일정을 확인하고 저장하도록 안내한다.
  // 매개변수: 없음.
  // 반환값: 현재 언어의 결과 화면 부제목.
  String get subtitle => isEnglish
      ? 'Review and save your medication schedules.'
      : '분석한 약과 복용 일정을 확인하고 저장합니다.';
  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: complete
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get complete => isEnglish ? 'Analysis Complete' : '분석 완료';
  // 함수이름: summary
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count개의 복약 일정을 저장할 수 있습니다" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String summary(int count) => isEnglish
      ? '$count medication item${count == 1 ? '' : 's'} ready to save'
      : '$count개의 복약 일정을 저장할 수 있습니다';
  // 함수이름: dose
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 투약량" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dose => isEnglish ? 'Dose' : '1회 투약량';
  // 함수이름: medicationStartDate
  // 함수역할: 약 복용 시작 날짜 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  String get medicationStartDate => isEnglish ? 'Start date' : '복용 시작일';
  // 함수이름: scheduleSlots
  // 함수역할: 복약 시간대 라벨를 현재 언어로 제공한다.
  // 매개변수: 없음.
  // 반환값: 한국어 또는 영어 표시 문구.
  String get scheduleSlots => isEnglish ? 'Medication time slots' : '실제 복약 시간대';
  // 함수이름: duration
  // 함수역할: 현재 언어와 입력값에 맞춰 "총 투약일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get duration => isEnglish ? 'Duration' : '총 투약일';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  // 함수이름: saveAll
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveAll => isEnglish ? 'Save All' : '전체 저장하기';
  // 함수이름: savingAll
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get savingAll => isEnglish ? 'Saving all...' : '전체 저장 중...';
  // 함수이름: allSaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get allSaved => isEnglish ? 'All Saved' : '전체 저장 완료';
  // 함수이름: saveSchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 일정 저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveSchedule =>
      isEnglish ? 'Save Medication Schedule' : '복약 일정 저장하기';
  // 함수이름: saved
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saved => isEnglish ? 'Saved' : '저장 완료';
  // 함수이름: saveCompletedTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 일정 저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveCompletedTitle =>
      isEnglish ? 'Medication schedule saved' : '복약 일정 저장 완료';
  // Function Name: saveCompletedDescription
  // Description: Explains where saved medications can be opened after saving.
  // Parameters: None.
  // Returns: Localized guidance to today's schedule or the medication cabinet.
  String get saveCompletedDescription => isEnglish
      ? 'Review the saved schedule now or return home.'
      : '저장한 약을 오늘 일정이나 복약함에서 바로 확인할 수 있습니다.';
  // 함수이름: openTodaySchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘 일정 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openTodaySchedule =>
      isEnglish ? 'View today\'s schedule' : '오늘 일정 확인';
  // 함수이름: openSavedMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약함 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openSavedMedication => isEnglish ? 'View Medications' : '복약함 보기';
  // 함수이름: returnHome
  // 함수역할: 현재 언어와 입력값에 맞춰 "홈으로 돌아가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get returnHome => isEnglish ? 'Return home' : '홈으로 돌아가기';
}
